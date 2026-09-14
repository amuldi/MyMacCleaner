import Foundation

/// Builds throwaway directory trees under the system temp folder so scanner
/// and cleanup tests never touch the real user's home folder. Mirrors the
/// TestEnvironment fixture idea from the product spec (§20).
enum TestFixtures {
    static func makeTemporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    static func writeFile(at url: URL, contents: Data = Data(repeating: 0x41, count: 1024)) -> URL {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: url)
        return url
    }

    static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
