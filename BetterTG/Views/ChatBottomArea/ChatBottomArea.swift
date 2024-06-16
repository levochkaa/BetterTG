// ChatBottomArea.swift

import SwiftUI
import PhotosUI
import Combine
import TDLibKit

// swiftlint:disable:next type_body_length
struct ChatBottomArea: View {
    @Binding var customChat: CustomChat
    @Binding var editCustomMessage: CustomMessage?
    @Binding var replyMessage: CustomMessage?
    var focused: FocusState<Bool>.Binding
    let scrollTo: (Int64) -> Void
    
    init(
        customChat: Binding<CustomChat>,
        editCustomMessage: Binding<CustomMessage?>,
        replyMessage: Binding<CustomMessage?>,
        focused: FocusState<Bool>.Binding,
        scrollTo: @escaping (Int64) -> Void
    ) {
        self._customChat = customChat
        self._editCustomMessage = editCustomMessage
        self._replyMessage = replyMessage
        self.focused = focused
        self.scrollTo = scrollTo
        
        if let draftMessage = customChat.wrappedValue.draftMessage,
           case .inputMessageText(let inputMessageText) = draftMessage.inputMessageText {
            self._text = State(initialValue: getAttributedString(from: inputMessageText.text))
        }
    }
    
    @State var displayedImages = [SelectedImage]()
    
    @State var timerCount = 0.0
    @State var timer: Timer?
    @State var wave = [Float]()
    
    @State var sendMessageTask: Task<Void, Never>?
    @State var setDisplayedImagesTask: Task<Void, Never>?
    @State var showDetail = false
    @State var showSendButton = false
    
    @State var text: AttributedString = ""
    @State var editMessageText: AttributedString = ""
    
    @Namespace var namespace
    
    @State var recordingVoiceNote = false
    @State var errorShown = false
    @State var photosPickerItems = [PhotosPickerItem]()
    @State var showCameraView = false
    @State var savedVoiceNoteUrl = URL(filePath: "")
    @State var audioRecorder = AVAudioRecorder()
    
