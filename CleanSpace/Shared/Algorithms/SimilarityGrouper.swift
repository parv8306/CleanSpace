import Foundation

struct HashedPhoto: Sendable {
    let hash: UInt64
    let date: Date?
    /// width / height of the original asset; 0 when unknown.
    let aspectRatio: Double
}

/// Groups perceptual hashes without comparing every photo to every other photo.
///
/// 1. Exact: identical hashes are bucketed in a dictionary — O(n).
/// 2. Near-duplicates anywhere in the library: the 64-bit hash is split into 8 bands of 8 bits.
///    By the pigeonhole principle, two hashes within Hamming distance ≤ 7 share at least one band
///    exactly, so we only compare photos that collide in some band (multi-index hashing).
/// 3. Bursts / similar shots: photos taken within `burstWindow` seconds of each other are compared
///    with a looser threshold using a sliding window over the date-sorted list — O(n·k).
/// Matches are merged with union-find; an aspect-ratio guard rejects crops and rotations.
struct SimilarityGrouper: Sendable {
    /// Must stay ≤ 7 for the 8-band index to be exhaustive.
    var nearDuplicateThreshold = 5
    var burstThreshold = 12
    var burstWindow: TimeInterval = 90
    var aspectTolerance = 0.06

    func groups(for photos: [HashedPhoto]) -> [[Int]] {
        let n = photos.count
        guard n > 1 else { return [] }
        var uf = UnionFind(count: n)

        // 1. Identical hashes.
        var byHash: [UInt64: [Int]] = [:]
        for (i, p) in photos.enumerated() { byHash[p.hash, default: []].append(i) }
        var representatives: [Int] = []
        representatives.reserveCapacity(byHash.count)
        for members in byHash.values {
            var localReps: [Int] = []
            for m in members {
                if let rep = localReps.first(where: { aspectCompatible(photos[$0], photos[m]) }) {
                    uf.union(rep, m)
                } else {
                    localReps.append(m)
                }
            }
            representatives.append(contentsOf: localReps)
        }

        // 2. Near-duplicates via banded index over unique representatives.
        let threshold = min(nearDuplicateThreshold, 7)
        for band in 0..<8 {
            let shift = UInt64(band * 8)
            var buckets: [UInt8: [Int]] = [:]
            for r in representatives {
                buckets[UInt8(truncatingIfNeeded: photos[r].hash >> shift), default: []].append(r)
            }
            for bucket in buckets.values where bucket.count > 1 {
                for a in 0..<(bucket.count - 1) {
                    let i = bucket[a]
                    for b in (a + 1)..<bucket.count {
                        let j = bucket[b]
                        if PerceptualHash.distance(photos[i].hash, photos[j].hash) <= threshold,
                           aspectCompatible(photos[i], photos[j]) {
                            uf.union(i, j)
                        }
                    }
                }
            }
        }

        // 3. Bursts: sliding time window.
        let dated: [(index: Int, date: Date)] = photos.enumerated()
            .compactMap { pair in pair.element.date.map { (pair.offset, $0) } }
            .sorted { $0.date < $1.date }
        if dated.count > 1 {
            for a in 0..<(dated.count - 1) {
                let (i, di) = dated[a]
                var b = a + 1
                while b < dated.count, dated[b].date.timeIntervalSince(di) <= burstWindow {
                    let j = dated[b].index
                    if PerceptualHash.distance(photos[i].hash, photos[j].hash) <= burstThreshold,
                       aspectCompatible(photos[i], photos[j]) {
                        uf.union(i, j)
                    }
                    b += 1
                }
            }
        }

        // 4. Collect components with 2+ members.
        var components: [Int: [Int]] = [:]
        for i in 0..<n { components[uf.find(i), default: []].append(i) }
        return components.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }

    func aspectCompatible(_ a: HashedPhoto, _ b: HashedPhoto) -> Bool {
        guard a.aspectRatio > 0, b.aspectRatio > 0 else { return true }
        return abs(a.aspectRatio - b.aspectRatio) / max(a.aspectRatio, b.aspectRatio) <= aspectTolerance
    }
}
