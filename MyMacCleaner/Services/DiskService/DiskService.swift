import Foundation

/// Snapshot of the boot volume's capacity, used by the Overview screen.
struct DiskUsage: Sendable, Equatable {
    let totalCapacity: Int64
    let availableCapacity: Int64

    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
}

enum DiskService {
    static func currentUsage(fileManager: FileManager = .default) -> DiskUsage? {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        guard let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity else {
            return nil
        }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return DiskUsage(totalCapacity: Int64(total), availableCapacity: available)
    }
}

/// Persists lightweight facts about the most recent scan so Overview has
/// something meaningful to show before the user scans again this launch.
enum ScanHistoryStore {
    private static let lastScanDateKey = "MyMacCleaner.lastScanDate"
    private static let lastCleanableBytesKey = "MyMacCleaner.lastCleanableBytes"

    static var lastScanDate: Date? {
        get { UserDefaults.standard.object(forKey: lastScanDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastScanDateKey) }
    }

    static var lastCleanableBytes: Int64 {
        get { Int64(UserDefaults.standard.double(forKey: lastCleanableBytesKey)) }
        set { UserDefaults.standard.set(Double(newValue), forKey: lastCleanableBytesKey) }
    }

    static func recordScan(cleanableBytes: Int64) {
        lastScanDate = Date()
        lastCleanableBytes = cleanableBytes
    }
}
