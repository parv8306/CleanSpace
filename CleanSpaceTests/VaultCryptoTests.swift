import CryptoKit
import XCTest
@testable import CleanSpace

final class VaultCryptoTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)

    func testRoundTripAcrossChunkBoundaries() throws {
        for size in [0, 1, 1000, VaultCrypto.chunkSize, VaultCrypto.chunkSize + 7, VaultCrypto.chunkSize * 2 + 3] {
            let data = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31) })
            let sealed = try VaultCrypto.encrypt(data, key: key)
            XCTAssertNotEqual(sealed, data)
            XCTAssertEqual(try VaultCrypto.decrypt(sealed, key: key), data, "size \(size)")
        }
    }

    func testFileRoundTripMatchesInMemoryFormat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appendingPathComponent("plain.bin")
        let sealed = dir.appendingPathComponent("sealed.bin")
        let back = dir.appendingPathComponent("back.bin")
        let data = Data((0..<(VaultCrypto.chunkSize + 12_345)).map { UInt8(truncatingIfNeeded: $0) })
        try data.write(to: plain)

        try VaultCrypto.encryptFile(from: plain, to: sealed, key: key)
        XCTAssertEqual(try VaultCrypto.decrypt(Data(contentsOf: sealed), key: key), data)
        try VaultCrypto.decryptFile(from: sealed, to: back, key: key)
        XCTAssertEqual(try Data(contentsOf: back), data)
    }

    func testWrongKeyFails() throws {
        let sealed = try VaultCrypto.encrypt(Data("secret".utf8), key: key)
        XCTAssertThrowsError(try VaultCrypto.decrypt(sealed, key: SymmetricKey(size: .bits256)))
    }

    func testTamperingIsDetected() throws {
        var sealed = try VaultCrypto.encrypt(Data("secret photo".utf8), key: key)
        sealed[sealed.count - 1] ^= 0xFF
        XCTAssertThrowsError(try VaultCrypto.decrypt(sealed, key: key))
    }

    func testReorderedChunksAreRejected() throws {
        let data = Data(repeating: 1, count: VaultCrypto.chunkSize) + Data(repeating: 2, count: 10)
        let sealed = try VaultCrypto.encrypt(data, key: key)
        // Split into magic + framed chunks and swap the two chunks.
        var cursor = VaultCrypto.magic.count
        var chunks: [Data] = []
        while cursor < sealed.count {
            let length = sealed[cursor..<(cursor + 4)].reduce(0) { ($0 << 8) | Int($1) }
            chunks.append(sealed[cursor..<(cursor + 4 + length)])
            cursor += 4 + length
        }
        XCTAssertEqual(chunks.count, 2)
        let swapped = VaultCrypto.magic + chunks[1] + chunks[0]
        XCTAssertThrowsError(try VaultCrypto.decrypt(swapped, key: key))
    }

    func testMissingMagicIsRejected() {
        XCTAssertThrowsError(try VaultCrypto.decrypt(Data("nope".utf8), key: key))
    }
}

final class PasscodeHashTests: XCTestCase {
    /// Published PBKDF2-HMAC-SHA256 test vectors (password "password", salt "salt", 32 bytes).
    func testPBKDF2Vectors() {
        let password = Data("password".utf8)
        let salt = Data("salt".utf8)
        XCTAssertEqual(hex(PBKDF2.sha256(password: password, salt: salt, rounds: 1)),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        XCTAssertEqual(hex(PBKDF2.sha256(password: password, salt: salt, rounds: 2)),
                       "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        XCTAssertEqual(hex(PBKDF2.sha256(password: password, salt: salt, rounds: 4096)),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    func testLongerOutputUsesMultipleBlocks() {
        let out = PBKDF2.sha256(password: Data("pw".utf8), salt: Data("s".utf8), rounds: 3, length: 40)
        XCTAssertEqual(out.count, 40)
        XCTAssertEqual(out.prefix(32), PBKDF2.sha256(password: Data("pw".utf8), salt: Data("s".utf8), rounds: 3))
    }

    func testConstantTimeEqual() {
        XCTAssertTrue(PasscodeStore.constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 3])))
        XCTAssertFalse(PasscodeStore.constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 4])))
        XCTAssertFalse(PasscodeStore.constantTimeEqual(Data([1, 2]), Data([1, 2, 3])))
    }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
