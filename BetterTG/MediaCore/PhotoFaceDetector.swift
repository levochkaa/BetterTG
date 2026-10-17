// PhotoFaceDetector.swift

import CoreImage
import UIKit

/// TGPaintFaceDetector's `detectFacesInImage:`: Core Image's accurate face detector on the editor's photo, skipping
/// faces under 17.5% of the picture. A face counts once both its eyes are found, as `_paintFaceForFaceFeature`
/// requires.
enum PhotoFaceDetector {
    /// Call off the main thread.
    static func hasFaces(in image: UIImage) -> Bool {
        guard let cgImage = image.cgImage,
              let detector = CIDetector(
                  ofType: CIDetectorTypeFace,
                  context: nil,
                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorMinFeatureSize: 0.175],
              )
        else { return false }
        let picture = CIImage(cgImage: cgImage)
            .oriented(forExifOrientation: exifOrientation(of: image.imageOrientation))
        return detector.features(in: picture).contains { feature in
            guard let face = feature as? CIFaceFeature else { return false }
            return face.hasLeftEyePosition && face.hasRightEyePosition
        }
    }

    /// `tiffOrientationFromImageOrientation:`.
    private static func exifOrientation(of orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up: 1
        case .upMirrored: 2
        case .down: 3
        case .downMirrored: 4
        case .leftMirrored: 5
        case .right: 6
        case .rightMirrored: 7
        case .left: 8
        @unknown default: 1
        }
    }
}
