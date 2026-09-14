import Foundation
import AppKit

/// Checks and communicates filesystem access without ever crashing when access
/// is missing. macOS (for a non-sandboxed app like this one) reports missing
/// permission as an ordinary POSIX error (EPERM/EACCES); this type turns that
/// into a `SkipReason` the UI can show inline instead of failing the whole scan.
enum PermissionManager {

    /// Best-effort pre-check so the scanner can skip a whole root quickly
    /// instead of discovering the failure file-by-file.
    static func canAccess(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            // Nothing to protect against — the caller reports this as "not found".
            return true
        }
        if isDirectory.boolValue {
            return (try? fileManager.contentsOfDirectory(atPath: url.path)) != nil
        }
        return fileManager.isReadableFile(atPath: url.path)
    }

    /// Turns a thrown filesystem error (or a directly-observed missing/unreadable
    /// path) into a reason the UI can present.
    static func classify(error: Error?, url: URL, fileManager: FileManager = .default) -> SkipReason {
        if let nsError = error as NSError? {
            if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileReadNoSuchFile.rawValue {
                return .notFound
            }
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
                return .permissionDenied
            }
        }
        if !fileManager.fileExists(atPath: url.path) {
            return .notFound
        }
        if !fileManager.isReadableFile(atPath: url.path) {
            return .permissionDenied
        }
        return .other(error?.localizedDescription ?? "Could not read this location.")
    }

    /// Opens System Settings to the Full Disk Access pane so the user has a
    /// one-click path to fixing a permission problem.
    @MainActor
    static func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
