import SwiftUI

/// "Space freed" screen shown after any cleanup or compression.
///
/// Sequence: the removed items (shown as category tiles) gather into the center, a blue swoosh
/// sweeps around, a check appears with a light burst, then the freed space and item counts count
/// up. Every number comes from the actual deletion results. With Reduce Motion the final state
/// appears straight away.
struct CleanupSummaryView: View {
    let summary: CleanupSummary
    var doneTitle = "Done"
    /// Thumbnails captured before deletion. When present they fly into the swoosh instead of icons.
    var previewImages: [UIImage] = []
    let onDone: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0          // 0 items shown, 1 gathering + swoosh, 2 clean
    @State private var particlesFaded = false

    private struct Tile: Identifiable {
        let id: Int
        let symbol: String
        let tint: Color
        var image: UIImage?
    }

    private var tiles: [Tile] {
        var result: [Tile] = []
        var raw: [(String, Color, Int)] = []
        let photoTiles = min(previewImages.count, summary.mediaRemoved, 8)
        for image in previewImages.prefix(photoTiles) {
            result.append(Tile(id: result.count, symbol: "photo", tint: Theme.Palette.brand, image: image))
        }
        if photoTiles == 0 {
            for category in CleanupCategory.mediaCategories {
                let count = summary.removedByCategory[category] ?? 0
                if count > 0 { raw.append((category.symbol, category.tint, min(count, 4))) }
            }
        }
        if summary.videosCompressed > 0 { raw.append(("film.stack", Theme.Palette.compress, 3)) }
        if summary.contactsRemoved + summary.contactGroupsMerged > 0 {
            raw.append(("person.crop.circle", Theme.Palette.contacts, min(summary.contactsRemoved + summary.contactGroupsMerged, 3)))
        }
        if summary.eventsRemoved > 0 { raw.append(("calendar", Theme.Palette.calendar, min(summary.eventsRemoved, 3))) }
        for (symbol, tint, count) in raw {
            for _ in 0..<count where result.count < 10 {
                result.append(Tile(id: result.count, symbol: symbol, tint: tint))
            }
        }
        return result
    }

