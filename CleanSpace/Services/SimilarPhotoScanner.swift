import Foundation
import Photos
import UIKit

struct SimilarScanResult: Sendable {
    /// Photos that look alike but aren't exact copies.
    let groups: [PhotoGroup]
    /// Exact copies (same file content, or same decoded pixels when the file isn't local).
    let duplicateGroups: [PhotoGroup]
    let blurry: [MediaItem]
    /// Photos likely saved from chat apps, newest first.
    let chatPhotos: [MediaItem]
    let chatPlatforms: [String: ChatPlatform]
    let scannedCount: Int
    let skippedCount: Int

    var suggestedIDs: Set<String> { Set(groups.flatMap(\.suggestedDeletionIDs)) }
    var duplicateSuggestedIDs: Set<String> { Set(duplicateGroups.flatMap(\.suggestedDeletionIDs)) }
}

/// Staged pipeline, all off the main thread, over EVERY photo the current authorization allows:
///  1. Metadata: one lazy PHFetchResult (bursts included). Assets are faulted in on access.
///  2. Thumbnails: a ≤256 px image per photo, requested in batches of 64, several at a time.
///     Batches only control memory; nothing is capped. If no high-quality preview is on the
///     device, a lower-resolution one is used rather than skipping the photo.
///  3. Fingerprints: perceptual hash, sharpness and contrast from the thumbnail (ImageAnalyzer),
///     plus chat-app signals from the asset's own metadata.
///  4. Comparison: SimilarityGrouper clusters look-alikes; inside each cluster, photos with the
///     same hash and dimensions are confirmed as exact copies by content fingerprint and split
///     into Duplicate groups. Only one copy of each duplicate set stays in the Similar group.
/// File sizes are read only for photos that end up in a result.
enum SimilarPhotoScanner {
    enum Event: Sendable {
        case progress(done: Int, total: Int)
        /// Every photo has been read; comparing, confirming duplicates and measuring sizes now.
        case analyzing
        case finished(SimilarScanResult)
    }

    static let thumbnailSide: CGFloat = 256
    static let batchSize = 128
    /// Laplacian variance under which a photo is flagged as blurry (on a ≤256px thumbnail).
    static let blurThreshold = 50.0
    /// Photos with less global contrast than this (sky, walls, fog) are never called blurry.
    static let minimumContrastForBlur = 22.0

    private struct Fingerprint: Sendable {
        let hash: UInt64
        let sharpness: Double
        let contrast: Double
        let date: Date?
        let aspectRatio: Double
        let isScreenshot: Bool
        /// False when only a low-resolution preview was available (too coarse to judge blur).
        let sharpnessIsReliable: Bool
        let chat: ChatPlatform?
    }

