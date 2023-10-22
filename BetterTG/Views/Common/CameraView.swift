// CameraView.swift

import SwiftUI

struct CameraView: UIViewControllerRepresentable {
    
    @Environment(ChatViewModel.self) var viewModel
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = false
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
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func hideCameraView() {
//            parent.viewModel.showBottomSheet = false
//            parent.viewModel.showCameraView = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            hideCameraView()
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            hideCameraView()
            
            guard parent.viewModel.displayedImages.count < 10,
                  let uiImage = info[.originalImage] as? UIImage,
                  let image = writeImage(uiImage, withSaving: true)
            else { return }
            
            withAnimation {
                parent.viewModel.displayedImages.add(image)
            }
        }
    }
}
