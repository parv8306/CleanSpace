import Foundation

/// Pure, platform-independent image math used by the photo scanner. Operates on 8-bit grayscale
/// buffers so it is fast, allocation-light and unit-testable without PhotoKit.
enum PerceptualHash {
    /// Area-averaging downscale (box filter). Deterministic and alias-free, which matters for hashing:
    /// two copies of the same photo must produce the same fingerprint.
    static func areaResize(_ src: [UInt8], width: Int, height: Int, toWidth tw: Int, toHeight th: Int) -> [UInt8] {
        guard tw > 0, th > 0 else { return [] }
        guard width > 0, height > 0, src.count >= width * height else {
            return [UInt8](repeating: 0, count: tw * th)
        }
        var out = [UInt8](repeating: 0, count: tw * th)
        for ty in 0..<th {
            let y0 = ty * height / th
            let y1 = min(max(y0 + 1, (ty + 1) * height / th), height)
            for tx in 0..<tw {
                let x0 = tx * width / tw
                let x1 = min(max(x0 + 1, (tx + 1) * width / tw), width)
                var sum = 0
                for y in y0..<y1 {
                    let row = y * width
                    for x in x0..<x1 { sum += Int(src[row + x]) }
                }
                let n = max((y1 - y0) * (x1 - x0), 1)
                out[ty * tw + tx] = UInt8(sum / n)
            }
        }
        return out
    }

    /// Difference hash: compares horizontally adjacent pixels of a 9×8 grayscale image → 64 bits.
    static func dHash(_ gray9x8: [UInt8]) -> UInt64 {
        guard gray9x8.count >= 72 else { return 0 }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                if gray9x8[y * 9 + x] > gray9x8[y * 9 + x + 1] { hash |= (1 << bit) }
                bit += 1
            }
        }
        return hash
    }

    /// Hamming distance between two 64-bit hashes.
    @inline(__always)
    static func distance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// Variance of the 4-neighbour Laplacian. Low values mean few edges → likely blurry.
    static func laplacianVariance(_ g: [UInt8], width w: Int, height h: Int) -> Double {
        guard w >= 3, h >= 3, g.count >= w * h else { return 0 }
        var sum = 0.0, sumSq = 0.0, n = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let v = Double(Int(g[i - w]) + Int(g[i + w]) + Int(g[i - 1]) + Int(g[i + 1]) - 4 * Int(g[i]))
                sum += v
                sumSq += v * v
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        let mean = sum / n
        return max(sumSq / n - mean * mean, 0)
    }

    /// Global contrast. Used to avoid calling a clear blue sky "blurry".
    static func standardDeviation(_ g: [UInt8]) -> Double {
        guard !g.isEmpty else { return 0 }
        var sum = 0.0, sumSq = 0.0
        for v in g { let d = Double(v); sum += d; sumSq += d * d }
        let n = Double(g.count)
        let mean = sum / n
        return max(sumSq / n - mean * mean, 0).squareRoot()
    }
}
