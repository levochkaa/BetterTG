// RootVM+Publishers.swift

import Combine
import Foundation
import TDLibKitDynamic

extension RootVM {
    func setPublishers() {
        TDLib.shared
            .activeClientChanges
            .sink { [weak self] _ in
                self?.listAuthority.invalidate()
                self?.chatInsertions.invalidate()
            }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .activeTelegramAccountChanged) { [weak self] _ in
            guard let self else { return }
            listAuthority.invalidate()
            chatInsertions.invalidate()
            folderLoadID = nil
            chatRefreshIDs.removeAll()
            activeAccountID = TDLib.shared.activeAccountID
            loggedIn = TDLib.shared.isActiveAccountReady
            scopeNotificationSettings = [:]
            folders = []
            archive = nil
            currentFolder = nil
        }
        observeListUpdate(.updateChatFolders) { $0.updateChatFolders($1) }
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            guard let self else { return }
            synchronizeAuthorization()
            if loggedIn { loadScopeNotificationSettings() }
        }
        nc.mergeMany(&cancellables, [
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
            .authorizationStateWaitPhoneNumber,
            .authorizationStateWaitCode,
            .authorizationStateWaitPassword,
        ]) { [weak self] _ in
            self?.synchronizeAuthorization()
        }
        observeListUpdate(.updateChatReadInbox) { owner, update in
            for folder in owner.allFolders {
                folder.chats.first(where: { $0.id == update.chatId })?.unreadCount = update.unreadCount
            }
        }
        observeListUpdate(.updateNewChat) { $0.updateNewChat($1) }
        observeListUpdate(.updateChatPosition) { $0.updateChatPosition($1) }
        observeListUpdate(.updateChatDraftMessage) { $0.updateChatDraftMessage($1) }
        observeListUpdate(.updateChatLastMessage) { $0.updateChatLastMessage($1) }
        observeListUpdate(.updateChatTitle) { $0.refreshChat(id: $1.chatId) }
        observeListUpdate(.updateChatPhoto) { $0.refreshChat(id: $1.chatId) }
        observeListUpdate(.updateChatAccentColors) { $0.refreshChat(id: $1.chatId) }
        observeListUpdate(.updateChatViewAsTopics) { $0.refreshChat(id: $1.chatId) }
        nc.scopedPublisher(&cancellables, for: .updateMessageSendSucceeded) { event in
            let update = event.value
            SelectedDocumentFileStore.complete(
                accountID: event.source.accountID,
                chatID: update.message.chatId,
                messageID: update.oldMessageId,
            )
        }
        nc.scopedPublisher(&cancellables, for: .updateMessageSendFailed) { event in
            let update = event.value
            try? SelectedDocumentFileStore.replaceMessageID(
                accountID: event.source.accountID,
                chatID: update.message.chatId,
                old: update.oldMessageId,
                new: update.message.id,
            )
        }
        nc.scopedPublisher(&cancellables, for: .updateDeleteMessages) { event in
            let update = event.value
            guard !update.fromCache, update.isPermanent else { return }
            for messageID in update.messageIds {
                SelectedDocumentFileStore.complete(
                    accountID: event.source.accountID,
                    chatID: update.chatId,
                    messageID: messageID,
                )
            }
        }
        observeListUpdate(.updateUser) { owner, update in
            for folder in owner.allFolders {
                for chat in folder.chats where chat.user?.id == update.user.id {
                    chat.updatePrivateUser(update.user)
                }
            }
        }
        observeListUpdate(.updateChatNotificationSettings) { $0.refreshChat(id: $1.chatId) }
        observeListUpdate(.updateChatIsMarkedAsUnread) { $0.refreshChat(id: $1.chatId) }
        observeListUpdate(.updateScopeNotificationSettings) { owner, update in
            var updatedSettings = owner.scopeNotificationSettings
            updatedSettings[update.scope] = update.notificationSettings
            owner.scopeNotificationSettings = updatedSettings
        }
        nc.scopedPublisher(&cancellables, for: .updateUnreadChatCount) { [weak self] event in
            guard let self, acceptsListUpdate(event.source) else { return }
            FolderUnreadStore.shared.update(event.value, clientID: event.source.clientID)
        }
    }

    private func acceptsListUpdate(_ source: TdUpdateSource) -> Bool {
        listAuthority.accepts(source, ownerAccountID: activeAccountID, activeSource: TDLib.shared.activeUpdateSource)
    }

    private func observeListUpdate<Value>(
        _ notification: TdNotification<Value>,
        perform: @escaping (RootVM, Value) -> Void,
    ) {
        nc.scopedPublisher(&cancellables, for: notification) { [weak self] event in
            guard let self, acceptsListUpdate(event.source) else { return }
            perform(self, event.value)
        }
    }

    private func synchronizeAuthorization() {
        // Legacy void auth notifications are wakeups, never authority for the
        // account that happens to own this root when main-queue delivery occurs.
        loggedIn = activeAccountID == TDLib.shared.activeAccountID && TDLib.shared.isActiveAccountReady
    }

    func updateChatFolders(_ update: UpdateChatFolders) {
        guard let (ticket, client) = captureListRequest() else { return }
        let requestID = UUID()
        folderLoadID = requestID
        Task { [weak self] in
            guard let self else { return }
            var newFolders = await update.chatFolders.asyncCompactMap { info -> CustomFolder? in
                guard self.acceptsListRequest(ticket), self.folderLoadID == requestID else { return nil }
                return await self.getCustomFolder(from: info, client: client)
            }
            guard acceptsListRequest(ticket), folderLoadID == requestID else { return }
            let mainChats = await getCustomChats(for: .chatListMain, client: client) ?? []
            guard acceptsListRequest(ticket), folderLoadID == requestID else { return }
            let archiveChats = await getCustomChats(for: .chatListArchive, client: client) ?? []
            guard acceptsListRequest(ticket), folderLoadID == requestID else { return }
            let mainFolder = CustomFolder(chats: mainChats, type: .main)
            let archiveFolder = CustomFolder(chats: archiveChats, type: .archive)
            let insertionIndex = min(max(update.mainChatListPosition, 0), newFolders.count)
            newFolders.insert(mainFolder, at: insertionIndex)
            folders = newFolders
            archive = archiveFolder
            if currentFolder == nil || !newFolders.contains(where: { $0.id == self.currentFolder }) {
                currentFolder = newFolders.first?.id
            }
        }
    }

    func updateNewChat(_ update: UpdateNewChat) {
        for position in update.chat.positions where position.order != 0 {
            applyChatPosition(id: update.chat.id, position: position)
        }
    }

    func updateChatPosition(_ update: UpdateChatPosition) {
        defer { refreshChat(id: update.chatId) }
        applyChatPosition(id: update.chatId, position: update.position)
    }

    func updateChatDraftMessage(_ update: UpdateChatDraftMessage) {
        for folder in allFolders {
            folder.chats.first(where: { $0.id == update.chatId })?.draftMessage = update.draftMessage
            applyChatPosition(
                id: update.chatId,
                position: RootChatInsertion.position(in: update.positions, for: folder.chatList),
            )
        }
    }

    func updateChatLastMessage(_ update: UpdateChatLastMessage) {
        for folder in allFolders {
            folder.chats.first(where: { $0.id == update.chatId })?.lastMessage = update.lastMessage
            applyChatPosition(
                id: update.chatId,
                position: RootChatInsertion.position(in: update.positions, for: folder.chatList),
            )
        }
    }

    private func applyChatPosition(id: Int64, position: ChatPosition) {
        guard let folder = allFolders.first(where: { $0.chatList == position.list }),
              let (ticket, client) = captureListRequest()
        else { return }
        chatInsertions.apply(
            source: ticket.source, chatID: id, position: position, folder: folder,
            accepts: { [weak self, weak folder] in
                guard let self, let folder else { return false }
                return acceptsListRequest(ticket) && allFolders.contains(where: { $0 === folder })
            },
            hydrate: { [weak self] in
                await self?.getCustomChat(from: id, for: position.list, client: client)
            },
        )
    }

    private func refreshChat(id: Int64) {
        guard let (ticket, client) = captureListRequest() else { return }
        let requestID = UUID()
        chatRefreshIDs[id] = requestID
        Task { [weak self] in
            guard let self, acceptsListRequest(ticket), chatRefreshIDs[id] == requestID else { return }
            defer { if chatRefreshIDs[id] == requestID { chatRefreshIDs[id] = nil } }
            guard let latest = try? await client.getChat(chatId: id),
                  acceptsListRequest(ticket), chatRefreshIDs[id] == requestID else { return }
            for folder in allFolders {
                folder.chats.first(where: { $0.id == id })?.chat = latest
            }
        }
    }
}
