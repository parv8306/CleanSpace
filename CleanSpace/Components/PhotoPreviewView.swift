import SwiftUI

/// Large on-device preview with details and a keep/select toggle.
struct PhotoPreviewView: View {
    let item: MediaItem
    let category: CleanupCategory

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let selected = app.selection.contains(item.id, in: category)
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                AssetThumbnail(id: item.id, side: 900, contentMode: .fit)
                    .background(Theme.Palette.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .frame(maxHeight: .infinity)

                VStack(spacing: Theme.Spacing.s) {
                    DetailRow(label: "Date", value: item.creationDate.map {
                        $0.formatted(date: .long, time: .shortened)
                    } ?? "Unknown")
                    if let resolution = item.resolutionText {
                        DetailRow(label: "Resolution", value: resolution)
                    }
                    if item.fileSize > 0 {
                        DetailRow(label: "Size", value: Format.bytes(item.fileSize))
                    }
                }
                .card()

                Button {
                    app.selection.toggle(item.id, in: category)
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
            }
            .padding(Theme.Spacing.l)
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.Palette.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