    static func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                let result = run(progress: { done, total in
                    continuation.yield(.progress(done: done, total: total))
                }, analyzing: {
                    continuation.yield(.analyzing)
                })
                if let result { continuation.yield(.finished(result)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Returns nil if cancelled.
    static func run(progress: (Int, Int) -> Void, analyzing: () -> Void = {}) -> SimilarScanResult? {
        let fetch = PhotoLibraryService.fetchImages()
        let total = fetch.count
        progress(0, total)
        guard total > 0 else {
            return SimilarScanResult(groups: [], duplicateGroups: [], blurry: [], chatPhotos: [],
                                     chatPlatforms: [:], scannedCount: 0, skippedCount: 0)
        }

        // Stages 2 and 3: thumbnails and fingerprints, batch by batch. Photos unchanged since the
        // last scan reuse their cached fingerprint and skip the thumbnail request entirely.
        let cache = FingerprintCache.shared
        cache.loadIfNeeded()
        // A caching manager lets Photos prepare the next batch's thumbnails while this batch is analyzed.
        let manager = PHCachingImageManager()
        let cacheSize = CGSize(width: thumbnailSide, height: thumbnailSide)
        let cacheOptions = Self.requestOptions(delivery: .fastFormat)
        func uncached(_ range: Range<Int>) -> [PHAsset] {
            range.map { fetch.object(at: $0) }.filter { cache.entry(for: $0.localIdentifier, modified: $0.modificationDate) == nil }
        }
        var fingerprints = [Fingerprint?](repeating: nil, count: total)
        var start = 0
        var warming = uncached(0..<min(batchSize, total))
        manager.startCachingImages(for: warming, targetSize: cacheSize, contentMode: .aspectFit, options: cacheOptions)
        while start < total {
            if Task.isCancelled {
                manager.stopCachingImagesForAllAssets()
                return nil
            }
            let end = min(start + batchSize, total)
            let assets = (start..<end).map { fetch.object(at: $0) }
            let next = uncached(end..<min(end + batchSize, total))
            if !next.isEmpty {
                manager.startCachingImages(for: next, targetSize: cacheSize, contentMode: .aspectFit, options: cacheOptions)
            }
            var batch = [Fingerprint?](repeating: nil, count: assets.count)
            batch.withUnsafeMutableBufferPointer { buffer in
                let output = buffer
                DispatchQueue.concurrentPerform(iterations: assets.count) { i in
                    autoreleasepool {
                        output[i] = cachedOrNewFingerprint(for: assets[i], manager: manager, cache: cache)
                    }
                }
            }
            for (offset, value) in batch.enumerated() { fingerprints[start + offset] = value }
            manager.stopCachingImages(for: warming, targetSize: cacheSize, contentMode: .aspectFit, options: cacheOptions)
            warming = next
            start = end
            progress(start, total)
        }
        manager.stopCachingImagesForAllAssets()

        analyzing()
        var liveIDs = Set<String>()
        liveIDs.reserveCapacity(total)
        for i in 0..<total { liveIDs.insert(fetch.object(at: i).localIdentifier) }
        cache.prune(keeping: liveIDs)
        cache.save()

        // Stage 4: comparison.
        var hashed: [HashedPhoto] = []
        var fetchIndexOf: [Int] = []
        hashed.reserveCapacity(total)
        fetchIndexOf.reserveCapacity(total)
        var skipped = 0
        for i in 0..<total {
            if let f = fingerprints[i] {
                hashed.append(HashedPhoto(hash: f.hash, date: f.date, aspectRatio: f.aspectRatio))
                fetchIndexOf.append(i)
            } else {
                skipped += 1
            }
        }
        let clusters = SimilarityGrouper().groups(for: hashed)
        if Task.isCancelled { return nil }

        // Measure every file size the results need, in parallel, before building them.
        var needed = Set<Int>()
        for cluster in clusters { for hashedIndex in cluster { needed.insert(fetchIndexOf[hashedIndex]) } }
        for i in 0..<total {
            guard let f = fingerprints[i] else { continue }
            let blurryCandidate = !f.isScreenshot && f.sharpnessIsReliable
                && f.sharpness < blurThreshold && f.contrast >= minimumContrastForBlur
            if blurryCandidate || f.chat != nil { needed.insert(i) }
        }
        let sizeAssets = needed.map { fetch.object(at: $0) }
        DispatchQueue.concurrentPerform(iterations: sizeAssets.count) { k in
            autoreleasepool { _ = AssetSizeCache.shared.size(for: sizeAssets[k]) }
        }
        if Task.isCancelled { return nil }

        var similarGroups: [PhotoGroup] = []
        var duplicateGroups: [PhotoGroup] = []
        for cluster in clusters {
            if Task.isCancelled { return nil }
            let items: [MediaItem] = autoreleasepool {
                cluster.map { hashedIndex in
                    let fetchIndex = fetchIndexOf[hashedIndex]
                    let asset = fetch.object(at: fetchIndex)
                    return PhotoLibraryService.makeItem(
                        from: asset,
                        fileSize: AssetSizeCache.shared.size(for: asset),
                        sharpness: fingerprints[fetchIndex]?.sharpness ?? 0
                    )
                }
            }

            // Candidates for exact copies: identical visual hash and identical pixel dimensions.
            var buckets: [String: [Int]] = [:]
            for (position, hashedIndex) in cluster.enumerated() {
                let item = items[position]
                buckets["\(hashed[hashedIndex].hash)|\(item.pixelWidth)x\(item.pixelHeight)", default: []].append(position)
            }
            var extraCopyIDs = Set<String>()
            // Identical files have identical sizes, so only same-size candidates are read and hashed.
            var sizeBuckets: [[Int]] = []
            for positions in buckets.values where positions.count > 1 {
                var bySize: [Int64: [Int]] = [:]
                var unknown: [Int] = []
                for position in positions {
                    let size = items[position].fileSize
                    if size > 0 { bySize[size, default: []].append(position) } else { unknown.append(position) }
                }
                sizeBuckets.append(contentsOf: bySize.values.filter { $0.count > 1 })
                if unknown.count > 1 { sizeBuckets.append(unknown) }
            }
            for positions in sizeBuckets {
                var byContent: [String: [MediaItem]] = [:]
                for position in positions {
                    let asset = fetch.object(at: fetchIndexOf[cluster[position]])
                    let digest: String? = autoreleasepool { ContentFingerprint.digest(for: asset) }
                    if let digest { byContent[digest, default: []].append(items[position]) }
                }
                for copies in byContent.values where copies.count > 1 {
                    if let group = PhotoGroup(items: copies, kind: .duplicates) {
                        duplicateGroups.append(group)
                        extraCopyIDs.formUnion(group.reclaimableItems.map(\.id))
                    }
                }
            }

            // What remains (one copy of each duplicate set plus the other look-alikes) is Similar.
            let remaining = items.filter { !extraCopyIDs.contains($0.id) }
            if let group = PhotoGroup(items: remaining, kind: .similar) { similarGroups.append(group) }
        }
        similarGroups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        duplicateGroups.sort { $0.reclaimableBytes > $1.reclaimableBytes }

        var blurry: [MediaItem] = []
        var chatPhotos: [MediaItem] = []
        var chatPlatforms: [String: ChatPlatform] = [:]
        for i in 0..<total {
            guard let f = fingerprints[i] else { continue }
            if Task.isCancelled { return nil }
            let isBlurry = !f.isScreenshot && f.sharpnessIsReliable
                && f.sharpness < blurThreshold && f.contrast >= minimumContrastForBlur
            guard isBlurry || f.chat != nil else { continue }
            let asset = fetch.object(at: i)
            let item = PhotoLibraryService.makeItem(from: asset, fileSize: AssetSizeCache.shared.size(for: asset),
                                                    sharpness: f.sharpness)
            if isBlurry { blurry.append(item) }
            if let chat = f.chat {
                chatPhotos.append(item)
                chatPlatforms[item.id] = chat
            }
        }

        AssetSizeCache.shared.save()
        return SimilarScanResult(groups: similarGroups, duplicateGroups: duplicateGroups, blurry: blurry,
                                 chatPhotos: chatPhotos, chatPlatforms: chatPlatforms,
                                 scannedCount: total - skipped, skippedCount: skipped)
    }

    private final class ImageBox: @unchecked Sendable {
        var image: CGImage?
    }

    private static func requestOptions(delivery: PHImageRequestOptionsDeliveryMode) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = delivery
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false   // never pull from iCloud; on-device data only
        return options
    }

    private static func thumbnail(for asset: PHAsset, manager: PHImageManager,
                                  delivery: PHImageRequestOptionsDeliveryMode) -> CGImage? {
        let options = requestOptions(delivery: delivery)
        let box = ImageBox()
        manager.requestImage(for: asset,
                             targetSize: CGSize(width: thumbnailSide, height: thumbnailSide),
                             contentMode: .aspectFit,
                             options: options) { image, _ in
            box.image = image?.cgImage
        }
        return box.image
    }

    private static func cachedOrNewFingerprint(for asset: PHAsset, manager: PHImageManager,
                                               cache: FingerprintCache) -> Fingerprint? {
        let id = asset.localIdentifier
        let aspect = asset.pixelHeight > 0 ? Double(asset.pixelWidth) / Double(asset.pixelHeight) : 0
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        if let entry = cache.entry(for: id, modified: asset.modificationDate) {
            return Fingerprint(hash: UInt64(bitPattern: entry.hash), sharpness: entry.sharpness,
                               contrast: entry.contrast, date: asset.creationDate, aspectRatio: aspect,
                               isScreenshot: isScreenshot, sharpnessIsReliable: entry.reliable,
                               chat: entry.chat.flatMap(ChatPlatform.init(rawValue:)))
        }
        guard let fresh = fingerprint(for: asset, manager: manager) else { return nil }
        cache.store(FingerprintCache.Entry(modified: asset.modificationDate?.timeIntervalSince1970 ?? 0,
                                           hash: Int64(bitPattern: fresh.hash), sharpness: fresh.sharpness,
                                           contrast: fresh.contrast, reliable: fresh.sharpnessIsReliable,
                                           chat: fresh.chat?.rawValue), for: id)
        return fresh
    }

    private static func fingerprint(for asset: PHAsset, manager: PHImageManager) -> Fingerprint? {
        // Photos' ready-made preview is much quicker than rendering a new one. Only when it's too
        // small to judge sharpness is a proper thumbnail requested.
        var reliable = true
        let quick = thumbnail(for: asset, manager: manager, delivery: .fastFormat)
        var image = quick
        if max(quick?.width ?? 0, quick?.height ?? 0) < 200 {
            if let better = thumbnail(for: asset, manager: manager, delivery: .highQualityFormat) {
                image = better
            } else {
                reliable = false
            }
        }
        guard let image, let analysis = ImageAnalyzer.analyze(image) else { return nil }
        if min(image.width, image.height) < 64 { reliable = false }

        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        // Reading resources is the slowest metadata call, so it's skipped for photos that can't
        // be chat photos: chat apps strip location, and never save screenshots, Live Photos,
        // Portrait shots or bursts.
        let subtypes = asset.mediaSubtypes
        let mayBeChat = !isScreenshot && asset.location == nil && asset.burstIdentifier == nil
            && !subtypes.contains(.photoLive) && !subtypes.contains(.photoDepthEffect)
        var chat: ChatPlatform?
        if mayBeChat {
            let resources = PHAssetResource.assetResources(for: asset)
            let primary = resources.first(where: { $0.type == .photo }) ?? resources.first
            chat = ChatPhotoDetector.classify(filename: primary?.originalFilename,
                                              uniformType: primary?.uniformTypeIdentifier,
                                              pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                                              hasLocation: false,
                                              isScreenshot: false)
        }
        let aspect = asset.pixelHeight > 0 ? Double(asset.pixelWidth) / Double(asset.pixelHeight) : 0
        return Fingerprint(hash: analysis.hash,
                           sharpness: analysis.sharpness,
                           contrast: analysis.contrast,
                           date: asset.creationDate,
                           aspectRatio: aspect,
                           isScreenshot: isScreenshot,
                           sharpnessIsReliable: reliable,
                           chat: chat)
    }
}
