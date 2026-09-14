import Foundation

/// Runs `operation` over `items` with at most `maxConcurrent` tasks in flight at
/// once. Keeps filesystem-heavy work from either serializing everything (slow)
/// or flooding the system with unbounded concurrent I/O.
func withBoundedConcurrency<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    operation: @escaping @Sendable (Item) async -> Result
) async -> [Result] {
    guard !items.isEmpty else { return [] }
    let limit = max(1, maxConcurrent)

    return await withTaskGroup(of: Result.self) { group in
        var iterator = items.makeIterator()
        var results: [Result] = []
        results.reserveCapacity(items.count)

        for _ in 0..<limit {
            guard let item = iterator.next() else { break }
            group.addTask { await operation(item) }
        }
        while let result = await group.next() {
            results.append(result)
            if let item = iterator.next() {
                group.addTask { await operation(item) }
            }
        }
        return results
    }
}

/// A reasonable default concurrency ceiling for I/O-bound filesystem work —
/// enough to overlap disk latency without starving the cooperative thread pool.
enum ScanConcurrency {
    static var defaultLimit: Int {
        max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
    }
}
