import Foundation

/// A minimal outcome summary shared by the Applications and Duplicates
/// features (the full `CleanSummary` used by Clean also tracks freed bytes and
/// per-item failures, which those two simpler flows don't need).
struct CleanSummaryLite: Equatable {
    let succeededCount: Int
    let failedCount: Int
}
