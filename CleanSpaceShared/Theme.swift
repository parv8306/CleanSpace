import SwiftUI
import UIKit

/// CleanSpace design tokens: a fresh, trustworthy blue system with neutral surfaces.
/// Blue carries the brand; category and status colors are used sparingly and always
/// paired with an icon or text so meaning never depends on color alone.
enum Theme {
    enum Palette {
        // Brand: a calm sapphire blue that matches the logo, with a quieter indigo companion.
        /// Primary blue: main actions, the water, selection.
        static let brand = Color(light: 0x2F5FD0, dark: 0x7AA2F7)
        /// Deep blue: pressed states and gradient ends.
        static let brandDeep = Color(light: 0x23479E, dark: 0x5B83E0)
        /// Light blue: highlights and the "can be freed" band.
        static let cyan = Color(light: 0x7FA3F2, dark: 0x9DB8F8)
        /// Indigo companion for secondary emphasis.
        static let indigo = Color(light: 0x5A55C8, dark: 0x9A97F0)
        /// The water in the storage bubble and the Scan button: a lighter sky blue, so they stand
        /// apart from the sapphire used by every other button.
        static let water = Color(light: 0x3E9BEF, dark: 0x5DB2F5)
        static let waterDeep = Color(light: 0x1F74D1, dark: 0x2F82DC)
        static let waterFoam = Color(light: 0x9FD0FA, dark: 0xA5D6FB)
        static let scan = Color(light: 0x2A86E0, dark: 0x2F7FD8)
        /// Soft blue wash for icon wells and highlighted rows.
        static let brandSoft = Color(light: 0xE9EFFB, dark: 0x16213A)

        // Text
        static let ink = Color(light: 0x111827, dark: 0xEDF0F6)
        static let secondaryText = Color(light: 0x5F6878, dark: 0x9BA3B4)

        // Surfaces
        static let background = Color(light: 0xF2F4F8, dark: 0x080A0F)
        static let surface = Color(light: 0xFFFFFF, dark: 0x141821)
        static let surfaceSunken = Color(light: 0xEBEEF3, dark: 0x1B202B)
        static let track = Color(light: 0xDDE2EA, dark: 0x272E3C)
        static let placeholder = Color(light: 0xE6EAF0, dark: 0x1B212D)
        /// Tint laid over the glass material in popups, for readable text.
        static let glassTint = Color(light: 0xF2F4F8, dark: 0x080A0F, lightAlpha: 0.42, darkAlpha: 0.4)
        /// Soft top-edge highlight on glass surfaces.
        static let glassEdge = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.14)
        static let separator = Color(light: 0x111827, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
        static let shadow = Color(light: 0x1B2436, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.3)

        // Status
        static let coral = Color(light: 0xD64545, dark: 0xF07A7A)
        static let amber = Color(light: 0xB7791F, dark: 0xE8B659)
        static let success = Color(light: 0x2F855A, dark: 0x68C290)

        // Categories: distinct but muted, so the app reads as calm and professional.
        static let duplicates = Color(light: 0x4F5BC4, dark: 0x8F99EE)
        static let similar = Color(light: 0x7456C2, dark: 0xAD97EA)
        static let screenshots = Color(light: 0x2F7FB8, dark: 0x7DB8E3)
        static let chat = Color(light: 0x2E8B57, dark: 0x6FC593)
        static let videos = Color(light: 0xC0485E, dark: 0xEE8C9C)
        static let blurry = Color(light: 0xB7791F, dark: 0xE8B659)
        static let contacts = Color(light: 0xC0672F, dark: 0xEBA06F)
        static let calendar = Color(light: 0xB84D7F, dark: 0xE890B7)

        // Tools
        static let vault = Color(light: 0x4F5BC4, dark: 0x8F99EE)
        static let compress = Color(light: 0xB7791F, dark: 0xE8B659)
        static let swipe = Color(light: 0x2F7FB8, dark: 0x7DB8E3)

        // Vault backdrop
        static let vaultTop = Color(light: 0xE4EBFA, dark: 0x0E1628)
        static let vaultBottom = Color(light: 0xF2F4F8, dark: 0x080A0F)
    }

