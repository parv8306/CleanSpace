import CoreTransferable
import Foundation
import Observation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A picked video, copied out of the picker's temporary location.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

@Observable
@MainActor
final class VaultModel {
    private(set) var items: [VaultItem] = []
    private(set) var isLoading = false
    private(set) var importProgress: (done: Int, total: Int)?
    var errorMessage: String?

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.byteCount } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await VaultStore.shared.items().sorted { $0.addedAt > $1.addedAt }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The vault couldn't be opened."
        }
    }

    /// Encrypts the picked items into the vault. Returns the Photos identifiers of the ones that
    /// were added, so the caller can offer to remove the originals.
    func importItems(_ picked: [PhotosPickerItem]) async -> [String] {
        guard !picked.isEmpty else { return [] }
        importProgress = (0, picked.count)
        var imported: [String] = []
        var failures = 0
        for (index, item) in picked.enumerated() {
            let date = item.itemIdentifier.flatMap(Self.creationDate(for:))
            do {
                let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                if isMovie {
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                        throw VaultError.unsupportedItem
                    }
                    _ = try await VaultStore.shared.addVideo(from: movie.url, originalDate: date)
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw VaultError.unsupportedItem
                    }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    _ = try await VaultStore.shared.addPhoto(data: data, fileExtension: ext, originalDate: date)
                }
                if let id = item.itemIdentifier { imported.append(id) }
            } catch {
                failures += 1
            }
            importProgress = (index + 1, picked.count)
        }
        importProgress = nil
        if failures > 0 {
            errorMessage = "\(Format.count(failures, "item")) couldn't be added. Items stored only in iCloud need to be downloaded in Photos first."
        }
        await load()
        return imported
    }

    func delete(_ ids: Set<UUID>) async {
        do {
            try await VaultStore.shared.delete(ids)
            items.removeAll { ids.contains($0.id) }
        } catch {
            errorMessage = "Those items couldn't be removed from the vault."
        }
    }

    /// Saves a decrypted copy back to the Photos library. The vault copy stays until deleted.
    func exportToPhotos(_ item: VaultItem) async -> Bool {
        do {
            switch item.kind {
            case .photo:
                let data = try await VaultStore.shared.photoData(for: item)
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                    request.creationDate = item.originalDate
                }
            case .video:
                let url = try await VaultStore.shared.decryptedFile(for: item)
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    request.addResource(with: .video, fileURL: url, options: options)
                    request.creationDate = item.originalDate
                }
            }
            return true
        } catch {
            errorMessage = "CleanSpace couldn't save this item to Photos. Check that photo access is allowed."
            return false
        }
    }

    /// Clears decrypted data from memory when the vault locks.
    func clear() {
        items = []
        importProgress = nil
        Task { await VaultStore.shared.forgetCachedState() }
    }

    private static func creationDate(for localIdentifier: String) -> Date? {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject?.creationDate
    }
}
