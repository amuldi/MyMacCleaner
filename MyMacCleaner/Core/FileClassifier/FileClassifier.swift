import Foundation

/// Maps well-known filesystem locations to the `CleanCategory` the scanner should
/// file them under, and describes how each location should be grouped into rows.
enum FileClassifier {

    /// One location the scanner walks. Results are grouped by the folder's
    /// immediate descendants at `groupDepth` levels down, so a whole app cache
    /// folder (or a whole DerivedData build folder) becomes one reviewable row
    /// instead of thousands of individual files.
    struct ScanRoot: Sendable {
        let category: CleanCategory
        let subcategory: DeveloperDataKind?
        let url: URL
        let groupDepth: Int
        /// Only entries whose final path component satisfies this predicate
        /// are included. Defaults to "everything" — used to carve a specific
        /// slice out of a shared parent folder (e.g. splitting browser and
        /// system caches out of the generic `~/Library/Caches` scan) without
        /// double-reporting the same file under two categories.
        let nameFilter: @Sendable (String) -> Bool

        init(
            category: CleanCategory,
            subcategory: DeveloperDataKind? = nil,
            url: URL,
            groupDepth: Int = 1,
            nameFilter: @escaping @Sendable (String) -> Bool = { _ in true }
        ) {
            self.category = category
            self.subcategory = subcategory
            self.url = url
            self.groupDepth = groupDepth
            self.nameFilter = nameFilter
        }
    }

    /// Well-known browser cache folder names that sit directly inside
    /// `~/Library/Caches` (Chrome and Brave nest one level deeper under a
    /// publisher folder and get their own explicit roots instead).
    static let directBrowserCacheNames: Set<String> = [
        "com.apple.Safari", "Firefox", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.brave.Browser", "com.operasoftware.Opera",
    ]
    private static let nestedBrowserPublishers: Set<String> = ["Google", "BraveSoftware"]
    private static let systemCachePrefix = "com.apple."

    /// The default set of locations scanned by the Clean feature. All of these
    /// live inside the current user's home folder — no system directories are
    /// ever included here.
    static func scanRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           tempDirectory: URL = FileManager.default.temporaryDirectory) -> [ScanRoot] {
        let cachesRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let reservedCacheNames = directBrowserCacheNames.union(nestedBrowserPublishers)

        return [
            // Browser caches: named directly under Caches...
            ScanRoot(category: .browserCache, url: cachesRoot,
                     nameFilter: { directBrowserCacheNames.contains($0) }),
            // ...or nested one level under a publisher folder (Chrome, Brave).
            ScanRoot(category: .browserCache, url: cachesRoot.appendingPathComponent("Google", isDirectory: true)),
            ScanRoot(category: .browserCache, url: cachesRoot.appendingPathComponent("BraveSoftware", isDirectory: true)),

            // Apple's own per-user system caches (iCloud sync, Spotlight,
            // QuickLook thumbnails, ...) — kept distinct from third-party
            // app caches so the user can tell them apart.
            ScanRoot(category: .systemUserCache, url: cachesRoot,
                     nameFilter: { $0.hasPrefix(systemCachePrefix) && !directBrowserCacheNames.contains($0) }),

            // Everything else in Caches is a regular third-party app cache.
            ScanRoot(category: .applicationCache, url: cachesRoot,
                     nameFilter: { !reservedCacheNames.contains($0) && !$0.hasPrefix(systemCachePrefix) }),

            ScanRoot(category: .logs, url: home.appendingPathComponent("Library/Logs", isDirectory: true)),
            ScanRoot(category: .temporaryFiles, url: tempDirectory),

            // Xcode Files, broken down the way a developer actually thinks
            // about disk usage: build data, archives, simulators, device
            // support — each becomes its own drill-down group in the UI.
            ScanRoot(category: .developerData, subcategory: .derivedData,
                     url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)),
            ScanRoot(category: .developerData, subcategory: .archives,
                     url: home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true), groupDepth: 2),
            ScanRoot(category: .developerData, subcategory: .simulators,
                     url: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)),
            ScanRoot(category: .developerData, subcategory: .iosDeviceSupport,
                     url: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)),
            ScanRoot(category: .developerData, subcategory: .watchosDeviceSupport,
                     url: home.appendingPathComponent("Library/Developer/Xcode/watchOS DeviceSupport", isDirectory: true)),

            // Installers left behind in Downloads after the app inside was
            // already installed — a very common, easy-to-recognize win.
            ScanRoot(category: .installerFiles, url: home.appendingPathComponent("Downloads", isDirectory: true),
                     nameFilter: { name in
                         let lower = name.lowercased()
                         return lower.hasSuffix(".dmg") || lower.hasSuffix(".pkg")
                     }),

            ScanRoot(category: .trash, url: home.appendingPathComponent(".Trash", isDirectory: true)),
        ]
    }
}
