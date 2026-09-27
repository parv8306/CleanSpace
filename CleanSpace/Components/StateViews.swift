import SwiftUI

/// Positive "nothing to do" state with a soft blue illustration.
struct EmptyStateView: View {
    var symbol = "sparkles"
    var title = "You're all clear"
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.brandSoft.opacity(0.6))
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(Theme.Palette.brandSoft)
                    .frame(width: 112, height: 112)
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: Theme.Palette.brand.opacity(0.35), radius: 12, y: 6)
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
                SparkleShape()
                    .fill(Theme.Palette.cyan)
                    .frame(width: 18, height: 18)
                    .offset(x: 52, y: -44)
                SparkleShape()
                    .fill(Theme.Palette.brand.opacity(0.6))
                    .frame(width: 10, height: 10)
                    .offset(x: -58, y: 30)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .accessibilityHidden(true)
            .padding(.bottom, Theme.Spacing.s)
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .foregroundStyle(Theme.Palette.brand)
                        .background(Theme.Palette.brandSoft, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, Theme.Spacing.s)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appeared = true }
        }
    }
}

/// Full-screen state while a cleaner scans: a pulsing scanner with real progress, then an
/// "Analyzing" step while results are compared (still not finished).
struct ScanningStateView: View {
    let title: String
    let phase: ScanPhase
    var unit = "items"
    var onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                if !reduceMotion {
                    ForEach(0..<2, id: \.self) { ring in
                        Circle()
                            .stroke(Theme.Palette.brand.opacity(0.35), lineWidth: 2)
                            .frame(width: 120, height: 120)
                            .phaseAnimator([0.0, 1.0]) { content, value in
                                content
                                    .scaleEffect(1 + 0.45 * value)
                                    .opacity(1 - value)
                            } animation: { value in
                                value == 1 ? .easeOut(duration: 2).delay(Double(ring)) : nil
                            }
                    }
                }
                Circle()
                    .fill(Theme.Palette.brandSoft)
                    .frame(width: 120, height: 120)
                if let fraction = phase.fraction {
                    ProgressRing(fraction: fraction, lineWidth: 7)
                        .frame(width: 104, height: 104)
                } else {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Theme.Palette.brand)
                }
            }
            .frame(width: 180, height: 180)
            Text(phase.isAnalyzing ? "Analyzing results" : title)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            if let counts = phase.counts, counts.total > 0 {
                Text("\(counts.done.formatted()) of \(counts.total.formatted()) \(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .contentTransition(.numericText())
            } else {
                Text(phase.isAnalyzing ? "Comparing and measuring. Almost done." : "Analyzing on this iPhone")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Label("Nothing leaves your iPhone", systemImage: "lock.shield.fill")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
            if let onCancel {
                Button("Stop scanning", role: .cancel, action: onCancel)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Palette.amber)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.secondaryText)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .padding(.top, Theme.Spacing.s)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(AngularGradient(colors: [Theme.Palette.cyan, Theme.Palette.brand, Theme.Palette.brandDeep], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Section header used above lists and grids in cleaner screens.
struct SummaryHeader: View {
    let title: String
    let subtitle: String
    var tint: Color = Theme.Palette.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.bigNumber)
                .foregroundStyle(Theme.Palette.ink)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
