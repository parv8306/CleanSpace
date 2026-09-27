import XCTest
@testable import CleanSpace

final class CalendarDuplicateFinderTests: XCTestCase {
    private typealias F = CalendarDuplicateFinder.Fingerprint
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testSameTitleAndTimesAreGrouped() {
        let events = [
            F(title: "Dentist", start: base, end: base.addingTimeInterval(3600), isAllDay: false),
            F(title: "  dentist ", start: base.addingTimeInterval(10), end: base.addingTimeInterval(3610), isAllDay: false),
            F(title: "Gym", start: base, end: base.addingTimeInterval(3600), isAllDay: false)
        ]
        XCTAssertEqual(CalendarDuplicateFinder.groups(events), [[0, 1]])
    }

    func testCaseAndDiacriticsAreIgnored() {
        let events = [
            F(title: "Café meetup", start: base, end: base, isAllDay: true),
            F(title: "CAFE MEETUP", start: base, end: base, isAllDay: true)
        ]
        XCTAssertEqual(CalendarDuplicateFinder.groups(events).count, 1)
    }

    func testDifferentTimesOrAllDayAreNotDuplicates() {
        let events = [
            F(title: "Standup", start: base, end: base.addingTimeInterval(900), isAllDay: false),
            F(title: "Standup", start: base.addingTimeInterval(86_400), end: base.addingTimeInterval(87_300), isAllDay: false),
            F(title: "Standup", start: base, end: base.addingTimeInterval(900), isAllDay: true)
        ]
        XCTAssertTrue(CalendarDuplicateFinder.groups(events).isEmpty)
    }

    func testUntitledEventsAreNeverGrouped() {
        let events = [
            F(title: "", start: base, end: base, isAllDay: false),
            F(title: "   ", start: base, end: base, isAllDay: false)
        ]
        XCTAssertTrue(CalendarDuplicateFinder.groups(events).isEmpty)
    }

    func testOldEventCutoffGoesBackTheRightNumberOfMonths() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let cutoff = OldEventCutoff.oneYear.date(from: now)
        let months = Calendar.current.dateComponents([.month], from: cutoff, to: now).month
        XCTAssertEqual(months, 12)
    }
}
