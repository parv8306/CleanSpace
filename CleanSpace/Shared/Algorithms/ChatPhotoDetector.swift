import Foundation

/// Where a photo most likely came from, when there's evidence for it.
enum ChatPlatform: String, CaseIterable, Identifiable, Sendable {
    case whatsapp, telegram, messenger, signal, snapchat, wechat, viber, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .telegram: "Telegram"
        case .messenger: "Messenger"
        case .signal: "Signal"
        case .snapchat: "Snapchat"
        case .wechat: "WeChat"
        case .viber: "Viber"
        case .other: "Other chat apps"
        }
    }
}

/// Best-effort detection of photos saved from messaging apps.
///
/// iOS doesn't record which app saved a photo, so this uses only signals PhotoKit exposes:
///
/// 1. **File name (strong).** Some apps name saved files in a recognisable way, for example
///    `IMG-20240105-WA0012.jpg` (WhatsApp), `telegram-…`, `received_1234567890.jpeg` (Messenger),
///    `signal-2024-…`, `mmexport…` (WeChat). Only this signal attributes a photo to a platform.
/// 2. **Compression footprint (weaker).** Chat apps re-encode photos as JPEG at fixed sizes and
///    strip location. A JPEG with no location whose long edge is exactly 1600 px (WhatsApp's
///    standard size) or 1280 / 2560 px (Telegram) is counted under "Other chat apps".
///    No iPhone camera produces these sizes, but a photo saved from a website could match.
///
/// Photos sent through iMessage keep their original data and can't be told apart from camera
/// photos, so they aren't detected.
enum ChatPhotoDetector {
    static let chatLongEdges: Set<Int> = [1600, 1280, 2560]

    static func platform(forFilename filename: String) -> ChatPlatform? {
        let name = filename.lowercased()
        if name.contains("whatsapp") || name.range(of: #"-wa\d{4}"#, options: .regularExpression) != nil {
            return .whatsapp
        }
        if name.contains("telegram") { return .telegram }
        if name.contains("messenger") || name.range(of: #"^received_\d{6,}"#, options: .regularExpression) != nil {
            return .messenger
        }
        if name.range(of: #"^signal-\d{4}-"#, options: .regularExpression) != nil { return .signal }
        if name.contains("snapchat") { return .snapchat }
        if name.hasPrefix("mmexport") { return .wechat }
        if name.contains("viber") { return .viber }
        return nil
    }

    static func classify(filename: String?, uniformType: String?, pixelWidth: Int, pixelHeight: Int,
                         hasLocation: Bool, isScreenshot: Bool) -> ChatPlatform? {
        guard !isScreenshot else { return nil }
        if let filename, let platform = platform(forFilename: filename) { return platform }
        let longEdge = max(pixelWidth, pixelHeight)
        let shortEdge = min(pixelWidth, pixelHeight)
        guard uniformType == "public.jpeg", !hasLocation, shortEdge > 0,
              chatLongEdges.contains(longEdge) else { return nil }
        return .other
    }
}
