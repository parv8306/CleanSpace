import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @State private var revealed = false
    @State private var infoCategory: CleanupCategory?

    private let primaryCategories: [CleanupCategory] = [.duplicatePhotos, .similarPhotos, .screenshots,
                                                        .chatPhotos, .largeVideos, .duplicateContacts]
    private let moreCategories: [CleanupCategory] = [.blurryPhotos, .calendarEvents]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                    .entrance(revealed, index: 0)
                StorageHeroCard()
                    .entrance(revealed, index: 1)
                ScanCTAButton()
                    .entrance(revealed, index: 2)
                if app.isScanning {
                    ScanStagesCard()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                cleanupSection
                toolsSection
                    .entrance(revealed, index: 12)
                if app.lifetimeFreedBytes > 0 || !app.history.isEmpty {
                    lifetimeRow
                        .entrance(revealed, index: 13)
                }
                lastScannedRow
                Label("Everything is analyzed on this iPhone. Nothing is uploaded.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .entrance(revealed, index: 14)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
            .animation(.snappy, value: app.isScanning)
        }
        .scrollIndicators(.hidden)
        .background(AppBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            app.refreshStorage()
            app.permissions.refresh()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.selection.isEmpty {
                SelectionBar(count: app.totalSelectedCount, noun: "item",
                             bytes: app.totalSelectedBytes, buttonTitle: "Review Changes",
                             onClear: { withAnimation(.snappy) { app.clearAllSelection() } }) {
                    app.openReview()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: app.selection.isEmpty)
        .onAppear { revealed = true }
        .glassCover(item: $infoCategory) { category in
            CategoryInfoSheet(category: category) {
                app.path.append(.category(category))
            }
            .environment(app)
        }
    }

    private func open(_ category: CleanupCategory) {
        if CategoryInfoPreferences.shouldShow(category) {
            infoCategory = category
        } else {
            app.path.append(.category(category))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            AppLogoMark(size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("CleanSpace")
                    .font(Theme.Typography.wordmark)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Make room for what matters.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer()
            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(width: 44, height: 44)
                    .csGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Clean up

    private var cleanupSection: some View {
        let all = primaryCategories + moreCategories
        let statuses = Dictionary(uniqueKeysWithValues: all.map { ($0, app.status(for: $0)) })
        let maxBytes = statuses.values.compactMap { status -> Int64? in
            if case let .ready(_, bytes) = status { return bytes }
            return nil
        }.max() ?? 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Cleanup") {
                if app.hasAnyResults && app.potentialBytes > 0 {
                    Text("Up to \(Format.bytes(app.potentialBytes))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.brand)
                        .contentTransition(.numericText())
                }
            }
            photoCard(.duplicatePhotos, statuses: statuses, wide: true, index: 0)
            photoCard(.similarPhotos, statuses: statuses, wide: true, index: 1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m),
                                GridItem(.flexible(), spacing: Theme.Spacing.m)],
                      spacing: Theme.Spacing.m) {
                photoCard(.screenshots, statuses: statuses, wide: false, index: 2)
                photoCard(.largeVideos, statuses: statuses, wide: false, index: 3)
                photoCard(.chatPhotos, statuses: statuses, wide: false, index: 4)
                photoCard(.duplicateContacts, statuses: statuses, wide: false, index: 5)
            }
            Text("More")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.top, Theme.Spacing.s)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(moreCategories.enumerated()), id: \.offset) { index, category in
                cardButton(category, status: statuses[category] ?? .notScanned, maxBytes: maxBytes,
                           index: primaryCategories.count + index)
            }
        }
    }

    private func photoCard(_ category: CleanupCategory, statuses: [CleanupCategory: CategoryStatus],
                           wide: Bool, index: Int) -> some View {
        let preview = previewContent(for: category)
        return Button {
            open(category)
        } label: {
            PhotoCategoryCard(category: category,
                              status: statuses[category] ?? .notScanned,
                              previewIDs: preview.ids,
                              contacts: preview.contacts,
                              videoDuration: preview.duration,
                              countText: countText(for: category),
                              selectedCount: app.selectedCount(in: category),
                              wide: wide)
        }
        .buttonStyle(PressableButtonStyle())
        .entrance(revealed, index: 3 + index)
        .accessibilityHint("Explains this category, then opens it")
    }

    /// The person's own first items in each category, for the card previews.
    private func previewContent(for category: CleanupCategory) -> (ids: [String], contacts: [ContactRecord], duration: Double) {
        switch category {
        case .duplicatePhotos:
            guard let group = app.similar.duplicateGroups.first else { return ([], [], 0) }
            let extra = group.reclaimableItems.first?.id
            return ([group.bestID] + (extra.map { [$0] } ?? []), [], 0)
        case .similarPhotos:
            guard let group = app.similar.groups.first else { return ([], [], 0) }
            return (Array(group.items.prefix(2).map(\.id)), [], 0)
        case .screenshots:
            return (app.screenshots.items.first.map { [$0.id] } ?? [], [], 0)
        case .largeVideos:
            guard let video = app.videos.largeVideos.first else { return ([], [], 0) }
            return ([video.id], [], video.duration)
        case .chatPhotos:
            return (app.similar.chatPhotos.first.map { [$0.id] } ?? [], [], 0)
        case .duplicateContacts:
            return ([], Array(app.contacts.groups.first?.contacts.prefix(4) ?? []), 0)
        default:
            return ([], [], 0)
        }
    }

    private func countText(for category: CleanupCategory) -> String {
        switch category {
        case .duplicatePhotos: return Format.count(app.similar.duplicateReclaimableCount, "Photo", "Photos")
        case .similarPhotos: return Format.count(app.similar.reclaimableCount, "Photo", "Photos")
        case .screenshots: return Format.count(app.screenshots.items.count, "Photo", "Photos")
        case .largeVideos: return Format.count(app.videos.largeVideos.count, "Video", "Videos")
        case .chatPhotos: return Format.count(app.similar.chatPhotos.count, "Photo", "Photos")
        case .duplicateContacts: return Format.count(app.contacts.duplicateCount, "Duplicate", "Duplicates")
        default: return ""
        }
    }

    private func cardButton(_ category: CleanupCategory, status: CategoryStatus, maxBytes: Int64, index: Int) -> some View {
        Button {
            open(category)
        } label: {
            CategoryCard(category: category, status: status,
                         selectedCount: app.selectedCount(in: category), maxBytes: maxBytes)
        }
        .buttonStyle(PressableButtonStyle())
        .entrance(revealed, index: 3 + index)
        .accessibilityHint("Explains this category, then opens it")
    }

    // MARK: Tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Tools")
            HStack(spacing: Theme.Spacing.m) {
                ToolTile(title: "Swipe mode", subtitle: "Keep or delete, one by one",
                         symbol: "hand.draw.fill", tint: Theme.Palette.swipe, route: .swipeHub)
                ToolTile(title: "Compress", subtitle: "Shrink big videos",
                         symbol: "arrow.down.right.and.arrow.up.left", tint: Theme.Palette.compress,
                         route: .compressVideos)
                ToolTile(title: "Vault", subtitle: app.vaultLock.state == .needsSetup ? "Hide private photos" : "Locked with your PIN",
                         symbol: "lock.square.stack.fill", tint: Theme.Palette.vault, route: .vault)
            }
        }
    }

    @ViewBuilder
    private var lastScannedRow: some View {
        if let date = app.lastScanDate {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "clock")
                Text("Last scanned: ") + Text(lastScanText(date)).fontWeight(.semibold)
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.xs)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Today at 9:42 AM", "Yesterday at 6:10 PM", or a date.
    private func lastScanText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    private var lifetimeRow: some View {
        NavigationLink(value: Route.history) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Theme.Palette.success)
                    .frame(width: 36, height: 36)
                    .background(Theme.Palette.success.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Freed with CleanSpace")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("See your cleanup history")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                Text(Format.bytes(app.lifetimeFreedBytes))
                    .font(Theme.Typography.rowNumber)
                    .foregroundStyle(Theme.Palette.ink)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
            }
            .card(padding: Theme.Spacing.m)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Storage hero

