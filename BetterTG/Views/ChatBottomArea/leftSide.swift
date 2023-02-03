// leftSide.swift

import SwiftUI
import PhotosUI

extension ChatBottomArea {
    @ViewBuilder var leftSide: some View {
        Button {
            showBottomSheet = true
        } label: {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundColor(.white)
                .contentShape(Rectangle())
        }
        .disabled(!redactionReasons.isEmpty)
        .unredacted()
    }
}
