import Photos
import PhotosUI
import UIKit

/// Presents iOS's "Manage selected photos" picker from the top-most view controller.
@MainActor
enum LimitedLibraryPicker {
    static func present(onChange: @escaping @MainActor () -> Void) {
        guard let presenter = topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { _ in
            Task { @MainActor in onChange() }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
