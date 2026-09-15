import Foundation

/// Maps well-known filesystem locations to the `CleanCategory` the scanner should
/// file them under, and describes how each location should be grouped into rows.
enum FileClassifier {

    /// One location the scanner walks. Depending on which optional fields are
    /// set, a root is scanned one of three ways:
    ///
    ///  1. **Plain** (default): group by the folder's immediate descendants
    ///     `groupDepth` levels down — a whole app cache folder becomes one
    ///     reviewable row instead of thousands of individual files.
    ///  2. **Per-child relative path** (`perChildRelativePath` set): `url`'s
    ///     immediate children are treated as one container each (e.g. one
    ///     per sandboxed app under `~/Library/Containers`), and this fixed
    ///     relative path *inside* each one is what's actually reported —
    ///     used for sandboxed apps whose cache lives at a predictable offset
    ///     inside their container, not directly inside `url`.
    ///  3. **Nested cache-folder search** (`nestedCacheFolderNames` set):
    ///     each immediate child of `url` (one per app) is searched, up to a
    ///     bounded depth, for subfolders whose *name* is a well-known
    ///     Chromium/Electron cache folder (`GPUCache`, `Code Cache`, ...) —
    ///     used for `~/Library/Application Support`, where an app's cache
    ///     sits at a variable depth under its own folder, not a fixed one.
    ///
    /// Modes 2 and 3 exist because a plain top-level listing can't reach
    /// these locations at all, not because they relax what counts as safe —
    /// the same `SafetyEngine` and `CleanCategory` rules still apply to
    /// whatever they find.
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
        let perChildRelativePath: String?
        let nestedCacheFolderNames: Set<String>?
        let nestedSearchMaxDepth: Int

        init(
            category: CleanCategory,
            subcategory: DeveloperDataKind? = nil,
            url: URL,
            groupDepth: Int = 1,
            nameFilter: @escaping @Sendable (String) -> Bool = { _ in true },
            perChildRelativePath: String? = nil,
            nestedCacheFolderNames: Set<String>? = nil,
            nestedSearchMaxDepth: Int = 3
        ) {
            self.category = category
            self.subcategory = subcategory
            self.url = url
            self.groupDepth = groupDepth
            self.nameFilter = nameFilter
            self.perChildRelativePath = perChildRelativePath
            self.nestedCacheFolderNames = nestedCacheFolderNames
            self.nestedSearchMaxDepth = nestedSearchMaxDepth
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

    /// Universally-recognized Chromium/Electron cache subfolder names. Any
    /// app built on Electron or CEF (Slack, Discord, VS Code, Notion, Figma,
    /// Spotify, ...) creates some of these inside its own
    /// `~/Library/Application Support/<App>` folder — regardless of the
    /// app's name — and every one of them is safe to delete: the app
    /// rebuilds them automatically, the same way a browser rebuilds its own
    /// cache. Deliberately excludes "Local Storage", "IndexedDB", and
    /// "Session Storage", which can hold real app/user state.
    static let nestedElectronCacheFolderNames: Set<String> = [
        "Cache", "Cache_Data", "Code Cache", "GPUCache",
        "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache",
        "blob_storage", "CacheStorage",
    ]

    /// The default set of locations scanned by the Clean feature. All of these
    /// live inside the current user's home folder — no system directories are
    /// ever included here.
    static func scanRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           tempDirectory: URL = FileManager.default.temporaryDirectory) -> [ScanRoot] {
        let cachesRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let reservedCacheNames = directBrowserCacheNames.union(nestedBrowserPublishers)
        let applicationSupportRoot = home.appendingPathComponent("Library/Application Support", isDirectory: true)

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

            // Sandboxed apps don't put their cache in ~/Library/Caches at
            // all — it lives inside their container, at this fixed offset.
            ScanRoot(category: .applicationCache,
                     url: home.appendingPathComponent("Library/Containers", isDirectory: true),
                     perChildRelativePath: "Data/Library/Caches"),
            ScanRoot(category: .applicationCache,
                     url: home.appendingPathComponent("Library/Group Containers", isDirectory: true),
                     perChildRelativePath: "Library/Caches"),

            // Non-sandboxed Electron/Chromium-style apps keep their cache
            // inside Application Support instead, at a variable depth
            // (sometimes directly inside the app folder, sometimes one level
            // deeper under a browser-style profile folder) — so this root
            // searches by folder name rather than a fixed path.
            ScanRoot(category: .applicationCache, url: applicationSupportRoot,
                     nameFilter: { $0 != "CrashReporter" },
                     nestedCacheFolderNames: nestedElectronCacheFolderNames),

            // Old crash reports — safe, historical diagnostic data only.
            ScanRoot(category: .logs, url: applicationSupportRoot.appendingPathComponent("CrashReporter", isDirectory: true)),

            ScanRoot(category: .logs, url: home.appendingPathComponent("Library/Logs", isDirectory: true)),
            ScanRoot(category: .temporaryFiles, url: tempDirectory),

            // Developer Data, broken down the way a developer actually
            // thinks about disk usage: Xcode build output, archives,
            // simulators, device support, and package manager caches —
            // each becomes its own drill-down group in the UI.
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

            // Package manager / dev-tool caches. `~/.cache` is the
            // XDG-convention "non-essential cached data" directory that pip,
            // uv, Hugging Face, and many other cross-platform CLI tools use
            // on macOS too; `~/.npm` is npm's own cache root. Both are only
            // ever scanned if they actually exist — nothing is assumed.
            ScanRoot(category: .developerData, subcategory: .packageManagerCache,
                     url: home.appendingPathComponent(".npm", isDirectory: true)),
            ScanRoot(category: .developerData, subcategory: .packageManagerCache,
                     url: home.appendingPathComponent(".cache", isDirectory: true)),

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
