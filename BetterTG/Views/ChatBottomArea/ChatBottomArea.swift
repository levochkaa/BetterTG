// ChatBottomArea.swift

import Combine

struct ChatBottomArea: View {
    
    var focused: FocusState<Bool>.Binding
    
    @State var timerCount = 0.0
    @State var timer: Timer?
    @State var wave = [Float]()
    
    @State var showSendButton = false
    
    @Namespace var namespace
    
    @Environment(ChatViewModel.self) var viewModel
    @Environment(RootViewModel.self) var rootViewModel
    
    let micId = "micId"
    let columns = Array(repeating: GridItem(.fixed(Utils.bottomSheetPhotoWidth)), count: 3)
    
    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .center, spacing: 5) {
            topSide
            
            if !viewModel.displayedImages.isEmpty {
                photosScroll
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
        .errorAlert(show: $viewModel.errorShown, text: viewModel.errorMessage)
        .sheet(isPresented: $viewModel.showBottomSheet) {
            bottomSheet
                .presentationDragIndicator(.hidden)
                .presentationDetents([.medium, .large])
        }
        .animation(value: viewModel.editCustomMessage)
        .animation(value: viewModel.replyMessage)
        .animation(value: showSendButton)
        .frame(height: 48)
        .padding(.horizontal, 10)
        .background(.bar)
        .cornerRadius(15)
        .padding([.bottom, .horizontal], 5)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.blue)
                .frame(width: 96, height: 96)
                .overlay(alignment: .center) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white)
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
    }
}
