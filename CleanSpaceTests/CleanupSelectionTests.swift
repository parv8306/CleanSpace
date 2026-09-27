import XCTest
@testable import CleanSpace

final class CleanupSelectionTests: XCTestCase {
    func testToggleAndCounts() {
        var selection = CleanupSelection()
        selection.toggle("a", in: .screenshots)
        selection.select(["b", "c"], in: .largeVideos)
        XCTAssertEqual(selection.mediaCount, 3)
        selection.toggle("a", in: .screenshots)
        XCTAssertEqual(selection.mediaCount, 2)
        XCTAssertFalse(selection.isEmpty)
    }

    func testRemoveMediaAcrossCategories() {
        var selection = CleanupSelection()
        selection.select(["x", "y"], in: .similarPhotos)
        selection.select(["x"], in: .blurryPhotos)
        selection.removeMedia(["x"])
        XCTAssertEqual(selection.ids(.similarPhotos), ["y"])
        XCTAssertTrue(selection.ids(.blurryPhotos).isEmpty)
    }

    func testMergeAndDeleteAreExclusivePerGroup() {
        var selection = CleanupSelection()
        selection.toggleContactDelete("c1", groupID: "g")
        let plan = ContactMergePlan(groupID: "g", memberIDs: ["c1", "c2"], nameSourceID: "c1", photoSourceID: nil)
        selection.setMerge(plan)
        XCTAssertTrue(selection.contactDeletes.isEmpty)
        XCTAssertEqual(selection.contactChangeCount, 1)
        selection.toggleContactDelete("c2", groupID: "g")
        XCTAssertNil(selection.contactMerges["g"])
        XCTAssertEqual(selection.contactDeletes, ["c2"])
    }

    func testEventsCountTowardSelection() {
        var selection = CleanupSelection()
        XCTAssertTrue(selection.isEmpty)
        selection.toggleEvent("e1")
        XCTAssertFalse(selection.isEmpty)
        XCTAssertEqual(selection.events, ["e1"])
        selection.toggleEvent("e1")
        XCTAssertTrue(selection.isEmpty)
        selection.events = ["e2", "e3"]
        selection.clearEvents()
        XCTAssertTrue(selection.events.isEmpty)
    }

    func testCategoryPermissions() {
        XCTAssertEqual(CleanupCategory.calendarEvents.permission, .calendar)
        XCTAssertEqual(CleanupCategory.duplicateContacts.permission, .contacts)
        XCTAssertTrue(CleanupCategory.screenshots.isMedia)
        XCTAssertFalse(CleanupCategory.calendarEvents.isMedia)
    }
}
