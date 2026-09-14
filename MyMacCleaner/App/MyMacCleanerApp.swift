import SwiftUI

@main
struct MyMacCleanerApp: App {
    @AppStorage(appLanguageStorageKey) private var storedLanguage: AppLanguage = .system

    private var resolvedLanguage: AppLanguage { AppLanguage.resolved(from: storedLanguage) }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 860, minHeight: 560)
                .environment(\.appLanguage, resolvedLanguage)
                .environment(\.locale, resolvedLanguage.locale ?? .autoupdatingCurrent)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
