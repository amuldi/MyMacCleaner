import Foundation
import Observation

@MainActor
@Observable
final class ApplicationsViewModel {
    enum State: Equatable { case idle, loading, loaded }

    private(set) var state: State = .idle
    private(set) var apps: [InstalledApplication] = []
    private(set) var selectedApp: InstalledApplication?
    private(set) var leftovers: [ApplicationLeftover] = []
    private var loadTask: Task<Void, Never>?

    func loadIfNeeded() {
        guard state == .idle else { return }
        refresh()
    }

    func refresh() {
        loadTask?.cancel()
        state = .loading
        loadTask = Task {
            let found = await ApplicationService.installedApplications()
            if Task.isCancelled { return }
            apps = found
            state = .loaded
        }
    }

    func select(_ app: InstalledApplication, language: AppLanguage) {
        selectedApp = app
        leftovers = ApplicationService.leftovers(for: app, language: language)
    }

    /// Moves the app bundle (and, if requested, its related files) to the
    /// Trash. Refuses outright if the app is currently running — quitting it
    /// first is the user's call, never something this makes for them.
    @discardableResult
    func uninstall(_ app: InstalledApplication, includingLeftovers leftoversToRemove: [ApplicationLeftover]) async -> CleanSummaryLite {
        guard !app.isRunning else {
            return CleanSummaryLite(succeededCount: 0, failedCount: 1)
        }

        var urls = [app.bundleURL]
        urls.append(contentsOf: leftoversToRemove.map(\.url))
        let results = await CleanupService.moveToTrash(urls)

        apps.removeAll { $0.id == app.id }
        if selectedApp?.id == app.id {
            selectedApp = nil
            leftovers = []
        }

        let succeeded = results.filter(\.success).count
        return CleanSummaryLite(succeededCount: succeeded, failedCount: results.count - succeeded)
    }
}
