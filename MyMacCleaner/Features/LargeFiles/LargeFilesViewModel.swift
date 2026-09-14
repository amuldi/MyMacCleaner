import Foundation
import Observation

@MainActor
@Observable
final class LargeFilesViewModel {
    enum State: Equatable {
        case idle
        case scanning
        case completed
        case cancelled
    }

    var threshold: LargeFileThreshold = .oneGB {
        didSet {
            guard oldValue != threshold else { return }
            startScan()
        }
    }

    private(set) var state: State = .idle
    private(set) var results: [LargeFileItem] = []
    private var scanTask: Task<Void, Never>?

    func startScanIfNeeded() {
        guard state == .idle else { return }
        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        state = .scanning
        results = []
        let minimumSize = threshold.rawValue
        let home = FileManager.default.homeDirectoryForCurrentUser

        scanTask = Task {
            let found = await LargeFileService.scan(root: home, minimumSize: minimumSize)
            if Task.isCancelled {
                state = .cancelled
                return
            }
            results = found
            state = .completed
        }
    }

    func cancel() {
        scanTask?.cancel()
        state = .cancelled
    }
}
