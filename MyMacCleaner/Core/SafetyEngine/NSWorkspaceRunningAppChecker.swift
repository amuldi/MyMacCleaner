import AppKit

/// Thin wrapper around `NSWorkspace` so the safety checks that depend on "is this
/// app currently running" stay easy to reason about and swap out in tests.
enum NSWorkspaceRunningAppChecker {
    static func isBundlePathRunning(_ path: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleURL?.standardizedFileURL.path == path
        }
    }
}
