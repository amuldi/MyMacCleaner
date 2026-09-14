import Foundation
import CryptoKit

/// One file that might be part of a duplicate set.
struct DuplicateCandidate: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let modificationDate: Date?
}

/// A set of files confirmed to have identical content.
struct DuplicateGroup: Identifiable, Sendable {
    let id: String // the shared full-content hash
    let size: Int64
    let items: [DuplicateCandidate]

    /// Space recoverable by keeping exactly one copy and removing the rest.
    var reclaimableSize: Int64 { size * Int64(max(0, items.count - 1)) }
}

/// Finds files that are byte-for-byte identical, using a cheap-to-expensive
/// funnel so most non-duplicates are ruled out without ever hashing a full file:
///
///   group by size  →  compare a small prefix hash  →  compare a full hash
///
/// Two files are only ever reported as duplicates once their full-content hash
/// matches — matching filenames alone, or matching size alone, is never enough.
enum DuplicateEngine {
    struct Options: Sendable {
        var minimumFileSize: Int64 = 4 * 1024
        var partialHashByteCount: Int = 64 * 1024
    }

    static func findDuplicates(in roots: [URL], options: Options = Options()) async -> [DuplicateGroup] {
        // Walking the candidate folders runs in a task-group child so it lands
        // on the cooperative thread pool rather than whichever actor called
        // us (often `@MainActor`, from a view model), while still cancelling
        // cleanly as a structured descendant of the caller's task.
        let minimumSize = options.minimumFileSize
        let candidates = await withTaskGroup(of: [DuplicateCandidate].self) { group in
            group.addTask { collectCandidateFiles(roots: roots, minimumSize: minimumSize) }
            return await group.next() ?? []
        }
        let bySize = Dictionary(grouping: candidates, by: \.size).filter { $0.value.count > 1 }

        var confirmedGroups: [DuplicateGroup] = []

        for (_, sizeGroup) in bySize {
            if Task.isCancelled { break }

            let partials = await withBoundedConcurrency(sizeGroup, maxConcurrent: ScanConcurrency.defaultLimit) {
                candidate -> (DuplicateCandidate, String?) in
                (candidate, hashPrefix(of: candidate.url, byteCount: options.partialHashByteCount))
            }
            let byPartialHash = Dictionary(grouping: partials.filter { $0.1 != nil }, by: { $0.1! })
                .filter { $0.value.count > 1 }

            for (_, partialGroup) in byPartialHash {
                if Task.isCancelled { break }

                let candidatesToConfirm = partialGroup.map(\.0)
                let fulls = await withBoundedConcurrency(candidatesToConfirm, maxConcurrent: ScanConcurrency.defaultLimit) {
                    candidate -> (DuplicateCandidate, String?) in
                    (candidate, fullHash(of: candidate.url))
                }
                let byFullHash = Dictionary(grouping: fulls.filter { $0.1 != nil }, by: { $0.1! })
                    .filter { $0.value.count > 1 }

                for (hash, fullGroup) in byFullHash {
                    let items = fullGroup.map(\.0)
                    confirmedGroups.append(DuplicateGroup(id: hash, size: items.first?.size ?? 0, items: items))
                }
            }
        }

        return confirmedGroups.sorted { $0.reclaimableSize > $1.reclaimableSize }
    }

    private static func collectCandidateFiles(roots: [URL], minimumSize: Int64) -> [DuplicateCandidate] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        let keySet = Set(keys)
        var results: [DuplicateCandidate] = []

        for root in roots {
            guard PermissionManager.canAccess(root) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return results }
                guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
                if values.isDirectory == true || values.isSymbolicLink == true { continue }
                if ProtectedPathRegistry.isSystemOrCredential(url) { continue }

                let size = Int64(values.fileSize ?? 0)
                guard size >= minimumSize else { continue }
                results.append(DuplicateCandidate(url: url, size: size, modificationDate: values.contentModificationDate))
            }
        }
        return results
    }

    private static func hashPrefix(of url: URL, byteCount: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: byteCount) else { return nil }
        return sha256Hex(data)
    }

    private static func fullHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while true {
            if Task.isCancelled { return nil }
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
