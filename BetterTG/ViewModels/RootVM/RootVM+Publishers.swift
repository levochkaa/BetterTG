// RootVM+Publishers.swift

import Combine
import TDLibKitDynamic

extension RootVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .activeTelegramAccountChanged) { [weak self] _ in
            guard let self else { return }
            activeAccountID = TDLib.shared.activeAccountID
            loggedIn = TDLib.shared.isActiveAccountReady
            scopeNotificationSettings = [:]
            folders = []
            archive = nil
            currentFolder = nil
        }
        nc.publisher(&cancellables, for: .updateChatFolders) { [weak self] update in
            self?.updateChatFolders(update)
        }
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            guard let self else { return }
            loggedIn = true
            loadScopeNotificationSettings()
        }
        nc.mergeMany(&cancellables, [
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
            .authorizationStateWaitPhoneNumber,
            .authorizationStateWaitCode,
            .authorizationStateWaitPassword,
        ]) { [weak self] _ in
            self?.loggedIn = false
        }
        nc.publisher(&cancellables, for: .updateChatReadInbox) { [weak self] update in
            guard let self else { return }
            for folder in allFolders {
                folder.chats.first(where: { $0.id == update.chatId })?.unreadCount = update.unreadCount
            }
        }
        nc.publisher(&cancellables, for: .updateNewChat) { [weak self] update in
            self?.updateNewChat(update)
        }
        nc.publisher(&cancellables, for: .updateChatPosition) { [weak self] update in
            self?.updateChatPosition(update)
        }
        nc.publisher(&cancellables, for: .updateChatDraftMessage) { [weak self] update in
            self?.updateChatDraftMessage(update)
        }
        nc.publisher(&cancellables, for: .updateChatLastMessage) { [weak self] update in
            self?.updateChatLastMessage(update)
        }
        nc.publisher(&cancellables, for: .updateChatTitle) { [weak self] update in
            self?.refreshChat(id: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateChatPhoto) { [weak self] update in
            self?.refreshChat(id: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateChatNotificationSettings) { [weak self] update in
            self?.refreshChat(id: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateChatIsMarkedAsUnread) { [weak self] update in
            self?.refreshChat(id: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateScopeNotificationSettings) { [weak self] update in
            guard let self else { return }
            var updatedSettings = scopeNotificationSettings
            updatedSettings[update.scope] = update.notificationSettings
            scopeNotificationSettings = updatedSettings
        }
        nc.publisher(&cancellables, for: .updateUnreadChatCount) { update in
            FolderUnreadStore.shared.update(update, clientID: td.id)
        }
    }

    func updateChatFolders(_ update: UpdateChatFolders) {
        let sourceAccountID = activeAccountID
        Task { [weak self] in
            guard let self else { return }
            var newFolders = await update.chatFolders.asyncCompactMap { await self.getCustomFolder(from: $0) }
            let mainChats = await getCustomChats(for: .chatListMain) ?? []
            let archiveChats = await getCustomChats(for: .chatListArchive) ?? []
            guard sourceAccountID == activeAccountID else { return }
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
            addChatIfNeeded(id: update.chat.id, position: position)
        }
    }

    func updateChatPosition(_ update: UpdateChatPosition) {
        defer { refreshChat(id: update.chatId) }
        guard let folder = allFolders.first(where: { $0.chatList == update.position.list }) else { return }
        guard update.position.order != 0 else {
            folder.chats.removeAll(where: { $0.id == update.chatId })
            return
        }
        if let chat = folder.chats.first(where: { $0.id == update.chatId }) {
            chat.position = update.position
        } else {
            addChatIfNeeded(id: update.chatId, position: update.position)
        }
    }

    func updateChatDraftMessage(_ update: UpdateChatDraftMessage) {
        for folder in allFolders {
            guard let chat = folder.chats.first(where: { $0.id == update.chatId }),
                  let position = update.positions.first(folder.chatList)
            else { continue }
            chat.draftMessage = update.draftMessage
            chat.position = position
        }
    }

    func updateChatLastMessage(_ update: UpdateChatLastMessage) {
        for folder in allFolders {
            guard let chat = folder.chats.first(where: { $0.id == update.chatId }),
                  let position = update.positions.first(folder.chatList)
            else { continue }
            chat.lastMessage = update.lastMessage
            chat.position = position
        }
    }

    private func addChatIfNeeded(id: Int64, position: ChatPosition) {
        guard let folder = allFolders.first(where: { $0.chatList == position.list }),
              !folder.chats.contains(where: { $0.id == id })
        else { return }
        Task { [weak self, weak folder] in
            guard let self, let folder,
                  let chat = await getCustomChat(from: id, for: position.list),
                  !folder.chats.contains(where: { $0.id == id })
            else { return }
            folder.chats.append(chat)
        }
    }

    private func refreshChat(id: Int64) {
        Task { [weak self] in
            guard let self, let latest = try? await td.getChat(chatId: id) else { return }
            for folder in allFolders {
                folder.chats.first(where: { $0.id == id })?.chat = latest
            }
        }
    }
}
