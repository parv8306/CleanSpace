import SwiftUI

/// Remembers which categories the person asked not to explain again.
enum CategoryInfoPreferences {
    private static let key = "cleanspace.skipCategoryInfo"

    static func shouldShow(_ category: CleanupCategory) -> Bool {
        !(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(category.rawValue)
    }

    static func setShow(_ show: Bool, for category: CleanupCategory) {
        var skipped = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if show { skipped.remove(category.rawValue) } else { skipped.insert(category.rawValue) }
        UserDefaults.standard.set(Array(skipped), forKey: key)
    }
}

/// Full-screen explainer for a category. It opens with real examples from the person's own
/// library (for duplicates: the copy to keep and the suggested extra), then the explanation in a
/// glass panel, what was found, and the swipe demo where it applies.
struct CategoryInfoSheet: View {
    let category: CleanupCategory
    /// Shown when opened from the dashboard; nil when already inside the category.
    var onOpen: (() -> Void)?

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var dontShowAgain = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                    VStack(spacing: 10) {
                        Text(category.title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Palette.ink)
                            .multilineTextAlignment(.center)
                        Text(category.explanation)
                            .font(.body)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .glassSurface(cornerRadius: 26)

                    if case let .ready(detail, bytes) = app.status(for: category) {
                        HStack(spacing: 0) {
                            figure("Found", detail)
                            if let bytes {
                                Divider().frame(height: 36).padding(.horizontal, 16)
                                figure("Can be freed", Format.bytes(bytes))
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .glassSurface(cornerRadius: 22)
                        .accessibilityElement(children: .combine)
                    }

                    if category.swipeSource != nil {
                        SwipeDemoView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let onOpen {
                VStack(spacing: 4) {
                    Button {
                        CategoryInfoPreferences.setShow(!dontShowAgain, for: category)
                        dismiss()
                        onOpen()
                    } label: {
                        Text("Let's Go")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .modifier(TintedGlassCapsule(tint: Theme.Palette.brand))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityHint("Opens \(category.title)")
                    Toggle("Don't show this again", isOn: $dontShowAgain)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .tint(Theme.Palette.brand)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.2).delay(0.1)) { appeared = true }
        }
    }

    // MARK: Hero (real examples)

    @ViewBuilder
    private var hero: some View {
        switch category {
        case .duplicatePhotos where !app.similar.duplicateGroups.isEmpty:
            examples {
                ForEach(Array(app.similar.duplicateGroups.prefix(2))) { group in
                    pairRow(label: "\(group.items.count) Duplicates", group: group, keepLabel: "Keep")
                }
            }
        case .similarPhotos where !app.similar.groups.isEmpty:
            examples {
                ForEach(Array(app.similar.groups.prefix(2))) { group in
                    pairRow(label: "\(group.items.count) Similar", group: group, keepLabel: "Best shot")
                }
            }
        case .screenshots where !app.screenshots.items.isEmpty:
            examples { grid(app.screenshots.items.prefix(6).map(\.id)) }
        case .chatPhotos where !app.similar.chatPhotos.isEmpty:
            examples { grid(app.similar.chatPhotos.prefix(6).map(\.id)) }
        case .blurryPhotos where !app.similar.blurry.isEmpty:
            examples { grid(app.similar.blurry.prefix(6).map(\.id)) }
        case .largeVideos where !app.videos.largeVideos.isEmpty:
            examples {
                HStack(spacing: 10) {
                    ForEach(Array(app.videos.largeVideos.prefix(2))) { video in
                        thumb(video.id, height: 170)
                            .overlay(alignment: .topLeading) {
                                Text(Format.bytes(video.fileSize))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.5), in: Capsule())
                                    .padding(8)
                            }
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(.black.opacity(0.4), in: Circle())
                            }
                    }
                }
            }
        case .duplicateContacts where !(app.contacts.groups.first?.contacts ?? []).isEmpty:
            examples {
                ContactCardPreview(contacts: Array(app.contacts.groups.first?.contacts.prefix(2) ?? []),
                                   tint: category.tint)
                    .frame(height: 190)
            }
        case .calendarEvents where !app.calendar.oldEvents.isEmpty:
            examples {
                VStack(spacing: 8) {
                    ForEach(Array(app.calendar.oldEvents.prefix(3))) { event in
                        HStack(spacing: 12) {
                            CleanSpaceIcon(symbol: "calendar", tint: category.tint, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .lineLimit(1)
                                Text(event.whenText)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .glassSurface(cornerRadius: 18)
                    }
                }
            }
        default:
            VStack(spacing: 14) {
                CleanSpaceIcon(symbol: category.symbol, tint: category.tint, size: 96)
                Text(category.tagline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    private func examples<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("From your library", systemImage: "photo.on.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pairRow(label: String, group: PhotoGroup, keepLabel: String) -> some View {
        let ids = Array(group.items.prefix(2).map(\.id))
        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
            HStack(spacing: 10) {
                ForEach(ids, id: \.self) { id in
                    let isKeep = id == group.bestID
                    thumb(id, height: 150)
                        .overlay(alignment: .bottomLeading) {
                            if isKeep {
                                Label(keepLabel, systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(light: 0x111827, dark: 0x111827))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.94), in: Capsule())
                                    .padding(8)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            checkmark(selected: !isKeep).padding(8)
                        }
                }
            }
        }
    }

    private func grid(_ ids: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(ids, id: \.self) { id in thumb(id, height: 104) }
        }
    }

    private func thumb(_ id: String, height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay { AssetThumbnail(id: id, side: 320) }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private func checkmark(selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.Palette.brand : Color.black.opacity(0.25))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white, lineWidth: 2)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A looping demonstration of the real gestures: a finger drags a photo left, it tilts, turns
/// red and flies off (marked for deletion); the next photo pops in and is dragged right, where it
/// turns blue and flies off (kept). Left marks for deletion and right keeps, exactly as in swipe mode.
struct SwipeDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Demo {
        var x: CGFloat = 0
        var rotation: Double = 0
        var cardOpacity: Double = 1
        var scale: CGFloat = 1
        var delete: Double = 0
        var keep: Double = 0
        var hand: Double = 0
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                if reduceMotion {
                    scene(Demo())
                } else {
                    Color.clear
                        .keyframeAnimator(initialValue: Demo(), repeating: true) { _, value in
                            scene(value)
                        } keyframes: { _ in
                            KeyframeTrack(\.x) {
                                LinearKeyframe(0, duration: 0.5)
                                CubicKeyframe(-80, duration: 0.6)
                                CubicKeyframe(-240, duration: 0.3)
                                MoveKeyframe(0)
                                LinearKeyframe(0, duration: 0.6)
                                CubicKeyframe(80, duration: 0.6)
                                CubicKeyframe(240, duration: 0.3)
                                MoveKeyframe(0)
                                LinearKeyframe(0, duration: 1.1)
                            }
                            KeyframeTrack(\.rotation) {
                                LinearKeyframe(0, duration: 0.5)
                                CubicKeyframe(-10, duration: 0.6)
                                CubicKeyframe(-18, duration: 0.3)
                                MoveKeyframe(0)
                                LinearKeyframe(0, duration: 0.6)
                                CubicKeyframe(10, duration: 0.6)
                                CubicKeyframe(18, duration: 0.3)
                                MoveKeyframe(0)
                                LinearKeyframe(0, duration: 1.1)
                            }
                            KeyframeTrack(\.cardOpacity) {
                                LinearKeyframe(1, duration: 1.1)
                                LinearKeyframe(0, duration: 0.3)
                                MoveKeyframe(0)
                                LinearKeyframe(1, duration: 0.3)
                                LinearKeyframe(1, duration: 0.9)
                                LinearKeyframe(0, duration: 0.3)
                                MoveKeyframe(0)
                                LinearKeyframe(1, duration: 0.3)
                                LinearKeyframe(1, duration: 0.8)
                            }
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(1, duration: 1.4)
                                MoveKeyframe(0.85)
                                SpringKeyframe(1, duration: 0.4)
                                LinearKeyframe(1, duration: 1.1)
                                MoveKeyframe(0.85)
                                SpringKeyframe(1, duration: 0.4)
                                LinearKeyframe(1, duration: 0.7)
                            }
                            KeyframeTrack(\.delete) {
                                LinearKeyframe(0, duration: 0.5)
                                LinearKeyframe(1, duration: 0.4)
                                LinearKeyframe(1, duration: 0.5)
                                LinearKeyframe(0, duration: 0.2)
                                LinearKeyframe(0, duration: 2.4)
                            }
                            KeyframeTrack(\.keep) {
                                LinearKeyframe(0, duration: 2.0)
                                LinearKeyframe(1, duration: 0.4)
                                LinearKeyframe(1, duration: 0.5)
                                LinearKeyframe(0, duration: 0.2)
                                LinearKeyframe(0, duration: 0.9)
                            }
                            KeyframeTrack(\.hand) {
                                LinearKeyframe(0, duration: 0.3)
                                LinearKeyframe(1, duration: 0.2)
                                LinearKeyframe(1, duration: 0.6)
                                LinearKeyframe(0, duration: 0.2)
                                LinearKeyframe(0, duration: 0.5)
                                LinearKeyframe(1, duration: 0.2)
                                LinearKeyframe(1, duration: 0.6)
                                LinearKeyframe(0, duration: 0.2)
                                LinearKeyframe(0, duration: 1.2)
                            }
                        }
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Swipe left to mark a photo for deletion, or right to keep it. Nothing is deleted until you confirm on the review screen.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.l)
        .glassSurface(cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Swipe left to mark for deletion. Swipe right to keep. Nothing is deleted until you confirm on the review screen.")
    }

    /// Builds the demo frame from fixed values only, so the animator can call it from any context.
    nonisolated private func scene(_ v: Demo) -> some View {
        ZStack {
            HStack {
                Label("Delete", systemImage: "arrow.left")
                    .foregroundStyle(Theme.Palette.coral)
                    .opacity(0.45 + 0.55 * v.delete)
                    .scaleEffect(1 + 0.08 * v.delete)
                Spacer()
                HStack(spacing: 4) {
                    Text("Keep")
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Theme.Palette.brand)
                .opacity(0.45 + 0.55 * v.keep)
                .scaleEffect(1 + 0.08 * v.keep)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.s)

            // The next photo waiting underneath.
            photoCard(tint: Theme.Palette.indigo)
                .scaleEffect(0.9)
                .offset(y: 8)
                .opacity(0.45)

            photoCard(tint: Theme.Palette.brand)
                .overlay(alignment: .topTrailing) {
                    stamp("Delete", color: Theme.Palette.coral).opacity(v.delete).padding(6)
                }
                .overlay(alignment: .topLeading) {
                    stamp("Keep", color: Theme.Palette.brand).opacity(v.keep).padding(6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(v.delete > 0 ? Theme.Palette.coral : Theme.Palette.brand,
                                      lineWidth: 2.5)
                        .opacity(max(v.delete, v.keep))
                }
                .scaleEffect(v.scale)
                .rotationEffect(.degrees(v.rotation))
                .offset(x: v.x)
                .opacity(v.cardOpacity)

            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.Palette.ink.opacity(0.85))
                .shadow(color: Theme.Palette.shadow, radius: 4, y: 2)
                .offset(x: min(max(v.x, -80), 80) + 22, y: 34)
                .opacity(v.hand)
        }
    }

    nonisolated private func photoCard(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 82, height: 104)
            .overlay(
                Image(systemName: "photo.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.9))
            )
            .shadow(color: Theme.Palette.shadow, radius: 8, y: 4)
    }

    nonisolated private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
