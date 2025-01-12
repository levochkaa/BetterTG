// PhotoPicker.swift

import SwiftUI
import PhotosUI

typealias PhotoPickerOnSelection = (_ index: Int, _ image: SelectedImage?, _ error: (any Error)?) -> Void

struct PhotoPicker: UIViewControllerRepresentable {
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onSelection: PhotoPickerOnSelection
        private let clear: () -> Void
        private var previousResultsCount = 0
        
        init(onSelection: @escaping PhotoPickerOnSelection, clear: @escaping () -> Void) {
            self.onSelection = onSelection
            self.clear = clear
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard previousResultsCount != results.count else { return picker.dismiss(animated: true) }
            previousResultsCount = results.count
            for (index, result) in results.enumerated() where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [self] item, error in
                    if let selectedImage = writeImage(item as? UIImage) {
                        onSelection(index, selectedImage, error)
                    } else {
                        onSelection(index, nil, error)
                    }
                }
            }
        }
    }
    
    let onSelection: PhotoPickerOnSelection
    let clear: () -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 10
        config.selection = .continuousAndOrdered
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_: PHPickerViewController, context _: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection, clear: clear)
    }
}
