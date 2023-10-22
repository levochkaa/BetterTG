// ChatBottomArea.swift

import SwiftUI
import Combine
import PhotosUI

struct ChatBottomArea: View {
    
    var focused: FocusState<Bool>.Binding
    
    @State var timerCount = 0.0
    @State var timer: Timer?
    @State var wave = [Float]()
    
    @State var setDisplayedImagesTask: Task<Void, Never>?
    @State var photosPickerItems = [PhotosPickerItem]()
    @State var showDetail = false
    @State var showSendButton = false
    
    @Namespace var namespace
    
    @Environment(ChatViewModel.self) var viewModel
    @Environment(RootViewModel.self) var rootViewModel
    
    let micId = "micId"
    let columns = Array(repeating: GridItem(.fixed(Utils.bottomSheetPhotoWidth)), count: 3)
    
    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 5) {
            topSide
            
            if !viewModel.displayedImages.isEmpty {
                photosScroll
            }
            
            Group {
                if !viewModel.recordingVoiceNote {
                    HStack(spacing: 10) {
                        leftSide
                            .font(.system(size: 25))
                            .foregroundStyle(.white)
                        
                        textField
                        
                        rightSide
                    }
                } else {
                    voiceNoteRecording
                }
            }
        }
        .errorAlert(show: $viewModel.errorShown, text: viewModel.errorMessage)
        .animation(value: viewModel.editCustomMessage)
        .animation(value: viewModel.replyMessage)
        .animation(value: showSendButton)
        .padding(.vertical, 5)
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
        .onChange(of: focused.wrappedValue) {
            withAnimation {
                showDetail = false
            }
        }
    }
    
    @ViewBuilder var leftSide: some View {
        @Bindable var viewModel = viewModel
        HStack(spacing: 10) {
            Button {
                withAnimation {
                    showDetail.toggle()
                }
            } label: {
                Group {
                    if showDetail {
                        Image(systemName: "xmark.circle")
                    } else {
                        Image(systemName: "plus.circle")
                    }
                }
                .transition(.scale)
            }
            
            if showDetail {
                PhotosPicker(
                    selection: $photosPickerItems,
                    maxSelectionCount: 10,
                    selectionBehavior: .continuousAndOrdered,
                    matching: .images
                ) {
                    Image(systemName: "paperclip.circle")
                }
                .onChange(of: photosPickerItems) { _, photosPickerItems in
                    viewModel.displayedImages.removeAll()
                    setDisplayedImagesTask?.cancel()
                    setDisplayedImagesTask = Task { @MainActor [viewModel] in
                        viewModel.displayedImages = await photosPickerItems.asyncCompactMap {
                            try? await $0.loadTransferable(type: SelectedImage.self)
                        }
                    }
                }
                
                Button {
                    viewModel.showCameraView = true
                } label: {
                    Image(systemName: "camera.circle")
                }
                .fullScreenCover(isPresented: $viewModel.showCameraView) {
                    NavigationStack {
                        CameraView()
                            .navigationTitle("Camera")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
    }
}
