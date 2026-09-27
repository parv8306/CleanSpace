import SwiftUI

struct PhotoGroupDetailView: View {
    let groupID: String

    private var category: CleanupCategory {
        app.similar.group(id: groupID)?.kind == .duplicates ? .duplicatePhotos : .similarPhotos
    }

    @Environment(AppState.self) private var app
    @State private var previewItem: MediaItem?

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.m),
                           GridItem(.flexible(), spacing: Theme.Spacing.m)]

    var body: some View {
        Group {
            if let group = app.similar.group(id: groupID) {
                content(group)
            } else {
                EmptyStateView(symbol: "checkmark.circle",
                               title: "This group is gone",
                               message: "Its photos were removed or changed since the last scan.")
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: category)
        }
        .navigationTitle("Group review")
        .navigationBarTitleDisplayMode(.inline)
        .glassCover(item: $previewItem) { item in
            PhotoPreviewView(item: item, category: category)
                .environment(app)
        }
    }

    private func content(_ group: PhotoGroup) -> some View {
        let selectedIDs = app.selection.ids(category)
        let allSelected = group.items.allSatisfy { selectedIDs.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SummaryHeader(title: "\(group.items.count.formatted()) \(group.kind == .duplicates ? "duplicates" : "similar photos")",
                              subtitle: "Tap to select or keep. Touch and hold a photo to preview it or make it the one to keep.")

                if allSelected {
                    Label("Every photo in this group is selected. If you delete them all, no copy is left.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Palette.amber)
                        .card(padding: Theme.Spacing.m)
                }

                LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                    ForEach(group.items) { item in
                        detailTile(item, group: group, isSelected: selectedIDs.contains(item.id))
                    }
                }

                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        app.selection.deselect(group.items.map(\.id), in: category)
                        app.selection.select(group.reclaimableItems.map(\.id), in: category)
                    } label: {
                        Text("Select all but best").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        app.selection.deselect(group.items.map(\.id), in: category)
                    } label: {
                        Text("Keep all").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(Theme.Spacing.l)
        }
    }

    private func detailTile(_ item: MediaItem, group: PhotoGroup, isSelected: Bool) -> some View {
        let isBest = item.id == group.bestID
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                app.selection.toggle(item.id, in: category)
            } label: {
                Color.clear
                    .aspectRatio(0.8, contentMode: .fit)
                    .overlay { AssetThumbnail(id: item.id, side: 220) }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                            .strokeBorder(isSelected ? Theme.Palette.brand : (isBest ? Theme.Palette.success : Color.clear),
                                          lineWidth: 3)
                    }
                    .overlay(alignment: .topLeading) { if isBest { BestBadge().padding(8) } }
                    .overlay(alignment: .topTrailing) { SelectionCheck(isSelected: isSelected, size: 26).padding(8) }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button { previewItem = item } label: { Label("Preview", systemImage: "eye") }
                if !isBest {
                    Button {
                        app.similar.setBest(item.id, inGroup: group.id)
                        app.selection.deselect([item.id], in: category)
                    } label: {
                        Label("Keep this one as best", systemImage: "star")
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(isBest ? "Best photo" : "Photo"), \(Format.date(item.creationDate))")
            .accessibilityValue(isSelected ? "Selected for removal" : "Kept")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Preview") { previewItem = item }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileSize > 0 ? Format.bytes(item.fileSize) : "Size unknown")
                    .font(Theme.Typography.rowNumber)
                    .foregroundStyle(Theme.Palette.ink)
                Text([item.resolutionText, Format.date(item.creationDate)].compactMap { $0 }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(2)
                if item.isScreenshot {
                    Text("Screenshot")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
        }
    }
}
