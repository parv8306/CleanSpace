import SwiftUI

struct ScreenshotsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let model = app.screenshots
        Group {
            if model.items.isEmpty && (model.phase.isScanning || !model.hasResults) {
                ScanningStateView(title: "Finding screenshots", phase: model.phase, unit: "screenshots",
                                  onCancel: model.phase.isScanning ? { model.cancel() } : nil)
            } else if model.items.isEmpty {
                EmptyStateView(symbol: "camera.viewfinder",
                               title: "No screenshots to clean",
                               message: "There are no screenshots in your library.",
                               actionTitle: "Scan again") { model.scan() }
            } else {
                MediaGridView(category: .screenshots, sections: model.sections) {
                    header(model)
                }
                .refreshable { model.scan() }
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: .screenshots)
        }
        .animation(.snappy, value: app.selectedCount(in: .screenshots) > 0)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SelectAllButton(category: .screenshots, ids: model.items.map(\.id))
            }
        }
        .task { app.ensureScanned(.screenshots) }
    }

    private func header(_ model: MediaListModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SummaryHeader(
                title: model.hasResults ? Format.bytes(model.totalBytes) : Format.count(model.items.count, "screenshot"),
                subtitle: model.hasResults
                    ? "\(Format.count(model.items.count, "screenshot")), newest first"
                    : "Measuring sizes"
            )
            if let counts = model.phase.counts, counts.total > 0 {
                ProgressView(value: Double(counts.done), total: Double(max(counts.total, 1)))
                    .tint(Theme.Palette.screenshots)
            }
            Text("Tap to select. Use Select next to a month to take it all at once. Touch and hold to preview.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }
}

struct BlurryPhotosView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let model = app.similar
        Group {
            if model.phase.isScanning && !model.hasResults {
                ScanningStateView(title: "Checking sharpness", phase: model.phase, unit: "photos",
                                  onCancel: { model.cancel() })
            } else if !model.hasResults {
                ScanningStateView(title: "Getting ready", phase: model.phase)
            } else if model.blurry.isEmpty {
                EmptyStateView(symbol: "camera.aperture",
                               title: "Everything looks sharp",
                               message: "No blurry photos found.",
                               actionTitle: "Scan again") { model.scan() }
            } else {
                MediaGridView(category: .blurryPhotos, sections: model.blurrySections) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SummaryHeader(title: Format.bytes(model.blurryBytes),
                                      subtitle: "\(Format.count(model.blurry.count, "photo")) look out of focus")
                        Text("Found by measuring edge detail on a small copy of each photo. Nothing is pre-selected, so check before you choose.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: .blurryPhotos)
        }
        .animation(.snappy, value: app.selectedCount(in: .blurryPhotos) > 0)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SelectAllButton(category: .blurryPhotos, ids: model.blurry.map(\.id))
            }
        }
        .task { app.ensureScanned(.blurryPhotos) }
    }
}
