import Foundation
import Observation

@Observable
@MainActor
final class CalendarModel {
    private(set) var phase: ScanPhase = .idle
    private(set) var pastEvents: [CalendarEventItem] = []
    private(set) var duplicateGroups: [CalendarDuplicateGroup] = []
    private(set) var totalEvents = 0
    private(set) var writableCalendarCount = 0
    private(set) var hasResults = false
    var cutoff: OldEventCutoff = .oneYear

    @ObservationIgnored var onFinished: (@MainActor () -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = 0

    var oldEvents: [CalendarEventItem] {
        let limit = cutoff.date()
        return pastEvents.filter { $0.endDate < limit }
    }

    var duplicateExtraCount: Int { duplicateGroups.reduce(0) { $0 + $1.extras.count } }

    /// Every event that could appear in a selection, for building the review plan.
    var allItems: [CalendarEventItem] {
        var seen = Set<String>()
        var result: [CalendarEventItem] = []
        for event in duplicateGroups.flatMap(\.events) + pastEvents where seen.insert(event.id).inserted {
            result.append(event)
        }
        return result
    }

    func scan() {
        task?.cancel()
        token += 1
        let current = token
        phase = .scanning(done: 0, total: 0)
        task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { CalendarService.scan() }.value
            guard let self, self.token == current else { return }
            self.pastEvents = result.pastEvents
            self.duplicateGroups = result.duplicateGroups
            self.totalEvents = result.totalEvents
            self.writableCalendarCount = result.writableCalendarCount
            self.hasResults = true
            self.phase = .finished
            self.task = nil
            self.onFinished?()
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
        pastEvents = []
        duplicateGroups = []
        totalEvents = 0
        writableCalendarCount = 0
        hasResults = false
    }

    func remove(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        pastEvents.removeAll { ids.contains($0.id) }
        duplicateGroups = duplicateGroups.compactMap { group in
            let remaining = group.events.filter { !ids.contains($0.id) }
            return remaining.count > 1 ? CalendarDuplicateGroup(id: group.id, events: remaining) : nil
        }
    }
}