/// The focal point: the storage ring, how much can be freed, and used, free and total space.
struct StorageHeroCard: View {
    @Environment(AppState.self) private var app
    @State private var refill = 0
    @State private var cleaning = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            if let storage = app.storage {
                let freeable = app.potentialBytes
                let freeableFraction = storage.total > 0 ? Double(freeable) / Double(storage.total) : 0
                let percent = Int((storage.usedFraction * 100).rounded())

                Button { quickClean() } label: {
                    StorageRingGauge(used: storage.usedFraction, freeable: freeableFraction,
                                     isScanning: app.isScanning, percentText: "\(percent)%", caption: "full",
                                     refillToken: refill, fillDuration: 2.0)
                        .frame(width: 236, height: 236)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(cleaning || app.isScanning)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xs)
                .sensoryFeedback(.impact(weight: .medium), trigger: refill)
                .accessibilityLabel("Quick clean. Storage \(percent) percent full.")
                .accessibilityHint(app.hasAnyResults ? "Selects the safe suggestions and opens the review screen" : "Scans your library")

                if !app.isScanning {
                    Label(cleaning ? "Preparing your quick clean" : "Tap the water for a quick clean",
                          systemImage: cleaning ? "sparkles" : "hand.tap")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .contentTransition(.opacity)
                }

                BatteryCard(compact: true)

                HStack(spacing: 0) {
                    storageFigure("Used", Format.bytes(storage.used), color: Theme.Palette.water)
                    Rectangle().fill(Theme.Palette.separator).frame(width: 1, height: 36)
                    storageFigure("Free", Format.bytes(storage.available), color: Theme.Palette.track)
                }
                .padding(.vertical, Theme.Spacing.s)
                .background(Theme.Palette.surfaceSunken.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

                Text("\(Format.bytes(storage.used)) of \(Format.bytes(storage.total)) used")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)

                freeableHeadline(freeable)
            } else {
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.Palette.brand)
                    Text("Storage details unavailable")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(app.storageErrorMessage ?? "Reading storage figures")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Button("Try again") { app.refreshStorage() }
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Empties the water and fills it back up over two seconds, then runs Quick Clean.
    private func quickClean() {
        guard !cleaning, !app.isScanning else { return }
        cleaning = true
        refill += 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            cleaning = false
            app.quickClean()
        }
    }

    private func storageFigure(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func freeableHeadline(_ bytes: Int64) -> some View {
        if app.hasAnyResults {
            VStack(spacing: 2) {
                Text(bytes > 0 ? Format.bytes(bytes) : "Nothing big")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.brandGradient)
                    .contentTransition(.numericText())
                Text(bytes > 0 ? "can be freed" : "to clear right now")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        } else {
            Text(app.isScanning ? "Looking for space you can free" : "Scan to see how much space you can free")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var accessibilitySummary: String {
        guard let storage = app.storage else { return "Storage details unavailable" }
        var text = "Storage. \(Int((storage.usedFraction * 100).rounded())) percent used. \(Format.bytes(storage.used)) used, \(Format.bytes(storage.available)) free, \(Format.bytes(storage.total)) total."
        if app.hasAnyResults { text += " \(Format.bytes(app.potentialBytes)) can be freed." }
        return text
    }
}

// MARK: - Scan button

/// The primary action. Its wording follows the real scan status: "Scanning" with live progress
/// while items are read, "Analyzing" while results are compared, and "Scan Again" only once
/// every part of the scan has finished.
struct ScanCTAButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let status = app.scanStatus
        let scanning = app.isScanning
        Button {
            guard !app.isScanning else { return }
            app.scanNowTapped()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                RadarIcon(isScanning: scanning, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(status))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(subtitle(status))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                trailing(status)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 11)
            .frame(minHeight: 56)
            .modifier(ScanButtonSurface())
            .overlay(alignment: .bottom) {
                if case let .scanning(done, total, _) = status, total > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(.white)
                                .frame(width: max(6, proxy.size.width * CGFloat(Double(done) / Double(total))))
                                .animation(.easeOut(duration: 0.3), value: done)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .allowsHitTesting(!scanning)
        .animation(.snappy, value: status)
        .sensoryFeedback(.impact(weight: .medium), trigger: scanning) { _, new in new }
        .accessibilityLabel(title(status))
        .accessibilityValue(subtitle(status))
        .accessibilityHint(scanning ? "" : "Scans your library for space you can free")
    }

    @ViewBuilder
    private func trailing(_ status: AppState.ScanStatus) -> some View {
        switch status {
        case let .scanning(done, total, _):
            if total > 0 {
                Text("\(Int((Double(done) / Double(total) * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        case .analyzing:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        default:
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func title(_ status: AppState.ScanStatus) -> String {
        switch status {
        case .scanning: "Scanning…"
        case .analyzing: "Analyzing…"
        case .failed: "Try Again"
        case .complete: "Scan Again"
        case .idle: app.lastScanDate != nil ? "Scan Again" : "Scan My iPhone"
        }
    }

    private func subtitle(_ status: AppState.ScanStatus) -> String {
        switch status {
        case let .scanning(done, total, label):
            return total > 0 ? "\(done.formatted()) of \(total.formatted()) \(label)" : "Getting ready"
        case let .analyzing(step):
            return step
        case let .failed(message):
            return message
        case .complete:
            return "Check your storage"
        case .idle:
            return app.lastScanDate == nil ? "Find space you can free" : "Check your storage"
        }
    }
}

/// Live list of the scan stages that are actually running, with their real progress.
struct ScanStagesCard: View {
    @Environment(AppState.self) private var app

    private struct Stage: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let phase: ScanPhase
        let hasResults: Bool
    }

    private var stages: [Stage] {
        var list: [Stage] = []
        if app.permissions.photos.canRead {
            list.append(Stage(id: "photos", title: "Analyzing your photo library", symbol: "photo.on.rectangle.angled",
                              phase: app.similar.phase, hasResults: app.similar.hasResults))
            list.append(Stage(id: "shots", title: "Checking screenshots", symbol: "camera.viewfinder",
                              phase: app.screenshots.phase, hasResults: app.screenshots.hasResults))
            list.append(Stage(id: "videos", title: "Finding large videos", symbol: "video.fill",
                              phase: app.videos.phase, hasResults: app.videos.hasResults))
        }
        if app.permissions.contacts.canRead {
            list.append(Stage(id: "contacts", title: "Checking contacts", symbol: "person.2.fill",
                              phase: app.contacts.phase, hasResults: app.contacts.hasResults))
        }
        if app.permissions.calendar.canRead {
            list.append(Stage(id: "calendar", title: "Checking your calendar", symbol: "calendar",
                              phase: app.calendar.phase, hasResults: app.calendar.hasResults))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Scanning your library…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button("Stop") { app.cancelScans() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.coral)
                    .accessibilityHint("Stops scanning")
            }
            ForEach(stages) { stage in
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: stage.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.brand)
                        .frame(width: 30, height: 30)
                        .background(Theme.Palette.brandSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(stage.phase.isAnalyzing ? "Comparing results" : stage.title)
                                .font(.subheadline)
                                .foregroundStyle(stage.phase.isScanning ? Theme.Palette.ink : Theme.Palette.secondaryText)
                            Spacer()
                            status(stage)
                        }
                        StageBar(fraction: stage.phase.fraction, isRunning: stage.phase.isScanning,
                                 isDone: !stage.phase.isScanning && stage.hasResults)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    @ViewBuilder
    private func status(_ stage: Stage) -> some View {
        if stage.phase.isScanning {
            if let fraction = stage.phase.fraction {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.Palette.brand)
                    .contentTransition(.numericText())
            } else {
                ProgressView().controlSize(.small)
            }
        } else if stage.phase.failureMessage != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.amber)
                .accessibilityLabel("Didn't finish")
        } else if stage.hasResults {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Palette.success)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Done")
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                .accessibilityLabel("Waiting")
        }
    }
}

// MARK: - Category card

struct CategoryCard: View {
    let category: CleanupCategory
    let status: CategoryStatus
    var selectedCount = 0
    var maxBytes: Int64 = 0

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            CleanSpaceIcon(symbol: category.symbol, tint: category.tint, colors: category.gradient)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(category.title)
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.ink)
                        Text(category.tagline)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    Spacer()
                    if selectedCount > 0 {
                        SelectionBadge(count: selectedCount)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                }
                detail
            }
        }
        .padding(Theme.Spacing.l)
        .glassSurface(cornerRadius: 26)
        .animation(.snappy, value: selectedCount)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        switch status {
        case let .ready(text, bytes):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
            if let bytes {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.bytes(bytes))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.numericText())
                    Text("can be freed")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                ShareBar(fraction: maxBytes > 0 ? Double(bytes) / Double(maxBytes) : 0, tint: category.tint)
            }
        case let .clean(text):
            Label(text, systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.success)
        case let .scanning(fraction):
            Text(fraction == nil ? "Analyzing" : "Scanning")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
            ShareBar(fraction: fraction ?? 0.08, tint: Theme.Palette.brand)
        case .needsAccess:
            Label(category.permission == .photos ? "Tap to allow access" : "Tap to check", systemImage: "hand.tap.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.brand)
        case .accessDenied:
            Label("Access is off", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
        case .notScanned:
            Text("Not scanned yet")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
        case .failed:
            Label("Couldn't finish, tap to retry", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.amber)
        }
    }
}

