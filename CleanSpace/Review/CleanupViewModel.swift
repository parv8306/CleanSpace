import Foundation
import Observation

@Observable
@MainActor
final class CleanupViewModel {
    enum Stage: Equatable {
        case review
        case working(String)
        case done(CleanupSummary)
    }

    private(set) var stage: Stage = .review
    var notice: String?

    var isWorking: Bool {
        if case .working = stage { return true }
        return false
    }

    /// Runs the confirmed plan. Photos go first because iOS shows its own confirmation;
    /// if the user declines there, nothing else happens either.
    /// `thumbnails` are small JPEGs captured on the Review screen, keyed by photo ID, for history.
    func run(_ plan: CleanupPlan, app: AppState, thumbnails: [String: Data] = [:]) async {
        guard !isWorking, !plan.isEmpty else { return }
        notice = nil
        var summary = CleanupSummary()
        summary.storageBefore = app.storage
        var deletedMedia = Set<String>()

        if plan.mediaCount > 0 {
            stage = .working("Waiting for iOS to confirm")
            let outcome = await PhotoLibraryService.deleteAssets(ids: plan.mediaIDs)
            if outcome.deleted.isEmpty {
                stage = .review
                notice = outcome.userCancelled
                    ? "Nothing was deleted. iOS asked for confirmation and it wasn't given."
                    : (outcome.errorMessage ?? "Nothing could be deleted. Please try again.")
                return
            }
            deletedMedia = outcome.deleted
            for entry in plan.media {
                let removed = entry.items.filter { deletedMedia.contains($0.id) }
                if !removed.isEmpty {
                    let bytes = removed.reduce(Int64(0)) { $0 + $1.fileSize }
                    summary.removedByCategory[entry.category] = removed.count
                    summary.bytesByCategory[entry.category] = bytes
                    summary.bytesFreed += bytes
                }
            }
            summary.failedMedia = plan.mediaCount - deletedMedia.count
            if summary.failedMedia > 0 {
                summary.mediaMessage = outcome.errorMessage
                    ?? "Some items couldn't be removed. They may be shared, synced from another device, or already gone."
            }
        }

        if plan.hasContactChanges {
            stage = .working("Updating contacts")
            let deletes = Set(plan.contactDeletes.map(\.id))
            let merges = plan.merges.map(\.plan)
            let outcome = await Task.detached(priority: .userInitiated) {
                ContactService.apply(deletes: deletes, merges: merges)
            }.value
            summary.contactsRemoved = outcome.deleted + outcome.removedByMerge
            summary.contactGroupsMerged = outcome.mergedGroups
            summary.failedContacts = outcome.failed
        }

        var deletedEvents = Set<String>()
        if plan.hasEventChanges {
            stage = .working("Updating your calendar")
            let ids = Set(plan.events.map(\.id))
            let outcome = await Task.detached(priority: .userInitiated) { CalendarService.delete(ids: ids) }.value
            summary.eventsRemoved = outcome.deleted
            summary.failedEvents = outcome.failed
            deletedEvents = outcome.deletedIDs
        }

        // History keeps a thumbnail for each item iOS confirmed as deleted.
        var historyItems: [HistoryItem] = []
        var moreHistoryItems = 0
        var writes: [(UUID, Data)] = []
        var seen = Set<String>()
        for entry in plan.media {
            for item in entry.items where deletedMedia.contains(item.id) && seen.insert(item.id).inserted {
                guard historyItems.count < HistoryThumbnailStore.maxItemsPerCleanup else {
                    moreHistoryItems += 1
                    continue
                }
                let thumbnail = thumbnails[item.id]
                let historyItem = HistoryItem(id: UUID(), categoryRaw: entry.category.rawValue, bytes: item.fileSize,
                                              duration: item.duration, hasThumbnail: thumbnail != nil)
                if let thumbnail { writes.append((historyItem.id, thumbnail)) }
                historyItems.append(historyItem)
            }
        }
        let pendingWrites = writes
        await Task.detached(priority: .utility) {
            for (id, data) in pendingWrites { HistoryThumbnailStore.save(data, for: id) }
        }.value

        app.applyCleanup(summary: summary, deletedMedia: deletedMedia,
                         contactsChanged: plan.hasContactChanges, deletedEvents: deletedEvents,
                         historyItems: historyItems, moreHistoryItems: moreHistoryItems)
        stage = .done(summary)
    }
}
