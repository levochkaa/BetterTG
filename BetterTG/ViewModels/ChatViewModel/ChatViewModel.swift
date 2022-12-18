// ChatViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit
import PhotosUI

class ChatViewModel: ObservableObject {

    let chat: Chat
    
    @Published var text = ""
    @Published var editMessageText = ""
    
    @Published var bottomAreaState: BottomAreaState = .message {
        didSet {
            switch bottomAreaState {
                case .message:
                    withAnimation {
                        text = ""
                        editMessageText = ""
                        replyMessage = nil
                        editMessage = nil
                        displayedPhotos = []
                    }
                case .caption, .reply, .edit:
                    break
            }
        }
    }
    
    var loadedAlbums = [TdInt64]()
    @Published var displayedPhotos = [SelectedImage]() {
        didSet {
            if !displayedPhotos.isEmpty {
                bottomAreaState = .caption
            }
        }
    }
    @Published var selectedPhotos = [PhotosPickerItem]() {
        didSet {
            Task {
                try await loadPhotos()
            }
        }
    }
    
    @Published var scrollViewProxy: ScrollViewProxy?
    @Published var isScrollToBottomButtonShown = false
    
    var initSavedFirstMessage: CustomMessage?
    @Published var savedFirstMessage: CustomMessage?
    
    @Published var savedNewMessages = [Message]()
    @Published var messages = [CustomMessage]()
    @Published var highlightedMessageId: Int64?
    
    @Published var loadingMessages = false
    @Published var initLoadingMessages = false
    
    var offset = 0
    var limit = 30
    
    @Published var editMessage: CustomMessage? {
        didSet {
            if editMessage != nil {
                bottomAreaState = .edit
            }
        }
    }
    @Published var replyMessage: CustomMessage? {
        didSet {
            if displayedPhotos.isEmpty && replyMessage != nil {
                bottomAreaState = .reply
            }
            Task {
                await updateDraft()
            }
        }
    }
    
    let tdApi: TdApi = .shared
    let logger = Logger(label: "ChatVM")
    let nc: NotificationCenter = .default
    
    init(chat: Chat) {
        self.chat = chat
        
        setPublishers()
        
        Task {
            await self.loadMessages(isInit: true)
            
            guard let draftMessage = chat.draftMessage else { return }
            await self.setDraft(draftMessage)
        }
    }
    
    // MARK: - Load -
    
    func loadPhotos() async throws {
        await MainActor.run {
            withAnimation {
                self.displayedPhotos.removeAll()
            }
        }
        
        let processedImages: [SelectedImage] = await selectedPhotos.asyncCompactMap {
            do {
                if let selectedImage = try await $0.loadTransferable(type: SelectedImage.self) {
                    return selectedImage
                }
                return nil
            } catch {
                logger.log("Error transfering image data: \(error)")
                return nil
            }
        }
        
        await MainActor.run {
            withAnimation {
                self.displayedPhotos = processedImages
            }
        }
    }
    
    func loadMessages(isInit: Bool = false) async {
        await MainActor.run {
            self.loadingMessages = true
            
            if isInit {
                self.initLoadingMessages = true
            }
        }
        
        guard let chatHistory = await tdGetChatHistory() else { return }
        
        let chatMessages = chatHistory.messages?.reversed() ?? []
        let customMessages = await chatMessages.asyncMap { chatMessage in
            await self.getCustomMessage(from: chatMessage)
        }
        
        var savedMessages = [CustomMessage]()
        for customMessage in customMessages {
            if customMessage.message.mediaAlbumId != 0 {
                let index = savedMessages.firstIndex(where: {
                    $0.message.mediaAlbumId == customMessage.message.mediaAlbumId
                })
                if let index {
                    savedMessages[index].album.append(customMessage.message)
                } else {
                    var newMessage = customMessage
                    newMessage.album = [customMessage.message]
                    savedMessages.append(newMessage)
                }
            } else {
                savedMessages.append(customMessage)
            }
        }
        
        if isInit {
            initSavedFirstMessage = savedMessages.first
        }
        
        await MainActor.run { [savedMessages] in
            self.savedFirstMessage = self.messages.first
            self.messages = savedMessages + self.messages
            self.offset = self.messages.count
            self.loadingMessages = false
            
            if isInit {
                self.initLoadingMessages = false
            }
        }
    }
    