/// Thin progress bar that grows into place.
private struct ShareBar: View {
    let fraction: Double
    let tint: Color
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.track)
                Capsule().fill(tint)
                    .frame(width: max(6, proxy.size.width * CGFloat(shown ? min(max(fraction, 0), 1) : 0)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.8), value: shown)
        .animation(.easeOut(duration: 0.5), value: fraction)
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Tools and footer

struct ToolTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                CleanSpaceIcon(symbol: symbol, tint: tint, size: 40, colors: [tint.opacity(0.7), tint])
                Spacer(minLength: Theme.Spacing.s)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(Theme.Spacing.m)
            .glassSurface(cornerRadius: 24)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Progress for one scan stage: real fraction when known, a gentle moving highlight while a
/// stage runs without countable progress (such as analyzing), full and green when done.
private struct StageBar: View {
    let fraction: Double?
    let isRunning: Bool
    let isDone: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.track)
                if isDone {
                    Capsule().fill(Theme.Palette.success)
                } else if let fraction, isRunning {
                    Capsule()
                        .fill(Theme.buttonGradient)
                        .frame(width: max(6, width * CGFloat(min(max(fraction, 0), 1))))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                } else if isRunning && !reduceMotion {
                    Capsule()
                        .fill(Theme.buttonGradient)
                        .frame(width: width * 0.3)
                        .phaseAnimator([false, true]) { content, phase in
                            content.offset(x: phase ? width * 0.7 : 0)
                        } animation: { _ in .easeInOut(duration: 0.9) }
                }
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .animation(.snappy, value: isDone)
        .accessibilityHidden(true)
    }
}

