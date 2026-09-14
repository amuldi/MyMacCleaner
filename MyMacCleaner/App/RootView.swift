import SwiftUI

/// Top-level sidebar destinations for the app.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case clean
    case largeFiles
    case applications
    case duplicates
    case settings

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .overview: return L("Overview", "개요", for: language)
        case .clean: return L("Clean", "정리", for: language)
        case .largeFiles: return L("Large Files", "대용량 파일", for: language)
        case .applications: return L("Applications", "애플리케이션", for: language)
        case .duplicates: return L("Duplicates", "중복 파일", for: language)
        case .settings: return L("Settings", "설정", for: language)
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .clean: return "sparkles"
        case .largeFiles: return "doc.badge.gearshape"
        case .applications: return "square.grid.2x2"
        case .duplicates: return "doc.on.doc"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(\.appLanguage) private var language
    @State private var selection: SidebarItem? = .overview
    @State private var cleanCoordinator = CleanCoordinator()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title(for: language), systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewView(onScan: {
                    cleanCoordinator.startScan(language: language)
                    selection = .clean
                })
                .environment(cleanCoordinator)
            case .clean:
                CleanView()
                    .environment(cleanCoordinator)
            case .largeFiles:
                LargeFilesView()
            case .applications:
                ApplicationsView()
            case .duplicates:
                DuplicatesView()
            case .settings:
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
}
