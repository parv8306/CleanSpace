import SwiftUI

enum CleanupCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case duplicatePhotos
    case similarPhotos
    case screenshots
    case chatPhotos
    case largeVideos
    case blurryPhotos
    case duplicateContacts
    case calendarEvents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicatePhotos: "Duplicate Photos"
        case .similarPhotos: "Similar Photos"
        case .screenshots: "Screenshots"
        case .chatPhotos: "Chat Photos"
        case .largeVideos: "Large Videos"
        case .blurryPhotos: "Blurry Photos"
        case .duplicateContacts: "Duplicate Contacts"
        case .calendarEvents: "Calendar Events"
        }
    }

    /// Short line under the title on dashboard cards.
    var tagline: String {
        switch self {
        case .duplicatePhotos: "Exact copies"
        case .similarPhotos: "Look alike, not exact copies"
        case .screenshots: "Screenshots in your library"
        case .chatPhotos: "Likely saved from chat apps"
        case .largeVideos: "25 MB or larger"
        case .blurryPhotos: "Out of focus"
        case .duplicateContacts: "Matching contact details"
        case .calendarEvents: "Old and duplicate events"
        }
    }

    /// Explanation shown in the category information sheet.
    var explanation: String {
        switch self {
        case .duplicatePhotos:
            "These are exact copies of the same photo. CleanSpace confirms them by comparing the photos' actual content, groups them together and suggests keeping one, so you can remove the extras."
        case .similarPhotos:
            "These are different photos that look alike, such as several shots of the same moment, bursts or re-edits. Exact copies are listed under Duplicate Photos instead. CleanSpace suggests the best shot to keep."
        case .screenshots:
            "Screenshots found in the photos CleanSpace can access, newest first. Screenshots are often useful for a moment and then forgotten."
        case .chatPhotos:
            "Photos CleanSpace identifies as likely saved from messaging or chat apps. iOS doesn't record which app saved a photo, so this is a best guess from file names and the way chat apps compress photos. A platform is shown only when the file name says so."
        case .largeVideos:
            "Videos using 25 MB or more of storage, largest first. You can play each one, delete it, or compress it to keep a smaller copy."
        case .blurryPhotos:
            "Photos that look out of focus. This is a visual estimate, so nothing here is selected for you."
        case .duplicateContacts:
            "Contacts that appear to contain matching information, such as the same phone number or email. You can merge them or delete specific cards."
        case .calendarEvents:
            "Old past events and duplicate events on calendars you can edit. Repeating events are never changed."
        }
    }

    /// Lowercase noun used in sentences ("3 screenshots").
    var noun: String {
        switch self {
        case .duplicatePhotos: "duplicate"
        case .similarPhotos: "photo"
        case .screenshots: "screenshot"
        case .chatPhotos: "chat photo"
        case .largeVideos: "video"
        case .blurryPhotos: "blurry photo"
        case .duplicateContacts: "contact"
        case .calendarEvents: "event"
        }
    }

    var symbol: String {
        switch self {
        case .duplicatePhotos: "plus.square.on.square"
        case .similarPhotos: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .chatPhotos: "bubble.left.and.bubble.right.fill"
        case .largeVideos: "film"
        case .blurryPhotos: "camera.aperture"
        case .duplicateContacts: "person.2.fill"
        case .calendarEvents: "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .duplicatePhotos: Theme.Palette.duplicates
        case .similarPhotos: Theme.Palette.similar
        case .screenshots: Theme.Palette.screenshots
        case .chatPhotos: Theme.Palette.chat
        case .largeVideos: Theme.Palette.videos
        case .blurryPhotos: Theme.Palette.blurry
        case .duplicateContacts: Theme.Palette.contacts
        case .calendarEvents: Theme.Palette.calendar
        }
    }

    /// Two-tone icon gradient, light to rich, like an app icon.
    var gradient: [Color] {
        switch self {
        case .duplicatePhotos: [Color(light: 0x818CF8, dark: 0x818CF8), Color(light: 0x4F46E5, dark: 0x4F46E5)]
        case .similarPhotos: [Color(light: 0xC084FC, dark: 0xC084FC), Color(light: 0x7C3AED, dark: 0x7C3AED)]
        case .screenshots: [Color(light: 0x38BDF8, dark: 0x38BDF8), Color(light: 0x0369A1, dark: 0x0369A1)]
        case .chatPhotos: [Color(light: 0x4ADE80, dark: 0x4ADE80), Color(light: 0x15803D, dark: 0x15803D)]
        case .largeVideos: [Color(light: 0xFB7185, dark: 0xFB7185), Color(light: 0xE11D48, dark: 0xE11D48)]
        case .blurryPhotos: [Color(light: 0xFCD34D, dark: 0xFCD34D), Color(light: 0xD97706, dark: 0xD97706)]
        case .duplicateContacts: [Color(light: 0xFDBA74, dark: 0xFDBA74), Color(light: 0xEA580C, dark: 0xEA580C)]
        case .calendarEvents: [Color(light: 0xF9A8D4, dark: 0xF9A8D4), Color(light: 0xDB2777, dark: 0xDB2777)]
        }
    }

    var permission: PermissionKind {
        switch self {
        case .duplicateContacts: .contacts
        case .calendarEvents: .calendar
        default: .photos
        }
    }

    var isMedia: Bool { permission == .photos }

    /// The swipe-mode pile for this category, if it has one.
    var swipeSource: SwipeSource? {
        switch self {
        case .duplicatePhotos: .duplicates
        case .similarPhotos: .similar
        case .screenshots: .screenshots
        case .chatPhotos: .chat
        case .largeVideos: .largeVideos
        case .blurryPhotos: .blurry
        case .duplicateContacts, .calendarEvents: nil
        }
    }

    static let mediaCategories: [CleanupCategory] = [.duplicatePhotos, .similarPhotos, .blurryPhotos,
                                                     .screenshots, .chatPhotos, .largeVideos]
}
