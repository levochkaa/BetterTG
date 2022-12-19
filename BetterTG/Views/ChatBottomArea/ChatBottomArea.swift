// ChatBottomArea.swift

import SwiftUI

struct ChatBottomArea: View {
    
    var focused: FocusState<Bool>.Binding
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var openedPhotoNamespace: Namespace.ID?
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    let logger = Logger(label: "ChatBottomArea")
    
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            top
                .transition(.move(edge: .bottom).combined(with: .opacity))
            
            if !viewModel.displayedPhotos.isEmpty {
                photosScroll
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            HStack(alignment: .center, spacing: 10) {
                left
                
                textField
                
                right
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.bar)
        .cornerRadius(15)
        .padding([.bottom, .horizontal], 5)
        .animation(.default, value: viewModel.bottomAreaState)
    }
}
