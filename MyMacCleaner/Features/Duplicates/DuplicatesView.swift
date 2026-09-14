import SwiftUI

/// Shows files that are confirmed byte-for-byte identical, grouped so the
/// user picks which single copy to keep. Nothing is removed without that
/// explicit per-group choice.
struct DuplicatesView: View {
    @Environment(\.appLanguage) private var language
    @State private var viewModel = DuplicatesViewModel()
    @State private var lastResult: CleanSummaryLite?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle(L("Duplicates", "중복 파일", for: language))
        .onAppear { viewModel.startScanIfNeeded() }
        .alert(L("Duplicates Removed", "중복 파일 삭제됨", for: language), isPresented: Binding(get: { lastResult != nil }, set: { if !$0 { lastResult = nil } })) {
            Button(L("OK", "확인", for: language)) { lastResult = nil }
        } message: {
            if let lastResult {
                Text(lastResult.failedCount == 0
                     ? L("Extra copies moved to Trash.", "여분의 복사본을 휴지통으로 이동했습니다.", for: language)
                     : L("\(lastResult.failedCount) item(s) could not be removed.", "\(lastResult.failedCount)개 항목을 삭제하지 못했습니다.", for: language))
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Duplicate Files", "중복 파일", for: language)).font(.title2.weight(.semibold))
                Text(L(
                    "Checked: \(viewModel.scannedFolders.map(\.lastPathComponent).joined(separator: ", "))",
                    "확인한 폴더: \(viewModel.scannedFolders.map(\.lastPathComponent).joined(separator: ", "))",
                    for: language
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.state == .scanning {
                ProgressView().controlSize(.small)
                Button(L("Cancel", "취소", for: language)) { viewModel.cancel() }
            } else {
                Button {
                    viewModel.startScan()
                } label: {
                    Label(L("Rescan", "다시 스캔", for: language), systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .scanning:
            VStack(spacing: 10) {
                ProgressView()
                Text(L("Comparing files by content…", "파일 내용을 비교하는 중…", for: language)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .cancelled where viewModel.groups.isEmpty:
            EmptyStateView(
                systemImage: "xmark.circle",
                title: L("Scan cancelled", "스캔이 취소됨", for: language),
                subtitle: L("Rescan to check for duplicates again.", "다시 스캔하면 중복 파일을 다시 확인할 수 있어요.", for: language)
            )

        case .completed, .cancelled:
            if viewModel.groups.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: L("No duplicates found", "중복 파일이 없습니다", for: language),
                    subtitle: L("Downloads and Desktop look duplicate-free.", "Downloads와 Desktop에 중복 파일이 없습니다.", for: language)
                )
            } else {
                List {
                    ForEach(viewModel.groups) { group in
                        DuplicateGroupSection(group: group, viewModel: viewModel) {
                            Task { lastResult = await viewModel.removeDuplicates(in: group) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct DuplicateGroupSection: View {
    @Environment(\.appLanguage) private var language
    let group: DuplicateGroup
    let viewModel: DuplicatesViewModel
    let onRemove: () -> Void
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(group.items) { item in
                HStack {
                    let isKept = viewModel.keepSelection[group.id] == item.url.path
                    Button {
                        viewModel.setKeep(item.url.path, for: group)
                    } label: {
                        Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isKept ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isKept
                          ? L("This copy will be kept", "이 복사본을 보관합니다", for: language)
                          : L("Keep this copy instead", "대신 이 복사본을 보관", for: language))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.url.lastPathComponent).lineLimit(1)
                        Text(item.url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(ByteFormat.string(item.size, language: language)).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text(L("Keep one copy, remove the rest", "하나만 남기고 나머지는 삭제", for: language)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Remove Duplicates", "중복 파일 삭제", for: language), role: .destructive, action: onRemove)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Image(systemName: "doc.on.doc")
                Text(L("\(group.items.count) copies", "복사본 \(group.items.count)개", for: language))
                Spacer()
                Text(L(
                    "Reclaim \(ByteFormat.string(group.reclaimableSize, language: language))",
                    "\(ByteFormat.string(group.reclaimableSize, language: language)) 확보 가능",
                    for: language
                )).foregroundStyle(.secondary)
            }
        }
    }
}
