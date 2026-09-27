import Foundation

/// Everything the user has marked. Nothing here is acted on until the Review screen is confirmed.
struct CleanupSelection: Equatable {
    var media: [CleanupCategory: Set<String>] = [:]
    var contactDeletes: Set<String> = []
    var contactMerges: [String: ContactMergePlan] = [:]
    var events: Set<String> = []

    func ids(_ category: CleanupCategory) -> Set<String> { media[category] ?? [] }

    func contains(_ id: String, in category: CleanupCategory) -> Bool {
        media[category]?.contains(id) ?? false
    }

    mutating func toggle(_ id: String, in category: CleanupCategory) {
        var set = media[category] ?? []
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        media[category] = set
    }

    mutating func select<S: Sequence>(_ ids: S, in category: CleanupCategory) where S.Element == String {
        media[category, default: []].formUnion(ids)
    }

    mutating func deselect<S: Sequence>(_ ids: S, in category: CleanupCategory) where S.Element == String {
        media[category]?.subtract(ids)
    }

    mutating func replace(_ ids: Set<String>, in category: CleanupCategory) {
        media[category] = ids
    }

    mutating func removeMedia(_ ids: Set<String>) {
        for key in Array(media.keys) { media[key]?.subtract(ids) }
    }

    mutating func clearMedia() { media = [:] }

    mutating func setMerge(_ plan: ContactMergePlan) {
        contactMerges[plan.groupID] = plan
        contactDeletes.subtract(plan.memberIDs)
    }

    mutating func removeMerge(groupID: String) { contactMerges[groupID] = nil }

    mutating func toggleContactDelete(_ id: String, groupID: String) {
        contactMerges[groupID] = nil
        if contactDeletes.contains(id) { contactDeletes.remove(id) } else { contactDeletes.insert(id) }
    }

    mutating func clearContacts() {
        contactDeletes = []
        contactMerges = [:]
    }

    mutating func toggleEvent(_ id: String) {
        if events.contains(id) { events.remove(id) } else { events.insert(id) }
    }

    mutating func clearEvents() { events = [] }

    var mediaCount: Int { media.values.reduce(0) { $0 + $1.count } }
    var contactChangeCount: Int { contactDeletes.count + contactMerges.count }
    var isEmpty: Bool { mediaCount == 0 && contactChangeCount == 0 && events.isEmpty }
}

struct CleanupSummary: Equatable, Sendable {
    var bytesFreed: Int64 = 0
    var removedByCategory: [CleanupCategory: Int] = [:]
    var contactsRemoved = 0
    var contactGroupsMerged = 0
    var failedMedia = 0
    var failedContacts = 0
    var eventsRemoved = 0
    var failedEvents = 0
    var videosCompressed = 0
    var bytesByCategory: [CleanupCategory: Int64] = [:]
    /// Storage as it was when the cleanup started, for the before/after gauge.
    var storageBefore: DeviceStorage?
    var mediaMessage: String?

    var mediaRemoved: Int { removedByCategory.values.reduce(0, +) }
    var totalRemoved: Int { mediaRemoved + contactsRemoved + eventsRemoved }
    var hadFailures: Bool { failedMedia > 0 || failedContacts > 0 || failedEvents > 0 }
    var didAnything: Bool { totalRemoved > 0 || contactGroupsMerged > 0 || videosCompressed > 0 }
}

/// One line of the cleanup history shown in Settings.
struct CleanupRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let date: Date
    let bytesFreed: Int64
    let mediaRemoved: Int
    let contactsRemoved: Int
    let eventsRemoved: Int
    let videosCompressed: Int
    /// Deleted photos, screenshots and videos with thumbnails (nil for records from older versions).
    var items: [HistoryItem]?
    /// Items deleted beyond the thumbnail limit.
    var moreItemCount: Int?

    init(summary: CleanupSummary, date: Date = Date(), items: [HistoryItem] = [], moreItemCount: Int = 0) {
        self.items = items
        self.moreItemCount = moreItemCount
        self.date = date
        bytesFreed = summary.bytesFreed
        mediaRemoved = summary.mediaRemoved
        contactsRemoved = summary.contactsRemoved
        eventsRemoved = summary.eventsRemoved
        videosCompressed = summary.videosCompressed
    }

    var description: String {
        var parts: [String] = []
        if mediaRemoved > 0 { parts.append(Format.count(mediaRemoved, "photo or video", "photos and videos")) }
        if videosCompressed > 0 { parts.append(Format.count(videosCompressed, "video compressed", "videos compressed")) }
        if contactsRemoved > 0 { parts.append(Format.count(contactsRemoved, "contact")) }
        if eventsRemoved > 0 { parts.append(Format.count(eventsRemoved, "event")) }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}
