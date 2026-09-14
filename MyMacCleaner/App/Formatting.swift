import Foundation

enum ByteFormat {
    // A fresh formatter per call, rather than a cached static one, keeps this
    // trivially safe under Swift 6 strict concurrency (formatters aren't
    // Sendable) — call volume here is display-only and low.
    static func string(_ bytes: Int64, language: AppLanguage = .english) -> String {
        // ByteCountFormatter has no `locale` property — it always renders
        // digits using the system locale, so `language` only affects the
        // callers that build a surrounding localized sentence around this.
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

enum RelativeDateFormat {
    static func string(_ date: Date, language: AppLanguage = .english) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        if let locale = language.locale {
            formatter.locale = locale
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension Date {
    func shortDisplayString(language: AppLanguage = .english) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let locale = language.locale {
            formatter.locale = locale
        }
        return formatter.string(from: self)
    }
}
