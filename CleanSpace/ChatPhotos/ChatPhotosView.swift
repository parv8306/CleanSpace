import SwiftUI

/// Photos likely saved from chat apps, with optional grouping by platform when file names say so.
struct ChatPhotosView: View {
    @Environment(AppState.self) private var app
    @State private var platform: ChatPlatform?

    var body: some View {
        let model = app.similar
        let items = platform.map { wanted in model.chatPhotos.filter { model.chatPlatforms[$0.id] == wanted } } ?? model.chatPhotos
        Group {
            if !model.hasResults {
                ScanningStateView(title: "Looking for chat photos", phase: model.phase, unit: "photos",
                                  onCancel: model.phase.isScanning ? { model.cancel() } : nil)
            } else if model.chatPhotos.isEmpty {
                EmptyStateView(symbol: CleanupCategory.chatPhotos.symbol,
                               title: "No chat photos found",
                               message: "None of your photos look like they were saved from a chat app. Photos from iMessage can't be told apart from camera photos.",
                               actionTitle: "Scan again") { model.scan() }
            } else {
                MediaGridView(category: .chatPhotos, sections: MediaSection.byMonth(items)) {
                    header(model, items: items)
                }
                .refreshable { model.scan() }
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: .chatPhotos)
        }
        .animation(.snappy, value: app.selectedCount(in: .chatPhotos) > 0)
        .animation(.snappy, value: platform)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SelectAllButton(category: .chatPhotos, ids: items.map(\.id))
            }
        }
        .task { app.ensureScanned(.chatPhotos) }
    }

    private func header(_ model: SimilarPhotosModel, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SummaryHeader(title: Format.bytes(items.reduce(0) { $0 + $1.fileSize }),
                          subtitle: "\(Format.count(items.count, "photo")) likely saved from chat apps")
            Label("iOS doesn't record which app saved a photo. CleanSpace looks at file names and the way chat apps compress photos, so treat this as a best guess and check before deleting.",
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
            let counts = model.chatPlatformCounts
            if counts.count > 1 || counts.first?.platform != .other {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        chip(title: "All", count: model.chatPhotos.count, selected: platform == nil) { platform = nil }
                        ForEach(counts, id: \.platform) { entry in
                            chip(title: entry.platform.title, count: entry.count, selected: platform == entry.platform) {
                                platform = entry.platform
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func chip(title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Text(count.formatted())
                    .foregroundStyle(selected ? .white.opacity(0.8) : Theme.Palette.secondaryText)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : Theme.Palette.ink)
            .background(selected ? AnyShapeStyle(Theme.buttonGradient) : AnyShapeStyle(Theme.Palette.surface), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.separator, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
