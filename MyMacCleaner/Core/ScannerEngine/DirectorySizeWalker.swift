import Foundation

/// Result of measuring one filesystem entry (a file, or a whole directory tree).
struct DirectoryWalkResult: Sendable {
    /// False when the entry vanished before it could be measured (a normal race
    /// during a live scan, not an error) — callers should silently drop it.
    var exists: Bool = true
    var totalSize: Int64 = 0
    var fileCount: Int = 0
    var modificationDate: Date?
    var isDirectory: Bool = false
}

/// Computes the on-disk size of a file or directory tree using only filesystem
/// metadata — it never opens or reads file contents, so memory use stays flat
/// regardless of how large the files being measured are.
enum DirectorySizeWalker {
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .isSymbolicLinkKey,
    ]
    private static let resourceKeySet = Set(resourceKeys)

    static func measure(_ url: URL, fileManager: FileManager = .default) -> DirectoryWalkResult {
        var result = DirectoryWalkResult()

        guard let selfValues = try? url.resourceValues(forKeys: resourceKeySet) else {
            result.exists = false
            return result
        }
        result.isDirectory = selfValues.isDirectory ?? false
        result.modificationDate = selfValues.contentModificationDate

        if !result.isDirectory {
            result.totalSize = Int64(selfValues.fileAllocatedSize ?? selfValues.fileSize ?? 0)
            result.fileCount = 1
            return result
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, _ in true } // an unreadable child is skipped, not fatal.
        ) else {
            return result
        }

        var latest = result.modificationDate
        var processed = 0
        for case let fileURL as URL in enumerator {
            processed += 1
            if processed.isMultiple(of: 128), Task.isCancelled { break }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeySet) else {
                continue // permission denied or disappeared mid-walk — just skip it.
            }
            if values.isSymbolicLink == true { continue } // never follow links out of the tree.
            if values.isDirectory == true { continue }     // only leaf files add to the size.

            result.totalSize += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
            result.fileCount += 1
            if let date = values.contentModificationDate, latest == nil || date > latest! {
                latest = date
            }
        }
        result.modificationDate = latest
        return result
    }
}
