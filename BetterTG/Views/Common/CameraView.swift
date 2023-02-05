// CameraView.swift

import SwiftUI

struct CameraView: UIViewControllerRepresentable {
    
    @EnvironmentObject var viewModel: ChatViewModel
    
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
            parent.viewModel.showBottomSheet = false
            parent.viewModel.showCameraView = false
            parent.viewModel.presentationDetent = .medium
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            hideCameraView()
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            hideCameraView()
            
            guard let uiImage = info[.originalImage] as? UIImage,
                  let data = uiImage.jpegData(compressionQuality: 1)
            else { return }
            
            UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
            
            let imageUrl = URL(filePath: NSTemporaryDirectory())
                .appending(path: "\(UUID().uuidString).png")
            
            do {
                try data.write(to: imageUrl, options: .atomic)
                withAnimation {
                    parent.viewModel.displayedImages = [SelectedImage(image: Image(uiImage: uiImage), url: imageUrl)]
                }
            } catch {
                log("Error getting data for an image: \(error)")
            }
        }
    }
}
