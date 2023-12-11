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
    
    let columns = Array(repeating: GridItem(.fixed(Utils.bottomSheetPhotoWidth)), count: 3)
    
    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 5) {
            topSide
                .transition(.move(edge: .bottom).combined(with: .opacity))
            
            if !viewModel.displayedImages.isEmpty {
                photosScroll
            }
            
            Group {
                if !viewModel.recordingVoiceNote {
                    HStack(alignment: .bottom, spacing: 10) {
                        leftSide
                        
                        textField
                        
                        rightSide
                    }
                } else {
                    voiceNoteRecording
                }
            }
        }
        .errorAlert(show: $viewModel.errorShown, text: viewModel.errorMessage)
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
    
    @ViewBuilder var leftSide: some View {
        @Bindable var viewModel = viewModel
        HStack(spacing: 10) {
            if !showDetail {
                Button {
                    withAnimation {
                        showDetail = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.white, Color.gray6)
                        .font(.system(size: 30))
                }
                .padding(.bottom, 2)
            }
            
            if showDetail {
                PhotosPicker(
                    selection: $photosPickerItems,
                    maxSelectionCount: 10,
                    selectionBehavior: .continuousAndOrdered,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                }
                .onChange(of: photosPickerItems) { _, photosPickerItems in
                    viewModel.displayedImages.removeAll()
                    setDisplayedImagesTask?.cancel()
                    setDisplayedImagesTask = Task { [viewModel] in
                        let displayedImages = await photosPickerItems.asyncCompactMap {
                            try? await $0.loadTransferable(type: SelectedImage.self)
                        }
                        await MainActor.run {
                            viewModel.displayedImages = displayedImages
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale))
                .padding(.bottom, 7)
            }
            
            if showDetail {
                Button {
                    viewModel.showCameraView = true
                } label: {
                    Image(systemName: "camera.fill")
                }
                .fullScreenCover(isPresented: $viewModel.showCameraView) {
                    NavigationStack {
                        CameraView()
                            .navigationTitle("Camera")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .transition(.opacity.combined(with: .scale).combined(with: .move(edge: .leading)))
                .padding(.bottom, 7)
            }
        }
        .font(.system(size: 22))
        .foregroundStyle(.white)
        .onChange(of: viewModel.text) { withAnimation { showDetail = false } }
        .onChange(of: viewModel.editMessageText) { withAnimation { showDetail = false } }
        .onChange(of: focused.wrappedValue) { _, focused in
            guard focused else { return }
            withAnimation { showDetail = false }
        }
    }
}
