import Foundation

/// A cluster of duplicate or visually similar photos. `items[0]` is always the recommended keeper.
struct PhotoGroup: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case duplicates   // identical fingerprint and dimensions
        case similar      // near-identical shots (bursts, re-edits, re-saves)

        var title: String {
            switch self {
            case .duplicates: "Duplicates"
            case .similar: "Similar shots"
            }
        }
    }

    let id: String
    let kind: Kind
    private(set) var items: [MediaItem]
    private(set) var bestID: String

    /// Returns nil when fewer than two photos remain (a "group" of one is not a group).
    init?(items: [MediaItem], kind: Kind, preferredBestID: String? = nil, id: String? = nil) {
        guard items.count >= 2 else { return nil }
        let ranked = items.sorted(by: PhotoRanking.isBetter)
        let best = preferredBestID.flatMap { wanted in ranked.first { $0.id == wanted } } ?? ranked[0]
        self.items = [best] + ranked.filter { $0.id != best.id }
        self.bestID = best.id
        self.kind = kind
        self.id = id ?? (items.map(\.id).min() ?? best.id)
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.fileSize } }
    var reclaimableItems: [MediaItem] { items.filter { $0.id != bestID } }
    var reclaimableBytes: Int64 { reclaimableItems.reduce(0) { $0 + $1.fileSize } }

    /// What we pre-select: everything except the keeper. Favorites are never pre-selected.
    var suggestedDeletionIDs: [String] {
        reclaimableItems.filter { !$0.isFavorite }.map(\.id)
    }

    func removing(_ ids: Set<String>) -> PhotoGroup? {
        let remaining = items.filter { !ids.contains($0.id) }
        return PhotoGroup(items: remaining, kind: kind,
                          preferredBestID: ids.contains(bestID) ? nil : bestID, id: id)
    }

    func withBest(_ itemID: String) -> PhotoGroup {
        PhotoGroup(items: items, kind: kind, preferredBestID: itemID, id: id) ?? self
    }
}

/// Local heuristics for choosing the photo to keep.
enum PhotoRanking {
    /// Strict weak ordering: `true` when `a` should be preferred over `b`.
    static func isBetter(_ a: MediaItem, _ b: MediaItem) -> Bool {
        if a.isFavorite != b.isFavorite { return a.isFavorite }            // the user already told us
        if a.isScreenshot != b.isScreenshot { return !a.isScreenshot }     // avoid keeping screenshots of photos
        if a.pixelCount != b.pixelCount { return a.pixelCount > b.pixelCount }
        let sa = sharpnessBucket(a.sharpness), sb = sharpnessBucket(b.sharpness)
        if sa != sb { return sa > sb }                                     // noticeably sharper wins
        let da = a.creationDate ?? .distantPast, db = b.creationDate ?? .distantPast
        if da != db { return da > db }                                     // newer (often the edited version)
        if a.fileSize != b.fileSize { return a.fileSize > b.fileSize }     // more detail retained
        return a.id < b.id
    }

    /// Buckets on a log scale so tiny sharpness differences between burst frames don't dominate.
    static func sharpnessBucket(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int((log2(value + 1) * 2).rounded(.down))
    }
}
