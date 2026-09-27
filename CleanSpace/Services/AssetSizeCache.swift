import Foundation
import Photos

/// Thread-safe cache of on-record file sizes for assets.
///
/// Reading sizes means asking PhotoKit for every resource of every item, which is one of the
/// slowest parts of a scan. Sizes are therefore also kept on disk (in Caches, keyed by the
/// asset's identifier and checked against its modification date), so launches and rescans only
/// measure new or edited items. "Clear temporary files" removes the stored sizes.
final class AssetSizeCache: @unchecked Sendable {
    static let shared = AssetSizeCache()

    private struct Stored: Codable {
        let modified: Double
        let size: Int64
    }

    private let lock = NSLock()
    private var storage: [String: Int64] = [:]
    private var persisted: [String: Stored] = [:]
    private var loaded = false
    private var dirty = false

    private var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("asset-sizes-v1.plist")
    }

    func size(for asset: PHAsset) -> Int64 {
        let key = asset.localIdentifier
        let modified = asset.modificationDate?.timeIntervalSince1970 ?? 0
        lock.lock()
        loadIfNeededLocked()
        if let cached = storage[key] {
            lock.unlock()
            return cached
        }
        if let stored = persisted[key], stored.modified == modified {
            storage[key] = stored.size
            lock.unlock()
            return stored.size
        }
        lock.unlock()
        let value = Self.computeSize(asset)
        lock.lock()
        storage[key] = value
        persisted[key] = Stored(modified: modified, size: value)
        dirty = true
        lock.unlock()
        return value
    }

    func forget(_ ids: Set<String>) {
        lock.lock()
        for id in ids {
            storage[id] = nil
            persisted[id] = nil
        }
        dirty = true
        lock.unlock()
    }

    /// Writes new sizes to disk. Called when a scan finishes.
    func save() {
        lock.lock()
        guard dirty, let url = fileURL else { lock.unlock(); return }
        let snapshot = persisted
        dirty = false
        lock.unlock()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }

    func clear() {
        lock.lock()
        storage = [:]
        persisted = [:]
        dirty = false
        lock.unlock()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }

    private func loadIfNeededLocked() {
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? PropertyListDecoder().decode([String: Stored].self, from: data) else { return }
        persisted = decoded
    }

    /// Sums every resource that would be removed with the asset (original, edited render,
    /// Live Photo video…). PhotoKit exposes the byte count through the `fileSize` key of
    /// PHAssetResource; there is no public typed property for it.
    static func computeSize(_ asset: PHAsset) -> Int64 {
        var total: Int64 = 0
        for resource in PHAssetResource.assetResources(for: asset) {
            if let number = resource.value(forKey: "fileSize") as? NSNumber {
                total += number.int64Value
            }
        }
        return total
    }
}
