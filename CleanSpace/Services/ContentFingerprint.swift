import CryptoKit
import Foundation
import Photos
import UIKit

/// Content fingerprints used to confirm exact duplicates.
///
/// Primary: SHA-256 of the photo's current file (the edited version if there is one), streamed
/// from local storage in chunks, so the whole file is never held in memory. Only called for the
/// few photos whose visual fingerprints and dimensions already match exactly.
///
/// Fallback when the file isn't on the device (iCloud "Optimize Storage"): SHA-256 of the decoded
/// pixels of an exact 256-pixel rendering. File and pixel fingerprints never match each other,
/// so a photo is only called a duplicate when both copies were compared the same way.
enum ContentFingerprint {
    private final class Accumulator: @unchecked Sendable {
        var hasher = SHA256()
        var failed = false
        let lock = NSLock()
    }

    static func digest(for asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizePhoto })
                ?? resources.first(where: { $0.type == .photo }) else {
            return renderDigest(for: asset)
        }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let accumulator = Accumulator()
        let done = DispatchSemaphore(value: 0)
        PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { chunk in
            accumulator.lock.lock()
            accumulator.hasher.update(data: chunk)
            accumulator.lock.unlock()
        }, completionHandler: { error in
            accumulator.lock.lock()
            accumulator.failed = error != nil
            accumulator.lock.unlock()
            done.signal()
        })
        done.wait()
        if accumulator.failed { return renderDigest(for: asset) }
        return "file:" + hex(accumulator.hasher.finalize())
    }

    private final class ImageBox: @unchecked Sendable {
        var image: CGImage?
    }

    static func renderDigest(for asset: PHAsset) -> String? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        let box = ImageBox()
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 256, height: 256),
                                              contentMode: .aspectFit, options: options) { image, _ in
            box.image = image?.cgImage
        }
        guard let image = box.image, let data = image.dataProvider?.data as Data? else { return nil }
        var hasher = SHA256()
        hasher.update(data: Data("\(image.width)x\(image.height)".utf8))
        hasher.update(data: data)
        return "pixels:" + hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
