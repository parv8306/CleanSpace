import XCTest
@testable import CleanSpace

final class CompressionEstimatorTests: XCTestCase {
    func testTargetFollowsTheChosenShareOfTheOriginal() {
        // 100 MB, 60 s: Balanced aims for 35% of the original.
        XCTAssertEqual(CompressionEstimator.estimatedBytes(duration: 60, originalBytes: 100_000_000, quality: .balanced), 35_000_000)
        XCTAssertEqual(CompressionEstimator.estimatedBytes(duration: 60, originalBytes: 100_000_000, quality: .high), 60_000_000)
        XCTAssertEqual(CompressionEstimator.estimatedBytes(duration: 60, originalBytes: 100_000_000, quality: .small), 20_000_000)
    }

    func testTargetNeverDropsBelowAWatchableFloorOrAboveTheOriginal() {
        // 10 MB over 10 minutes is already tiny: the floor exceeds the original, so no saving.
        let bytes = CompressionEstimator.estimatedBytes(duration: 600, originalBytes: 10_000_000, quality: .small)
        XCTAssertEqual(bytes, 10_000_000)
        XCTAssertEqual(CompressionEstimator.estimatedSavings(duration: 600, originalBytes: 10_000_000, quality: .small), 0)
    }

    func testBitRateLandsOnTheTarget() {
        let target: Int64 = 35_000_000
        let rate = CompressionEstimator.videoBitRate(targetBytes: target, duration: 60, quality: .balanced)
        // (video + audio) * duration * overhead should come back to the target within 1%.
        let bytes = Double(rate + CompressionQuality.balanced.audioBitRate) * 60 / 8 * (1 + CompressionEstimator.containerOverhead)
        XCTAssertEqual(bytes, Double(target), accuracy: Double(target) * 0.01)
    }

    func testResolutionFollowsBitRate() {
        XCTAssertEqual(CompressionEstimator.maxLongEdge(for: .high, videoBitRate: 6_000_000), 1920)
        XCTAssertEqual(CompressionEstimator.maxLongEdge(for: .high, videoBitRate: 1_500_000), 1280)
        XCTAssertEqual(CompressionEstimator.maxLongEdge(for: .balanced, videoBitRate: 800_000), 960)
    }

    func testOutputSizeKeepsAspectNeverUpscalesAndIsEven() {
        XCTAssertEqual(CompressionEstimator.outputSize(for: CGSize(width: 3840, height: 2160), maxLongEdge: 1280),
                       CGSize(width: 1280, height: 720))
        XCTAssertEqual(CompressionEstimator.outputSize(for: CGSize(width: 1080, height: 1920), maxLongEdge: 1280),
                       CGSize(width: 720, height: 1280))
        XCTAssertEqual(CompressionEstimator.outputSize(for: CGSize(width: 640, height: 360), maxLongEdge: 1920),
                       CGSize(width: 640, height: 360))
        let odd = CompressionEstimator.outputSize(for: CGSize(width: 1001, height: 563), maxLongEdge: 960)
        XCTAssertEqual(Int(odd.width) % 2, 0)
        XCTAssertEqual(Int(odd.height) % 2, 0)
    }

    func testSmallerOptionsSaveMore() {
        let high = CompressionEstimator.estimatedSavings(duration: 120, originalBytes: 800_000_000, quality: .high)
        let balanced = CompressionEstimator.estimatedSavings(duration: 120, originalBytes: 800_000_000, quality: .balanced)
        let small = CompressionEstimator.estimatedSavings(duration: 120, originalBytes: 800_000_000, quality: .small)
        XCTAssertLessThan(high, balanced)
        XCTAssertLessThan(balanced, small)
    }

    func testInvalidDurationFallsBackToOriginal() {
        XCTAssertEqual(CompressionEstimator.estimatedBytes(duration: .nan, originalBytes: 42, quality: .small), 42)
        XCTAssertEqual(CompressionEstimator.estimatedBytes(duration: 0, originalBytes: 42, quality: .small), 42)
    }
}
