import Foundation

/// Answers "what is the scanner still missing?" by re-measuring a curated
/// list of locations known to hold significant data on developer Macs, and
/// comparing each one's real size against what a completed scan actually
/// found underneath it. Intended for development/debugging, not end users —
/// see `SettingsView`'s Debug-only "Scan Diagnostics" section.
enum DiagnosticsService {
    /// One directory worth checking for scanner blind spots, as a path
    /// relative to the home folder. Only ones that actually exist are
    /// measured — nothing here is assumed present.
    static let candidateDirectories: [String] = [
        "Library/Application Support", "Library/Containers", "Library/Group Containers",
        "Library/Caches", "Library/Developer",
        ".npm", ".cache", ".yarn", ".pnpm-store", ".gradle", ".m2", ".cocoapods",
        "Downloads",
    ]

    struct UndetectedArea: Sendable, Identifiable, Equatable {
        var id: String { path }
        let path: String
        let totalSize: Int64
        let detectedSize: Int64
        var undetectedSize: Int64 { max(0, totalSize - detectedSize) }
    }

    struct Report: Sendable {
        let scannedBytes: Int64
        let safeBytes: Int64
        let reviewBytes: Int64
        let skippedLocations: [String]
        let largestUndetectedAreas: [UndetectedArea]
    }

    /// `items` and `skippedRoots` should come from a just-completed scan
    /// (e.g. `CleanCoordinator`'s state) so the comparison reflects what the
    /// app actually found, not a separate/stale run.
    static func buildReport(
        items: [ScannedItem],
        skippedRoots: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> Report {
        let safeBytes = items.filter { $0.safety == .safe }.reduce(Int64(0)) { $0 + $1.size }
        let reviewBytes = items.filter { $0.safety == .review }.reduce(Int64(0)) { $0 + $1.size }
        let scannedBytes = items.reduce(Int64(0)) { $0 + $1.size }

        let areas = await withTaskGroup(of: UndetectedArea?.self) { group in
            for relativePath in candidateDirectories {
                group.addTask {
                    let url = home.appendingPathComponent(relativePath, isDirectory: true)
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    let measured = DirectorySizeWalker.measure(url)
                    guard measured.exists, measured.totalSize > 0 else { return nil }

                    let prefix = url.standardizedFileURL.path + "/"
                    let detected = items
                        .filter { $0.url.standardizedFileURL.path.hasPrefix(prefix) }
                        .reduce(Int64(0)) { $0 + $1.size }

                    return UndetectedArea(path: relativePath, totalSize: measured.totalSize, detectedSize: detected)
                }
            }
            var results: [UndetectedArea] = []
            for await area in group {
                if let area { results.append(area) }
            }
            return results
        }

        return Report(
            scannedBytes: scannedBytes,
            safeBytes: safeBytes,
            reviewBytes: reviewBytes,
            skippedLocations: skippedRoots.map(\.path),
            largestUndetectedAreas: areas.sorted { $0.undetectedSize > $1.undetectedSize }
        )
    }
}
