// ChatVM+Publishers.swift

import Combine
import Foundation
import TDLibKit

extension ChatVM {
    func setPublishers() {
        // Install the receipt listener before issuing the current-client baseline read.
        observeCurrentUpdate(.updateChatReadOutbox) { [weak self] update, authority in
            self?.receiveDeliveryReceipt(update, authority: authority)
        }
        TDLib.shared
            .activeClientChanges
            .sink { [weak self] source in
                guard let self, !source.matches(location) else { return }
                retireDeliveryReceipts()
            }
            .store(in: &cancellables)
        observeCurrentUpdate(.updateConnectionState) { [weak self] update, _ in
            guard case .connectionStateReady = update.state else { return }
            self?.retryMessageRefresh()
            self?.loadDeliveryReceiptIfNeeded()
        }
        observeCurrentUpdate(.updateChatReadInbox) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.chatId == customChat.id else { return }
            customChat.unreadCount = update.unreadCount
        }
        observeCurrentUpdate(.updateNewMessage) { [weak self] update, authority in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateNewMessage(update, authority: authority)
        }
        observeCurrentUpdate(.updateDeleteMessages) { [weak self] update, authority in
            guard let self else { return }
            if update.chatId == customChat.id {
                updateDeleteMessages(update, authority: authority)
                if !update.fromCache,
                   update.isPermanent,
                   supportsPinnedMessages,
                   TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage.map({ update.messageIds.contains($0.id) }) == true
                {
                    applyPermanentPinnedMessageDeletion(update.messageIds)
                }
            }
            guard !update.fromCache else { return }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: Set(update.messageIds), authority: authority)
            if update.isPermanent {
                invalidateDeletedForwardTargets(chatID: update.chatId, messageIDs: Set(update.messageIds))
            }
        }
        observeCurrentUpdate(.updateMessageEdited) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            if update.chatId == customChat.id {
                updateMessageEdited(update, authority: authority)
                if TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage?.id == update.messageId
                {
                    refreshPinnedMessages()
                }
            }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: [update.messageId], authority: authority)
        }
        observeCurrentUpdate(.updateMessageContent) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            if update.chatId == customChat.id {
                refreshMessage(id: update.messageId, authority: authority)
                if TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage?.id == update.messageId
                {
                    refreshPinnedMessages()
                }
            }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: [update.messageId], authority: authority)
        }
        observeCurrentUpdate(.updateMessageInteractionInfo) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            notePartialMessageUpdate([update.messageId])
            messages.first(where: { $0.id == update.messageId })?.reactions = update.interactionInfo?.reactions
        }
        observeCurrentUpdate(.updateMessageUnreadReactions) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            notePartialMessageUpdate([update.messageId])
            messages.first(where: { $0.id == update.messageId })?.unreadReactions = update.unreadReactions
        }
        observeCurrentUpdate(.updateMessageIsPinned) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            applyPinnedMessageUpdate(messageID: update.messageId, isPinned: update.isPinned)
        }
        observeCurrentUpdate(.updateChatPermissions) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateChatPermissions(update.permissions)
        }
        observeCurrentUpdate(.updateChatAvailableReactions) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateAvailableReactions(update.availableReactions)
        }
        observeCurrentUpdate(.updateSupergroup) { [weak self] update, _ in
            guard let self,
                  locationContextIsCurrent,
                  update.supergroup.id == customChat.supergroup?.id
            else { return }
            customChat.type = .supergroup(update.supergroup)
            refreshAllMessagesForumTopicsIfNeeded()
            refreshDeliveryStates()
            objectWillChange.send()
        }
        observeCurrentUpdate(.updateForumTopicInfo) { [weak self] update, _ in
            guard let self,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateForumTopicInfo(update.info)
        }
        observeCurrentUpdate(.updateForumTopic) { [weak self] update, authority in
            guard let self,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  update.chatId == location.chatID
            else { return }
            if isAllMessagesForum {
                receiveAllMessagesForumTopicUpdate(update, source: authority.source)
                return
            }
            guard update.forumTopicId == location.forumTopicID else { return }
            receiveForumTopicUpdate(update, authority: authority)
        }
        observeCurrentUpdate(.updateMessageSendSucceeded) { [weak self] update, authority in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateMessageSendSucceeded(update, authority: authority)
        }
        observeCurrentUpdate(.updateMessageSendFailed) { [weak self] update, authority in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateMessageSendFailed(update, authority: authority)
        }
        nc.publisher(&cancellables, for: .voiceNoteDraftResolved) { [weak self] notification in
            guard let self,
                  locationContextIsCurrent,
                  let resolution = notification.object as? VoiceNoteDraftResolution,
                  resolution.draft.destination == location.draftKey
            else { return }
            handleVoiceNoteDraftResolution(resolution)
        }
        nc.publisher(&cancellables, for: .voiceNoteDraftChanged) { [weak self] notification in
            guard let self, locationContextIsCurrent,
                  let change = notification.object as? VoiceNoteDraftChange,
                  change.destination == location.draftKey
            else { return }
            Task { [weak self] in await self?.refreshPendingVoiceDraft(id: change.draftID) }
        }
        nc.publisher(&cancellables, for: .videoNoteDraftResolved) { [weak self] notification in
            guard let self,
                  locationContextIsCurrent,
                  let resolution = notification.object as? VideoNoteDraftResolution,
                  resolution.draft.destination == location.draftKey
            else { return }
            handleVideoNoteDraftResolution(resolution)
        }
        observeCurrentUpdate(.updateUserStatus) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.userId == customChat.user?.id else { return }
            updateOnlineStatus(from: update.status)
        }
        observeCurrentUpdate(.updateChatOnlineMemberCount) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.chatId == chatID else { return }
            onlineMemberCount = update.onlineMemberCount
        }
        observeCurrentUpdate(.updateBasicGroup) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.basicGroup.id == customChat.group?.id else { return }
            memberCount = update.basicGroup.memberCount
            // The member status decides who may send (`CustomChat.allowsSending`): leaving or being promoted
            // changes the composer at once.
            if customChat.group?.status != update.basicGroup.status {
                customChat.type = .group(update.basicGroup)
                objectWillChange.send()
            }
        }
        observeCurrentUpdate(.updateBasicGroupFullInfo) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.basicGroupId == customChat.group?.id else { return }
            memberCount = update.basicGroupFullInfo.members.count
        }
        observeCurrentUpdate(.updateSupergroup) { [weak self] update, _ in
            guard let self,
                  locationContextIsCurrent,
                  update.supergroup.id == customChat.supergroup?.id,
                  update.supergroup.memberCount > 0
            else { return }
            memberCount = update.supergroup.memberCount
        }
        observeCurrentUpdate(.updateSupergroupFullInfo) { [weak self] update, _ in
            guard let self,
                  locationContextIsCurrent,
                  update.supergroupId == customChat.supergroup?.id
            else { return }
            updateSlowMode(expiresIn: update.supergroupFullInfo.slowModeDelayExpiresIn)
            if update.supergroupFullInfo.memberCount > 0 { memberCount = update.supergroupFullInfo.memberCount }
        }
        observeCurrentUpdate(.updateUserFullInfo) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.userId == customChat.user?.id else { return }
            updateRecipientNoteRestriction(update.userFullInfo.hasRestrictedVoiceAndVideoNoteMessages)
        }
        observeCurrentUpdate(.updateUser) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.update(user: update.user)
            for message in messages {
                if message.message.senderId == .messageSenderUser(.init(userId: update.user.id)) {
                    notePartialMessageUpdate([message.id])
                    message.senderUser = update.user
                }
            }
            refreshReferencedMetadata(userID: update.user.id, authority: authority)
        }
        observeCurrentUpdate(.updateChatTitle) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.invalidateChat(id: update.chatId)
            refreshReferencedMetadata(chatID: update.chatId, authority: authority)
        }
        observeCurrentUpdate(.updateChatPhoto) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.invalidateChat(id: update.chatId)
            refreshReferencedMetadata(chatID: update.chatId, authority: authority)
        }
        observeCurrentUpdate(.updateChatAction) { [weak self] update, _ in
            guard let self,
                  locationContextIsCurrent,
                  update.chatId == customChat.id,
                  isAllMessagesForum
                  ? update.topicId == acceptedChatActionTopic
                  : (location.topic == nil || update.topicId == location.topic)
            else { return }
            updateChatAction(update)
        }
    }

    private func observeCurrentUpdate<Value>(
        _ notification: TdNotification<Value>,
        perform: @escaping (Value, ChatUpdateDeliveryAuthority) -> Void,
    ) {
        ChatUpdateDeliveryAuthority.observe(
            notification, center: nc, subscriptions: &cancellables, location: location,
            currentLocation: { [weak self] in self?.location },
            currentSource: { TDLib.shared.activeUpdateSource },
            ownerIsCurrent: { [weak self] in self?.locationContextIsCurrent == true },
            perform: perform,
        )
    }

    private func acceptsUpdate(_ authority: ChatUpdateDeliveryAuthority) -> Bool {
        !Task.isCancelled && authority.permits(
            currentLocation: location, currentSource: TDLib.shared.activeUpdateSource,
            ownerIsCurrent: locationContextIsCurrent,
        )
    }

    func updateChatAction(_ update: UpdateChatAction) {
        actionStatus =
            switch update.action {
            case .chatActionTyping: L10n.telegram("DialogList.Typing")
            case .chatActionRecordingVideo: L10n.telegram("Activity.RecordingVideoMessage")
            case .chatActionUploadingVideo: L10n.telegram("Activity.UploadingVideo")
            case .chatActionRecordingVoiceNote: L10n.telegram("Activity.RecordingAudio")
            case .chatActionUploadingVoiceNote: L10n.telegram("Activity.UploadingDocument")
            case .chatActionUploadingPhoto: L10n.telegram("Activity.UploadingPhoto")
            case .chatActionUploadingDocument: L10n.telegram("Activity.UploadingDocument")
            case .chatActionChoosingSticker: L10n.telegram("Activity.ChoosingSticker")
            case .chatActionChoosingLocation: L10n.betterTG("Chat.ChoosingLocation")
            case .chatActionChoosingContact: L10n.betterTG("Chat.ChoosingContact")
            case .chatActionStartPlayingGame: L10n.telegram("Activity.PlayingGame")
            case .chatActionRecordingVideoNote: L10n.telegram("Activity.RecordingVideoMessage")
            case .chatActionUploadingVideoNote: L10n.telegram("Activity.UploadingVideoMessage")
            case .chatActionWatchingAnimations(let action): L10n.telegram("Activity.EnjoyingAnimations", action.emoji)
            case .chatActionCancel: ""
            }
    }

    private func updateMessageSendSucceeded(
        _ update: UpdateMessageSendSucceeded,
        authority: ChatUpdateDeliveryAuthority,
    ) {
        MediaUploadProgressRegistry.noteSendSucceeded(
            chatID: update.message.chatId,
            oldMessageID: update.oldMessageId,
            newMessageID: update.message.id,
        )
        sendTransitionMessageIDReplaced.send((update.oldMessageId, update.message.id))
        releaseOutgoingDocumentFile(messageID: update.oldMessageId)
        guard acceptsUpdate(authority) else { return }
        acceptCompleteMessage(update.message, replacing: update.oldMessageId)
    }

    private func updateMessageSendFailed(
        _ update: UpdateMessageSendFailed,
        authority: ChatUpdateDeliveryAuthority,
    ) {
        sendTransitionMessageIDReplaced.send((update.oldMessageId, update.message.id))
        replaceOutgoingDocumentMessageID(old: update.oldMessageId, new: update.message.id)
        guard acceptsUpdate(authority) else { return }
        acceptCompleteMessage(update.message, replacing: update.oldMessageId, sendFailed: true)
    }

    private func updateDeleteMessages(_ update: UpdateDeleteMessages, authority _: ChatUpdateDeliveryAuthority) {
        guard !update.fromCache, update.isPermanent else { return }
        notePermanentMessageDeletion(update.messageIds)
        bufferPotentialVoiceMessageDeletions(update.messageIds)
        handlePotentialVideoMessageDeletions(update.messageIds)
        update.messageIds.forEach { releaseOutgoingDocumentFile(messageID: $0) }
        // Telegram leaves edit mode when the edited message disappears; a send would only fail.
        if let edited = editCustomMessage, locationContextIsCurrent,
           Set(update.messageIds).contains(edited.message.id)
        {
            cancelMessageEditing()
        }
        removeMessagesFromTimeline(update.messageIds)
    }

    /// A confirmed history absence only removes display state. Send-draft
    /// outcomes and file ownership remain exclusive to accepted TD updates.
    func removeMessagesFromTimeline(_ ids: [Int64]) {
        let deletedIDs = Set(ids)
        let deletedBubbleIDs = Set(messages.compactMap { message -> DisplayedMessageID? in
            message.sourceMessages.allSatisfy { deletedIDs.contains($0.id) }
                ? message.displayedID
                : nil
        })
        if !deletedBubbleIDs.isEmpty {
            messageBubblesWillDelete.send(deletedBubbleIDs)
        }
        var promotedRepresentativeIDs = [Int64]()
        messages = messages.compactMap { message in
            let remaining = message.sourceMessages.filter { !deletedIDs.contains($0.id) }
            guard !remaining.isEmpty else { return nil }
            guard case .album = message.displayedID else { return message }
            message.album = remaining.sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date
            }
            if deletedIDs.contains(message.message.id), let representative = message.album.first {
                message.message = representative
                message.formattedText = nil
                message.replyPresentation = nil
                message.forwardPresentation = nil
                message.reactions = representative.interactionInfo?.reactions
                message.unreadReactions = representative.unreadReactions
                message.isPinned = representative.isPinned
                promotedRepresentativeIDs.append(representative.id)
            }
            return message
        }
        notePartialMessageUpdate(promotedRepresentativeIDs, refresh: true)
    }

    private func updateNewMessage(_ update: UpdateNewMessage, authority: ChatUpdateDeliveryAuthority) {
        guard acceptsUpdate(authority) else { return }
        acceptCompleteMessage(update.message)
    }

    private func updateMessageEdited(_ update: UpdateMessageEdited, authority: ChatUpdateDeliveryAuthority) {
        refreshMessage(id: update.messageId, authority: authority)
    }

    private func refreshMessage(id: Int64, authority: ChatUpdateDeliveryAuthority) {
        guard acceptsUpdate(authority) else { return }
        notePartialMessageUpdate([id], refresh: true)
    }

    private func refreshReferencedMetadata(
        chatID: Int64,
        messageIDs: Set<Int64>,
        authority: ChatUpdateDeliveryAuthority,
    ) {
        let candidates = messages.filter { message in
            guard let reply = message.replyPresentation else { return false }
            return reply.targetChatID == chatID
                && reply.targetMessageID.map(messageIDs.contains) == true
        }
        for message in candidates {
            refreshMetadata(for: message, authority: authority)
        }
    }

    private func refreshReferencedMetadata(userID: Int64, authority: ChatUpdateDeliveryAuthority) {
        for message in messages {
            let refreshReply = message.replyPresentation?.referencedUserID == userID
            let refreshForward = message.forwardPresentation?.referencedUserIDs.contains(userID) == true
            if refreshReply || refreshForward {
                refreshMetadata(for: message, authority: authority)
            }
        }
    }

    private func invalidateDeletedForwardTargets(chatID: Int64, messageIDs: Set<Int64>) {
        for message in messages {
            guard let forward = message.forwardPresentation,
                  forward.targetChatID == chatID,
                  forward.targetMessageID.map(messageIDs.contains) == true
            else { continue }
            notePartialMessageUpdate([message.id])
            message.forwardPresentation = forward.removingNavigationTarget()
        }
    }

    private func refreshReferencedMetadata(chatID: Int64, authority: ChatUpdateDeliveryAuthority) {
        for message in messages {
            let refreshReply = message.replyPresentation?.referencedChatID == chatID
                || message.replyPresentation?.targetChatID == chatID
            let refreshForward = message.forwardPresentation?.referencedChatIDs.contains(chatID) == true
            if refreshReply || refreshForward {
                refreshMetadata(for: message, authority: authority)
            }
        }
    }

    private func refreshMetadata(for message: CustomMessage, authority: ChatUpdateDeliveryAuthority) {
        guard acceptsUpdate(authority) else { return }
        notePartialMessageUpdate([message.id], refresh: true)
    }
}