    // MARK: - Get -
    
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = await tdGetMessage(id: id) else { return nil }
        let customMessage = await getCustomMessage(from: message)
        return customMessage
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        let replyToMessage = await getReplyToMessage(id: message.replyToMessageId)
        var customMessage = CustomMessage(message: message, replyToMessage: replyToMessage)
        
        if case let .messageSenderUser(messageSenderUser) = message.senderId {
            let senderUser = await tdGetUser(id: messageSenderUser.userId)
            customMessage.senderUser = senderUser
        }
        
        if case let .messageSenderUser(messageSenderUser) = replyToMessage?.senderId {
            let replyUser = await tdGetUser(id: messageSenderUser.userId)
            customMessage.replyUser = replyUser
            return customMessage
        }
        
        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }
        
        return customMessage
    }
    
    func getReplyToMessage(id: Int64) async -> Message? {
        return id != 0 ? await tdGetMessage(id: id) : nil
    }
    
    // MARK: - Send/Edit/Delete -
    
    func sendMedia() async {
        if displayedPhotos.isEmpty { return }
        
        await tdSendMessage()
        
        await MainActor.run {
            bottomAreaState = .message
        }
    }
    
    func sendMessage() async {
        if bottomAreaState == .message || bottomAreaState == .reply {
            if text.isEmpty { return }
        }
        
        await tdSendMessage()
        
        await MainActor.run {
            bottomAreaState = .message
        }
    }
    
    func editMessage() async {
        guard let editMessage = self.editMessage else { return }
        
        await tdEditMessageText(editMessage)
        
        await MainActor.run {
            bottomAreaState = .message
        }
    }
    
    func deleteMessage(id: Int64, deleteForBoth: Bool) async {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        
        if customMessage.album.isEmpty {
            await tdDeleteMessages(ids: [id], deleteForBoth: deleteForBoth)
        } else {
            let ids = customMessage.album.map { $0.id }
            await tdDeleteMessages(ids: ids, deleteForBoth: deleteForBoth)
        }
    }
    
    // MARK: - Draft -
    
    func setDraft(_ draftMessage: DraftMessage) async {
        if !text.isEmpty || replyMessage != nil { return }
        
        if case let .inputMessageText(inputMessageText) = draftMessage.inputMessageText {
            await MainActor.run {
                text = inputMessageText.text.text
            }
        }
        
        let customMessage = await getCustomMessage(fromId: draftMessage.replyToMessageId)
        
        await MainActor.run {
            withAnimation {
                replyMessage = customMessage
            }
        }
    }
    
    func updateDraft() async {
        let draftMessage = DraftMessage(
            date: Int(Date.now.timeIntervalSince1970),
            inputMessageText: .inputMessageText(
                .init(
                    clearDraft: true,
                    disableWebPagePreview: true,
                    text: FormattedText(
                        entities: [],
                        text: text
                    )
                )
            ),
            replyToMessageId: replyMessage?.message.id ?? 0
        )
        
        await tdSetChatDraftMessage(draftMessage)
    }
    
    // MARK: - Scroll -
    
    func scrollToLast() {
        guard let lastId = messages.last?.message.id,
              let scrollViewProxy
        else { return }
        
        withAnimation {
            scrollViewProxy.scrollTo(lastId, anchor: .bottom)
        }
    }
    
    func scrollTo(id: Int64?, anchor: UnitPoint = .center) {
        guard let scrollViewProxy, let id else { return }
        
        withAnimation {
            scrollViewProxy.scrollTo(id, anchor: anchor)
            highlightedMessageId = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                self.highlightedMessageId = nil
            }
        }
    }
}
