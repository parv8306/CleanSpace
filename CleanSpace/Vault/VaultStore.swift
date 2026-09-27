import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import Security
import UIKit
import UniformTypeIdentifiers

struct VaultItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case photo, video }

    let id: UUID
    let kind: Kind
    let originalDate: Date?
    let addedAt: Date
    let byteCount: Int64
    let fileExtension: String
    let duration: Double
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Encrypted on-disk storage for the private vault.
///
/// Layout (Application Support/Vault, excluded from backups, Complete file protection):
///   index.bin        encrypted JSON list of VaultItem
///   <id>.item        encrypted original
///   <id>.thumb       encrypted JPEG thumbnail
actor VaultStore {
    static let shared = VaultStore()

    private static let keyAccount = "masterKey"
    private var cachedKey: SymmetricKey?
    private var cachedIndex: [VaultItem]?

    // MARK: Paths

    private var directory: URL {
        get throws {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            var dir = base.appendingPathComponent("Vault", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                        attributes: [.protectionKey: FileProtectionType.complete])
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try dir.setResourceValues(values)
            }
            return dir
        }
    }

    private var playbackDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VaultPlayback", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    private func itemURL(_ id: UUID) throws -> URL { try directory.appendingPathComponent("\(id.uuidString).item") }
    private func thumbURL(_ id: UUID) throws -> URL { try directory.appendingPathComponent("\(id.uuidString).thumb") }
    private func indexURL() throws -> URL { try directory.appendingPathComponent("index.bin") }

    // MARK: Key

    private func key() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        if let data = Keychain.data(for: Self.keyAccount), data.count == 32 {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard Keychain.set(data, for: Self.keyAccount) else { throw VaultError.keyUnavailable }
        cachedKey = key
        return key
    }

    // MARK: Index

    func items() throws -> [VaultItem] {
        if let cachedIndex { return cachedIndex }
        let url = try indexURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedIndex = []
            return []
        }
        let plain = try VaultCrypto.decrypt(Data(contentsOf: url), key: key())
        let decoder = JSONDecoder()
        let list = try decoder.decode([VaultItem].self, from: plain)
        cachedIndex = list
        return list
    }

    private func saveIndex(_ list: [VaultItem]) throws {
        let plain = try JSONEncoder().encode(list)
        let sealed = try VaultCrypto.encrypt(plain, key: key())
        try sealed.write(to: indexURL(), options: [.atomic, .completeFileProtection])
        cachedIndex = list
    }

    // MARK: Adding

    func addPhoto(data: Data, fileExtension: String, originalDate: Date?) throws -> VaultItem {
        let id = UUID()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw VaultError.unsupportedItem }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let thumb = Self.thumbnailJPEG(from: source)

        let vaultKey = try key()
        try VaultCrypto.encrypt(data, key: vaultKey).write(to: itemURL(id), options: [.atomic, .completeFileProtection])
        if let thumb {
            try VaultCrypto.encrypt(thumb, key: vaultKey).write(to: thumbURL(id), options: [.atomic, .completeFileProtection])
        }
        let item = VaultItem(id: id, kind: .photo, originalDate: originalDate, addedAt: Date(),
                             byteCount: Int64(data.count), fileExtension: fileExtension,
                             duration: 0, pixelWidth: width, pixelHeight: height)
        try saveIndex(try items() + [item])
        return item
    }

    /// Encrypts the video at `url` (streaming) and removes the plaintext copy.
    func addVideo(from url: URL, originalDate: Date?) async throws -> VaultItem {
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        let asset = AVURLAsset(url: url)
        let info = await Self.videoInfo(asset)
        let duration = info.duration
        let size = info.size
        let thumb = await Self.videoThumbnail(asset, duration: duration)

        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let vaultKey = try key()
        try VaultCrypto.encryptFile(from: url, to: itemURL(id), key: vaultKey)
        if let thumb {
            try VaultCrypto.encrypt(thumb, key: vaultKey).write(to: thumbURL(id), options: [.atomic, .completeFileProtection])
        }
        let item = VaultItem(id: id, kind: .video, originalDate: originalDate, addedAt: Date(),
                             byteCount: bytes, fileExtension: url.pathExtension.isEmpty ? "mov" : url.pathExtension,
                             duration: duration.isFinite ? duration : 0,
                             pixelWidth: Int(size.width), pixelHeight: Int(size.height))
        try saveIndex(try items() + [item])
        return item
    }

    // MARK: Reading

    func thumbnail(for id: UUID) -> Data? {
        do {
            let sealed = try Data(contentsOf: thumbURL(id))
            return try VaultCrypto.decrypt(sealed, key: key())
        } catch {
            return nil
        }
    }

    func photoData(for item: VaultItem) throws -> Data {
        try VaultCrypto.decrypt(Data(contentsOf: itemURL(item.id)), key: key())
    }

    /// Decrypts to a temporary, fully protected file for playback or export. Delete it when done.
    func decryptedFile(for item: VaultItem) throws -> URL {
        let destination = playbackDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(item.fileExtension)
        try VaultCrypto.decryptFile(from: itemURL(item.id), to: destination, key: key())
        return destination
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: playbackDirectory)
    }

    // MARK: Removing

    func delete(_ ids: Set<UUID>) throws {
        for id in ids {
            try? FileManager.default.removeItem(at: itemURL(id))
            try? FileManager.default.removeItem(at: thumbURL(id))
        }
        try saveIndex(try items().filter { !ids.contains($0.id) })
    }

    /// Permanently removes every vault file and the vault key.
    func eraseAll() {
        do { try FileManager.default.removeItem(at: directory) } catch {}
        removeTemporaryFiles()
        Keychain.delete(Self.keyAccount)
        cachedKey = nil
        cachedIndex = nil
    }

    /// Drops decrypted state held in memory (called when the vault locks).
    func forgetCachedState() {
        cachedIndex = nil
        removeTemporaryFiles()
    }

    // MARK: Helpers

    private static func videoInfo(_ asset: AVURLAsset) async -> (duration: Double, size: CGSize) {
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard let track = tracks.first else { return (duration, .zero) }
        let natural = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        return (duration, CGSize(width: abs(rect.width), height: abs(rect.height)))
    }

    private static func videoThumbnail(_ asset: AVURLAsset, duration: Double) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        let time = CMTime(seconds: min(0.5, max(duration / 2, 0)), preferredTimescale: 600)
        do {
            let frame = try await generator.image(at: time)
            return UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.8)
        } catch {
            return nil
        }
    }

    private static func thumbnailJPEG(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
    }
}
