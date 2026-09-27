import Contacts
import Foundation

struct ContactScanResult: Sendable {
    let groups: [ContactGroup]
    let totalContacts: Int
}

struct ContactCleanupOutcome: Sendable {
    var deleted = 0
    var mergedGroups = 0
    var removedByMerge = 0
    var failed = 0
}

enum ContactCleanupError: Error {
    case missingContact
}

/// All Contacts framework access. Every method is synchronous and must be called off the main thread.
/// Note: we never request the `note` field (it needs a special entitlement and we don't need it).
enum ContactService {
    static func scanKeys() -> [CNKeyDescriptor] {
        [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)] + ([
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactMiddleNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactThumbnailImageDataKey
        ] as [CNKeyDescriptor])
    }

    static func mergeKeys() -> [CNKeyDescriptor] {
        [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)] + ([
            CNContactIdentifierKey,
            CNContactNamePrefixKey,
            CNContactGivenNameKey,
            CNContactMiddleNameKey,
            CNContactFamilyNameKey,
            CNContactNameSuffixKey,
            CNContactNicknameKey,
            CNContactOrganizationNameKey,
            CNContactDepartmentNameKey,
            CNContactJobTitleKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactUrlAddressesKey,
            CNContactSocialProfilesKey,
            CNContactInstantMessageAddressesKey,
            CNContactRelationsKey,
            CNContactDatesKey,
            CNContactBirthdayKey,
            CNContactImageDataKey,
            CNContactImageDataAvailableKey,
            CNContactThumbnailImageDataKey
        ] as [CNKeyDescriptor])
    }

    // MARK: Scan

    static func scan() throws -> ContactScanResult {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: scanKeys())
        request.sortOrder = .userDefault
        var contacts: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }

        let fingerprints = contacts.map { contact -> ContactFingerprint in
            var parts = [contact.givenName, contact.middleName, contact.familyName]
            if parts.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                parts = [contact.organizationName]
            }
            return ContactFingerprint(
                nameParts: parts,
                phones: contact.phoneNumbers.map { $0.value.stringValue },
                emails: contact.emailAddresses.map { $0.value as String }
            )
        }

        let groups = ContactDuplicateFinder.findGroups(fingerprints).map { match -> ContactGroup in
            let records = match.members.map { record(from: contacts[$0]) }
            let id = records.map(\.id).min() ?? UUID().uuidString
            return ContactGroup(id: id, contacts: records, reasons: match.reasons, confidence: match.confidence)
        }
        let sorted = groups.sorted {
            if $0.confidence != $1.confidence { return $0.confidence == .likely }
            return $0.contacts[0].displayName.localizedCaseInsensitiveCompare($1.contacts[0].displayName) == .orderedAscending
        }
        return ContactScanResult(groups: sorted, totalContacts: contacts.count)
    }

    static func record(from contact: CNContact) -> ContactRecord {
        let phones = contact.phoneNumbers.map { $0.value.stringValue }
        let emails = contact.emailAddresses.map { $0.value as String }
        let formatted = (CNContactFormatter.string(from: contact, style: .fullName) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if !formatted.isEmpty {
            name = formatted
        } else if !contact.organizationName.isEmpty {
            name = contact.organizationName
        } else if let email = emails.first {
            name = email
        } else if let phone = phones.first {
            name = phone
        } else {
            name = "No Name"
        }
        return ContactRecord(id: contact.identifier,
                             displayName: name,
                             organization: contact.organizationName,
                             phones: phones,
                             emails: emails,
                             thumbnail: contact.thumbnailImageData)
    }

    // MARK: Cleanup

    static func apply(deletes: Set<String>, merges: [ContactMergePlan]) -> ContactCleanupOutcome {
        let store = CNContactStore()
        var outcome = ContactCleanupOutcome()

        for plan in merges {
            do {
                try merge(plan, store: store)
                outcome.mergedGroups += 1
                outcome.removedByMerge += plan.removedCount
            } catch {
                outcome.failed += plan.removedCount
            }
        }

        guard !deletes.isEmpty else { return outcome }
        let ids = Array(deletes)
        let idKeys = [CNContactIdentifierKey as CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(withIdentifiers: ids)
        let existing = (try? store.unifiedContacts(matching: predicate, keysToFetch: idKeys)) ?? []
        guard !existing.isEmpty else { return outcome }

        let request = CNSaveRequest()
        for contact in existing {
            if let mutable = contact.mutableCopy() as? CNMutableContact { request.delete(mutable) }
        }
        do {
            try store.execute(request)
        } catch {
            // One read-only entry (e.g. from an Exchange directory) can fail the whole batch —
            // retry one by one so everything that *can* be removed is removed.
            for contact in existing {
                guard let mutable = contact.mutableCopy() as? CNMutableContact else { continue }
                let single = CNSaveRequest()
                single.delete(mutable)
                try? store.execute(single)
            }
        }

        let remainingCount: Int
        if let remaining = try? store.unifiedContacts(matching: predicate, keysToFetch: idKeys) {
            remainingCount = remaining.count
        } else {
            remainingCount = 0
        }
        outcome.deleted = existing.count - remainingCount
        outcome.failed += remainingCount
        return outcome
    }

    /// Folds every other member into the chosen contact (union of phones, emails, addresses, URLs,
    /// social profiles, dates and relations; empty scalar fields are filled in), then removes the others
    /// in the same save request.
    static func merge(_ plan: ContactMergePlan, store: CNContactStore) throws {
        let predicate = CNContact.predicateForContacts(withIdentifiers: plan.memberIDs)
        let fetched = try store.unifiedContacts(matching: predicate, keysToFetch: mergeKeys())
        guard let source = fetched.first(where: { $0.identifier == plan.nameSourceID }),
              let primary = source.mutableCopy() as? CNMutableContact else {
            throw ContactCleanupError.missingContact
        }
        let others = fetched.filter { $0.identifier != plan.nameSourceID }
        guard !others.isEmpty else { return }

        for other in others { absorb(other, into: primary, takePhoto: plan.photoSourceID == nil) }

        if let photoID = plan.photoSourceID, photoID != plan.nameSourceID,
           let photoSource = fetched.first(where: { $0.identifier == photoID }),
           photoSource.imageDataAvailable, let data = photoSource.imageData {
            primary.imageData = data
        }

        let request = CNSaveRequest()
        request.update(primary)
        for other in others {
            if let mutable = other.mutableCopy() as? CNMutableContact { request.delete(mutable) }
        }
        try store.execute(request)
    }

    static func absorb(_ other: CNContact, into primary: CNMutableContact, takePhoto: Bool) {
        primary.phoneNumbers = union(primary.phoneNumbers, other.phoneNumbers) {
            ContactNormalizer.phoneKey($0.stringValue) ?? $0.stringValue
        }
        primary.emailAddresses = union(primary.emailAddresses, other.emailAddresses) {
            ($0 as String).lowercased()
        }
        primary.postalAddresses = union(primary.postalAddresses, other.postalAddresses) {
            CNPostalAddressFormatter.string(from: $0, style: .mailingAddress).lowercased()
        }
        primary.urlAddresses = union(primary.urlAddresses, other.urlAddresses) {
            ($0 as String).lowercased()
        }
        primary.socialProfiles = union(primary.socialProfiles, other.socialProfiles) {
            "\($0.service)|\($0.username)|\($0.urlString)".lowercased()
        }
        primary.instantMessageAddresses = union(primary.instantMessageAddresses, other.instantMessageAddresses) {
            "\($0.service)|\($0.username)".lowercased()
        }
        primary.contactRelations = union(primary.contactRelations, other.contactRelations) {
            $0.name.lowercased()
        }
        primary.dates = union(primary.dates, other.dates) {
            "\($0.year)-\($0.month)-\($0.day)"
        }
        if primary.organizationName.isEmpty { primary.organizationName = other.organizationName }
        if primary.departmentName.isEmpty { primary.departmentName = other.departmentName }
        if primary.jobTitle.isEmpty { primary.jobTitle = other.jobTitle }
        if primary.nickname.isEmpty { primary.nickname = other.nickname }
        if primary.birthday == nil { primary.birthday = other.birthday }
        if takePhoto, primary.imageData == nil, other.imageDataAvailable, let data = other.imageData {
            primary.imageData = data
        }
    }

    static func union<T: NSCopying & NSSecureCoding>(_ existing: [CNLabeledValue<T>],
                                                     _ incoming: [CNLabeledValue<T>],
                                                     key: (T) -> String) -> [CNLabeledValue<T>] {
        var seen = Set(existing.map { key($0.value) })
        var result = existing
        for labeled in incoming where seen.insert(key(labeled.value)).inserted {
            result.append(CNLabeledValue(label: labeled.label, value: labeled.value))
        }
        return result
    }
}
