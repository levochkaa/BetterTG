// ChatVM.swift

import SwiftUI
import TDLibKit
import Combine
import AVKit

@Observable final class ChatVM {
    var customChat: CustomChat
    
    init(customChat: CustomChat) {
        self.customChat = customChat
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }
        
        try? td.openChat(chatId: customChat.chat.id) { _ in }
        setPublishers()
        loadMessages()
        Media.shared.onChatOpen(title: customChat.chat.title)
        
        if let draftMessage = customChat.draftMessage,
           case .inputMessageText(let inputMessageText) = draftMessage.inputMessageText {
            self.text = getAttributedString(from: inputMessageText.text)
        }
        
        Task.background {
            guard let draftMessage = customChat.draftMessage else { return }
            let replyMessage = await self.getInputReplyToMessage(draftMessage.replyTo)
            withAnimation { self.replyMessage = replyMessage }
        }
    }
    
    deinit {
        log("deinit \(customChat.chat.id)")
        try? td.closeChat(chatId: customChat.chat.id) { _ in }
        Media.shared.onChatDismiss()
    }
    
    var focused = false
    var bottomAreaHeight: CGFloat = .zero
    var extraBottomPadding: CGFloat { bottomAreaHeight + (focused ? 0 : UIApplication.safeAreaInsets.bottom) + 5 }
    var actionStatus = ""
    var onlineStatus = ""
    var editCustomMessage: CustomMessage?
    var replyMessage: CustomMessage?
    var highlightedMessageId: Int64?
    var messages = [CustomMessage]()
    @ObservationIgnored var dateFormatter: DateFormatter = {
       let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter
    }()
    @ObservationIgnored var loadingMessagesTask: Task<Void, Never>?
    // Scroll
    let chatScrollNamespaceId = "chatScrollNamespaceId"
    @ObservationIgnored var scrollOnFocus = true
    var showScrollToBottomButton = false
    @ObservationIgnored var scrollViewProxy: ScrollViewProxy?
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    var displayedImages = [SelectedImage]()
    var timerCount = 0.0
    @ObservationIgnored var timer: Timer?
    @ObservationIgnored var wave = [Float]()
    @ObservationIgnored var sendMessageTask: Task<Void, Never>?
    @ObservationIgnored var setDisplayedImagesTask: Task<Void, Never>?
    var showDetail = false
    var showSendButton = false
    var text: AttributedString = ""
    var editMessageText: AttributedString = ""
    var recordingVoiceNote = false
    var errorShown = false
    var showCameraView = false
    var showPhotoPickerView = false
    @ObservationIgnored var savedVoiceNoteUrl = URL(filePath: "")
    @ObservationIgnored var audioRecorder: AVAudioRecorder?
    
    func onPreferenceChange(_ value: CGRect) {
        if Int(value.maxY) > Int(UIScreen.main.bounds.height) {
            scrollOnFocus = false
            if !showScrollToBottomButton {
                withAnimation {
                    showScrollToBottomButton = true
                }
            }
        } else {
            scrollOnFocus = true
            if showScrollToBottomButton {
                withAnimation {
                    showScrollToBottomButton = false
                }
            }
        }
        
        guard Int(value.minY) > -500 else { return }
        loadMessages()
    }
    
    func getLastSeenTime(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        
        let difference = Date().timeIntervalSince1970 - TimeInterval(time)
        if difference < 60 {
            return "now"
        } else if difference < 60 * 60 {
            return "\(Int(difference / 60)) minutes ago"
        } else if difference < 60 * 60 * 24 {
            return "\(Int(difference / 60 / 60)) hours ago"
        } else if difference < 60 * 60 * 24 * 2 {
            dateFormatter.dateFormat = "HH:mm"
            return "yesterday at \(dateFormatter.string(from: date))"
        } else {
            dateFormatter.dateFormat = "dd.MM.yy"
            return dateFormatter.string(from: date)
        }
    }
    
    func scrollToLast() {
        guard let lastId = messages.first?.id, let scrollViewProxy else { return }
        withAnimation { scrollViewProxy.scrollTo(lastId, anchor: .bottom) }
    }
    
    func scrollTo(id: Int64?, anchor: UnitPoint = .center) {
        guard let scrollViewProxy, let id else { return }
        
        withAnimation {
            scrollViewProxy.scrollTo(id, anchor: anchor)
            highlightedMessageId = id
        }
        
        Task.main(delay: 0.5) {
            withAnimation {
                self.highlightedMessageId = nil
            }
        }
    }
    
    func getOnlineStatus(from userStatus: UserStatus) -> String {
        switch userStatus {
            case .userStatusEmpty: "empty"
            case .userStatusOnline: /* (let userStatusOnline) */ "online"
            case .userStatusOffline(let userStatusOffline): "last seen \(getLastSeenTime(userStatusOffline.wasOnline))"
            case .userStatusRecently: "last seen recently"
            case .userStatusLastWeek: "last seen last week"
            case .userStatusLastMonth: "last seen last month"
        }
    }
    
    func loadMessages() {
        guard loadingMessagesTask == nil else { return }
        self.loadingMessagesTask = Task.background { await self._loadMessages() }
    }
    
    func _loadMessages() async {
        guard let chatHistory = try? await td.getChatHistory(
            chatId: customChat.chat.id,
            fromMessageId: messages.last?.message.id ?? 0,
            limit: 30,
            offset: 0,
            onlyLocal: false
        ).messages else { return }
        
        let customMessages = await chatHistory.asyncMap { chatMessage in
            await getCustomMessage(from: chatMessage)
        }
        
        var savedMessages = [CustomMessage]()
        for customMessage in customMessages {
            if customMessage.message.mediaAlbumId != 0 {
                if let index = savedMessages.firstIndex(where: {
                    $0.message.mediaAlbumId == customMessage.message.mediaAlbumId
                }) {
                    savedMessages[index].album.append(customMessage.message)
                } else {
                    customMessage.album = [customMessage.message]
                    savedMessages.append(customMessage)
                }
            } else {
                savedMessages.append(customMessage)
            }
        }
        
        await main { [savedMessages] in
            self.messages.append(contentsOf: savedMessages)
            
            Task.main(delay: 0.5) {
                self.loadingMessagesTask = nil
            }
        }
    }
    
    func deleteMessage(id: Int64, deleteForBoth: Bool) {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        Task.background {
            if customMessage.album.isEmpty {
                _ = try? await td.deleteMessages(chatId: self.customChat.chat.id, messageIds: [id], revoke: deleteForBoth)
            } else {
                let ids = customMessage.album.map { $0.id }
                _ = try? await td.deleteMessages(chatId: self.customChat.chat.id, messageIds: ids, revoke: deleteForBoth)
            }
        }
    }
    
    func viewMessage(id: Int64) {
        Task.background {
            try await td.viewMessages(
                chatId: self.customChat.chat.id,
                forceRead: true,
                messageIds: [id],
                source: nil
            )
        }
    }
    
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = try? await td.getMessage(chatId: customChat.chat.id, messageId: id) else { return nil }
        return await getCustomMessage(from: message)
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        let replyToMessage = await getReplyToMessage(message.replyTo)
        let customMessage = CustomMessage(
            message: message,
            replyToMessage: replyToMessage,
            forwardedFrom: await getForwardedFrom(message.forwardInfo?.origin),
            properties: (try? await td.getMessageProperties(
                chatId: customChat.chat.id, messageId: message.id
            )) ?? .default
        )
        
        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }
        
        if case .messageSenderUser(let messageSenderUser) = message.senderId {
            customMessage.senderUser = try? await td.getUser(userId: messageSenderUser.userId)
        }
        
        if case .messageSenderUser(let messageSenderUser) = replyToMessage?.senderId {
            customMessage.replyUser = try? await td.getUser(userId: messageSenderUser.userId)
        }
        
        switch message.content {
            case .messageText(let messageText):
                customMessage.formattedText = messageText.text
            case .messagePhoto(let messagePhoto):
                if !messagePhoto.caption.text.isEmpty {
                    customMessage.formattedText = messagePhoto.caption
                }
            case .messageVoiceNote(let messageVoiceNote):
                if !messageVoiceNote.caption.text.isEmpty {
                    customMessage.formattedText = messageVoiceNote.caption
                }
            case .messageUnsupported:
                customMessage.formattedText = FormattedText(entities: [], text: "TDLib not supported")
            default:
                customMessage.formattedText = FormattedText(entities: [], text: "BTG not supported")
        }
        
        return customMessage
    }
    
    func getForwardedFrom(_ origin: MessageOrigin?) async -> String? {
        guard let origin else { return nil }
        
        switch origin {
            case .messageOriginChat(let chat):
                if let title = (try? await td.getChat(chatId: chat.senderChatId))?.title {
                    return !chat.authorSignature.isEmpty ? "\(title) (\(chat.authorSignature))" : title
                } else {
                    return !chat.authorSignature.isEmpty ? chat.authorSignature : nil
                }
            case .messageOriginChannel(let channel):
                if let title = (try? await td.getChat(chatId: channel.chatId))?.title {
                    return !channel.authorSignature.isEmpty ? "\(title) (\(channel.authorSignature))" : title
                } else {
                    return !channel.authorSignature.isEmpty ? channel.authorSignature : nil
                }
            case .messageOriginHiddenUser(let messageOriginHiddenUser):
                return messageOriginHiddenUser.senderName
            case .messageOriginUser(let messageOriginUser):
                return (try? await td.getUser(userId: messageOriginUser.senderUserId))?.firstName
        }
    }
    
    func getReplyToMessage(_ replyTo: MessageReplyTo?) async -> Message? {
        if case .messageReplyToMessage(let messageReplyToMessage) = replyTo, messageReplyToMessage.messageId != 0 {
            return try? await td.getMessage(chatId: customChat.chat.id, messageId: messageReplyToMessage.messageId)
        }
        return nil
    }
    
    func getInputReplyToMessage(_ inputMessageReplyTo: InputMessageReplyTo?) async -> CustomMessage? {
        if case .inputMessageReplyToMessage(let message) = inputMessageReplyTo {
            return await getCustomMessage(fromId: message.messageId)
        }
        return nil
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
                self.displayedImages.removeAll()
                self.editMessageText = ""
                self.text = ""
                self.replyMessage = nil
                self.editCustomMessage = nil
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
            effectId: 0,
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
    
    func setShowSendButton() {
        guard editCustomMessage == nil else { return withAnimation { showSendButton = true } }
        let value = !displayedImages.isEmpty || !editMessageText.characters.isEmpty || !text.characters.isEmpty
        withAnimation { showSendButton = value }
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
        return .inputMessageReplyToMessage(.init(messageId: customMessage.message.id, quote: nil))
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
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self, let audioRecorder else { return }
            audioRecorder.updateMeters()
            wave.append(audioRecorder.peakPower(forChannel: 0))
            timerCount += timer.timeInterval
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
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
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            withAnimation { recordingVoiceNote = true }
            try? await tdSendChatAction(.chatActionRecordingVoiceNote)
        } catch {
            log("Error creating AudioRecorder: \(error)")
        }
    }
    
    func mediaStopRecordingVoice(duration: Int, wave: [Float]) {
        audioRecorder?.stop()
        withAnimation { recordingVoiceNote = false }
        Task.background { try? await self.tdSendChatAction(.chatActionCancel) }
        
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
            try? await self.tdSendChatAction(.chatActionUploadingVoiceNote(.init(progress: 0)))
            await self.sendMessageVoiceNote(duration: duration, waveform: waveform)
        }
    }
}
