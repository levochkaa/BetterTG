// ChatVM.swift

import AVFoundation
import Combine
import ImageIO
import TDLibKit
import UIKit

@MainActor final class ChatVM: ObservableObject {
    // MARK: Lifecycle

    init(customChat: CustomChat) {
        self.customChat = customChat
        self.chatID = customChat.id
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }
        
        try? td.openChat(chatId: customChat.chat.id) { _ in }
        setPublishers()
        loadMessages()
        Media.shared.onChatOpen(title: customChat.chat.title)
        
        if let draftMessage = customChat.draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            self.text = getAttributedString(from: draftMessageContentText.text)
        }
        
        let draftMessage = customChat.draftMessage
        Task { [weak self] in
            guard let self, let draftMessage else { return }
            let replyMessage = await getInputReplyToMessage(draftMessage.replyTo)
            self.replyMessage = replyMessage
        }
    }

    deinit {
        log("deinit \(chatID)")
        loadingMessagesTask?.cancel()
        sendMessageTask?.cancel()
        timer?.invalidate()
        audioRecorder?.stop()
        try? td.closeChat(chatId: chatID) { _ in }
        Media.shared.onChatDismiss()
    }
    
    // MARK: Internal

    let messagesDidChange = PassthroughSubject<Void, Never>()

    let customChat: CustomChat
    nonisolated let chatID: Int64

    @Published var actionStatus = ""
    @Published var onlineStatus = ""
    @Published var editCustomMessage: CustomMessage?
    @Published var replyMessage: CustomMessage?
    @Published var highlightedMessageId: Int64?
    @Published var displayedImages = [SelectedImage]()
    @Published var timerCount = 0.0
    @Published var text: AttributedString = ""
    @Published var editMessageText: AttributedString = ""
    @Published var recordingVoiceNote = false
    @Published var errorShown = false

    var loadingMessagesTask: Task<Void, Never>?
    var cancellables = Set<AnyCancellable>()
    var timer: Timer?
    var wave = [Float]()
    var sendMessageTask: Task<Void, Never>?
    var savedVoiceNoteUrl = URL(filePath: "")
    var audioRecorder: AVAudioRecorder?

    @Published var messages = [CustomMessage]() {
        didSet { messagesDidChange.send() }
    }

    var canEditMessage: Bool {
        guard let editCustomMessage else { return false }
        switch editCustomMessage.message.content {
        case .messageAnimation, .messagePhoto, .messageVideo, .messageVoiceNote:
            return true
        case .messageText:
            return !editMessageText.characters.isEmpty
        default:
            return false
        }
    }
    
    var formattedTimerCount: String {
        let time = String(format: "%.2f", timerCount).split(separator: ".", maxSplits: 2)
        let seconds = Int(time[0]) ?? 0
        var resultString = ""
        if seconds >= 60 {
            resultString += "\(seconds / 60):" // seconds / 60 == minutes
            var estimatedSeconds = String(seconds % 60)
            if estimatedSeconds.count == 1 {
                estimatedSeconds = "0\(estimatedSeconds)"
            }
            resultString += "\(estimatedSeconds)"
        } else {
            resultString += "\(seconds).\(time[1])" // time[1] == millisecongs
        }
        return resultString
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
        guard loadingMessagesTask == nil, hasMoreMessages else { return }
        let fromMessageID = messages.last?.message.id ?? 0
        loadingMessagesTask = Task { [weak self] in
            await self?._loadMessages(fromMessageID: fromMessageID)
        }
    }
    
    func _loadMessages(fromMessageID: Int64) async {
        guard let chatHistory = try? await td.getChatHistory(
            chatId: customChat.chat.id,
            fromMessageId: fromMessageID,
            limit: 30,
            offset: 0,
            onlyLocal: false,
        )
        .messages else {
            await main { self.loadingMessagesTask = nil }
            return
        }
        guard !chatHistory.isEmpty else {
            await main {
                self.hasMoreMessages = false
                self.loadingMessagesTask = nil
            }
            return
        }
        
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
            let existingIDs = Set(self.messages.map(\.id))
            self.messages.append(contentsOf: savedMessages.filter { !existingIDs.contains($0.id) })
            self.hasMoreMessages = chatHistory.count == 30
            self.loadingMessagesTask = nil
        }
    }

    func deleteMessage(id: Int64, deleteForBoth: Bool) {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        let ids = customMessage.album.isEmpty ? [id] : customMessage.album.map(\.id)
        Task {
            _ = try? await td.deleteMessages(chatId: chatID, messageIds: ids, revoke: deleteForBoth)
        }
    }
    
    func viewMessage(id: Int64) {
        Task {
            try await td.viewMessages(
                chatId: chatID,
                forceRead: true,
                messageIds: [id],
                source: nil,
            )
        }
    }
    
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = try? await td.getMessage(chatId: customChat.chat.id, messageId: id) else { return nil }
        return await getCustomMessage(from: message)
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        let replyToMessage = await getReplyToMessage(message.replyTo)
        let customMessage = await CustomMessage(
            message: message,
            replyToMessage: replyToMessage,
            forwardedFrom: getForwardedFrom(message.forwardInfo?.origin),
            properties: (try? td.getMessageProperties(
                chatId: customChat.chat.id, messageId: message.id,
            )) ?? .default,
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
        case .messageAnimation(let messageAnimation):
            if !messageAnimation.caption.text.isEmpty {
                customMessage.formattedText = messageAnimation.caption
            }
        case .messageVideo(let messageVideo):
            if !messageVideo.caption.text.isEmpty {
                customMessage.formattedText = messageVideo.caption
            }
        case .messageSticker:
            break
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
            if let title = await (try? td.getChat(chatId: chat.senderChatId))?.title {
                return !chat.authorSignature.isEmpty ? "\(title) (\(chat.authorSignature))" : title
            } else {
                return !chat.authorSignature.isEmpty ? chat.authorSignature : nil
            }
        case .messageOriginChannel(let channel):
            if let title = await (try? td.getChat(chatId: channel.chatId))?.title {
                return !channel.authorSignature.isEmpty ? "\(title) (\(channel.authorSignature))" : title
            } else {
                return !channel.authorSignature.isEmpty ? channel.authorSignature : nil
            }
        case .messageOriginHiddenUser(let messageOriginHiddenUser):
            return messageOriginHiddenUser.senderName
        case .messageOriginUser(let messageOriginUser):
            return await (try? td.getUser(userId: messageOriginUser.senderUserId))?.firstName
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
                        text: text.string,
                    ),
                    duration: duration,
                    selfDestructType: nil,
                    voiceNote: .inputFileLocal(.init(path: savedVoiceNoteUrl.path())),
                    waveform: waveform,
                ),
            ),
            options: nil,
            replyMarkup: nil,
            replyTo: getMessageReplyTo(from: replyMessage),
            topicId: nil,
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
            self.displayedImages.removeAll()
            self.editMessageText = ""
            self.text = ""
            self.replyMessage = nil
            self.editCustomMessage = nil
        }
    }
    
    func sendMessagePhotos() async {
        try? await tdSendChatAction(.chatActionUploadingPhoto(.init(progress: 0)))
        
        if displayedImages.count == 1, let photo = displayedImages.first {
            _ = try? await td.sendMessage(
                chatId: customChat.chat.id,
                inputMessageContent: makeInputMessageContent(for: photo.url),
                options: nil,
                replyMarkup: nil,
                replyTo: getMessageReplyTo(from: replyMessage),
                topicId: nil,
            )
        } else {
            var messageContents = [InputMessageContent]()
            for image in displayedImages {
                await messageContents.append(makeInputMessageContent(for: image.url))
            }
            _ = try? await td.sendMessageAlbum(
                chatId: customChat.chat.id,
                inputMessageContents: messageContents,
                options: nil,
                replyTo: getMessageReplyTo(from: replyMessage),
                topicId: nil,
            )
        }
        
        try? await tdSendChatAction(.chatActionCancel)
    }
    
    func makeInputMessageContent(for url: URL) async -> InputMessageContent {
        let path = url.path()
        let dimensions = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return CGSize.zero }
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            return CGSize(width: width, height: height)
        }.value
        let input = InputFile.inputFileLocal(.init(path: path))
        let photo = InputPhoto(
            addedStickerFileIds: [],
            height: Int(dimensions.height),
            photo: input,
            thumbnail: InputThumbnail(
                height: Int(dimensions.height),
                thumbnail: input,
                width: Int(dimensions.width),
            ),
            video: nil,
            width: Int(dimensions.width),
        )
        return .inputMessagePhoto(
            InputMessagePhoto(
                caption: FormattedText(entities: getEntities(from: text), text: text.string),
                hasSpoiler: false,
                photo: photo,
                selfDestructType: nil,
                showCaptionAboveMedia: false,
            ),
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
                        text: text.string,
                    ),
                ),
            ),
            options: nil,
            replyMarkup: nil,
            replyTo: getMessageReplyTo(from: replyMessage),
            topicId: nil,
        )
        
        try? await tdSendChatAction(.chatActionCancel)
    }
    
    func editMessage() async {
        guard let message = editCustomMessage?.message else { return }
        
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
                            text: editMessageText.string,
                        ),
                    ),
                ),
                messageId: message.id,
                replyMarkup: nil,
            )
        case .messageAnimation, .messagePhoto, .messageVideo, .messageVoiceNote:
            _ = try? await td.editMessageCaption(
                caption: FormattedText(
                    entities: getEntities(from: editMessageText),
                    text: editMessageText.string,
                ),
                chatId: customChat.chat.id,
                messageId: message.id,
                replyMarkup: nil,
                showCaptionAboveMedia: false,
            )
        default:
            log("Unsupported edit message type")
        }
    }
    
    func updateDraft() async {
        let draftMessage = DraftMessage(
            content: .draftMessageContentText(
                .init(
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string,
                    ),
                ),
            ),
            date: Int(Date.now.timeIntervalSince1970),
            effectId: 0,
            replyTo: getMessageReplyTo(from: replyMessage),
            suggestedPostInfo: nil,
        )
        _ = try? await td.setChatDraftMessage(
            chatId: customChat.chat.id,
            draftMessage: draftMessage,
            topicId: nil,
        )
    }
    
    func setEditMessageText(from message: Message?) {
        switch message?.content {
        case .messageText(let messageText):
            editMessageText = getAttributedString(from: messageText.text)
        case .messagePhoto(let messagePhoto):
            editMessageText = getAttributedString(from: messagePhoto.caption)
        case .messageVoiceNote(let messageVoiceNote):
            editMessageText = getAttributedString(from: messageVoiceNote.caption)
        case .messageAnimation(let messageAnimation):
            editMessageText = getAttributedString(from: messageAnimation.caption)
        case .messageVideo(let messageVideo):
            editMessageText = getAttributedString(from: messageVideo.caption)
        default:
            break
        }
    }
    
    func getMessageReplyTo(from customMessage: CustomMessage?) -> InputMessageReplyTo? {
        guard let customMessage else { return nil }
        return .inputMessageReplyToMessage(.init(
            checklistTaskId: 0,
            messageId: customMessage.message.id,
            pollOptionId: "",
            quote: nil,
        ))
    }
    
    func startTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, let audioRecorder else { return }
                audioRecorder.updateMeters()
                wave.append(audioRecorder.peakPower(forChannel: 0))
                timerCount += timer.timeInterval
            }
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
                bytesWave.append((wave & 0b0001_1111) << 3)
            case 1:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1100) >> 2)
                bytesWave.append((wave & 0b0000_0011) << 6)
            case 2:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1111) << 1)
            case 3:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_0000) >> 4)
                bytesWave.append((wave & 0b0000_1111) << 4)
            case 4:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1110) >> 1)
                bytesWave.append((wave & 0b0000_0001) << 7)
            case 5:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1111) << 2)
            case 6:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1000) >> 3)
                bytesWave.append((wave & 0b0000_0111) << 5)
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
            topicId: nil,
        )
    }
    
    @MainActor func mediaStartRecordingVoice() async {
        Media.shared.setAudioSessionRecord()
        Media.shared.stop()
        wave.removeAll(keepingCapacity: true)
        timerCount = 0
        
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            log("Access to Microphone for Voice messages is granted")
        } else {
            log("Access to Microphone for Voice messages is not granted")
            errorShown = true
            return
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue,
        ]
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav")
        savedVoiceNoteUrl = url
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            recordingVoiceNote = true
            try? await tdSendChatAction(.chatActionRecordingVoiceNote)
        } catch {
            log("Error creating AudioRecorder: \(error)")
        }
    }
    
    func mediaStopRecordingVoice(duration: Int, wave: [Float]) {
        audioRecorder?.stop()
        recordingVoiceNote = false
        self.wave.removeAll(keepingCapacity: true)
        Task { try? await self.tdSendChatAction(.chatActionCancel) }
        
        let intWave: [Int] = wave.compactMap { wave in
            let intWave = abs(Int(wave))
            if intWave == 120 || intWave == 160 {
                return nil
            }
            return intWave
        }
        let resultWave: [Int] = intWave.map { wave in
            let value = 32 - Int(Double(wave) * Double(32) / Double(66)) // 66 is a random number, need to be tested
            return value < 0 ? 0 : value
        }
        let collapsedWave: [Int] = resultWave.reduce([]) { result, element in
            if result.last != element {
                return result + [element]
            }
            return result
        }
        let endWave = collapsedWave.map { UInt8($0) }
        let bytesWave = getBytesWave(from: endWave)
        let waveform = Data(bytesWave).prefix(63)
        
        Task {
            try? await self.tdSendChatAction(.chatActionUploadingVoiceNote(.init(progress: 0)))
            await self.sendMessageVoiceNote(duration: duration, waveform: waveform)
        }
    }

    func cancelVoiceRecording() {
        audioRecorder?.stop()
        try? FileManager.default.removeItem(at: savedVoiceNoteUrl)
        wave.removeAll(keepingCapacity: true)
        stopTimer()
        recordingVoiceNote = false
        Task { try? await self.tdSendChatAction(.chatActionCancel) }
    }

    // MARK: Private

    private var hasMoreMessages = true
}
