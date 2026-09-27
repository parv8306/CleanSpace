import Foundation
import Observation

/// View model shared by the Screenshots and Large Videos screens.
@Observable
@MainActor
final class MediaListModel {
    /// Videos at or above this size are called "large" on the dashboard.
    nonisolated static let largeVideoThreshold: Int64 = 25 * 1_000_000

    let kind: MediaListKind
    private(set) var phase: ScanPhase = .idle
    private(set) var items: [MediaItem] = []
    private(set) var sections: [MediaSection] = []
    private(set) var hasResults = false

    @ObservationIgnored var onFinished: (@MainActor () -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = 0

    init(kind: MediaListKind) {
        self.kind = kind
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.fileSize } }
    var largeVideos: [MediaItem] { items.filter { $0.fileSize >= Self.largeVideoThreshold } }
    /// What the dashboard counts as freeable for this category.
    var cleanableItems: [MediaItem] { kind == .videos ? largeVideos : items }
    var cleanableBytes: Int64 { cleanableItems.reduce(0) { $0 + $1.fileSize } }

    func scan() {
        task?.cancel()
        token += 1
        let current = token
        phase = .scanning(done: 0, total: 0)
        let kind = self.kind
        task = Task { [weak self] in
            for await event in MediaListScanner.events(for: kind) {
                guard let self, self.token == current else { return }
                switch event {
                case let .items(items, done, total):
                    self.setItems(items)
                    self.phase = .scanning(done: done, total: total)
                case let .progress(done, total):
                    self.phase = .scanning(done: done, total: total)
                case let .finished(items):
                    self.setItems(items)
                    self.hasResults = true
                    self.phase = .finished
                    self.task = nil
                    self.onFinished?()
                }
            }
            guard let self, self.token == current, self.phase.isScanning else { return }
            self.phase = .failed("The scan stopped before it finished.")
            self.task = nil
        }
    }

    func cancel() {
        guard phase.isScanning else { return }
        token += 1
        task?.cancel()
        task = nil
        if hasResults {
            phase = .finished
        } else {
            phase = .idle
            setItems([])
        }
    }

    func reset() {
        token += 1
        task?.cancel()
        task = nil
        phase = .idle
        hasResults = false
        setItems([])
    }

    func remove(_ ids: Set<String>) {
        guard !ids.isEmpty, items.contains(where: { ids.contains($0.id) }) else { return }
        setItems(items.filter { !ids.contains($0.id) })
    }

    private func setItems(_ newItems: [MediaItem]) {
        items = newItems
        sections = kind == .screenshots ? MediaSection.byMonth(newItems) : []
    }
}
