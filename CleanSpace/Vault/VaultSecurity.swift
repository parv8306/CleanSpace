import CryptoKit
import Foundation
import Security

/// Minimal Keychain wrapper. Items are "when unlocked, this device only": they never sync to iCloud
/// and are not restored onto another device from a backup.
enum Keychain {
    static let service = "com.cleanspace.vault"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func data(for account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func set(_ data: Data, for account: String) -> Bool {
        delete(account)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}

/// PBKDF2-HMAC-SHA256 built on CryptoKit (RFC 8018). Used to store the vault passcode as a salted,
/// slow hash rather than the passcode itself.
enum PBKDF2 {
    static func sha256(password: Data, salt: Data, rounds: Int, length: Int = 32) -> Data {
        precondition(rounds >= 1 && length > 0)
        let key = SymmetricKey(data: password)
        var derived = Data()
        var blockIndex: UInt32 = 1
        while derived.count < length {
            var saltBlock = salt
            withUnsafeBytes(of: blockIndex.bigEndian) { saltBlock.append(contentsOf: $0) }
            var u = Array(HMAC<SHA256>.authenticationCode(for: saltBlock, using: key))
            var t = u
            if rounds > 1 {
                for _ in 1..<rounds {
                    u = Array(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for i in 0..<t.count { t[i] ^= u[i] }
                }
            }
            derived.append(contentsOf: t)
            blockIndex += 1
        }
        return Data(derived.prefix(length))
    }
}

/// Stores and checks the vault passcode.
enum PasscodeStore {
    struct Record: Codable {
        let salt: Data
        let hash: Data
        let rounds: Int
        let length: Int
    }

    static let account = "passcode"
    static let rounds = 60_000
    static let length = 6

    static var hasPasscode: Bool { Keychain.data(for: account) != nil }

    /// Slow on purpose — call off the main thread.
    static func save(_ passcode: String) -> Bool {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return false }
        let hash = PBKDF2.sha256(password: Data(passcode.utf8), salt: salt, rounds: rounds)
        let record = Record(salt: salt, hash: hash, rounds: rounds, length: passcode.count)
        guard let data = try? JSONEncoder().encode(record) else { return false }
        return Keychain.set(data, for: account)
    }

    /// Slow on purpose — call off the main thread.
    static func verify(_ passcode: String) -> Bool {
        guard let data = Keychain.data(for: account),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return false }
        let hash = PBKDF2.sha256(password: Data(passcode.utf8), salt: record.salt, rounds: record.rounds)
        return constantTimeEqual(hash, record.hash)
    }

    static func remove() { Keychain.delete(account) }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}
