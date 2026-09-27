import SwiftUI

/// Fast 3-column month-sectioned grid with tap-to-select, per-month bulk selection and a
/// long-press preview. Used by Screenshots and Blurry Photos.
struct MediaGridView<Header: View>: View {
    let category: CleanupCategory
    let sections: [MediaSection]
    @ViewBuilder var header: () -> Header

    @Environment(AppState.self) private var app
    @State private var previewItem: MediaItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            header()
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
            LazyVGrid(columns: columns, spacing: 6, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            tile(item)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(AppBackdrop())
        .glassCover(item: $previewItem) { item in
            PhotoPreviewView(item: item, category: category)
                .environment(app)
        }
    }

    private func tile(_ item: MediaItem) -> some View {
        let selected = app.selection.contains(item.id, in: category)
        return Button {
            app.selection.toggle(item.id, in: category)
        } label: {
            SquareThumbnail(id: item.id, side: 130)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Theme.Palette.brand.opacity(0.16))
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(Theme.Palette.brand, lineWidth: 3)
                    }
                }
                .scaleEffect(selected ? 0.94 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.35), value: selected)
                .overlay(alignment: .topTrailing) {
                    SelectionCheck(isSelected: selected, size: 22).padding(6)
                }
                .overlay(alignment: .bottomLeading) {
                    if item.fileSize > 0 { SizeBadge(bytes: item.fileSize).padding(5) }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { previewItem = item } label: { Label("Preview", systemImage: "eye") }
            Button {
                app.selection.toggle(item.id, in: category)
            } label: {
                Label(selected ? "Keep" : "Select", systemImage: selected ? "arrow.uturn.backward" : "checkmark.circle")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.noun.capitalized), \(Format.date(item.creationDate))\(item.fileSize > 0 ? ", " + Format.bytes(item.fileSize) : "")")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Preview") { previewItem = item }
    }

    private func sectionHeader(_ section: MediaSection) -> some View {
        let ids = section.items.map(\.id)
        let selectedIDs = app.selection.ids(category)
        let allSelected = !ids.isEmpty && ids.allSatisfy { selectedIDs.contains($0) }
        return HStack {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text(section.items.count.formatted())
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
            Spacer()
            Button(allSelected ? "Deselect" : "Select") {
                if allSelected {
                    app.selection.deselect(ids, in: category)
                } else {
                    app.selection.select(ids, in: category)
                }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityLabel(allSelected ? "Deselect \(section.title)" : "Select all from \(section.title)")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.Palette.background.opacity(0.96))
    }
}

/// Toolbar button that flips between Select All and Deselect All.
struct SelectAllButton: View {
    let category: CleanupCategory
    let ids: [String]
    @Environment(AppState.self) private var app

    var body: some View {
        let selected = app.selection.ids(category)
        let allSelected = !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
        Button(allSelected ? "Deselect All" : "Select All") {
            if allSelected {
                app.selection.deselect(ids, in: category)
            } else {
                app.selection.select(ids, in: category)
            }
        }
        .disabled(ids.isEmpty)
    }
}
