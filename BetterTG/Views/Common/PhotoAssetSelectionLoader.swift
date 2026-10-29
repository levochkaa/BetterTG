// PhotoAssetSelectionLoader.swift

import Photos
import UIKit

/// Reads the attachment sheet's picked library items into composer items in pick order, as
/// `legacyAssetPickerItemGenerator` reads Telegram's `TGMediaAsset`s: a photo's current version scaled to 1280 px, or
/// 2560 px when sent in high quality (`LegacyMediaPickers`' `forceHd`), a Live Photo as its still unless the sheet
/// sends it live, then with its paired motion, and a video as the app's copy of its current file. Items keep the
/// picker's spoiler, timer and video quality, the quality capped at each video's own size, and the editor's crop or
/// trim and mute. Items that can't be read, such as an iCloud original while offline, are left out.
enum PhotoAssetSelectionLoader {
    /// Library reads running at once, so a pick of a hundred items doesn't decode them all together.
    private static let concurrentLoads = 4
    private static let queue = DispatchQueue(label: "BetterTG.PhotoAssetSelectionLoader", qos: .userInitiated)

    static func load(
        _ assets: [PHAsset],
        cropAdjustments: [String: PhotoCropAdjustments] = [:],
        videoEdits: [String: VideoEditAdjustments] = [:],
        livePhotoAssetIDs: Set<String> = [],
        highQualityPhotos: Bool,
        spoilerAssetIDs: Set<String> = [],
        selfDestructTimer: MediaSelfDestructTimer? = nil,
        videoPreset: VideoSendPreset = .medium,
        completion: @escaping ([SelectedImage]) -> Void,
    ) {
        guard !assets.isEmpty else { return completion([]) }
        let maximumSide = highQualityPhotos ? PhotoSendPreset.highQualityMaximumSide : PhotoSendPreset.maximumSide
        queue.async {
            // Expired attachments go before this selection writes its own files.
            SelectedDocumentFileStore.removeExpiredFiles()
            let lock = NSLock()
            let group = DispatchGroup()
            let slots = DispatchSemaphore(value: concurrentLoads)
            var selected = [Int: SelectedImage]()
            for (index, asset) in assets.enumerated() {
                slots.wait()
                group.enter()
                let hasSpoiler = spoilerAssetIDs.contains(asset.localIdentifier)
                load(
                    asset,
                    maximumSide: maximumSide,
                    crop: cropAdjustments[asset.localIdentifier],
                    videoEdit: videoEdits[asset.localIdentifier],
                    sendsLive: livePhotoAssetIDs.contains(asset.localIdentifier),
                ) { image in
                    if var image {
                        image.sourceAssetIdentifier = asset.localIdentifier
                        image.hasSpoiler = hasSpoiler
                        image.selfDestructTimer = selfDestructTimer
                        if let size = image.video?.presentationSize {
                            image.video?.preset = videoPreset.capped(for: size)
                        }
                        lock.lock()
                        selected[index] = image
                        lock.unlock()
                    }
                    slots.signal()
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                completion(selected.keys.sorted().compactMap { selected[$0] })
            }
        }
    }

    private static func load(
        _ asset: PHAsset,
        maximumSide: Int,
        crop: PhotoCropAdjustments?,
        videoEdit: VideoEditAdjustments?,
        sendsLive: Bool,
        completion: @escaping (SelectedImage?) -> Void,
    ) {
        switch asset.mediaType {
        case .video:
            loadVideo(asset, edit: videoEdit, completion: completion)
        case .image where sendsLive && asset.mediaSubtypes.contains(.photoLive):
            loadLivePhoto(asset, maximumSide: maximumSide, crop: crop, completion: completion)
        case .image:
            // An edited photo goes as the editor left it (TGPhotoEditorCrop), and a Live Photo whose mode is Live
            // Off as its still (`TGMediaAssetsResolvedLivePhotoMode`).
            loadPhoto(asset, maximumSide: maximumSide, crop: crop, completion: completion)
        default:
            completion(nil)
        }
    }

    /// The photo as the library shows it, edits included (`PHImageRequestOptionsVersion.current`).
    private static func loadPhoto(
        _ asset: PHAsset,
        maximumSide: Int,
        crop: PhotoCropAdjustments? = nil,
        completion: @escaping (SelectedImage?) -> Void,
    ) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            guard let data else {
                log("Could not read picked photo: \(String(describing: info?[PHImageErrorKey]))")
                completion(nil)
                return
            }
            // Photos answers on the main queue; the photo is scaled and written off it.
            DispatchQueue.global(qos: .userInitiated).async {
                if let crop {
                    completion(writeImage(data: data, cropping: crop, maximumSide: maximumSide))
                } else {
                    completion(writeImage(data: data, maximumSide: maximumSide))
                }
            }
        }
    }

    /// TGMediaAssetsController's Live mode: the still as a photo, edited as the editor left it, with the paired
    /// motion the composer sends as a Live Photo. The motion goes as the library keeps it, and TDLib converts it with
    /// the still's crop when it uploads (`livePhotoConversion`). Without readable motion the still goes alone.
    private static func loadLivePhoto(
        _ asset: PHAsset,
        maximumSide: Int,
        crop: PhotoCropAdjustments?,
        completion: @escaping (SelectedImage?) -> Void,
    ) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let motion = resources.first(where: { $0.type == .fullSizePairedVideo })
            ?? resources.first(where: { $0.type == .pairedVideo })
        else {
            loadPhoto(asset, maximumSide: maximumSide, crop: crop, completion: completion)
            return
        }
        loadPhoto(asset, maximumSide: maximumSide, crop: crop) { image in
            guard let image, let motionURL = try? SelectedDocumentFileStore.makeFileURL(named: "motion.mov") else {
                completion(image)
                return
            }
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: motion, toFile: motionURL, options: options) { error in
                var selected = image
                if let error {
                    log("Could not read picked Live Photo motion: \(error)")
                    try? FileManager.default.removeItem(at: motionURL)
                } else {
                    selected.livePhotoVideoURL = motionURL
                    selected.livePhotoCrop = crop
                }
                completion(selected)
            }
        }
    }

    /// Telegram sends a picked video converted, with its first frame as the thumbnail (`LegacyMediaPickers`). The
    /// edited render is preferred to the original, as the library shows it. A GIF's copy is named `mp4`, the type
    /// it converts to, because TDLib takes an animation's MIME type from the original's extension.
    private static func loadVideo(
        _ asset: PHAsset,
        edit: VideoEditAdjustments?,
        completion: @escaping (SelectedImage?) -> Void,
    ) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video })
        else {
            completion(nil)
            return
        }
        var pathExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension
        if edit?.sendsAsGIF == true {
            pathExtension = "mp4"
        } else if pathExtension.isEmpty {
            pathExtension = "mov"
        }
        guard let url = try? SelectedDocumentFileStore.makeFileURL(named: "video.\(pathExtension)") else {
            completion(nil)
            return
        }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
            if let error {
                log("Could not read picked video: \(error)")
                try? FileManager.default.removeItem(at: url)
                completion(nil)
                return
            }
            Task.detached(priority: .userInitiated) {
                await completion(SelectedVideoLoader.selection(forMovieAt: url, edit: edit))
            }
        }
    }
}