/// Tinted Liquid Glass for the scan button on iOS 26 and later; the teal-to-indigo fill before.
private struct ScanButtonSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Theme.Palette.scan).interactive(), in: shape)
        } else {
            content
                .background(LinearGradient(colors: [Theme.Palette.water, Theme.Palette.waterDeep],
                                           startPoint: .leading, endPoint: .trailing), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: Theme.Palette.scan.opacity(0.22), radius: 10, x: 0, y: 5)
        }
    }
}

/// A category shown with the person's own first photos (or contact avatars), and a pill with the
/// count and size. Before a scan, or when a category is clear, it shows the category's icon and
/// what to do next instead.
struct PhotoCategoryCard: View {
    let category: CleanupCategory
    let status: CategoryStatus
    let previewIDs: [String]
    var contacts: [ContactRecord] = []
    var videoDuration: Double = 0
    let countText: String
    var selectedCount = 0
    let wide: Bool

    private var previewHeight: CGFloat { wide ? 156 : 176 }

    private var hasContent: Bool {
        guard case .ready = status else { return false }
        return !previewIDs.isEmpty || !contacts.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.title)
                    .font(.system(wide ? .title3 : .headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if selectedCount > 0 {
                    SelectionBadge(count: selectedCount)
                        .transition(.scale.combined(with: .opacity))
                } else if wide {
                    Text(category.tagline)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            preview
                .frame(height: previewHeight)
                .overlay(alignment: .bottomTrailing) { pill.padding(8) }
        }
        .padding(14)
        .glassSurface(cornerRadius: 26)
        .animation(.snappy, value: selectedCount)
        .accessibilityElement(children: .combine)
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if hasContent && !contacts.isEmpty {
            ContactCardPreview(contacts: contacts, tint: category.tint)
        } else if hasContent {
            HStack(spacing: 8) {
                ForEach(Array(previewIDs.prefix(wide ? 2 : 1).enumerated()), id: \.element) { position, id in
                    photo(id, first: position == 0)
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(category.tint.opacity(0.10))
                CleanSpaceIcon(symbol: category.symbol, tint: category.tint, size: 54)
                    .offset(y: -12)
            }
        }
    }

    private func photo(_ id: String, first: Bool) -> some View {
        Color.clear
            .overlay { AssetThumbnail(id: id, side: wide ? 340 : 380) }
            .overlay(alignment: .bottom) {
                // Soft shade so the button always reads clearly over bright photos.
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.38)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                if first { badge.padding(8) }
            }
            .overlay {
                if category == .largeVideos {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.black.opacity(0.4), in: Circle())
                        .offset(y: -14)
                }
            }
    }

