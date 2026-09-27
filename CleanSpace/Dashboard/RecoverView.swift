import SwiftUI

/// How to get deleted items back. iOS doesn't let apps restore from Recently Deleted, so this
/// explains where they are, how long they stay, and opens Photos, alongside thumbnails of what
/// CleanSpace removed in the last 30 days.
struct RecoverView: View {
    @Environment(AppState.self) private var app

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    private var recent: [CleanupRecord] {
        let limit = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return app.history.filter { $0.date >= limit && !($0.items ?? []).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recover deleted items")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Photos and videos you delete stay in Recently Deleted in the Photos app for 30 days. You can bring them back from there at any time before then.")
                        .font(.body)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: 20)

                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Open the Photos app.")
                    step(2, "Scroll to Utilities and open Recently Deleted. You may need Face ID.")
                    step(3, "Select the items and tap Recover.")
                }
                .card()

                Button {
                    if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                } label: {
                    PrimaryButtonLabel(title: "Open Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(PressableButtonStyle())

                if recent.isEmpty {
                    Text("Nothing has been deleted with CleanSpace in the last 30 days.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Deleted with CleanSpace")
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.ink)
                        ForEach(recent) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.Palette.ink)
                                    Spacer()
                                    Text(daysLeft(record.date))
                                        .font(.caption)
                                        .foregroundStyle(Theme.Palette.secondaryText)
                                }
                                LazyVGrid(columns: columns, spacing: 6) {
                                    ForEach(record.items ?? []) { item in HistoryThumbnailTile(item: item) }
                                }
                            }
                        }
                    }
                }

                Text("Contact changes, deleted calendar events and items removed from the private vault can't be recovered.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .padding(20)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.Palette.brand)
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func daysLeft(_ date: Date) -> String {
        let passed = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        let left = max(30 - passed, 0)
        return left == 1 ? "About 1 day left" : "About \(left) days left"
    }
}
