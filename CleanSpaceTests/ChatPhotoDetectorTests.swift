import XCTest
@testable import CleanSpace

final class ChatPhotoDetectorTests: XCTestCase {
    private func classify(_ name: String?, uti: String? = "public.jpeg", w: Int = 1600, h: Int = 1200,
                          location: Bool = false, screenshot: Bool = false) -> ChatPlatform? {
        ChatPhotoDetector.classify(filename: name, uniformType: uti, pixelWidth: w, pixelHeight: h,
                                   hasLocation: location, isScreenshot: screenshot)
    }

    func testFileNamesAttributePlatforms() {
        XCTAssertEqual(classify("IMG-20240105-WA0012.jpg", w: 4032, h: 3024), .whatsapp)
        XCTAssertEqual(classify("telegram-cloud-photo-size-2-5.jpg", w: 4032, h: 3024), .telegram)
        XCTAssertEqual(classify("received_1234567890123.jpeg", w: 4032, h: 3024), .messenger)
        XCTAssertEqual(classify("signal-2024-01-05-101010.jpg", w: 4032, h: 3024), .signal)
        XCTAssertEqual(classify("mmexport1704450000000.jpg", w: 4032, h: 3024), .wechat)
    }

    func testCompressionFootprintIsOtherChatApps() {
        XCTAssertEqual(classify("IMG_1234.JPG", w: 1600, h: 1200), .other)
        XCTAssertEqual(classify("IMG_1234.JPG", w: 960, h: 1280), .other)
        XCTAssertEqual(classify("IMG_1234.JPG", w: 2560, h: 1920), .other)
    }

    func testCameraPhotosAreNotChatPhotos() {
        XCTAssertNil(classify("IMG_1234.HEIC", uti: "public.heic", w: 4032, h: 3024))
        XCTAssertNil(classify("IMG_1234.JPG", w: 4032, h: 3024))
        // A chat-sized JPEG that still has a location was probably not sent through a chat app.
        XCTAssertNil(classify("IMG_1234.JPG", w: 1600, h: 1200, location: true))
        // HEIC at a chat size doesn't match either: chat apps send JPEG.
        XCTAssertNil(classify("IMG_1234.HEIC", uti: "public.heic", w: 1600, h: 1200))
    }

    func testScreenshotsAreExcluded() {
        XCTAssertNil(classify("IMG-20240105-WA0012.jpg", screenshot: true))
    }

    func testOrdinaryNamesDontMatchPlatforms() {
        XCTAssertNil(ChatPhotoDetector.platform(forFilename: "IMG_0042.JPG"))
        XCTAssertNil(ChatPhotoDetector.platform(forFilename: "received.jpg"))
        XCTAssertNil(ChatPhotoDetector.platform(forFilename: "swan-lake.jpg"))
    }

    func testCategoriesHaveSwipePilesWhereExpected() {
        XCTAssertEqual(CleanupCategory.duplicatePhotos.swipeSource, .duplicates)
        XCTAssertEqual(CleanupCategory.chatPhotos.swipeSource, .chat)
        XCTAssertNil(CleanupCategory.duplicateContacts.swipeSource)
        XCTAssertTrue(CleanupCategory.mediaCategories.contains(.duplicatePhotos))
        XCTAssertTrue(CleanupCategory.mediaCategories.contains(.chatPhotos))
    }

    func testLargeVideoThresholdIs25MB() {
        XCTAssertEqual(MediaListModel.largeVideoThreshold, 25_000_000)
    }
}
