// PhotoCropAdjustments.swift

import ImageIO
import UIKit

// MARK: - PhotoCropOrientation

/// PGPhotoEditor's `cropOrientation`: the crop's quarter turns. Rotate turns it counterclockwise
/// (`TGNextCCWOrientationForOrientation`).
enum PhotoCropOrientation: Int {
    case up
    case left
    case down
    case right

    /// `TGRotationForOrientation`.
    var angle: CGFloat {
        switch self {
        case .up: 0
        case .left: -.pi / 2
        case .down: -.pi
        case .right: .pi / 2
        }
    }

    /// `TGOrientationIsSideward`.
    var isSideward: Bool {
        self == .left || self == .right
    }

    var nextCounterclockwise: PhotoCropOrientation {
        switch self {
        case .up: .left
        case .left: .down
        case .down: .right
        case .right: .up
        }
    }
}

// MARK: - PhotoCropAdjustments

/// A photo's crop as TGMediaEditingContext keeps it (PGPhotoEditorValues): the crop rectangle inside the bounding box
/// of the straightened photo, in `originalSize` units, the quarter turns, the straightening angle, the mirroring and
/// the locked aspect ratio.
struct PhotoCropAdjustments: Equatable {
    /// TGPhotoCropScrollView's `maximumZoomScale`.
    static let maximumZoomScale: CGFloat = 10
    /// `TGPhotoCropRotationViewMaximumAngle`.
    static let maximumRotation: CGFloat = .pi / 4

    /// The upright photo's size the crop is measured in.
    let originalSize: CGSize
    var cropRect: CGRect
    var orientation = PhotoCropOrientation.up
    /// The straightening angle in radians, clockwise.
    var rotation: CGFloat = 0
    var isMirrored = false
    /// The crop's height over its width while a ratio is locked; zero otherwise.
    var lockedAspectRatio: CGFloat = 0

    /// PGPhotoEditor's `hasDefaultCropping`: the whole photo, upright, straight and unmirrored.
    var hasDefaultCropping: Bool {
        let full = CGRect(origin: .zero, size: originalSize)
        let isFull = abs(cropRect.minX - full.minX) < 1 && abs(cropRect.minY - full.minY) < 1
            && abs(cropRect.width - full.width) < 2 && abs(cropRect.height - full.height) < 2
        return isFull && orientation == .up && abs(rotation) <= .ulpOfOne && !isMirrored
    }

    /// The bounding box of the straightened photo (`TGRotatedContentSize`), which `cropRect` lives in.
    var rotatedContentSize: CGSize {
        Self.boundingSize(of: originalSize, rotation: rotation)
    }

    /// The crop as it comes out, with its quarter turns.
    var croppedSize: CGSize {
        orientation.isSideward ? CGSize(width: cropRect.height, height: cropRect.width) : cropRect.size
    }

    init(originalSize: CGSize) {
        self.originalSize = originalSize
        self.cropRect = CGRect(origin: .zero, size: originalSize)
    }

    static func boundingSize(of size: CGSize, rotation: CGFloat) -> CGSize {
        let cosine = abs(cos(rotation))
        let sine = abs(sin(rotation))
        return CGSize(
            width: size.width * cosine + size.height * sine,
            height: size.width * sine + size.height * cosine,
        )
    }

    /// `TGScaleToSize`: the size fitted to the width of `bounds`, or to its height when it is too tall.
    static func scaleToSize(_ size: CGSize, _ bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        var result = CGSize(width: bounds.width, height: (bounds.width * size.height / size.width).rounded(.down))
        if result.height > bounds.height {
            result.height = bounds.height
            result.width = (bounds.height * size.width / size.height).rounded(.down)
        }
        return result
    }

