import Foundation

enum Route: Hashable {
    case category(CleanupCategory)
    case photoGroup(String)
    case contactGroup(String)
    case swipeHub
    case swipe(SwipeSource)
    case compressVideos
    case vault
    case settings
    case history
}

/// Opens the shared Review screen for the given categories.
struct ReviewRequest: Identifiable, Equatable {
    let id = UUID()
    let categories: Set<CleanupCategory>
}

/// What the dashboard shows for a category row.
enum CategoryStatus: Equatable {
    case needsAccess
    case accessDenied
    case notScanned
    case scanning(Double?)
    case ready(detail: String, bytes: Int64?)
    case clean(String)
    case failed(String)
}
