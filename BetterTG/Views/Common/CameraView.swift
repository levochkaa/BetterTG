// CameraView.swift

import SwiftUI

struct CameraView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        // MARK: Lifecycle

        init(_ onSelection: @escaping (SelectedImage) -> Void) {
            self.onSelection = onSelection
        }
        
        // MARK: Internal

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
        ) {
            picker.dismiss(animated: true)
            guard let image = writeImage(info[.originalImage] as? UIImage, withSaving: true) else { return }
            onSelection(image)
        }

        // MARK: Private

        private let onSelection: (SelectedImage) -> Void
    }

    let onSelection: (SelectedImage) -> Void
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = false
        controller.cameraCaptureMode = .photo
        controller.cameraDevice = .rear
        controller.cameraFlashMode = .auto
        controller.showsCameraControls = true
        controller.videoMaximumDuration = 0
        controller.videoQuality = .typeLow
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_: UIViewControllerType, context _: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection)
    }
}
