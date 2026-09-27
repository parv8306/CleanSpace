import XCTest
@testable import CleanSpace

final class PhotoRankingTests: XCTestCase {
    private func item(_ id: String, w: Int = 4032, h: Int = 3024, favorite: Bool = false,
                      screenshot: Bool = false, sharpness: Double = 200, size: Int64 = 3_000_000,
                      date: TimeInterval = 0) -> MediaItem {
        MediaItem(id: id, creationDate: Date(timeIntervalSince1970: 1_700_000_000 + date),
                  pixelWidth: w, pixelHeight: h, isScreenshot: screenshot, isFavorite: favorite,
                  fileSize: size, sharpness: sharpness)
    }

    func testFavoriteIsAlwaysBest() {
        let group = PhotoGroup(items: [item("a", w: 8000, h: 6000), item("b", favorite: true)], kind: .similar)
        XCTAssertEqual(group?.bestID, "b")
    }

    func testHigherResolutionWins() {
        let group = PhotoGroup(items: [item("small", w: 1024, h: 768), item("large")], kind: .similar)
        XCTAssertEqual(group?.bestID, "large")
    }

    func testSharperWinsAtSameResolution() {
        let group = PhotoGroup(items: [item("blurry", sharpness: 20), item("sharp", sharpness: 400)], kind: .similar)
        XCTAssertEqual(group?.bestID, "sharp")
    }

    func testRealPhotoBeatsScreenshotOfIt() {
        let group = PhotoGroup(items: [item("shot", screenshot: true), item("photo")], kind: .similar)
        XCTAssertEqual(group?.bestID, "photo")
    }

    func testSuggestionsExcludeBestAndFavorites() throws {
        let group = try XCTUnwrap(PhotoGroup(items: [
            item("best", w: 8000, h: 6000),
            item("fav", favorite: false),
            item("other", w: 1000, h: 750)
        ], kind: .similar))
        XCTAssertEqual(group.bestID, "best")
        XCTAssertEqual(Set(group.suggestedDeletionIDs), ["fav", "other"])

        let withFavorite = try XCTUnwrap(PhotoGroup(items: [
            item("fav", favorite: true), item("x", w: 1000, h: 750), item("y", w: 1000, h: 750, favorite: true)
        ], kind: .similar))
        XCTAssertFalse(withFavorite.suggestedDeletionIDs.contains("y"))
    }

    func testGroupOfOneIsNotAGroup() {
        XCTAssertNil(PhotoGroup(items: [item("a")], kind: .duplicates))
    }

    func testRemovingKeepsChosenBestAndDropsSmallGroups() throws {
        let group = try XCTUnwrap(PhotoGroup(items: [item("a"), item("b", w: 100, h: 75), item("c", w: 100, h: 75)], kind: .similar))
        let chosen = group.withBest("c")
        XCTAssertEqual(chosen.bestID, "c")
        XCTAssertEqual(chosen.items.first?.id, "c")
        XCTAssertEqual(chosen.removing(["a"])?.bestID, "c")
        XCTAssertNil(chosen.removing(["a", "b"]))
    }

    func testMonthSectionsPreserveOrder() {
        let cal = Calendar.current
        let march = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let feb = cal.date(from: DateComponents(year: 2026, month: 2, day: 5))!
        let items = [
            MediaItem(id: "1", creationDate: march, pixelWidth: 1, pixelHeight: 1),
            MediaItem(id: "2", creationDate: march, pixelWidth: 1, pixelHeight: 1),
            MediaItem(id: "3", creationDate: feb, pixelWidth: 1, pixelHeight: 1),
            MediaItem(id: "4", creationDate: nil, pixelWidth: 1, pixelHeight: 1)
        ]
        let sections = MediaSection.byMonth(items)
        XCTAssertEqual(sections.map { $0.items.map(\.id) }, [["1", "2"], ["3"], ["4"]])
        XCTAssertEqual(sections.last?.title, "Undated")
    }
}
