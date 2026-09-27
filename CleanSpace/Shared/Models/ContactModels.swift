import Foundation

struct ContactRecord: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let organization: String
    let phones: [String]
    let emails: [String]
    let thumbnail: Data?

    var hasContactInfo: Bool { !phones.isEmpty || !emails.isEmpty }

    var initials: String {
        let words = displayName.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

enum MatchReason: String, Hashable, Sendable, CaseIterable {
    case samePhone, sameEmail, sameName

    var label: String {
        switch self {
        case .samePhone: "Same phone"
        case .sameEmail: "Same email"
        case .sameName: "Same name"
        }
    }

    var symbol: String {
        switch self {
        case .samePhone: "phone.fill"
        case .sameEmail: "envelope.fill"
        case .sameName: "person.fill"
        }
    }
}

enum ContactMatchConfidence: Sendable, Hashable {
    /// Names are compatible and details overlap — very likely the same person.
    case likely
    /// Details overlap but names differ (e.g. a shared family landline). Needs a human look.
    case review
}

struct ContactGroup: Identifiable, Hashable, Sendable {
    let id: String
    let contacts: [ContactRecord]
    let reasons: Set<MatchReason>
    let confidence: ContactMatchConfidence

    var memberIDs: [String] { contacts.map(\.id) }
}

struct ContactMergePlan: Hashable, Sendable {
    let groupID: String
    let memberIDs: [String]
    /// The contact whose name (and identity) is kept; the others are folded into it and removed.
    var nameSourceID: String
    /// Optional contact whose photo should be used on the merged card.
    var photoSourceID: String?

    var removedCount: Int { max(memberIDs.count - 1, 0) }
}
