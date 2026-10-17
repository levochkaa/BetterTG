// RootVM+Publishers.swift

import Combine
import Foundation
import TDLibKit
import UserNotifications

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
            .authorizationStateWaitEmailAddress,
            .authorizationStateWaitEmailCode,
            .authorizationStateWaitOtherDeviceConfirmation,
            .authorizationStateWaitRegistration,
            .authorizationStateWaitPremiumPurchase,
        ]) { [weak self] _ in
            self?.synchronizeAuthorization()
        }
        // Telegram's app badge counts the active account's unread messages outside muted chats (the default
        // Badge Counter settings).
        nc.scopedPublisher(&cancellables, for: .updateUnreadMessageCount) { event in
            guard case .chatListMain = event.value.chatList,
                  event.source == TDLib.shared.activeUpdateSource else { return }
            let count = event.value.unreadUnmutedCount
            UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { error in
                if let error { log("App badge update failed: \(error.localizedDescription)") }
            }
        }
        nc.scopedPublisher(&cancellables, for: .updateDiceEmojis) { event in
            DiceEmojiStore.update(event.value.emojis, clientID: event.source.clientID)
        }
        nc.scopedPublisher(&cancellables, for: .updateOption) { event in
            guard event.value.name == MessageQuoteLengthStore.optionName else { return }
            let length: Int64? =
                if case .optionValueInteger(let value) = event.value.value {
                    value.value
                } else {
                    nil
                }
            MessageQuoteLengthStore.update(length, clientID: event.source.clientID)
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
        let ownsActiveAccount = activeAccountID == TDLib.shared.activeAccountID
        let ready = ownsActiveAccount && TDLib.shared.isActiveAccountReady
        // A foreground restore renews the same account's client; until it reports a real state, keep the shell.
        if !ready, loggedIn, activeAccountID != nil, activeAccountID == TDLib.shared.renewingAccountID { return }
        // An account switch keeps the shell as well, with the new account's list loading, while that account's client
        // starts; Telegram shows its chat list then. Only an account without a session gets the sign-in screen (L-9).
        loggedIn = ready || ownsActiveAccount && TDLib.shared.activeAccountIsStarting
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
        // Returning from the background renews the same account's client. Telegram's list never empties then, so
        // keep the rows on screen, and their scroll position, until the new client lists them again.
        if !accountChanged, allFolders.contains(where: { !$0.chats.isEmpty }) {
            beginChatListRenewalHold()
        } else {
            endChatListRenewalHold()
            scopeNotificationSettings = [:]
            folders = []
            archive = nil
        }
        if accountChanged { resetHiddenFolders() }
        if accountChanged { currentFolder = nil }
        ensureBaseChatLists()
        if store.folderConfiguration != nil { loadFolderConfiguration() }
        // A renewing client keeps `loggedIn` before it is ready; its ready notification starts the loads.
        guard loggedIn, TDLib.shared.isActiveAccountReady else { return }
        loadScopeNotificationSettings()
        allFolders.forEach { self.loadMoreChats(in: $0) }
    }

    private func beginChatListRenewalHold() {
        renewalHeldFolderIDs = Set(allFolders.map(\.id))
        // The previous client's loads were cancelled mid-flight and never cleared their state.
        for folder in allFolders {
            folder.isLoading = false
            folder.hasMoreChats = true
            folder.loadError = nil
            folder.chats.forEach { $0.isHeldThroughClientRenewal = true }
        }
        renewalHoldTask?.cancel()
        renewalHoldTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.endChatListRenewalHold()
        }
    }

    /// Ends the hold for one list, or for all of them, and drops the rows the new client no longer lists.
    func endChatListRenewalHold(folderID: Int? = nil) {
        if let folderID {
            guard renewalHeldFolderIDs.remove(folderID) != nil else { return }
        } else {
            guard !renewalHeldFolderIDs.isEmpty else { return }
            renewalHeldFolderIDs = []
        }
        if renewalHeldFolderIDs.isEmpty {
            renewalHoldTask?.cancel()
            renewalHoldTask = nil
        }
        synchronizeChatLists()
        // A row the renewed client never listed again is dropped above, or stays only while its list is held.
        for folder in allFolders where !renewalHeldFolderIDs.contains(folder.id) {
            folder.chats.forEach { $0.isHeldThroughClientRenewal = false }
        }
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
            var newFolders = [CustomFolder]()
            for info in configuration.chatFolders where !hiddenFolderIDs.contains(info.id) {
                guard let definition = try? await client.getChatFolder(chatFolderId: info.id) else { continue }
                guard !Task.isCancelled, folderConfigurationGeneration == generation,
                      activeAccountID == accountID, td.id == client.id else { return }
                // An existing folder keeps its object, so its page, rows and loads stay; Telegram updates a folder
                // tab in place when its definition changes.
                if let previous = folders.first(where: { $0.id == Int(info.id) }) {
                    previous.update(info: info, definition: definition)
                    loadedFolders.append(previous)
                } else {
                    let folder = CustomFolder(chats: [], type: .folder(info, definition))
                    loadedFolders.append(folder)
                    newFolders.append(folder)
                }
            }
            guard !Task.isCancelled, folderConfigurationGeneration == generation,
                  activeAccountID == accountID, td.id == client.id,
                  let main = folders.first(where: { $0.id == 0 }) else { return }
            loadedFolders.insert(main, at: min(max(0, configuration.mainChatListPosition), loadedFolders.count))
            // Only removed folders stop loading.
            let keptIDs = Set(loadedFolders.map(\.id) + [archive?.id].compactMap(\.self))
            for (id, task) in folderLoadTasks where !keptIDs.contains(id) {
                task.cancel()
                folderLoadTasks[id] = nil
            }
            for folder in allFolders where !keptIDs.contains(folder.id) {
                folder.isLoading = false
            }
            folders = loadedFolders
            synchronizeChatLists()
            if currentFolder == nil || !folders.contains(where: { $0.id == self.currentFolder }) {
                currentFolder = folders.first?.id
            }
            // A page loads its next chats when it needs them; only new folders and empty lists load now.
            if loggedIn {
                for folder in allFolders where newFolders.contains(where: { $0 === folder }) || folder.chats.isEmpty {
                    loadMoreChats(in: folder)
                }
            }
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
                    // A renewing client has not listed this chat yet.
                    if renewalHeldFolderIDs.contains(folder.id) { continue }
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
                    // A held list keeps its order until the renewed client's order is complete, so rows do not
                    // swap while positions arrive one update at a time.
                    if !renewalHeldFolderIDs.contains(folder.id) { existing.position = latest.position }
                    existing.unreadCount = latest.unreadCount
                    existing.lastMessage = latest.lastMessage
                    existing.draftMessage = latest.draftMessage
                    existing.type = latest.type
                    existing.isHeldThroughClientRenewal = false
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
        // The shell of a starting account loads nothing before its client is ready; the ready notification loads.
        guard loggedIn, TDLib.shared.isActiveAccountReady, allFolders.contains(where: { $0 === folder }),
              !folder.isLoading, folder.hasMoreChats else { return }
        let client = td
        let accountID = activeAccountID
        // A renewal reloads what the list showed; later pages load as the user scrolls.
        let renewing = renewalHeldFolderIDs.contains(folder.id)
        let desiredCount = renewing ? max(folder.chats.count, 1) : folder.chats.count + 100
        let loadedCount = { [weak folder] in
            guard let folder else { return Int.max }
            return renewing
                ? TelegramChatListStore.shared.chatIDs(in: folder.chatList).count
                : folder.chats.count
        }
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
            while !Task.isCancelled, loadedCount() < desiredCount {
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
                        break
                    } else {
                        folder.loadError = error.localizedDescription
                        return
                    }
                }
            }
            if renewing, !Task.isCancelled {
                await endChatListRenewalHoldOnceStored(
                    folder,
                    client: client,
                    accountID: accountID,
                    limit: desiredCount,
                )
            }
        }
    }

    /// TDLib answers `loadChats` before this app has consumed the updates it sent first, so ending the hold on the
    /// answer dropped every held row the store did not have yet: the list collapsed to a few dozen rows, lost its
    /// position, and grew back one row at a time. The store also fills its positions one update at a time, so rows
    /// it has can still stand in an interim order that swaps pinned rows and back. The hold now ends once the store
    /// lists every held chat that the renewed client still lists, in the client's order, or at the hold's deadline.
    private func endChatListRenewalHoldOnceStored(
        _ folder: CustomFolder, client: TDLibClient, accountID: UUID?, limit: Int,
    ) async {
        let heldIDs = Set(folder.chats.map(\.id))
        let store = TelegramChatListStore.shared
        var checks = 0
        var awaitedIDs = [Int64]()
        while !Task.isCancelled, renewalHeldFolderIDs.contains(folder.id), activeAccountID == accountID,
              td.id == client.id
        {
            // A message arriving meanwhile reorders the list for real, so the client's order is read again.
            if checks % 16 == 0 {
                let listedIDs = await (try? client.getChats(chatList: folder.chatList, limit: limit).chatIds) ?? []
                awaitedIDs = listedIDs.filter { heldIDs.contains($0) }
                guard !Task.isCancelled, activeAccountID == accountID, td.id == client.id else { return }
            }
            checks += 1
            let awaited = Set(awaitedIDs)
            let storedIDs = store.chatIDs(in: folder.chatList).filter {
                awaited.contains($0) && store.listsChat(id: $0, in: folder.chatList)
            }
            if storedIDs == awaitedIDs { break }
            try? await Task.sleep(for: .milliseconds(32))
        }
        guard !Task.isCancelled, activeAccountID == accountID, td.id == client.id else { return }
        endChatListRenewalHold(folderID: folder.id)
    }
}
