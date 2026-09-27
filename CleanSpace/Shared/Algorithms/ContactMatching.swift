import Foundation

enum ContactNormalizer {
    /// Case-, diacritic- and width-insensitive name tokens. "José  SMITH" → ["jose", "smith"].
    static func nameTokens(_ parts: [String]) -> [String] {
        let joined = parts.joined(separator: " ")
        let folded = joined.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        return folded.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Order-insensitive key so "Smith John" and "John Smith" match.
    static func nameKey(_ tokens: [String]) -> String { tokens.sorted().joined(separator: " ") }

    /// Digits only, compared on the last 10 digits so "+1 (555) 010-2030" == "555 010 2030"
    /// and "+44 7700 900123" == "07700 900123". Numbers shorter than 7 digits (short codes) are ignored.
    static func phoneKey(_ raw: String) -> String? {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        guard digits.count >= 7 else { return nil }
        return String(digits.suffix(10))
    }

    static func emailKey(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.count >= 3, let at = email.firstIndex(of: "@"),
              at != email.startIndex, email.index(after: at) != email.endIndex else { return nil }
        return email
    }
}

struct ContactFingerprint: Sendable {
    let nameKey: String
    let nameTokens: Set<String>
    let phones: Set<String>
    let emails: Set<String>

    init(nameParts: [String], phones: [String], emails: [String]) {
        let tokens = ContactNormalizer.nameTokens(nameParts)
        self.nameTokens = Set(tokens)
        self.nameKey = ContactNormalizer.nameKey(tokens)
        self.phones = Set(phones.compactMap(ContactNormalizer.phoneKey))
        self.emails = Set(emails.compactMap(ContactNormalizer.emailKey))
    }

    var hasContactInfo: Bool { !phones.isEmpty || !emails.isEmpty }
}

struct ContactMatchGroup: Sendable {
    let members: [Int]
    let reasons: Set<MatchReason>
    let confidence: ContactMatchConfidence
}

/// Conservative duplicate finder. Two contacts are linked when they:
///  • share a normalized phone number, or
///  • share a normalized email, or
///  • have the same (order-insensitive) name and at least one of them has no phone/email at all
///    (a name-only stub). Same name with *different* details is NOT linked — those are often
///    different people.
/// A phone/email shared by more than `maxSharedOwners` contacts (a company switchboard) is ignored.
enum ContactDuplicateFinder {
    static let maxSharedOwners = 6

    static func findGroups(_ contacts: [ContactFingerprint]) -> [ContactMatchGroup] {
        let n = contacts.count
        guard n > 1 else { return [] }
        var phoneOwners: [String: [Int]] = [:]
        var emailOwners: [String: [Int]] = [:]
        var nameOwners: [String: [Int]] = [:]
        for (i, c) in contacts.enumerated() {
            for p in c.phones { phoneOwners[p, default: []].append(i) }
            for e in c.emails { emailOwners[e, default: []].append(i) }
            if !c.nameKey.isEmpty { nameOwners[c.nameKey, default: []].append(i) }
        }

        var edges: [(Int, Int, MatchReason)] = []
        func star(_ owners: [String: [Int]], _ reason: MatchReason) {
            for list in owners.values where list.count > 1 && list.count <= maxSharedOwners {
                for k in 1..<list.count { edges.append((list[0], list[k], reason)) }
            }
        }
        star(phoneOwners, .samePhone)
        star(emailOwners, .sameEmail)
        for list in nameOwners.values where list.count > 1 && list.count <= 50 {
            for a in 0..<(list.count - 1) {
                for b in (a + 1)..<list.count {
                    let i = list[a], j = list[b]
                    if !contacts[i].hasContactInfo || !contacts[j].hasContactInfo {
                        edges.append((i, j, .sameName))
                    }
                }
            }
        }

        var uf = UnionFind(count: n)
        for (i, j, _) in edges { uf.union(i, j) }

        var reasonsByRoot: [Int: Set<MatchReason>] = [:]
        for (i, _, reason) in edges { reasonsByRoot[uf.find(i), default: []].insert(reason) }

        var components: [Int: [Int]] = [:]
        for i in 0..<n { components[uf.find(i), default: []].append(i) }

        var result: [ContactMatchGroup] = []
        for (root, members) in components where members.count > 1 {
            var reasons = reasonsByRoot[root] ?? []
            let keys = Set(members.map { contacts[$0].nameKey })
            if keys.count == 1, let only = keys.first, !only.isEmpty { reasons.insert(.sameName) }
            var compatible = true
            outer: for a in 0..<members.count {
                for b in (a + 1)..<members.count where !namesCompatible(contacts[members[a]], contacts[members[b]]) {
                    compatible = false
                    break outer
                }
            }
            result.append(ContactMatchGroup(members: members.sorted(), reasons: reasons,
                                            confidence: compatible ? .likely : .review))
        }
        return result.sorted { $0.members[0] < $1.members[0] }
    }

    /// Equal names, a missing name, or one name contained in the other ("John" vs "John Smith").
    static func namesCompatible(_ a: ContactFingerprint, _ b: ContactFingerprint) -> Bool {
        if a.nameKey.isEmpty || b.nameKey.isEmpty { return true }
        return a.nameTokens.isSubset(of: b.nameTokens) || b.nameTokens.isSubset(of: a.nameTokens)
    }
}
