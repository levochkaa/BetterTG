// ChatBottomArea.swift

import SwiftUI
import PhotosUI
import Combine
import TDLibKit

struct ChatBottomArea: View {
    var focused: FocusState<Bool>.Binding
    
    init(focused: FocusState<Bool>.Binding) {
        self.focused = focused
    }
    
    @Namespace var namespace
    @Environment(ChatVM.self) var chatVM
    
    var body: some View {
        @Bindable var chatVM = chatVM
        VStack(spacing: 5) {
            topSide
                .transition(.move(edge: .bottom).combined(with: .opacity))
            
            if !chatVM.displayedImages.isEmpty {
                photosScroll
            }
            
            Group {
                if !chatVM.recordingVoiceNote {
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
        .onDisappear { Task.background { [chatVM] in await chatVM.updateDraft() } }
        .task(id: chatVM.replyMessage) { await chatVM.updateDraft() }
        .task(id: chatVM.editCustomMessage) { chatVM.setEditMessageText(from: chatVM.editCustomMessage?.message) }
        .alert("Error", isPresented: $chatVM.errorShown) {
            Text("""
            Access to Microphone isn't granted.
            Go to Settings -> BetterTG -> Microphone
            if you want to record Voice
            """)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.bar)
        .clipShape(.rect(cornerRadius: 15))
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
                .disabled(!chatVM.recordingVoiceNote)
                .opacity(chatVM.recordingVoiceNote ? 1 : 0)
                .scaleEffect(chatVM.recordingVoiceNote ? 1 : 0)
                .offset(x: 20, y: 20)
                .onTapGesture { chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave) }
        }
        .onChange(of: chatVM.displayedImages) { nc.post(name: .localScrollToLastOnFocus) }
        .onReceive(nc.publisher(for: .localOnSelectedImagesDrop)) { notification in
            guard let selectedImages = notification.object as? [SelectedImage] else { return }
            withAnimation { chatVM.displayedImages = selectedImages }
        }
    }
    
    @ViewBuilder var leftSide: some View {
        @Bindable var chatVM = chatVM
        HStack(spacing: 10) {
            Menu {
                Button {
                    withAnimation {
                        chatVM.displayedImages.removeAll()
                    }
                    chatVM.showPhotoPickerView = true
                } label: {
                    Label("Attach Photos", systemImage: "photo")
                }
                Button {
                    chatVM.showCameraView = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
//                Button {
//                    showDocumentPicker = true
//                } label: {
//                    Label("Attach Files", systemImage: "folder")
//                }
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.white)
                    .font(.system(size: 25))
            }
            .menuOrder(.fixed)
            .frame(height: 36)
            .padding(.bottom, 2)
            .sheet(isPresented: $chatVM.showPhotoPickerView) {
                PhotoPicker { index, image, error in
                    if let image {
                        Task.main {
                            withAnimation {
                                chatVM.displayedImages.place(image, at: index)
                            }
                        }
                    } else if let error {
                        print("Error picking image: \(error.localizedDescription)")
                    }
                } clear: {
                    withAnimation {
                        chatVM.displayedImages.removeAll()
                    }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $chatVM.showCameraView) {
                NavigationStack {
                    CameraView { selectedImage in
                        withAnimation { chatVM.displayedImages = [selectedImage] }
                    }
                    .navigationTitle("Camera")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .font(.system(size: 22))
        .foregroundStyle(.white)
        .onChange(of: chatVM.text) { withAnimation { chatVM.showDetail = false } }
        .onChange(of: chatVM.editMessageText) { withAnimation { chatVM.showDetail = false } }
        .onChange(of: chatVM.replyMessage) {
            if chatVM.replyMessage == nil {
                nc.post(name: .localScrollToLastOnFocus)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: chatVM.editCustomMessage) {
            if chatVM.editCustomMessage == nil {
                nc.post(name: .localScrollToLastOnFocus)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: focused.wrappedValue) {
            nc.post(name: .localScrollToLastOnFocus)
            guard focused.wrappedValue else { return }
            withAnimation { chatVM.showDetail = false }
        }
    }
    
    @ViewBuilder var rightSide: some View {
        Group {
            if chatVM.showSendButton {
                Image("send")
                    .resizable()
                    .clipShape(.circle)
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 3)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.white)
                    .padding(.bottom, 5)
            }
        }
        .font(.title2)
        .contentShape(.rect)
        .transition(.scale)
        .onTapGesture {
            chatVM.sendMessageTask?.cancel()
            chatVM.sendMessageTask = Task.main { await chatVM.sendMessage() }
        }
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 1000) {
            Task.main { await chatVM.mediaStartRecordingVoice() }
        }
        .onChange(of: chatVM.editMessageText, chatVM.setShowSendButton)
        .onChange(of: chatVM.text, chatVM.setShowSendButton)
        .onChange(of: chatVM.displayedImages, chatVM.setShowSendButton)
        .onChange(of: chatVM.editCustomMessage, chatVM.setShowSendButton)
    }
    
    @ViewBuilder var topSide: some View {
        if let editCustomMessage = chatVM.editCustomMessage {
            replyMessageView(editCustomMessage, type: .edit)
        } else if let replyMessage = chatVM.replyMessage {
            replyMessageView(replyMessage, type: .reply)
        }
    }
    
    @ViewBuilder func replyMessageView(_ customMessage: CustomMessage, type: ReplyMessageType) -> some View {
        HStack {
            ReplyMessageView(customMessage: customMessage, type: type, onTap: {
                var id: Int64?
                switch type {
                    case .reply: id = chatVM.replyMessage?.id
                    case .edit: id = chatVM.editCustomMessage?.id
                    default: break
                }
                guard let id else { return }
                chatVM.scrollTo(id: id)
            })
            .background(Color.gray6)
            .clipShape(.rect(cornerRadius: 15))
            
            Image(systemName: "xmark")
                .onTapGesture {
                    withAnimation {
                        chatVM.replyMessage = nil
                        chatVM.editCustomMessage = nil
                    }
                }
        }
    }
    
    @ViewBuilder var photosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .center, spacing: 5) {
                ForEach(chatVM.displayedImages) { photo in
                    photo.image
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 10))
                        .transition(.scale.combined(with: .opacity))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation {
                                    chatVM.displayedImages.removeAll(where: { photo.id == $0.id })
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .blue)
                                    .padding(5)
                            }
                        }
                }
            }
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 15))
        .padding(5)
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 15))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder var textField: some View {
        @Bindable var chatVM = chatVM
        Group {
            if chatVM.editCustomMessage == nil {
                CustomTextField("Message...", text: $chatVM.text)
                    .onReceive(nc.publisher(for: .localPasteImages)) { notification in
                        guard let images = notification.object as? [SelectedImage] else { return }
                        withAnimation { chatVM.displayedImages = images }
                    }
            } else {
                CustomTextField("Edit...", text: $chatVM.editMessageText, focus: true)
            }
        }
        .focused(focused)
        .lineLimit(10)
        .padding(.horizontal, 5)
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 15))
//        .onReceive(
//            Just(text)
//                .throttle(
//                    for: 2,
//                    scheduler: DispatchQueue.global(qos: .background),
//                    latest: true
//                )
//        ) { text in
//            Task.background {
//                if !text.characters.isEmpty {
//                    await tdSendChatAction(.chatActionTyping)
//                } else {
//                    await tdSendChatAction(.chatActionCancel)
//                }
//            }
//        }
    }
    
    @ViewBuilder var voiceNoteRecording: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                withAnimation {
                    try? FileManager.default.removeItem(at: chatVM.savedVoiceNoteUrl)
                    chatVM.audioRecorder?.stop()
                    chatVM.recordingVoiceNote = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22))
                    .contentShape(.rect)
            }
            
            Spacer()
            Text(chatVM.formattedTimerCount)
            Spacer()
            
            rightSide
        }
        .padding(.vertical, 2)
        .onAppear(perform: chatVM.startTimer)
        .onDisappear(perform: chatVM.stopTimer)
    }
}