    @ViewBuilder
    private var badge: some View {
        switch category {
        case .largeVideos:
            if videoDuration > 0 {
                Text(Format.duration(videoDuration))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule())
            }
        case .chatPhotos:
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(7)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .duplicatePhotos, .similarPhotos:
            Label("Keep", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.Palette.success, in: Capsule())
        default:
            EmptyView()
        }
    }

    // MARK: Pill

    private var pill: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pillTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(light: 0x111827, dark: 0x111827))
                    .lineLimit(1)
                if let pillDetail {
                    Text(pillDetail)
                        .font(.caption)
                        .foregroundStyle(Color(light: 0x4B5563, dark: 0x4B5563))
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(pillTint, in: Circle())
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.95), in: Capsule())
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
        .fixedSize()
    }

    private var pillTint: Color {
        if case .clean = status { return Theme.Palette.success }
        if case .failed = status { return Theme.Palette.amber }
        return Theme.Palette.brand
    }

    private var pillTitle: String {
        switch status {
        case .ready: return countText
        case .clean: return "All clear"
        case .scanning: return "Scanning"
        case .needsAccess: return category.permission == .photos ? "Allow access" : "Check"
        case .accessDenied: return "Access off"
        case .notScanned: return "Scan"
        case .failed: return "Retry"
        }
    }

    private var pillDetail: String? {
        if case let .ready(_, bytes) = status, let bytes { return Format.bytes(bytes) }
        return nil
    }
}

