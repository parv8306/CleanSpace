import CryptoKit
import Foundation

enum VaultError: LocalizedError {
    case keyUnavailable
    case corrupted
    case unsupportedItem
    case notFound

    var errorDescription: String? {
        switch self {
        case .keyUnavailable: "The vault key isn't available. Unlock your iPhone and try again."
        case .corrupted: "This item couldn't be decrypted."
        case .unsupportedItem: "This item can't be added to the vault."
        case .notFound: "This item is no longer in the vault."
        }
    }
}

/// Chunked AES-GCM so large videos never have to fit in memory.
///
/// Format: "TWV1" magic, then repeated [UInt32 big-endian length][AES-GCM combined box].
/// Each chunk authenticates its own index, so chunks can't be reordered or dropped unnoticed.
enum VaultCrypto {
    static let magic = Data("TWV1".utf8)
    static let chunkSize = 1 << 20

    static func encrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        var output = magic
        var index: UInt64 = 0
        var offset = 0
        repeat {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            output.append(try sealChunk(chunk, index: index, key: key))
            index += 1
            offset = end
        } while offset < data.count
        return output
    }

    static func decrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        guard data.count >= magic.count, data.prefix(magic.count) == magic else { throw VaultError.corrupted }
        var output = Data()
        var cursor = data.startIndex + magic.count
        var index: UInt64 = 0
        while cursor < data.endIndex {
            guard data.endIndex - cursor >= 4 else { throw VaultError.corrupted }
            let length = Int(readLength(data[cursor..<(cursor + 4)]))
            cursor += 4
            guard length > 0, data.endIndex - cursor >= length else { throw VaultError.corrupted }
            output.append(try openChunk(data[cursor..<(cursor + length)], index: index, key: key))
            cursor += length
            index += 1
        }
        return output
    }

    static func encryptFile(from source: URL, to destination: URL, key: SymmetricKey) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.write(contentsOf: magic)
        var index: UInt64 = 0
        var wroteChunk = false
        while true {
            let chunk: Data = try autoreleasepool { try input.read(upToCount: chunkSize) ?? Data() }
            if chunk.isEmpty && wroteChunk { break }
            try output.write(contentsOf: try sealChunk(chunk, index: index, key: key))
            wroteChunk = true
            index += 1
            if chunk.count < chunkSize { break }
        }
    }

    static func decryptFile(from source: URL, to destination: URL, key: SymmetricKey) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try input.read(upToCount: magic.count) == magic else { throw VaultError.corrupted }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var index: UInt64 = 0
        while let header = try input.read(upToCount: 4), !header.isEmpty {
            guard header.count == 4 else { throw VaultError.corrupted }
            let length = Int(readLength(header))
            try autoreleasepool {
                guard let box = try input.read(upToCount: length), box.count == length else { throw VaultError.corrupted }
                try output.write(contentsOf: try openChunk(box, index: index, key: key))
            }
            index += 1
        }
    }

    private static func sealChunk(_ chunk: Data, index: UInt64, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(chunk, using: key, authenticating: indexData(index))
        guard let combined = sealed.combined else { throw VaultError.corrupted }
        var length = UInt32(combined.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(combined)
        return framed
    }

    private static func openChunk<D: DataProtocol>(_ bytes: D, index: UInt64, key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes))
            return try AES.GCM.open(box, using: key, authenticating: indexData(index))
        } catch {
            throw VaultError.corrupted
        }
    }

    private static func indexData(_ index: UInt64) -> Data {
        withUnsafeBytes(of: index.bigEndian) { Data($0) }
    }

    private static func readLength<D: DataProtocol>(_ bytes: D) -> UInt32 {
        bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
