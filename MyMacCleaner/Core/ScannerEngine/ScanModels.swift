import Foundation

/// A category of files the scanner groups results into, shown throughout the UI.
enum CleanCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case applicationCache = "Application Cache"
    case browserCache = "Browser Cache"
    case systemUserCache = "System/User Cache"
    case logs = "Logs"
    case temporaryFiles = "Temporary Files"
    case developerData = "Developer Data"
    case installerFiles = "Installer Files"
    case trash = "Trash"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .applicationCache: return "square.stack.3d.up.fill"
        case .browserCache: return "network"
        case .systemUserCache: return "internaldrive"
        case .logs: return "doc.text"
        case .temporaryFiles: return "clock.arrow.2.circlepath"
        case .developerData: return "hammer.fill"
        case .installerFiles: return "shippingbox"
        case .trash: return "trash"
        }
    }

    /// Trash items are already discarded by the user; "cleaning" this category
    /// means permanently emptying it rather than moving items to the Trash again.
    var cleanupIsPermanentDeletion: Bool { self == .trash }

    func displayName(for language: AppLanguage) -> String {
        switch self {
        case .applicationCache: return L("Application Cache", "앱 캐시 파일", for: language)
        case .browserCache: return L("Browser Cache", "브라우저 캐시", for: language)
        case .systemUserCache: return L("System Cache", "시스템 캐시 파일", for: language)
        case .logs: return L("Logs", "로그 파일", for: language)
        case .temporaryFiles: return L("Temporary Files", "임시 파일", for: language)
        case .developerData: return L("Xcode Files", "Xcode 파일", for: language)
        case .installerFiles: return L("Installer Files", "설치 파일 (DMG/PKG)", for: language)
        case .trash: return L("Trash", "휴지통", for: language)
        }
    }
}

/// A finer-grained bucket used only within `.developerData`, so "Xcode Files"
/// can drill down the same way it does in other cleaner apps (build data,
/// archives, simulators, device support, each shown as its own group).
enum DeveloperDataKind: String, Sendable {
    case derivedData
    case archives
    case simulators
    case iosDeviceSupport
    case watchosDeviceSupport

    func displayName(for language: AppLanguage) -> String {
        switch self {
        case .derivedData: return L("Xcode Build Data", "Xcode 빌드 데이터", for: language)
        case .archives: return L("Archives", "보관 파일", for: language)
        case .simulators: return L("Simulator Caches", "시뮬레이터 캐시", for: language)
        case .iosDeviceSupport: return L("iOS Device Support", "iOS 기기 지원 파일", for: language)
        case .watchosDeviceSupport: return L("watchOS Device Support", "watchOS 기기 지원 파일", for: language)
        }
    }
}

/// A file-system safety classification. Ordering matters: `protected` always wins.
enum SafetyLevel: String, Codable, Comparable, Sendable {
    case safe = "SAFE"
    case review = "REVIEW"
    case protected = "PROTECTED"

    func displayName(for language: AppLanguage) -> String {
        switch self {
        case .safe: return L("SAFE", "안전", for: language)
        case .review: return L("REVIEW", "검토 필요", for: language)
        case .protected: return L("PROTECTED", "보호됨", for: language)
        }
    }

    private var rank: Int {
        switch self {
        case .safe: return 0
        case .review: return 1
        case .protected: return 2
        }
    }

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool { lhs.rank < rhs.rank }
}

/// One file or folder discovered by the scanner, already classified.
struct ScannedItem: Identifiable, Hashable, Sendable {
    /// The absolute path is a stable, unique identifier for a filesystem entry.
    var id: String { url.path }
    let url: URL
    let category: CleanCategory
    /// Non-nil only for `.developerData` items — the raw value of a
    /// `DeveloperDataKind`, used to group the category's detail list.
    let subcategory: String?
    let safety: SafetyLevel
    let reason: String
    let size: Int64
    let modificationDate: Date?
    let isDirectory: Bool

    init(
        url: URL,
        category: CleanCategory,
        subcategory: String? = nil,
        safety: SafetyLevel,
        reason: String,
        size: Int64,
        modificationDate: Date?,
        isDirectory: Bool
    ) {
        self.url = url
        self.category = category
        self.subcategory = subcategory
        self.safety = safety
        self.reason = reason
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }

    static func == (lhs: ScannedItem, rhs: ScannedItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Lightweight progress snapshot emitted while a scan is running.
struct ScanProgress: Sendable, Equatable {
    var filesScanned: Int = 0
    var bytesFound: Int64 = 0
    var currentDescription: String = ""
}

/// Why a location was skipped instead of scanned.
enum SkipReason: Sendable, Equatable {
    case permissionDenied
    case notFound
    case other(String)

    func displayText(for language: AppLanguage) -> String {
        switch self {
        case .permissionDenied: return L("Skipped — Permission Required", "건너뜀 — 권한 필요", for: language)
        case .notFound: return L("Not found", "찾을 수 없음", for: language)
        case .other(let message): return message
        }
    }
}

/// Events streamed out of `ScannerEngine.scan` while a scan is in progress.
enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case item(ScannedItem)
    case rootSkipped(url: URL, reason: SkipReason)
    case finished(totalFiles: Int, totalBytes: Int64)
    case cancelled
}
