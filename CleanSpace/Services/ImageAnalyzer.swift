import CoreGraphics
import Foundation

/// Bridges CoreGraphics images into the pure `PerceptualHash` math.
enum ImageAnalyzer {
    struct Analysis: Sendable {
        let hash: UInt64
        let sharpness: Double
        let contrast: Double
    }

    /// Longest side of the working grayscale buffer. Small enough to be fast, large enough that
    /// motion blur is still measurable.
    static let workingSide = 256

    static func analyze(_ image: CGImage) -> Analysis? {
        let w0 = image.width, h0 = image.height
        guard w0 > 0, h0 > 0 else { return nil }
        let scale = min(1.0, Double(workingSide) / Double(max(w0, h0)))
        let w = max(9, Int((Double(w0) * scale).rounded()))
        let h = max(8, Int((Double(h0) * scale).rounded()))
        guard let gray = grayscale(image, width: w, height: h) else { return nil }
        let tiny = PerceptualHash.areaResize(gray, width: w, height: h, toWidth: 9, toHeight: 8)
        return Analysis(
            hash: PerceptualHash.dHash(tiny),
            sharpness: PerceptualHash.laplacianVariance(gray, width: w, height: h),
            contrast: PerceptualHash.standardDeviation(gray)
        )
    }

    static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
