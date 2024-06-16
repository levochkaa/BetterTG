// ChatView.swift

import SwiftUI
import TDLibKit
import PhotosUI
import Combine

// swiftlint:disable:next type_body_length
struct ChatView: View {
    @State var customChat: CustomChat
    
    @FocusState var focused
    
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    @State var highlightedMessageId: Int64?
    @State var messages = [CustomMessage]()
    @State var loadingMessagesTask: Task<Void, Never>?
    
    @State var editCustomMessage: CustomMessage?
    @State var replyMessage: CustomMessage?
    
    // Scroll
    let chatScrollNamespaceId = "chatScrollNamespaceId"
    @State var scrollOnFocus = true
    @State var showScrollToBottomButton = false
    @State var scrollViewProxy: ScrollViewProxy?
    
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            bodyView.onAppear { self.scrollViewProxy = scrollViewProxy }
        }
        .overlay {
            if customChat.lastMessage == nil {
                Text("No messages")
                    .center(.vertically)
                    .fullScreenBackground(color: .black)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isPreview {
                ChatBottomArea(
                    customChat: $customChat,
                    editCustomMessage: $editCustomMessage,
                    replyMessage: $replyMessage,
                    focused: $focused,
                    scrollTo: { id in scrollTo(id: id) }
                )
            }
        }
        .dropDestination(for: SelectedImage.self) { items, _ in
            nc.post(name: .localOnSelectedImagesDrop, object: Array(items.prefix(10)))
            return true
        }
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ChatToolbar(customChat: $customChat))
        .task {
            guard let draftMessage = customChat.draftMessage else { return }
            let replyMessage = await getInputReplyToMessage(draftMessage.replyTo)
            withAnimation { self.replyMessage = replyMessage }
        }
        .onAppear { try? td.openChat(chatId: customChat.chat.id) { _ in } }
        .onDisappear { try? td.closeChat(chatId: customChat.chat.id) { _ in } }
        .onAppear { Media.shared.onChatOpen(title: customChat.chat.title) }
        .onDisappear { Media.shared.onChatDismiss() }
        .onAppear(perform: setPublishers)
        .onAppear(perform: loadMessages)
    }
    
    var bodyView: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach($messages) { $customMessage in
                    HStack(spacing: 0) {
                        if customMessage.message.isOutgoing { Spacer(minLength: 0) }
                        
                        MessageView(
                            customMessage: $customMessage,
                            highlightedMessageId: $highlightedMessageId,
                            replyMessage: $replyMessage,
                            editCustomMessage: $editCustomMessage,
                            scrollTo: { id in scrollTo(id: id) },
                            deleteMessage: { id, deleteForBoth in
                                Task.background { await deleteMessage(id: id, deleteForBoth: deleteForBoth) }
                            }
                        )
                        .frame(
                            maxWidth: Utils.maxMessageContentWidth,
                            alignment: customMessage.message.isOutgoing ? .trailing : .leading
                        )
                        .onVisible {
                            viewMessage(id: customMessage.message.id)
                        }
                        
                        if !customMessage.message.isOutgoing { Spacer(minLength: 0) }
                    }
                    .padding(customMessage.message.isOutgoing ? .trailing : .leading, 16)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top),
                            removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading)
                        )
                        .combined(with: .opacity)
                    )
                    .flipped()
                }
            }
            .overlay {
                GeometryReader { geometryProxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometryProxy.frame(in: .named(chatScrollNamespaceId))
                    )
                }
            }
        }
        .background(.black)
        .flipped()
        .coordinateSpace(name: chatScrollNamespaceId)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            let maxY = Int(value.maxY)
            if maxY > 670 {
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
        .onTapGesture { focused = false }
        .overlay(alignment: .bottomTrailing) {
            if showScrollToBottomButton {
                scrollToBottomButton
            }
        }
    }
    
    @ViewBuilder var scrollToBottomButton: some View {
        Image(systemName: "chevron.down")
            .offset(y: 1)
            .font(.title3)
            .padding(10)
            .background(.black)
            .clipShape(.circle)
            .overlay {
                Circle()
                    .stroke(.blue, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if customChat.unreadCount != 0 {
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Text("\(customChat.unreadCount)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.5)
                        }
                        .offset(y: -5)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .scale).combined(with: .opacity))
            .padding(.trailing)
            .padding(.bottom, 5)
            .onTapGesture(perform: scrollToLast)
    }
    
    private func setPublishers() {
        nc.publisher(&cancellables, for: .localScrollToLastOnFocus) { _ in
            guard scrollOnFocus else { return }
            Task.main { scrollToLast() }
        }
        nc.publisher(&cancellables, for: .updateNewMessage) { notification in
            guard let updateNewMessage = notification.object as? UpdateNewMessage,
                  updateNewMessage.message.chatId == customChat.chat.id
            else { return }
            self.updateNewMessage(updateNewMessage)
        }
        nc.publisher(&cancellables, for: .updateDeleteMessages) { notification in
            guard let updateDeleteMessages = notification.object as? UpdateDeleteMessages,
                  updateDeleteMessages.chatId == customChat.chat.id
            else { return }
            self.updateDeleteMessages(updateDeleteMessages)
        }
        nc.publisher(&cancellables, for: .updateChatReadInbox) { notification in
            guard let updateChatReadInbox = notification.object as? UpdateChatReadInbox,
                  updateChatReadInbox.chatId == customChat.chat.id
            else { return }
            Task.main { customChat.unreadCount = updateChatReadInbox.unreadCount }
        }
        nc.publisher(&cancellables, for: .updateMessageEdited) { notification in
            guard let updateMessageEdited = notification.object as? UpdateMessageEdited,
                  updateMessageEdited.chatId == customChat.chat.id
            else { return }
            self.updateMessageEdited(updateMessageEdited)
        }
        nc.publisher(&cancellables, for: .updateMessageSendSucceeded) { notification in
            guard let updateMessageSendSucceeded = notification.object as? UpdateMessageSendSucceeded,
                  updateMessageSendSucceeded.message.chatId == customChat.chat.id
            else { return }
            self.updateMessageSendSucceeded(updateMessageSendSucceeded)
        }
    }
    
    func tdSendChatAction(_ chatAction: ChatAction) async throws {
        try await td.sendChatAction(
            action: chatAction,
            businessConnectionId: nil,
            chatId: customChat.chat.id,
            messageThreadId: 0
        )
    }
    
    private func scrollToLast() {
        guard let lastId = messages.first?.id, let scrollViewProxy else { return }
        withAnimation { scrollViewProxy.scrollTo(lastId, anchor: .bottom) }
    }
    
    private func scrollTo(id: Int64?, anchor: UnitPoint = .center) {
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
    
    func updateMessageSendSucceeded(_ updateMessageSendSucceeded: UpdateMessageSendSucceeded) {
        let message = updateMessageSendSucceeded.message
        let oldMessageId = updateMessageSendSucceeded.oldMessageId
        
        if message.mediaAlbumId == 0 {
            guard let index = messages.firstIndex(where: { $0.message.id == oldMessageId  }) else { return }
            Task.background {
                let customMessage = await getCustomMessage(from: message)
                await main {
                    withAnimation {
                        messages[index] = customMessage
                    }
                }
            }
        } else {
            messages.enumerated().forEach { outerIndex, outerMessage in
                outerMessage.album.enumerated().forEach { innerIndex, innerMessage in
                    guard innerMessage.id == oldMessageId else { return }
                    withAnimation {
                        messages[outerIndex].album[innerIndex] = message
                    }
                    nc.post(name: .localScrollToLastOnFocus)
                }
            }
        }
    }
    
    func updateDeleteMessages(_ updateDeleteMessages: UpdateDeleteMessages) {
        if updateDeleteMessages.fromCache || !updateDeleteMessages.isPermanent { return }
        
        Task.main(delay: 0.5) {
            withAnimation {
                self.messages.removeAll { customMessage in
                    updateDeleteMessages.messageIds.contains(customMessage.message.id)
                }
            }
        }
    }
    
    func updateNewMessage(_ updateNewMessage: UpdateNewMessage) {
        let message = updateNewMessage.message
        Task.background {
            let customMessage = await getCustomMessage(from: message)
            if message.mediaAlbumId == 0 {
                await main {
                    withAnimation {
                        self.messages.add(customMessage)
                    }
                }
            } else {
                if let index = await messages.firstIndex(where: {
                    $0.message.mediaAlbumId == message.mediaAlbumId
                }) {
                    await main {
                        withAnimation {
                            messages[index].album.append(customMessage.message)
                        }
                    }
                } else {
                    await main {
                        withAnimation {
                            messages.add(customMessage)
                        }
                    }
                }
            }
            nc.post(name: .localScrollToLastOnFocus)
        }
    }
    
    func updateMessageEdited(_ updateMessageEdited: UpdateMessageEdited) {
        if let index = self.messages.firstIndex(where: { $0.message.id == updateMessageEdited.messageId }) {
            Task.background {
                guard let customMessage = await getCustomMessage(fromId: updateMessageEdited.messageId) else { return }
                
                await main {
                    withAnimation {
                        messages[index] = customMessage
                        
                        if updateMessageEdited.messageId == replyMessage?.message.id {
                            replyMessage = customMessage
                        }
                    }
                }
            }
        }
        
        let indices = self.messages.enumerated().compactMap { index, customMessage in
            return customMessage.replyToMessage?.id == updateMessageEdited.messageId ? index : nil
        }
        guard !indices.isEmpty else { return }
        Task.background {
            let reply = try? await td.getMessage(chatId: customChat.chat.id, messageId: updateMessageEdited.messageId)
            await main {
                for index in indices {
                    withAnimation {
                        messages[index].replyToMessage = reply
                    }
                }
            }
        }
    }
    
    func loadMessages() {
        guard loadingMessagesTask == nil else { return }
        loadingMessagesTask = Task.background(priority: .high) { await _loadMessages() }
    }
    
    private func _loadMessages() async {
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
                    var newMessage = customMessage
                    newMessage.album = [customMessage.message]
                    savedMessages.append(newMessage)
                }
            } else {
                savedMessages.append(customMessage)
            }
        }
        
        await main { [savedMessages] in
            messages.append(contentsOf: savedMessages)
            
            Task.main(delay: 0.5) {
                loadingMessagesTask = nil
            }
        }
    }
    
    func deleteMessage(id: Int64, deleteForBoth: Bool) async {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        
        if customMessage.album.isEmpty {
            _ = try? await td.deleteMessages(chatId: customChat.chat.id, messageIds: [id], revoke: deleteForBoth)
        } else {
            let ids = customMessage.album.map { $0.id }
            _ = try? await td.deleteMessages(chatId: customChat.chat.id, messageIds: ids, revoke: deleteForBoth)
        }
    }
    
    func viewMessage(id: Int64) {
        Task.background {
            try await td.viewMessages(
                chatId: customChat.chat.id,
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
        var customMessage = CustomMessage(
            message: message,
            replyToMessage: replyToMessage,
            forwardedFrom: await getForwardedFrom(message.forwardInfo?.origin)
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
            return message.chatId == 0 ? await getCustomMessage(fromId: message.messageId) : nil
        }
        return nil
    }
}

// swiftlint:disable:this file_length
