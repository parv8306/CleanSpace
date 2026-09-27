import SwiftUI
import UIKit

/// The person's choice of System, Light or Dark, saved across launches.
///
/// Applied by overriding the window's interface style, so every screen, sheet, alert and system
/// picker follows it, and all of CleanSpace's colors (defined for both modes in `Theme`) resolve
/// correctly. System removes the override and follows the iPhone's setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "cleanspace.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    static func apply(_ mode: AppearanceMode) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                    window.overrideUserInterfaceStyle = mode.interfaceStyle
                }
            }
        }
    }
}
