// PhotoHistogram.swift

import CoreGraphics
import Foundation

/// PGPhotoHistogram as PGPhotoHistogramGenerator counts it from the editor's output: 256 bins of the luminance and of
/// each color, each over its largest bin after the first, with the first bin left at zero (PGPhotoHistogramBins).
struct PhotoHistogram {
    let luminance: [CGFloat]
    let red: [CGFloat]
    let green: [CGFloat]
    let blue: [CGFloat]

    /// Counts the picture's pixels. Call off the main thread.
    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let isDrawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard isDrawn else { return nil }
        // The luminance's bins, then red's, green's and blue's.
        var bins = [Int](repeating: 0, count: 256 * 4)
        pixels.withUnsafeBufferPointer { bytes in
            bins.withUnsafeMutableBufferPointer { counts in
                for index in stride(from: 0, to: bytes.count, by: 4) {
                    let red = Int(bytes[index])
                    let green = Int(bytes[index + 1])
                    let blue = Int(bytes[index + 2])
                    // The generator truncates the luma to a whole step.
                    let luma = Int(Double(red) * 0.3 + Double(green) * 0.59 + Double(blue) * 0.11)
                    counts[min(255, luma)] += 1
                    counts[256 + red] += 1
                    counts[512 + green] += 1
                    counts[768 + blue] += 1
                }
            }
        }
        self.luminance = Self.normalized(bins[0..<256])
        self.red = Self.normalized(bins[256..<512])
        self.green = Self.normalized(bins[512..<768])
        self.blue = Self.normalized(bins[768..<1024])
    }

    private static func normalized(_ bins: ArraySlice<Int>) -> [CGFloat] {
        let maximum = max(1, bins.dropFirst().max() ?? 1)
        return bins.enumerated().map { offset, count in
            offset == 0 ? 0 : CGFloat(count) / CGFloat(maximum)
        }
    }

    subscript(channel: PhotoCurvesChannel) -> [CGFloat] {
        switch channel {
        case .luminance: luminance
        case .red: red
        case .green: green
        case .blue: blue
        }
    }
}
