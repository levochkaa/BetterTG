// PhotoHorizonDetector.swift

import CoreML
import ImageIO
import UIKit
import Vision

// MARK: - PhotoHorizonDetector

/// The straightening TGPhotoCropController offers as AUTO (`_autoRotationAngle`). Telegram reads it from the
/// phone's tilt when its own camera took the photo (PGCameraShotMetadata's `deviceAngle`); this editor opens library
/// photos, so Vision's horizon stands in for the tilt. As in `relativeDeviceAngleFromAngle:orientation:`, a tilt of
/// 45° or more offers nothing.
enum PhotoHorizonDetector {
    /// The clockwise turn in radians that levels the horizon of the upright `image`, or nil without one.
    static func straighteningAngle(for image: UIImage) -> CGFloat? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectHorizonRequest()
        #if targetEnvironment(simulator)
            // The Simulator runs Vision's models only on the CPU.
            if let devices = try? request.supportedComputeStageDevices[.main] {
                for case .cpu(let device) in devices {
                    request.setComputeDevice(.cpu(device), for: .main)
                    break
                }
            }
        #endif
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(of: image), options: [:])
        do {
            try handler.perform([request])
        } catch {
            log("Could not find the photo's horizon: \(error)")
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        // Vision gives the counterclockwise turn with y up that levels the horizon, which is clockwise on screen.
        let angle = -CGFloat(observation.angle)
        guard angle.isFinite, abs(angle) < PhotoCropAdjustments.maximumRotation else { return nil }
        return angle
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
