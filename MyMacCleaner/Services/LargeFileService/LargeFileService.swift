import Foundation

/// One large file (or app-like bundle) found on disk.
struct LargeFileItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let modificationDate: Date?
    let isDirectory: Bool
}

enum LargeFileThreshold: Int64, CaseIterable, Identifiable, Hashable {
    case oneGB = 1_000_000_000
    case fiveGB = 5_000_000_000
    case tenGB = 10_000_000_000

    var id: Int64 { rawValue }
    var label: String {
        switch self {
        case .oneGB: return "1 GB"
        case .fiveGB: return "5 GB"
        case .tenGB: return "10 GB"
        }
    }
}

/// Finds individual files (and recognizable app-like bundles, reported as one
/// unit) at or above a size threshold. Nothing here is ever deleted
/// automatically — this feature is discovery-only; see product spec §11.
enum LargeFileService {
    /// Bundle-style directories that represent one logical "thing" to a user
    /// (an app, a framework, an archive) — reported as a single sized row
    /// instead of being descended into file-by-file.
    private static let packageExtensions: Set<String> = [
        "app", "framework", "xcarchive", "bundle", "kext",
        "plugin", "prefpane", "qlgenerator", "action", "mdimporter", "saver", "component",
    ]

    /// Walking the whole home folder is not cheap, so the actual work happens
    /// in a `withTaskGroup` child task — that runs on the cooperative thread
    /// pool instead of whichever actor (often `@MainActor`, from a view
    /// model) called `scan`, and still cancels cleanly because a task-group
    /// child is a structured descendant of the caller's task.
    static func scan(root: URL, minimumSize: Int64) async -> [LargeFileItem] {
        await withTaskGroup(of: [LargeFileItem].self) { group in
            group.addTask {
                scanSynchronously(root: root, minimumSize: minimumSize)
            }
            return await group.next() ?? []
        }
    }

    private static func scanSynchronously(root: URL, minimumSize: Int64) -> [LargeFileItem] {
        let fileManager = FileManager.default
        guard PermissionManager.canAccess(root, fileManager: fileManager) else { return [] }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .fileAllocatedSizeKey,
            .contentModificationDateKey, .isSymbolicLinkKey,
        ]
        let keySet = Set(keys)
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [LargeFileItem] = []
        var processed = 0

        for case let url as URL in enumerator {
            processed += 1
            if processed.isMultiple(of: 256), Task.isCancelled { break }

            guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
            if values.isSymbolicLink == true { continue }
            if ProtectedPathRegistry.isSystemOrCredential(url) {
                enumerator.skipDescendants()
                continue
            }

            if values.isDirectory == true {
                guard packageExtensions.contains(url.pathExtension.lowercased()) else { continue }
                enumerator.skipDescendants()
                let measured = DirectorySizeWalker.measure(url, fileManager: fileManager)
                guard measured.exists, measured.totalSize >= minimumSize else { continue }
                results.append(LargeFileItem(url: url, size: measured.totalSize, modificationDate: measured.modificationDate, isDirectory: true))
                continue
            }

            let size = Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
            guard size >= minimumSize else { continue }
            results.append(LargeFileItem(url: url, size: size, modificationDate: values.contentModificationDate, isDirectory: false))
        }

        return results.sorted { $0.size > $1.size }
    }
}
