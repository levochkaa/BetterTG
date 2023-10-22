// ChatBottomArea+LeftSide.swift

import SwiftUI
import PhotosUI

extension ChatBottomArea {
    @ViewBuilder var leftSide: some View {
        PhotosPicker(
            selection: $photosPickerItems,
            maxSelectionCount: 10,
            selectionBehavior: .continuousAndOrdered,
            matching: .images
        ) {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundStyle(.white)
                .contentShape(Rectangle())
        }
        .onChange(of: photosPickerItems) { _, photosPickerItems in
            Task { @MainActor in
                viewModel.displayedImages = await photosPickerItems.asyncCompactMap {
                    try? await $0.loadTransferable(type: SelectedImage.self)
                }
                self.photosPickerItems.removeAll()
            }
        }
    }
}