/// A duplicate contact shown as a small contact card with the person's photo (or monogram), with
/// the duplicate card peeking out behind it.
struct ContactCardPreview: View {
    let contacts: [ContactRecord]
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
            if contacts.count > 1 {
                card(contacts[1])
                    .scaleEffect(0.9)
                    .rotationEffect(.degrees(6))
                    .offset(x: 10, y: -12)
                    .opacity(0.7)
            }
            if let first = contacts.first {
                card(first)
                    .rotationEffect(.degrees(-3))
                    .offset(y: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contacts.first.map { "Possible duplicate: \($0.displayName)" } ?? "Duplicate contacts")
    }

    private func card(_ contact: ContactRecord) -> some View {
        VStack(spacing: 6) {
            ContactPhoto(contact: contact, tint: tint, size: 54)
            Text(contact.displayName.isEmpty ? "No name" : contact.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
            if let line = contact.phones.first ?? contact.emails.first {
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: 118)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.Palette.shadow, radius: 8, y: 4)
    }
}

/// The contact's own photo, or a monogram on a soft gradient when there isn't one.
struct ContactPhoto: View {
    let contact: ContactRecord
    let tint: Color
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let data = contact.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(contact.initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
        .accessibilityHidden(true)
    }
}

/// The iPhone's real battery status from iOS. CleanSpace can't measure battery "saved" by a
/// cleanup (iOS doesn't expose that, and freeing storage doesn't measurably change battery life),
/// so this shows only what iOS reports.
struct BatteryCard: View {
    @State private var level: Float = -1
    @State private var state: UIDevice.BatteryState = .unknown
    @State private var lowPower = false

