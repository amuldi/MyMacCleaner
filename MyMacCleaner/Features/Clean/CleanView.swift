import SwiftUI
import AppKit

/// The screen users spend the most time in: scan, review by category, then
/// clean. Every candidate is shown with its safety level so nothing is removed
/// as a surprise.
struct CleanView: View {
    @Environment(CleanCoordinator.self) private var coordinator
    @Environment(\.appLanguage) private var language
    @State private var showCleanConfirmation = false
    @State private var lastSummary: CleanSummary?
    @State private var isCleaning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle(L("Clean", "정리", for: language))
        .sheet(isPresented: $showCleanConfirmation) {
            CleanConfirmationView(
                bytes: coordinator.selectedBytes,
                count: coordinator.selectedItems.count,
                includesPermanentDeletion: coordinator.selectedItems.contains { $0.category.cleanupIsPermanentDeletion },
                onCancel: { showCleanConfirmation = false },
                onConfirm: {
                    showCleanConfirmation = false
                    Task {
                        isCleaning = true
                        lastSummary = await coordinator.performClean()
                        isCleaning = false
                    }
                }
            )
        }
        .alert(L("Clean Complete", "정리 완료", for: language), isPresented: Binding(
            get: { lastSummary != nil },
            set: { if !$0 { lastSummary = nil } }
        )) {
            Button(L("OK", "확인", for: language)) { lastSummary = nil }
        } message: {
            Text(summaryText)
        }
    }

    private var summaryText: String {
        guard let summary = lastSummary else { return "" }
        var text = L(
            "Freed \(ByteFormat.string(summary.freedBytes, language: language)) across \(summary.succeededCount) item\(summary.succeededCount == 1 ? "" : "s").",
            "\(summary.succeededCount)개 항목에서 \(ByteFormat.string(summary.freedBytes, language: language))를 확보했습니다.",
            for: language
        )
        if summary.failedCount > 0 {
            text += " " + L(
                "\(summary.failedCount) item\(summary.failedCount == 1 ? "" : "s") could not be removed.",
                "\(summary.failedCount)개 항목은 삭제하지 못했습니다.",
                for: language
            )
        }
        return text
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Find unnecessary files", "불필요한 파일 찾기", for: language)).font(.title2.weight(.semibold))
                Text(L("Application caches, logs, temporary files, and more.",
                       "앱 캐시, 로그, 임시 파일 등을 확인합니다.", for: language))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.hasScannedOnce, !coordinator.isScanning {
                Button {
                    coordinator.startScan(language: language)
                } label: {
                    Label(L("Scan Again", "다시 스캔", for: language), systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.scanState {
        case .idle:
            idleState
        case .scanning(let progress):
            scanningState(progress)
        case .cancelled:
            cancelledState
        case .completed:
            if coordinator.items.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: L("Your Mac looks clean.", "Mac이 깨끗한 상태예요.", for: language),
                    subtitle: L("Nothing unnecessary was found.", "불필요한 파일을 찾지 못했습니다.", for: language)
                )
            } else {
                resultsState
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Button(L("Scan", "스캔", for: language)) { coordinator.startScan(language: language) }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanningState(_ progress: ScanProgress) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(L("Scanning your Mac…", "Mac을 스캔하는 중…", for: language)).font(.headline)
            Text(progress.currentDescription.isEmpty ? " " : progress.currentDescription)
                .font(.callout).foregroundStyle(.secondary)
            Text(L(
                "\(progress.filesScanned) files analyzed · \(ByteFormat.string(progress.bytesFound, language: language)) found",
                "파일 \(progress.filesScanned)개 분석 · \(ByteFormat.string(progress.bytesFound, language: language)) 발견",
                for: language
            ))
                .font(.footnote).foregroundStyle(.secondary)
            Button(L("Cancel", "취소", for: language)) { coordinator.cancelScan() }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cancelledState: some View {
        VStack(spacing: 12) {
            Text(L("Scan cancelled", "스캔이 취소됨", for: language)).font(.headline)
            Text(L(
                "\(coordinator.items.count) items were found before cancelling.",
                "취소 전까지 \(coordinator.items.count)개 항목을 찾았습니다.",
                for: language
            ))
                .foregroundStyle(.secondary)
            Button(L("Scan Again", "다시 스캔", for: language)) { coordinator.startScan(language: language) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsState: some View {
        VStack(spacing: 0) {
            if !coordinator.skippedRoots.isEmpty {
                PermissionBannerView(skippedCount: coordinator.skippedRoots.count)
                    .padding([.horizontal, .top], 20)
            }

            VStack(spacing: 4) {
                Text(ByteFormat.string(coordinator.safeBytes, language: language))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(L("can be safely cleaned", "안전하게 정리할 수 있어요", for: language))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)

            List {
                ForEach(coordinator.groupedByCategory, id: \.category) { group in
                    CategorySection(category: group.category, items: group.items)
                }
            }
            .listStyle(.inset)

            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack {
            Text(L(
                "\(coordinator.selectedItems.count) items selected · \(ByteFormat.string(coordinator.selectedBytes, language: language))",
                "\(coordinator.selectedItems.count)개 항목 선택됨 · \(ByteFormat.string(coordinator.selectedBytes, language: language))",
                for: language
            ))
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
            Button {
                showCleanConfirmation = true
            } label: {
                if isCleaning {
                    ProgressView().controlSize(.small).frame(width: 40)
                } else {
                    Text(L("Clean", "정리", for: language)).frame(width: 40)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(coordinator.selectedItems.isEmpty || isCleaning)
        }
        .padding(16)
    }
}

private struct CategorySection: View {
    @Environment(CleanCoordinator.self) private var coordinator
    @Environment(\.appLanguage) private var language
    let category: CleanCategory
    let items: [ScannedItem]
    @State private var isExpanded = false

    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    /// Groups with a subcategory (currently only Xcode Files) get one more
    /// level of drill-down — e.g. "iOS Device Support" as its own disclosure
    /// full of the individual device folders — instead of a flat file list.
    private var hasSubgroups: Bool { items.contains { $0.subcategory != nil } }

    private var subgroups: [(key: String, items: [ScannedItem])] {
        Dictionary(grouping: items, by: { $0.subcategory ?? "" })
            .map { (key: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.items.reduce(0) { $0 + $1.size } > $1.items.reduce(0) { $0 + $1.size } }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if hasSubgroups {
                ForEach(subgroups, id: \.key) { group in
                    SubcategorySection(subcategoryKey: group.key, items: group.items)
                }
            } else {
                ForEach(items) { item in
                    ItemRow(item: item)
                }
            }
        } label: {
            HStack {
                Toggle(isOn: Binding(
                    get: { coordinator.isCategoryFullySelected(category) },
                    set: { coordinator.setSelected($0, forCategory: category) }
                )) {
                    Label(category.displayName(for: language), systemImage: category.systemImage)
                }
                .toggleStyle(.checkbox)
                Spacer()
                Text(ByteFormat.string(totalSize, language: language))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The extra drill-down level inside a category — e.g. "iOS Device Support"
/// inside "Xcode Files" — with its own select-all checkbox and size total.
private struct SubcategorySection: View {
    @Environment(CleanCoordinator.self) private var coordinator
    @Environment(\.appLanguage) private var language
    let subcategoryKey: String
    let items: [ScannedItem]
    @State private var isExpanded = false

    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    private var title: String {
        DeveloperDataKind(rawValue: subcategoryKey)?.displayName(for: language) ?? subcategoryKey
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(items) { item in
                ItemRow(item: item)
            }
        } label: {
            HStack {
                Toggle(isOn: Binding(
                    get: { coordinator.isFullySelected(items) },
                    set: { coordinator.setSelected($0, for: items) }
                )) {
                    Text(title)
                }
                .toggleStyle(.checkbox)
                Spacer()
                Text(ByteFormat.string(totalSize, language: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
    }
}

private struct ItemRow: View {
    @Environment(CleanCoordinator.self) private var coordinator
    @Environment(\.appLanguage) private var language
    let item: ScannedItem

    var body: some View {
        HStack(alignment: .top) {
            Toggle(isOn: Binding(
                get: { coordinator.isSelected(item) },
                set: { _ in coordinator.toggleSelection(item) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.url.lastPathComponent).lineLimit(1)
                        SafetyBadgeView(safety: item.safety)
                    }
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormat.string(item.size, language: language))
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help(L("Reveal in Finder", "Finder에서 보기", for: language))
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(L("Reveal in Finder", "Finder에서 보기", for: language)) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}

private struct CleanConfirmationView: View {
    @Environment(\.appLanguage) private var language
    let bytes: Int64
    let count: Int
    let includesPermanentDeletion: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            Text(L(
                "\(ByteFormat.string(bytes, language: language)) will be moved to Trash",
                "\(ByteFormat.string(bytes, language: language))가 휴지통으로 이동됩니다",
                for: language
            ))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(descriptionText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button(L("Cancel", "취소", for: language), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L("Clean", "정리", for: language), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 360)
    }

    private var descriptionText: String {
        var text = L(
            "\(count) item\(count == 1 ? "" : "s") selected.",
            "\(count)개 항목이 선택되었습니다.",
            for: language
        )
        if includesPermanentDeletion {
            text += " " + L(
                "Items already in the Trash will be permanently deleted.",
                "휴지통에 이미 있는 항목은 완전히 삭제됩니다.",
                for: language
            )
        }
        return text
    }
}
