// ChatBottomArea.swift

import SwiftUI

struct ChatBottomArea: View {
    
    var focused: FocusState<Bool>.Binding
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var rootNamespace: Namespace.ID?
    
    @State var timerCount = 0.0
    @State var timer: Timer?
    @State var wave = [Float]()
    
    @State var showSendButton = false
    
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
        .animation(.default, value: viewModel.editCustomMessage)
        .animation(.default, value: viewModel.replyMessage)
        .animation(.default, value: showSendButton)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.bar)
        .cornerRadius(15)
        .padding([.bottom, .horizontal], 5)
        // swiftlint:disable multiple_closures_with_trailing_closure
        .alert("Error", isPresented: $viewModel.errorShown, actions: {}) {
            Text(viewModel.errorMessage)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.blue)
                .frame(width: 96, height: 96)
                .overlay(alignment: .center) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .matchedGeometryEffect(id: micId, in: chatBottomAreaNamespace)
                }
                .disabled(!viewModel.recordingVoiceNote)
                .opacity(viewModel.recordingVoiceNote ? 1 : 0)
                .scaleEffect(viewModel.recordingVoiceNote ? 1 : 0)
                .offset(x: 20, y: 20)
                .onTapGesture {
                    viewModel.text = ""
                    viewModel.mediaStopRecordingVoice(duration: Int(timerCount), wave: wave)
                }
        }
        .onChange(of: viewModel.text) { _ in
            showSendButton = !viewModel.text.isEmpty
            || !viewModel.editMessageText.isEmpty
            || !viewModel.displayedPhotos.isEmpty
        }
        .onChange(of: viewModel.editMessageText) { _ in
            showSendButton = !viewModel.text.isEmpty
            || !viewModel.editMessageText.isEmpty
            || !viewModel.displayedPhotos.isEmpty
        }
        .onChange(of: viewModel.displayedPhotos) { _ in
            showSendButton = !viewModel.text.isEmpty
            || !viewModel.editMessageText.isEmpty
            || !viewModel.displayedPhotos.isEmpty
        }
    }
}