    private var sortedBreakdown: [(category: CleanupCategory, bytes: Int64)] {
        summary.bytesByCategory
            .filter { $0.value > 0 }
            .map { (category: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                burst
                    .frame(height: 230)
                    .padding(.top, Theme.Spacing.l)
                headline
                if stage >= 2 {
                    Group {
                        beforeAfter
                        stats
                        if sortedBreakdown.count > 1 { breakdown }
                        if summary.hadFailures { failures }
                        if summary.mediaRemoved > 0 || summary.videosCompressed > 0 { recentlyDeleted }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Button(action: onDone) {
                    PrimaryButtonLabel(title: doneTitle)
                }
                .buttonStyle(PressableButtonStyle())
                .opacity(stage >= 2 ? 1 : 0)
            }
            .padding(Theme.Spacing.l)
        }
        .background(background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: stage == 2)
        .task { await play() }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            Color.clear
            RadialGradient(colors: [Theme.Palette.brand.opacity(0.22), .clear],
                           center: .top, startRadius: 10, endRadius: 420)
                .frame(height: 520)
        }
    }

    // MARK: Animation

    private func play() async {
        guard stage == 0 else { return }
        if reduceMotion || tiles.isEmpty {
            stage = 2
            particlesFaded = true
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut(duration: 0.7)) { stage = 1 }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.spring(duration: 0.55, bounce: 0.35)) { stage = 2 }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeOut(duration: 0.7)) { particlesFaded = true }
    }

    private var burst: some View {
        ZStack {
            // Glow
            Circle()
                .fill(Theme.Palette.brand.opacity(0.35))
                .frame(width: 150, height: 150)
                .blur(radius: 30)
                .scaleEffect(stage >= 2 ? 1 : 0.4)
                .opacity(stage >= 2 ? 1 : 0)

            // Items gathering into the center
            ForEach(tiles) { tile in
                let angle = Double(tile.id) / Double(max(tiles.count, 1)) * .pi * 2 - .pi / 2
                Group {
                    if let image = tile.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2))
                    } else {
                        Image(systemName: tile.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(tile.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .shadow(color: tile.tint.opacity(0.35), radius: 6, y: 3)
                    .offset(x: stage >= 1 ? 0 : cos(angle) * 105, y: stage >= 1 ? 0 : sin(angle) * 105)
                    .scaleEffect(stage >= 1 ? 0.2 : 1)
                    .rotationEffect(.degrees(stage >= 1 ? 160 : 0))
                    .opacity(stage >= 1 ? 0 : 1)
                    .animation(.easeIn(duration: 0.55).delay(Double(tile.id) * 0.035), value: stage)
            }

            // Swoosh
            Circle()
                .trim(from: 0, to: stage >= 1 ? 0.72 : 0.02)
                .stroke(AngularGradient(colors: [Theme.Palette.cyan.opacity(0), Theme.Palette.cyan, Theme.Palette.brand],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(stage >= 1 ? 250 : -110))
                .opacity(stage == 1 ? 1 : 0)
            Circle()
                .trim(from: 0, to: stage >= 1 ? 0.5 : 0.02)
                .stroke(Theme.Palette.brand.opacity(0.5), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 136, height: 136)
                .rotationEffect(.degrees(stage >= 1 ? -200 : 60))
                .opacity(stage == 1 ? 1 : 0)

            // Light burst
            ForEach(0..<12, id: \.self) { index in
                let angle = Double(index) / 12 * .pi * 2
                Group {
                    if index.isMultiple(of: 3) {
                        SparkleShape().fill(Theme.Palette.cyan).frame(width: 12, height: 12)
                    } else {
                        Circle().fill(index.isMultiple(of: 2) ? Theme.Palette.brand : Theme.Palette.cyan)
                            .frame(width: 6, height: 6)
                    }
                }
                .offset(x: cos(angle) * (stage >= 2 ? 112 : 40), y: sin(angle) * (stage >= 2 ? 112 : 40))
                .opacity(stage >= 2 && !particlesFaded ? 1 : 0)
            }

            // Result mark
            ZStack {
                Circle()
                    .fill(summary.didAnything ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.Palette.secondaryText))
                    .frame(width: 104, height: 104)
                    .shadow(color: Theme.Palette.brand.opacity(0.4), radius: 16, y: 8)
                Image(systemName: summary.didAnything ? "checkmark" : "minus")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: stage >= 2)
            }
            .scaleEffect(stage >= 2 ? 1 : 0.3)
            .opacity(stage >= 2 ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    // MARK: Text

    private var headline: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(titleText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
            if summary.bytesFreed > 0 {
                Group {
                    if stage >= 2 {
                        CountingBytesText(target: summary.bytesFreed, animate: !reduceMotion, duration: 1.3)
                    } else {
                        Text(Format.bytes(0)).hidden()
                    }
                }
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.brandGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                Text(summary.videosCompressed > 0 && summary.mediaRemoved == 0 ? "saved by compressing" : "freed")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            if app.lifetimeFreedBytes > summary.bytesFreed && stage >= 2 {
                Label("\(Format.bytes(app.lifetimeFreedBytes)) freed with CleanSpace so far", systemImage: "leaf.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Palette.success)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, 6)
                    .background(Theme.Palette.success.opacity(0.12), in: Capsule())
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var titleText: String {
        if !summary.didAnything { return "Nothing was changed" }
        return summary.hadFailures ? "Mostly clean" : "All Clean!"
    }

    // MARK: Before and after

    @ViewBuilder
    private var beforeAfter: some View {
        if let before = summary.storageBefore, before.total > 0, summary.bytesFreed > 0 {
            let beforeFraction = before.usedFraction
            let afterFraction = max(Double(before.used - summary.bytesFreed) / Double(before.total), 0)
            HStack(spacing: Theme.Spacing.l) {
                LiquidGauge(fraction: particlesFaded ? afterFraction : beforeFraction, ringWidth: 3, animateOnAppear: false)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Storage used")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Text("\(percent(beforeFraction)) → \(percent(afterFraction))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    if summary.mediaRemoved > 0 {
                        Text("Once Recently Deleted is emptied")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
                Spacer()
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

    private func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    // MARK: Counts

    private struct StatRow: Identifiable {
        let id: String
        let symbol: String
        let tint: Color
        let label: String
        let value: Int
    }

    private var statRows: [StatRow] {
        let removed = summary.removedByCategory
        let photos = (removed[.duplicatePhotos] ?? 0) + (removed[.similarPhotos] ?? 0) + (removed[.blurryPhotos] ?? 0) + (removed[.chatPhotos] ?? 0)
        let candidates: [StatRow] = [
            StatRow(id: "photos", symbol: "photo.on.rectangle.angled", tint: Theme.Palette.similar, label: "Photos removed", value: photos),
            StatRow(id: "shots", symbol: "camera.viewfinder", tint: Theme.Palette.screenshots, label: "Screenshots removed", value: removed[.screenshots] ?? 0),
            StatRow(id: "videos", symbol: "video.fill", tint: Theme.Palette.videos, label: "Videos removed", value: removed[.largeVideos] ?? 0),
            StatRow(id: "compressed", symbol: "arrow.down.right.and.arrow.up.left", tint: Theme.Palette.compress, label: "Videos compressed", value: summary.videosCompressed),
            StatRow(id: "merged", symbol: "arrow.triangle.merge", tint: Theme.Palette.contacts, label: "Contact groups merged", value: summary.contactGroupsMerged),
            StatRow(id: "contacts", symbol: "person.2.fill", tint: Theme.Palette.contacts, label: "Contact cards removed", value: summary.contactsRemoved),
            StatRow(id: "events", symbol: "calendar", tint: Theme.Palette.calendar, label: "Calendar events removed", value: summary.eventsRemoved)
        ]
        return candidates.filter { $0.value > 0 }
    }

    @ViewBuilder
    private var stats: some View {
        let rows = statRows
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(row.tint)
                            .frame(width: 32, height: 32)
                            .background(row.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        CountingNumberText(target: row.value, animate: !reduceMotion)
                            .font(Theme.Typography.rowNumber)
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 { Divider().padding(.leading, 60) }
                }
            }
            .card(padding: 0)
        }
    }

    private var breakdown: some View {
        let total = max(sortedBreakdown.reduce(Int64(0)) { $0 + $1.bytes }, 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Where the space came from")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(sortedBreakdown, id: \.category) { entry in
                        Rectangle()
                            .fill(entry.category.tint)
                            .frame(width: max(4, (proxy.size.width - CGFloat(sortedBreakdown.count - 1) * 2)
                                              * CGFloat(Double(entry.bytes) / Double(total))))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            ForEach(sortedBreakdown, id: \.category) { entry in
                HStack(spacing: Theme.Spacing.m) {
                    Circle().fill(entry.category.tint).frame(width: 10, height: 10)
                    Text(entry.category.title).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text(Format.bytes(entry.bytes))
                        .font(Theme.Typography.rowNumber)
                        .foregroundStyle(Theme.Palette.ink)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    // MARK: Notes

    private var failures: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Some items weren't changed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.Palette.amber)
            if summary.failedMedia > 0 {
                Text("\(Format.count(summary.failedMedia, "photo or video", "photos or videos")) couldn't be deleted. \(summary.mediaMessage ?? "") They stay selected, so you can try again.")
            }
            if summary.failedContacts > 0 {
                Text("\(Format.count(summary.failedContacts, "contact")) couldn't be changed. Contacts from work or school accounts are sometimes read-only.")
            }
            if summary.failedEvents > 0 {
                Text("\(Format.count(summary.failedEvents, "event")) couldn't be deleted. Events you were invited to may belong to someone else's calendar.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var recentlyDeleted: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Deleted photos and videos wait in Recently Deleted for 30 days", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("iOS releases the space after that. To get it back now, open Photos, go to Albums, then Recently Deleted, and delete them there.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
            Button {
                if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
            } label: {
                Label("Open Photos", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.brand)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Counts up to `target` bytes once when it appears, easing out.
struct CountingBytesText: View {
    let target: Int64
    var animate = true
    var duration: TimeInterval = 1.1

    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: finished || !animate)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = (!animate || finished) ? 1 : min(max(elapsed / duration, 0), 1)
            let eased = 1 - pow(1 - t, 3)
            Text(Format.bytes(Int64(Double(target) * eased)))
                .monospacedDigit()
        }
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(for: .seconds(duration + 0.1))
            finished = true
        }
        .accessibilityLabel(Format.bytes(target))
    }
}

/// Counts up to a whole number once when it appears.
struct CountingNumberText: View {
    let target: Int
    var animate = true
    var duration: TimeInterval = 0.9

    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: finished || !animate)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = (!animate || finished) ? 1 : min(max(elapsed / duration, 0), 1)
            let eased = 1 - pow(1 - t, 3)
            Text(Int((Double(target) * eased).rounded()).formatted())
                .monospacedDigit()
        }
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(for: .seconds(duration + 0.1))
            finished = true
        }
        .accessibilityLabel(target.formatted())
    }
}
