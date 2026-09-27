import Foundation
import UIKit
import UserNotifications

/// App facts shown in Settings and About.
enum AppInfo {
    static let name = "CleanSpace"
    static let tagline = "Make room for what matters."

    /// Set this to your support address to show "Send Feedback" in Settings.
    /// It stays hidden while this is nil, so there's never a button that goes nowhere.
    static let feedbackEmail: String? = nil

    /// A ready-to-send feedback email, or nil while `feedbackEmail` isn't set.
    @MainActor
    static var feedbackURL: URL? {
        guard let feedbackEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "CleanSpace \(version) feedback"),
            URLQueryItem(name: "body", value: "\n\n\nCleanSpace \(version) (\(build)), iOS \(UIDevice.current.systemVersion)")
        ]
        return components.url
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }

    static let features: [(symbol: String, text: String)] = [
        ("photo.on.rectangle.angled", "On-device scanning of every photo you allow"),
        ("plus.square.on.square", "Exact duplicate photo detection"),
        ("square.on.square", "Similar photo detection"),
        ("camera.viewfinder", "Screenshot cleanup"),
        ("bubble.left.and.bubble.right.fill", "Chat photo discovery"),
        ("video.fill", "Large video discovery and compression"),
        ("person.2.fill", "Duplicate contact detection and merging"),
        ("calendar", "Old and duplicate calendar events"),
        ("lock.square.stack.fill", "Encrypted private vault"),
        ("rectangle.stack.fill", "Home and Lock Screen storage widget")
    ]

    struct Release: Identifiable {
        let version: String
        let notes: [String]
        var id: String { version }
    }

    static let releases: [Release] = [
        Release(version: "1.0.0", notes: [
            "Say hello to CleanSpace: a new name, a new blue look and a new icon.",
            "A redesigned dashboard with a live water gauge that fills to your real storage.",
            "A clearer scan button that shows each stage as it runs.",
            "A new cleanup animation and a space-freed summary that counts up your results.",
            "Settings rebuilt: every Access row now works, with clear status badges.",
            "Weekly scan reminders, and a button to clear CleanSpace's temporary files.",
            "Compress videos, swipe mode, a private vault, calendar cleanup and a widget.",
            "Duplicate Photos (exact copies, confirmed by content) is now separate from Similar Photos.",
            "New Chat Photos category for photos likely saved from messaging apps.",
            "Every burst frame is now scanned, and photos with only a small preview on your iPhone are no longer skipped.",
            "Large Videos now includes every video of 25 MB or more.",
            "Choose System, Light or Dark appearance in Settings.",
            "A redesigned PIN screen for the private vault.",
            "Popups now open full screen on frosted glass.",
            "Video compression rebuilt: it aims for the size you choose and checks the result plays.",
            "Cleanup History shows thumbnails of what you deleted.",
            "Finishing a scan no longer selects anything; suggestions appear when you open a category.",
            "A calmer storage display, softer blues and more compact buttons.",
            "Scan status is now exact: scanning, analyzing, complete or didn't finish.",
            "Faster scans: unchanged photos are skipped on later scans.",
            "Recover deleted items, now in Cleanup History and Settings.",
            "Apple's Liquid Glass on cards, buttons and bars (iOS 26 and later).",
            "Nothing is selected until you tap Select suggested.",
            "A launch animation that draws the logo and fills it with water.",
            "The water gauge shows how full your iPhone is.",
            "A clearer swipe-mode demo, and popup text in glass panels.",
            "Popups close with one larger glass X, which responds on the first tap.",
            "Rounder buttons.",
            "Tap the water for a Quick Clean.",
            "A calmer sapphire blue, and a cleaner light mode.",
            "Three short pages on first launch, and a new opening animation.",
            "Cleanup categories are now photo cards showing your own first photos.",
            "Cancelling a Quick Clean deselects what it picked, and every selection bar has Clear.",
            "A one-line selection bar, clearer buttons on photo cards, and a contact card with photos.",
            "Popups open with real examples from your library.",
            "A Battery card with your iPhone's real battery status.",
            "Faster launches and rescans: file sizes are remembered between scans.",
            "A faster first scan, and a lighter sky blue for the water and the Scan button."
        ])
    ]
}

/// Optional weekly local notification reminding the person to scan. Nothing leaves the device.
enum ScanReminder {
    static let identifier = "cleanspace.weeklyScanReminder"
    static let defaultsKey = "cleanspace.scanReminder"

    /// Asks for notification permission if needed, then schedules Sundays at 10:00.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Time for a quick clean"
        content.body = "See how much space CleanSpace can free up this week."
        content.sound = .default
        var components = DateComponents()
        components.weekday = 1
        components.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// True if notifications are allowed and the reminder is actually scheduled.
    static func isActive() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        let pending = await center.pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier }
    }
}

/// Removes CleanSpace's own temporary and cache files (leftovers from compression, picker
/// copies and so on). Never touches photos, contacts, events or the vault.
enum TemporaryFiles {
    static func clear() -> Int64 {
        let fm = FileManager.default
        var roots = [fm.temporaryDirectory]
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first { roots.append(caches) }
        var freed: Int64 = 0
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.lastPathComponent != "VaultPlayback" {
                let size = allocatedSize(of: url)
                if (try? fm.removeItem(at: url)) != nil { freed += size }
            }
        }
        return freed
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            var total: Int64 = 0
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
            while let child = enumerator?.nextObject() as? URL {
                let childValues = try? child.resourceValues(forKeys: keys)
                total += Int64(childValues?.totalFileAllocatedSize ?? childValues?.fileAllocatedSize ?? 0)
            }
            return total
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
