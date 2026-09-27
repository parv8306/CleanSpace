import Foundation

/// Remembers each photo's fingerprint so later scans skip photos that haven't changed.
///
/// Entries are keyed by the photo's identifier and checked against its modification date, so an
/// edited photo is analyzed again. Stored in Caches (never backed up; iOS may purge it, and
/// "Clear temporary files" removes it). Holds only hashes, sharpness numbers and the chat-app
/// guess, never images or file names.
final class FingerprintCache: @unchecked Sendable {
    static let shared = FingerprintCache()

    struct Entry: Codable, Sendable {
        let modified: Double
        let hash: Int64
        let sharpness: Double
        let contrast: Double
        let reliable: Bool
        let chat: String?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var loaded = false
    private var dirty = false

    private var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("photo-fingerprints-v2.plist")
    }

    func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? PropertyListDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    func entry(for id: String, modified: Date?) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[id], entry.modified == (modified?.timeIntervalSince1970 ?? 0) else { return nil }
        return entry
    }

    func store(_ entry: Entry, for id: String) {
        lock.lock()
        entries[id] = entry
        dirty = true
        lock.unlock()
    }

    /// Forgets photos that are no longer in the library.
    func prune(keeping ids: Set<String>) {
        lock.lock()
        let before = entries.count
        entries = entries.filter { ids.contains($0.key) }
        if entries.count != before { dirty = true }
        lock.unlock()
    }

    func save() {
        lock.lock()
        guard dirty, let url = fileURL else { lock.unlock(); return }
        let snapshot = entries
        dirty = false
        lock.unlock()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func clear() {
        lock.lock()
        entries = [:]
        dirty = false
        lock.unlock()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }
}
