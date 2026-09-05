// LivePhotoResources.swift

import AVFoundation
import ImageIO
import Photos
import UniformTypeIdentifiers

struct LivePhotoResources {
    let directory: URL
    let photo: URL
    let video: URL

    /// Match Telegram's SaveToCameraRoll pairing: Apple's maker-note key 17
    /// and QuickTime content identifier tie the JPEG and MOV to one Live Photo.
    static func prepare(photo: URL, video: URL) async throws -> Self {
        let identifier = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "bettertg-live-export-\(identifier)",
            isDirectory: true,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = Self(
            directory: directory,
            photo: directory.appendingPathComponent("Live Photo.jpg"),
            video: directory.appendingPathComponent("Live Photo.mov"),
        )
        do {
            try await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let destination = CGImageDestinationCreateWithURL(
                          result.photo as CFURL,
                          UTType.jpeg.identifier as CFString,
                          1,
                          nil,
                      )
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                var metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
                var maker = metadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
                maker["17"] = identifier
                metadata[kCGImagePropertyMakerAppleDictionary as String] = maker
                CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            }.value
            try Task.checkCancellation()
            let asset = AVURLAsset(url: video)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let contentIdentifier = AVMutableMetadataItem()
            contentIdentifier.keySpace = .quickTimeMetadata
            contentIdentifier.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
            contentIdentifier.value = identifier as NSString
            let stillImageTime = AVMutableMetadataItem()
            stillImageTime.keySpace = .quickTimeMetadata
            stillImageTime.key = "com.apple.quicktime.still-image-time" as NSString
            stillImageTime.value = NSNumber(value: 0)
            stillImageTime.dataType = "com.apple.metadata.datatype.int8"
            exporter.metadata = [contentIdentifier, stillImageTime]
            exporter.shouldOptimizeForNetworkUse = true
            try await exporter.export(to: result.video, as: .mov)
            try Task.checkCancellation()
            return result
        } catch {
            result.cleanup()
            throw error
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    func save(creationDate: Date?) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photo, options: nil)
            request.addResource(with: .pairedVideo, fileURL: video, options: nil)
            request.creationDate = creationDate
        }
    }
}
