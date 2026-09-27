import SwiftUI

/// A sine-wave surface filled downward. `level` is the fill height as a fraction of the rect.
/// Deliberately not animatable: callers drive level and phase from a clock so the two never
/// fight each other inside one animation.
struct WaveShape: Shape {
    var level: Double
    var amplitude: Double = 0.035
    var phase: Double = 0
    var frequency: Double = 1.2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }
        let clamped = min(max(level, 0), 1)
        let baseline = rect.maxY - rect.height * CGFloat(clamped)
        // Flatten the wave near empty and full so it never spills past the edges.
        let damping = min(clamped, 1 - clamped, 0.12) / 0.12
        let amp = rect.height * CGFloat(amplitude * damping)
        let steps = 48
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0...steps {
            let rel = Double(i) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(rel)
            let y = baseline + CGFloat(sin(rel * .pi * 2 * frequency + phase)) * amp
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Static drawing of the water gauge: a glass circle filled with blue water to `fraction`,
/// with the part CleanSpace could free drawn as a lighter aqua band at the surface.
/// Used directly by the widget; the app wraps it in `LiquidGauge` for motion.
struct LiquidGaugeContent: View {
    let fraction: Double
    var freeable: Double = 0
    var phase: Double = 0
    var ringWidth: CGFloat = 5

    var body: some View {
        let used = min(max(fraction, 0), 1)
        let band = min(max(freeable, 0), used)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.Palette.surface, Theme.Palette.surfaceSunken],
                                     startPoint: .top, endPoint: .bottom))
            WaveShape(level: used + 0.018, amplitude: 0.032, phase: phase * 0.8 + 2.1)
                .fill(Theme.Palette.waterFoam.opacity(0.35))
            if band > 0.004 {
                WaveShape(level: used, amplitude: 0.03, phase: phase)
                    .fill(Theme.Palette.waterFoam.opacity(0.85))
            }
            WaveShape(level: used - band, amplitude: 0.03, phase: phase)
                .fill(LinearGradient(colors: [Theme.Palette.water, Theme.Palette.waterDeep],
                                     startPoint: .top, endPoint: .bottom))
            // Glass highlight
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .scaleEffect(x: 0.62, y: 0.3, anchor: .top)
                .padding(.top, 8)
        }
        .clipShape(Circle())
        .padding(ringWidth + 4)
        .background(
            Circle().fill(Theme.Palette.brandSoft.opacity(0.5))
        )
        .overlay(
            Circle().strokeBorder(
                LinearGradient(colors: [Theme.Palette.glassEdge, Theme.Palette.water.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: ringWidth)
        )
    }
}

