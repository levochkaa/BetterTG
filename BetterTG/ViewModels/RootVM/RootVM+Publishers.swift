// RootVM+Publishers.swift

import Combine
import Foundation
import TDLibKit

extension RootVM {
    func setPublishers() {
        TelegramChatListStore.shared
            .changes
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .reset:
                    restoreChatListContext()
                case .folders:
                    loadFolderConfiguration()
                case .chats(let ids):
                    synchronizeChatLists(changedIDs: ids)
                }
            }
            .store(in: &cancellables)
        TDLib.shared
            .activeClientChanges
            .sink { [weak self] _ in
                self?.listAuthority.invalidate()
                self?.scopeSettingsLoading.invalidate()
            }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            guard let self else { return }
            synchronizeAuthorization()
            guard loggedIn else { return }
            loadScopeNotificationSettings()
            ensureBaseChatLists()
            allFolders.forEach { self.loadMoreChats(in: $0) }
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
        nc.scopedPublisher(&cancellables, for: .updateScopeNotificationSettings) { [weak self] event in
            guard let self, acceptsListUpdate(event.source) else { return }
            let update = event.value
            scopeSettingsLoading.invalidate(scope: update.scope)
            var updatedSettings = scopeNotificationSettings
            updatedSettings[update.scope] = update.notificationSettings
            scopeNotificationSettings = updatedSettings
        }
        nc.scopedPublisher(&cancellables, for: .updateUnreadChatCount) { [weak self] event in
            guard let self, acceptsListUpdate(event.source) else { return }
            FolderUnreadStore.shared.update(event.value, clientID: event.source.clientID)
        }
    }

    private func acceptsListUpdate(_ source: TdUpdateSource) -> Bool {
        listAuthority.accepts(source, ownerAccountID: activeAccountID, activeSource: TDLib.shared.activeUpdateSource)
    }

    private func synchronizeAuthorization() {
        // Legacy void auth notifications are wakeups, never authority for the
        // account that happens to own this root when main-queue delivery occurs.
        loggedIn = activeAccountID == TDLib.shared.activeAccountID && TDLib.shared.isActiveAccountReady
    }

    func restoreChatListContext() {
        let store = TelegramChatListStore.shared
        guard store.clientID != nil else { return }
        folderLoadTasks.values.forEach { $0.cancel() }
        folderLoadTasks = [:]
        folderConfigurationTask?.cancel()
        folderConfigurationGeneration = UUID()
        listAuthority.invalidate()
        scopeSettingsLoading.invalidate()
        let accountChanged = activeAccountID != store.accountID
        activeAccountID = store.accountID
        synchronizeAuthorization()
        scopeNotificationSettings = [:]
        folders = []
        archive = nil
        if accountChanged { currentFolder = nil }
        ensureBaseChatLists()
        if store.folderConfiguration != nil { loadFolderConfiguration() }
        guard loggedIn else { return }
        loadScopeNotificationSettings()
        allFolders.forEach { self.loadMoreChats(in: $0) }
    }

    func ensureBaseChatLists() {
        if !folders.contains(where: { $0.id == 0 }) {
            let main = CustomFolder(chats: [], type: .main)
            folders.insert(main, at: 0)
        }
        if archive == nil { archive = CustomFolder(chats: [], type: .archive) }
        synchronizeChatLists()
    }

    func loadFolderConfiguration() {
        let store = TelegramChatListStore.shared
        guard let configuration = store.folderConfiguration else { return }
        let client = td
        let accountID = activeAccountID
        let generation = UUID()
        folderConfigurationGeneration = generation
        folderConfigurationTask?.cancel()
        ensureBaseChatLists()
        folderConfigurationTask = Task { [weak self] in
            guard let self else { return }
            var loadedFolders = [CustomFolder]()
            for info in configuration.chatFolders {
                guard let definition = try? await client.getChatFolder(chatFolderId: info.id) else { continue }
                guard !Task.isCancelled, folderConfigurationGeneration == generation,
                      activeAccountID == accountID, td.id == client.id else { return }
                let folder = CustomFolder(chats: [], type: .folder(info, definition))
                if let previous = folders.first(where: { $0.id == folder.id }) {
                    folder.chats = previous.chats
                }
                loadedFolders.append(folder)
            }
            guard !Task.isCancelled, folderConfigurationGeneration == generation,
                  activeAccountID == accountID, td.id == client.id,
                  let main = folders.first(where: { $0.id == 0 }) else { return }
            loadedFolders.insert(main, at: min(max(0, configuration.mainChatListPosition), loadedFolders.count))
            folderLoadTasks.values.forEach { $0.cancel() }
            folderLoadTasks = [:]
            allFolders.forEach { $0.isLoading = false }
            folders = loadedFolders
            synchronizeChatLists()
            if currentFolder == nil || !folders.contains(where: { $0.id == self.currentFolder }) {
                currentFolder = folders.first?.id
            }
            if loggedIn { allFolders.forEach { self.loadMoreChats(in: $0) } }
        }
    }

    func synchronizeChatLists(changedIDs: Set<Int64>? = nil) {
        let store = TelegramChatListStore.shared
        guard activeAccountID == store.accountID, store.clientID == td.id else { return }
        for folder in allFolders {
            let ids = changedIDs ?? Set(store.chatIDs(in: folder.chatList)).union(folder.chats.map(\.id))
            var updated = folder.chats
            var membershipChanged = false
            for id in ids {
                guard let latest = store.customChat(id: id, in: folder.chatList) else {
                    if updated.contains(where: { $0.id == id }) {
                        updated.removeAll { $0.id == id }
                        membershipChanged = true
                    }
                    continue
                }
                #if DEBUG
                ChatListStoreDebugProbe.runIfRequested(seed: latest)
                CustomEmojiTextDebugProbe.runIfRequested()
                LivePhotoDebugProbe.runIfRequested()
                SavedMediaDebugProbe.runIfRequested(chat: latest)
                ParityFixtureDebugProbe.runIfRequested(chat: latest)
                #endif
                if let existing = updated.first(where: { $0.id == id }) {
                    existing.chat = latest.chat
                    existing.position = latest.position
                    existing.unreadCount = latest.unreadCount
                    existing.lastMessage = latest.lastMessage
                    existing.draftMessage = latest.draftMessage
                    existing.type = latest.type
                    folder.chatDidChange.send(id)
                } else {
                    updated.append(latest)
                    membershipChanged = true
                }
            }
            if membershipChanged {
                folder.chats = updated.sorted {
                    $0.position.order == $1.position.order ? $0.id > $1.id : $0.position.order > $1.position.order
                }
            }
        }
    }

    func loadMoreChats(in folder: CustomFolder) {
        guard loggedIn, allFolders.contains(where: { $0 === folder }),
              !folder.isLoading, folder.hasMoreChats else { return }
        let client = td
        let accountID = activeAccountID
        let desiredCount = folder.chats.count + 100
        folder.isLoading = true
        folder.loadError = nil
        let generation = folderConfigurationGeneration
        folderLoadTasks[folder.id] = Task { [weak self, weak folder] in
            guard let self, let folder else { return }
            defer {
                if !Task.isCancelled, generation == folderConfigurationGeneration,
                   allFolders.contains(where: { $0 === folder })
                {
                    folder.isLoading = false
                    folderLoadTasks[folder.id] = nil
                }
            }
            while !Task.isCancelled, folder.chats.count < desiredCount {
                guard activeAccountID == accountID, td.id == client.id,
                      generation == folderConfigurationGeneration,
                      allFolders.contains(where: { $0 === folder }) else { return }
                do {
                    _ = try await client.send(TDNativeRequests.loadChats(chatList: folder.chatList, limit: 100))
                    await Task.yield()
                } catch {
                    guard !Task.isCancelled, activeAccountID == accountID, td.id == client.id else { return }
                    if let error = error as? TDLibError, error.code == 404 {
                        folder.hasMoreChats = false
                    } else {
                        folder.loadError = error.localizedDescription
                    }
                    return
                }
            }
        }
    }
}
