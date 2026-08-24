// ChatVM.swift

import AVFoundation
import Combine
import ImageIO
import TDLibKitDynamic
import UIKit

@MainActor final class ChatVM: ObservableObject {
    // MARK: Lifecycle

    init(customChat: CustomChat, previewing: Bool = false) {
        self.customChat = customChat
        self.chatID = customChat.id
        self.previewing = previewing
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }
        
        try? td.openChat(chatId: customChat.chat.id) { _ in }
        setPublishers()
        observeVoiceRecordingInterruptions()
        loadMessages()
        if !previewing {
            Media.shared.onChatOpen(title: customChat.chat.title)
        }
        
        if !previewing,
           let draftMessage = customChat.draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            self.text = getAttributedString(from: draftMessageContentText.text)
        }
        
        let draftMessage = previewing ? nil : customChat.draftMessage
        Task { [weak self] in
            guard let self, let draftMessage else { return }
            let replyMessage = await getInputReplyToMessage(draftMessage.replyTo)
            self.replyMessage = replyMessage
        }
        Task { [weak self] in
            guard let self else { return }
            guard !previewing else {
                self.loadingVoiceDraft = false
                return
            }
            let drafts = await VoiceNoteDraftStore.shared.drafts(for: chatID)
            var restoredPendingDraft: VoiceNoteSendDraft?
            for draft in drafts {
                if let temporaryMessageID = draft.temporaryMessageID {
                    outgoingVoiceNotes[temporaryMessageID] = draft
                } else if restoredPendingDraft == nil {
                    restoredPendingDraft = draft
                }
            }
            if let restoredPendingDraft {
                activatePendingVoiceDraft(restoredPendingDraft)
                if restoredPendingDraft.enqueueStartedAt != nil {
                    self.voiceNoteErrorMessage = "A previous voice send was interrupted before its status was confirmed. Check the chat before retrying."
                } else if let retryStatus = pendingVoiceRetryStatusMessage {
                    self.voiceNoteErrorMessage = retryStatus
                }
            }
            self.loadingVoiceDraft = false
        }
    }

    deinit {
        log("deinit \(chatID)")
        loadingMessagesTask?.cancel()
        sendMessageTask?.cancel()
        voiceFinalizeTask?.cancel()
        voiceRetryAvailabilityTask?.cancel()
        timer?.invalidate()
        if audioRecorder != nil {
            Media.shared.endAudioSessionRecord()
        }
        audioRecorder?.stop()
        if let recordingVoiceNoteURL {
            try? FileManager.default.removeItem(at: recordingVoiceNoteURL)
        }
        try? td.closeChat(chatId: chatID) { _ in }
        if !previewing {
            Media.shared.onChatDismiss()
        }
    }
    
    // MARK: Internal

    enum VoiceRecordingInteractionState: Equatable {
        case holding
        case idle
        case locked
    }

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
    @Published private(set) var voiceRecordingInteractionState = VoiceRecordingInteractionState.idle
    @Published private(set) var startingVoiceNote = false
    @Published private(set) var loadingVoiceDraft = true
    @Published private(set) var finalizingVoiceNote = false
    @Published private(set) var hasPendingVoiceNote = false
    @Published private(set) var pendingVoiceReplyMessage: CustomMessage?
    @Published var voiceNoteErrorMessage: String?
    @Published var errorShown = false

    var loadingMessagesTask: Task<Void, Never>?
    var cancellables = Set<AnyCancellable>()
    var timer: Timer?
    var wave = [Float]()
    var sendMessageTask: Task<Void, Never>?
    var voiceFinalizeTask: Task<Void, Never>?
    var recordingVoiceNoteURL: URL?
    var audioRecorder: AVAudioRecorder?

    @Published var messages = [CustomMessage]() {
        didSet { messagesDidChange.send() }
    }

    var pendingVoiceReplyMessageID: Int64? {
        pendingVoiceNote?.replyMessageID
    }

    var canRetryPendingVoiceNote: Bool {
        guard let pendingVoiceNote, pendingVoiceNote.enqueueStartedAt == nil else { return false }
        return pendingVoiceNote.failedSendState?.canRetryNow ?? true
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
    
    init(customChat: CustomChat, previewing: Bool = false) {
        self.customChat = customChat
        self.chatID = customChat.id
        self.previewing = previewing
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }

        try? td.openChat(chatId: customChat.chat.id) { _ in }
        setPublishers()
        loadMessages()
        if !previewing {
            Media.shared.onChatOpen(title: customChat.displayTitle)
        }

        if !previewing,
           let draftMessage = customChat.draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            self.text = getAttributedString(from: draftMessageContentText.text)
        }

        let draftMessage = previewing ? nil : customChat.draftMessage
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
        if !previewing {
            Media.shared.onChatDismiss()
        }
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

    func displayedMessageID(containing messageID: Int64) -> Int64? {
        messages.first(where: { message in
            message.id == messageID || message.album.contains(where: { $0.id == messageID })
        })?.id
    }

    func ensureMessageLoaded(id: Int64) async -> Int64? {
        if let displayedID = displayedMessageID(containing: id) {
            return displayedID
        }

        var history = await (try? td.getChatHistory(
            chatId: chatID,
            fromMessageId: id,
            limit: windowSize,
            offset: -(windowSize / 2),
            onlyLocal: false,
        )
        .messages) ?? []
        if !history.contains(where: { $0.id == id }),
           let target = try? await td.getMessage(chatId: chatID, messageId: id)
        {
            history.append(target)
        }
        guard !history.isEmpty else { return nil }

        let loaded = await history.asyncMap { await getCustomMessage(from: $0) }
        guard !Task.isCancelled else { return nil }
        var grouped = [CustomMessage]()
        for message in loaded {
            let albumID = message.message.mediaAlbumId
            if albumID != 0, let existing = grouped.first(where: { $0.message.mediaAlbumId == albumID }) {
                if !existing.album.contains(where: { $0.id == message.id }) {
                    existing.album.append(message.message)
                }
            } else {
                grouped.append(message)
            }
        }

        var merged = messages
        for message in grouped {
            let albumID = message.message.mediaAlbumId
            if albumID != 0, let existing = merged.first(where: { $0.message.mediaAlbumId == albumID }) {
                let knownIDs = Set(existing.album.map(\.id))
                existing.album.append(contentsOf: message.album.filter { !knownIDs.contains($0.id) })
                existing.album.sort { lhs, rhs in
                    lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date
                }
            } else if !merged.contains(where: { $0.id == message.id }) {
                merged.append(message)
            }
        }
        let preparedMessages = merged.sorted { lhs, rhs in
            lhs.message.date == rhs.message.date ? lhs.id > rhs.id : lhs.message.date > rhs.message.date
        }
        guard let displayedMessageID = preparedMessages.first(where: { message in
            message.id == id || message.album.contains(where: { $0.id == id })
        })?.id else { return nil }
        return PreparedMessageWindow(messages: preparedMessages, displayedMessageID: displayedMessageID)
    }

    func applyMessageWindow(_ window: PreparedMessageWindow) {
        messages = window.messages
    }

    func deleteMessage(id: Int64, deleteForBoth: Bool) {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        let ids = customMessage.album.isEmpty ? [id] : customMessage.album.map(\.id)
        for messageID in ids {
            outgoingVoiceNotes.removeValue(forKey: messageID)
        }
        if let failedMessageID = pendingVoiceNote?.failedSendState?.messageID, ids.contains(failedMessageID) {
            pendingVoiceNote = nil
            pendingVoiceReplyMessage = nil
            hasPendingVoiceNote = false
            voiceNoteErrorMessage = nil
        }
        Task {
            await VoiceNoteDraftStore.shared.discardMessages(chatID: chatID, messageIDs: ids)
            await promoteNextPendingVoiceDraft()
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
        guard timer == nil else { return }
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
    
    func tdSendChatAction(_ chatAction: ChatAction) async throws {
        try await td.sendChatAction(
            action: chatAction,
            businessConnectionId: nil,
            chatId: customChat.chat.id,
            topicId: nil,
        )
    }
    
    @MainActor func mediaStartRecordingVoice() async -> Bool {
        guard !loadingVoiceDraft,
              !startingVoiceNote,
              !recordingVoiceNote,
              !finalizingVoiceNote,
              pendingVoiceNote == nil
        else { return false }
        startingVoiceNote = true
        defer { startingVoiceNote = false }
        wave.removeAll(keepingCapacity: true)
        timerCount = 0
        
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            log("Access to Microphone for Voice messages is granted")
        } else {
            log("Access to Microphone for Voice messages is not granted")
            errorShown = true
            await promoteNextPendingVoiceDraft()
            return false
        }
        guard pendingVoiceNote == nil, !recordingVoiceNote, !finalizingVoiceNote else {
            await promoteNextPendingVoiceDraft()
            return false
        }
        Media.shared.setAudioSessionRecord()
        Media.shared.stop()
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav")
        recordingVoiceNoteURL = url
        
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw VoiceNoteFailure.couldNotStartRecorder
            }
            audioRecorder = recorder
            recordingVoiceNote = true
            voiceRecordingInteractionState = .holding
            startTimer()
            Task { [weak self] in try? await self?.tdSendChatAction(.chatActionRecordingVoiceNote) }
            return true
        } catch {
            log("Error creating AudioRecorder: \(error)")
            try? FileManager.default.removeItem(at: url)
            recordingVoiceNoteURL = nil
            audioRecorder = nil
            voiceRecordingInteractionState = .idle
            Media.shared.endAudioSessionRecord()
            voiceNoteErrorMessage = "Couldn’t start voice recording."
            await promoteNextPendingVoiceDraft()
            return false
        }
    }
    
    func mediaStopRecordingVoice() {
        finishVoiceRecording(sendWhenReady: true, pendingMessage: nil)
    }

    func lockVoiceRecording() {
        guard recordingVoiceNote, voiceRecordingInteractionState == .holding else { return }
        voiceRecordingInteractionState = .locked
    }

    func cancelVoiceRecording() {
        audioRecorder?.stop()
        Media.shared.endAudioSessionRecord()
        audioRecorder = nil
        if let recordingVoiceNoteURL {
            try? FileManager.default.removeItem(at: recordingVoiceNoteURL)
        }
        recordingVoiceNoteURL = nil
        wave.removeAll(keepingCapacity: true)
        stopTimer()
        recordingVoiceNote = false
        voiceRecordingInteractionState = .idle
        Task { [weak self] in
            await self?.promoteNextPendingVoiceDraft()
            try? await self?.tdSendChatAction(.chatActionCancel)
        }
    }

    func retryPendingVoiceNote() {
        guard !loadingVoiceDraft, !finalizingVoiceNote, canRetryPendingVoiceNote else { return }
        startVoiceFinalization()
    }

    func discardPendingVoiceNote() {
        voiceFinalizeTask?.cancel()
        voiceFinalizeTask = nil
        finalizingVoiceNote = false
        let discardedDraft = pendingVoiceNote
        let discardedReply = pendingVoiceReplyMessage
        pendingVoiceNote = nil
        pendingVoiceReplyMessage = nil
        voiceRetryAvailabilityTask?.cancel()
        hasPendingVoiceNote = false
        voiceNoteErrorMessage = nil
        restoreReplyIfNeeded(from: discardedDraft, knownReply: discardedReply)
        Task { [weak self] in
            if let discardedDraft {
                await VoiceNoteDraftStore.shared.remove(discardedDraft)
            }
            await self?.promoteNextPendingVoiceDraft()
            try? await self?.tdSendChatAction(.chatActionCancel)
        }
    }

    func handleVoiceNoteDraftResolution(_ resolution: VoiceNoteDraftResolution) {
        if registeringVoiceMessageIDs.contains(resolution.temporaryMessageID) {
            bufferedVoiceOutcomes[resolution.temporaryMessageID] = resolution
            return
        }
        applyVoiceNoteDraftResolution(resolution)
    }

    func bufferPotentialVoiceMessageDeletions(_ messageIDs: [Int64]) {
        guard finalizingVoiceNote || !registeringVoiceMessageIDs.isEmpty else { return }
        bufferedDeletedMessageIDs.formUnion(messageIDs)
    }

    // MARK: Private

    private enum VoiceNoteFailure: Swift.Error {
        case couldNotStartRecorder
        case resendUnavailable
    }

    private let previewing: Bool

    private var pendingVoiceNote: VoiceNoteSendDraft?
    private var outgoingVoiceNotes = [Int64: VoiceNoteSendDraft]()
    private var registeringVoiceMessageIDs = Set<Int64>()
    private var bufferedVoiceOutcomes = [Int64: VoiceNoteDraftResolution]()
    private var bufferedDeletedMessageIDs = Set<Int64>()
    private var voiceRetryAvailabilityTask: Task<Void, Never>?
    private var hasMoreMessages = true

    private var pendingVoiceRetryStatusMessage: String? {
        guard let draft = pendingVoiceNote else { return nil }
        if draft.enqueueStartedAt != nil {
            return "A previous voice send ended before its status was confirmed. Check the chat before discarding it."
        }
        guard let failedState = draft.failedSendState else { return nil }
        if failedState.requiredPaidMessageStarCount > 0 {
            return "Retrying this voice message requires a paid message, which BetterTG does not support."
        }
        if failedState.needAnotherReplyQuote || failedState.needAnotherSender {
            return "Telegram requires a different reply or sender before this voice message can be retried."
        }
        guard failedState.canRetry else {
            return "Telegram marked this voice message as non-retryable. You can discard the draft."
        }
        if failedState.retryAvailableAt > Foundation.Date() {
            let seconds = max(1, Int(ceil(failedState.retryAvailableAt.timeIntervalSinceNow)))
            return "Telegram will allow retrying this voice message in \(seconds) seconds."
        }
        return nil
    }

    private func finishVoiceRecording(sendWhenReady: Bool, pendingMessage: String?) {
        guard let audioRecorder, let sourceURL = recordingVoiceNoteURL else { return }
        let recordedDuration = audioRecorder.currentTime
        let peakPowers = wave
        audioRecorder.stop()
        Media.shared.endAudioSessionRecord()
        self.audioRecorder = nil
        recordingVoiceNoteURL = nil
        recordingVoiceNote = false
        voiceRecordingInteractionState = .idle
        wave.removeAll(keepingCapacity: true)
        stopTimer()
        Task { try? await self.tdSendChatAction(.chatActionCancel) }
        guard recordedDuration >= 0.5 else {
            try? FileManager.default.removeItem(at: sourceURL)
            voiceNoteErrorMessage = pendingMessage ?? "Voice message is too short."
            Task { [weak self] in await self?.promoteNextPendingVoiceDraft() }
            return
        }
        let reply = replyMessage
        pendingVoiceNote = VoiceNoteSendDraft(
            id: UUID(),
            chatID: chatID,
            caption: FormattedText(entities: getEntities(from: text), text: text.string),
            createdAt: Foundation.Date(),
            duration: max(1, Int(recordedDuration)),
            enqueueStartedAt: nil,
            failedSendState: nil,
            fileURL: sourceURL,
            isEncoded: false,
            replyMessageID: reply?.id,
            replyTo: getMessageReplyTo(from: reply),
            temporaryMessageID: nil,
            waveform: VoiceNoteCodec.encodeWaveform(peakPowers: peakPowers),
        )
        pendingVoiceReplyMessage = reply
        replyMessage = nil
        startVoiceFinalization(sendWhenReady: sendWhenReady, pendingMessage: pendingMessage)
    }

    private func sendMessageVoiceNote(fileURL: URL, draft: VoiceNoteSendDraft) async throws -> Message {
        let message = try await td.sendMessage(
            chatId: customChat.chat.id,
            inputMessageContent: .inputMessageVoiceNote(
                .init(
                    caption: draft.caption,
                    selfDestructType: nil,
                    voiceNote: .init(
                        duration: draft.duration,
                        voiceNote: .inputFileLocal(.init(path: fileURL.path())),
                        waveform: draft.waveform,
                    ),
                ),
            ),
            options: nil,
            replyMarkup: nil,
            replyTo: draft.replyTo,
            topicId: nil,
        )
        try? await tdSendChatAction(.chatActionCancel)
        return message
    }

    private func startVoiceFinalization(
        sendWhenReady: Bool = true,
        pendingMessage: String? = nil,
    ) {
        guard var draft = pendingVoiceNote else { return }
        voiceFinalizeTask?.cancel()
        voiceRetryAvailabilityTask?.cancel()
        finalizingVoiceNote = true
        hasPendingVoiceNote = false
        voiceNoteErrorMessage = nil
        voiceFinalizeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                bufferedDeletedMessageIDs.removeAll()
                finalizingVoiceNote = false
                voiceFinalizeTask = nil
            }
            do {
                draft = try await VoiceNoteDraftStore.shared.adopt(draft)
                pendingVoiceNote = draft
                if !draft.isEncoded {
                    let sourceURL = draft.fileURL
                    let encodedURL = try await VoiceNoteCodec.encodeOggOpus(from: sourceURL)
                    try Task.checkCancellation()
                    draft = try await VoiceNoteDraftStore.shared.replaceFile(in: draft, with: encodedURL)
                    pendingVoiceNote = draft
                }
                guard sendWhenReady else {
                    activatePendingVoiceDraft(draft)
                    voiceNoteErrorMessage = pendingMessage ?? "Voice recording stopped before it could be sent."
                    return
                }
                try? await tdSendChatAction(.chatActionUploadingVoiceNote(.init(progress: 0)))
                draft = try await VoiceNoteDraftStore.shared.beginEnqueue(draft)
                pendingVoiceNote = draft
                let message: Message
                if let failedSendState = draft.failedSendState {
                    guard failedSendState.canRetryNow else {
                        throw VoiceNoteFailure.resendUnavailable
                    }
                    let resentMessages = try await td.resendMessages(
                        chatId: chatID,
                        messageIds: [failedSendState.messageID],
                        paidMessageStarCount: 0,
                        quote: nil,
                    )
                    guard let resentMessage = resentMessages.messages?.first else {
                        throw VoiceNoteFailure.resendUnavailable
                    }
                    message = resentMessage
                    draft.failedSendState = nil
                } else {
                    message = try await sendMessageVoiceNote(fileURL: draft.fileURL, draft: draft)
                }
                draft.temporaryMessageID = message.id
                registeringVoiceMessageIDs.insert(message.id)
                var registration: VoiceNoteEnqueueRegistration?
                do {
                    registration = try await VoiceNoteDraftStore.shared.registerEnqueued(
                        draft,
                        temporaryMessageID: message.id,
                    )
                } catch {
                    log("Voice note enqueue persistence failed: \(error)")
                    voiceNoteErrorMessage = "The voice message was queued, but local retry state couldn’t be saved."
                }
                var deletionResolution: VoiceNoteDraftResolution?
                if bufferedDeletedMessageIDs.remove(message.id) != nil {
                    deletionResolution = try? await VoiceNoteDraftStore.shared.handleMessageDeleted(
                        chatID: chatID,
                        temporaryMessageID: message.id,
                    )
                    if deletionResolution == nil, registration == nil,
                       let pendingDraft = try? await VoiceNoteDraftStore.shared.markPending(
                           draft,
                           failedSendState: nil,
                       )
                    {
                        deletionResolution = VoiceNoteDraftResolution(
                            chatID: chatID,
                            draft: pendingDraft,
                            outcome: .failed,
                            temporaryMessageID: message.id,
                        )
                    }
                }
                registeringVoiceMessageIDs.remove(message.id)
                bufferedDeletedMessageIDs.removeAll()
                let bufferedResolution = bufferedVoiceOutcomes.removeValue(forKey: message.id)
                pendingVoiceNote = nil
                pendingVoiceReplyMessage = nil
                voiceRetryAvailabilityTask?.cancel()
                hasPendingVoiceNote = false
                let registrationResolution = registration.flatMap { registration -> VoiceNoteDraftResolution? in
                    guard let outcome = registration.outcome else { return nil }
                    return VoiceNoteDraftResolution(
                        chatID: self.chatID,
                        draft: registration.draft,
                        outcome: outcome,
                        temporaryMessageID: message.id,
                    )
                }
                if let resolution = bufferedResolution ?? registrationResolution ?? deletionResolution {
                    applyVoiceNoteDraftResolution(resolution)
                } else {
                    outgoingVoiceNotes[message.id] = registration?.draft ?? draft
                    if registration != nil {
                        await promoteNextPendingVoiceDraft()
                    }
                }
            } catch is CancellationError {
                hasPendingVoiceNote = pendingVoiceNote != nil
            } catch {
                log("Voice note finalization failed: \(error)")
                if draft.enqueueStartedAt != nil {
                    draft = await (try? VoiceNoteDraftStore.shared.markPending(
                        draft,
                        failedSendState: draft.failedSendState,
                    )) ?? draft
                }
                activatePendingVoiceDraft(draft)
                voiceNoteErrorMessage = pendingVoiceRetryStatusMessage
                    ?? "Couldn’t send the voice message. You can retry without recording again."
                try? await tdSendChatAction(.chatActionCancel)
            }
        }
    }

    private func activatePendingVoiceDraft(_ draft: VoiceNoteSendDraft) {
        pendingVoiceNote = draft
        hasPendingVoiceNote = true
        pendingVoiceReplyMessage = nil
        voiceRetryAvailabilityTask?.cancel()
        if let retryAvailableAt = draft.failedSendState?.retryAvailableAt,
           retryAvailableAt > Foundation.Date()
        {
            voiceRetryAvailabilityTask = Task { [weak self] in
                let delay = retryAvailableAt.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task<Never, Never>.sleep(for: .seconds(delay))
                }
                guard let self, pendingVoiceNote?.id == draft.id else { return }
                objectWillChange.send()
            }
        }
        guard let replyMessageID = draft.replyMessageID else { return }
        Task { [weak self] in
            guard let self else { return }
            let reply = await getCustomMessage(fromId: replyMessageID)
            guard pendingVoiceNote?.id == draft.id else { return }
            pendingVoiceReplyMessage = reply
        }
    }

    private func applyVoiceNoteDraftResolution(_ resolution: VoiceNoteDraftResolution) {
        outgoingVoiceNotes.removeValue(forKey: resolution.temporaryMessageID)
        switch resolution.outcome {
        case .failed:
            if pendingVoiceNote == nil, !recordingVoiceNote, !startingVoiceNote {
                activatePendingVoiceDraft(resolution.draft)
                voiceNoteErrorMessage = pendingVoiceRetryStatusMessage
                    ?? "Couldn’t upload the voice message. You can retry without recording again."
            }
        case .succeeded:
            Task { [weak self] in await self?.promoteNextPendingVoiceDraft() }
        }
    }

    private func promoteNextPendingVoiceDraft() async {
        guard pendingVoiceNote == nil else { return }
        let drafts = await VoiceNoteDraftStore.shared.drafts(for: chatID)
        guard pendingVoiceNote == nil,
              let nextDraft = drafts.first(where: { $0.temporaryMessageID == nil })
        else { return }
        activatePendingVoiceDraft(nextDraft)
        if nextDraft.enqueueStartedAt != nil {
            voiceNoteErrorMessage = "A previous voice send was interrupted before its status was confirmed. Check the chat before retrying."
        } else if let retryStatus = pendingVoiceRetryStatusMessage {
            voiceNoteErrorMessage = retryStatus
        }
    }

    private func restoreReplyIfNeeded(
        from draft: VoiceNoteSendDraft?,
        knownReply: CustomMessage?,
    ) {
        guard replyMessage == nil, editCustomMessage == nil, let replyMessageID = draft?.replyMessageID else { return }
        if let knownReply {
            replyMessage = knownReply
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let restoredReply = await getCustomMessage(fromId: replyMessageID)
            guard replyMessage == nil, editCustomMessage == nil else { return }
            replyMessage = restoredReply
        }
    }

    private func observeVoiceRecordingInterruptions() {
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let rawValue = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?
                          .uintValue,
                          AVAudioSession.InterruptionType(rawValue: rawValue) == .began,
                          recordingVoiceNote
                else { return }
                finishVoiceRecording(
                    sendWhenReady: false,
                    pendingMessage: "Voice recording was interrupted. Retry to send it or discard the draft.",
                )
            }
            .store(in: &cancellables)
    }
}
