import SwiftUI

/// The dashboard's storage visualization: the water orb resting in a still glass disc with a
/// soft halo. Used space is the water level; free space is the clear glass above it; the lighter
/// band at the surface is what CleanSpace can free. Nothing here rotates or pulses, so it never
/// reads as a loading indicator; the water only rises into place and glides when values change.
struct StorageRingGauge: View {
    let used: Double
    var freeable: Double = 0
    var isScanning = false
    var percentText: String
    var caption = "Used"
    var refillToken = 0
    var fillDuration: Double = 2.0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.Palette.water.opacity(0.16), Theme.Palette.water.opacity(0)],
                                         center: .center, startRadius: side * 0.3, endRadius: side * 0.52))
                Circle()
                    .fill(Theme.Palette.surface.opacity(0.6))
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(colors: [Theme.Palette.glassEdge, Theme.Palette.water.opacity(0.2)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5)
                    )
                    .shadow(color: Theme.Palette.shadow, radius: 12, y: 6)
                    .padding(side * 0.05)
                LiquidGauge(fraction: used, freeable: freeable, isScanning: false,
                            value: percentText, caption: caption, ringWidth: 2,
                            fillDuration: fillDuration, refillToken: refillToken)
                    .frame(width: side * 0.8, height: side * 0.8)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Theme.Motion.gauge, value: used)
        .animation(Theme.Motion.gauge, value: freeable)
    }
}

/// Custom scan mark for the Scan button: radar rings, a sweep that turns while scanning,
/// a sparkle "blip", and a ring that pings outward when a scan starts.
struct RadarIcon: View {
    let isScanning: Bool
    var size: CGFloat = 52

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pings = 0

    private struct Ping {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.18))
            Circle().stroke(.white.opacity(0.55), lineWidth: 1.5).padding(size * 0.13)
            Circle().stroke(.white.opacity(0.35), lineWidth: 1.2).padding(size * 0.29)
            if isScanning && !reduceMotion {
                TimelineView(.animation) { context in
                    sweep.rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 300))
                }
            } else {
                sweep.rotationEffect(.degrees(40))
            }
            Circle().fill(.white).frame(width: size * 0.12, height: size * 0.12)
            SparkleShape()
                .fill(.white)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.17, y: -size * 0.17)
                .opacity(isScanning ? 0.4 : 1)
            Circle()
                .stroke(.white, lineWidth: 2)
                .keyframeAnimator(initialValue: Ping(), trigger: pings) { content, value in
                    content.scaleEffect(value.scale).opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1.0, duration: 0.01)
                        CubicKeyframe(1.8, duration: 0.8)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0.9, duration: 0.01)
                        LinearKeyframe(0.0, duration: 0.8)
                    }
                }
        }
        .frame(width: size, height: size)
        .onChange(of: isScanning) { _, scanning in
            if scanning && !reduceMotion { pings += 1 }
        }
        .accessibilityHidden(true)
    }

    private var sweep: some View {
        Circle()
            .fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: 0.72),
                .init(color: .white.opacity(0.65), location: 1)
            ]), center: .center))
            .padding(size * 0.08)
    }
}
