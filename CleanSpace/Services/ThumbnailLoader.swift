import AVFoundation
import Photos
import UIKit

/// Small wrapper over PHCachingImageManager with an in-memory LRU for decoded thumbnails.
/// All requests are local-only (no iCloud downloads).
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    private let manager = PHCachingImageManager()
    private let images = NSCache<NSString, UIImage>()
    private let assets = NSCache<NSString, PHAsset>()

    private init() {
        images.countLimit = 500
        images.totalCostLimit = 120 * 1024 * 1024
        assets.countLimit = 5000
        manager.allowsCachingHighQualityImages = false
    }

    func asset(for id: String) -> PHAsset? {
        if let cached = assets.object(forKey: id as NSString) { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        assets.setObject(asset, forKey: id as NSString)
        return asset
    }

    /// Delivers a fast degraded image first (when available), then the final one. Always on main.
    @discardableResult
    func requestImage(id: String,
                      pixelSize: CGSize,
                      contentMode: PHImageContentMode = .aspectFill,
                      completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let key = "\(id)|\(Int(pixelSize.width))x\(Int(pixelSize.height))|\(contentMode.rawValue)" as NSString
        if let cached = images.object(forKey: key) {
            completion(cached)
            return nil
        }
        guard let asset = asset(for: id) else {
            completion(nil)
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let images = self.images
        return manager.requestImage(for: asset, targetSize: pixelSize, contentMode: contentMode, options: options) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if let image, !degraded {
                let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
                images.setObject(image, forKey: key, cost: cost)
            }
            if Thread.isMainThread {
                completion(image)
            } else {
                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    func cancel(_ requestID: PHImageRequestID) {
        manager.cancelImageRequest(requestID)
    }

    func forget(_ ids: Set<String>) {
        for id in ids { assets.removeObject(forKey: id as NSString) }
    }

    /// One final (non-degraded) image, for places that need a single result.
    func finalImage(id: String, pixelSize: CGSize) async -> UIImage? {
        guard let asset = asset(for: id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // the handler is called exactly once
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let manager = self.manager
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: pixelSize, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Drops every cached thumbnail and asset lookup. They're rebuilt on demand.
    func clearMemory() {
        images.removeAllObjects()
        assets.removeAllObjects()
    }

    /// Local-only player item. Returns nil for videos that live only in iCloud.
    func playerItem(id: String) async -> AVPlayerItem? {
        guard let asset = asset(for: id) else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}
