import XCTest
@testable import CleanSpace

final class SimilarityGrouperTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func photo(_ hash: UInt64, at seconds: TimeInterval? = nil, aspect: Double = 0.75) -> HashedPhoto {
        HashedPhoto(hash: hash, date: seconds.map { base.addingTimeInterval($0) }, aspectRatio: aspect)
    }

    /// Flips the lowest `bits` bits.
    private func flip(_ hash: UInt64, bits: Int) -> UInt64 {
        bits == 0 ? hash : hash ^ ((1 << UInt64(bits)) - 1)
    }

    func testExactDuplicatesGroup() {
        let h: UInt64 = 0xDEAD_BEEF_0123_4567
        let groups = SimilarityGrouper().groups(for: [photo(h), photo(0x1111_2222_3333_4444), photo(h)])
        XCTAssertEqual(groups, [[0, 2]])
    }

    func testNearDuplicatesAcrossTimeGroup() {
        let h: UInt64 = 0xA5A5_5A5A_F0F0_0F0F
        let groups = SimilarityGrouper().groups(for: [photo(h, at: 0), photo(flip(h, bits: 4), at: 86_400 * 30)])
        XCTAssertEqual(groups, [[0, 1]])
    }

    func testDistantHashesFarApartInTimeDoNotGroup() {
        let h: UInt64 = 0xA5A5_5A5A_F0F0_0F0F
        let groups = SimilarityGrouper().groups(for: [photo(h, at: 0), photo(flip(h, bits: 10), at: 86_400)])
        XCTAssertTrue(groups.isEmpty)
    }

    func testBurstUsesLooserThreshold() {
        let h: UInt64 = 0x0F0F_F0F0_3C3C_C3C3
        let groups = SimilarityGrouper().groups(for: [photo(h, at: 0), photo(flip(h, bits: 10), at: 20)])
        XCTAssertEqual(groups, [[0, 1]])
    }

    func testBurstStillRejectsUnrelatedShots() {
        let groups = SimilarityGrouper().groups(for: [photo(0, at: 0), photo(.max, at: 5)])
        XCTAssertTrue(groups.isEmpty)
    }

    func testAspectRatioGuardSeparatesCrops() {
        let h: UInt64 = 0x1234_5678_9ABC_DEF0
        let groups = SimilarityGrouper().groups(for: [photo(h, aspect: 0.75), photo(h, aspect: 1.0)])
        XCTAssertTrue(groups.isEmpty)
    }

    func testTransitiveMatchesMerge() {
        let h: UInt64 = 0xFFFF_0000_FFFF_0000
        let groups = SimilarityGrouper().groups(for: [photo(h), photo(flip(h, bits: 3)), photo(flip(h, bits: 6))])
        XCTAssertEqual(groups, [[0, 1, 2]])
    }

    func testEmptyAndSingleInputs() {
        XCTAssertTrue(SimilarityGrouper().groups(for: []).isEmpty)
        XCTAssertTrue(SimilarityGrouper().groups(for: [photo(1)]).isEmpty)
    }
}
