import Testing
import Foundation
@testable import MyMacCleaner

/// Exercises the state machine behind the Clean screen — scan, cancel,
/// review, clean, empty result, and an error (skipped-location) state — at
/// the view-model level. These are not full XCUITest UI tests, but they drive
/// exactly the same `CleanCoordinator` the view binds to, against fixture
/// directories instead of the real filesystem.
@Suite("CleanCoordinator")
@MainActor
struct CleanCoordinatorTests {
    private func waitForCompletion(_ coordinator: CleanCoordinator, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while coordinator.isScanning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Scan populates items and completes")
    func scanPopulatesItems() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("SomeApp/cache.bin"))

        let coordinator = CleanCoordinator()
        coordinator.startScan(roots: [.init(category: .applicationCache, url: root)])
        await waitForCompletion(coordinator)

        #expect(coordinator.scanState == .completed)
        #expect(coordinator.items.count == 1)
        #expect(coordinator.items.first?.safety == .safe)
    }

    @Test("Empty result: a clean location reports zero items, not an error")
    func emptyResultIsHandled() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }

        let coordinator = CleanCoordinator()
        coordinator.startScan(roots: [.init(category: .logs, url: root)])
        await waitForCompletion(coordinator)

        #expect(coordinator.scanState == .completed)
        #expect(coordinator.items.isEmpty)
    }

    @Test("Error state: a missing location surfaces as a skipped root, not a crash")
    func missingRootSurfacesAsSkipped() async {
        let missing = TestFixtures.makeTemporaryRoot().appendingPathComponent("nope")
        let coordinator = CleanCoordinator()
        coordinator.startScan(roots: [.init(category: .logs, url: missing)])
        await waitForCompletion(coordinator)

        #expect(coordinator.scanState == .completed)
        #expect(coordinator.skippedRoots.count == 1)
        #expect(coordinator.skippedRoots.first?.reason == .notFound)
    }

    @Test("Cancel: cancelling a scan marks it cancelled")
    func cancellingMarksCancelled() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        for index in 0..<10 {
            TestFixtures.writeFile(at: root.appendingPathComponent("item\(index)/payload.bin"))
        }

        let coordinator = CleanCoordinator()
        coordinator.startScan(roots: [.init(category: .applicationCache, url: root)])
        coordinator.cancelScan()

        #expect(coordinator.scanState == .cancelled)
    }

    @Test("Review: REVIEW-classified items are found but not selected by default")
    func reviewItemsAreNotAutoSelected() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("2026-01-01/App 1.xcarchive/Info.plist"))

        let coordinator = CleanCoordinator()
        coordinator.startScan(roots: [.init(category: .developerData, url: root, groupDepth: 2)])
        await waitForCompletion(coordinator)

        guard let item = coordinator.items.first else {
            Issue.record("expected an archive item to be found")
            return
        }
        #expect(item.safety == .review)
        #expect(!coordinator.isSelected(item))

        // The user can still opt in explicitly.
        coordinator.toggleSelection(item)
        #expect(coordinator.isSelected(item))
    }

    @Test("Clean: cleaning selected items moves them to the Trash and drops them from the list")
    func cleaningRemovesSelectedItems() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("SomeApp/cache.bin"))

        let coordinator = CleanCoordinator()
        coordinator.startScan(roots: [.init(category: .applicationCache, url: root)])
        await waitForCompletion(coordinator)
        #expect(coordinator.items.count == 1)

        let summary = await coordinator.performClean()

        #expect(summary.succeededCount == 1)
        #expect(summary.failedCount == 0)
        #expect(coordinator.items.isEmpty)
    }
}
