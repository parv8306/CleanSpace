import Foundation

/// An immutable snapshot of exactly what the Review screen shows and what will be acted on.
struct CleanupPlan: Equatable {
    struct MediaEntry: Identifiable, Equatable {
        let category: CleanupCategory
        let items: [MediaItem]
        var id: CleanupCategory { category }
        var bytes: Int64 { items.reduce(0) { $0 + $1.fileSize } }
    }

    struct MergeEntry: Identifiable, Equatable {
        let plan: ContactMergePlan
        let group: ContactGroup
        var id: String { plan.groupID }
        var keptName: String {
            group.contacts.first { $0.id == plan.nameSourceID }?.displayName ?? "Contact"
        }
    }

    var media: [MediaEntry] = []
    var contactDeletes: [ContactRecord] = []
    var merges: [MergeEntry] = []
    var events: [CalendarEventItem] = []

    var mediaIDs: [String] { media.flatMap { $0.items.map(\.id) } }
    var mediaCount: Int { media.reduce(0) { $0 + $1.items.count } }
    var mediaBytes: Int64 { media.reduce(0) { $0 + $1.bytes } }
    var contactsRemovedCount: Int { contactDeletes.count + merges.reduce(0) { $0 + $1.plan.removedCount } }
    var totalCount: Int { mediaCount + contactsRemovedCount + events.count }
    var hasContactChanges: Bool { !contactDeletes.isEmpty || !merges.isEmpty }
    var hasEventChanges: Bool { !events.isEmpty }
    /// Contacts and events have no Recently Deleted, so they get an extra confirmation.
    var hasPermanentChanges: Bool { hasContactChanges || hasEventChanges }
    var isEmpty: Bool { mediaCount == 0 && !hasContactChanges && !hasEventChanges }

    /// Order matters for de-duplication: a photo that is both "similar" and "blurry" is listed once.
    static let mediaOrder: [CleanupCategory] = [.duplicatePhotos, .similarPhotos, .blurryPhotos, .screenshots, .chatPhotos, .largeVideos]

    @MainActor
    static func build(from app: AppState, categories: Set<CleanupCategory>) -> CleanupPlan {
        var plan = CleanupPlan()
        var seen = Set<String>()
        for category in mediaOrder where categories.contains(category) {
            let ids = app.selection.ids(category)
            guard !ids.isEmpty else { continue }
            var items: [MediaItem] = []
            var local = Set<String>()
            for item in app.items(for: category) {
                guard ids.contains(item.id), !seen.contains(item.id), local.insert(item.id).inserted else { continue }
                items.append(item)
            }
            seen.formUnion(local)
            if !items.isEmpty { plan.media.append(MediaEntry(category: category, items: items)) }
        }

        if categories.contains(.duplicateContacts) {
            let deletes = app.selection.contactDeletes
            var records: [String: ContactRecord] = [:]
            for group in app.contacts.groups {
                for record in group.contacts where deletes.contains(record.id) { records[record.id] = record }
            }
            plan.contactDeletes = records.values.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            plan.merges = app.selection.contactMerges.values.compactMap { mergePlan in
                app.contacts.group(id: mergePlan.groupID).map { MergeEntry(plan: mergePlan, group: $0) }
            }
            .sorted { $0.keptName.localizedCaseInsensitiveCompare($1.keptName) == .orderedAscending }
        }

        if categories.contains(.calendarEvents) {
            let ids = app.selection.events
            plan.events = app.calendar.allItems.filter { ids.contains($0.id) }.sorted { $0.startDate > $1.startDate }
        }
        return plan
    }
}
