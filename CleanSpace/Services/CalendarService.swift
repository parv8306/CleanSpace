import EventKit
import Foundation

struct CalendarScanResult: Sendable {
    /// Past, non-recurring events on calendars CleanSpace may change, newest first.
    let pastEvents: [CalendarEventItem]
    let duplicateGroups: [CalendarDuplicateGroup]
    let totalEvents: Int
    let writableCalendarCount: Int
}

struct CalendarCleanupOutcome: Sendable {
    var deletedIDs: Set<String> = []
    var failed = 0
    var deleted: Int { deletedIDs.count }
}

/// All EventKit access. Synchronous; call off the main thread.
///
/// Only calendars that allow changes are scanned (subscribed, holiday and birthday calendars are
/// skipped), and recurring events are left alone — deleting one occurrence of a repeating meeting
/// is rarely what someone wants from a cleaner.
enum CalendarService {
    static let yearsBack = 10
    static let yearsAhead = 2

    static func scan(now: Date = Date()) -> CalendarScanResult {
        let store = EKEventStore()
        let calendars = store.calendars(for: .event).filter { $0.allowsContentModifications }
        guard !calendars.isEmpty else {
            return CalendarScanResult(pastEvents: [], duplicateGroups: [], totalEvents: 0, writableCalendarCount: 0)
        }

        let cal = Calendar.current
        var cursor = cal.date(byAdding: .year, value: -yearsBack, to: now) ?? now
        let end = cal.date(byAdding: .year, value: yearsAhead, to: now) ?? now
        var seen = Set<String>()
        var items: [CalendarEventItem] = []

        // EventKit caps a single predicate at four years, so walk the range in three-year windows.
        while cursor < end {
            let windowEnd = min(cal.date(byAdding: .year, value: 3, to: cursor) ?? end, end)
            let predicate = store.predicateForEvents(withStart: cursor, end: windowEnd, calendars: calendars)
            for event in store.events(matching: predicate) {
                guard !event.hasRecurrenceRules,
                      let id = event.eventIdentifier,
                      seen.insert(id).inserted else { continue }
                items.append(item(from: event))
            }
            cursor = windowEnd
        }

        let past = items.filter { $0.endDate < now }.sorted { $0.startDate > $1.startDate }

        let fingerprints = items.map {
            CalendarDuplicateFinder.Fingerprint(title: $0.title, start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
        let groups = CalendarDuplicateFinder.groups(fingerprints).map { indices -> CalendarDuplicateGroup in
            // Keep the one created first (the original); the copies came later.
            let events = indices.map { items[$0] }.sorted {
                ($0.createdAt ?? .distantFuture, $0.id) < ($1.createdAt ?? .distantFuture, $1.id)
            }
            return CalendarDuplicateGroup(id: events[0].id, events: events)
        }
        .sorted { $0.keeper.startDate > $1.keeper.startDate }

        return CalendarScanResult(pastEvents: past, duplicateGroups: groups,
                                  totalEvents: items.count, writableCalendarCount: calendars.count)
    }

    static func item(from event: EKEvent) -> CalendarEventItem {
        CalendarEventItem(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar?.title ?? "Calendar",
            calendarColor: hex(from: event.calendar?.cgColor),
            location: event.location?.isEmpty == false ? event.location : nil,
            createdAt: event.creationDate
        )
    }

    /// Deletes each event individually so one read-only event can't block the rest,
    /// then checks what is actually gone.
    static func delete(ids: Set<String>) -> CalendarCleanupOutcome {
        let store = EKEventStore()
        var outcome = CalendarCleanupOutcome()
        for id in ids {
            guard let event = store.event(withIdentifier: id) else { continue }
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                outcome.failed += 1
            }
        }
        store.reset()
        let remaining = Set(ids.filter { store.event(withIdentifier: $0) != nil })
        outcome.deletedIDs = ids.subtracting(remaining)
        outcome.failed = remaining.count
        return outcome
    }

    private static func hex(from color: CGColor?) -> UInt32 {
        guard let color,
              let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                        intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return 0x8E8E93 }
        let r = UInt32((min(max(c[0], 0), 1) * 255).rounded())
        let g = UInt32((min(max(c[1], 0), 1) * 255).rounded())
        let b = UInt32((min(max(c[2], 0), 1) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}
