import XCTest
@testable import CleanSpace

final class ContactMatchingTests: XCTestCase {
    private func contact(_ name: String, phones: [String] = [], emails: [String] = []) -> ContactFingerprint {
        ContactFingerprint(nameParts: [name], phones: phones, emails: emails)
    }

    func testPhoneNormalization() {
        XCTAssertEqual(ContactNormalizer.phoneKey("+1 (555) 010-2030"), ContactNormalizer.phoneKey("555 010 2030"))
        XCTAssertEqual(ContactNormalizer.phoneKey("+44 7700 900123"), ContactNormalizer.phoneKey("07700 900123"))
        XCTAssertNil(ContactNormalizer.phoneKey("911"))
    }

    func testEmailNormalization() {
        XCTAssertEqual(ContactNormalizer.emailKey("  Ana@Example.COM "), "ana@example.com")
        XCTAssertNil(ContactNormalizer.emailKey("not-an-email"))
    }

    func testNameNormalizationIgnoresCaseAccentsAndOrder() {
        let a = ContactNormalizer.nameKey(ContactNormalizer.nameTokens(["José", "SMITH"]))
        let b = ContactNormalizer.nameKey(ContactNormalizer.nameTokens(["smith jose"]))
        XCTAssertEqual(a, b)
    }

    func testSamePhoneGroupsAsLikely() {
        let groups = ContactDuplicateFinder.findGroups([
            contact("John Smith", phones: ["+1 555 010 2030"]),
            contact("John", phones: ["(555) 010-2030"]),
            contact("Maria Lopez", phones: ["555 999 0000"])
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members, [0, 1])
        XCTAssertTrue(groups[0].reasons.contains(.samePhone))
        XCTAssertEqual(groups[0].confidence, .likely)
    }

    func testSharedLineWithDifferentNamesNeedsReview() {
        let groups = ContactDuplicateFinder.findGroups([
            contact("Anna Berg", phones: ["555 123 4567"]),
            contact("Oscar Berg", phones: ["555-123-4567"])
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].confidence, .review)
    }

    func testSameNameDifferentDetailsIsNotLinked() {
        let groups = ContactDuplicateFinder.findGroups([
            contact("Alex Kim", phones: ["555 111 2222"]),
            contact("Alex Kim", phones: ["555 333 4444"])
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testSameNameStubIsLinked() {
        let groups = ContactDuplicateFinder.findGroups([
            contact("Priya Nair", emails: ["priya@example.com"]),
            contact("priya nair")
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].reasons.contains(.sameName))
    }

    func testSwitchboardNumbersAreIgnored() {
        let shared = "555 000 1000"
        let people = (0..<(ContactDuplicateFinder.maxSharedOwners + 1)).map { contact("Person \($0)", phones: [shared]) }
        XCTAssertTrue(ContactDuplicateFinder.findGroups(people).isEmpty)
    }

    func testSharedEmailGroups() {
        let groups = ContactDuplicateFinder.findGroups([
            contact("Sam Lee", emails: ["SAM@example.com"]),
            contact("Samuel Lee", emails: ["sam@example.com"])
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].reasons.contains(.sameEmail))
    }
}
