import Foundation
import Observation

/// View model for the similar/duplicate and blurry photo results (one scan feeds both).
@Observable
@MainActor
final class SimilarPhotosModel {
    private(set) var phase: ScanPhase = .idle
    /// Look-alike groups (not exact copies).
    private(set) var groups: [PhotoGroup] = []
    /// Exact-copy groups.
    private(set) var duplicateGroups: [PhotoGroup] = []
    private(set) var chatPhotos: [MediaItem] = []
    private(set) var chatPlatforms: [String: ChatPlatform] = [:]
    private(set) var blurry: [MediaItem] = []
    private(set) var blurrySections: [MediaSection] = []
    private(set) var scannedCount = 0
    private(set) var skippedCount = 0
    private(set) var hasResults = false

    @ObservationIgnored var onFinished: (@MainActor (SimilarScanResult) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = 0

    var photoCount: Int { groups.reduce(0) { $0 + $1.items.count } }
    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }
    var reclaimableCount: Int { groups.reduce(0) { $0 + $1.reclaimableItems.count } }
    var blurryBytes: Int64 { blurry.reduce(0) { $0 + $1.fileSize } }
    var allItems: [MediaItem] { groups.flatMap(\.items) }

    var duplicateItems: [MediaItem] { duplicateGroups.flatMap(\.items) }
    var duplicateReclaimableBytes: Int64 { duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes } }
    var duplicateReclaimableCount: Int { duplicateGroups.reduce(0) { $0 + $1.reclaimableItems.count } }
    var chatBytes: Int64 { chatPhotos.reduce(0) { $0 + $1.fileSize } }

    /// Platforms found, most photos first, with "Other chat apps" last.
    var chatPlatformCounts: [(platform: ChatPlatform, count: Int)] {
        var counts: [ChatPlatform: Int] = [:]
        for platform in chatPlatforms.values { counts[platform, default: 0] += 1 }
        return counts.map { (platform: $0.key, count: $0.value) }
            .sorted { ($0.platform == .other ? 1 : 0, -$0.count) < ($1.platform == .other ? 1 : 0, -$1.count) }
    }

    func groups(of kind: PhotoGroup.Kind) -> [PhotoGroup] {
        kind == .duplicates ? duplicateGroups : groups
    }

    func group(id: String) -> PhotoGroup? {
        groups.first { $0.id == id } ?? duplicateGroups.first { $0.id == id }
    }

    func scan() {
        task?.cancel()
        token += 1
        let current = token
        phase = .scanning(done: 0, total: 0)
        task = Task { [weak self] in
            for await event in SimilarPhotoScanner.events() {
                guard let self, self.token == current else { return }
                switch event {
                case let .progress(done, total):
                    self.phase = .scanning(done: done, total: total)
                case .analyzing:
                    self.phase = .analyzing
                case let .finished(result):
                    self.apply(result)
                }
            }
            // The stream ended without a result and nobody cancelled it: say so, don't pretend.
            guard let self, self.token == current, self.phase.isScanning else { return }
            self.phase = .failed("The photo scan stopped before it finished.")
            self.task = nil
        }
    }

    func cancel() {
        guard phase.isScanning else { return }
        token += 1
        task?.cancel()
        task = nil
        phase = hasResults ? .finished : .idle
    }

    func reset() {
        token += 1
        task?.cancel()
        task = nil
        phase = .idle
        groups = []
        duplicateGroups = []
        chatPhotos = []
        chatPlatforms = [:]
        blurry = []
        blurrySections = []
        scannedCount = 0
        skippedCount = 0
        hasResults = false
    }

    func setBest(_ itemID: String, inGroup groupID: String) {
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index] = groups[index].withBest(itemID)
        } else if let index = duplicateGroups.firstIndex(where: { $0.id == groupID }) {
            duplicateGroups[index] = duplicateGroups[index].withBest(itemID)
        }
    }

    /// Drops deleted photos; groups that fall below two photos disappear.
    func remove(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        groups = groups.compactMap { group in
            group.items.contains(where: { ids.contains($0.id) }) ? group.removing(ids) : group
        }
        duplicateGroups = duplicateGroups.compactMap { group in
            group.items.contains(where: { ids.contains($0.id) }) ? group.removing(ids) : group
        }
        chatPhotos.removeAll { ids.contains($0.id) }
        for id in ids { chatPlatforms[id] = nil }
        blurry.removeAll { ids.contains($0.id) }
        blurrySections = MediaSection.byMonth(blurry)
    }

    private func apply(_ result: SimilarScanResult) {
        groups = result.groups
        duplicateGroups = result.duplicateGroups
        chatPhotos = result.chatPhotos
        chatPlatforms = result.chatPlatforms
        blurry = result.blurry
        blurrySections = MediaSection.byMonth(result.blurry)
        scannedCount = result.scannedCount
        skippedCount = result.skippedCount
        hasResults = true
        phase = .finished
        task = nil
        onFinished?(result)
    }
}
