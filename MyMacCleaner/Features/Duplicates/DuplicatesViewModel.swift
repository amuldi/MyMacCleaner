import Foundation
import Observation

@MainActor
@Observable
final class DuplicatesViewModel {
    enum State: Equatable { case idle, scanning, completed, cancelled }

    private(set) var state: State = .idle
    private(set) var groups: [DuplicateGroup] = []
    /// For each group, the path of the copy to *keep*; every other copy in
    /// that group is the one offered for removal.
    private(set) var keepSelection: [String: String] = [:]
    private var scanTask: Task<Void, Never>?

    /// MVP scope: the two folders where duplicate clutter accumulates most.
    /// A future version can let the user add folders via an open panel.
    var scannedFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func startScanIfNeeded() {
        guard state == .idle else { return }
        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        state = .scanning
        groups = []
        keepSelection = [:]
        let roots = scannedFolders

        scanTask = Task {
            let found = await DuplicateEngine.findDuplicates(in: roots)
            if Task.isCancelled {
                state = .cancelled
                return
            }
            groups = found
            for group in found {
                if let keep = group.items.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }) {
                    keepSelection[group.id] = keep.url.path
                }
            }
            state = .completed
        }
    }

    func cancel() {
        scanTask?.cancel()
        state = .cancelled
    }

    func setKeep(_ path: String, for group: DuplicateGroup) {
        keepSelection[group.id] = path
    }

    func deletables(in group: DuplicateGroup) -> [DuplicateCandidate] {
        let keepPath = keepSelection[group.id]
        return group.items.filter { $0.url.path != keepPath }
    }

    @discardableResult
    func removeDuplicates(in group: DuplicateGroup) async -> CleanSummaryLite {
        let urls = deletables(in: group).map(\.url)
        let results = await CleanupService.moveToTrash(urls)
        groups.removeAll { $0.id == group.id }
        let succeeded = results.filter(\.success).count
        return CleanSummaryLite(succeededCount: succeeded, failedCount: results.count - succeeded)
    }
}
