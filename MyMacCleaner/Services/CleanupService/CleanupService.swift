import Foundation

/// Outcome of attempting to remove one item.
struct CleanupResult: Sendable, Identifiable {
    var id: String { url.path }
    let url: URL
    let success: Bool
    let errorDescription: String?
}

/// Performs the actual removal step. Never deletes permanently by default —
/// see product spec §9 — and always processes every item even if some fail,
/// so one locked or already-gone file never blocks the rest of a batch.
enum CleanupService {
    /// Moves each item to the Trash. This is the only action available for
    /// anything outside the Trash itself, and is fully reversible by the user
    /// from Finder afterwards.
    static func moveToTrash(_ urls: [URL]) async -> [CleanupResult] {
        await withBoundedConcurrency(urls, maxConcurrent: 4) { url in
            do {
                // A fresh `.default` access per task, never a captured
                // instance — FileManager isn't Sendable, so each concurrent
                // task must fetch the shared instance itself.
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return CleanupResult(url: url, success: true, errorDescription: nil)
            } catch {
                return CleanupResult(url: url, success: false, errorDescription: error.localizedDescription)
            }
        }
    }

    /// Permanently deletes items — used only for "Empty Trash", and refuses to
    /// run on anything that isn't already inside `~/.Trash` as a last-line
    /// safeguard even if a caller passed the wrong URLs in.
    static func permanentlyDelete(_ urls: [URL]) async -> [CleanupResult] {
        await withBoundedConcurrency(urls, maxConcurrent: 4) { url in
            guard url.standardizedFileURL.path.contains("/.Trash/") else {
                return CleanupResult(url: url, success: false, errorDescription: "Refused: this item is not inside the Trash.")
            }
            do {
                try FileManager.default.removeItem(at: url)
                return CleanupResult(url: url, success: true, errorDescription: nil)
            } catch {
                return CleanupResult(url: url, success: false, errorDescription: error.localizedDescription)
            }
        }
    }
}
