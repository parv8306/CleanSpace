import Foundation

struct DeviceStorage: Equatable, Sendable {
    let total: Int64
    let available: Int64

    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
}

enum StorageService {
    enum StorageError: Error { case unavailable }

    /// Reads real volume capacity from iOS. `volumeAvailableCapacityForImportantUsage` matches what
    /// the Settings app reports as available (it includes purgeable space iOS can reclaim on demand).
    static func current() throws -> DeviceStorage {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let basic = Int64(values.volumeAvailableCapacity ?? 0)
        let available = important > 0 ? important : basic
        guard total > 0 else { throw StorageError.unavailable }
        return DeviceStorage(total: total, available: min(available, total))
    }
}
