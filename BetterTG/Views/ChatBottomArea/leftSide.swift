// leftSide.swift

import SwiftUI
import PhotosUI

extension ChatBottomArea {
    @ViewBuilder var leftSide: some View {
        PhotosPicker(selection: $viewModel.selectedPhotos,
                     maxSelectionCount: 10,
                     selectionBehavior: .default,
                     matching: .any(of: [.images, .screenshots]),
                     preferredItemEncoding: .automatic,
                     photoLibrary: .shared()
        ) {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundColor(.white)
        }
    }
}
