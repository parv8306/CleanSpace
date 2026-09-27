import Contacts
import EventKit
import Photos
import SwiftUI

enum PermissionKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case photos
    case contacts
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: "Photos"
        case .contacts: "Contacts"
        case .calendar: "Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .contacts: "person.crop.circle"
        case .calendar: "calendar"
        }
    }

    var headline: String {
        switch self {
        case .photos: "Let CleanSpace look through your library"
        case .contacts: "Let CleanSpace check your contacts"
        case .calendar: "Let CleanSpace check your calendar"
        }
    }

    /// The plain-language promise shown before the system prompt.
    var explanation: String {
        switch self {
        case .photos:
            "Your photos stay on your iPhone. We use photo access only to find duplicates, screenshots and large videos."
        case .contacts:
            "Your contacts stay on your iPhone. We use contact access only to identify possible duplicates."
        case .calendar:
            "Your calendar stays on your iPhone. We use calendar access only to find old and duplicate events."
        }
    }

    struct Promise: Hashable {
        let symbol: String
        let text: String
    }

    var promises: [Promise] {
        switch self {
        case .photos:
            [Promise(symbol: "iphone", text: "Analyzed entirely on this device"),
             Promise(symbol: "icloud.slash", text: "Nothing is uploaded or shared"),
             Promise(symbol: "hand.raised", text: "Nothing is deleted until you approve it")]
        case .contacts:
            [Promise(symbol: "iphone", text: "Compared entirely on this device"),
             Promise(symbol: "icloud.slash", text: "Nothing is uploaded or shared"),
             Promise(symbol: "hand.raised", text: "Nothing changes until you approve it")]
        case .calendar:
            [Promise(symbol: "iphone", text: "Checked entirely on this device"),
             Promise(symbol: "repeat", text: "Repeating events are never touched"),
             Promise(symbol: "hand.raised", text: "Nothing is deleted until you approve it")]
        }
    }

    var deniedMessage: String {
        switch self {
        case .photos:
            "CleanSpace can't see your library, so photo, screenshot and video cleaning is unavailable. You can turn on access in Settings at any time."
        case .contacts:
            "CleanSpace can't see your contacts, so duplicate checking is unavailable. You can turn on access in Settings at any time."
        case .calendar:
            "CleanSpace needs Full Access to your calendar to find old and duplicate events. You can change this in Settings at any time."
        }
    }

    var restrictedMessage: String {
        "Access to \(title) is restricted on this iPhone, for example by Screen Time or a device profile. CleanSpace can't change that setting."
    }
}

enum AccessState: Equatable, Sendable {
    case notDetermined
    case full
    case limited
    case denied
    case restricted

    var canRead: Bool { self == .full || self == .limited }
}

/// Single source of truth for Photos and Contacts authorization.
@Observable
@MainActor
final class PermissionCenter {
    private(set) var photos: AccessState
    private(set) var contacts: AccessState
    private(set) var calendar: AccessState

    init() {
        photos = Self.currentPhotoState()
        contacts = Self.currentContactState()
        calendar = Self.currentCalendarState()
    }

    /// True when CleanSpace can read at least one of Photos, Contacts or Calendar.
    var anyReadable: Bool {
        photos.canRead || contacts.canRead || calendar.canRead
    }

    func state(_ kind: PermissionKind) -> AccessState {
        switch kind {
        case .photos: photos
        case .contacts: contacts
        case .calendar: calendar
        }
    }

    /// Re-reads both statuses (the user may have changed them in Settings).
    /// Returns which kinds changed.
    @discardableResult
    func refresh() -> Set<PermissionKind> {
        var changed = Set<PermissionKind>()
        let newPhotos = Self.currentPhotoState()
        let newContacts = Self.currentContactState()
        let newCalendar = Self.currentCalendarState()
        if newPhotos != photos { photos = newPhotos; changed.insert(.photos) }
        if newContacts != contacts { contacts = newContacts; changed.insert(.contacts) }
        if newCalendar != calendar { calendar = newCalendar; changed.insert(.calendar) }
        return changed
    }

    func request(_ kind: PermissionKind) async -> AccessState {
        switch kind {
        case .photos:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            photos = Self.map(status)
            return photos
        case .contacts:
            let store = CNContactStore()
            _ = try? await store.requestAccess(for: .contacts)
            contacts = Self.currentContactState()
            return contacts
        case .calendar:
            let store = EKEventStore()
            _ = try? await store.requestFullAccessToEvents()
            calendar = Self.currentCalendarState()
            return calendar
        }
    }

    static func currentPhotoState() -> AccessState {
        map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    static func currentContactState() -> AccessState {
        map(CNContactStore.authorizationStatus(for: .contacts))
    }

    static func currentCalendarState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .full
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied   // denied, or write-only access (which can't read events)
        }
    }

    static func map(_ status: PHAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: .full
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ status: CNAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: return .full
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        default:
            // iOS 18 added `.limited` (raw value 4) for contacts shared selectively.
            return status.rawValue == 4 ? .limited : .denied
        }
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
