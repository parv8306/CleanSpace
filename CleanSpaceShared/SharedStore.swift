import Foundation

/// The few numbers the widget shows besides live storage. The app writes them into the App Group
/// container; the widget only reads. Nothing else is shared.
struct StorageSnapshot: Codable, Equatable, Sendable {
    var freeableBytes: Int64?
    var lastScan: Date?
    var lifetimeFreedBytes: Int64
    var updated: Date
}

enum SharedStore {
    /// Info.plist key whose value is the App Group identifier (set from the CLEANSPACE_APP_GROUP build setting).
    static let appGroupInfoKey = "CleanSpaceAppGroup"
    private static let snapshotKey = "cleanspace.widgetSnapshot"

    static var appGroupID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    private static var defaults: UserDefaults? {
        appGroupID.flatMap { UserDefaults(suiteName: $0) }
    }

    static func read() -> StorageSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(StorageSnapshot.self, from: data)
    }

    static func write(_ snapshot: StorageSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}
