import Foundation

/// Sendable snapshot of an EKEvent. Recurring events are never included (see CalendarService).
struct CalendarEventItem: Identifiable, Hashable, Sendable {
    let id: String            // EKEvent.eventIdentifier
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColor: UInt32
    let location: String?
    let createdAt: Date?

    var displayTitle: String { title.isEmpty ? "Untitled event" : title }

    var whenText: String {
        if isAllDay { return startDate.formatted(date: .abbreviated, time: .omitted) }
        return startDate.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Events with the same title, start and end on writable calendars. `events[0]` is the one to keep.
struct CalendarDuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let events: [CalendarEventItem]

    var keeper: CalendarEventItem { events[0] }
    var extras: [CalendarEventItem] { Array(events.dropFirst()) }
}

enum OldEventCutoff: Int, CaseIterable, Identifiable, Sendable {
    case sixMonths = 6
    case oneYear = 12
    case twoYears = 24
    case fiveYears = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sixMonths: "6 months"
        case .oneYear: "1 year"
        case .twoYears: "2 years"
        case .fiveYears: "5 years"
        }
    }

    func date(from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .month, value: -rawValue, to: now) ?? now
    }
}

/// Pure duplicate detection so it can be unit-tested without EventKit.
enum CalendarDuplicateFinder {
    struct Fingerprint: Sendable {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    /// Case- and whitespace-insensitive title; start/end compared to the minute.
    static func key(for f: Fingerprint) -> String? {
        let title = f.title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !title.isEmpty else { return nil }   // untitled events are too ambiguous to call duplicates
        let start = Int((f.start.timeIntervalSince1970 / 60).rounded())
        let end = Int((f.end.timeIntervalSince1970 / 60).rounded())
        return "\(title)|\(start)|\(end)|\(f.isAllDay)"
    }

    /// Returns groups of indices (2+ members), each sorted in input order.
    static func groups(_ fingerprints: [Fingerprint]) -> [[Int]] {
        var buckets: [String: [Int]] = [:]
        for (i, f) in fingerprints.enumerated() {
            guard let key = key(for: f) else { continue }
            buckets[key, default: []].append(i)
        }
        return buckets.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }
}
