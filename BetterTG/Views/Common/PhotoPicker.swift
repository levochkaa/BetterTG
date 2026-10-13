// PhotoPicker.swift

import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum PhotoPickerSelectionLoader {
    static func load(_ results: [PHPickerResult], completion: @escaping ([SelectedImage]) -> Void) {
        guard !results.isEmpty else { return completion([]) }
        let lock = NSLock()
        let group = DispatchGroup()
        var selected = [Int: SelectedImage]()

        for (index, result) in results.prefix(10).enumerated() {
            let provider = result.itemProvider
            let isVideo = !provider.canLoadObject(ofClass: PHLivePhoto.self)
                && provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            guard isVideo || provider.canLoadObject(ofClass: UIImage.self) else { continue }
            group.enter()
            let store: (SelectedImage?) -> Void = { image in
                defer { group.leave() }
                guard let image else { return }
                lock.lock()
                selected[index] = image
                lock.unlock()
            }
            if isVideo {
                loadVideo(result, completion: store)
            } else {
                load(result, completion: store)
            }
        }

        group.notify(queue: .main) {
            completion(selected.keys.sorted().compactMap { selected[$0] })
        }
    }

    /// Telegram sends a picked video converted, with its first frame as the thumbnail (`LegacyMediaPickers`).
    private static func loadVideo(_ result: PHPickerResult, completion: @escaping (SelectedImage?) -> Void) {
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
            guard let url, let copy = SelectedVideoLoader.copy(url) else {
                log("Error loading picked video: \(String(describing: error))")
                completion(nil)
                return
            }
            Task.detached(priority: .userInitiated) {
                await completion(SelectedVideoLoader.selection(forMovieAt: copy))
            }
        }
    }

    private static func load(_ result: PHPickerResult, completion: @escaping (SelectedImage?) -> Void) {
        let provider = result.itemProvider
        guard provider.canLoadObject(ofClass: PHLivePhoto.self) else {
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error { log("Error loading picked image: \(error)") }
                completion(writeImage(object as? UIImage))
            }
            return
        }
        provider.loadObject(ofClass: PHLivePhoto.self) { object, error in
            guard let livePhoto = object as? PHLivePhoto else {
                log("Could not load selected Live Photo: \(String(describing: error))")
                completion(nil)
                return
            }
            let resources = PHAssetResource.assetResources(for: livePhoto)
            guard let photo = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }),
                  let video = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo })
            else {
                completion(nil)
                return
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "bettertg-live-photo-\(UUID().uuidString)",
                isDirectory: true,
            )
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { completion(nil)
                return
            }
            let photoURL = directory
                .appendingPathComponent("photo.\(URL(fileURLWithPath: photo.originalFilename).pathExtension)")
            let videoURL = directory.appendingPathComponent("motion.mov")
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: photo, toFile: photoURL, options: options) { error in
                guard error == nil else {
                    try? FileManager.default.removeItem(at: directory)
                    completion(nil)
                    return
                }
                PHAssetResourceManager.default().writeData(for: video, toFile: videoURL, options: options) { error in
                    guard error == nil, var selected = writeImage(UIImage(contentsOfFile: photoURL.path)) else {
                        try? FileManager.default.removeItem(at: directory)
                        completion(nil)
                        return
                    }
                    selected.livePhotoVideoURL = videoURL
                    completion(selected)
                }
            }
        }
    }
}
