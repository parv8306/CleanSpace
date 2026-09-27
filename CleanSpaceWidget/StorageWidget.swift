import SwiftUI
import WidgetKit

struct StorageEntry: TimelineEntry {
    let date: Date
    let storage: DeviceStorage?
    let snapshot: StorageSnapshot?

    static let preview = StorageEntry(
        date: Date(),
        storage: DeviceStorage(total: 128_000_000_000, available: 41_500_000_000),
        snapshot: StorageSnapshot(freeableBytes: 6_400_000_000, lastScan: Date().addingTimeInterval(-7200),
                                  lifetimeFreedBytes: 18_000_000_000, updated: Date())
    )
}

/// Live storage is read directly by the widget; what CleanSpace could free comes from the app's
/// last scan via the App Group. If the App Group isn't available, the widget still shows storage.
struct StorageProvider: TimelineProvider {
    func placeholder(in context: Context) -> StorageEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        completion(context.isPreview ? .preview : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> StorageEntry {
        StorageEntry(date: Date(), storage: try? StorageService.current(), snapshot: SharedStore.read())
    }
}

struct StorageWidget: Widget {
    let kind = "CleanSpaceStorage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StorageProvider()) { entry in
            StorageWidgetView(entry: entry)
                .containerBackground(Theme.Palette.surface, for: .widget)
        }
        .configurationDisplayName("Storage")
        .description("How full your iPhone is, and how much CleanSpace found that can go.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct StorageWidgetView: View {
    let entry: StorageEntry
    @Environment(\.widgetFamily) private var family

    private var used: Double { entry.storage?.usedFraction ?? 0 }
    private var percent: Int { Int((used * 100).rounded()) }
    private var freeableFraction: Double {
        guard let storage = entry.storage, storage.total > 0, let bytes = entry.snapshot?.freeableBytes else { return 0 }
        return Double(bytes) / Double(storage.total)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                LiquidGaugeContent(fraction: used, freeable: freeableFraction, phase: 0.6, ringWidth: 3)
                    .frame(width: 58, height: 58)
                Spacer()
                AppLogoMark(size: 20)
            }
            Spacer(minLength: 0)
            Text("\(percent)% full")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
            if let storage = entry.storage {
                Text("\(Format.bytes(storage.available)) free")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            freeableLine
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            LiquidGaugeContent(fraction: used, freeable: freeableFraction, phase: 0.6, ringWidth: 4)
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(percent)% full")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                if let storage = entry.storage {
                    Text("\(Format.bytes(storage.available)) free of \(Format.bytes(storage.total))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                freeableLine
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let lastScan = entry.snapshot?.lastScan {
                    Text("Scanned \(Text(lastScan, style: .relative)) ago")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.secondaryText)
                } else {
                    Text("Open CleanSpace to scan")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var freeableLine: some View {
        if let bytes = entry.snapshot?.freeableBytes, bytes > 0 {
            Text("\(Format.bytes(bytes)) can go")
                .foregroundStyle(Theme.Palette.coral)
        } else if entry.snapshot?.freeableBytes == 0 {
            Text("All clean")
                .foregroundStyle(Theme.Palette.brand)
        } else {
            Text("Tap to scan")
                .foregroundStyle(Theme.Palette.brand)
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: used) {
            Image(systemName: "internaldrive")
        } currentValueLabel: {
            Text("\(percent)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CleanSpace")
                .font(.headline)
                .widgetAccentable()
            if let storage = entry.storage {
                Text("\(Format.bytes(storage.available)) free")
                    .font(.caption)
            }
            Gauge(value: used) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
    }
}
