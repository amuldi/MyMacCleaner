import Testing
import Foundation
@testable import MyMacCleaner

@Suite("CleanupService")
struct CleanupServiceTests {
    @Test("Moves a real file to the Trash")
    func movesFileToTrash() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let file = TestFixtures.writeFile(at: root.appendingPathComponent("throwaway-\(UUID().uuidString).txt"))

        let results = await CleanupService.moveToTrash([file])

        #expect(results.count == 1)
        #expect(results.first?.success == true)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("A missing file fails gracefully instead of crashing")
    func missingFileFailsGracefully() async {
        let missing = TestFixtures.makeTemporaryRoot().appendingPathComponent("gone.txt")
        let results = await CleanupService.moveToTrash([missing])

        #expect(results.count == 1)
        #expect(results.first?.success == false)
        #expect(results.first?.errorDescription != nil)
    }

    @Test("A file that disappears right before cleanup still fails gracefully")
    func fileDisappearingBeforeCleanupFailsGracefully() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let file = TestFixtures.writeFile(at: root.appendingPathComponent("vanishing.txt"))
        try? FileManager.default.removeItem(at: file)

        let results = await CleanupService.moveToTrash([file])
        #expect(results.first?.success == false)
    }

    @Test("A locked file fails gracefully and other items in the same batch still proceed")
    func lockedFileDoesNotBlockOtherItems() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let locked = TestFixtures.writeFile(at: root.appendingPathComponent("locked.txt"))
        let normal = TestFixtures.writeFile(at: root.appendingPathComponent("normal.txt"))
        try! FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)

        let results = await CleanupService.moveToTrash([locked, normal])

        // Always restore mutability before the fixture directory is torn down.
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path)

        let lockedResult = results.first { $0.url == locked }
        let normalResult = results.first { $0.url == normal }
        #expect(lockedResult?.success == false)
        #expect(normalResult?.success == true)
    }

    @Test("permanentlyDelete refuses anything outside the Trash and never touches it")
    func refusesPermanentDeleteOutsideTrash() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let file = TestFixtures.writeFile(at: root.appendingPathComponent("safe.txt"))

        let results = await CleanupService.permanentlyDelete([file])

        #expect(results.first?.success == false)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
