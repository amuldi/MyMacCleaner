import SwiftUI
import AppKit

/// Lets the user find the biggest things on disk. Nothing here is deleted
/// automatically — the user reveals, reviews, and decides for each item.
struct LargeFilesView: View {
    @Environment(\.appLanguage) private var language
    @State private var viewModel = LargeFilesViewModel()
    @State private var selection: LargeFileItem?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                list
            }
            .frame(minWidth: 420)

            Group {
                if let selection {
                    detail(for: selection)
                } else {
                    EmptyStateView(
                        systemImage: "doc.text.magnifyingglass",
                        title: L("Select a file", "파일을 선택하세요", for: language),
                        subtitle: L("Choose an item on the left to see its details.", "왼쪽에서 항목을 선택하면 자세한 정보를 볼 수 있어요.", for: language)
                    )
                }
            }
            .frame(minWidth: 260)
        }
        .navigationTitle(L("Large Files", "대용량 파일", for: language))
        .onAppear { viewModel.startScanIfNeeded() }
    }

    private var header: some View {
        HStack {
            Picker(L("Show files larger than", "이보다 큰 파일 표시", for: language), selection: $viewModel.threshold) {
                ForEach(LargeFileThreshold.allCases) { threshold in
                    Text(threshold.label).tag(threshold)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

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
        .padding(16)
    }

    @ViewBuilder
    private var list: some View {
        switch viewModel.state {
        case .idle, .scanning:
            VStack(spacing: 10) {
                ProgressView()
                Text(L("Looking for large files…", "대용량 파일을 찾는 중…", for: language)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .cancelled where viewModel.results.isEmpty:
            EmptyStateView(
                systemImage: "xmark.circle",
                title: L("Scan cancelled", "스캔이 취소됨", for: language),
                subtitle: L("Rescan to look for large files again.", "다시 스캔하면 대용량 파일을 다시 찾을 수 있어요.", for: language)
            )

        case .completed, .cancelled:
            if viewModel.results.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: L("No large files found", "대용량 파일이 없습니다", for: language),
                    subtitle: L(
                        "Nothing on your Mac is larger than \(viewModel.threshold.label).",
                        "\(viewModel.threshold.label)보다 큰 파일이 없습니다.",
                        for: language
                    )
                )
            } else {
                List(viewModel.results, selection: $selection) { item in
                    LargeFileRow(item: item).tag(item)
                }
                .listStyle(.inset)
            }
        }
    }

    private func detail(for item: LargeFileItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: item.isDirectory ? "app.badge" : "doc")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(item.url.lastPathComponent)
                .font(.title3.weight(.semibold))
                .lineLimit(2)

            LabeledContent(L("Size", "크기", for: language), value: ByteFormat.string(item.size, language: language))
            LabeledContent(L("Path", "경로", for: language), value: item.url.deletingLastPathComponent().path)
                .lineLimit(3)
            if let date = item.modificationDate {
                LabeledContent(L("Last Modified", "마지막 수정", for: language), value: date.shortDisplayString(language: language))
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label(L("Reveal in Finder", "Finder에서 보기", for: language), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
    }
}

private struct LargeFileRow: View {
    @Environment(\.appLanguage) private var language
    let item: LargeFileItem

    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "app.badge" : "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(item.size, language: language)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
