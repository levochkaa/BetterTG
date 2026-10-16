// PhotoAssetSelectionLoader.swift

import Photos
import UIKit

/// Reads the attachment sheet's picked library items into composer items in pick order, as
/// `legacyAssetPickerItemGenerator` reads Telegram's `TGMediaAsset`s: a photo's current version scaled to 1280 px, or
/// 2560 px when sent in high quality (`LegacyMediaPickers`' `forceHd`), a Live Photo with its paired motion, and a
/// video as the app's copy of its current file. Items that can't be read, such as an iCloud original while offline,
/// are left out.
enum PhotoAssetSelectionLoader {
    /// Library reads running at once, so a pick of a hundred items doesn't decode them all together.
    private static let concurrentLoads = 4
    private static let queue = DispatchQueue(label: "BetterTG.PhotoAssetSelectionLoader", qos: .userInitiated)

    static func load(
        _ assets: [PHAsset],
        highQualityPhotos: Bool,
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
                load(asset, maximumSide: maximumSide) { image in
                    if let image {
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
        completion: @escaping (SelectedImage?) -> Void,
    ) {
        switch asset.mediaType {
        case .video:
            loadVideo(asset, completion: completion)
        case .image:
            if asset.mediaSubtypes.contains(.photoLive) {
                loadLivePhoto(asset, maximumSide: maximumSide, completion: completion)
            } else {
                loadPhoto(asset, maximumSide: maximumSide, completion: completion)
            }
        default:
            completion(nil)
        }
    }

    /// The photo as the library shows it, edits included (`PHImageRequestOptionsVersion.current`).
    private static func loadPhoto(
        _ asset: PHAsset,
        maximumSide: Int,
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
                completion(writeImage(data: data, maximumSide: maximumSide))
            }
        }
    }

    /// The still as a photo, with the paired motion the composer can send as a Live Photo. Without readable motion
    /// the still goes alone.
    private static func loadLivePhoto(
        _ asset: PHAsset,
        maximumSide: Int,
        completion: @escaping (SelectedImage?) -> Void,
    ) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let motion = resources.first(where: { $0.type == .fullSizePairedVideo })
            ?? resources.first(where: { $0.type == .pairedVideo })
        else {
            loadPhoto(asset, maximumSide: maximumSide, completion: completion)
            return
        }
        loadPhoto(asset, maximumSide: maximumSide) { image in
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
                }
                completion(selected)
            }
        }
    }

    /// Telegram sends a picked video converted, with its first frame as the thumbnail (`LegacyMediaPickers`). The
    /// edited render is preferred to the original, as the library shows it.
    private static func loadVideo(_ asset: PHAsset, completion: @escaping (SelectedImage?) -> Void) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video })
        else {
            completion(nil)
            return
        }
        let pathExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension
        guard let url = try? SelectedDocumentFileStore.makeFileURL(
            named: "video.\(pathExtension.isEmpty ? "mov" : pathExtension)",
        ) else {
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
                await completion(SelectedVideoLoader.selection(forMovieAt: url))
            }
        }
    }
}
