import Testing
import Foundation
@testable import MyMacCleaner

@Suite("DuplicateEngine")
struct DuplicateEngineTests {
    // A tiny minimum size and prefix length so short test fixtures still
    // exercise the real size -> partial hash -> full hash funnel.
    private let options = DuplicateEngine.Options(minimumFileSize: 1, partialHashByteCount: 64)

    @Test("Identical files are grouped as duplicates")
    func identicalFilesAreGrouped() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let content = Data(repeating: 0x7, count: 5000)
        TestFixtures.writeFile(at: root.appendingPathComponent("a/one.bin"), contents: content)
        TestFixtures.writeFile(at: root.appendingPathComponent("b/two.bin"), contents: content)

        let groups = await DuplicateEngine.findDuplicates(in: [root], options: options)

        #expect(groups.count == 1)
        #expect(groups.first?.items.count == 2)
        #expect(groups.first?.reclaimableSize == Int64(content.count))
    }

    @Test("Different files that happen to share a filename are not duplicates")
    func sameNameDifferentContentIsNotADuplicate() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("a/note.txt"), contents: Data("first draft of the note".utf8))
        TestFixtures.writeFile(at: root.appendingPathComponent("b/note.txt"), contents: Data("completely different text".utf8))

        let groups = await DuplicateEngine.findDuplicates(in: [root], options: options)
        #expect(groups.isEmpty)
    }

    @Test("Different files with the same size are not duplicates")
    func sameSizeDifferentContentIsNotADuplicate() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        TestFixtures.writeFile(at: root.appendingPathComponent("a.bin"), contents: Data(repeating: 0x1, count: 4096))
        TestFixtures.writeFile(at: root.appendingPathComponent("b.bin"), contents: Data(repeating: 0x2, count: 4096))

        let groups = await DuplicateEngine.findDuplicates(in: [root], options: options)
        #expect(groups.isEmpty)
    }

    @Test("Three identical files form one group of three, not separate pairs")
    func threeIdenticalFilesFormOneGroup() async {
        let root = TestFixtures.makeTemporaryRoot()
        defer { TestFixtures.removeIfExists(root) }
        let content = Data("triplicate content".utf8)
        TestFixtures.writeFile(at: root.appendingPathComponent("a.txt"), contents: content)
        TestFixtures.writeFile(at: root.appendingPathComponent("b.txt"), contents: content)
        TestFixtures.writeFile(at: root.appendingPathComponent("c.txt"), contents: content)

        let groups = await DuplicateEngine.findDuplicates(in: [root], options: options)
        #expect(groups.count == 1)
        #expect(groups.first?.items.count == 3)
    }
}
