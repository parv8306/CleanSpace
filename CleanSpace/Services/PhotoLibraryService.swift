import Foundation
import Photos

struct MediaDeletionOutcome: Sendable {
    let deleted: Set<String>
    let userCancelled: Bool
    let errorMessage: String?
}

enum PhotoLibraryService {
    static func fetchScreenshots() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                        Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    static func fetchVideos() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .video, options: options)
    }

    /// Every photo the current authorization allows, including every frame of a burst
    /// (by default PhotoKit returns only a burst's key photo, hiding the rest from the scan).
    static func fetchImages() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    static func makeItem(from asset: PHAsset, fileSize: Int64 = 0, sharpness: Double = 0) -> MediaItem {
        MediaItem(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isFavorite: asset.isFavorite,
            fileSize: fileSize,
            sharpness: sharpness
        )
    }

    /// Deletes through PhotoKit, which shows iOS's own confirmation. Afterwards we re-query the
    /// library so the result reflects what was *actually* removed, never what we hoped was removed.
    static func deleteAssets(ids: [String]) async -> MediaDeletionOutcome {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var existingBefore = Set<String>()
        fetch.enumerateObjects { asset, _, _ in existingBefore.insert(asset.localIdentifier) }
        guard !existingBefore.isEmpty else {
            return MediaDeletionOutcome(deleted: [], userCancelled: false,
                                        errorMessage: "These items are no longer in your library.")
        }

        var cancelled = false
        var message: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetch)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == "PHPhotosErrorDomain" && nsError.code == 3072 {
                cancelled = true   // PHPhotosError.userCancelled — user tapped "Don't Allow"
            } else {
                message = "Photos couldn't remove some items. They may be shared, synced from another device, or in use."
            }
        }

        let remaining = PHAsset.fetchAssets(withLocalIdentifiers: Array(existingBefore), options: nil)
        var remainingIDs = Set<String>()
        remaining.enumerateObjects { asset, _, _ in remainingIDs.insert(asset.localIdentifier) }
        return MediaDeletionOutcome(deleted: existingBefore.subtracting(remainingIDs),
                                    userCancelled: cancelled, errorMessage: message)
    }
}
