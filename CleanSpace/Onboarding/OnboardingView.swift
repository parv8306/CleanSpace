import SwiftUI

/// Shown once, on the first launch. Three short pages, then the dashboard. Later launches show
/// the opening animation instead. Nothing here asks for permissions.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var page = 0

    private let pages: [(title: String, message: String)] = [
        ("See what's taking space",
         "CleanSpace finds duplicate and look-alike photos, screenshots, large videos, duplicate contacts and old events, and shows how much each could free."),
        ("Review before anything goes",
         "You choose every item on one review screen. Deleted photos stay in Recently Deleted for 30 days, so you can change your mind."),
        ("Private by design",
         "Everything is analyzed on your iPhone. No accounts, no servers and no tracking. Keep private photos in a PIN-locked vault.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages.count - 1 {
                    Button("Skip") { app.completeOnboarding() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .padding(.horizontal, Theme.Spacing.l)
                        .frame(height: 44)
                }
            }
            .frame(height: 52)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPage(title: pages[index].title, message: pages[index].message) {
                        switch index {
                        case 0: StorageArt()
                        case 1: ReviewArt()
                        default: PrivacyArt()
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: page)

            VStack(spacing: Theme.Spacing.l) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.Palette.brand : Theme.Palette.track)
                            .frame(width: index == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(page + 1) of \(pages.count)")

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                    } else {
                        app.completeOnboarding()
                    }
                } label: {
                    PrimaryButtonLabel(title: page < pages.count - 1 ? "Continue" : "Get Started")
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(AppBackdrop())
        .interactiveDismissDisabled()
    }
}

private struct OnboardingPage<Art: View>: View {
    let title: String
    let message: String
    @ViewBuilder let art: () -> Art

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            art()
                .frame(height: 260)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            Spacer(minLength: 0)
        }
    }
}

/// Page 1: the water gauge with the kinds of things CleanSpace finds around it.
private struct StorageArt: View {
    var body: some View {
        ZStack {
            LiquidGauge(fraction: 0.72, freeable: 0.14, value: "72%", caption: "full", ringWidth: 2)
                .frame(width: 180, height: 180)
            chip("Duplicates", CleanupCategory.duplicatePhotos).offset(x: -110, y: -80)
            chip("Large videos", CleanupCategory.largeVideos).offset(x: 112, y: -30)
            chip("Screenshots", CleanupCategory.screenshots).offset(x: -96, y: 78)
        }
    }

    private func chip(_ title: String, _ category: CleanupCategory) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbol).foregroundStyle(category.tint)
            Text(title).foregroundStyle(Theme.Palette.ink)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassSurface(cornerRadius: 16)
    }
}

/// Page 2: a small stack of photos, one marked to keep and one selected for review.
private struct ReviewArt: View {
    var body: some View {
        ZStack {
            photo(Theme.Palette.similar).rotationEffect(.degrees(-10)).offset(x: -64, y: 12)
            photo(Theme.Palette.screenshots).rotationEffect(.degrees(9)).offset(x: 64, y: 12)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white, Theme.Palette.brand)
                        .offset(x: 72, y: -4)
                }
            photo(Theme.Palette.duplicates)
                .overlay(alignment: .bottom) {
                    Label("Keep", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Palette.success, in: Capsule())
                        .padding(.bottom, 10)
                }
        }
    }

    private func photo(_ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 120, height: 150)
            .overlay(Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(.white.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 3))
            .shadow(color: Theme.Palette.shadow, radius: 12, y: 6)
    }
}

/// Page 3: the shield, with what stays on the device.
private struct PrivacyArt: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(Theme.Palette.brand)
                .frame(width: 124, height: 124)
                .background(Theme.Palette.brandSoft, in: Circle())
            HStack(spacing: Theme.Spacing.s) {
                tag("iphone", "On device")
                tag("icloud.slash", "No uploads")
                tag("hand.raised.fill", "No tracking")
            }
        }
    }

    private func tag(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassSurface(cornerRadius: 16)
    }
}
