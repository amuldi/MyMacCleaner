import Testing
import Foundation
@testable import MyMacCleaner

@Suite("ScannerEngine")
struct ScannerEngineTests {
    private func collectEvents(_ stream: AsyncStream<ScanEvent>) async -> [ScanEvent] {
        var events: [ScanEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func items(in events: [ScanEvent]) -> [ScannedItem] {
        events.compactMap {
            if case .item(let item) = $0 { return item }
            return nil
        }
    }

    private func skipReasons(in events: [ScanEvent]) -> [SkipReason] {
        events.compactMap {
            if case .rootSkipped(_, let reason) = $0 { return reason }
            return nil
        }
    }

    @Test("Detects application cache folders and classifies them SAFE")
    func detectsCache() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let cachesDir = root.appendingPathComponent("Library/Caches")
        TestFixtures.writeFile(at: cachesDir.appendingPathComponent("SomeApp/data.bin"))

        let engine = ScannerEngine()
        let events = await collectEvents(engine.scan(roots: [.init(category: .applicationCache, url: cachesDir)]))
        let found = items(in: events)

        #expect(found.count == 1)
        #expect(found.first?.category == .applicationCache)
        #expect(found.first?.safety == .safe)
        #expect((found.first?.size ?? 0) > 0)
    }

    @Test("Detects log files and classifies them SAFE")
    func detectsLogs() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let logsDir = root.appendingPathComponent("Library/Logs")
        TestFixtures.writeFile(at: logsDir.appendingPathComponent("install.log"))

        let events = await collectEvents(ScannerEngine().scan(roots: [.init(category: .logs, url: logsDir)]))
        let found = items(in: events)

        #expect(found.count == 1)
        #expect(found.first?.safety == .safe)
    }

