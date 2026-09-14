import SwiftUI

/// The first screen the user sees: current disk usage and one clear call to
/// action. No settings, no accounts, no explanation required.
struct OverviewView: View {
    @Environment(CleanCoordinator.self) private var cleanCoordinator
    @Environment(\.appLanguage) private var language
    let onScan: () -> Void

    private var diskUsage: DiskUsage? { DiskService.currentUsage() }

    private var lastScanDate: Date? {
        cleanCoordinator.lastScanCompletedAt ?? ScanHistoryStore.lastScanDate
    }

    private var cleanableBytes: Int64 {
        cleanCoordinator.hasScannedOnce ? cleanCoordinator.safeBytes : ScanHistoryStore.lastCleanableBytes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                diskCard
                summaryRow
                scanButton
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("Overview", "개요", for: language))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Your Mac", "내 Mac", for: language))
                .font(.largeTitle.bold())
            Text(L("A quick look at your storage and what can be cleaned up.",
                   "저장 공간과 정리 가능한 항목을 한눈에 확인하세요.", for: language))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var diskCard: some View {
        if let diskUsage {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Disk Usage", "디스크 사용량", for: language)).font(.headline)
                    Spacer()
                    Text("\(ByteFormat.string(diskUsage.usedCapacity, language: language)) \(L("of", "/", for: language)) \(ByteFormat.string(diskUsage.totalCapacity, language: language))")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(.tint)
                            .frame(width: max(6, proxy.size.width * diskUsage.usedFraction))
                    }
                }
                .frame(height: 10)
                Text(L("\(ByteFormat.string(diskUsage.availableCapacity, language: language)) available",
                       "\(ByteFormat.string(diskUsage.availableCapacity, language: language)) 사용 가능", for: language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            statTile(
                title: L("Last Scan", "마지막 스캔", for: language),
                value: lastScanDate.map { RelativeDateFormat.string($0, language: language) } ?? L("Never", "없음", for: language)
            )
            statTile(
                title: L("Can Be Cleaned", "정리 가능", for: language),
                value: ByteFormat.string(cleanableBytes, language: language)
            )
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private var scanButton: some View {
        Button(action: onScan) {
            Label(L("Scan", "스캔", for: language), systemImage: "sparkle.magnifyingglass")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
