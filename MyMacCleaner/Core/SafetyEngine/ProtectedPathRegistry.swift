import Foundation

/// Central list of locations that must never be treated as deletion candidates,
/// regardless of size, age, or name. This registry is intentionally conservative:
/// when in doubt, a path is protected. Safety takes priority over thoroughness.
enum ProtectedPathRegistry {

    /// Absolute system paths that are always off-limits, matched by prefix.
    static let protectedRoots: [String] = [
        "/System",
        "/bin",
        "/sbin",
        "/usr",
        "/var/db",
        "/private/var/db",
        "/private/etc",
        "/etc",
        "/Library/Apple",
    ]

    /// Directory names that, wherever they appear in a path, mark content that
    /// must never be auto-classified as deletable (keys, source control, etc.).
    static let protectedDirectoryNames: Set<String> = [
        ".ssh",
        ".git",
        ".gnupg",
    ]

    /// User content directories (Documents, Desktop, Pictures, Movies, Music) —
    /// the scanner never treats anything under these as a deletion candidate.
    static func personalContentRoots(fileManager: FileManager = .default) -> [URL] {
        let dirs: [FileManager.SearchPathDirectory] = [
            .documentDirectory, .desktopDirectory, .picturesDirectory,
            .moviesDirectory, .musicDirectory,
        ]
        return dirs.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
    }

    /// Full protection check used by the Clean feature: nothing under here is
    /// ever eligible for SAFE/REVIEW auto-cleanup, including the user's own
    /// documents and media.
    static func isProtected(_ url: URL, fileManager: FileManager = .default) -> Bool {
        if isSystemOrCredential(url, fileManager: fileManager) { return true }
        if isUserPersonalContent(url, fileManager: fileManager) { return true }
        return false
    }

    /// Narrower check used by read-only discovery features (like Duplicates)
    /// where finding a copy inside Documents or Pictures is the point — it still
    /// refuses to ever flag system files, credentials, or source repositories.
    static func isSystemOrCredential(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        for root in protectedRoots where path == root || path.hasPrefix(root + "/") {
            return true
        }

        let components = standardized.pathComponents
        if components.contains(where: { protectedDirectoryNames.contains($0) }) {
            return true
        }

        if isKeychainOrCertificate(standardized) { return true }
        if isRunningApplication(standardized) { return true }

        return false
    }

    static func isUserPersonalContent(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let path = url.standardizedFileURL.path
        for base in personalContentRoots(fileManager: fileManager) {
            let basePath = base.standardizedFileURL.path
            if path == basePath || path.hasPrefix(basePath + "/") { return true }
        }
        return false
    }

    static func isKeychainOrCertificate(_ url: URL) -> Bool {
        let path = url.path
        if path.contains("/Library/Keychains/") { return true }
        let protectedExtensions = ["keychain", "keychain-db", "p12", "cer", "crt", "pem"]
        return protectedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Never treat the bundle of a currently-running application as a candidate.
    static func isRunningApplication(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.hasSuffix(".app") else { return false }
        return NSWorkspaceRunningAppChecker.isBundlePathRunning(path)
    }
}
