import AVKit
import SwiftUI

struct LargeVideosView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case large, all
        var id: String { rawValue }
        var title: String { self == .large ? "Over \(Format.bytes(MediaListModel.largeVideoThreshold))" : "All videos" }
    }

    @Environment(AppState.self) private var app
    @State private var filter: Filter = .large
    @State private var previewItem: MediaItem?
    @State private var compressItem: MediaItem?

    var body: some View {
        let model = app.videos
        let visible = filter == .large ? model.largeVideos : model.items
        Group {
            if !model.hasResults {
                ScanningStateView(title: "Measuring videos", phase: model.phase, unit: "videos",
                                  onCancel: model.phase.isScanning ? { model.cancel() } : nil)
            } else if model.items.isEmpty {
                EmptyStateView(symbol: "film",
                               title: "No videos yet",
                               message: "There are no videos in your library.",
                               actionTitle: "Scan again") { model.scan() }
            } else {
                list(model: model, visible: visible)
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: .largeVideos)
        }
        .animation(.snappy, value: app.selectedCount(in: .largeVideos) > 0)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SelectAllButton(category: .largeVideos, ids: visible.map(\.id))
            }
        }
        .glassCover(item: $previewItem) { item in
            VideoPreviewView(item: item)
                .environment(app)
        }
        .glassCover(item: $compressItem, chrome: .none) { item in
            CompressVideoSheet(item: item)
                .environment(app)
        }
        .task { app.ensureScanned(.largeVideos) }
    }

    private func list(model: MediaListModel, visible: [MediaItem]) -> some View {
        let largest = max(model.items.first?.fileSize ?? 1, 1)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SummaryHeader(
                    title: Format.bytes(visible.reduce(0) { $0 + $1.fileSize }),
                    subtitle: "\(Format.count(visible.count, "video")), largest first"
                )
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Button {
                    app.path.append(.compressVideos)
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.compress)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Compress instead of deleting")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                            Text("Keep the memory, free most of the space")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .card(padding: Theme.Spacing.m)
                }
                .buttonStyle(PressableButtonStyle())

                if model.phase.isScanning {
                    Label("Refreshing sizes", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }

                if visible.isEmpty {
                    EmptyStateView(symbol: "film",
                                   title: "Your videos are under control",
                                   message: "No videos are larger than \(Format.bytes(MediaListModel.largeVideoThreshold)).",
                                   actionTitle: "Show all videos") { filter = .all }
                        .frame(minHeight: 300)
                } else {
                    LazyVStack(spacing: Theme.Spacing.s) {
                        ForEach(visible) { item in
                            VideoRow(item: item,
                                     fraction: Double(item.fileSize) / Double(largest),
                                     isSelected: app.selection.contains(item.id, in: .largeVideos),
                                     onToggle: { app.selection.toggle(item.id, in: .largeVideos) },
                                     onPreview: { previewItem = item })
                                .contextMenu {
                                    Button { previewItem = item } label: { Label("Play", systemImage: "play") }
                                    Button { compressItem = item } label: {
                                        Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                                    }
                                }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .refreshable { model.scan() }
    }
}

struct VideoRow: View {
    let item: MediaItem
    let fraction: Double
    let isSelected: Bool
    let onToggle: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: onPreview) {
                HStack(spacing: Theme.Spacing.m) {
                    ZStack(alignment: .bottomTrailing) {
                        AssetThumbnail(id: item.id, side: 92)
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        Text(Format.duration(item.duration))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(4)
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 3)
                            .frame(width: 92, height: 92)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.fileSize > 0 ? Format.bytes(item.fileSize) : "Size unknown")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.Palette.ink)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.track)
                                Capsule()
                                    .fill(Theme.Palette.videos)
                                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
                            }
                        }
                        .frame(height: 5)
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Video, \(Format.bytes(item.fileSize)), \(Format.duration(item.duration)), \(Format.date(item.creationDate))")
            .accessibilityHint("Opens a preview")

            CheckboxButton(isSelected: isSelected, action: onToggle)
        }
        .padding(Theme.Spacing.m)
        .glassSurface(cornerRadius: Theme.Radius.medium)
        .shadow(color: Theme.Palette.shadow, radius: 10, x: 0, y: 5)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile + 4, style: .continuous)
                .strokeBorder(isSelected ? Theme.Palette.brand : Color.clear, lineWidth: 2)
        }
    }

    private var metadata: String {
        var parts = [Format.date(item.creationDate)]
        if let resolution = item.resolutionText { parts.append(resolution) }
        return parts.joined(separator: ", ")
    }
}

/// Full video preview (on-device copies only), with a select toggle so the decision can be made here.
struct VideoPreviewView: View {
    let item: MediaItem

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var unavailable = false
    @State private var compressing: MediaItem?

    var body: some View {
        let selected = app.selection.contains(item.id, in: .largeVideos)
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .fill(Color.black)
                    if let player {
                        VideoPlayer(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    } else if unavailable {
                        VStack(spacing: Theme.Spacing.s) {
                            AssetThumbnail(id: item.id, side: 400, contentMode: .fit)
                                .frame(maxHeight: 220)
                            Label("This video is stored in iCloud, so it can't be played here without downloading. CleanSpace never downloads your media.",
                                  systemImage: "icloud")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding()
                        }
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxHeight: .infinity)

                VStack(spacing: Theme.Spacing.s) {
                    DetailRow(label: "Size", value: item.fileSize > 0 ? Format.bytes(item.fileSize) : "Unknown")
                    DetailRow(label: "Length", value: Format.duration(item.duration))
                    if let resolution = item.resolutionText {
                        DetailRow(label: "Resolution", value: resolution)
                    }
                    DetailRow(label: "Recorded", value: item.creationDate.map {
                        $0.formatted(date: .long, time: .shortened)
                    } ?? "Unknown")
                }
                .card()

                Button {
                    app.selection.toggle(item.id, in: .largeVideos)
                } label: {
                    Label(selected ? "Selected for removal" : "Select for removal",
                          systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(selected ? Color.white : Theme.Palette.brand)
                        .background(selected ? Theme.Palette.brand : Theme.Palette.brandSoft, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    player?.pause()
                    compressing = item
                } label: {
                    Label("Compress instead", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.compress)
                }
            }
            .padding(Theme.Spacing.l)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if let playerItem = await ThumbnailLoader.shared.playerItem(id: item.id) {
                let newPlayer = AVPlayer(playerItem: playerItem)
                player = newPlayer
                newPlayer.play()
            } else {
                unavailable = true
            }
        }
        .onDisappear { player?.pause() }
        .glassCover(item: $compressing, chrome: .none) { item in
            CompressVideoSheet(item: item).environment(app)
        }
    }
}
