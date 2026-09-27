import SwiftUI

// CleanSpace's reusable components. Screens compose these instead of restyling from scratch,
// so cards, buttons, icons and headers look the same everywhere. Tokens live in `Theme`
// (`CleanSpaceTheme`).

/// The app's icon style: a colored symbol on a soft square of the same color.
struct CleanSpaceIcon: View {
    let symbol: String
    var tint: Color = Theme.Palette.brand
    var size: CGFloat = 44
    /// Accepted for older call sites; the soft style uses `tint` only.
    var colors: [Color]?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Apple's Liquid Glass on iOS 26 and later; a quiet material or solid tint before that.
/// Used only for controls and floating bars, where Apple uses it, never behind body content.
enum GlassRecipe {
    @available(iOS 26.0, *)
    static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    @ViewBuilder
    func csGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(GlassRecipe.glass(tint: tint, interactive: interactive), in: shape)
        } else if let tint {
            background(tint, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

/// The app's one button style: compact capsules with a clear press state and 44 pt touch targets.
struct CSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    var compact = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, compact ? 14 : 20)
            .frame(minHeight: compact ? 32 : 44)
            .foregroundStyle(foreground)
            .modifier(ButtonSurface(kind: kind))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .frame(minHeight: 44)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive: .white
        case .secondary: Theme.Palette.brand
        }
    }

    private struct ButtonSurface: ViewModifier {
        let kind: Kind
        func body(content: Content) -> some View {
            switch kind {
            case .primary: content.csGlass(in: Capsule(), tint: Theme.Palette.brand, interactive: true)
            case .destructive: content.csGlass(in: Capsule(), tint: Theme.Palette.coral, interactive: true)
            case .secondary:
                if #available(iOS 26.0, *) {
                    content.glassEffect(GlassRecipe.glass(tint: nil, interactive: true), in: Capsule())
                } else {
                    content.background(Theme.Palette.brandSoft, in: Capsule())
                }
            }
        }
    }
}

/// Section title with an optional trailing accessory.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// "12 selected" capsule.
struct SelectionBadge: View {
    let count: Int

    var body: some View {
        Text("\(count.formatted()) selected")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Palette.brand)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.Palette.brand.opacity(0.12), in: Capsule())
            .contentTransition(.numericText())
    }
}

/// Primary, secondary and destructive buttons with consistent shape and press feedback.
struct CleanSpaceButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    var systemImage: String?
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .primary:
                PrimaryButtonLabel(title: title, systemImage: systemImage)
            case .destructive:
                PrimaryButtonLabel(title: title, systemImage: systemImage, tint: Theme.Palette.coral)
            case .secondary:
                HStack(spacing: 8) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(title)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(Theme.Palette.brand)
                .background(Theme.Palette.brandSoft, in: Capsule())
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Frosted "glass" card for dark or gradient backdrops such as the vault.
struct GlassCard: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(GlassCard(padding: padding))
    }

    /// Staggered entrance: fade, slight rise and scale, delayed by position.
    func entrance(_ visible: Bool, index: Int) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 18)
            .scaleEffect(visible ? 1 : 0.98)
            .animation(Theme.Motion.entrance.delay(Double(index) * Theme.Motion.stagger), value: visible)
    }
}

/// Small reassuring card about on-device privacy.
struct PrivacyCard: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.brand)
                .frame(width: 38, height: 38)
                .background(Theme.Palette.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Your data stays on your iPhone.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Everything is analyzed on this device. No servers, accounts or analytics.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

/// Names from the design brief, mapped to the components that implement them.
typealias CleanSpaceCard = CardBackground