/// The app's animated water gauge.
///
/// - Fills from empty to the real value when it first appears, and glides to new values
///   (for example after a cleanup) instead of jumping.
/// - The water moves gently; motion pauses when the view is off screen and is replaced by a
///   still image when Reduce Motion is on.
/// - The label is drawn twice: dark above the waterline and white below it, so it stays
///   readable at any fill level.
/// - While scanning, a soft light sweeps around the rim.
struct LiquidGauge: View {
    let fraction: Double
    var freeable: Double = 0
    var isScanning = false
    var value: String?
    var caption: String?
    var ringWidth: CGFloat = 6
    var fillDuration: Double = 1.4
    /// When false the gauge starts at its value instead of filling up from empty.
    var animateOnAppear = true
    /// Changing this empties the water and fills it back up to the real value over `fillDuration`.
    var refillToken = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var from: Double = 0
    @State private var to: Double = 0
    @State private var start = Date()
    @State private var isVisible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isVisible)) { context in
            let now = context.date
            let level = reduceMotion ? fraction : currentLevel(at: now)
            let phase = reduceMotion ? 0.6 : now.timeIntervalSinceReferenceDate * 1.3
            let band = fraction > 0 ? freeable * (level / fraction) : 0
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    LiquidGaugeContent(fraction: level, freeable: band, phase: phase, ringWidth: ringWidth)
                    if value != nil || caption != nil {
                        label(side: side, color: Theme.Palette.ink)
                        label(side: side, color: .white)
                            .mask(
                                WaveShape(level: level, amplitude: 0.03, phase: phase)
                                    .padding(ringWidth + 4)
                            )
                    }
                    if !reduceMotion {
                        WaterEffects(level: level, phase: phase, time: now.timeIntervalSinceReferenceDate)
                            .padding(ringWidth + 4)
                            .clipShape(Circle())
                            .allowsHitTesting(false)
                    }
                    if isScanning && !reduceMotion {
                        Circle()
                            .trim(from: 0, to: 0.22)
                            .stroke(
                                AngularGradient(colors: [Theme.Palette.cyan.opacity(0), Theme.Palette.cyan],
                                                center: .center, startAngle: .degrees(0), endAngle: .degrees(80)),
                                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                            .rotationEffect(.degrees(now.timeIntervalSinceReferenceDate * 220))
                            .padding(ringWidth / 2)
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            isVisible = true
            from = (reduceMotion || !animateOnAppear) ? fraction : 0
            to = fraction
            start = Date()
        }
        .onDisappear { isVisible = false }
        .onChange(of: fraction) { _, newValue in
            from = currentLevel(at: Date())
            to = newValue
            start = Date()
        }
        .onChange(of: refillToken) { _, _ in
            guard !reduceMotion else { return }
            from = 0
            to = fraction
            start = Date()
        }
    }

    private func currentLevel(at date: Date) -> Double {
        let duration = from == 0 ? fillDuration : 1.0
        let t = min(max(date.timeIntervalSince(start) / duration, 0), 1)
        let eased = 1 - pow(1 - t, 3)
        return from + (to - from) * eased
    }

    private func label(side: CGFloat, color: Color) -> some View {
        VStack(spacing: side * 0.01) {
            if let value {
                Text(value)
                    .font(.system(size: side * 0.2, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: max(side * 0.07, 11), weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, side * 0.16)
        .offset(y: -side * 0.04)
    }
}

/// The CleanSpace mark, matching the app icon: an open "C" that holds water, and a sparkle.
struct AppLogoMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(light: 0x3FD0FF, dark: 0x3FD0FF),
                                              Color(light: 0x1E5EFF, dark: 0x1E5EFF),
                                              Color(light: 0x0A227A, dark: 0x0A227A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            ZStack {
                Circle()
                    .trim(from: 0.133, to: 0.883)
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                WaveShape(level: 0.42, amplitude: 0.07, phase: 0.3)
                    .fill(Color(light: 0xD7F0FF, dark: 0xD7F0FF))
                    .clipShape(Circle())
                    .padding(size * 0.1)
            }
            .frame(width: size * 0.54, height: size * 0.54)
            .offset(x: -size * 0.03, y: size * 0.02)
            SparkleShape()
                .fill(.white)
                .frame(width: size * 0.17, height: size * 0.17)
                .offset(x: size * 0.25, y: -size * 0.03)
            SparkleShape()
                .fill(.white)
                .frame(width: size * 0.07, height: size * 0.07)
                .offset(x: size * 0.3, y: -size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Four-point sparkle (an astroid).
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0...120 {
            let t = Double(i) / 120 * .pi * 2
            let cx = cos(t), sy = sin(t)
            let x = c.x + r * CGFloat(copysign(pow(abs(cx), 3), cx))
            let y = c.y + r * CGFloat(copysign(pow(abs(sy), 3), sy))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

/// Just the top edge of a wave, for the foam line on the water's surface.
struct WaveLine: Shape {
    var level: Double
    var amplitude: Double = 0.03
    var phase: Double = 0
    var frequency: Double = 1.2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }
        let clamped = min(max(level, 0), 1)
        let baseline = rect.maxY - rect.height * CGFloat(clamped)
        let damping = min(clamped, 1 - clamped, 0.12) / 0.12
        let amp = rect.height * CGFloat(amplitude * damping)
        for i in 0...48 {
            let rel = Double(i) / 48
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(rel),
                                y: baseline + CGFloat(sin(rel * .pi * 2 * frequency + phase)) * amp)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// A soft bright line along the water's surface. (No bubbles: the motion stays calm.)
struct WaterEffects: View {
    let level: Double
    let phase: Double
    let time: TimeInterval

    var body: some View {
        WaveLine(level: level, amplitude: 0.03, phase: phase)
            .stroke(LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.55), .white.opacity(0.05)],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .accessibilityHidden(true)
    }
}
