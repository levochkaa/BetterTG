// ChatBottomArea.swift

import SwiftUI

struct ChatBottomArea: View {
    
    var focused: FocusState<Bool>.Binding
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var rootNamespace: Namespace.ID?
    
    @State var onLongPressVoice = false
    @State var timerCount = 0.0
    @State var timer: Timer?
    @State var wave = [Float]()
    
    @Namespace var chatBottomAreaNamespace
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    let micId = "micId"
    
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            topSide
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
        .overlay(alignment: .bottomTrailing) {
            if onLongPressVoice {
                Circle()
                    .fill(.blue)
                    .frame(width: 96, height: 96)
                    .offset(x: 20, y: 20)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.white)
                            .font(.title2)
                            .matchedGeometryEffect(id: micId, in: chatBottomAreaNamespace)
                    }
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
