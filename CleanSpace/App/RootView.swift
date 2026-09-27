import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @State private var showSplash = true

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            DashboardView()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbar(.visible, for: .navigationBar)
                }
        }
        .glassCover(item: $app.review, chrome: .none, onDismiss: { app.reviewDismissed() }) { request in
            ReviewCleanupView(request: request)
                .environment(app)
        }
        .glassCover(item: $app.permissionPrompt, onDismiss: { app.permissionPromptDismissed() }) { kind in
            PermissionSheet(kind: kind)
                .environment(app)
        }
        .fullScreenCover(isPresented: $app.showOnboarding) {
            OnboardingView()
                .environment(app)
        }
        .overlay {
            if showSplash && !app.showOnboarding {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(1)
            }
        }
        .task {
            if app.showOnboarding {
                showSplash = false
                return
            }
            try? await Task.sleep(for: .milliseconds(1750))
            withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
        }
        .overlay {
            // Hide vault contents from the app switcher snapshot.
            if scenePhase != .active && app.path.contains(.vault) {
                PrivacyShield()
            }
        }
        .task { app.launch() }
        .onChange(of: appearance, initial: true) { _, value in
            AppearanceMode.apply(AppearanceMode(rawValue: value) ?? .system)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.didBecomeActive()
            case .background: app.didEnterBackground()
            default: break
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case let .category(category):
            CategoryDestination(category: category)
        case let .photoGroup(id):
            PermissionGate(kind: .photos) { PhotoGroupDetailView(groupID: id) }
        case let .contactGroup(id):
            PermissionGate(kind: .contacts) { ContactGroupDetailView(groupID: id) }
        case .swipeHub:
            PermissionGate(kind: .photos) { SwipeHubView() }
                .navigationTitle("Swipe Mode")
        case let .swipe(source):
            PermissionGate(kind: .photos) { SwipeDeckView(source: source) }
        case .compressVideos:
            PermissionGate(kind: .photos) { CompressVideosView() }
                .navigationTitle("Compress Videos")
        case .vault:
            VaultView()
        case .settings:
            SettingsView()
        case .history:
            CleanupHistoryView()
        }
    }
}

struct CategoryDestination: View {
    let category: CleanupCategory
    @Environment(AppState.self) private var app
    @State private var showInfo = false

    var body: some View {
        Group {
            switch category {
            case .duplicatePhotos:
                PermissionGate(kind: .photos) { SimilarPhotosView(kind: .duplicates) }
            case .similarPhotos:
                PermissionGate(kind: .photos) { SimilarPhotosView(kind: .similar) }
            case .chatPhotos:
                PermissionGate(kind: .photos) { ChatPhotosView() }
            case .blurryPhotos:
                PermissionGate(kind: .photos) { BlurryPhotosView() }
            case .screenshots:
                PermissionGate(kind: .photos) { ScreenshotsView() }
            case .largeVideos:
                PermissionGate(kind: .photos) { LargeVideosView() }
            case .duplicateContacts:
                PermissionGate(kind: .contacts) { DuplicateContactsView() }
            case .calendarEvents:
                PermissionGate(kind: .calendar) { CalendarCleanupView() }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About \(category.title)")
            }
        }
        .glassCover(isPresented: $showInfo) {
            CategoryInfoSheet(category: category).environment(app)
        }
    }
}

struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            AppLogoMark(size: 72)
        }
        .ignoresSafeArea()
    }
}

/// Opening animation on every launch after the first (the first shows the explainer pages).
/// Calm and brief: the mark resolves from a soft blur, the "C" draws and fills, a light sheen
/// crosses the tile, and the name settles into place.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var textIn = false

    var body: some View {
        ZStack {
            AppBackdrop()
            VStack(spacing: 24) {
                AnimatedLogo(start: start, isStatic: reduceMotion)
                    .frame(width: 112, height: 112)
                VStack(spacing: 6) {
                    Text("CleanSpace")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .tracking(textIn ? 0.2 : 3)
                    Text(AppInfo.tagline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .opacity(textIn ? 1 : 0)
                .offset(y: textIn ? 0 : 6)
            }
        }
        .onAppear {
            start = Date()
            withAnimation(.easeOut(duration: 0.6).delay(reduceMotion ? 0 : 0.6)) { textIn = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CleanSpace")
    }
}

/// The app mark, resolved from a start time.
private struct AnimatedLogo: View {
    let start: Date
    var isStatic = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isStatic)) { context in
            let t = isStatic ? 10 : context.date.timeIntervalSince(start)
            let appear = eased(t, from: 0, over: 0.55)
            let arc = eased(t, from: 0.2, over: 0.65)
            let water = eased(t, from: 0.45, over: 0.75)
            let sparkle = eased(t, from: 0.8, over: 0.45)
            let sheen = min(max((t - 0.95) / 0.6, 0), 1)
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let tileShape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                ZStack {
                    tileShape
                        .fill(LinearGradient(colors: [Color(light: 0x3FD0FF, dark: 0x3FD0FF),
                                                      Color(light: 0x1E5EFF, dark: 0x1E5EFF),
                                                      Color(light: 0x0A227A, dark: 0x0A227A)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color(light: 0x1E3A8A, dark: 0x000000).opacity(0.25 * appear), radius: 18, y: 10)

                    ZStack {
                        Circle()
                            .trim(from: 0.133, to: 0.133 + 0.75 * arc)
                            .stroke(.white, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                        WaveShape(level: 0.42 * water, amplitude: 0.06, phase: t * 1.8)
                            .fill(Color(light: 0xD7F0FF, dark: 0xD7F0FF))
                            .clipShape(Circle())
                            .padding(size * 0.1)
                    }
                    .frame(width: size * 0.54, height: size * 0.54)
                    .offset(x: -size * 0.03, y: size * 0.02)

                    SparkleShape()
                        .fill(.white)
                        .frame(width: size * 0.17, height: size * 0.17)
                        .scaleEffect(0.6 + 0.4 * sparkle)
                        .opacity(sparkle)
                        .offset(x: size * 0.25, y: -size * 0.03)
                    SparkleShape()
                        .fill(.white)
                        .frame(width: size * 0.07, height: size * 0.07)
                        .opacity(sparkle)
                        .offset(x: size * 0.3, y: -size * 0.15)

                    // A single light sheen crossing the tile once.
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: size * 0.45)
                        .rotationEffect(.degrees(20))
                        .offset(x: -size + CGFloat(sheen) * size * 2)
                        .opacity(sheen > 0 && sheen < 1 ? 1 : 0)
                        .mask(tileShape)
                }
                .frame(width: size, height: size)
                .scaleEffect(0.92 + 0.08 * appear)
                .opacity(appear)
                .blur(radius: (1 - appear) * 8)
            }
        }
        .accessibilityHidden(true)
    }

    private func eased(_ t: Double, from start: Double, over duration: Double) -> Double {
        let raw = min(max((t - start) / duration, 0), 1)
        return 1 - pow(1 - raw, 3)
    }
}
