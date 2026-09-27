import SwiftUI

/// Duplicate Photos (exact copies) and Similar Photos (look-alikes) share this screen.
struct SimilarPhotosView: View {
    var kind: PhotoGroup.Kind = .similar
    @Environment(AppState.self) private var app

    private var category: CleanupCategory { kind == .duplicates ? .duplicatePhotos : .similarPhotos }

    var body: some View {
        let model = app.similar
        let groups = model.groups(of: kind)
        Group {
            if !model.hasResults {
                ScanningStateView(title: "Comparing photos", phase: model.phase, unit: "photos",
                                  onCancel: model.phase.isScanning ? { model.cancel() } : nil)
            } else if groups.isEmpty {
                EmptyStateView(symbol: category.symbol,
                               title: "You're all clear",
                               message: kind == .duplicates
                                   ? "No exact copies found in \(Format.count(model.scannedCount, "photo"))."
                                   : "No look-alike photos found in \(Format.count(model.scannedCount, "photo")).",
                               actionTitle: "Scan again") { model.scan() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header(model, groups: groups)
                        ForEach(groups) { group in
                            PhotoGroupCard(group: group)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
                .refreshable { model.scan() }
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: category)
        }
        .animation(.snappy, value: app.selectedCount(in: category) > 0)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        app.selection.replace(app.suggestedSelection(for: category), in: category)
                    } label: {
                        Label("Select suggested", systemImage: "wand.and.stars")
                    }
                    Button {
                        app.selection.replace(Set(groups.flatMap { $0.reclaimableItems.map(\.id) }), in: category)
                    } label: {
                        Label("Select all extras", systemImage: "checkmark.circle")
                    }
                    Button {
                        app.selection.replace([], in: category)
                    } label: {
                        Label("Deselect all", systemImage: "circle")
                    }
                    Divider()
                    Button {
                        app.path.append(.swipe(kind == .duplicates ? .duplicates : .similar))
                    } label: {
                        Label("Swipe to review", systemImage: "hand.draw")
                    }
                } label: {
                    Image(systemName: "checklist")
                }
                .disabled(groups.isEmpty)
                .accessibilityLabel("Selection options")
            }
        }
        .task { app.ensureScanned(category) }
    }

    /// Nothing is pre-selected. These buttons are the only way suggestions get selected.
    private func selectionControls(groups: [PhotoGroup]) -> some View {
        let suggested = app.suggestedSelection(for: category)
        let selected = app.selectedCount(in: category)
        return HStack(spacing: Theme.Spacing.s) {
            Button {
                withAnimation(.snappy) { app.selection.replace(suggested, in: category) }
            } label: {
                Label("Select suggested (\(suggested.count.formatted()))", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .modifier(TintedGlassCapsule(tint: category.tint))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(suggested.isEmpty)
            if selected > 0 {
                Button {
                    withAnimation(.snappy) { app.selection.replace([], in: category) }
                } label: {
                    Text("Deselect all")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(Theme.Palette.brand)
                        .glassSurface(cornerRadius: 20)
                }
                .buttonStyle(PressableButtonStyle())
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func header(_ model: SimilarPhotosModel, groups: [PhotoGroup]) -> some View {
        let reclaimable = groups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        let extras = groups.reduce(0) { $0 + $1.reclaimableItems.count }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SummaryHeader(title: Format.bytes(reclaimable),
                          subtitle: kind == .duplicates
                              ? "reclaimable from \(Format.count(extras, "extra copy", "extra copies")) in \(Format.count(groups.count, "group"))"
                              : "could be freed from \(Format.count(groups.count, "group")) of look-alike photos")
            Text(kind == .duplicates
                 ? "Exact copies of the same photo, confirmed by comparing their content. Tap Select suggested to pick every extra copy and keep one of each, or choose photos yourself."
                 : "Photos that look alike but aren't exact copies. The best shot in each group is marked Keep. Tap Select suggested to pick the rest (never favorites), or choose photos yourself.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
            selectionControls(groups: groups)
            if model.skippedCount > 0 {
                Label("\(Format.count(model.skippedCount, "photo")) couldn't be analyzed because no preview of them is on this iPhone. CleanSpace never downloads your media.",
                      systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            if model.phase.isScanning {
                Label("Rescanning", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Button {
                app.path.append(.swipe(kind == .duplicates ? .duplicates : .similar))
            } label: {
                HStack {
                    Image(systemName: "hand.draw.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Swipe to review")
                            .font(.subheadline.weight(.semibold))
                        Text("Decide one photo at a time")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .foregroundStyle(category.tint)
                .card(padding: Theme.Spacing.m)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}

struct PhotoGroupCard: View {
    let group: PhotoGroup
    @Environment(AppState.self) private var app

    private var category: CleanupCategory { group.kind == .duplicates ? .duplicatePhotos : .similarPhotos }

    var body: some View {
        let selectedIDs = app.selection.ids(category)
        let selectedItems = group.items.filter { selectedIDs.contains($0.id) }
        let allSelected = selectedItems.count == group.items.count
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            NavigationLink(value: Route.photoGroup(group.id)) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.kind == .duplicates ? "Duplicate group" : "Similar group")
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.ink)
                        Text("\(group.items.count.formatted()) photos, \(Format.bytes(group.totalBytes))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Review")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.brand)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.s) {
                    ForEach(group.items) { item in
                        GroupPhotoTile(item: item, isBest: item.id == group.bestID,
                                       isSelected: selectedIDs.contains(item.id), side: 104) {
                            app.selection.toggle(item.id, in: category)
                        }
                    }
                }
            }
            .frame(height: 104)

            if let best = group.items.first(where: { $0.id == group.bestID }) {
                Label {
                    Text("Recommended to keep: ") + Text(bestDescription(best)).fontWeight(.semibold)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
                }
                .font(.footnote)
                .foregroundStyle(Theme.Palette.ink)
            }

            HStack(spacing: Theme.Spacing.s) {
                if allSelected {
                    Label("Every photo is selected. Keep at least one if you want a copy.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Palette.amber)
                } else if selectedItems.isEmpty {
                    Text("Keeping all")
                        .foregroundStyle(Theme.Palette.secondaryText)
                } else {
                    Text("\(selectedItems.count.formatted()) selected, \(Format.bytes(selectedItems.reduce(0) { $0 + $1.fileSize }))")
                        .foregroundStyle(Theme.Palette.brand)
                }
            }
            .font(.footnote.weight(.medium))
        }
        .card()
    }

    private func bestDescription(_ item: MediaItem) -> String {
        if item.isFavorite { return "your favorite" }
        if group.kind == .duplicates { return "one copy (\(Format.date(item.creationDate)))" }
        return "the sharpest, highest-resolution shot"
    }
}

/// Photo tile with the "Best" badge and selection state.
struct GroupPhotoTile: View {
    let item: MediaItem
    let isBest: Bool
    let isSelected: Bool
    var side: CGFloat = 104
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AssetThumbnail(id: item.id, side: side)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Theme.Palette.brand.opacity(0.14))
                    }
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(isSelected ? Theme.Palette.brand : (isBest ? Theme.Palette.success : Color.clear),
                                      lineWidth: 3)
                }
                .scaleEffect(isSelected ? 0.95 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.35), value: isSelected)
                .overlay(alignment: .topLeading) {
                    if isBest { BestBadge().padding(5) }
                }
                .overlay(alignment: .topTrailing) {
                    SelectionCheck(isSelected: isSelected, size: 22).padding(5)
                }
                .overlay(alignment: .bottomLeading) {
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isBest ? "Best photo" : "Photo"), \(Format.date(item.creationDate)), \(Format.bytes(item.fileSize))")
        .accessibilityValue(isSelected ? "Selected for removal" : "Kept")
        .accessibilityAddTraits(.isButton)
    }
}

struct BestBadge: View {
    var body: some View {
        Label("Keep", systemImage: "checkmark")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.Palette.success, in: Capsule())
    }
}