    /// Compact chip style.
    var compact = false
    /// Tall battery gauge for beside the water bubble.
    var vertical = false

    var body: some View {
        Group {
            if vertical { verticalBody } else if compact { compactBody } else { fullBody }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            refresh()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIDevice.batteryLevelDidChangeNotification) { refresh() }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIDevice.batteryStateDidChangeNotification) { refresh() }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: Notification.Name.NSProcessInfoPowerStateDidChange) { refresh() }
        }
        .accessibilityElement(children: .combine)
    }

    private var fullBody: some View {
        HStack(spacing: Theme.Spacing.m) {
            CleanSpaceIcon(symbol: symbol, tint: color, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Battery")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text(level >= 0 ? "\(Int((level * 100).rounded()))%" : "Not available")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.numericText())
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.track)
                        Capsule().fill(color)
                            .frame(width: proxy.size.width * CGFloat(max(level, 0)))
                    }
                }
                .frame(height: 6)
                .animation(.easeOut(duration: 0.6), value: level)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    /// A tall battery that fills from the bottom to the real charge level.
    private var verticalBody: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(color.opacity(0.9), lineWidth: 2.5)
                GeometryReader { proxy in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(0, (proxy.size.height) * CGFloat(max(level, 0))))
                    }
                }
                .padding(6)
                .animation(.easeOut(duration: 0.8), value: level)
                if state == .charging || state == .full {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 58, height: 112)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(color.opacity(0.9))
                    .frame(width: 22, height: 6)
                    .offset(y: -8)
            }
            .padding(.top, 8)
            Text(level >= 0 ? "\(Int((level * 100).rounded()))%" : "--")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .contentTransition(.numericText())
            Text(level >= 0 ? shortDetail : "Battery")
                .font(.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 84)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level >= 0 ? "Battery \(Int((level * 100).rounded())) percent, \(shortDetail)" : "Battery level not available")
    }

    private var compactBody: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(level >= 0 ? "\(Int((level * 100).rounded()))%" : "Battery")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .contentTransition(.numericText())
            Text(shortDetail)
                .font(.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 18)
    }

    private var shortDetail: String {
        guard level >= 0 else { return "Not available" }
        var text: String
        switch state {
        case .charging: text = "Charging"
        case .full: text = "Fully charged"
        case .unplugged: text = "On battery"
        default: text = "Battery"
        }
        if lowPower { text += ", Low Power Mode" }
        return text
    }

    private func refresh() {
        level = UIDevice.current.batteryLevel
        state = UIDevice.current.batteryState
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var symbol: String {
        if state == .charging || state == .full { return "battery.100percent.bolt" }
        switch level {
        case ..<0: return "battery.0percent"
        case ..<0.2: return "battery.25percent"
        case ..<0.5: return "battery.50percent"
        case ..<0.8: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var color: Color {
        if lowPower { return Theme.Palette.amber }
        if level >= 0 && level < 0.2 && state != .charging { return Theme.Palette.coral }
        return Theme.Palette.success
    }

    private var detail: String {
        var parts: [String] = []
        switch state {
        case .charging: parts.append("Charging")
        case .full: parts.append("Fully charged")
        case .unplugged: parts.append("On battery")
        default: break
        }
        parts.append(lowPower ? "Low Power Mode is on" : "Low Power Mode is off")
        return parts.joined(separator: ". ") + ". Keeping some storage free helps your iPhone run smoothly."
    }
}
