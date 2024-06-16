// CameraView.swift

import SwiftUI

struct CameraView: UIViewControllerRepresentable {
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
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onSelection: (SelectedImage) -> Void
        
        init(_ onSelection: @escaping (SelectedImage) -> Void) {
            self.onSelection = onSelection
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            guard let image = writeImage(info[.originalImage] as? UIImage, withSaving: true) else { return }
            onSelection(image)
        }
    }
}
