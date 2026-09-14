import Foundation
import AppKit

/// One app found in /Applications or ~/Applications.
struct InstalledApplication: Identifiable, Hashable, Sendable {
    var id: String { bundleURL.path }
    let bundleURL: URL
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let size: Int64
    let modificationDate: Date?
    let isRunning: Bool
}

/// A file that appears to belong to an installed app but lives outside its
/// `.app` bundle (cache, preferences, saved state, ...).
struct ApplicationLeftover: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let safety: SafetyLevel
    let reason: String
}

enum ApplicationService {
    static func installedApplications(fileManager: FileManager = .default) async -> [InstalledApplication] {
        let searchRoots = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ].filter { fileManager.fileExists(atPath: $0.path) }

        var appURLs: [URL] = []
        for root in searchRoots {
            guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            appURLs.append(contentsOf: children.filter { $0.pathExtension == "app" })
        }

        let runningPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })

        let apps = await withBoundedConcurrency(appURLs, maxConcurrent: ScanConcurrency.defaultLimit) { url -> InstalledApplication? in
            guard let bundle = Bundle(url: url) else { return nil }
            let info = bundle.infoDictionary
            let name = (info?["CFBundleDisplayName"] as? String)
                ?? (info?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version = info?["CFBundleShortVersionString"] as? String
            let measured = DirectorySizeWalker.measure(url)
            return InstalledApplication(
                bundleURL: url,
                name: name,
                bundleIdentifier: bundle.bundleIdentifier,
                version: version,
                size: measured.totalSize,
                modificationDate: measured.modificationDate,
                isRunning: runningPaths.contains(url.standardizedFileURL.path)
            )
        }

        return apps.compactMap { $0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Finds files that clearly belong to `app`, matched by its bundle
    /// identifier wherever possible. Anything that could hold the user's own
    /// data (preferences, Application Support) is reported as REVIEW, never
    /// bundled into an automatic delete.
    static func leftovers(for app: InstalledApplication, language: AppLanguage = .english, fileManager: FileManager = .default) -> [ApplicationLeftover] {
        guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return [] }
        let home = fileManager.homeDirectoryForCurrentUser

        let candidates: [(url: URL, safety: SafetyLevel, reason: String)] = [
            (home.appendingPathComponent("Library/Caches/\(bundleID)"), .safe,
             L("This is \(app.name)'s cache. It's safe to remove along with the app.",
               "\(app.name)의 캐시입니다. 앱과 함께 삭제해도 안전합니다.", for: language)),
            (home.appendingPathComponent("Library/Saved Application State/\(bundleID).savedState"), .safe,
             L("This only stores window positions for \(app.name) and is recreated automatically.",
               "\(app.name)의 창 위치만 저장하며, 자동으로 다시 생성됩니다.", for: language)),
            (home.appendingPathComponent("Library/Logs/\(bundleID)"), .safe,
             L("This is a log folder created by \(app.name).",
               "\(app.name)이 만든 로그 폴더입니다.", for: language)),
            (home.appendingPathComponent("Library/Preferences/\(bundleID).plist"), .review,
             L("This stores \(app.name)'s settings. Remove it if you want a clean, default setup next time you install this app.",
               "\(app.name)의 설정을 저장합니다. 다음에 설치할 때 기본 설정으로 시작하고 싶다면 삭제하세요.", for: language)),
            (home.appendingPathComponent("Library/Application Support/\(app.name)"), .review,
             L("This may hold \(app.name)'s saved data, not just cache — review it before removing.",
               "캐시뿐 아니라 \(app.name)의 저장된 데이터가 들어 있을 수 있습니다 — 삭제 전에 확인하세요.", for: language)),
        ]

        var results: [ApplicationLeftover] = []
        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.url.path) else { continue }
            guard !ProtectedPathRegistry.isProtected(candidate.url) else { continue }
            let measured = DirectorySizeWalker.measure(candidate.url, fileManager: fileManager)
            guard measured.exists else { continue }
            results.append(ApplicationLeftover(url: candidate.url, size: measured.totalSize, safety: candidate.safety, reason: candidate.reason))
        }
        return results
    }
}
