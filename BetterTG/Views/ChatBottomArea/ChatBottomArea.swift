// ChatBottomArea.swift

import SwiftUI

struct ChatBottomArea: View {
    
    var focused: FocusState<Bool>.Binding
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var openedPhotoNamespace: Namespace.ID?
    
    @State var onLongPressVoice = false
    @State var timerCount = 0.0
    @State var timer: Timer?
    @State var wave = [Float]()
    
    @Namespace var chatBottomAreaNamespace
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    let micId = "micId"
    
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            top
                .transition(.move(edge: .bottom).combined(with: .opacity))
            
            if !viewModel.displayedPhotos.isEmpty {
                photosScroll
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            if !viewModel.recordingVoiceNote {
                HStack(alignment: .center, spacing: 10) {
                    leftSide
                    
                    textField
                    
                    rightSide
                }
            } else {
                voiceNoteRecording
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.bar)
        .cornerRadius(15)
        .padding([.bottom, .horizontal], 5)
        // swiftlint:disable multiple_closures_with_trailing_closure
        .alert("Error", isPresented: $viewModel.errorShown, actions: {}) {
            Text(viewModel.errorMessage)
        }
        .animation(.default, value: viewModel.bottomAreaState)
    }
}