    /// `TGRubberBandDistance`.
    static func rubberBandDistance(_ offset: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return 0 }
        let constant: CGFloat = 0.55
        let result = constant * abs(offset) * dimension / (dimension + constant * abs(offset))
        return offset < 0 ? -result : result
    }

    /// The same crop measured in another size of the photo, such as a newly loaded copy for the editor.
    func scaled(to size: CGSize) -> PhotoCropAdjustments {
        guard originalSize.width > 0, originalSize.height > 0, size != originalSize else { return self }
        let factor = size.width / originalSize.width
        var result = PhotoCropAdjustments(originalSize: size)
        result.cropRect = CGRect(
            x: cropRect.minX * factor,
            y: cropRect.minY * factor,
            width: cropRect.width * factor,
            height: cropRect.height * factor,
        )
        result.orientation = orientation
        result.rotation = rotation
        result.isMirrored = isMirrored
        result.lockedAspectRatio = lockedAspectRatio
        return result
    }

    // MARK: Geometry

    /// How much `size` can grow while the straightened photo still covers it.
    func coverFactor(for size: CGSize) -> CGFloat {
        let box = Self.boundingSize(of: size, rotation: -rotation)
        guard box.width > 0, box.height > 0 else { return 1 }
        return min(originalSize.width / box.width, originalSize.height / box.height)
    }

    /// TGPhotoCropScrollView's `fitContentInsideBoundsAllowScale`: the rectangle moved, and with `allowsScale`
    /// shrunk about its center, until the straightened photo covers it.
    func fitted(_ rect: CGRect, allowsScale: Bool) -> CGRect {
        var size = rect.size
        if allowsScale {
            let factor = min(1, coverFactor(for: size))
            size = CGSize(width: size.width * factor, height: size.height * factor)
        }
        let box = Self.boundingSize(of: size, rotation: -rotation)
        let content = rotatedContentSize
        let middle = CGPoint(x: content.width / 2, y: content.height / 2)
        var local = CGPoint(x: rect.midX - middle.x, y: rect.midY - middle.y)
            .applying(CGAffineTransform(rotationAngle: -rotation))
        let limitX = max(0, (originalSize.width - box.width) / 2)
        let limitY = max(0, (originalSize.height - box.height) / 2)
        local.x = min(max(local.x, -limitX), limitX)
        local.y = min(max(local.y, -limitY), limitY)
        let offset = local.applying(CGAffineTransform(rotationAngle: rotation))
        return CGRect(
            x: middle.x + offset.x - size.width / 2,
            y: middle.y + offset.y - size.height / 2,
            width: size.width,
            height: size.height,
        )
    }

    /// TGPhotoCropView's `performConfirmAnimated`: a crop smaller than the photo over the maximum zoom on both sides
    /// grows back to that size.
    func constrainedToMinimumSize(_ rect: CGRect) -> CGRect {
        let minimum = CGSize(
            width: originalSize.width / Self.maximumZoomScale,
            height: originalSize.height / Self.maximumZoomScale,
        )
        guard rect.width < minimum.width, rect.height < minimum.height, rect.width > 0, rect.height > 0
        else { return rect }
        var result = rect
        if rect.width > rect.height {
            result.size.width = minimum.width
            result.size.height = rect.height * minimum.width / rect.width
        } else {
            result.size.height = minimum.height
            result.size.width = rect.width * minimum.height / rect.height
        }
        let content = rotatedContentSize
        if result.maxX > content.width { result.origin.x = content.width - result.width }
        if result.maxY > content.height { result.origin.y = content.height - result.height }
        return result
    }

    // MARK: Rendering

    /// `TGPhotoEditorCrop`: the crop of an upright `image` of the photo, at any resolution, drawn opaque on black and
    /// fitted into `maximumSide` pixels of a photo whose full upright size is `sourcePixelSize`.
    func render(_ image: UIImage, sourcePixelSize: CGSize, maximumSide: CGFloat) -> UIImage? {
        let crop = cropRect.standardized
        guard crop.width > 0, crop.height > 0, originalSize.width > 0, originalSize.height > 0,
              sourcePixelSize.width > 0, maximumSide > 0
        else { return nil }
        let pixelsPerUnit = sourcePixelSize.width / originalSize.width
        let cropPixels = CGSize(width: crop.width * pixelsPerUnit, height: crop.height * pixelsPerUnit)
        // `TGFitSize`: only ever smaller.
        let fit = min(1, maximumSide / max(cropPixels.width, cropPixels.height))
        var outputSize = CGSize(
            width: max(1, (cropPixels.width * fit).rounded(.down)),
            height: max(1, (cropPixels.height * fit).rounded(.down)),
        )
        if orientation.isSideward {
            outputSize = CGSize(width: outputSize.height, height: outputSize.width)
        }
        let scale = pixelsPerUnit * fit
        let content = rotatedContentSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            let canvas = context.cgContext
            canvas.interpolationQuality = .high
            canvas.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
            canvas.rotate(by: orientation.angle)
            canvas.scaleBy(x: scale, y: scale)
            canvas.translateBy(x: content.width / 2 - crop.midX, y: content.height / 2 - crop.midY)
            canvas.rotate(by: rotation)
            if isMirrored { canvas.scaleBy(x: -1, y: 1) }
            image.draw(in: CGRect(
                x: -originalSize.width / 2,
                y: -originalSize.height / 2,
                width: originalSize.width,
                height: originalSize.height,
            ))
        }
    }
}

// MARK: - Cropped photo files

/// Writes encoded photo data cropped as `adjustments` say, as the JPEG Telegram sends: `TGPhotoEditorCrop` fitted to
/// the send size. ImageIO decodes the photo only as large as the crop needs. Call off the main thread.
func writeImage(data: Data, cropping adjustments: PhotoCropAdjustments, maximumSide: Int) -> SelectedImage? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
          width > 0, height > 0
    else {
        log("Error reading edited image data")
        return nil
    }
    // EXIF orientations 5 to 8 turn the photo sideways.
    let exifOrientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let uprightSize = exifOrientation >= 5
        ? CGSize(width: height, height: width)
        : CGSize(width: width, height: height)
    let crop = adjustments.cropRect.standardized
    guard crop.width > 0, crop.height > 0, adjustments.originalSize.width > 0 else { return nil }
    let pixelsPerUnit = uprightSize.width / adjustments.originalSize.width
    let cropSide = max(crop.width, crop.height) * pixelsPerUnit
    let decodeFactor = min(1, CGFloat(maximumSide) / cropSide)
    let decodeSide = max(1, Int((max(uprightSize.width, uprightSize.height) * decodeFactor).rounded(.up)))
    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: decodeSide,
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
          let rendered = adjustments.render(
              UIImage(cgImage: decoded),
              sourcePixelSize: uprightSize,
              maximumSide: CGFloat(maximumSide),
          )
    else {
        log("Error cropping edited image")
        return nil
    }
    return writeImage(rendered, maximumSide: maximumSide)
}
