import SwiftUI

struct ApplicationsView: View {
    @Environment(\.appLanguage) private var language
    @State private var viewModel = ApplicationsViewModel()
    @State private var selection: InstalledApplication?
    @State private var showUninstallConfirmation = false
    @State private var includeLeftovers = true
    @State private var lastResult: CleanSummaryLite?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                list
            }
            .frame(minWidth: 380)

            detailPane
                .frame(minWidth: 300)
        }
        .navigationTitle(L("Applications", "애플리케이션", for: language))
        .onAppear { viewModel.loadIfNeeded() }
        .onChange(of: selection) { _, newValue in
            if let newValue { viewModel.select(newValue, language: language) }
        }
        .sheet(isPresented: $showUninstallConfirmation) {
            if let app = viewModel.selectedApp {
                UninstallConfirmationView(
                    app: app,
                    leftovers: viewModel.leftovers,
                    includeLeftovers: $includeLeftovers,
                    onCancel: { showUninstallConfirmation = false },
                    onConfirm: {
                        showUninstallConfirmation = false
                        Task {
                            lastResult = await viewModel.uninstall(app, includingLeftovers: includeLeftovers ? viewModel.leftovers : [])
                            selection = nil
                        }
                    }
                )
            }
        }
        .alert(L("Uninstall", "삭제", for: language), isPresented: Binding(get: { lastResult != nil }, set: { if !$0 { lastResult = nil } })) {
            Button(L("OK", "확인", for: language)) { lastResult = nil }
        } message: {
            if let lastResult {
                Text(lastResult.failedCount == 0
                     ? L("Moved to Trash.", "휴지통으로 이동했습니다.", for: language)
                     : L("Couldn't remove this app — it may still be running.", "앱을 삭제하지 못했습니다 — 아직 실행 중일 수 있습니다.", for: language))
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L("\(viewModel.apps.count) Applications", "애플리케이션 \(viewModel.apps.count)개", for: language)).font(.headline)
            Spacer()
            if viewModel.state == .loading { ProgressView().controlSize(.small) }
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.state == .loaded && viewModel.apps.isEmpty {
            EmptyStateView(
                systemImage: "square.grid.2x2",
                title: L("No applications found", "애플리케이션이 없습니다", for: language),
                subtitle: L(
                    "MyMacCleaner looks in /Applications and your home Applications folder.",
                    "MyMacCleaner는 /Applications와 홈 폴더의 Applications를 확인합니다.",
                    for: language
                )
            )
        } else {
            List(viewModel.apps, selection: $selection) { app in
                AppRow(app: app).tag(app)
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let app = viewModel.selectedApp {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "app.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text(app.name).font(.title3.weight(.semibold))
                if app.isRunning {
                    Label(L("Currently running", "현재 실행 중", for: language), systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                LabeledContent(L("Version", "버전", for: language), value: app.version ?? "—")
                LabeledContent(L("Size", "크기", for: language), value: ByteFormat.string(app.size, language: language))
                if let date = app.modificationDate {
                    LabeledContent(L("Last Modified", "마지막 수정", for: language), value: date.shortDisplayString(language: language))
                }

                if !viewModel.leftovers.isEmpty {
                    Divider()
                    Text(L("Related Files", "관련 파일", for: language)).font(.subheadline.weight(.semibold))
                    ForEach(viewModel.leftovers) { leftover in
                        HStack(alignment: .top) {
                            SafetyBadgeView(safety: leftover.safety)
                            Text(leftover.url.lastPathComponent).lineLimit(1)
                            Spacer()
                            Text(ByteFormat.string(leftover.size, language: language)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if app.isRunning {
                    Text(L("Quit \(app.name) before uninstalling.", "삭제하려면 먼저 \(app.name)을(를) 종료하세요.", for: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    showUninstallConfirmation = true
                } label: {
                    Label(L("Uninstall", "삭제", for: language), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.isRunning)
            }
            .padding(20)
        } else {
            EmptyStateView(
                systemImage: "hand.point.left",
                title: L("Select an app", "앱을 선택하세요", for: language),
                subtitle: L("Choose an application on the left to see its details.", "왼쪽에서 앱을 선택하면 자세한 정보를 볼 수 있어요.", for: language)
            )
        }
    }
}

private struct AppRow: View {
    @Environment(\.appLanguage) private var language
    let app: InstalledApplication

    var body: some View {
        HStack {
            Image(systemName: "app.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                if let version = app.version {
                    Text(L("Version \(version)", "버전 \(version)", for: language)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ByteFormat.string(app.size, language: language)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct UninstallConfirmationView: View {
    @Environment(\.appLanguage) private var language
    let app: InstalledApplication
    let leftovers: [ApplicationLeftover]
    @Binding var includeLeftovers: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash").font(.system(size: 32)).foregroundStyle(.tint)
            Text(L("Move \(app.name) to Trash?", "\(app.name)을(를) 휴지통으로 이동할까요?", for: language)).font(.title3.weight(.semibold))
            if !leftovers.isEmpty {
                Toggle(
                    L(
                        "Also remove \(leftovers.count) related file\(leftovers.count == 1 ? "" : "s") (\(ByteFormat.string(leftovers.reduce(0) { $0 + $1.size }, language: language)))",
                        "관련 파일 \(leftovers.count)개(\(ByteFormat.string(leftovers.reduce(0) { $0 + $1.size }, language: language)))도 함께 삭제",
                        for: language
                    ),
                    isOn: $includeLeftovers
                )
                .toggleStyle(.checkbox)
            }
            HStack {
                Button(L("Cancel", "취소", for: language), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Uninstall", "삭제", for: language), role: .destructive, action: onConfirm).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
