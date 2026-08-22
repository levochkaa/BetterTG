// PhotoPicker.swift

import PhotosUI
import UIKit

enum PhotoPickerSelectionLoader {
    static func load(_ results: [PHPickerResult], completion: @escaping ([SelectedImage]) -> Void) {
        guard !results.isEmpty else { return completion([]) }
        let lock = NSLock()
        let group = DispatchGroup()
        var selected = [Int: SelectedImage]()

        for (index, result) in results.prefix(10).enumerated() {
            guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                defer { group.leave() }
                if let error {
                    log("Error loading picked image: \(error)")
                    return
                }
                guard let image = writeImage(object as? UIImage) else { return }
                lock.lock()
                selected[index] = image
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            completion(selected.keys.sorted().compactMap { selected[$0] })
        }
    }
}
