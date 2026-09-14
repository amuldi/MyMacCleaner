import Foundation

/// Walks the filesystem locations described by `FileClassifier.scanRoots()` and
/// streams back classified results as they're found.
///
/// Design notes:
///  - Runs entirely off the main actor; the UI only ever sees `ScanEvent`s
///    delivered through the returned `AsyncStream`, so a large disk never
///    blocks the interface.
///  - Cancellation is cooperative: cancelling the consuming `Task` (or letting
///    the `AsyncStream` terminate) stops in-flight work within a bounded number
///    of files, and whatever was already discovered stays valid — nothing
///    crashes and no partial state is left corrupted.
///  - Concurrency across the entries within one location is capped (see
///    `ScanConcurrency`) instead of either scanning one file at a time or
///    spawning unbounded tasks.
///  - Only filesystem metadata is read — never file contents — so memory use
///    stays flat no matter how large the scanned files are.
actor ScannerEngine {
    func scan(
        roots: [FileClassifier.ScanRoot] = FileClassifier.scanRoots(),
        language: AppLanguage = .english
    ) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.runScan(roots: roots, language: language, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func runScan(
        roots: [FileClassifier.ScanRoot],
        language: AppLanguage,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        var totalFiles = 0
        var totalBytes: Int64 = 0

        for root in roots {
            if Task.isCancelled { break }

            continuation.yield(.progress(ScanProgress(
                filesScanned: totalFiles,
                bytesFound: totalBytes,
                currentDescription: L("Checking \(root.category.displayName(for: language).lowercased())",
                                      "\(root.category.displayName(for: language)) 확인 중",
                                      for: language)
            )))

            guard PermissionManager.canAccess(root.url) else {
                continuation.yield(.rootSkipped(url: root.url, reason: .permissionDenied))
                continue
            }

            let groupURLs: [URL]
            do {
                groupURLs = try Self.groupedChildURLs(of: root.url, depth: root.groupDepth)
                    .filter { root.nameFilter($0.lastPathComponent) }
            } catch {
                continuation.yield(.rootSkipped(url: root.url, reason: PermissionManager.classify(error: error, url: root.url)))
                continue
            }

            if Task.isCancelled { break }

            let (files, bytes) = await scanGroup(
                groupURLs, category: root.category, subcategory: root.subcategory,
                language: language, continuation: continuation
            )
            totalFiles += files
            totalBytes += bytes

            if Task.isCancelled { break }
        }

        if Task.isCancelled {
            continuation.yield(.cancelled)
        } else {
            continuation.yield(.finished(totalFiles: totalFiles, totalBytes: totalBytes))
        }
        continuation.finish()
    }

    /// Measures every URL in `groupURLs` with bounded concurrency, yielding a
    /// `.item` (and updated `.progress`) as each measurement completes.
    private func scanGroup(
        _ groupURLs: [URL],
        category: CleanCategory,
        subcategory: DeveloperDataKind?,
        language: AppLanguage,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async -> (files: Int, bytes: Int64) {
        var filesInGroup = 0
        var bytesInGroup: Int64 = 0
        let maxConcurrent = ScanConcurrency.defaultLimit

        await withTaskGroup(of: (URL, DirectoryWalkResult).self) { group in
            var iterator = groupURLs.makeIterator()

            func addNext() {
                guard let url = iterator.next() else { return }
                group.addTask {
                    if Task.isCancelled { return (url, DirectoryWalkResult(exists: false)) }
                    return (url, DirectorySizeWalker.measure(url))
                }
            }

            for _ in 0..<maxConcurrent { addNext() }

            while let (url, result) = await group.next() {
                if !Task.isCancelled, result.exists {
                    let (safety, reason) = SafetyEngine.evaluate(url: url, category: category, language: language)
                    let item = ScannedItem(
                        url: url,
                        category: category,
                        subcategory: subcategory?.rawValue,
                        safety: safety,
                        reason: reason,
                        size: result.totalSize,
                        modificationDate: result.modificationDate,
                        isDirectory: result.isDirectory
                    )
                    filesInGroup += max(result.fileCount, 1)
                    bytesInGroup += result.totalSize
                    continuation.yield(.item(item))
                    continuation.yield(.progress(ScanProgress(
                        filesScanned: filesInGroup,
                        bytesFound: bytesInGroup,
                        currentDescription: category.displayName(for: language)
                    )))
                }
                if !Task.isCancelled { addNext() }
            }
        }

        return (filesInGroup, bytesInGroup)
    }

    /// Returns the filesystem entries `depth` levels below `root` (e.g. depth 1
    /// = immediate children, depth 2 = grandchildren for locations like Xcode's
    /// date-bucketed Archives folder).
    private static func groupedChildURLs(of root: URL, depth: Int) throws -> [URL] {
        let fileManager = FileManager.default
        var level: [URL] = [root]
        for pass in 0..<max(1, depth) {
            var next: [URL] = []
            for url in level {
                do {
                    let children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    next.append(contentsOf: children)
                } catch {
                    if pass == 0, level.count == 1 {
                        throw error // the root itself is missing/unreadable — surface it.
                    }
                    continue // one nested folder failed; skip it, keep the rest.
                }
            }
            level = next
        }
        return level
    }
}
