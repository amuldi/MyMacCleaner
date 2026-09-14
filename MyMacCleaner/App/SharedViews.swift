import SwiftUI

extension ShapeStyle where Self == Color {
    /// A card surface that reads correctly in both light and dark mode without
    /// hand-tuning opacity values.
    static var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
}

/// Small colored pill showing a file's safety classification.
struct SafetyBadgeView: View {
    @Environment(\.appLanguage) private var language
    let safety: SafetyLevel

    var body: some View {
        Text(safety.displayName(for: language))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch safety {
        case .safe: return .green
        case .review: return .orange
        case .protected: return .secondary
        }
    }
}

/// A calm, centered empty state — used whenever a scan or search finds nothing,
/// so the app never shows a bare blank screen.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Inline banner telling the user that some locations couldn't be scanned
/// because macOS requires explicit permission — with a one-click way to fix it.
struct PermissionBannerView: View {
    @Environment(\.appLanguage) private var language
    let skippedCount: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text(L("Some locations require permission and were skipped.",
                   "일부 위치는 권한이 필요해 건너뛰었습니다.", for: language))
                .font(.callout)
            Spacer()
            Button(L("Open System Settings", "시스템 설정 열기", for: language)) {
                PermissionManager.openFullDiskAccessSettings()
            }
            .font(.callout)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Reusable "why can I remove this?" disclosure used across item detail rows.
struct ReasonDisclosureView: View {
    @Environment(\.appLanguage) private var language
    let reason: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Why can I remove this?", "왜 삭제해도 되나요?", for: language))
                .font(.caption.weight(.semibold))
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