    /// Brand gradient, light at the top-left to deep at the bottom-right, as in the icon.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [Palette.brand, Palette.indigo],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Horizontal gradient for primary buttons.
    static var buttonGradient: LinearGradient {
        LinearGradient(colors: [Palette.brand, Palette.brandDeep], startPoint: .leading, endPoint: .trailing)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        /// The three-step scale: small for chips and thumbnails, medium for rows and tiles,
        /// large for major cards and primary components.
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let card: CGFloat = 24
        static let tile: CGFloat = 12
        static let thumb: CGFloat = 8
    }

    /// Shadow recipes, so elevation looks the same everywhere.
    enum Shadow {
        static let cardRadius: CGFloat = 16
        static let cardY: CGFloat = 8
        static let raisedRadius: CGFloat = 24
        static let raisedY: CGFloat = 12
    }

    /// Animation timing, so motion feels the same everywhere.
    enum Motion {
        static let quick = Animation.snappy(duration: 0.25)
        static let standard = Animation.spring(duration: 0.45, bounce: 0.2)
        static let entrance = Animation.spring(duration: 0.55, bounce: 0.15)
        static let gauge = Animation.easeInOut(duration: 0.9)
        /// Delay between items in a staggered entrance.
        static let stagger: Double = 0.06
    }

    enum Typography {
        static let hero = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let bigNumber = Font.system(.title, design: .rounded, weight: .bold)
        static let number = Font.system(.title3, design: .rounded, weight: .semibold)
        static let rowNumber = Font.system(.body, design: .rounded, weight: .semibold)
        static let wordmark = Font.system(.title2, design: .rounded, weight: .heavy)
        static let sectionTitle = Font.system(.title3, design: .rounded, weight: .bold)
    }
}

/// The name used in the design brief. `Theme` and `CleanSpaceTheme` are the same thing.
typealias CleanSpaceTheme = Theme

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Theme.Radius.card)
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// Subtle press feedback for large custom buttons and cards.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Primary call-to-action style: brand gradient capsule with a soft blue shadow.
struct PrimaryButtonLabel: View {
    let title: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(.white)
        .modifier(TintedGlassCapsule(tint: tint ?? Theme.Palette.brand))
    }
}

/// Card and panel surface. Dark mode uses Apple's Liquid Glass (iOS 26 and later) or a frosted
/// material. Light mode layers a bright white frost over the glass, with a hairline and a soft
/// shadow, so cards stay crisp and separate on a light background instead of washing out.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if colorScheme == .light {
            lightSurface(content, shape: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [Theme.Palette.glassEdge, Theme.Palette.separator],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: Theme.Palette.shadow, radius: 12, x: 0, y: 5)
        }
    }

    @ViewBuilder
    private func lightSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(Color.white.opacity(0.78), in: shape)
                .glassEffect(.regular, in: shape)
                .shadow(color: Theme.Palette.shadow, radius: 14, x: 0, y: 6)
        } else {
            content
                .background(Color.white.opacity(0.82), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.Palette.separator, lineWidth: 0.75))
                .shadow(color: Theme.Palette.shadow, radius: 14, x: 0, y: 6)
        }
    }
}

/// Tinted, touch-responsive Liquid Glass for primary buttons; a solid capsule before iOS 26.
struct TintedGlassCapsule: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            content
                .background(Capsule().fill(tint))
                .shadow(color: tint.opacity(0.18), radius: 8, x: 0, y: 4)
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

/// The app's backdrop: a calm neutral base with faint blue and indigo washes for the glass to
/// pick up. Static, so it costs nothing while scrolling.
struct AppBackdrop: View {
    var body: some View {
        ZStack {
            Theme.Palette.background
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack {
                    Circle()
                        .fill(Theme.Palette.brand.opacity(0.10))
                        .frame(width: w * 0.95)
                        .blur(radius: 80)
                        .position(x: w * 0.1, y: proxy.size.height * 0.08)
                    Circle()
                        .fill(Theme.Palette.indigo.opacity(0.08))
                        .frame(width: w * 0.8)
                        .blur(radius: 80)
                        .position(x: w * 0.95, y: proxy.size.height * 0.28)
                    Circle()
                        .fill(Theme.Palette.cyan.opacity(0.08))
                        .frame(width: w * 0.9)
                        .blur(radius: 90)
                        .position(x: w * 0.3, y: proxy.size.height * 0.85)
                }
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