    @Test("Detects temporary files and classifies them SAFE")
    func detectsTemporaryFiles() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("scratch.tmp"))

        let events = await collectEvents(ScannerEngine().scan(roots: [.init(category: .temporaryFiles, url: root)]))
        let found = items(in: events)

        #expect(found.count == 1)
        #expect(found.first?.category == .temporaryFiles)
    }

    @Test("A missing location is reported as skipped, not a crash")
    func missingRootIsSkipped() async {
        let missing = TestFixtures.makeTemporaryRoot().appendingPathComponent("does-not-exist")
        let events = await collectEvents(ScannerEngine().scan(roots: [.init(category: .logs, url: missing)]))
        #expect(skipReasons(in: events) == [.notFound])
    }

    @Test("A location without read permission is reported as skipped, not a crash")
    func permissionDeniedRootIsSkipped() async {
        let root = TestFixtures.makeTemporaryRoot()
        let locked = root.appendingPathComponent("locked")
        try! FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        TestFixtures.writeFile(at: locked.appendingPathComponent("secret.txt"))
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            TestFixtures.removeIfExists(root)
        }

        let events = await collectEvents(ScannerEngine().scan(roots: [.init(category: .logs, url: locked)]))
        #expect(skipReasons(in: events) == [.permissionDenied])
    }

    @Test("An empty location finishes with zero items instead of an error")
    func emptyLocationFinishesCleanly() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }

        let events = await collectEvents(ScannerEngine().scan(roots: [.init(category: .logs, url: root)]))
        #expect(items(in: events).isEmpty)
        #expect(events.contains { if case .finished(let files, let bytes) = $0 { return files == 0 && bytes == 0 } else { return false } })
    }

    @Test("Cancelling mid-scan stops the stream without hanging or crashing")
    func cancellationStopsCleanly() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        for index in 0..<25 {
            TestFixtures.writeFile(at: root.appendingPathComponent("item\(index)/payload.bin"))
        }

        let engine = ScannerEngine()
        let consumer = Task {
            let stream = await engine.scan(roots: [.init(category: .applicationCache, url: root)])
            for await _ in stream {
                if Task.isCancelled { break }
            }
        }

        try? await Task.sleep(for: .milliseconds(5))
        consumer.cancel()
        await consumer.value

        #expect(consumer.isCancelled)
    }

    @Test("Archives are grouped two levels deep, matching Xcode's date-bucketed layout")
    func archivesGroupTwoLevelsDeep() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("2026-01-01/App 1.xcarchive/Info.plist"))
        TestFixtures.writeFile(at: root.appendingPathComponent("2026-01-02/App 2.xcarchive/Info.plist"))

        let events = await collectEvents(ScannerEngine().scan(roots: [.init(category: .developerData, url: root, groupDepth: 2)]))
        let found = items(in: events)

        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.url.pathExtension == "xcarchive" })
        #expect(found.allSatisfy { $0.safety == .review })
    }

    @Test("A scan root's name filter excludes non-matching entries")
    func nameFilterExcludesNonMatches() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("com.apple.dt.Xcode/data.bin"))
        TestFixtures.writeFile(at: root.appendingPathComponent("SomeThirdPartyApp/data.bin"))

        let events = await collectEvents(ScannerEngine().scan(roots: [
            .init(category: .systemUserCache, url: root, nameFilter: { $0.hasPrefix("com.apple.") }),
        ]))
        let found = items(in: events)

        #expect(found.count == 1)
        #expect(found.first?.url.lastPathComponent == "com.apple.dt.Xcode")
    }

    @Test("Developer data items carry their subcategory through to the scanned item")
    func developerDataItemsCarrySubcategory() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("MyApp-abcdef/data.bin"))

        let events = await collectEvents(ScannerEngine().scan(roots: [
            .init(category: .developerData, subcategory: .derivedData, url: root),
        ]))
        let found = items(in: events)

        #expect(found.count == 1)
        #expect(found.first?.subcategory == DeveloperDataKind.derivedData.rawValue)
    }

    @Test("Nested cache-folder search finds known cache names at any depth, never real data")
    func nestedCacheFolderSearchFindsCachesOnly() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        // Directly inside the app folder...
        TestFixtures.writeFile(at: root.appendingPathComponent("AppA/GPUCache/shader.bin"))
        // ...one level deeper under a profile folder (Chrome-style)...
        TestFixtures.writeFile(at: root.appendingPathComponent("AppB/Default/Cache/data.bin"))
        // ...and real, non-cache data that must never be picked up.
        TestFixtures.writeFile(at: root.appendingPathComponent("AppA/RealData/secret.txt"))
        TestFixtures.writeFile(at: root.appendingPathComponent("AppB/Default/Local Storage/state.db"))

        let events = await collectEvents(ScannerEngine().scan(roots: [
            .init(category: .applicationCache, url: root, nestedCacheFolderNames: FileClassifier.nestedElectronCacheFolderNames),
        ]))
        let found = items(in: events)

        #expect(found.count == 2)
        #expect(Set(found.map(\.url.lastPathComponent)) == ["GPUCache", "Cache"])
        #expect(!found.contains { $0.url.path.contains("RealData") })
        #expect(!found.contains { $0.url.path.contains("Local Storage") })
    }

    @Test("Per-child relative path only reports the fixed cache offset, never sibling data")
    func perChildRelativePathNeverTouchesSiblingData() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("com.example.app/Data/Library/Caches/x.bin"))
        TestFixtures.writeFile(at: root.appendingPathComponent("com.example.app/Data/Documents/personal.txt"))
        // This container has no cache at the expected offset at all.
        TestFixtures.writeFile(at: root.appendingPathComponent("com.other.app/Data/SomethingElse/file.txt"))

        let events = await collectEvents(ScannerEngine().scan(roots: [
            .init(category: .applicationCache, url: root, perChildRelativePath: "Data/Library/Caches"),
        ]))
        let found = items(in: events)

        #expect(found.count == 1)
        #expect(found.first?.url.path.hasSuffix("com.example.app/Data/Library/Caches") == true)
        #expect(!found.contains { $0.url.path.contains("Documents") })
    }
}
