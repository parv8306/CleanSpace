import Foundation
import Observation
import Photos
import WidgetKit

/// App-wide state: permissions, scan results, the selection, navigation, the vault and history.
/// Views read it from the environment; heavy work happens in the services, never here.
@Observable
@MainActor
final class AppState {
    let permissions = PermissionCenter()
    let similar = SimilarPhotosModel()
    let screenshots = MediaListModel(kind: .screenshots)
    let videos = MediaListModel(kind: .videos)
    let contacts = ContactsModel()
    let calendar = CalendarModel()
    let vaultLock = VaultLock()
    let vault = VaultModel()

    private(set) var storage: DeviceStorage?
    private(set) var storageErrorMessage: String?
    var selection = CleanupSelection()
    var path: [Route] = []
    var review: ReviewRequest?
    var permissionPrompt: PermissionKind?
    var showOnboarding: Bool
    private(set) var lastScanDate: Date?
    private(set) var lifetimeFreedBytes: Int64
    private(set) var history: [CleanupRecord]

    @ObservationIgnored private var pendingPrompts: [PermissionKind] = []
    /// Suggested picks from the last scan. They're applied only when the person opens that
    /// category, so finishing a scan never selects anything by itself.
    @ObservationIgnored private var pendingSuggestions: [CleanupCategory: Set<String>] = [:]
    /// What Quick Clean added to the selection. If the Review screen is closed without cleaning,
    /// exactly these are deselected again; anything the person picked themselves stays.
    @ObservationIgnored private var quickCleanAdded: [CleanupCategory: Set<String>]?
    @ObservationIgnored private var hasLaunched = false
    @ObservationIgnored private var scanAllInFlight = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastScan = "cleanspace.lastScanDate"
        static let freed = "cleanspace.lifetimeFreedBytes"
        static let history = "cleanspace.history"
        static let onboarded = "cleanspace.onboarded"
    }

    init() {
        let defaults = UserDefaults.standard
        lastScanDate = defaults.object(forKey: Keys.lastScan) as? Date
        lifetimeFreedBytes = Int64(defaults.integer(forKey: Keys.freed))
        showOnboarding = !defaults.bool(forKey: Keys.onboarded)
        if let data = defaults.data(forKey: Keys.history),
           let saved = try? JSONDecoder().decode([CleanupRecord].self, from: data) {
            history = saved
        } else {
            history = []
        }

        similar.onFinished = { [weak self] result in self?.similarFinished(result) }
        screenshots.onFinished = { [weak self] in self?.mediaListFinished(.screenshots) }
        videos.onFinished = { [weak self] in self?.mediaListFinished(.largeVideos) }
        contacts.onFinished = { [weak self] in self?.contactsFinished() }
        calendar.onFinished = { [weak self] in self?.calendarFinished() }
    }

    // MARK: Lifecycle

    func launch() {
        guard !hasLaunched else { return }
        hasLaunched = true
        refreshStorage()
        permissions.refresh()
        // Results are never persisted, so estimates are rebuilt on launch. Scanning only reads;
        // nothing is removed without the Review screen.
        if !showOnboarding && permissions.anyReadable {
            scanAll()
        }
        publishWidgetSnapshot()
    }

    func completeOnboarding() {
        showOnboarding = false
        defaults.set(true, forKey: Keys.onboarded)
    }

    func didBecomeActive() {
        guard hasLaunched else { return }
        refreshStorage()
        let changed = permissions.refresh()
        for kind in changed { handleAccessChange(kind) }
    }

    /// The vault relocks and forgets decrypted data whenever CleanSpace leaves the screen.
    func didEnterBackground() {
        vaultLock.lock()
        vault.clear()
        publishWidgetSnapshot()
    }

    private func handleAccessChange(_ kind: PermissionKind) {
        let state = permissions.state(kind)
        switch kind {
        case .photos:
            if state.canRead {
                scanPhotos()
            } else {
                similar.reset(); screenshots.reset(); videos.reset()
                selection.clearMedia()
            }
        case .contacts:
            if state.canRead {
                scanContacts()
            } else {
                contacts.reset()
                selection.clearContacts()
            }
        case .calendar:
            if state.canRead {
                scanCalendar()
            } else {
                calendar.reset()
                selection.clearEvents()
            }
        }
    }

    func requestAccess(_ kind: PermissionKind) async {
        let state = await permissions.request(kind)
        guard state.canRead else { return }
        // Returning from the system alert may already have triggered a scan via didBecomeActive.
        switch kind {
        case .photos: if !similar.phase.isScanning { scanPhotos() }
        case .contacts: if !contacts.phase.isScanning { scanContacts() }
        case .calendar: if !calendar.phase.isScanning { scanCalendar() }
        }
    }

    // MARK: Scan Now

    /// Scan Now asks only for Photos (the big win). Contacts and Calendar are offered when the
    /// person opens those rows, so nobody faces three permission prompts in a row.
    func scanNowTapped() {
        pendingPrompts = permissions.photos == .notDetermined ? [.photos] : []
        if let first = pendingPrompts.first {
            pendingPrompts.removeFirst()
            permissionPrompt = first
        } else {
            scanAll()
        }
    }

    func permissionPromptDismissed() {
        if let next = pendingPrompts.first {
            pendingPrompts.removeFirst()
            permissionPrompt = next
        } else {
            scanAll()
        }
    }

    func scanAll() {
        refreshStorage()
        var started = false
        if permissions.photos.canRead { scanPhotos(); started = true }
        if permissions.contacts.canRead { scanContacts(); started = true }
        if permissions.calendar.canRead { scanCalendar(); started = true }
        scanAllInFlight = started
    }

    func scanPhotos() {
        similar.scan()
        screenshots.scan()
        videos.scan()
    }

    func scanContacts() { contacts.scan() }
    func scanCalendar() { calendar.scan() }

    /// Opening a cleaner that has no results yet starts its scan.
    func ensureScanned(_ category: CleanupCategory) {
        guard permissions.state(category.permission).canRead else { return }
        switch category {
        case .similarPhotos, .blurryPhotos, .duplicatePhotos, .chatPhotos:
            if !similar.hasResults && !similar.phase.isScanning { similar.scan() }
        case .screenshots:
            if !screenshots.hasResults && !screenshots.phase.isScanning { screenshots.scan() }
        case .largeVideos:
            if !videos.hasResults && !videos.phase.isScanning { videos.scan() }
        case .duplicateContacts:
            if !contacts.hasResults && !contacts.phase.isScanning { contacts.scan() }
        case .calendarEvents:
            if !calendar.hasResults && !calendar.phase.isScanning { calendar.scan() }
        }
    }

    func cancelScans() {
        similar.cancel()
        screenshots.cancel()
        videos.cancel()
        contacts.cancel()
        calendar.cancel()
        scanAllInFlight = false
    }

    func photoLibrarySelectionChanged() {
        permissions.refresh()
        if permissions.photos.canRead { scanPhotos() }
    }

    func refreshStorage() {
        do {
            storage = try StorageService.current()
            storageErrorMessage = nil
        } catch {
            storageErrorMessage = "iOS didn't report storage figures right now."
        }
    }

    // MARK: Scan completion

    private func similarFinished(_ result: SimilarScanResult) {
        let blurryIDs = Set(result.blurry.map(\.id))
        // Fresh results: pre-select everything except each group's keeper (and favorites).
        let chatIDs = Set(result.chatPhotos.map(\.id))
        // Nothing is selected when a scan finishes. Keep only what the person had already chosen
        // (if those photos still qualify) and hold the suggestions until the category is opened.
        // The copy a Duplicate group keeps is never suggested in Similar Photos.
        let duplicateKeepers = Set(result.duplicateGroups.map(\.bestID))
        let similarIDs = Set(result.groups.flatMap { $0.items.map(\.id) })
        let duplicateIDs = Set(result.duplicateGroups.flatMap { $0.items.map(\.id) })
        selection.replace(selection.ids(.similarPhotos).intersection(similarIDs), in: .similarPhotos)
        selection.replace(selection.ids(.duplicatePhotos).intersection(duplicateIDs), in: .duplicatePhotos)
        pendingSuggestions[.similarPhotos] = result.suggestedIDs.subtracting(duplicateKeepers)
        pendingSuggestions[.duplicatePhotos] = result.duplicateSuggestedIDs
        selection.replace(selection.ids(.blurryPhotos).intersection(blurryIDs), in: .blurryPhotos)
        selection.replace(selection.ids(.chatPhotos).intersection(chatIDs), in: .chatPhotos)
        scanCompleted()
    }

    private func mediaListFinished(_ category: CleanupCategory) {
        let model = category == .screenshots ? screenshots : videos
        let valid = Set(model.items.map(\.id))
        selection.replace(selection.ids(category).intersection(valid), in: category)
        scanCompleted()
    }

    private func contactsFinished() {
        let valid = Set(contacts.groups.flatMap(\.memberIDs))
        selection.contactDeletes.formIntersection(valid)
        for (groupID, plan) in selection.contactMerges {
            let group = contacts.group(id: groupID)
            if group == nil || Set(group?.memberIDs ?? []) != Set(plan.memberIDs) {
                selection.removeMerge(groupID: groupID)
            }
        }
        scanCompleted()
    }

    private func calendarFinished() {
        let valid = Set(calendar.allItems.map(\.id))
        selection.events.formIntersection(valid)
        scanCompleted()
    }

    private func scanCompleted() {
        if scanAllInFlight, !isScanning {
            scanAllInFlight = false
            let now = Date()
            lastScanDate = now
            defaults.set(now, forKey: Keys.lastScan)
        }
        if !isScanning { publishWidgetSnapshot() }
    }

    // MARK: Derived numbers

    var isScanning: Bool {
        similar.phase.isScanning || screenshots.phase.isScanning || videos.phase.isScanning
            || contacts.phase.isScanning || calendar.phase.isScanning
    }

    var hasAnyResults: Bool {
        similar.hasResults || screenshots.hasResults || videos.hasResults
            || contacts.hasResults || calendar.hasResults
    }

    /// One honest status for the whole scan. "Complete" only when every started scan finished.
    enum ScanStatus: Equatable {
        case idle
        case scanning(done: Int, total: Int, label: String)
        case analyzing(String)
        case complete(Date?)
        case failed(String)
    }

    var scanStatus: ScanStatus {
        let photoPhases = [similar.phase, screenshots.phase, videos.phase]
        if let counts = similar.phase.counts {
            return .scanning(done: counts.done, total: counts.total, label: "photos")
        }
        if let counts = videos.phase.counts, counts.total > 0 {
            return .scanning(done: counts.done, total: counts.total, label: "videos")
        }
        if let counts = screenshots.phase.counts, counts.total > 0 {
            return .scanning(done: counts.done, total: counts.total, label: "screenshots")
        }
        if similar.phase.isAnalyzing { return .analyzing("Finding duplicates and look-alikes") }
        if photoPhases.contains(where: \.isScanning) { return .analyzing("Measuring files") }
        if contacts.phase.isScanning { return .analyzing("Comparing contacts") }
        if calendar.phase.isScanning { return .analyzing("Checking your calendar") }
        let all = photoPhases + [contacts.phase, calendar.phase]
        if let message = all.compactMap(\.failureMessage).first { return .failed(message) }
        return hasAnyResults ? .complete(lastScanDate) : .idle
    }

    var overallScanProgress: Double? {
        let phases = [similar.phase, screenshots.phase, videos.phase, contacts.phase, calendar.phase].filter(\.isScanning)
        guard !phases.isEmpty else { return nil }
        let fractions = phases.map { $0.fraction ?? 0 }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    var scanStatusLine: String {
        if let counts = similar.phase.counts, counts.total > 0 {
            return "Comparing photos: \(counts.done.formatted()) of \(counts.total.formatted())"
        }
        if let counts = videos.phase.counts, counts.total > 0 {
            return "Measuring videos: \(counts.done.formatted()) of \(counts.total.formatted())"
        }
        if screenshots.phase.isScanning { return "Finding screenshots" }
        if contacts.phase.isScanning { return "Comparing contacts" }
        if calendar.phase.isScanning { return "Checking your calendar" }
        return "Getting ready"
    }

    func items(for category: CleanupCategory) -> [MediaItem] {
        switch category {
        case .duplicatePhotos: similar.duplicateItems
        case .similarPhotos: similar.allItems
        case .blurryPhotos: similar.blurry
        case .chatPhotos: similar.chatPhotos
        case .screenshots: screenshots.items
        case .largeVideos: videos.items
        case .duplicateContacts, .calendarEvents: []
        }
    }

    /// Everything the scans suggest could go, counted once even when a photo is in two categories.
    var potentialBytes: Int64 {
        var sizes: [String: Int64] = [:]
        for group in similar.groups + similar.duplicateGroups {
            for item in group.reclaimableItems { sizes[item.id] = item.fileSize }
        }
        for item in similar.chatPhotos { sizes[item.id] = item.fileSize }
        for item in similar.blurry { sizes[item.id] = item.fileSize }
        for item in screenshots.items { sizes[item.id] = item.fileSize }
        for item in videos.largeVideos { sizes[item.id] = item.fileSize }
        return sizes.values.reduce(0, +)
    }

    func selectedBytes(in category: CleanupCategory) -> Int64 {
        let ids = selection.ids(category)
        guard !ids.isEmpty else { return 0 }
        return items(for: category).reduce(0) { ids.contains($1.id) ? $0 + $1.fileSize : $0 }
    }

    func selectedCount(in category: CleanupCategory) -> Int {
        switch category {
        case .duplicateContacts:
            return selection.contactDeletes.count + selection.contactMerges.values.reduce(0) { $0 + $1.removedCount }
        case .calendarEvents:
            return selection.events.count
        default:
            return selection.ids(category).count
        }
    }

    var selectedMediaIDs: Set<String> {
        selection.media.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    var totalSelectedBytes: Int64 {
        let ids = selectedMediaIDs
        guard !ids.isEmpty else { return 0 }
        var sizes: [String: Int64] = [:]
        for category in CleanupCategory.mediaCategories {
            for item in items(for: category) where ids.contains(item.id) { sizes[item.id] = item.fileSize }
        }
        return sizes.values.reduce(0, +)
    }

    var totalSelectedCount: Int {
        selectedMediaIDs.count + selectedCount(in: .duplicateContacts) + selectedCount(in: .calendarEvents)
    }

    func status(for category: CleanupCategory) -> CategoryStatus {
        switch permissions.state(category.permission) {
        case .notDetermined: return .needsAccess
        case .denied, .restricted: return .accessDenied
        case .full, .limited: break
        }

        let phase: ScanPhase
        let hasResults: Bool
        switch category {
        case .similarPhotos, .blurryPhotos, .duplicatePhotos, .chatPhotos:
            phase = similar.phase; hasResults = similar.hasResults
        case .screenshots: phase = screenshots.phase; hasResults = screenshots.hasResults
        case .largeVideos: phase = videos.phase; hasResults = videos.hasResults
        case .duplicateContacts: phase = contacts.phase; hasResults = contacts.hasResults
        case .calendarEvents: phase = calendar.phase; hasResults = calendar.hasResults
        }
        if phase.isScanning { return .scanning(phase.fraction) }
        if let message = phase.failureMessage { return .failed(message) }
        guard hasResults else { return .notScanned }

        switch category {
        case .duplicatePhotos:
            guard !similar.duplicateGroups.isEmpty else { return .clean("No exact copies found") }
            return .ready(detail: "\(Format.count(similar.duplicateReclaimableCount, "extra copy", "extra copies")) in \(Format.count(similar.duplicateGroups.count, "group"))",
                          bytes: similar.duplicateReclaimableBytes)
        case .chatPhotos:
            guard !similar.chatPhotos.isEmpty else { return .clean("None found") }
            return .ready(detail: Format.count(similar.chatPhotos.count, "photo"), bytes: similar.chatBytes)
        case .similarPhotos:
            guard !similar.groups.isEmpty else { return .clean("No look-alikes found") }
            return .ready(detail: "\(Format.count(similar.reclaimableCount, "extra copy", "extra copies")) in \(Format.count(similar.groups.count, "group"))",
                          bytes: similar.reclaimableBytes)
        case .blurryPhotos:
            guard !similar.blurry.isEmpty else { return .clean("Everything looks sharp") }
            return .ready(detail: Format.count(similar.blurry.count, "blurry photo"), bytes: similar.blurryBytes)
        case .screenshots:
            guard !screenshots.items.isEmpty else { return .clean("No screenshots") }
            return .ready(detail: Format.count(screenshots.items.count, "screenshot"), bytes: screenshots.totalBytes)
        case .largeVideos:
            let large = videos.largeVideos
            guard !large.isEmpty else {
                return .clean(videos.items.isEmpty ? "No videos" : "No videos over \(Format.bytes(MediaListModel.largeVideoThreshold))")
            }
            return .ready(detail: "\(Format.count(large.count, "video")) over \(Format.bytes(MediaListModel.largeVideoThreshold))",
                          bytes: large.reduce(0) { $0 + $1.fileSize })
        case .duplicateContacts:
            guard !contacts.groups.isEmpty else { return .clean("No duplicates") }
            return .ready(detail: "\(Format.count(contacts.duplicateCount, "duplicate")) in \(Format.count(contacts.groups.count, "group"))",
                          bytes: nil)
        case .calendarEvents:
            let old = calendar.oldEvents.count
            let dupes = calendar.duplicateExtraCount
            guard old + dupes > 0 else { return .clean("Nothing to tidy") }
            var parts: [String] = []
            if old > 0 { parts.append(Format.count(old, "old event")) }
            if dupes > 0 { parts.append(Format.count(dupes, "duplicate")) }
            return .ready(detail: parts.joined(separator: ", "), bytes: nil)
        }
    }

    // MARK: Review & cleanup

    func openReview(_ categories: Set<CleanupCategory>? = nil) {
        review = ReviewRequest(categories: categories ?? Set(CleanupCategory.allCases))
    }

    /// Applies a finished cleanup to local state. Only what the frameworks confirmed as gone is removed.
    func applyCleanup(summary: CleanupSummary, deletedMedia: Set<String>, contactsChanged: Bool, deletedEvents: Set<String>,
                      historyItems: [HistoryItem] = [], moreHistoryItems: Int = 0) {
        // The person confirmed the cleanup, so Quick Clean's picks are no longer provisional.
        quickCleanAdded = nil
        removeMediaEverywhere(deletedMedia)
        if contactsChanged {
            selection.clearContacts()
            if permissions.contacts.canRead { contacts.scan() }
        }
        if !deletedEvents.isEmpty {
            calendar.remove(deletedEvents)
            selection.events.subtract(deletedEvents)
        }
        record(summary, items: historyItems, moreItems: moreHistoryItems)
    }

    /// A compressed copy was saved and the original deleted.
    func recordCompression(originalID: String, originalBytes: Int64, newBytes: Int64,
                           thumbnail: Data? = nil, duration: Double = 0) -> CleanupSummary {
        var summary = CleanupSummary()
        summary.storageBefore = storage
        summary.bytesFreed = max(originalBytes - newBytes, 0)
        summary.videosCompressed = 1
        summary.bytesByCategory[.largeVideos] = summary.bytesFreed
        removeMediaEverywhere([originalID])
        let item = HistoryItem(id: UUID(), categoryRaw: CleanupCategory.largeVideos.rawValue,
                               bytes: originalBytes, duration: duration, hasThumbnail: thumbnail != nil)
        if let thumbnail { HistoryThumbnailStore.save(thumbnail, for: item.id) }
        record(summary, items: [item])
        if permissions.photos.canRead { videos.scan() }
        return summary
    }

    /// After moving items into the vault, the person may delete the originals (iOS confirms).
    func deleteOriginalsAfterVaultImport(_ ids: [String]) async {
        let outcome = await PhotoLibraryService.deleteAssets(ids: ids)
        removeMediaEverywhere(outcome.deleted)
        refreshStorage()
    }

    /// The picks CleanSpace recommends for Duplicate or Similar Photos. Applied only when the
    /// person taps "Select suggested"; scanning and opening a category never select anything.
    func suggestedSelection(for category: CleanupCategory) -> Set<String> {
        switch category {
        case .duplicatePhotos:
            return Set(similar.duplicateGroups.flatMap(\.suggestedDeletionIDs))
        case .similarPhotos:
            let keepers = Set(similar.duplicateGroups.map(\.bestID))
            return Set(similar.groups.flatMap(\.suggestedDeletionIDs)).subtracting(keepers)
        default:
            return []
        }
    }

    /// Quick Clean from the water gauge. With results, pre-selects only the safe picks (extra copies
    /// of exact duplicates, and look-alikes that aren't the best shot; never favorites) and opens
    /// the Review screen, where nothing is deleted until the person confirms. Without results, or
    /// with nothing safe to suggest, it runs a scan instead.
    func quickClean() {
        guard !isScanning else { return }
        refreshStorage()
        let duplicates = suggestedSelection(for: .duplicatePhotos)
        let similarPicks = suggestedSelection(for: .similarPhotos)
        guard hasAnyResults, !(duplicates.isEmpty && similarPicks.isEmpty) else {
            scanNowTapped()
            return
        }
        quickCleanAdded = [
            .duplicatePhotos: duplicates.subtracting(selection.ids(.duplicatePhotos)),
            .similarPhotos: similarPicks.subtracting(selection.ids(.similarPhotos))
        ]
        selection.replace(selection.ids(.duplicatePhotos).union(duplicates), in: .duplicatePhotos)
        selection.replace(selection.ids(.similarPhotos).union(similarPicks), in: .similarPhotos)
        openReview([.duplicatePhotos, .similarPhotos])
    }

    /// Called whenever the Review screen closes. After a Quick Clean that was cancelled, the
    /// picks it made are removed so nothing stays selected behind the person's back.
    func reviewDismissed() {
        guard let added = quickCleanAdded else { return }
        quickCleanAdded = nil
        for (category, ids) in added where !ids.isEmpty {
            selection.replace(selection.ids(category).subtracting(ids), in: category)
        }
    }

    /// Clears everything selected in one category.
    func clearSelection(in category: CleanupCategory) {
        switch category {
        case .duplicateContacts: selection.clearContacts()
        case .calendarEvents: selection.clearEvents()
        default: selection.replace([], in: category)
        }
    }

    /// Clears the whole selection.
    func clearAllSelection() {
        selection = CleanupSelection()
        quickCleanAdded = nil
    }

    /// Called when the person opens a category: applies that category's suggested picks once.
    func categoryOpened(_ category: CleanupCategory) {
        guard let suggested = pendingSuggestions.removeValue(forKey: category), !suggested.isEmpty else { return }
        selection.replace(selection.ids(category).union(suggested), in: category)
    }

    /// Swipe mode lets the person decide every photo, so suggestions are dropped.
    func discardSuggestions(for category: CleanupCategory) {
        pendingSuggestions[category] = nil
    }

    private func removeMediaEverywhere(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for key in Array(pendingSuggestions.keys) { pendingSuggestions[key]?.subtract(ids) }
        similar.remove(ids)
        screenshots.remove(ids)
        videos.remove(ids)
        selection.removeMedia(ids)
        AssetSizeCache.shared.forget(ids)
        ThumbnailLoader.shared.forget(ids)
    }

    private func record(_ summary: CleanupSummary, items: [HistoryItem] = [], moreItems: Int = 0) {
        if summary.bytesFreed > 0 {
            lifetimeFreedBytes += summary.bytesFreed
            defaults.set(Int(lifetimeFreedBytes), forKey: Keys.freed)
        }
        if summary.didAnything {
            history.insert(CleanupRecord(summary: summary, items: items, moreItemCount: moreItems), at: 0)
            if history.count > 50 {
                let dropped = history.suffix(history.count - 50)
                HistoryThumbnailStore.delete(dropped.flatMap { $0.items ?? [] }.map(\.id))
                history.removeLast(history.count - 50)
            }
            if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: Keys.history) }
        }
        refreshStorage()
        publishWidgetSnapshot()
    }

    func clearHistory() {
        HistoryThumbnailStore.deleteAll()
        history = []
        defaults.removeObject(forKey: Keys.history)
    }

    func finishCleanupFlow() {
        review = nil
        path = []
        refreshStorage()
    }

    // MARK: Widget

    func publishWidgetSnapshot() {
        SharedStore.write(StorageSnapshot(freeableBytes: hasAnyResults ? potentialBytes : nil,
                                          lastScan: lastScanDate,
                                          lifetimeFreedBytes: lifetimeFreedBytes,
                                          updated: Date()))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
