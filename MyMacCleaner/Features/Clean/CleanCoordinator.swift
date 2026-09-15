import Foundation
import Observation

/// Drives a Clean scan and holds its results. Shared between the Overview and
/// Clean screens (via `@Environment`) so "Scan" on Overview and the Clean tab
/// stay in sync without duplicating state.
@MainActor
@Observable
final class CleanCoordinator {
    enum ScanState: Equatable {
        case idle
        case scanning(ScanProgress)
        case completed
        case cancelled
    }

    private(set) var scanState: ScanState = .idle
    private(set) var items: [ScannedItem] = []
    private(set) var skippedRoots: [SkippedRoot] = []
    private(set) var selection: Set<String> = []
    private(set) var lastScanCompletedAt: Date?

    private var scanTask: Task<Void, Never>?
    private let engine = ScannerEngine()

    struct SkippedRoot: Identifiable {
        let id = UUID()
        let url: URL
        let reason: SkipReason
    }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    var hasScannedOnce: Bool { scanState != .idle }

    var groupedByCategory: [(category: CleanCategory, items: [ScannedItem])] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return CleanCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items.sorted { $0.size > $1.size })
        }
    }

    var totalFoundBytes: Int64 { items.reduce(0) { $0 + $1.size } }
    var safeBytes: Int64 { items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size } }
    /// Found, but not auto-selected — the user decides after reviewing what's
    /// actually inside (see product spec §14: "Needs Review" is its own
    /// bucket, distinct from both "Safe to Clean" and disk usage overall).
    var reviewBytes: Int64 { items.filter { $0.safety == .review }.reduce(0) { $0 + $1.size } }
    var selectedItems: [ScannedItem] { items.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    /// `roots` defaults to the real scan locations; tests inject a fixture
    /// set so they never touch the actual user's home folder.
    func startScan(roots: [FileClassifier.ScanRoot] = FileClassifier.scanRoots(), language: AppLanguage = .english) {
        cancelScan()
        items = []
        skippedRoots = []
        selection = []
        scanState = .scanning(ScanProgress())

        scanTask = Task {
            let stream = await engine.scan(roots: roots, language: language)
            for await event in stream {
                if Task.isCancelled { return }
                handle(event)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning { scanState = .cancelled }
    }

    func isSelected(_ item: ScannedItem) -> Bool { selection.contains(item.id) }

    func toggleSelection(_ item: ScannedItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func setSelected(_ selected: Bool, forCategory category: CleanCategory) {
        for item in items where item.category == category {
            if selected { selection.insert(item.id) } else { selection.remove(item.id) }
        }
    }

    /// Selects or deselects an arbitrary group of items at once — used by the
    /// subcategory-level "select all" checkbox (e.g. everything under
    /// "iOS Device Support") in the Clean detail list.
    func setSelected(_ selected: Bool, for items: [ScannedItem]) {
        for item in items {
            if selected { selection.insert(item.id) } else { selection.remove(item.id) }
        }
    }

    /// Whether none, some, or all of a group are selected — used to show a
    /// "mixed" checkbox for a category like Developer Data, where the SAFE
    /// build data is auto-selected but the REVIEW package caches inside the
    /// same category aren't. A plain on/off checkbox would otherwise look
    /// fully unchecked even while part of the category counts toward the
    /// selected total, which reads as a bug rather than a mix.
    func selectionState(for items: [ScannedItem]) -> SelectionState {
        guard !items.isEmpty else { return .none }
        let selectedCount = items.count { selection.contains($0.id) }
        if selectedCount == 0 { return .none }
        if selectedCount == items.count { return .all }
        return .partial
    }

    func selectionState(forCategory category: CleanCategory) -> SelectionState {
        selectionState(for: items.filter { $0.category == category })
    }

    /// Moves every selected item to the Trash (or, for items already in the
    /// Trash, empties them permanently). Returns a plain summary for the UI —
    /// individual failures never abort the batch.
    @discardableResult
    func performClean() async -> CleanSummary {
        let toTrash = selectedItems.filter { !$0.category.cleanupIsPermanentDeletion }
        let toDeletePermanently = selectedItems.filter { $0.category.cleanupIsPermanentDeletion }

        async let trashResults = CleanupService.moveToTrash(toTrash.map(\.url))
        async let permanentResults = CleanupService.permanentlyDelete(toDeletePermanently.map(\.url))
        let allResults = await trashResults + (await permanentResults)

        let succeededPaths = Set(allResults.filter(\.success).map { $0.url.path })
        let freedBytes = selectedItems
            .filter { succeededPaths.contains($0.url.path) }
            .reduce(Int64(0)) { $0 + $1.size }

        items.removeAll { succeededPaths.contains($0.url.path) }
        selection.subtract(succeededPaths)
        ScanHistoryStore.recordScan(cleanableBytes: safeBytes)

        return CleanSummary(
            succeededCount: succeededPaths.count,
            failedCount: allResults.count - succeededPaths.count,
            freedBytes: freedBytes,
            failures: allResults.filter { !$0.success }
        )
    }

    private func handle(_ event: ScanEvent) {
        switch event {
        case .progress(let progress):
            scanState = .scanning(progress)
        case .item(let item):
            guard item.safety != .protected else { return } // defense-in-depth; never surfaced.
            items.append(item)
            if item.safety == .safe { selection.insert(item.id) }
        case .rootSkipped(let url, let reason):
            skippedRoots.append(SkippedRoot(url: url, reason: reason))
        case .finished:
            scanState = .completed
            lastScanCompletedAt = Date()
            ScanHistoryStore.recordScan(cleanableBytes: safeBytes)
        case .cancelled:
            scanState = .cancelled
        }
    }
}

enum SelectionState { case none, partial, all }

struct CleanSummary: Equatable {
    let succeededCount: Int
    let failedCount: Int
    let freedBytes: Int64
    let failures: [CleanupResult]

    static func == (lhs: CleanSummary, rhs: CleanSummary) -> Bool {
        lhs.succeededCount == rhs.succeededCount && lhs.failedCount == rhs.failedCount && lhs.freedBytes == rhs.freedBytes
    }
}
