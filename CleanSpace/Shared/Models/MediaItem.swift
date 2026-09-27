import Foundation

/// Lightweight, Sendable snapshot of a PHAsset. We never keep PHAssets or images in our models,
/// only identifiers and metadata, so large libraries stay cheap in memory.
struct MediaItem: Identifiable, Hashable, Sendable {
    let id: String              // PHAsset.localIdentifier
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let isScreenshot: Bool
    let isFavorite: Bool
    var fileSize: Int64         // bytes on record in PhotoKit; 0 when unknown
    var sharpness: Double       // Laplacian variance of a downscaled thumbnail; 0 when unknown

    init(id: String,
         creationDate: Date?,
         pixelWidth: Int,
         pixelHeight: Int,
         duration: TimeInterval = 0,
         isScreenshot: Bool = false,
         isFavorite: Bool = false,
         fileSize: Int64 = 0,
         sharpness: Double = 0) {
        self.id = id
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isScreenshot = isScreenshot
        self.isFavorite = isFavorite
        self.fileSize = fileSize
        self.sharpness = sharpness
    }

    var pixelCount: Int { pixelWidth * pixelHeight }

    var resolutionText: String? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return "\(pixelWidth) × \(pixelHeight)"
    }
}

/// Month buckets for grids ("March 2026"), preserving the incoming item order.
struct MediaSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [MediaItem]

    static func byMonth(_ items: [MediaItem]) -> [MediaSection] {
        let calendar = Calendar.current
        var sections: [MediaSection] = []
        var currentKey: String?
        var currentTitle = ""
        var bucket: [MediaItem] = []
        var usedKeys = Set<String>()

        func flush() {
            guard let key = currentKey, !bucket.isEmpty else { return }
            var uniqueKey = key
            var n = 1
            while usedKeys.contains(uniqueKey) { n += 1; uniqueKey = "\(key)-\(n)" }
            usedKeys.insert(uniqueKey)
            sections.append(MediaSection(id: uniqueKey, title: currentTitle, items: bucket))
        }

        for item in items {
            let key: String
            let title: String
            if let date = item.creationDate {
                let c = calendar.dateComponents([.year, .month], from: date)
                key = "\(c.year ?? 0)-\(c.month ?? 0)"
                title = date.formatted(.dateTime.month(.wide).year())
            } else {
                key = "undated"
                title = "Undated"
            }
            if key != currentKey {
                flush()
                currentKey = key
                currentTitle = title
                bucket = []
            }
            bucket.append(item)
        }
        flush()
        return sections
    }
}
