import SwiftUI

/// The app's display language. `.system` follows the Mac's language setting;
/// `.english` and `.korean` are explicit overrides chosen in Settings.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case korean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .korean: return "한국어"
        }
    }

    /// `nil` means "don't override" — SwiftUI already follows the system
    /// locale on its own in that case.
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .english: return Locale(identifier: "en")
        case .korean: return Locale(identifier: "ko")
        }
    }

    /// Turns `.system` into the concrete language it currently resolves to,
    /// so the rest of the app never has to handle a "follow the system"
    /// case itself — every view just gets `.english` or `.korean`.
    static func resolved(from stored: AppLanguage) -> AppLanguage {
        switch stored {
        case .english, .korean:
            return stored
        case .system:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return code.hasPrefix("ko") ? .korean : .english
        }
    }
}

/// Shared `@AppStorage`/`UserDefaults` key so every reader of the stored
/// preference (the App scene, Settings) agrees on where to find it.
let appLanguageStorageKey = "MyMacCleaner.appLanguage"

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .english
}

extension EnvironmentValues {
    /// The resolved (never `.system`) language in effect for this view tree.
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

/// Picks between an English and a Korean string for the given language.
/// Used inline at call sites instead of a separate strings catalog, since most
/// of this app's text is short UI chrome that's easiest to read side by side
/// with its translation right where it's used.
func L(_ english: String, _ korean: String, for language: AppLanguage) -> String {
    language == .korean ? korean : english
}
