// ChatBottomArea.swift

import SwiftUI

struct ChatBottomArea: View {
    
    var focused: FocusState<Bool>.Binding
    
    @State var timerCount = 0.0
    @State var timer: Timer?
    @State var wave = [Float]()
    
    @State var showSendButton = false
    @State var selectedImagesCount = 0
    
    @Namespace var namespace
    
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var rootViewModel: RootViewModel
    
    @Environment(\.redactionReasons) var redactionReasons
    
    let micId = "micId"
    let columns = Array(repeating: GridItem(.fixed(Utils.bottomSheetPhotoWidth)), count: 3)
    
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            topSide
                .transition(.move(edge: .bottom).combined(with: .opacity))
            
            if !viewModel.displayedImages.isEmpty {
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
        .animation(value: viewModel.editCustomMessage)
        .animation(value: viewModel.replyMessage)
        .animation(value: showSendButton)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.bar)
        .cornerRadius(15)
        .padding([.bottom, .horizontal], 5)
        .errorAlert(show: $viewModel.errorShown, text: viewModel.errorMessage)
        .sheet(isPresented: $viewModel.showBottomSheet) {
            bottomSheet
                .presentationDragIndicator(.hidden)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.blue)
                .frame(width: 96, height: 96)
                .overlay(alignment: .center) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .matchedGeometryEffect(id: micId, in: namespace)
                }
                .disabled(!viewModel.recordingVoiceNote)
                .opacity(viewModel.recordingVoiceNote ? 1 : 0)
                .scaleEffect(viewModel.recordingVoiceNote ? 1 : 0)
                .offset(x: 20, y: 20)
                .onTapGesture {
                    viewModel.mediaStopRecordingVoice(duration: Int(timerCount), wave: wave)
                }
        }
        .onChange(of: viewModel.text) { _ in
            showSendButton = !viewModel.text.isEmpty
            || !viewModel.editMessageText.isEmpty
            || !viewModel.displayedImages.isEmpty
        }
        .onChange(of: viewModel.editMessageText) { _ in
            showSendButton = !viewModel.text.isEmpty
            || !viewModel.editMessageText.isEmpty
            || !viewModel.displayedImages.isEmpty
        }
        .onChange(of: viewModel.displayedImages) { _ in
            showSendButton = !viewModel.text.isEmpty
            || !viewModel.editMessageText.isEmpty
            || !viewModel.displayedImages.isEmpty
        }
    }
}
