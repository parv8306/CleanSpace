import SwiftUI

/// Six-digit PIN entry: individual boxes that glow as they fill, and a custom keypad.
/// The PIN itself is never shown, only filled boxes. Calls `onComplete` once all digits are in.
struct PasscodePad: View {
    let title: String
    var message: String?
    var isError = false
    var biometricSymbol: String?
    var onBiometric: (() -> Void)?
    var isDisabled = false
    let onComplete: (String) -> Void

    @State private var digits = ""
    @State private var shake = 0

    private let length = PasscodeStore.length
    private let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["bio", "0", "del"]]

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)
                Text(message ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(isError ? Theme.Palette.coral : Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 40, alignment: .top)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: message)
            }

            PinBoxes(filled: digits.count, length: length, isError: isError)
                .modifier(ShakeEffect(shakes: CGFloat(shake)))
                .animation(.default, value: shake)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("PIN")
                .accessibilityValue("\(digits.count) of \(length) digits entered")

            VStack(spacing: 14) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.self) { key in keyView(key) }
                    }
                }
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
        }
        .onChange(of: isError) { _, error in
            if error {
                shake += 1
                digits = ""
            }
        }
        .sensoryFeedback(.error, trigger: shake)
        .sensoryFeedback(.impact(weight: .light), trigger: digits.count)
    }

    @ViewBuilder
    private func keyView(_ key: String) -> some View {
        switch key {
        case "bio":
            if let biometricSymbol, let onBiometric {
                Button(action: onBiometric) {
                    Image(systemName: biometricSymbol)
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.Palette.brand)
                        .frame(width: 74, height: 74)
                }
                .accessibilityLabel("Unlock with biometrics")
            } else {
                Color.clear.frame(width: 74, height: 74)
            }
        case "del":
            Button {
                if !digits.isEmpty {
                    withAnimation(.spring(duration: 0.25)) { _ = digits.removeLast() }
                }
            } label: {
                Image(systemName: "delete.backward")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 74, height: 74)
            }
            .accessibilityLabel("Delete")
            .disabled(digits.isEmpty)
        default:
            Button {
                guard digits.count < length else { return }
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) { digits.append(key) }
                if digits.count == length {
                    let entered = digits
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        digits = ""
                        onComplete(entered)
                    }
                }
            } label: {
                Text(key)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 74, height: 74)
                    .background(
                        Circle()
                            .fill(Theme.Palette.surface)
                            .shadow(color: Theme.Palette.shadow, radius: 6, y: 3)
                    )
                    .overlay(Circle().strokeBorder(Theme.Palette.separator, lineWidth: 1))
            }
            .buttonStyle(KeypadButtonStyle())
        }
    }
}

/// The six boxes. Filled boxes use the brand gradient with a dot; the next box to fill is
/// outlined in blue; errors turn every box red.
struct PinBoxes: View {
    let filled: Int
    let length: Int
    var isError = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<length, id: \.self) { index in
                let isFilled = index < filled
                let isActive = index == filled && !isError
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFilled
                          ? AnyShapeStyle(isError ? LinearGradient(colors: [Theme.Palette.coral, Theme.Palette.coral], startPoint: .top, endPoint: .bottom) : Theme.brandGradient)
                          : AnyShapeStyle(Theme.Palette.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isError ? Theme.Palette.coral : (isActive ? Theme.Palette.brand : Theme.Palette.track),
                                          lineWidth: isActive || isError ? 2 : 1.2)
                    )
                    .overlay {
                        if isFilled {
                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 44, height: 54)
                    .shadow(color: (isFilled || isActive) ? Theme.Palette.brand.opacity(0.35) : .clear, radius: 8, y: 2)
                    .scaleEffect(isFilled ? 1.04 : 1)
                    .animation(.spring(duration: 0.3, bounce: 0.45), value: isFilled)
                    .animation(.easeOut(duration: 0.2), value: isActive)
            }
        }
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Glowing vault mark used at the top of the vault screens.
struct VaultHero: View {
    var size: CGFloat = 110
    var symbol = "lock.shield.fill"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.brand.opacity(0.28))
                .frame(width: size * 1.45, height: size * 1.45)
                .blur(radius: 24)
                .scaleEffect(breathe ? 1.06 : 0.94)
            Circle()
                .strokeBorder(Theme.Palette.cyan.opacity(0.35), lineWidth: 1.5)
                .frame(width: size * 1.28, height: size * 1.28)
            Circle()
                .fill(Theme.brandGradient)
                .frame(width: size, height: size)
                .shadow(color: Theme.Palette.brand.opacity(0.45), radius: 18, y: 10)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: size * 1.45)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityHidden(true)
    }
}

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 4), y: 0))
    }
}
