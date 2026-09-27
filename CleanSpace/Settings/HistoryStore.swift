import Foundation

/// One deleted photo, screenshot or video shown in Cleanup History.
struct HistoryItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let categoryRaw: String
    let bytes: Int64
    let duration: Double
    let hasThumbnail: Bool

    var category: CleanupCategory? { CleanupCategory(rawValue: categoryRaw) }
    var isVideo: Bool { category == .largeVideos || duration > 0 }
}

/// Small JPEG thumbnails of deleted items, captured before deletion (afterwards the photo is gone).
/// Stored only on this iPhone in Application Support, removed when history is cleared.
enum HistoryThumbnailStore {
    static let maxItemsPerCleanup = 60

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CleanupHistory", isDirectory: true)
    }

    private static func url(for id: UUID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).jpg")
    }

    static func save(_ data: Data, for id: UUID) {
        guard let directory, let url = url(for: id) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func data(for id: UUID) -> Data? {
        guard let url = url(for: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func delete(_ ids: [UUID]) {
        for id in ids {
            if let url = url(for: id) { try? FileManager.default.removeItem(at: url) }
        }
    }

    static func deleteAll() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}
