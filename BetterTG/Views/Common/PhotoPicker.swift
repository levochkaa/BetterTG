// PhotoPicker.swift

import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum PhotoPickerSelectionLoader {
    static func load(_ results: [PHPickerResult], completion: @escaping ([SelectedImage]) -> Void) {
        guard !results.isEmpty else { return completion([]) }
        // Expired attachments go before this selection writes its own files.
        DispatchQueue.global(qos: .userInitiated).async {
            SelectedDocumentFileStore.removeExpiredFiles()
            loadAll(results, completion: completion)
        }
    }

    private static func loadAll(_ results: [PHPickerResult], completion: @escaping ([SelectedImage]) -> Void) {
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
            loadPhoto(provider, completion: completion)
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
                  let video = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }),
                  let videoURL = try? SelectedDocumentFileStore.makeFileURL(named: "motion.mov")
            else {
                completion(nil)
                return
            }
            // The library still is only read once, to write the JPEG that is sent.
            let photoURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "bettertg-live-photo-\(UUID().uuidString).\(URL(fileURLWithPath: photo.originalFilename).pathExtension)",
            )
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: photo, toFile: photoURL, options: options) { error in
                guard error == nil else {
                    try? FileManager.default.removeItem(at: photoURL)
                    completion(nil)
                    return
                }
                PHAssetResourceManager.default().writeData(for: video, toFile: videoURL, options: options) { error in
                    defer { try? FileManager.default.removeItem(at: photoURL) }
                    guard error == nil, var selected = writeImage(contentsOf: photoURL) else {
                        try? FileManager.default.removeItem(at: videoURL)
                        completion(nil)
                        return
                    }
                    selected.livePhotoVideoURL = videoURL
                    completion(selected)
                }
            }
        }
    }

    /// Reads the library file instead of a decoded image, so only the sent size is decoded.
    private static func loadPhoto(_ provider: NSItemProvider, completion: @escaping (SelectedImage?) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            loadDecodedPhoto(provider, completion: completion)
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
            // The file exists only during this handler.
            guard let url else {
                log("Error loading picked image file: \(String(describing: error))")
                completion(nil)
                return
            }
            completion(writeImage(contentsOf: url))
        }
    }

    private static func loadDecodedPhoto(_ provider: NSItemProvider, completion: @escaping (SelectedImage?) -> Void) {
        provider.loadObject(ofClass: UIImage.self) { object, error in
            if let error { log("Error loading picked image: \(error)") }
            completion(writeImage(object as? UIImage))
        }
    }
}
