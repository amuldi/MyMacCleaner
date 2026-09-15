import SwiftUI

struct SettingsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(CleanCoordinator.self) private var cleanCoordinator
    @AppStorage(appLanguageStorageKey) private var storedLanguage: AppLanguage = .system
    #if DEBUG
    @State private var diagnosticsReport: DiagnosticsService.Report?
    @State private var isRunningDiagnostics = false
    #endif

    var body: some View {
        Form {
            Section(L("Language", "언어", for: language)) {
                Picker(L("App Language", "앱 언어", for: language), selection: $storedLanguage) {
                    Text(L("System", "시스템 설정 따름", for: language)).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("한국어").tag(AppLanguage.korean)
                }
                .pickerStyle(.menu)
                Text(L(
                    "Changes take effect immediately. A new scan uses the new language for its results.",
                    "변경 사항은 즉시 적용됩니다. 새로 스캔하면 그 결과부터 새 언어로 표시됩니다.",
                    for: language
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section(L("About", "정보", for: language)) {
                LabeledContent(L("Version", "버전", for: language), value: "0.1.0")
            }

            Section(L("Permissions", "권한", for: language)) {
                Button(L("Open Full Disk Access Settings…", "전체 디스크 접근 권한 설정 열기…", for: language)) {
                    PermissionManager.openFullDiskAccessSettings()
                }
                Text(L(
                    "MyMacCleaner needs Full Disk Access to see every cache and log file. Nothing is ever deleted without your review.",
                    "MyMacCleaner가 모든 캐시와 로그 파일을 확인하려면 전체 디스크 접근 권한이 필요합니다. 직접 검토하지 않은 항목은 절대 삭제되지 않습니다.",
                    for: language
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            #if DEBUG
            diagnosticsSection
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle(L("Settings", "설정", for: language))
        .frame(maxWidth: 480)
    }

    #if DEBUG
    @ViewBuilder
    private var diagnosticsSection: some View {
        Section("Scan Diagnostics (Debug)") {
            HStack {
                Button("Run Scan Diagnostics") {
                    Task {
                        isRunningDiagnostics = true
                        diagnosticsReport = await DiagnosticsService.buildReport(
                            items: cleanCoordinator.items,
                            skippedRoots: cleanCoordinator.skippedRoots.map(\.url)
                        )
                        isRunningDiagnostics = false
                    }
                }
                .disabled(isRunningDiagnostics || !cleanCoordinator.hasScannedOnce)
                if isRunningDiagnostics {
                    ProgressView().controlSize(.small)
                }
            }
            if !cleanCoordinator.hasScannedOnce {
                Text("Run a scan on the Clean tab first — diagnostics compares against its results.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let report = diagnosticsReport {
                LabeledContent("Scanned", value: ByteFormat.string(report.scannedBytes))
                LabeledContent("Safe", value: ByteFormat.string(report.safeBytes))
                LabeledContent("Review", value: ByteFormat.string(report.reviewBytes))
                LabeledContent("Skipped Locations", value: "\(report.skippedLocations.count)")
                ForEach(report.skippedLocations, id: \.self) { path in
                    Text(path).font(.caption).foregroundStyle(.secondary)
                }

                Text("Largest Undetected Areas").font(.subheadline.weight(.semibold))
                ForEach(report.largestUndetectedAreas.prefix(8)) { area in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("~/\(area.path)")
                            Text("\(ByteFormat.string(area.totalSize)) total · \(ByteFormat.string(area.detectedSize)) detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ByteFormat.string(area.undetectedSize))
                            .font(.callout.weight(.semibold))
                    }
                }
            }
        }
    }
    #endif
}

#Preview {
    SettingsView()
        .environment(CleanCoordinator())
}
