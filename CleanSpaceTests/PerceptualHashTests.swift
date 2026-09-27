import XCTest
@testable import CleanSpace

final class PerceptualHashTests: XCTestCase {
    /// Deterministic pseudo-random "photo" with some structure.
    private func makeImage(width: Int, height: Int, seed: UInt64) -> [UInt8] {
        var state = seed
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let noise = Int((state >> 58) & 0x0F)
                let gradient = (x * 180 / width) + (y * 60 / height)
                let blob = ((x / 16 + y / 16 + Int(seed % 7)) % 3) * 20
                pixels[y * width + x] = UInt8(clamping: gradient + blob + noise)
            }
        }
        return pixels
    }

    private func hash(_ pixels: [UInt8], _ w: Int, _ h: Int) -> UInt64 {
        PerceptualHash.dHash(PerceptualHash.areaResize(pixels, width: w, height: h, toWidth: 9, toHeight: 8))
    }

    func testIdenticalImagesHashIdentically() {
        let image = makeImage(width: 128, height: 96, seed: 42)
        XCTAssertEqual(hash(image, 128, 96), hash(image, 128, 96))
    }

    func testResizedCopyStaysClose() {
        let big = makeImage(width: 256, height: 192, seed: 7)
        let small = PerceptualHash.areaResize(big, width: 256, height: 192, toWidth: 128, toHeight: 96)
        let distance = PerceptualHash.distance(hash(big, 256, 192), hash(small, 128, 96))
        XCTAssertLessThanOrEqual(distance, 5)
    }

    func testSlightBrightnessChangeStaysClose() {
        let image = makeImage(width: 128, height: 96, seed: 11)
        let brighter = image.map { UInt8(clamping: Int($0) + 12) }
        XCTAssertLessThanOrEqual(PerceptualHash.distance(hash(image, 128, 96), hash(brighter, 128, 96)), 5)
    }

    func testDifferentImagesAreFar() {
        let a = makeImage(width: 128, height: 96, seed: 1)
        let flipped = (0..<96).flatMap { y in (0..<128).reversed().map { x in a[y * 128 + x] } }
        XCTAssertGreaterThan(PerceptualHash.distance(hash(a, 128, 96), hash(flipped, 128, 96)), 20)
    }

    func testDistanceIsHamming() {
        XCTAssertEqual(PerceptualHash.distance(0, 0), 0)
        XCTAssertEqual(PerceptualHash.distance(0, 0b1011), 3)
        XCTAssertEqual(PerceptualHash.distance(0, .max), 64)
    }

    func testBlurLowersLaplacianVariance() {
        let w = 64, h = 64
        let sharp = (0..<(w * h)).map { i -> UInt8 in ((i % w) / 4 + (i / w) / 4) % 2 == 0 ? 20 : 235 }
        var blurred = sharp
        for _ in 0..<4 {
            var next = blurred
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let i = y * w + x
                    let sum = Int(blurred[i]) * 4 + Int(blurred[i - 1]) + Int(blurred[i + 1]) + Int(blurred[i - w]) + Int(blurred[i + w])
                    next[i] = UInt8(sum / 8)
                }
            }
            blurred = next
        }
        XCTAssertGreaterThan(PerceptualHash.laplacianVariance(sharp, width: w, height: h),
                             PerceptualHash.laplacianVariance(blurred, width: w, height: h) * 4)
    }

    func testFlatImageHasNoContrast() {
        XCTAssertEqual(PerceptualHash.standardDeviation([UInt8](repeating: 128, count: 100)), 0, accuracy: 0.0001)
        XCTAssertEqual(PerceptualHash.laplacianVariance([UInt8](repeating: 128, count: 100), width: 10, height: 10), 0, accuracy: 0.0001)
    }
}
