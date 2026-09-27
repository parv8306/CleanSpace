import SwiftUI

/// Tool screen: large videos ranked by how much compression could save.
struct CompressVideosView: View {
    @Environment(AppState.self) private var app
    @State private var compressing: MediaItem?

    var body: some View {
        let model = app.videos
        let candidates = model.items
            .filter { $0.fileSize >= 20_000_000 && $0.duration > 0 }
            .sorted { Self.savings($0) > Self.savings($1) }
        Group {
            if !model.hasResults {
                ScanningStateView(title: "Measuring videos", phase: model.phase, unit: "videos",
                                  onCancel: model.phase.isScanning ? { model.cancel() } : nil)
            } else if candidates.isEmpty {
                EmptyStateView(symbol: "arrow.down.right.and.arrow.up.left",
                               message: "None of your videos are big enough to be worth compressing.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        let total = candidates.reduce(Int64(0)) { $0 + Self.savings($1) }
                        SummaryHeader(title: "Up to \(Format.bytes(total))",
                                      subtitle: "could be saved by compressing \(Format.count(candidates.count, "video")) to 720p")
                        Text("Compressing saves a smaller copy with the same date, place and favorite status. You then choose whether to delete the original.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryText)
                        LazyVStack(spacing: Theme.Spacing.s) {
                            ForEach(candidates) { item in
                                Button { compressing = item } label: { CompressCandidateRow(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
        }
        .background(AppBackdrop())
        .navigationTitle("Compress Videos")
        .navigationBarTitleDisplayMode(.inline)
        .glassCover(item: $compressing, chrome: .none) { item in
            CompressVideoSheet(item: item).environment(app)
        }
        .task { app.ensureScanned(.largeVideos) }
    }

    static func savings(_ item: MediaItem) -> Int64 {
        CompressionEstimator.estimatedSavings(duration: item.duration, originalBytes: item.fileSize, quality: .balanced)
    }
}

private struct CompressCandidateRow: View {
    let item: MediaItem

    var body: some View {
        let saving = CompressionEstimator.estimatedSavings(duration: item.duration, originalBytes: item.fileSize, quality: .balanced)
        HStack(spacing: Theme.Spacing.m) {
            AssetThumbnail(id: item.id, side: 64)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.bytes(item.fileSize))
                    .font(Theme.Typography.rowNumber)
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(Format.duration(item.duration)), \(Format.date(item.creationDate))")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Save about")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Text(Format.bytes(saving))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.compress)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
        }
        .padding(Theme.Spacing.m)
        .glassSurface(cornerRadius: Theme.Radius.tile + 4)
        .contentShape(Rectangle())
    }
}

/// Choose a quality, compress, then keep both or delete the original.
struct CompressVideoSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var job: VideoCompressionJob
    @State private var summary: CleanupSummary?
    @State private var playingCopy: MediaItem?

    init(item: MediaItem) {
        _job = State(initialValue: VideoCompressionJob(item: item))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    CleanupSummaryView(summary: summary) { dismiss() }
                } else {
                    ScrollView { content.padding(Theme.Spacing.l) }
                }
            }
            .navigationTitle(summary == nil ? "Compress Video" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if summary == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(job.isBusy ? "Stop" : "Close") {
                            if job.isBusy { job.cancel() } else { dismiss() }
                        }
                        .disabled(job.stage == .saving || job.stage == .deletingOriginal || job.stage == .verifying)
                    }
                }
            }
        }
        .interactiveDismissDisabled(job.isBusy)
        .glassCover(item: $playingCopy) { copy in
            VideoPreviewView(item: copy).environment(app)
        }
        .onDisappear {
            if case .compressed = job.stage { app.videos.scan() }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                AssetThumbnail(id: job.item.id, side: 96)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.bytes(job.item.fileSize))
                        .font(Theme.Typography.bigNumber)
                        .foregroundStyle(Theme.Palette.ink)
                    Text([Format.duration(job.item.duration), job.item.resolutionText, Format.date(job.item.creationDate)]
                        .compactMap { $0 }.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }

            switch job.stage {
            case .ready, .failed:
                qualityPicker
                if case let .failed(message) = job.stage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Palette.amber)
                }
                if job.canSaveSpace {
                    primaryButton("Compress to about \(Format.bytes(job.estimatedBytes))") {
                        Task { await job.start() }
                    }
                } else {
                    Label("This video is already about as small as it can get at good quality.",
                          systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Palette.brand)
                }
                Text("The original isn't touched until you choose. Compressing takes about as long as the video on newer iPhones, and needs free space for the copy.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            case .preparing:
                progressCard(title: "Preparing", fraction: nil)
            case let .exporting(fraction):
                progressCard(title: "Compressing", fraction: fraction)
            case .verifying:
                progressCard(title: "Checking the compressed video plays", fraction: nil)
            case .saving:
                progressCard(title: "Saving the copy to Photos", fraction: nil)
            case let .compressed(original, new, newID):
                resultCard(original: original, new: new, newID: newID)
                primaryButton("Delete original, free \(Format.bytes(max(original - new, 0)))") {
                    Task { await deleteOriginal(original: original, new: new) }
                }
                Button("Keep both") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                Text("iOS will ask you to confirm. The original stays in Recently Deleted for 30 days.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            case .deletingOriginal:
                progressCard(title: "Waiting for iOS to confirm", fraction: nil)
            case let .notWorthIt(original, new):
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Label("This video is already efficient", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.brand)
                    Text("Compressing only got it from \(Format.bytes(original)) to \(Format.bytes(new)), so nothing was saved. Try a smaller setting, or keep it as it is.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .card()
                qualityPicker
                primaryButton("Try again") { Task { await job.start() } }
            }
        }
    }

    private var qualityPicker: some View {
        VStack(spacing: 0) {
            ForEach(CompressionQuality.allCases) { quality in
                Button {
                    job.quality = quality
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: job.quality == quality ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(job.quality == quality ? Theme.Palette.brand : Theme.Palette.secondaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quality.title).foregroundStyle(Theme.Palette.ink)
                            Text(quality.detail).font(.caption).foregroundStyle(Theme.Palette.secondaryText)
                        }
                        Spacer()
                        Text("about \(Format.bytes(CompressionEstimator.estimatedBytes(duration: job.item.duration, originalBytes: job.item.fileSize, quality: quality)))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(job.quality == quality ? .isSelected : [])
            }
        }
        .card(padding: 0)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Theme.Palette.brand, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func progressCard(title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.Palette.ink)
                Spacer()
                if let fraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            if let fraction {
                ProgressView(value: fraction).tint(Theme.Palette.compress)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if job.targetBytes > 0 {
                HStack {
                    sizeFigure("Original", Format.bytes(job.item.fileSize))
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(Theme.Palette.secondaryText)
                    sizeFigure("Target", "about \(Format.bytes(job.targetBytes))")
                }
            }
            Text("Keep CleanSpace open until this finishes.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .card()
    }

    private func resultCard(original: Int64, new: Int64, newID: String?) -> some View {
        let saved = original > 0 ? Int((Double(original - new) / Double(original) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label("Compressed copy saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.Palette.success)
            HStack(alignment: .top) {
                sizeFigure("Original", Format.bytes(original))
                Spacer()
                sizeFigure("Target", "about \(Format.bytes(job.targetBytes))")
                Spacer()
                sizeFigure("Compressed", Format.bytes(new), emphasized: true)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.track)
                    Capsule().fill(Theme.buttonGradient)
                        .frame(width: proxy.size.width * CGFloat(original > 0 ? Double(new) / Double(original) : 1))
                }
            }
            .frame(height: 8)
            Text("\(saved)% smaller. Checked: the new file plays and is the full length.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
            if let newID, let asset = ThumbnailLoader.shared.asset(for: newID) {
                Button {
                    playingCopy = PhotoLibraryService.makeItem(from: asset, fileSize: new)
                } label: {
                    Label("Play the compressed copy", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.brand)
                }
            }
        }
        .card()
    }

    private func sizeFigure(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(value)
                .font(.system(emphasized ? .title3 : .subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(emphasized ? Theme.Palette.brand : Theme.Palette.ink)
        }
    }

    private func deleteOriginal(original: Int64, new: Int64) async {
        // Capture a thumbnail first, for Cleanup History; after deletion it's gone.
        let thumbnail = await ThumbnailLoader.shared.finalImage(id: job.item.id, pixelSize: CGSize(width: 180, height: 180))?
            .jpegData(compressionQuality: 0.75)
        let outcome = await job.deleteOriginal()
        guard !outcome.deleted.isEmpty else { return }
        summary = app.recordCompression(originalID: job.item.id, originalBytes: original, newBytes: new,
                                        thumbnail: thumbnail, duration: job.item.duration)
    }
}