    var body: some View {
        VStack(spacing: 5) {
            topSide
                .transition(.move(edge: .bottom).combined(with: .opacity))
            
            if !displayedImages.isEmpty {
                photosScroll
            }
            
            Group {
                if !recordingVoiceNote {
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
        .onDisappear { Task.background { await updateDraft() } }
        .task(id: replyMessage) { await updateDraft() }
        .task(id: editCustomMessage) { setEditMessageText(from: editCustomMessage?.message) }
        .alert("Error", isPresented: $errorShown) {
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
                .disabled(!recordingVoiceNote)
                .opacity(recordingVoiceNote ? 1 : 0)
                .scaleEffect(recordingVoiceNote ? 1 : 0)
                .offset(x: 20, y: 20)
                .onTapGesture { mediaStopRecordingVoice(duration: Int(timerCount), wave: wave) }
        }
        .onChange(of: displayedImages) { nc.post(name: .localScrollToLastOnFocus) }
        .onReceive(nc.publisher(for: .localOnSelectedImagesDrop)) { notification in
            guard let selectedImages = notification.object as? [SelectedImage] else { return }
            withAnimation { displayedImages = selectedImages }
        }
    }
    
    @ViewBuilder var leftSide: some View {
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
                    setDisplayedImagesTask?.cancel()
                    setDisplayedImagesTask = Task.background {
                        let displayedImages = await photosPickerItems.asyncCompactMap {
                            try? await $0.loadTransferable(type: SelectedImage.self)
                        }
                        await main { self.displayedImages = displayedImages }
                    }
                }
                .transition(.opacity.combined(with: .scale))
                .padding(.bottom, 7)
            }
            
            if showDetail {
                Button {
                    showCameraView = true
                } label: {
                    Image(systemName: "camera.fill")
                }
                .fullScreenCover(isPresented: $showCameraView) {
                    NavigationStack {
                        CameraView { selectedImage in
                            withAnimation { displayedImages = [selectedImage] }
                        }
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
        .onChange(of: text) { withAnimation { showDetail = false } }
        .onChange(of: editMessageText) { withAnimation { showDetail = false } }
        .onChange(of: replyMessage) {
            if replyMessage == nil {
                nc.post(name: .localScrollToLastOnFocus)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: editCustomMessage) {
            if editCustomMessage == nil {
                nc.post(name: .localScrollToLastOnFocus)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: focused.wrappedValue) {
            nc.post(name: .localScrollToLastOnFocus)
            guard focused.wrappedValue else { return }
            withAnimation { showDetail = false }
        }
    }
    
    @ViewBuilder var rightSide: some View {
        Group {
            if showSendButton {
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
            sendMessageTask?.cancel()
            sendMessageTask = Task.main { await sendMessage() }
        }
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 1000) {
            Task.main { await mediaStartRecordingVoice() }
        }
        .onChange(of: editMessageText, setShowSendButton)
        .onChange(of: text, setShowSendButton)
        .onChange(of: displayedImages, setShowSendButton)
        .onChange(of: editCustomMessage, setShowSendButton)
    }
    
    func setShowSendButton() {
        guard editCustomMessage == nil else { return withAnimation { showSendButton = true } }
        let value = !displayedImages.isEmpty
            || !editMessageText.characters.isEmpty
            || !text.characters.isEmpty
        withAnimation {
            showSendButton = value
        }
    }
    
    @ViewBuilder var topSide: some View {
        if let editCustomMessage {
            replyMessageView(editCustomMessage, type: .edit)
        } else if let replyMessage {
            replyMessageView(replyMessage, type: .reply)
        }
    }
    
    @ViewBuilder func replyMessageView(_ customMessage: CustomMessage, type: ReplyMessageType) -> some View {
        HStack {
            ReplyMessageView(customMessage: customMessage, type: type, onTap: {
                var id: Int64?
                switch type {
                    case .reply: id = replyMessage?.id
                    case .edit: id = editCustomMessage?.id
                    default: break
                }
                guard let id else { return }
                scrollTo(id)
            })
            .background(.gray6)
            .clipShape(.rect(cornerRadius: 15))
            
            Image(systemName: "xmark")
                .onTapGesture {
                    withAnimation {
                        self.replyMessage = nil
                        self.editCustomMessage = nil
                    }
                }
        }
    }
    
    @ViewBuilder var photosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .center, spacing: 5) {
                ForEach(displayedImages) { photo in
                    photo.image
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 10))
                        .transition(.scale.combined(with: .opacity))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation {
                                    displayedImages.removeAll(where: { photo.id == $0.id })
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
        .background(.gray6)
        .clipShape(.rect(cornerRadius: 15))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder var textField: some View {
        Group {
            if editCustomMessage == nil {
                CustomTextField("Message...", text: $text)
                    .onReceive(nc.publisher(for: .localPasteImages)) { notification in
                        guard let images = notification.object as? [SelectedImage] else { return }
                        withAnimation { displayedImages = images }
                    }
            } else {
                CustomTextField("Edit...", text: $editMessageText, focus: true)
            }
        }
        .focused(focused)
        .lineLimit(10)
        .padding(.horizontal, 5)
        .background(.gray6)
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
                    try? FileManager.default.removeItem(at: savedVoiceNoteUrl)
                    audioRecorder.stop()
                    recordingVoiceNote = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22))
                    .contentShape(.rect)
            }
            
            Spacer()
            Text(formattedTimerCount)
            Spacer()
            
            rightSide
        }
        .padding(.vertical, 2)
        .onAppear(perform: startTimer)
        .onDisappear(perform: stopTimer)
    }
    
    var formattedTimerCount: String {
        let time = String(format: "%.2f", timerCount).split(separator: ".", maxSplits: 2)
        let seconds = Int(time[0]) ?? 0
        var resultString = ""
        if seconds >= 60 {
            resultString += "\(seconds / 60):" // seconds / 60 == minutes
            var estimatedSeconds = String(seconds % 60)
            if estimatedSeconds.count == 1 { estimatedSeconds = "0\(estimatedSeconds)" }
            resultString += "\(estimatedSeconds)"
        } else {
            resultString += "\(seconds).\(time[1])" // time[1] == millisecongs
        }
        return resultString
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
            audioRecorder.updateMeters()
            wave.append(audioRecorder.peakPower(forChannel: 0))
            timerCount += timer.timeInterval
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerCount = 0
    }
    
    func getBytesWave(from waves: [UInt8]) -> [UInt8] {
        var bytesWave = [UInt8]()
        var count = 0
        for wave in waves {
            let index = bytesWave.count - 1
            switch count {
                case 0:
                    bytesWave.append((wave & 0b00011111) << 3)
                case 1:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011100) >> 2)
                    bytesWave.append((wave & 0b00000011) << 6)
                case 2:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011111) << 1)
                case 3:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00010000) >> 4)
                    bytesWave.append((wave & 0b00001111) << 4)
                case 4:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011110) >> 1)
                    bytesWave.append((wave & 0b00000001) << 7)
                case 5:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011111) << 2)
                case 6:
                    bytesWave[index] = bytesWave.last! | ((wave & 0b00011000) >> 3)
                    bytesWave.append((wave & 0b00000111) << 5)
                case 7:
                    bytesWave[index] = bytesWave.last! | wave
                default:
                    break
            }
            count += count == 7 ? -7 : 1
        }
        return bytesWave
    }
    
    func tdSendChatAction(_ chatAction: ChatAction) async throws {
        try await td.sendChatAction(
            action: chatAction,
            businessConnectionId: nil,
            chatId: customChat.chat.id,
            messageThreadId: 0
        )
    }
    
    @MainActor func mediaStartRecordingVoice() async {
        Media.shared.setAudioSessionRecord()
        Media.shared.stop()
        
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            log("Access to Microphone for Voice messages is granted")
        } else {
            log("Access to Microphone for Voice messages is not granted")
            self.errorShown = true
            return
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav")
        savedVoiceNoteUrl = url
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            withAnimation { recordingVoiceNote = true }
            try? await tdSendChatAction(.chatActionRecordingVoiceNote)
        } catch {
            log("Error creating AudioRecorder: \(error)")
        }
    }
    
    func mediaStopRecordingVoice(duration: Int, wave: [Float]) {
        audioRecorder.stop()
        withAnimation { recordingVoiceNote = false }
        Task.background { try? await tdSendChatAction(.chatActionCancel) }
        
        let intWave: [Int] = wave.compactMap { wave in
            let intWave = abs(Int(wave))
            if intWave == 120 || intWave == 160 { return nil }
            return intWave
        }
        let resultWave: [Int] = intWave.map { wave in
            let value = 32 - Int(Double(wave) * Double(32) / Double(66)) // 66 is a random number, need to be tested
            return value < 0 ? 0 : value
        }
        let collapsedWave: [Int] = resultWave.reduce([]) { result, element in
            if result.last != element { return result + [element] }
            return result
        }
        let endWave = collapsedWave.map { UInt8($0) }
        let bytesWave = getBytesWave(from: endWave)
        let waveform = Data(bytesWave).prefix(63)
        
        Task.background {
            try? await tdSendChatAction(.chatActionUploadingVoiceNote(.init(progress: 0)))
            await sendMessageVoiceNote(duration: duration, waveform: waveform)
        }
    }
    
    func sendMessageVoiceNote(duration: Int, waveform: Data) async {
        _ = try? await td.sendMessage(
            chatId: customChat.chat.id,
            inputMessageContent: .inputMessageVoiceNote(
                .init(
                    caption: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string
                    ),
                    duration: duration,
                    selfDestructType: nil,
                    voiceNote: .inputFileLocal(.init(path: savedVoiceNoteUrl.path())),
                    waveform: waveform
                )
            ),
            messageThreadId: 0,
            options: nil,
            replyMarkup: nil,
            replyTo: getMessageReplyTo(from: replyMessage)
        )
        text = ""
        try? await tdSendChatAction(.chatActionCancel)
    }
    
    func sendMessage() async {
        if !displayedImages.isEmpty {
            await sendMessagePhotos()
        } else if canEditMessage {
            await editMessage()
        } else if !text.characters.isEmpty {
            await sendMessageText()
        } else {
            return
        }
        
        await main {
            withAnimation {
                displayedImages.removeAll()
                editMessageText = ""
                text = ""
                replyMessage = nil
                editCustomMessage = nil
            }
        }
    }
    
    var canEditMessage: Bool {
        guard let editCustomMessage else { return false }
        switch editCustomMessage.message.content {
            case .messagePhoto, .messageVoiceNote:
                return true
            case .messageText:
                return !editMessageText.characters.isEmpty
            default:
                return false
        }
    }
    
    func sendMessagePhotos() async {
        try? await tdSendChatAction(.chatActionUploadingPhoto(.init(progress: 0)))
        
        if displayedImages.count == 1, let photo = displayedImages.first {
            _ = try? await td.sendMessage(
                chatId: customChat.chat.id,
                inputMessageContent: makeInputMessageContent(for: photo.url),
                messageThreadId: 0,
                options: nil,
                replyMarkup: nil,
                replyTo: getMessageReplyTo(from: replyMessage)
            )
        } else {
            let messageContents = displayedImages.map {
                makeInputMessageContent(for: $0.url)
            }
            _ = try? await td.sendMessageAlbum(
                chatId: customChat.chat.id,
                inputMessageContents: messageContents,
                messageThreadId: nil,
                options: nil,
                replyTo: getMessageReplyTo(from: replyMessage)
            )
        }
        
        try? await tdSendChatAction(.chatActionCancel)
    }
    
    func makeInputMessageContent(for url: URL) -> InputMessageContent {
        let path = url.path()
        let image = UIImage(contentsOfFile: path) ?? UIImage()
        let input: InputFile = .inputFileLocal(.init(path: path))
        return .inputMessagePhoto(
            InputMessagePhoto(
                addedStickerFileIds: [],
                caption: FormattedText(entities: getEntities(from: text), text: text.string),
                hasSpoiler: false,
                height: Int(image.size.height),
                photo: input,
                selfDestructType: nil,
                showCaptionAboveMedia: false,
                thumbnail: InputThumbnail(
                    height: Int(image.size.height),
                    thumbnail: input,
                    width: Int(image.size.width)
                ),
                width: Int(image.size.width)
            )
        )
    }
    
    func sendMessageText() async {
        _ = try? await td.sendMessage(
            chatId: customChat.chat.id,
            inputMessageContent: .inputMessageText(
                .init(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string
                    )
                )
            ),
            messageThreadId: 0,
            options: nil,
            replyMarkup: nil,
            replyTo: getMessageReplyTo(from: replyMessage)
        )
        
        try? await tdSendChatAction(.chatActionCancel)
    }
    
    func editMessage() async {
        guard let message = self.editCustomMessage?.message else { return }
        
        switch message.content {
            case .messageText:
                _ = try? await td.editMessageText(
                    chatId: customChat.chat.id,
                    inputMessageContent:
                            .inputMessageText(
                                .init(
                                    clearDraft: true,
                                    linkPreviewOptions: nil,
                                    text: FormattedText(
                                        entities: getEntities(from: editMessageText),
                                        text: editMessageText.string
                                    )
                                )
                            ),
                    messageId: message.id,
                    replyMarkup: nil
                )
            case .messagePhoto, .messageVoiceNote:
                _ = try? await td.editMessageCaption(
                    caption: FormattedText(
                        entities: getEntities(from: editMessageText),
                        text: editMessageText.string
                    ),
                    chatId: customChat.chat.id,
                    messageId: message.id,
                    replyMarkup: nil,
                    showCaptionAboveMedia: false
                )
            default:
                log("Unsupported edit message type")
        }
    }
    
    func updateDraft() async {
        let draftMessage = DraftMessage(
            date: Int(Date.now.timeIntervalSince1970),
            inputMessageText: .inputMessageText(
                .init(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string
                    )
                )
            ),
            replyTo: getMessageReplyTo(from: replyMessage)
        )
        _ = try? await td.setChatDraftMessage(
            chatId: customChat.chat.id,
            draftMessage: draftMessage,
            messageThreadId: 0
        )
    }
    
    func setEditMessageText(from message: Message?) {
        withAnimation {
            switch message?.content {
                case .messageText(let messageText):
                    editMessageText = getAttributedString(from: messageText.text)
                case .messagePhoto(let messagePhoto):
                    editMessageText = getAttributedString(from: messagePhoto.caption)
                case .messageVoiceNote(let messageVoiceNote):
                    editMessageText = getAttributedString(from: messageVoiceNote.caption)
                default:
                    break
            }
        }
    }
    
    func getMessageReplyTo(from customMessage: CustomMessage?) -> InputMessageReplyTo? {
        guard let customMessage else { return nil }
        return .inputMessageReplyToMessage(
            .init(
                chatId: 0,
                messageId: customMessage.message.id,
                quote: nil
            )
        )
    }
}

// swiftlint:disable:this file_length
