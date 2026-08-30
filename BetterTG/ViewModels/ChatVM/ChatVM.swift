// ChatVM.swift

import AVFoundation
import Combine
import ImageIO
import TDLibKitDynamic
import UIKit

@MainActor final class ChatVM: ObservableObject {
    // MARK: Internal

    enum VoiceRecordingInteractionState: Equatable {
        case holding
        case idle
        case locked
        case pausing
        case preview
        case resuming
    }

    struct PreparedMessageWindow {
        let messages: [CustomMessage]
        let displayedMessageID: DisplayedMessageID
        let rawOldestMessageID: Int64?
        let readToken: ChatHistoryRestorationRefresh.ReadToken?
    }

    // MARK: Private

    private enum VoiceNoteFailure: Swift.Error {
        case couldNotStartRecorder
        case resendUnavailable
    }

    private enum ReactionMutationFailure: Swift.Error {
        case accountChanged
        case unavailable
    }

    private enum PinMutationFailure: Swift.Error {
        case accountChanged
        case unavailable
    }

    private enum VoiceRecordingTrimContinuation {
        case resume
        case send
    }

    private static let historyPageSize = 30

    let messagesDidChange = PassthroughSubject<Void, Never>()
    let messageBubblesWillDelete = PassthroughSubject<Set<DisplayedMessageID>, Never>()
    let sendTransitionAccepted = PassthroughSubject<ComposerSendTransitionAcceptance, Never>()
    let sendTransitionCancelled = PassthroughSubject<UUID, Never>()
    let sendTransitionMessageIDReplaced = PassthroughSubject<(old: Int64, new: Int64), Never>()
    let sendTransitionWillBegin = PassthroughSubject<ComposerSendTransitionRequest, Never>()

    let customChat: CustomChat
    nonisolated let chatID: Int64
    nonisolated let accountID: UUID?
    nonisolated let location: ChatLocation
    let client: TDLibClient
    let metadataResolver: MessageMetadataResolver
    let pollInteractionStore = MessagePollInteractionStore()
    @Published var actionStatus = ""
    @Published var onlineStatus = ""
    @Published var memberCount = 0
    @Published var onlineMemberCount = 0
    @Published var editCustomMessage: CustomMessage?
    @Published var replyMessage: CustomMessage?
    @Published var highlightedMessageId: Int64?
    @Published var displayedImages = [SelectedImage]()
    @Published var displayedDocuments = [SelectedDocument]()
    @Published var timerCount = 0.0
    @Published var text: AttributedString = ""
    @Published var editMessageText: AttributedString = "" {
        didSet {
            if editMessageText != oldValue { composerEditState.changeText() }
        }
    }

    @Published var recordingVoiceNote = false
    @Published private(set) var voiceRecordingInteractionState = VoiceRecordingInteractionState.idle
    @Published private(set) var startingVoiceNote = false
    @Published private(set) var loadingVoiceDraft = true
    @Published private(set) var finalizingVoiceNote = false
    @Published private(set) var hasPendingVoiceNote = false
    @Published private(set) var hasPendingVideoNote = false
    @Published private(set) var retryingVideoNote = false
    @Published private(set) var restoredVideoRecordingDraft: VideoNoteRecordingDraft? {
        didSet { queueForumTopicDemandRefresh() }
    }

    @Published private(set) var restoredVideoRecordingReplyMessage: CustomMessage?
    @Published private(set) var pendingVoiceReplyMessage: CustomMessage?
    @Published private(set) var pendingVideoReplyMessage: CustomMessage?
    @Published private(set) var voiceRecordingPreviewIsPlaying = false
    @Published private(set) var voiceRecordingPreviewPosition = 0.0
    private(set) var voiceRecordingTrimIsUpdating = false
    @Published var voiceNoteErrorMessage: String?
    @Published var videoNoteErrorMessage: String?
    @Published var reactionErrorMessage: String?
    @Published var sendErrorMessage: String?
    @Published private(set) var sendingComposerMessage = false
    @Published var draftErrorMessage: String?
    @Published private(set) var canAddReactions = false
    @Published private(set) var maximumChosenReactionCount = 1
    @Published private(set) var pinnedMessage: Message?
    @Published private(set) var locallyHiddenPinnedMessageID: Int64?
    @Published var pinErrorMessage: String?
    @Published private(set) var forumTopic: ForumTopic?
    @Published private(set) var forumTopicInfo: ForumTopicInfo?
    @Published private(set) var forumTopicsByID = [Int: ForumTopic]()
    @Published var errorShown = false
    var loadingMessagesTask: Task<Void, Never>?
    var cancellables = Set<AnyCancellable>()
    var timer: Timer?
    var wave = [Float]()
    var sendMessageTask: Task<Void, Never>?
    var chatInfoTask: Task<Void, Never>?
    var savedVoiceNoteUrl = URL(filePath: "")
    var audioRecorder: AVAudioRecorder?
    @Published var messages = [CustomMessage]() {
        didSet {
            refreshAllMessagesForumTopicsIfNeeded()
            refreshDeliveryStates()
            messagesDidChange.send()
        }
    }

    var recordingVideoTopicDemand: MessageTopic? {
        didSet { queueForumTopicDemandRefresh() }
    }

    private var voiceFinalizationGeneration = UInt64.zero
    private var voiceDraftRefreshGeneration = UInt64.zero
    @Published private var pendingVoiceDraftIsFinalizing = false

    private let chatOpenLease: ChatOpenLease
    private var deliveryReceipts: ChatDeliveryReceiptState
    private var deliveryReadTask: Task<Void, Never>?
    private var currentChatPermissions: ChatPermissions

    private var voiceRecordingTimerBaseline = 0.0
    private var voiceRecordingLastRecorderTime = 0.0
    private var voiceRecordingDraftTask: Task<Void, Never>?
    private var voiceRecordingDraftGeneration = 0
    private var voiceRecordingDraftID: UUID?
    private var voiceRecordingLifecycle = VoiceRecordingLifecycle()
    private var voiceFinalizationNeedsCheckpoint = false
    private let voiceBackgroundCheckpoint = VoiceRecordingCheckpointProtection()
    private var activeVoiceRecordingDraft: VoiceRecordingDraft? {
        didSet { queueForumTopicDemandRefresh() }
    }

    private var activeVoiceRecordingContext: ResolvedSendContext? {
        didSet { queueForumTopicDemandRefresh() }
    }

    private let voiceRecordingPreviewPlayer = LocalMediaPlayer()
    private var voiceRecordingPreviewLoadedURL: URL?
    private var voiceRecordingPreviewOwnsAudioSession = false
    private var voiceRecordingPreviewCancellables = Set<AnyCancellable>()
    private var voiceRecordingTrimTask: Task<Void, Never>?
    private var voiceRecordingTrimGeneration = 0
    private var voiceRecordingTrimBaseDraft: VoiceRecordingDraft?
    private var pendingVideoNote: VideoNoteSendDraft? {
        didSet { queueForumTopicDemandRefresh() }
    }

    private var outgoingVideoNotes = [Int64: VideoNoteSendDraft]() {
        didSet { queueForumTopicDemandRefresh() }
    }

    private var outgoingDocumentURLsByMessageID = [Int64: URL]()
    private var outgoingDocumentProvisionalLeaseIDsByMessageID = [Int64: Int64]()
    private var bufferedTerminalDocumentMessageIDs = Set<Int64>()
    private var bufferedDocumentMessageIDAliases = [Int64: Int64]()
    private var videoRetryAvailabilityTask: Task<Void, Never>?
    private var videoRetryTask: Task<Void, Never>?
    private var videoSendTransitionIDs = [UUID: UUID]()
    private var registeringVideoMessageIDs = Set<Int64>()
    private var submittingVideoDraftIDs = Set<UUID>()
    private var bufferedVideoResolutions = [Int64: VideoNoteDraftResolution]()
    private var bufferedVideoDeletedMessageIDs = Set<Int64>()
    private var replySelectionGeneration = UInt64.zero
    private var reactionMutationTasks = [Int64: Task<Void, Never>]()
    private var reactionMutationGenerations = [Int64: UUID]()
    private var pinnedMessageTask: Task<Void, Never>?
    private var pinnedMessageGeneration = UInt64.zero
    private var pinMutationTasks = [Int64: Task<Void, Never>]()
    private var pinMutationGenerations = [Int64: UUID]()
    private var pinAuthoritativeRevisions = [Int64: UInt64]()
    private var pinnedMessageAuthoritativeRevision = UInt64.zero
    private var forumTopicTask: Task<Void, Never>?
    private var forumTopicRequestID: UUID?
    private var forumTopicLiveUpdates: ForumTopicLiveUpdateState
    private var forumTopicInfoRevision = UInt64.zero
    private var allMessagesTopicReads: ChatForumTopicReads?
    private var allMessagesTopicReadsRetired = false
    private var forumTopicDemandRefreshQueued = false

    private var activeChatAction: ChatAction?
    private var activeChatActionContext: ResolvedSendContext?
    private var chatActionRouteRevision = UInt64.zero
    private var desiredChatAction: ChatAction?
    private var desiredChatActionContext: ResolvedSendContext?
    private var composerRevision = UInt64.zero
    private let composerEditState = ChatComposerEditState()
    private let composerRestorationLifetime = ChatComposerRestorationLifetime()
    private var composerMediaDraftTask: Task<Void, Never>?
    private var composerIsDirty = false
    private var awaitingAuthoritativeDraftClear = false
    private var draftClearGeneration = UInt64.zero
    private var draftClearTask: Task<Void, Never>?
    private let previewing: Bool

    private var pendingVoiceNote: VoiceNoteSendDraft? {
        didSet { queueForumTopicDemandRefresh() }
    }

    private var outgoingVoiceNotes = [Int64: VoiceNoteSendDraft]() {
        didSet { queueForumTopicDemandRefresh() }
    }

    private var registeringVoiceMessageIDs = Set<Int64>()
    private var bufferedVoiceOutcomes = [Int64: VoiceNoteDraftResolution]()
    private var bufferedDeletedMessageIDs = Set<Int64>()
    private var voiceRetryAvailabilityTask: Task<Void, Never>?
    private var voiceSendTransitionIDs = [UUID: UUID]()
    private var hasMoreMessages = true
    private var oldestHistoryMessageID: Int64?
    private var messageRefresh: ChatHistoryRestorationRefresh?
    private var messageRefreshTask: Task<Void, Never>?
    private var latestRestorationCursor: ChatHistoryLatestRefreshCursor?
    private var restorationWaitsForViewport = false
    private var latestRestorationFailed = false
    private var messageReplacementIDs = [Int64: Int64]()

    var visiblePinnedMessage: Message? {
        PinnedMessageState.visibleMessage(
            newest: pinnedMessage,
            locallyHiddenMessageID: locallyHiddenPinnedMessageID,
            supported: supportsPinnedMessages,
        )
    }

    var supportsPinnedMessages: Bool {
        !previewing
            && !location.isTopicScoped
            && customChat.supergroup?.isForum != true
            && customChat.supergroup?.isDirectMessagesGroup != true
            && !customChat.chat.viewAsTopics
    }

    var isReadOnlyTopic: Bool {
        location.isTopicScoped && !canWriteAnyMessage
    }

    var isAllMessagesForum: Bool {
        guard location.topic == nil, !customChat.chat.viewAsTopics, !customChat.isSavedMessages,
              case .chatTypeSupergroup(let type) = customChat.chat.type,
              let group = customChat.supergroup, group.id == type.supergroupId else { return false }
        return group.isForum && !type.isChannel && !group.isChannel && !group.isDirectMessagesGroup
    }

    var acceptedChatActionTopic: MessageTopic? {
        guard isAllMessagesForum else { return location.topic }
        let desiredContext = desiredChatAction == nil ? nil : desiredChatActionContext
        return (desiredContext ?? activeChatActionContext)?.destinationTopic
    }

    var canWriteBasicMessages: Bool {
        if let message = editCustomMessage?.message {
            return (try? resolveEditContext(for: message)) != nil
        }
        return (try? resolveSendContext(
            for: .text,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    var canAttachPhotos: Bool {
        (try? resolveSendContext(
            for: .photo,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    var canAttachDocuments: Bool {
        (try? resolveSendContext(
            for: .document,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    var canSendStickersAndAnimations: Bool {
        (try? resolveSendContext(
            for: .sticker,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    var canWriteAnyMessage: Bool {
        canWriteBasicMessages || canAttachPhotos || canAttachDocuments || canSendStickersAndAnimations
            || canRecordVoiceNote || canRecordVideoNote
    }

    var canShowComposer: Bool {
        !previewing && canWriteAnyMessage
    }

    var canRecordVoiceNote: Bool {
        (try? resolveSendContext(
            for: .voiceNote,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    var canRecordVideoNote: Bool {
        (try? resolveSendContext(
            for: .videoNote,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    var composerPlaceholder: String {
        if isAllMessagesForum {
            let info = replyMessage
                .flatMap { forumTopicInfo(for: $0.message.topicId) }
                ?? generalForumTopic?.info
            guard let topicName = info?.name else { return "Message…" }
            return replyMessage == nil
                ? "Message in \(topicName)"
                : "Reply in \(topicName)"
        }
        guard let topicName = forumTopicInfo?.name, location.isTopicScoped else {
            return "Message…"
        }
        return replyMessage == nil
            ? "Message in \(topicName)"
            : "Reply in \(topicName)"
    }

    var composerRestrictionText: String {
        if isAllMessagesForum {
            if let replyMessage,
               let info = forumTopicInfo(for: replyMessage.message.topicId),
               info.isClosed || info.isHidden
            {
                return "Replies are disabled in this closed topic."
            }
            if generalForumTopic == nil {
                return "Loading the General topic…"
            }
        }
        if forumTopicInfo?.isClosed == true || forumTopicInfo?.isHidden == true {
            return "Only the topic creator or an administrator can post here."
        }
        return "You can't send messages in this topic."
    }

    var locationContextIsCurrent: Bool {
        !composerRestorationLifetime.isRetired
            && TDLib.shared.activeAccountID == location.accountID
            && TDLib.shared.activeClient.id == location.clientID
            && client.id == location.clientID
    }

    var pendingVoiceReplyMessageID: Int64? {
        activeVoiceRecordingDraft?.replyMessageID ?? pendingVoiceNote?.replyMessageID
    }

    var canRetryPendingVoiceNote: Bool {
        guard !pendingVoiceDraftIsFinalizing, let pendingVoiceNote,
              (try? resolveFrozenMediaSendContext(
                  for: .voiceNote,
                  destination: pendingVoiceNote.destination,
                  sendTopic: pendingVoiceNote.sendTopic,
                  replyTo: pendingVoiceNote.replyTo,
              )) != nil,
              pendingVoiceNote.enqueueStartedAt == nil
        else { return false }
        return pendingVoiceNote.failedSendState?.canRetryNow ?? true
    }

    var canRetryPendingVideoNote: Bool {
        guard !retryingVideoNote,
              let pendingVideoNote,
              (try? resolveFrozenMediaSendContext(
                  for: .videoNote,
                  destination: pendingVideoNote.destination,
                  sendTopic: pendingVideoNote.sendTopic,
                  replyTo: pendingVideoNote.replyTo,
              )) != nil,
              pendingVideoNote.enqueueStartedAt == nil
        else { return false }
        return pendingVideoNote.failedSendState?.canRetryNow ?? true
    }

    var pendingVideoReplyMessageID: Int64? {
        pendingVideoNote?.replyMessageID
    }

    var pendingVideoReplyNavigationTarget: MessageMetadataNavigationTarget? {
        MessageReplyInputBuilder.navigationTarget(
            for: pendingVideoNote?.replyTo ?? restoredVideoRecordingDraft?.replyTo,
            currentChatID: chatID,
        )
    }

    var pendingVoiceReplyNavigationTarget: MessageMetadataNavigationTarget? {
        MessageReplyInputBuilder.navigationTarget(
            for: pendingVoiceNote?.replyTo ?? activeVoiceRecordingDraft?.replyTo,
            currentChatID: chatID,
        )
    }

    var canEditMessage: Bool {
        guard let editCustomMessage else { return false }
        return ChatComposerEditState.allowsSubmission(message: editCustomMessage.message, text: editMessageText)
    }

    var headerStatus: String {
        guard actionStatus.isEmpty else { return actionStatus }
        switch customChat.type {
        case .bot, .user:
            return onlineStatus
        case .group:
            return memberStatus(memberCount: memberCount, onlineMemberCount: onlineMemberCount)
        case .supergroup(let group):
            guard memberCount > 0 else { return group.isChannel ? "channel" : "group" }
            if group.isChannel {
                return countStatus(memberCount, singular: "subscriber", plural: "subscribers")
            }
            return memberStatus(memberCount: memberCount, onlineMemberCount: onlineMemberCount)
        }
    }

    var headerStatusIsActive: Bool {
        !actionStatus.isEmpty || headerStatus == "online"
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
    
    private var oldestLoadedMessageID: Int64 {
        guard let oldestMessage = messages.last else { return 0 }
        return ([oldestMessage.id] + oldestMessage.album.map(\.id)).min() ?? oldestMessage.id
    }

    init(customChat: CustomChat, previewing: Bool = false) {
        self.customChat = customChat
        self.chatID = resolvedLocation.chatID
        self.accountID = resolvedLocation.accountID
        self.location = resolvedLocation
        self.deliveryReceipts = ChatDeliveryReceiptState(location: resolvedLocation)
        self.forumTopicLiveUpdates = ForumTopicLiveUpdateState(location: resolvedLocation)
        self.client = client
        self.chatOpenLease = ChatOpenLeaseCoordinator.shared.acquire(
            location: resolvedLocation,
            client: client,
        )
        self.metadataResolver = MessageMetadataResolver(client: client)
        self.currentChatPermissions = customChat.chat.permissions
        self.previewing = previewing
        self.memberCount = customChat.group?.memberCount ?? customChat.supergroup?.memberCount ?? 0
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }

        setPublishers()
        loadGroupInfo()
        loadMessages()
        if isReadOnlyTopic, forumTopicInfo == nil, forumTopicTask == nil {
            loadForumTopic()
        }
        if supportsPinnedMessages {
            refreshPinnedMessages()
        }
        if !previewing {
            Media.shared.onChatOpen(title: customChat.displayTitle)
        }

        let routeDraftMessage: DraftMessage? =
            if previewing {
                nil
            } else if resolvedLocation.isTopicScoped {
                canWriteBasicMessages ? forumTopic?.draftMessage : nil
            } else {
                customChat.draftMessage
            }
        applyAuthoritativeDraft(routeDraftMessage, expectedRevision: composerRevision)
        Task { [weak self] in
            guard let self else { return }
            guard !previewing, !isReadOnlyTopic else {
                self.loadingVoiceDraft = false
                return
            }
            let draftKey = self.location.draftKey
            await VoiceRecordingDraftPreservation.wait(for: draftKey)
            await VideoNoteRecordingPreservation.wait(for: draftKey)
            guard !Task.isCancelled, locationContextIsCurrent else {
                self.loadingVoiceDraft = false
                return
            }
            let migrateLegacy = ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: draftKey)
            async let sendDrafts = VoiceNoteDraftStore.shared.drafts(
                for: draftKey,
                migrateLegacy: migrateLegacy,
            )
            async let recordingDrafts = VoiceRecordingDraftStore.shared.drafts(
                for: draftKey,
                migrateLegacy: migrateLegacy,
            )
            async let videoDrafts = VideoNoteFileStore.shared.drafts(
                for: draftKey,
                migrateLegacy: migrateLegacy,
            )
            async let videoRecordingDrafts = VideoNoteRecordingDraftStore.shared.drafts(
                for: draftKey,
                migrateLegacy: migrateLegacy,
            )
            let loadedDrafts = await (
                sendDrafts,
                recordingDrafts,
                videoDrafts,
                videoRecordingDrafts,
            )
            guard locationContextIsCurrent else {
                self.loadingVoiceDraft = false
                return
            }
            var restoredPendingDraft: VoiceNoteSendDraft?
            for draft in loadedDrafts.0 {
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
            } else if let recordingDraft = loadedDrafts.1.first {
                restoreVoiceRecordingDraft(recordingDraft)
            }
            var restoredVideoDraft: VideoNoteSendDraft?
            for draft in loadedDrafts.2 {
                if let temporaryMessageID = draft.temporaryMessageID {
                    outgoingVideoNotes[temporaryMessageID] = draft
                } else if restoredVideoDraft == nil {
                    restoredVideoDraft = draft
                }
            }
            if let restoredVideoDraft {
                activatePendingVideoDraft(restoredVideoDraft)
                if restoredVideoDraft.enqueueStartedAt != nil {
                    self.videoNoteErrorMessage = "A previous video send was interrupted before its status was confirmed. Check the chat before retrying."
                } else if let status = pendingVideoRetryStatusMessage {
                    self.videoNoteErrorMessage = status
                }
            }
            if restoredVideoDraft == nil,
               !hasPendingVoiceNote,
               !recordingVoiceNote,
               let recordingDraft = loadedDrafts.3.first
            {
                let reply = await resolveStoredReply(
                    replyTo: recordingDraft.replyTo,
                    legacyMessageID: recordingDraft.replyMessageID,
                )
                guard locationContextIsCurrent else {
                    self.loadingVoiceDraft = false
                    return
                }
                // Install this demand only when its draft context can follow synchronously.
                refreshForumTopicIfNeeded(recordingDraft.sendTopic)
                self.restoredVideoRecordingReplyMessage = reply
                self.restoredVideoRecordingDraft = recordingDraft
            }
            self.loadingVoiceDraft = false
        }
    }

    deinit {
        log("deinit \(chatID)")
        loadingMessagesTask?.cancel()
        sendMessageTask?.cancel()
        chatInfoTask?.cancel()
        timer?.invalidate()
        audioRecorder?.stop()
        try? td.closeChat(chatId: chatID) { _ in }
        if !previewing {
            Media.shared.onChatDismiss()
        }
    }

    func refreshDeliveryStates() {
        if isAllMessagesForum {
            refreshAllMessagesForumDeliveryStates()
            return
        }
        let current = locationContextIsCurrent
            && deliveryReceipts.permits(TDLib.shared.activeUpdateSource, location: location)
        for message in messages {
            message.updateDeliveryState(
                permitsFinalStatus: (usesOrdinaryDeliveryReceipts || usesForumDeliveryReceipts) && current
                    && message.deliverySourceMessage.chatId == location.chatID,
                readOutbox: current ? deliveryReceipts.lastReadOutbox : nil,
                topic: location.topic,
            )
        }
    }

    func receiveDeliveryReceipt(_ update: UpdateChatReadOutbox, authority: ChatUpdateDeliveryAuthority) {
        guard usesOrdinaryDeliveryReceipts, locationContextIsCurrent,
              deliveryReceipts.receive(update, source: authority.source, location: authority.location) else { return }
        refreshDeliveryStates()
    }

    func receiveDeliveryReceipt(_ update: UpdateForumTopic, authority: ChatUpdateDeliveryAuthority) {
        guard locationContextIsCurrent,
              deliveryReceipts.receive(update, source: authority.source, location: authority.location) else { return }
        refreshDeliveryStates()
    }

    func receiveForumTopicUpdate(_ update: UpdateForumTopic, authority: ChatUpdateDeliveryAuthority) {
        guard locationContextIsCurrent,
              let change = forumTopicLiveUpdates.receive(update, current: forumTopic, source: authority.source)
        else { return }
        receiveDeliveryReceipt(update, authority: authority)
        if change.metadataChanged, let forumTopic {
            self.forumTopic = forumTopicLiveUpdates.applyingLatest(to: forumTopic)
        }
        if awaitingAuthoritativeDraftClear, update.draftMessage == nil {
            awaitingAuthoritativeDraftClear = false
            composerIsDirty = false
        } else if change.draftChanged, !awaitingAuthoritativeDraftClear, canWriteBasicMessages {
            applyAuthoritativeDraft(update.draftMessage, expectedRevision: composerRevision)
        }
        if change.refreshUnreadCount { loadForumTopic() }
    }

    func loadDeliveryReceiptIfNeeded() {
        if let id = location.forumTopicID, id > 0 {
            guard locationContextIsCurrent, forumTopicTask == nil,
                  deliveryReceipts.lastReadOutbox == nil else { return }
            loadForumTopic()
            return
        }
        guard usesOrdinaryDeliveryReceipts, locationContextIsCurrent, deliveryReadTask == nil,
              deliveryReceipts.lastReadOutbox == nil,
              let read = deliveryReceipts.beginRead(source: TDLib.shared.activeUpdateSource, location: location)
        else { return }
        let client = client
        let location = location
        deliveryReadTask = Task { [weak self] in
            defer { self?.deliveryReadTask = nil }
            guard !Task.isCancelled, self?.locationContextIsCurrent == true else { return }
            let chat = try? await client.getChat(chatId: location.chatID)
            guard let self, !Task.isCancelled, locationContextIsCurrent else { return }
            if deliveryReceipts.finishRead(
                read,
                value: chat?.id == location.chatID
                    ? chat?.lastReadOutboxMessageId
                    : nil,
                source: TDLib.shared.activeUpdateSource,
                location: location,
            ) {
                refreshDeliveryStates()
            }
        }
    }

    func retireDeliveryReceipts() {
        allMessagesTopicReadsRetired = true
        allMessagesTopicReads?.retire()
        forumTopicsByID.removeAll()
        deliveryReadTask?.cancel()
        deliveryReadTask = nil
        if location.forumTopicID != nil {
            forumTopicLiveUpdates.retire()
            forumTopicRequestID = nil
            forumTopicTask?.cancel()
            forumTopicTask = nil
        }
        deliveryReceipts.retire()
        refreshDeliveryStates()
    }

    /// Foundation only: the controller must also fence navigation and local
    /// picker/recorder work before committing. No route opts into this yet.
    func prepareComposerRestoration() -> ChatComposerRestorationTransfer? {
        guard composerCanTransfer, location.accountID != nil else { return nil }
        let snapshot = composerRestorationState()
        return ChatComposerRestorationTransfer(snapshot: snapshot) { [self] in
            guard composerCanTransfer, composerRestorationState() == snapshot,
                  composerRestorationLifetime.retire()
            else { return false }
            _ = voiceRecordingLifecycle.suspend()
            replySelectionGeneration &+= 1
            composerEditState.changeSession()
            composerRevision &+= 1
            cancellables.removeAll()
            retireDeliveryReceipts()
            voiceRecordingPreviewCancellables.removeAll()
            stopVoiceRecordingPreviewPlayback()
            loadingMessagesTask?.cancel()
            messageRefreshTask?.cancel()
            messageRefresh?.cancel()
            composerMediaDraftTask?.cancel()
            cancelPendingDraftClearRetry()
            // No discard/remove helper: those helpers delete the transferred files.
            displayedDocuments = []
            displayedImages = []
            return true
        }
    }

    /// Display-only seed. The replacement must reconcile it with its current
    /// client's latest history and source-message reads before claiming freshness.
    func historyRestorationState() -> ChatHistoryRestorationState? {
        guard composerCanTransfer, reactionMutationTasks.isEmpty, pinMutationTasks.isEmpty else { return nil }
        return ChatHistoryRestorationState(
            location: location, messages: messages.map(ChatHistoryMessageValue.init),
            oldestHistoryMessageID: oldestHistoryMessageID, hasMoreMessages: hasMoreMessages,
        )
    }

    func acceptCompleteMessage(_ message: Message, replacing oldID: Int64? = nil, sendFailed: Bool = false) {
        guard locationContextIsCurrent else { return }
        if let oldID, oldID != message.id {
            messageRefresh?.notePermanentDeletion(messageIDs: [oldID])
            messageReplacementIDs[message.id] = oldID
        }
        let display = CustomMessage(
            message: message, sendFailed: sendFailed,
            formattedText: MessageContentPresentation.make(message).formattedText, properties: .default,
        )
        if let previous = messages.first(where: { $0.sourceMessages.contains { $0.id == (oldID ?? message.id) } }) {
            display.properties = previous.properties
            if previous.message.senderId == message.senderId { display.senderUser = previous.senderUser }
            if previous.message.replyTo == message.replyTo { display.replyPresentation = previous.replyPresentation }
            if previous.message.forwardInfo == message
                .forwardInfo { display.forwardPresentation = previous.forwardPresentation }
        }
        if message.mediaAlbumId != 0 { display.album = [message] }
        if messageRefresh?.acceptLiveMessage(ChatHistoryMessageValue(display)) == true {
            messageRefresh?.enqueueHydration(message: message)
        }
        driveMessageRefresh()
    }

    func notePartialMessageUpdate(_ ids: [Int64], refresh: Bool = false) {
        messageRefresh?.noteLiveUpdate(messageIDs: ids)
        if refresh {
            let displayed = Set(messages.flatMap(\.sourceMessages).map(\.id))
            messageRefresh?.enqueue(messageIDs: ids.filter(displayed.contains))
            driveMessageRefresh()
        }
    }

    func notePermanentMessageDeletion(_ ids: [Int64]) {
        messageRefresh?.notePermanentDeletion(messageIDs: ids)
        ids.forEach { messageReplacementIDs[$0] = nil }
    }

    /// The controller starts freshness only after installing its one-shot pixel
    /// anchor. Publishers already protect this provisional seed in the meantime.
    func beginRestoredHistoryRefresh() {
        guard locationContextIsCurrent, restorationWaitsForViewport else { return }
        restorationWaitsForViewport = false
        driveMessageRefresh()
    }

    func retryMessageRefresh() {
        guard locationContextIsCurrent else { return }
        retryAllMessagesForumTopics()
        messageRefresh?.retryFailures()
        latestRestorationFailed = false
        driveMessageRefresh()
    }

    func resolveSendContext(
        for kind: ChatSendContentKind,
        replyingTo reply: CustomMessage?,
        useCurrentReplyOverride: Bool = false,
    ) throws -> ResolvedSendContext {
        guard let accountID = location.accountID,
              locationContextIsCurrent
        else { throw ChatSendContextError.accountUnavailable }
        guard permissionAllows(kind) else {
            throw ChatSendContextError.chatPermissionDenied
        }

        let destinationTopic: MessageTopic?
        let draftTopic: MessageTopic?
        if isAllMessagesForum {
            draftTopic = nil
            if let reply {
                guard reply.message.chatId == location.chatID,
                      reply.properties.canBeReplied,
                      let topic = reply.message.topicId,
                      case .messageTopicForum = topic,
                      let info = forumTopicInfo(for: topic)
                else { throw ChatSendContextError.crossTopicReply }
                guard !info.isClosed, !info.isHidden else {
                    throw ChatSendContextError.topicReadOnly
                }
                destinationTopic = topic
            } else {
                guard let general = generalForumTopic,
                      general.info.chatId == location.chatID,
                      general.info.isGeneral
                else { throw ChatSendContextError.topicMetadataUnavailable }
                if general.info.isClosed || general.info.isHidden {
                    guard canManageForumTopics else { throw ChatSendContextError.topicReadOnly }
                }
                destinationTopic = .messageTopicForum(.init(forumTopicId: general.info.forumTopicId))
            }
        } else {
            if location.topic == nil,
               customChat.chat.viewAsTopics || customChat.supergroup?.isForum == true
            {
                throw ChatSendContextError.forumTopicRequired
            }
            if case .messageTopicForum = location.topic {
                guard let info = forumTopicInfo,
                      info.chatId == location.chatID,
                      info.forumTopicId == location.forumTopicID
                else { throw ChatSendContextError.topicMetadataUnavailable }
                let topicIsRestricted = info.isClosed || info.isHidden
                guard !topicIsRestricted || info.isOutgoing || canManageForumTopics else {
                    throw ChatSendContextError.topicReadOnly
                }
            }
            if let reply,
               reply.message.chatId == location.chatID,
               reply.message.topicId != location.topic
            {
                throw ChatSendContextError.crossTopicReply
            }
            destinationTopic = location.topic
            draftTopic = location.topic
        }
        if reply == nil,
           useCurrentReplyOverride,
           case .inputMessageReplyToMessage = replyInputOverride
        {
            throw ChatSendContextError.crossTopicReply
        }
        let resolvedReplyTo: InputMessageReplyTo? =
            if let reply {
                getMessageReplyTo(from: reply)
            } else if useCurrentReplyOverride {
                replyInputOverride
            } else {
                nil
            }
        return ResolvedSendContext(
            accountID: accountID,
            chatID: location.chatID,
            clientID: location.clientID,
            destinationTopic: destinationTopic,
            draftTopic: draftTopic,
            replyTo: resolvedReplyTo,
        )
    }

    func consumeRestoredVideoRecordingDraft(id: UUID) {
        guard restoredVideoRecordingDraft?.id == id else { return }
        restoredVideoRecordingDraft = nil
        restoredVideoRecordingReplyMessage = nil
    }

    func getLastSeenTime(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: AppLocalization.shared.selectedLanguagePackID)

        let difference = Date().timeIntervalSince1970 - TimeInterval(time)
        if difference < 60 {
            return L10n.telegram("LastSeen.JustNow")
        } else if difference < 60 * 60 {
            return L10n.telegramPlural("LastSeen.MinutesAgo", count: Int(difference / 60))
        } else if difference < 60 * 60 * 24 {
            return L10n.telegramPlural("LastSeen.HoursAgo", count: Int(difference / 60 / 60))
        } else if difference < 60 * 60 * 24 * 2 {
            dateFormatter.timeStyle = .short
            return L10n.telegram("LastSeen.YesterdayAt", dateFormatter.string(from: date))
        } else {
            dateFormatter.dateStyle = .short
            return L10n.telegram("LastSeen.AtDate", dateFormatter.string(from: date))
        }
    }

    func getOnlineStatus(from userStatus: UserStatus) -> String {
        switch userStatus {
        case .userStatusEmpty: ""
        case .userStatusOnline: L10n.telegram("Presence.online")
        case .userStatusOffline(let userStatusOffline): getLastSeenTime(userStatusOffline.wasOnline)
        case .userStatusRecently: L10n.telegram("LastSeen.Lately")
        case .userStatusLastWeek: L10n.telegram("LastSeen.WithinAWeek")
        case .userStatusLastMonth: L10n.telegram("LastSeen.WithinAMonth")
        }
    }

    func loadGroupInfo() {
        let client = td
        switch customChat.type {
        case .supergroup(let group):
            chatInfoTask = Task { [weak self] in
                guard let info = try? await client.getSupergroupFullInfo(supergroupId: group.id),
                      !Task.isCancelled,
                      info.memberCount > 0,
                      let self
                else { return }
                memberCount = info.memberCount
            }
        case .group(let group) where group.memberCount == 0:
            chatInfoTask = Task { [weak self] in
                guard let info = try? await client.getBasicGroupFullInfo(basicGroupId: group.id),
                      !Task.isCancelled,
                      let self
                else { return }
                memberCount = info.members.count
            }
        case .bot, .group, .user:
            break
        }
    }
    
    func loadMessages() {
        guard loadingMessagesTask == nil, hasMoreMessages else { return }
        let fromMessageID = oldestLoadedMessageID
        let client = td
        loadingMessagesTask = Task { [weak self] in
            guard let self else { return }
            if fromMessageID == 0 {
                _ = try? await client.openChat(chatId: chatID)
            }
            guard !Task.isCancelled else {
                loadingMessagesTask = nil
                return
            }
            await _loadMessages(fromMessageID: fromMessageID, client: client)
        }
    }

    func _loadMessages(fromMessageID: Int64, client: TDLibClient) async {
        var knownIDs = Set(messages.flatMap { message in
            [message.id] + message.album.map(\.id)
        })
        var cursor = fromMessageID
        var chatHistory = [Message]()
        var consecutiveNoProgressCount = 0
        var reachedEnd = false

        while chatHistory.count < Self.historyPageSize,
              consecutiveNoProgressCount < 2,
              !Task.isCancelled
        {
            let remainingCount = Self.historyPageSize - chatHistory.count
            let requestLimit = min(100, remainingCount + (cursor == 0 ? 0 : 1))
            guard let fetched = try? await client.getChatHistory(
                chatId: chatID,
                fromMessageId: cursor,
                limit: requestLimit,
                offset: 0,
                onlyLocal: false,
            )
            .messages else {
                loadingMessagesTask = nil
                return
            }
            guard !fetched.isEmpty else {
                reachedEnd = true
                break
            }

            let previousCount = chatHistory.count
            for message in fetched where knownIDs.insert(message.id).inserted {
                chatHistory.append(message)
                if chatHistory.count == Self.historyPageSize {
                    break
                }
            }
            let nextCursor = fetched.last?.id ?? cursor
            if chatHistory.count == previousCount || nextCursor == cursor {
                consecutiveNoProgressCount += 1
                await Task.yield()
            } else {
                consecutiveNoProgressCount = 0
            }
            cursor = nextCursor
        }

        guard !Task.isCancelled else {
            loadingMessagesTask = nil
            return
        }
        if consecutiveNoProgressCount == 2 {
            reachedEnd = true
        }
        
        let customMessages = await chatHistory.filter { location.matches(message: $0) }.asyncMap { chatMessage in
            await getCustomMessage(from: chatMessage)
        }
        let nextCursor = chatHistory.last?.id
        await main { [customMessages] in
            guard !Task.isCancelled, self.locationContextIsCurrent else {
                self.loadingMessagesTask = nil
                return
            }
        }
        
        await main { [savedMessages] in
            let existingIDs = Set(self.messages.map(\.id))
            self.messages.append(contentsOf: savedMessages.filter { !existingIDs.contains($0.id) })
            self.hasMoreMessages = !reachedEnd
            self.loadingMessagesTask = nil
            self.driveMessageRefresh()
        }
    }

    func displayedMessageID(containing messageID: Int64) -> DisplayedMessageID? {
        messages.first(where: { message in
            message.id == messageID || message.album.contains(where: { $0.id == messageID })
        })?.displayedID
    }

    func prepareMessageWindow(around id: Int64) async -> PreparedMessageWindow? {
        guard locationContextIsCurrent else { return nil }
        let readToken = messageRefresh?.beginRead()
        let windowSize = 50
        #if DEBUG
            ChatMessageNavigationDiagnostic.record("history-read")
        #endif
        var history = await loadHistory(
            fromMessageId: id,
            limit: windowSize,
            offset: -(windowSize / 2),
        ) ?? []
        guard !Task.isCancelled, locationContextIsCurrent else { return nil }
        #if DEBUG
            ChatMessageNavigationDiagnostic.record("history-ready")
        #endif
        let rawOldestMessageID = history.last?.id
        if !history.contains(where: { $0.id == id }) {
            #if DEBUG
                ChatMessageNavigationDiagnostic.record("fallback-read")
            #endif
            if let target = try? await client.getMessage(chatId: chatID, messageId: id),
               location.matches(message: target) { history.append(target) }
        }
        guard !history.isEmpty, locationContextIsCurrent else {
            #if DEBUG
                if locationContextIsCurrent { ChatMessageNavigationDiagnostic.record("target-missing") }
            #endif
            return nil
        }

        #if DEBUG
            ChatMessageNavigationDiagnostic.record("hydrating")
        #endif
        let loaded = await history.filter { location.matches(message: $0) }
            .asyncMap { await getCustomMessage(from: $0) }
        guard !Task.isCancelled, locationContextIsCurrent else { return nil }
        guard let displayedMessageID = (loaded + messages)
            .first(where: { message in
                message.id == id || message.album.contains(where: { $0.id == id })
            })?.displayedID
        else {
                #if DEBUG
                    ChatMessageNavigationDiagnostic.record("target-missing")
                #endif
            return nil
        }
        #if DEBUG
            ChatMessageNavigationDiagnostic.record("window-prepared")
        #endif
        return PreparedMessageWindow(
            messages: loaded, displayedMessageID: displayedMessageID,
            rawOldestMessageID: rawOldestMessageID, readToken: readToken,
        )
    }

    func applyMessageWindow(_ window: PreparedMessageWindow) {
        guard !Task.isCancelled, locationContextIsCurrent else { return }
        let current = window.readToken.map {
            messageRefresh?.takeCurrentValues(window.messages.map(ChatHistoryMessageValue.init), token: $0)
                .map { $0.makeMessage() } ?? []
        } ?? window.messages
        messages = canonicalMessages(merging: messages, with: current, replacingExisting: true)
        if let oldest = window.rawOldestMessageID, oldestHistoryMessageID.map({ oldest < $0 }) ?? true {
            oldestHistoryMessageID = oldest
        }
        driveMessageRefresh()
    }

    func mergeIncomingMessages(_ incoming: [CustomMessage]) {
        messages = canonicalMessages(merging: messages, with: incoming)
    }

    func replaceSourceMessage(oldID: Int64, with replacement: CustomMessage) {
        guard let index = messages.firstIndex(where: {
            $0.sourceMessages.contains(where: { $0.id == oldID })
        }) else { return }
        let current = messages[index]
        guard case .album = current.displayedID else {
            messages[index] = replacement
            if replyMessage?.id == oldID {
                replyMessage = replacement
            }
            return
        }
        let members = deduplicatedAlbumMessages(
            current.sourceMessages.filter { $0.id != oldID } + [replacement.message],
        )
        let representative = members.first?.id == replacement.message.id
            ? replacement
            : current
        representative.album = members
        messages[index] = representative
        if replyMessage?.id == oldID {
            replyMessage = replacement
        }
    }

    func deleteMessage(id: Int64, deleteForBoth: Bool) {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        let ids = customMessage.album.isEmpty ? [id] : customMessage.album.map(\.id)
        deleteMessages(ids: ids, deleteForBoth: deleteForBoth)
    }

    func deleteMessages(ids rawIDs: [Int64], deleteForBoth: Bool) {
        guard !isReadOnlyTopic, locationContextIsCurrent else { return }
        let ids = Array(Set(rawIDs)).sorted()
        let availableIDs = Set(messages.flatMap { message in
            message.album.isEmpty ? [message.id] : message.album.map(\.id)
        })
        guard !ids.isEmpty, ids.allSatisfy(availableIDs.contains) else { return }
        for messageID in ids {
            outgoingVoiceNotes.removeValue(forKey: messageID)
            outgoingVideoNotes.removeValue(forKey: messageID)
        }
        if let failedMessageID = pendingVoiceNote?.failedSendState?.messageID, ids.contains(failedMessageID) {
            pendingVoiceNote = nil
            pendingVoiceReplyMessage = nil
            hasPendingVoiceNote = false
            voiceNoteErrorMessage = nil
        }
        if let failedMessageID = pendingVideoNote?.failedSendState?.messageID, ids.contains(failedMessageID) {
            pendingVideoNote = nil
            pendingVideoReplyMessage = nil
            hasPendingVideoNote = false
            videoNoteErrorMessage = nil
        }
        Task {
            await VoiceNoteDraftStore.shared.discardMessages(destination: location.draftKey, messageIDs: ids)
            await promoteNextPendingVoiceDraft()
            await VideoNoteFileStore.shared.discardMessages(destination: location.draftKey, messageIDs: ids)
            await promoteNextPendingVideoDraft()
            guard locationContextIsCurrent else { return }
            _ = try? await client.deleteMessages(chatId: chatID, messageIds: ids, revoke: deleteForBoth)
        }
    }

    func viewMessages(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let client = client
        let accountID = accountID
        Task {
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            try await client.viewMessages(
                chatId: chatID,
                forceRead: true,
                messageIds: ids,
                source: nil,
            )
        }
    }

    func readAllReactions() {
        let client = client
        let accountID = accountID
        Task {
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            _ =
                if let forumTopicID = location.forumTopicID {
                    try? await client.readAllForumTopicReactions(
                        chatId: chatID,
                        forumTopicId: forumTopicID,
                    )
                } else {
                    try? await client.readAllChatReactions(chatId: chatID)
                }
        }
    }

    func submitPollAnswer(messageID: Int64, optionIDs: [Int], submission: MessagePollInteractionStore.Submission) {
        guard submission.messageID == messageID,
              pollInteractionStore.currentSubmission(messageID: messageID) == submission else { return }
        guard !isReadOnlyTopic,
              locationContextIsCurrent,
              messages.contains(where: { message in
                  message.id == messageID || message.album.contains(where: { $0.id == messageID })
              })
        else {
            pollInteractionStore.failSubmission(submission)
            return
        }
        let client = client
        Task {
            do {
                guard pollInteractionStore.currentSubmission(messageID: messageID) == submission else { return }
                guard locationContextIsCurrent else {
                    pollInteractionStore.failSubmission(submission)
                    return
                }
                _ = try await client.setPollAnswer(
                    chatId: chatID,
                    messageId: messageID,
                    optionIds: optionIDs,
                )
            } catch {
                if pollInteractionStore.failSubmission(submission) {
                    log("Couldn't submit poll answer for \(messageID): \(error.localizedDescription)")
                }
            }
        }
    }

    func toggleReaction(
        on message: CustomMessage,
        type: ReactionType,
        isBig: Bool,
    ) {
        guard !type.isPaid,
              !message.reactionMutationInFlight,
              location.matches(message: message.message),
              message.message.selfDestructType == nil,
              message.message.ephemeralMessageId == 0,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id,
              messages.contains(where: { $0 === message })
        else { return }
        let previous = message.reactions
        let wasChosen = MessageReactionStateReducer.isChosen(type, in: previous)
        let generation = UUID()
        let messageID = message.id
        message.reactionMutationInFlight = true
        reactionMutationGenerations[messageID] = generation
        messageRefresh?.setMutationBlocked(true, messageID: messageID, owner: .reaction)
        let client = client
        reactionMutationTasks[messageID] = Task { [weak self, weak message] in
            guard let self else { return }
            defer { settleMessageMutation(messageID, owner: .reaction) }
            var optimistic: MessageReactions?
            var appliedOptimisticState = false
            do {
                guard TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else {
                    throw ReactionMutationFailure.accountChanged
                }
                let areTags: Bool
                if wasChosen {
                    areTags = previous?.areTags ?? false
                } else {
                    let available = try await client.getMessageAvailableReactions(
                        chatId: chatID,
                        messageId: messageID,
                        rowSize: 8,
                    )
                    guard available.allowsNonPremium(type) else {
                        throw ReactionMutationFailure.unavailable
                    }
                    guard TDLib.shared.activeAccountID == accountID,
                          TDLib.shared.activeClient.id == client.id
                    else {
                        throw ReactionMutationFailure.accountChanged
                    }
                    areTags = available.areTags
                }
                optimistic = MessageReactionStateReducer.toggling(
                    type,
                    in: previous,
                    areTags: areTags,
                    maximumChosenCount: maximumChosenReactionCount,
                )
                if optimistic != previous {
                    message?.reactions = optimistic
                    appliedOptimisticState = true
                }
                _ =
                    if wasChosen {
                        try await client.removeMessageReaction(
                            chatId: chatID,
                            messageId: messageID,
                            reactionType: type,
                        )
                    } else {
                        try await client.addMessageReaction(
                            chatId: chatID,
                            isBig: isBig,
                            messageId: messageID,
                            reactionType: type,
                            updateRecentReactions: true,
                        )
                    }
                guard reactionMutationGenerations[messageID] == generation else { return }
                reactionMutationTasks[messageID] = nil
                reactionMutationGenerations[messageID] = nil
                message?.reactionMutationInFlight = false
            } catch is CancellationError {
                guard reactionMutationGenerations[messageID] == generation else { return }
                reactionMutationTasks[messageID] = nil
                reactionMutationGenerations[messageID] = nil
                message?.reactionMutationInFlight = false
            } catch {
                guard reactionMutationGenerations[messageID] == generation else { return }
                reactionMutationTasks[messageID] = nil
                reactionMutationGenerations[messageID] = nil
                if appliedOptimisticState,
                   let message,
                   message.reactions == optimistic
                {
                    message.reactions = previous
                }
                message?.reactionMutationInFlight = false
                reactionErrorMessage =
                    switch error as? ReactionMutationFailure {
                    case .accountChanged:
                        "The active Telegram account changed."
                    case .unavailable:
                        "This reaction isn't available for the message."
                    case nil:
                        wasChosen
                            ? "The reaction couldn't be removed."
                            : "The reaction couldn't be added."
                    }
            }
        }
    }

    func updateChatPermissions(_ permissions: ChatPermissions) {
        currentChatPermissions = permissions
        canAddReactions = permissions.canReactToMessages
        objectWillChange.send()
        messagesDidChange.send()
    }

    func updateAvailableReactions(_ availableReactions: ChatAvailableReactions) {
        maximumChosenReactionCount = availableReactions.maximumChosenReactionCount
    }

    func updateForumTopicInfo(_ info: ForumTopicInfo) {
        guard info.chatId == location.chatID else { return }
        if isAllMessagesForum {
            guard locationContextIsCurrent, let source = TDLib.shared.activeUpdateSource else { return }
            allMessagesTopicReads?.receive(info, source: source)
            return
        }
        if info.forumTopicId == location.forumTopicID {
            forumTopicInfoRevision &+= 1
            forumTopicInfo = info
        }
        if let topic = forumTopicsByID[info.forumTopicId] {
            forumTopicsByID[info.forumTopicId] = topic.replacing(info: info)
            messagesDidChange.send()
        }
    }

    func forumTopic(id: Int) -> ForumTopic? {
        forumTopicsByID[id]
    }

    func refreshForumTopic(id: Int) {
        guard let reader = allMessagesForumReader() else { return }
        reader.request(id)
        // Reply/draft callers install their context synchronously after requesting.
        queueForumTopicDemandRefresh()
    }

    func receiveAllMessagesForumTopicUpdate(_ update: UpdateForumTopic, source: TdUpdateSource) {
        guard isAllMessagesForum, locationContextIsCurrent else { return }
        allMessagesTopicReads?.receive(update, source: source)
    }

    func retryAllMessagesForumTopics() {
        refreshAllMessagesForumTopicsIfNeeded()
        allMessagesTopicReads?.retryMissing()
    }

    func loadForumTopic() {
        guard let forumTopicID = location.forumTopicID, forumTopicID > 0, locationContextIsCurrent,
              let metadataRead = forumTopicLiveUpdates.beginRead(source: TDLib.shared.activeUpdateSource),
              let receiptRead = deliveryReceipts.beginRead(source: TDLib.shared.activeUpdateSource, location: location)
        else { return }
        forumTopicTask?.cancel()
        let requestID = UUID()
        forumTopicRequestID = requestID
        let client = client
        let location = location
        let expectedComposerRevision = composerRevision
        let expectedInfoRevision = forumTopicInfoRevision
        forumTopicTask = Task { [weak self] in
            defer {
                if let self, forumTopicRequestID == requestID {
                    forumTopicLiveUpdates.finishRead(metadataRead, topic: nil, source: TDLib.shared.activeUpdateSource)
                    deliveryReceipts.finishForumRead(
                        receiptRead, topic: nil, source: TDLib.shared.activeUpdateSource, location: location,
                    )
                    forumTopicRequestID = nil
                    forumTopicTask = nil
                }
            }
            guard !Task.isCancelled, self?.locationContextIsCurrent == true,
                  self?.forumTopicRequestID == requestID else { return }
            do {
                let topic = try await client.getForumTopic(
                    chatId: location.chatID,
                    forumTopicId: forumTopicID,
                )
                guard let self, !Task.isCancelled, locationContextIsCurrent, forumTopicRequestID == requestID,
                      topic.info.chatId == location.chatID, topic.info.forumTopicId == forumTopicID
                else { return }
                if deliveryReceipts.finishForumRead(
                    receiptRead, topic: topic, source: TDLib.shared.activeUpdateSource, location: location,
                ) { refreshDeliveryStates() }
                guard var accepted = forumTopicLiveUpdates.finishRead(
                    metadataRead, topic: topic, source: TDLib.shared.activeUpdateSource,
                ) else { return }
                if forumTopicInfoRevision != expectedInfoRevision, let forumTopicInfo {
                    accepted = accepted.replacing(info: forumTopicInfo)
                }
                forumTopic = accepted
                forumTopicInfo = accepted.info
                if awaitingAuthoritativeDraftClear, accepted.draftMessage == nil {
                    awaitingAuthoritativeDraftClear = false
                    composerIsDirty = false
                } else if !awaitingAuthoritativeDraftClear, canWriteBasicMessages {
                    applyAuthoritativeDraft(
                        accepted.draftMessage,
                        expectedRevision: expectedComposerRevision,
                    )
                }
            } catch {} // Keep current scalar state; the existing Ready/user refresh can retry.
        }
    }

    func refreshPinnedMessages() {
        guard supportsPinnedMessages else { return }
        pinnedMessageGeneration &+= 1
        let generation = pinnedMessageGeneration
        pinnedMessageTask?.cancel()
        let client = client
        let accountID = accountID
        pinnedMessageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await client.getChatPinnedMessage(chatId: chatID)
                guard !Task.isCancelled,
                      pinnedMessageGeneration == generation,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                pinnedMessageAuthoritativeRevision &+= 1
                pinnedMessage = message.topicId == nil ? message : nil
                pinnedMessageTask = nil
            } catch is CancellationError {
                guard pinnedMessageGeneration == generation else { return }
                pinnedMessageTask = nil
            } catch {
                guard !Task.isCancelled,
                      pinnedMessageGeneration == generation,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                if PinnedMessageState.fetchErrorMeansNoPinnedMessage(error) {
                    pinnedMessageAuthoritativeRevision &+= 1
                    pinnedMessage = nil
                }
                pinnedMessageTask = nil
            }
        }
    }

    func hidePinnedMessageBanner() {
        locallyHiddenPinnedMessageID = pinnedMessage?.id
    }

    func applyPinnedMessageUpdate(messageID: Int64, isPinned: Bool) {
        notePartialMessageUpdate([messageID])
        pinnedMessageAuthoritativeRevision &+= 1
        pinAuthoritativeRevisions[messageID, default: 0] &+= 1
        messages.first(where: { $0.id == messageID })?.isPinned = isPinned
        if !isPinned, pinnedMessage?.id == messageID {
            pinnedMessage = nil
        }
        refreshPinnedMessages()
    }

    func applyPermanentPinnedMessageDeletion(_ messageIDs: [Int64]) {
        guard pinnedMessage.map({ messageIDs.contains($0.id) }) == true else { return }
        pinnedMessageAuthoritativeRevision &+= 1
        pinnedMessage = nil
        refreshPinnedMessages()
    }

    func pinMessage(
        _ message: CustomMessage,
        mode: MessagePinMode,
    ) {
        setMessagePinned(
            message,
            pinned: true,
            disableNotification: mode.disableNotification,
            onlyForSelf: mode.onlyForSelf,
        )
    }

    func unpinMessage(_ message: CustomMessage) {
        setMessagePinned(
            message,
            pinned: false,
            disableNotification: true,
            onlyForSelf: false,
        )
    }

    func beginReply(to message: CustomMessage) {
        guard location.matches(message: message.message) else { return }
        if isAllMessagesForum, let topicID = message.forumTopicID {
            refreshForumTopic(id: topicID)
        }
        markComposerDirty()
        replySelectionGeneration &+= 1
        replyMessage = message
        replyQuote = nil
        replyInputOverride = nil
        replyFallbackPresentation = nil
        reconcileActiveChatActionAfterReplyChange()
    }

    func beginQuoteReply(to message: CustomMessage) {
        guard location.matches(message: message.message) else { return }
        if isAllMessagesForum, let topicID = message.forumTopicID {
            refreshForumTopic(id: topicID)
        }
        guard let formattedText = message.formattedText, !formattedText.text.isEmpty else {
            beginReply(to: message)
            return
        }
        markComposerDirty()
        replySelectionGeneration &+= 1
        let generation = replySelectionGeneration
        replyMessage = message
        replyQuote = nil
        replyInputOverride = nil
        replyFallbackPresentation = nil
        reconcileActiveChatActionAfterReplyChange()
        let client = client
        Task { [weak self, weak message] in
            guard let self, let message else { return }
            let maximumLength: Int =
                if case .optionValueInteger(let value) = try? await client.getOption(
                    name: "message_reply_quote_length_max",
                ) {
                    max(1, Int(clamping: value.value.rawValue))
                } else {
                    1024
                }
            guard replySelectionGeneration == generation,
                  replyMessage === message,
                  let quote = MessageQuoteBuilder.make(from: formattedText, maximumLength: maximumLength)
            else { return }
            replyQuote = quote
        }
    }

    func cancelReply(markDirty: Bool = true) {
        if markDirty {
            markComposerDirty()
        }
        replySelectionGeneration &+= 1
        replyMessage = nil
        replyQuote = nil
        replyInputOverride = nil
        replyFallbackPresentation = nil
        reconcileActiveChatActionAfterReplyChange()
    }

    func updateComposerTextFromUser(_ value: AttributedString) {
        markComposerDirty()
        text = value
    }

    func appendComposerEmoji(_ emoji: String) {
        guard !emoji.isEmpty else { return }
        markComposerDirty()
        if editCustomMessage == nil {
            text.append(AttributedString(emoji))
        } else {
            editMessageText.append(AttributedString(emoji))
        }
        composerMediaDraftTask?.cancel()
        composerMediaDraftTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            await updateDraft()
            composerMediaDraftTask = nil
        }
    }

    func replaceDisplayedDocuments(_ documents: [SelectedDocument]) {
        let previousURLs = displayedDocuments.map(\.url)
        displayedDocuments = documents
        removeTemporaryDocuments(previousURLs)
    }

    func removeDisplayedDocument(id: UUID) {
        let removedURLs = displayedDocuments.filter { $0.id == id }.map(\.url)
        displayedDocuments.removeAll { $0.id == id }
        removeTemporaryDocuments(removedURLs)
    }

    func discardDisplayedDocuments() {
        let removedURLs = displayedDocuments.map(\.url)
        displayedDocuments = []
        removeTemporaryDocuments(removedURLs)
    }

    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = try? await client.getMessage(chatId: customChat.chat.id, messageId: id),
              location.matches(message: message)
        else { return nil }
        return await getCustomMessage(from: message)
    }

    func getCustomMessage(from message: Message) async -> CustomMessage {
        async let replyPresentation = metadataResolver.replyPresentation(for: message)
        async let forwardPresentation = metadataResolver.forwardPresentation(for: message.forwardInfo)
        async let properties = try? client.getMessageProperties(chatId: message.chatId, messageId: message.id)
        let customMessage = await CustomMessage(
            message: message,
            replyPresentation: replyPresentation,
            forwardPresentation: forwardPresentation,
            properties: properties ?? .default,
        )
        
        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }
        
        if case .messageSenderUser(let messageSenderUser) = message.senderId {
            customMessage.senderUser = try? await client.getUser(userId: messageSenderUser.userId)
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
            customMessage.formattedText = FormattedText(
                entities: [],
                text: L10n.betterTG("Chat.UnsupportedTDLib"),
            )
        default:
            customMessage.formattedText = FormattedText(
                entities: [],
                text: L10n.betterTG("Chat.UnsupportedBetterTG"),
            )
        }
        
        return customMessage
    }

    func getInputReplyToMessage(_ inputMessageReplyTo: InputMessageReplyTo?) async -> CustomMessage? {
        switch inputMessageReplyTo {
        case .inputMessageReplyToMessage(let message):
            guard let target = try? await client.getMessage(chatId: chatID, messageId: message.messageId),
                  location.matches(message: target)
            else { return nil }
            return await getCustomMessage(from: target)
        case .inputMessageReplyToExternalMessage(let message):
            guard let target = try? await client.getMessage(chatId: message.chatId, messageId: message.messageId)
            else { return nil }
            return await getCustomMessage(from: target)
        case .inputMessageReplyToEphemeralMessage, .inputMessageReplyToStory, nil:
            return nil
        }
    }

    func sendMessage() async {
        guard !sendingComposerMessage else { return }
        sendingComposerMessage = true
        defer {
            sendingComposerMessage = false
            sendMessageTask = nil
        }
        switch composerEditState.prepare(message: editCustomMessage?.message, text: editMessageText) {
        case .ordinary:
            break
        case .invalidEdit:
            // An invalid edit is never an intent to send the preserved compose draft.
            return
        case .edit(let attempt):
            let completion = await composerEditState.perform(attempt) { [self] attempt in
                try await editMessage(attempt)
            }
            guard locationContextIsCurrent, composerEditState.isCurrent(attempt), !Task.isCancelled else { return }
            switch completion {
            case .obsolete:
                break
            case .succeeded:
                cancelMessageEditing()
                sendErrorMessage = nil
            case .failed(let error):
                sendErrorMessage = error.localizedDescription
            }
            return
        }
        let sentText = text
        let sentImageIDs = Set(displayedImages.map(\.id))
        let sentDocumentIDs = Set(displayedDocuments.map(\.id))
        let sentReplyID = replyMessage?.id
        let transitionID = UUID()
        let transitionKind: ComposerSendTransitionKind = displayedImages.isEmpty && displayedDocuments.isEmpty
            ? .text
            : .media
        sendTransitionWillBegin.send(ComposerSendTransitionRequest(id: transitionID, kind: transitionKind))
        do {
            let result: (context: ResolvedSendContext, messages: [Message])
            if !displayedDocuments.isEmpty {
                result = try await sendMessageDocuments()
            } else if !displayedImages.isEmpty {
                result = try await sendMessagePhotos()
            } else if !text.characters.isEmpty {
                result = try await sendMessageText()
            } else {
                sendTransitionCancelled.send(transitionID)
                return
            }
            let draftClearSucceeded = await clearRouteDraft(result.context)
            guard locationContextIsCurrent else {
                sendTransitionCancelled.send(transitionID)
                return
            }
            displayedImages.removeAll { sentImageIDs.contains($0.id) }
            displayedDocuments.removeAll { sentDocumentIDs.contains($0.id) }
            if text == sentText {
                text = ""
            }
            if replyMessage?.id == sentReplyID {
                cancelReply(markDirty: false)
            }
            composerRevision &+= 1
            let hasNewComposerState = !text.characters.isEmpty
                || replyMessage != nil
                || !displayedImages.isEmpty
                || !displayedDocuments.isEmpty
                || editCustomMessage != nil
            awaitingAuthoritativeDraftClear = location.isTopicScoped && !hasNewComposerState
            composerIsDirty = awaitingAuthoritativeDraftClear
                || hasNewComposerState
                || !draftClearSucceeded
            sendErrorMessage = nil
            if hasNewComposerState {
                cancelPendingDraftClearRetry()
                await updateDraft()
            } else if location.isTopicScoped {
                loadForumTopic()
            }
            await Task.yield()
            sendTransitionAccepted.send(ComposerSendTransitionAcceptance(
                id: transitionID,
                messageIDs: result.messages.map(\.id),
            ))
        } catch {
            sendTransitionCancelled.send(transitionID)
            sendErrorMessage = error.localizedDescription
        }
    }

    func sendMessageDocuments() async throws -> (context: ResolvedSendContext, messages: [Message]) {
        let context = try resolveSendContext(
            for: .document,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        let documents = Array(displayedDocuments.prefix(10))
        guard !documents.isEmpty else { throw ChatSendContextError.chatPermissionDenied }
        let caption: FormattedText? = text.characters.isEmpty
            ? nil
            : FormattedText(entities: getEntities(from: text), text: text.string)
        let provisionalMessageIDs = documents.map { _ in -Int64.random(in: 1...Int64.max) }
        var persistedProvisionalMessageIDs = [Int64]()
        do {
            for (document, provisionalMessageID) in zip(documents, provisionalMessageIDs) {
                try SelectedDocumentFileStore.lease(
                    document.url,
                    accountID: context.accountID,
                    chatID: context.chatID,
                    messageID: provisionalMessageID,
                )
                persistedProvisionalMessageIDs.append(provisionalMessageID)
            }
        } catch {
            for provisionalMessageID in persistedProvisionalMessageIDs {
                SelectedDocumentFileStore.unlease(
                    accountID: context.accountID,
                    chatID: context.chatID,
                    messageID: provisionalMessageID,
                )
            }
            throw error
        }
        var boundProvisionalMessageIDs = Set<Int64>()
        do {
            try await sendChatAction(.chatActionUploadingDocument(.init(progress: 0)), in: context)
            let contents = documents.enumerated().map { index, document in
                InputMessageContent.inputMessageDocument(.init(
                    caption: index == 0 ? caption : nil,
                    document: InputDocument(
                        disableContentTypeDetection: true,
                        document: .inputFileLocal(.init(path: document.url.path(percentEncoded: false))),
                        thumbnail: nil,
                    ),
                ))
            }
            guard locationContextIsCurrent else { throw ChatSendContextError.accountUnavailable }
            let messages: [Message]
            if contents.count == 1, let content = contents.first {
                let message = try await client.sendMessage(
                    chatId: context.chatID,
                    inputMessageContent: content,
                    options: nil,
                    replyMarkup: nil,
                    replyTo: context.replyTo,
                    topicId: context.destinationTopic,
                )
                messages = [message]
            } else {
                let result = try await client.sendMessageAlbum(
                    chatId: context.chatID,
                    inputMessageContents: contents,
                    options: nil,
                    replyTo: context.replyTo,
                    topicId: context.destinationTopic,
                )
                messages = result.messages ?? []
            }
            for index in 0..<min(messages.count, documents.count) {
                let resolvedMessageID = bufferedDocumentMessageIDAliases[messages[index].id] ?? messages[index].id
                let provisionalMessageID = provisionalMessageIDs[index]
                boundProvisionalMessageIDs.insert(provisionalMessageID)
                do {
                    try SelectedDocumentFileStore.replaceMessageID(
                        accountID: context.accountID,
                        chatID: context.chatID,
                        old: provisionalMessageID,
                        new: resolvedMessageID,
                    )
                } catch {
                    outgoingDocumentProvisionalLeaseIDsByMessageID[resolvedMessageID] = provisionalMessageID
                }
            }
            for provisionalMessageID in provisionalMessageIDs
                where !boundProvisionalMessageIDs.contains(provisionalMessageID)
            {
                SelectedDocumentFileStore.unlease(
                    accountID: context.accountID,
                    chatID: context.chatID,
                    messageID: provisionalMessageID,
                )
            }
            retainOutgoingDocumentFiles(messages: messages, documents: documents)
            guard messages.count == contents.count else {
                let acceptedDocumentIDs = Set(documents.prefix(messages.count).map(\.id))
                displayedDocuments.removeAll { acceptedDocumentIDs.contains($0.id) }
                throw ChatSendContextError.partialAlbum(sent: messages.count, expected: contents.count)
            }
            guard messages.allSatisfy({ context.matches(message: $0) }) else {
                throw ChatSendContextError.unexpectedDestination
            }
            try? await cancelChatAction(in: context)
            return (context, messages)
        } catch {
            for provisionalMessageID in provisionalMessageIDs
                where !boundProvisionalMessageIDs.contains(provisionalMessageID)
            {
                SelectedDocumentFileStore.unlease(
                    accountID: context.accountID,
                    chatID: context.chatID,
                    messageID: provisionalMessageID,
                )
            }
            try? await cancelChatAction(in: context)
            throw error
        }
    }

    func sendSticker(_ sticker: Sticker) async {
        guard !sendingComposerMessage else { return }
        sendingComposerMessage = true
        let transitionID = UUID()
        let sentReplyID = replyMessage?.id
        sendTransitionWillBegin.send(ComposerSendTransitionRequest(id: transitionID, kind: .media))
        defer { sendingComposerMessage = false }
        do {
            let context = try resolveSendContext(
                for: .sticker,
                replyingTo: replyMessage,
                useCurrentReplyOverride: true,
            )
            guard case .stickerFullTypeRegular(let regular) = sticker.fullType,
                  regular.premiumAnimation == nil
            else { throw ChatSendContextError.chatPermissionDenied }
            let message = try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: .inputMessageSticker(.init(
                    emoji: sticker.emoji,
                    sticker: InputSticker(
                        height: sticker.height,
                        sticker: .inputFileId(.init(id: sticker.sticker.id)),
                        thumbnail: nil,
                        width: sticker.width,
                    ),
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: context.replyTo,
                topicId: context.destinationTopic,
            )
            guard locationContextIsCurrent,
                  context.matches(message: message)
            else { throw ChatSendContextError.unexpectedDestination }
            if replyMessage?.id == sentReplyID {
                cancelReply(markDirty: false)
                do {
                    try await updateDraft(in: context, replyTo: nil)
                    draftErrorMessage = nil
                } catch {
                    composerIsDirty = true
                    scheduleDraftUpdateRetry(context, replyTo: nil)
                }
            }
            sendErrorMessage = nil
            await Task.yield()
            sendTransitionAccepted.send(.init(id: transitionID, messageIDs: [message.id]))
        } catch {
            sendTransitionCancelled.send(transitionID)
            sendErrorMessage = error.localizedDescription
        }
    }

    func sendAnimation(_ animation: Animation) async {
        guard !sendingComposerMessage else { return }
        sendingComposerMessage = true
        let transitionID = UUID()
        let sentText = text
        let sentReplyID = replyMessage?.id
        sendTransitionWillBegin.send(ComposerSendTransitionRequest(id: transitionID, kind: .media))
        defer { sendingComposerMessage = false }
        do {
            let context = try resolveSendContext(
                for: .animation,
                replyingTo: replyMessage,
                useCurrentReplyOverride: true,
            )
            let caption: FormattedText? = sentText.characters.isEmpty
                ? nil
                : FormattedText(entities: getEntities(from: sentText), text: sentText.string)
            let message = try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: .inputMessageAnimation(.init(
                    animation: InputAnimation(
                        addedStickerFileIds: [],
                        animation: .inputFileId(.init(id: animation.animation.id)),
                        duration: animation.duration,
                        height: animation.height,
                        thumbnail: nil,
                        width: animation.width,
                    ),
                    caption: caption,
                    hasSpoiler: false,
                    showCaptionAboveMedia: false,
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: context.replyTo,
                topicId: context.destinationTopic,
            )
            guard locationContextIsCurrent,
                  context.matches(message: message)
            else { throw ChatSendContextError.unexpectedDestination }
            let draftClearSucceeded = await clearRouteDraft(context)
            if text == sentText {
                text = ""
            }
            if replyMessage?.id == sentReplyID {
                cancelReply(markDirty: false)
            }
            composerRevision &+= 1
            let hasNewComposerState = !text.characters.isEmpty
                || replyMessage != nil
                || !displayedImages.isEmpty
                || !displayedDocuments.isEmpty
            awaitingAuthoritativeDraftClear = location.isTopicScoped && !hasNewComposerState
            composerIsDirty = awaitingAuthoritativeDraftClear || hasNewComposerState || !draftClearSucceeded
            if hasNewComposerState {
                await updateDraft()
            } else if location.isTopicScoped {
                loadForumTopic()
            }
            sendErrorMessage = nil
            await Task.yield()
            sendTransitionAccepted.send(.init(id: transitionID, messageIDs: [message.id]))
        } catch {
            sendTransitionCancelled.send(transitionID)
            sendErrorMessage = error.localizedDescription
        }
    }

    func releaseOutgoingDocumentFile(messageID: Int64) {
        if let url = outgoingDocumentURLsByMessageID.removeValue(forKey: messageID) {
            if let provisionalMessageID = outgoingDocumentProvisionalLeaseIDsByMessageID.removeValue(
                forKey: messageID,
            ) {
                SelectedDocumentFileStore.unlease(
                    accountID: accountID,
                    chatID: chatID,
                    messageID: provisionalMessageID,
                )
                SelectedDocumentFileStore.remove([url])
            } else {
                SelectedDocumentFileStore.complete(
                    accountID: accountID,
                    chatID: chatID,
                    messageID: messageID,
                )
                removeTemporaryDocuments([url])
            }
        } else if sendingComposerMessage, !displayedDocuments.isEmpty {
            bufferedTerminalDocumentMessageIDs.insert(messageID)
        }
    }

    func replaceOutgoingDocumentMessageID(old: Int64, new: Int64) {
        if let url = outgoingDocumentURLsByMessageID.removeValue(forKey: old) {
            outgoingDocumentURLsByMessageID[new] = url
            let persistedMessageID = outgoingDocumentProvisionalLeaseIDsByMessageID.removeValue(forKey: old) ?? old
            do {
                try SelectedDocumentFileStore.replaceMessageID(
                    accountID: accountID,
                    chatID: chatID,
                    old: persistedMessageID,
                    new: new,
                )
            } catch {
                outgoingDocumentProvisionalLeaseIDsByMessageID[new] = persistedMessageID
            }
        } else if sendingComposerMessage, !displayedDocuments.isEmpty {
            bufferedDocumentMessageIDAliases[old] = new
        }
    }

    func sendMessagePhotos() async throws -> (context: ResolvedSendContext, messages: [Message]) {
        let context = try resolveSendContext(
            for: .photo,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        let images = displayedImages
        guard !images.isEmpty else { throw ChatSendContextError.chatPermissionDenied }
        let caption = FormattedText(entities: getEntities(from: text), text: text.string)
        try await sendChatAction(.chatActionUploadingPhoto(.init(progress: 0)), in: context)
        do {
            let sentMessages: [Message]
            var messageContents = [InputMessageContent]()
            for image in images {
                await messageContents.append(makeInputMessageContent(for: image.url, caption: caption))
            }
            guard locationContextIsCurrent else { throw ChatSendContextError.accountUnavailable }
            if messageContents.count == 1, let content = messageContents.first {
                let message = try await client.sendMessage(
                    chatId: context.chatID,
                    inputMessageContent: content,
                    options: nil,
                    replyMarkup: nil,
                    replyTo: context.replyTo,
                    topicId: context.destinationTopic,
                )
                guard context.matches(message: message) else {
                    throw ChatSendContextError.unexpectedDestination
                }
                sentMessages = [message]
            } else {
                let result = try await client.sendMessageAlbum(
                    chatId: context.chatID,
                    inputMessageContents: messageContents,
                    options: nil,
                    replyTo: context.replyTo,
                    topicId: context.destinationTopic,
                )
                let messages = result.messages ?? []
                guard messages.count == messageContents.count else {
                    throw ChatSendContextError.partialAlbum(
                        sent: messages.count,
                        expected: messageContents.count,
                    )
                }
                guard messages.allSatisfy({ context.matches(message: $0) }) else {
                    throw ChatSendContextError.unexpectedDestination
                }
                sentMessages = messages
            }
            try? await cancelChatAction(in: context)
            return (context, sentMessages)
        } catch {
            try? await cancelChatAction(in: context)
            throw error
        }
    }

    func makeInputMessageContent(
        for url: URL,
        caption: FormattedText,
    ) async -> InputMessageContent {
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
                caption: caption,
                hasSpoiler: false,
                photo: photo,
                selfDestructType: nil,
                showCaptionAboveMedia: false,
            ),
        )
    }

    func sendMessageText() async throws -> (context: ResolvedSendContext, messages: [Message]) {
        let context = try resolveSendContext(
            for: .text,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        let message = try await client.sendMessage(
            chatId: context.chatID,
            inputMessageContent: .inputMessageText(
                .init(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string,
                    ),
                ),
            ),
            options: nil,
            replyMarkup: nil,
            replyTo: context.replyTo,
            topicId: context.destinationTopic,
        )
        guard context.matches(message: message) else {
            throw ChatSendContextError.unexpectedDestination
        }
        try? await cancelChatAction(in: context)
        return (context, [message])
    }

    func submitVideoNote(
        _ asset: VideoNoteAsset,
        thumbnail: VideoNoteInputThumbnailAsset? = nil,
        originRecordingDraftID: UUID? = nil,
        replyingTo reply: CustomMessage?,
        storedReplyMessageID: Int64? = nil,
        storedReplyTo: InputMessageReplyTo? = nil,
        storedSendTopic: MessageTopic? = nil,
    ) async -> VideoNoteSubmissionResult {
        let sendContext: ResolvedSendContext
        do {
            sendContext = try isAllMessagesForum
                ? resolveFrozenMediaSendContext(
                    for: .videoNote,
                    destination: location.draftKey,
                    sendTopic: storedSendTopic,
                    replyTo: storedReplyTo ?? getMessageReplyTo(from: reply),
                )
                : resolveSendContext(for: .videoNote, replyingTo: reply)
        } catch {
            return .retained(
                asset,
                originConsumed: false,
                message: error.localizedDescription,
            )
        }
        var draft: VideoNoteSendDraft
        var alreadyEnqueued = false
        var didBeginEnqueue = false
        do {
            let preparation = try await VideoNoteFileStore.shared.adoptAndPrepareEnqueue(
                asset,
                thumbnail: thumbnail,
                chatID: chatID,
                draftKey: location.draftKey,
                originRecordingDraftID: originRecordingDraftID,
                replyMessageID: reply?.id ?? storedReplyMessageID,
                replyTo: sendContext.replyTo ?? storedReplyTo,
                sendTopic: sendContext.destinationTopic,
            )
            switch preparation {
            case .alreadyEnqueued(let preparedDraft):
                draft = preparedDraft
                alreadyEnqueued = true
            case .ready(let preparedDraft):
                draft = preparedDraft
                didBeginEnqueue = true
            case .retained(let preparedDraft):
                draft = preparedDraft
            }
            guard draft.destination == sendContext.draftKey else {
                throw ChatSendContextError.unexpectedDestination
            }
            if isAllMessagesForum, draft.sendTopic != sendContext.destinationTopic {
                throw ChatSendContextError.unexpectedDestination
            }
        } catch {
            return .retained(
                asset,
                originConsumed: false,
                message: "Couldn’t preserve the video message for sending.",
            )
        }
        if let adoptedOriginID = draft.originRecordingDraftID ?? originRecordingDraftID {
            await VideoNoteRecordingDraftStore.shared.discard(id: adoptedOriginID)
        }
        if alreadyEnqueued {
            if let temporaryMessageID = draft.temporaryMessageID {
                outgoingVideoNotes[temporaryMessageID] = draft
            }
            return .enqueued(messageID: draft.temporaryMessageID)
        }
        guard didBeginEnqueue else {
            return .retained(
                draft.asset,
                originConsumed: true,
                message: "Another video message is still being sent. Try again when it finishes.",
            )
        }

        do {
            try Task.checkCancellation()
            let activeSendContext = try resolveFrozenMediaSendContext(
                for: .videoNote,
                destination: draft.destination,
                sendTopic: draft.sendTopic,
                replyTo: draft.replyTo,
            )
            _ = try? await sendChatAction(
                .chatActionUploadingVideoNote(.init(progress: 0)),
                in: activeSendContext,
            )
            pendingVideoNote = draft
            submittingVideoDraftIDs.insert(draft.id)
            let message: Message
            if let failedSendState = draft.failedSendState {
                guard failedSendState.canRetryNow else { throw CancellationError() }
                let resent = try await client.resendMessages(
                    chatId: chatID,
                    messageIds: [failedSendState.messageID],
                    paidMessageStarCount: 0,
                    quote: nil,
                )
                guard let resentMessage = resent.messages?.first else { throw CancellationError() }
                guard activeSendContext.matches(message: resentMessage) else {
                    throw ChatSendContextError.unexpectedDestination
                }
                message = resentMessage
                draft.failedSendState = nil
            } else {
                message = try await sendMessageVideoNote(draft)
            }
            registeringVideoMessageIDs.insert(message.id)
            let registration: VideoNoteEnqueueRegistration?
            do {
                registration = try await VideoNoteFileStore.shared.registerEnqueued(
                    draft,
                    temporaryMessageID: message.id,
                )
            } catch {
                registration = nil
                videoNoteErrorMessage = "The video message was queued, but local retry state couldn’t be saved."
            }
            var deletionResolution: VideoNoteDraftResolution?
            if bufferedVideoDeletedMessageIDs.remove(message.id) != nil {
                deletionResolution = try? await VideoNoteFileStore.shared.handleMessageDeleted(
                    destination: location.draftKey,
                    temporaryMessageID: message.id,
                )
                if deletionResolution == nil,
                   registration == nil,
                   let pendingDraft = try? await VideoNoteFileStore.shared.markPending(draft)
                {
                    deletionResolution = VideoNoteDraftResolution(
                        chatID: chatID,
                        draft: pendingDraft,
                        outcome: .failed,
                        temporaryMessageID: message.id,
                    )
                }
            }
            registeringVideoMessageIDs.remove(message.id)
            bufferedVideoDeletedMessageIDs.removeAll()
            let bufferedResolution = bufferedVideoResolutions.removeValue(forKey: message.id)
            let registrationResolution = registration.flatMap { registration -> VideoNoteDraftResolution? in
                guard let outcome = registration.outcome else { return nil }
                return VideoNoteDraftResolution(
                    chatID: chatID,
                    draft: registration.draft,
                    outcome: outcome,
                    temporaryMessageID: message.id,
                )
            }
            pendingVideoNote = nil
            pendingVideoReplyMessage = nil
            hasPendingVideoNote = false
            submittingVideoDraftIDs.remove(draft.id)
            let resolution = bufferedResolution ?? registrationResolution ?? deletionResolution
            if let resolution {
                handleVideoNoteDraftResolution(resolution)
            } else {
                outgoingVideoNotes[message.id] = registration?.draft ?? draft
            }
            if let replyTo = draft.replyTo,
               getMessageReplyTo(from: replyMessage) == replyTo
            {
                cancelReply()
            }
            _ = try? await cancelChatAction(in: activeSendContext)
            if registration != nil, resolution?.outcome != .failed {
                videoNoteErrorMessage = nil
            }
            if let resolution, resolution.outcome == .failed {
                return .retained(
                    resolution.draft.asset,
                    originConsumed: true,
                    message: "Couldn’t upload the video message. You can retry without recording again.",
                )
            }
            await clearRouteDraftAfterMediaSend(draft.destination)
            return .enqueued(messageID: message.id)
        } catch is CancellationError {
            if didBeginEnqueue {
                submittingVideoDraftIDs.remove(draft.id)
                draft = await (try? VideoNoteFileStore.shared.markPending(
                    draft,
                    failedSendState: draft.failedSendState,
                )) ?? draft
                activatePendingVideoDraft(draft)
            }
            return .retained(
                draft.asset,
                originConsumed: true,
                message: "Video message sending was cancelled.",
            )
        } catch {
            if didBeginEnqueue {
                submittingVideoDraftIDs.remove(draft.id)
                draft = await (try? VideoNoteFileStore.shared.markPending(
                    draft,
                    failedSendState: draft.failedSendState,
                )) ?? draft
                activatePendingVideoDraft(draft)
            }
            _ = try? await tdSendFrozenMediaChatAction(
                .chatActionCancel,
                sendTopic: draft.sendTopic,
                replyTo: draft.replyTo,
            )
            return .retained(
                draft.asset,
                originConsumed: true,
                message: "Couldn’t send the video message. You can retry without recording again.",
            )
        }
    }

    func retryPendingVideoNote() {
        guard videoRetryTask == nil,
              let draft = pendingVideoNote,
              canRetryPendingVideoNote
        else { return }
        beginVideoSendTransition(for: draft.id)
        retryingVideoNote = true
        videoRetryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                retryingVideoNote = false
                videoRetryTask = nil
            }
            let result = await submitVideoNote(
                draft.asset,
                originRecordingDraftID: draft.originRecordingDraftID,
                replyingTo: pendingVideoReplyMessage,
                storedReplyMessageID: draft.replyMessageID,
                storedReplyTo: draft.replyTo,
                storedSendTopic: draft.sendTopic,
            )
            switch result {
            case .enqueued(let messageID):
                if let messageID {
                    acceptVideoSendTransition(for: draft.id, messageID: messageID)
                } else {
                    cancelVideoSendTransition(for: draft.id)
                }
            case .retained(_, _, let message):
                cancelVideoSendTransition(for: draft.id)
                videoNoteErrorMessage = message
            }
        }
    }

    func discardPendingVideoNote() {
        guard videoRetryTask == nil else {
            videoNoteErrorMessage = "Wait for the current video-message retry to finish."
            return
        }
        guard let draft = pendingVideoNote else { return }
        cancelVideoSendTransition(for: draft.id)
        pendingVideoNote = nil
        hasPendingVideoNote = false
        let knownReply = pendingVideoReplyMessage
        pendingVideoReplyMessage = nil
        videoRetryAvailabilityTask?.cancel()
        videoRetryAvailabilityTask = nil
        Task { [weak self] in
            await VideoNoteFileStore.shared.remove(draft)
            await self?.promoteNextPendingVideoDraft()
        }
        restoreVideoReplyIfNeeded(from: draft, knownReply: knownReply)
    }

    func discardVideoNoteAsset(_ asset: VideoNoteAsset) async {
        guard let draft = pendingVideoNote,
              draft.fileURL.standardizedFileURL == asset.url.standardizedFileURL
        else {
            await VideoNoteFileStore.shared.discardAsset(at: asset.url)
            return
        }
        cancelVideoSendTransition(for: draft.id)
        let knownReply = pendingVideoReplyMessage
        pendingVideoNote = nil
        pendingVideoReplyMessage = nil
        hasPendingVideoNote = false
        videoNoteErrorMessage = nil
        videoRetryAvailabilityTask?.cancel()
        videoRetryAvailabilityTask = nil
        await VideoNoteFileStore.shared.remove(draft)
        restoreVideoReplyIfNeeded(from: draft, knownReply: knownReply)
        await promoteNextPendingVideoDraft()
    }

    func handleVideoNoteDraftResolution(_ resolution: VideoNoteDraftResolution) {
        if registeringVideoMessageIDs.contains(resolution.temporaryMessageID)
            || submittingVideoDraftIDs.contains(resolution.draft.id)
        {
            bufferedVideoResolutions[resolution.temporaryMessageID] = resolution
            return
        }
        outgoingVideoNotes.removeValue(forKey: resolution.temporaryMessageID)
        switch resolution.outcome {
        case .failed:
            if pendingVideoNote == nil || pendingVideoNote?.id == resolution.draft.id {
                activatePendingVideoDraft(resolution.draft)
                videoNoteErrorMessage = pendingVideoRetryStatusMessage
                    ?? "Couldn’t upload the video message. You can retry without recording again."
            }
        case .succeeded:
            if pendingVideoNote?.id == resolution.draft.id {
                pendingVideoNote = nil
                pendingVideoReplyMessage = nil
                hasPendingVideoNote = false
            }
            Task { [weak self] in await self?.promoteNextPendingVideoDraft() }
        }
    }

    func handlePotentialVideoMessageDeletions(_ messageIDs: [Int64]) {
        if !submittingVideoDraftIDs.isEmpty
            || !registeringVideoMessageIDs.isEmpty
            || retryingVideoNote
        {
            bufferedVideoDeletedMessageIDs.formUnion(messageIDs)
            return
        }
        guard let draft = pendingVideoNote,
              draft.enqueueStartedAt == nil,
              let failedMessageID = draft.failedSendState?.messageID,
              messageIDs.contains(failedMessageID)
        else { return }
        pendingVideoNote = nil
        pendingVideoReplyMessage = nil
        hasPendingVideoNote = false
        videoNoteErrorMessage = nil
        Task { [weak self] in
            await VideoNoteFileStore.shared.remove(draft)
            await self?.promoteNextPendingVideoDraft()
        }
    }

    func beginMessageEditing(_ message: CustomMessage) {
        composerEditState.changeSession()
        editCustomMessage = message
        setEditMessageText(from: message.message)
    }

    func cancelMessageEditing() {
        composerEditState.changeSession()
        editCustomMessage = nil
        editMessageText = ""
    }

    func updateDraft() async {
        guard editCustomMessage == nil else { return }
        do {
            let context = try resolveSendContext(
                for: .text,
                replyingTo: replyMessage,
                useCurrentReplyOverride: true,
            )
            try await updateDraft(in: context, replyTo: context.replyTo)
        } catch {
            if !(error is CancellationError) {
                log("Chat draft update failed: \(error)")
            }
        }
    }

    func getMessageReplyTo(from customMessage: CustomMessage?) -> InputMessageReplyTo? {
        guard let customMessage else { return replyInputOverride }
        return MessageReplyInputBuilder.make(
            currentChatID: chatID,
            target: customMessage.message,
            override: customMessage === replyMessage ? replyInputOverride : nil,
            quote: customMessage === replyMessage ? replyQuote : nil,
        )
    }

    func startTimer() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let audioRecorder else { return }
                audioRecorder.updateMeters()
                wave.append(audioRecorder.peakPower(forChannel: 0))
                updateVoiceRecordingDuration()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerCount = 0
        voiceRecordingTimerBaseline = 0
        voiceRecordingLastRecorderTime = 0
    }
    
    func tdSendChatAction(_ chatAction: ChatAction) async throws {
        guard locationContextIsCurrent else { throw ChatSendContextError.accountUnavailable }
        if case .chatActionCancel = chatAction {
            if let context = desiredChatActionContext ?? activeChatActionContext {
                try await cancelChatAction(in: context)
            } else if !isAllMessagesForum {
                chatActionRouteRevision &+= 1
                desiredChatAction = nil
                try await client.sendChatAction(
                    action: chatAction,
                    businessConnectionId: nil,
                    chatId: location.chatID,
                    topicId: location.topic,
                )
            } else {
                chatActionRouteRevision &+= 1
                desiredChatAction = nil
            }
            return
        }
        let kind = sendContentKind(for: chatAction)
        let context = try resolveSendContext(
            for: kind,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        try await sendChatAction(chatAction, in: context)
    }

    func tdSendFrozenMediaChatAction(
        _ chatAction: ChatAction,
        sendTopic: MessageTopic?,
        replyTo: InputMessageReplyTo?,
    ) async throws {
        guard let accountID = location.accountID,
              locationContextIsCurrent
        else { throw ChatSendContextError.accountUnavailable }
        if case .chatActionCancel = chatAction {
            guard !isAllMessagesForum || sendTopic != nil else {
                throw ChatSendContextError.unexpectedDestination
            }
            let context = ResolvedSendContext(
                accountID: accountID,
                chatID: location.chatID,
                clientID: location.clientID,
                destinationTopic: sendTopic ?? location.topic,
                draftTopic: location.topic,
                replyTo: replyTo,
            )
            try await cancelChatAction(in: context)
            return
        }
        let context = try resolveFrozenMediaSendContext(
            for: sendContentKind(for: chatAction),
            destination: location.draftKey,
            sendTopic: sendTopic,
            replyTo: replyTo,
        )
        try await sendChatAction(chatAction, in: context)
    }

    @MainActor func mediaStartRecordingVoice() async -> Bool {
        let replySnapshot = replyMessage
        guard !voiceRecordingLifecycle.isSuspended,
              canRecordVoiceNote,
              locationContextIsCurrent,
              let initialContext = try? resolveSendContext(
                  for: .voiceNote,
                  replyingTo: replySnapshot,
                  useCurrentReplyOverride: true,
              )
        else { return false }
        guard !loadingVoiceDraft,
              !startingVoiceNote,
              !recordingVoiceNote,
              !finalizingVoiceNote,
              pendingVoiceNote == nil
        else { return false }
        startingVoiceNote = true
        let interactionGeneration = voiceRecordingLifecycle.generation
        defer { startingVoiceNote = false }
        wave.removeAll(keepingCapacity: true)
        timerCount = 0
        voiceRecordingTimerBaseline = 0
        voiceRecordingLastRecorderTime = 0
        
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            log("Access to Microphone for Voice messages is granted")
        } else {
            log("Access to Microphone for Voice messages is not granted")
            errorShown = true
            await promoteNextPendingVoiceDraft()
            return false
        }
        guard !Task.isCancelled, voiceRecordingLifecycle.permitsContinuation(interactionGeneration),
              pendingVoiceNote == nil, !recordingVoiceNote, !finalizingVoiceNote
        else {
            await promoteNextPendingVoiceDraft()
            return false
        }
        guard let recordingContext = try? resolveFrozenMediaSendContext(
            for: .voiceNote,
            destination: initialContext.draftKey,
            sendTopic: initialContext.destinationTopic,
            replyTo: initialContext.replyTo,
        ) else { return false }
        activeVoiceRecordingContext = recordingContext
        pendingVoiceReplyMessage = replySnapshot
        Media.shared.setAudioSessionRecord()
        Media.shared.stop()
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav")
        recordingVoiceNoteURL = url
        
        do {
            let recorder = try makeVoiceRecorder(url: url)
            audioRecorder = recorder
            recordingVoiceNote = true
            voiceRecordingInteractionState = .holding
            voiceRecordingTimerBaseline = 0
            voiceRecordingLastRecorderTime = recorder.currentTime
            startTimer()
            Task { [weak self] in
                guard let self else { return }
                _ = try? await sendChatAction(.chatActionRecordingVoiceNote, in: recordingContext)
            }
            return true
        } catch {
            log("Error creating AudioRecorder: \(error)")
            try? FileManager.default.removeItem(at: url)
            recordingVoiceNoteURL = nil
            audioRecorder = nil
            activeVoiceRecordingContext = nil
            pendingVoiceReplyMessage = nil
            voiceRecordingInteractionState = .idle
            Media.shared.endAudioSessionRecord()
            voiceNoteErrorMessage = "Couldn’t start voice recording."
            await promoteNextPendingVoiceDraft()
            return false
        }
    }
    
    func mediaStopRecordingVoice() {
        guard !voiceRecordingLifecycle.isSuspended else { return }
        switch voiceRecordingInteractionState {
        case .preview:
            sendVoiceRecordingPreview()
        case .locked where activeVoiceRecordingDraft != nil:
            closeVoiceRecordingSegment(sendAfterPreparation: true)
        case .holding, .locked:
            finishVoiceRecording(sendWhenReady: true, pendingMessage: nil)
        case .idle, .pausing, .resuming:
            break
        }
    }

    func lockVoiceRecording() {
        guard recordingVoiceNote, voiceRecordingInteractionState == .holding else { return }
        voiceRecordingInteractionState = .locked
    }

    func pauseVoiceRecording() {
        closeVoiceRecordingSegment(sendAfterPreparation: false)
    }

    func resumeVoiceRecordingInteraction() {
        voiceRecordingLifecycle.resumeInteraction()
    }

    /// Lifecycle teardown preserves a recording; only explicit Delete/cancel discards it.
    func suspendVoiceRecording() {
        guard voiceRecordingLifecycle.suspend() else { return }
        preserveVoiceRecordingCheckpoint()
    }

    func resumeVoiceRecording(confirmingTrim: Bool = false) {
        guard !voiceRecordingLifecycle.isSuspended,
              recordingVoiceNote,
              voiceRecordingInteractionState == .preview,
              voiceRecordingDraftTask == nil,
              voiceRecordingTrimTask == nil,
              !voiceRecordingTrimIsUpdating,
              let draft = activeVoiceRecordingDraft
        else { return }
        let range = draft.effectiveRange
        if range.lowerBound > 0.000_001 || abs(range.upperBound - draft.exactDuration) > 0.000_001 {
            guard confirmingTrim else { return }
            materializeVoiceRecordingTrim(draft, continuation: .resume)
            return
        }
        beginVoiceRecordingResume(draft)
    }

    func toggleVoiceRecordingPreview() {
        guard !voiceRecordingLifecycle.isSuspended,
              voiceRecordingInteractionState == .preview,
              let draft = activeVoiceRecordingDraft
        else { return }
        if voiceRecordingPreviewPlayer.isPlaybackRequested {
            voiceRecordingPreviewPlayer.pause()
            releaseVoiceRecordingPreviewAudioSession()
            return
        }
        activateVoiceRecordingPreviewAudioSession()
        if voiceRecordingPreviewLoadedURL != draft.fileURL {
            loadVoiceRecordingPreview(draft)
        }
        let range = draft.effectiveRange
        if voiceRecordingPreviewPosition < range.lowerBound || voiceRecordingPreviewPosition >= range.upperBound {
            voiceRecordingPreviewPlayer.seek(to: range.lowerBound)
            voiceRecordingPreviewPosition = range.lowerBound
        }
        voiceRecordingPreviewPlayer.play()
    }

    func seekVoiceRecordingPreview(to progress: CGFloat) {
        guard voiceRecordingInteractionState == .preview,
              let draft = activeVoiceRecordingDraft
        else { return }
        if voiceRecordingPreviewLoadedURL != draft.fileURL {
            loadVoiceRecordingPreview(draft)
        }
        let range = draft.effectiveRange
        let boundedProgress = min(1, max(0, Double(progress)))
        let position = min(range.upperBound, max(range.lowerBound, draft.exactDuration * boundedProgress))
        voiceRecordingPreviewPlayer.seek(to: position)
        voiceRecordingPreviewPosition = position
    }

    func updateVoiceRecordingTrim(
        start: Double,
        end: Double,
        updatedEnd: Bool,
        finished: Bool,
    ) {
        guard voiceRecordingInteractionState == .preview,
              voiceRecordingDraftTask == nil,
              voiceRecordingTrimTask == nil,
              let previousDraft = activeVoiceRecordingDraft,
              previousDraft.exactDuration >= 2
        else { return }
        let duration = previousDraft.exactDuration
        let minimumDuration = min(duration, 1.0)
        var lowerBound = max(0, min(start, duration))
        var upperBound = max(0, min(end, duration))
        if upperBound - lowerBound < minimumDuration {
            if updatedEnd {
                upperBound = min(duration, lowerBound + minimumDuration)
                lowerBound = min(lowerBound, upperBound - minimumDuration)
            } else {
                lowerBound = max(0, upperBound - minimumDuration)
                upperBound = max(upperBound, lowerBound + minimumDuration)
            }
        }
        guard lowerBound < upperBound else { return }
        if !voiceRecordingTrimIsUpdating {
            voiceRecordingTrimBaseDraft = previousDraft
        }
        let canonicalDraft = voiceRecordingTrimBaseDraft ?? previousDraft
        voiceRecordingTrimIsUpdating = true
        voiceRecordingPreviewPlayer.pause()
        releaseVoiceRecordingPreviewAudioSession()
        var editedDraft = previousDraft
        if lowerBound <= 0.000_001, abs(upperBound - duration) <= 0.000_001 {
            editedDraft.trimStart = nil
            editedDraft.trimEnd = nil
        } else {
            editedDraft.trimStart = lowerBound
            editedDraft.trimEnd = upperBound
        }
        activeVoiceRecordingDraft = editedDraft
        voiceRecordingPreviewPosition = min(upperBound, max(lowerBound, voiceRecordingPreviewPosition))
        voiceRecordingPreviewPlayer.seek(to: voiceRecordingPreviewPosition)
        guard finished else { return }
        voiceRecordingTrimGeneration &+= 1
        let generation = voiceRecordingTrimGeneration
        let range = lowerBound..<upperBound
        let interactionGeneration = voiceRecordingLifecycle.generation
        let shouldPreviewAfterSave = !voiceRecordingLifecycle.isSuspended
        voiceRecordingTrimTask = VoiceRecordingDraftPreservation.start(for: location.draftKey) { [self] in
            do {
                let storedDraft = try await VoiceRecordingDraftStore.shared.updateTrim(
                    in: canonicalDraft,
                    range: range,
                )
                try Task.checkCancellation()
                guard voiceRecordingTrimGeneration == generation,
                      activeVoiceRecordingDraft?.id == storedDraft.id
                else { return }
                activeVoiceRecordingDraft = storedDraft
                voiceRecordingTrimTask = nil
                voiceRecordingTrimIsUpdating = false
                voiceRecordingTrimBaseDraft = nil
                objectWillChange.send()
                if shouldPreviewAfterSave, voiceRecordingLifecycle.permitsContinuation(interactionGeneration) {
                    previewVoiceRecordingTrimEdge(storedDraft, updatedEnd: updatedEnd)
                }
            } catch {
                guard voiceRecordingTrimGeneration == generation else { return }
                activeVoiceRecordingDraft = canonicalDraft
                voiceRecordingTrimTask = nil
                voiceRecordingTrimIsUpdating = false
                voiceRecordingTrimBaseDraft = nil
                voiceRecordingPreviewIsPlaying = false
                voiceNoteErrorMessage = "Couldn’t save the voice trim range."
                objectWillChange.send()
                loadVoiceRecordingPreview(canonicalDraft)
            }
        }
        objectWillChange.send()
    }

    func cancelVoiceRecording() {
        guard recordingVoiceNote else { return }
        voiceRecordingDraftGeneration &+= 1
        voiceRecordingDraftTask?.cancel()
        voiceRecordingDraftTask = nil
        voiceRecordingTrimGeneration &+= 1
        voiceRecordingTrimTask?.cancel()
        voiceRecordingTrimTask = nil
        voiceRecordingTrimIsUpdating = false
        voiceRecordingTrimBaseDraft = nil
        stopVoiceRecordingPreviewPlayback()
        audioRecorder?.stop()
        Media.shared.endAudioSessionRecord()
        audioRecorder = nil
        if let recordingVoiceNoteURL {
            try? FileManager.default.removeItem(at: recordingVoiceNoteURL)
        }
        recordingVoiceNoteURL = nil
        let recordingDraftID = voiceRecordingDraftID ?? activeVoiceRecordingDraft?.id
        if let recordingDraftID {
            cancelVoiceSendTransition(for: recordingDraftID)
        }
        let recordingReply = pendingVoiceReplyMessage
        let recordingReplyTo = activeVoiceRecordingDraft?.replyTo ?? activeVoiceRecordingContext?.replyTo
        activeVoiceRecordingDraft = nil
        activeVoiceRecordingContext = nil
        voiceRecordingDraftID = nil
        pendingVoiceReplyMessage = nil
        if replyMessage == nil {
            restoreReplyState(message: recordingReply, input: recordingReplyTo)
        }
        wave.removeAll(keepingCapacity: true)
        stopTimer()
        recordingVoiceNote = false
        voiceRecordingInteractionState = .idle
        Task { [weak self] in
            if let recordingDraftID {
                await VoiceRecordingDraftStore.shared.discard(id: recordingDraftID)
            }
            await self?.promoteNextPendingVoiceDraft()
            try? await self?.tdSendChatAction(.chatActionCancel)
        }
    }

    func retryPendingVoiceNote() {
        guard !voiceRecordingLifecycle.isSuspended, !loadingVoiceDraft,
              !finalizingVoiceNote,
              canRetryPendingVoiceNote,
              let pendingVoiceNote
        else { return }
        beginVoiceSendTransition(for: pendingVoiceNote.id)
        startVoiceFinalization()
    }

    func discardPendingVoiceNote() {
        guard let discardedDraft = pendingVoiceNote else { return }
        voiceFinalizationGeneration &+= 1
        let generation = voiceFinalizationGeneration
        let finalization = voiceFinalizeTask
        finalization?.cancel()
        voiceFinalizeTask = nil
        finalizingVoiceNote = finalization != nil
        cancelVoiceSendTransition(for: discardedDraft.id)
        let discardedReply = pendingVoiceReplyMessage
        voiceRetryAvailabilityTask?.cancel()
        voiceNoteErrorMessage = nil
        Task { [weak self] in
            // Cancelling a detached native encode does not stop its file access.
            // Join this VM's worker before asking the canonical owner to discard.
            await finalization?.value
            let removed = await VoiceNoteDraftStore.shared.remove(discardedDraft)
            guard let self, voiceFinalizationGeneration == generation,
                  pendingVoiceNote?.id == discardedDraft.id
            else { return }
            finalizingVoiceNote = false
            guard removed else {
                await refreshPendingVoiceDraft(id: discardedDraft.id)
                guard voiceFinalizationGeneration == generation else { return }
                if pendingVoiceNote?.id == discardedDraft.id {
                    voiceNoteErrorMessage = "This voice message is still being prepared or sent. Its file was kept."
                }
                return
            }
            pendingVoiceNote = nil
            pendingVoiceReplyMessage = nil
            pendingVoiceDraftIsFinalizing = false
            hasPendingVoiceNote = false
            restoreReplyIfNeeded(from: discardedDraft, knownReply: discardedReply)
            await promoteNextPendingVoiceDraft()
            guard voiceFinalizationGeneration == generation else { return }
            try? await tdSendChatAction(.chatActionCancel)
        }
    }

    func refreshPendingVoiceDraft(id: UUID) async {
        guard pendingVoiceNote?.id == id, !finalizingVoiceNote else { return }
        let generation = voiceFinalizationGeneration
        voiceDraftRefreshGeneration &+= 1
        let refreshGeneration = voiceDraftRefreshGeneration
        let status = await VoiceNoteDraftStore.shared.status(id: id, destination: location.draftKey)
        guard pendingVoiceNote?.id == id, !finalizingVoiceNote,
              voiceFinalizationGeneration == generation,
              voiceDraftRefreshGeneration == refreshGeneration, locationContextIsCurrent
        else { return }
        pendingVoiceDraftIsFinalizing = status.isFinalizing
        if let draft = status.draft, draft.temporaryMessageID == nil {
            pendingVoiceNote = draft
            hasPendingVoiceNote = true
        } else {
            if let draft = status.draft, let id = draft.temporaryMessageID {
                outgoingVoiceNotes[id] = draft
            }
            pendingVoiceNote = nil
            pendingVoiceReplyMessage = nil
            hasPendingVoiceNote = false
            pendingVoiceDraftIsFinalizing = false
            await promoteNextPendingVoiceDraft()
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

    func refreshAllMessagesForumTopicsIfNeeded() {
        guard isAllMessagesForum else {
            allMessagesTopicReads?.synchronize([])
            return
        }
        guard let reader = allMessagesForumReader() else { return }
        let composerTopics: [MessageTopic?] = [
            .messageTopicForum(.init(forumTopicId: 1)), // General is only the base composer's default.
            replyMessage?.message.chatId == chatID ? replyMessage?.message.topicId : nil,
            editCustomMessage?.message.chatId == chatID ? editCustomMessage?.message.topicId : nil,
            activeVoiceRecordingContext?.destinationTopic, activeVoiceRecordingDraft?.sendTopic,
            restoredVideoRecordingDraft?.sendTopic, recordingVideoTopicDemand,
            pendingVoiceNote?.sendTopic, pendingVideoNote?.sendTopic,
        ] + outgoingVoiceNotes.values.map(\.sendTopic) + outgoingVideoNotes.values.map(\.sendTopic)
        reader.synchronize(ChatForumTopicReads.demandedIDs(
            chatID: chatID, messages: messages.flatMap(\.sourceMessages), composerTopics: composerTopics,
        ))
    }

    private func refreshAllMessagesForumDeliveryStates(topicID: Int? = nil) {
        let current = isAllMessagesForum && locationContextIsCurrent && !allMessagesTopicReadsRetired
        for message in messages {
            let raw = message.deliverySourceMessage
            if let topicID {
                guard raw.chatId == location.chatID,
                      raw.topicId == .messageTopicForum(.init(forumTopicId: topicID)) else { continue }
            }
            let projection = current ? allMessagesTopicReads?.receipt(for: raw) : nil
            message.updateDeliveryState(
                permitsFinalStatus: projection?.permitsFinalStatus == true,
                readOutbox: projection?.readOutbox,
                topic: projection?.topic,
            )
        }
    }

    private func preserveVoiceRecordingCheckpoint() {
        stopVoiceRecordingPreviewPlayback()
        guard recordingVoiceNote else { return }

        switch voiceRecordingInteractionState {
        case .holding, .locked:
            updateVoiceRecordingDuration()
            voiceRecordingInteractionState = .locked
            if canPauseVoiceRecording {
                closeVoiceRecordingSegment(sendAfterPreparation: false)
            } else {
                finishVoiceRecording(
                    sendWhenReady: false,
                    pendingMessage: "Voice recording stopped before a preview could be created.",
                )
            }
        case .preview:
            // A disappearing trim control may never deliver its final touch event.
            // Commit the current range and let an already-running save finish.
            if voiceRecordingTrimIsUpdating, voiceRecordingTrimTask == nil,
               let draft = activeVoiceRecordingDraft
            {
                updateVoiceRecordingTrim(
                    start: draft.effectiveRange.lowerBound,
                    end: draft.effectiveRange.upperBound,
                    updatedEnd: false,
                    finished: true,
                )
            }
        case .idle, .pausing, .resuming:
            // Owned persistence work must finish. Its continuation observes suspension.
            break
        }
    }

    private func configureMessageRefresh(seedIDs: [Int64], visibleIDs: [Int64]) {
        let client = client
        let location = location
        guard let accountID = location.accountID else { return }
        let source = TdUpdateSource(accountID: accountID, clientID: client.id)
        messageRefresh = ChatHistoryRestorationRefresh(
            location: location, source: source, seedIDs: seedIDs, visibleIDs: visibleIDs,
            currentSource: { [weak self] in
                self?.locationContextIsCurrent == true ? TDLib.shared.activeUpdateSource : nil
            },
            read: { try await client.getMessage(chatId: location.chatID, messageId: $0) },
            hydrate: { [weak self] message in
                guard let self else {
                    return ChatHistoryMessageValue(CustomMessage(message: message, properties: .default))
                }
                return await ChatHistoryMessageValue(getCustomMessage(from: message))
            },
            retriesPartialRaces: true,
            deliver: { [weak self] in self?.applyMessageRefresh($0) },
        )
    }

    private func applyMessageRefresh(_ delivery: ChatHistoryRestorationRefresh.Delivery) {
        guard locationContextIsCurrent, delivery.source == TDLib.shared.activeUpdateSource else { return }
        switch delivery.result {
        case .message(let value):
            let oldID = messageReplacementIDs.removeValue(forKey: delivery.messageID) ?? delivery.messageID
            let replacement = value.makeMessage()
            if let previous = messages.first(where: { $0.sourceMessages.contains { $0.id == oldID } }) {
                preservePresentationState(from: previous, in: replacement)
                replaceSourceMessage(oldID: oldID, with: replacement)
            } else {
                mergeIncomingMessages([replacement])
            }
        case .missing:
            removeMessagesFromTimeline([delivery.messageID])
        case .retry:
            break // Keep display seeds and raw pagination state while offline.
        }
    }

    private func driveMessageRefresh() {
        guard locationContextIsCurrent, !restorationWaitsForViewport, messageRefreshTask == nil,
              let refresh = messageRefresh,
              refresh.remainingCount > 0 || latestRestorationCursor != nil && !latestRestorationFailed
        else { return }
        messageRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                messageRefreshTask = nil
                if !Task.isCancelled, refresh.remainingCount > 0 { driveMessageRefresh() }
            }
            while !Task.isCancelled, locationContextIsCurrent {
                if await refresh.refreshNextBatch() { continue }
                guard !latestRestorationFailed, var cursor = latestRestorationCursor,
                      let token = refresh.beginLatestRead() else { break }
                guard let page = await loadHistory(fromMessageId: cursor.fromMessageID, limit: 30, offset: 0),
                      !Task.isCancelled, locationContextIsCurrent
                else {
                    latestRestorationFailed = !refresh.failLatestRead(token: token)
                    if latestRestorationFailed { break }
                    continue
                }
                guard cursor.accept(rawPage: page, requestedFromMessageID: cursor.fromMessageID),
                      refresh.enqueueLatest(page, token: token)
                else {
                    latestRestorationFailed = !refresh.failLatestRead(token: token)
                    if latestRestorationFailed { break }
                    continue
                }
                latestRestorationCursor = cursor.isComplete ? nil : cursor
            }
        }
    }

    private func settleMessageMutation(_ id: Int64, owner: ChatHistoryRestorationRefresh.MutationOwner) {
        // Reaction and pin work may overlap for one wrapper. The last owner
        // releases it on success, failure or cancellation, never mid-operation.
        messageRefresh?.setMutationBlocked(false, messageID: id, owner: owner)
        driveMessageRefresh()
    }

    private func composerRestorationState() -> ChatComposerRestorationState {
        ChatComposerRestorationState(
            location: location,
            revision: composerRevision,
            text: text,
            edit: editCustomMessage.map { .init(target: .init($0), text: editMessageText) },
            replyMessage: replyMessage.map(ChatComposerRestorationState.MessageValue.init),
            replyTo: getMessageReplyTo(from: replyMessage),
            images: displayedImages,
            documents: displayedDocuments,
            sendError: sendErrorMessage,
            draftError: draftErrorMessage,
        )
    }

    private func seedComposerRestoration(_ seed: ChatComposerRestorationState) {
        markComposerDirty()
        text = seed.text
        editCustomMessage = seed.edit?.target.makeMessage()
        editMessageText = seed.edit?.text ?? ""
        replyMessage = seed.replyMessage?.makeMessage()
        replyInputOverride = seed.replyTo
        replyQuote = inputQuote(from: seed.replyTo)
        replyFallbackPresentation = replyMessage == nil
            ? seed.replyTo.map { MessageReplyPresentation.fallback(for: $0, currentChatID: chatID) }
            : nil
        displayedImages = seed.images
        displayedDocuments = seed.documents
        sendErrorMessage = seed.sendError
        draftErrorMessage = seed.draftError
    }

    private func editMessage(_ attempt: ChatComposerEditState.Attempt) async throws {
        let message = attempt.message
        let context = try resolveEditContext(for: message)
        try Task.checkCancellation()
        switch message.content {
        case .messageText:
            _ = try await client.editMessageText(
                chatId: context.chatID,
                inputMessageContent:
                .inputMessageText(
                    .init(
                        clearDraft: false,
                        linkPreviewOptions: nil,
                        text: attempt.text,
                    ),
                ),
                messageId: message.id,
                replyMarkup: nil,
            )
        case .messageAnimation, .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
            _ = try await client.editMessageCaption(
                caption: attempt.text,
                chatId: context.chatID,
                messageId: message.id,
                replyMarkup: nil,
                showCaptionAboveMedia: false,
            )
        default:
            throw ChatSendContextError.chatPermissionDenied
        }
    }

    private func setEditMessageText(from message: Message?) {
        switch message?.content {
        case .messageText(let messageText):
            editMessageText = ComposerText.attributed(messageText.text)
        case .messagePhoto(let messagePhoto):
            editMessageText = ComposerText.attributed(messagePhoto.caption)
        case .messageVoiceNote(let messageVoiceNote):
            editMessageText = ComposerText.attributed(messageVoiceNote.caption)
        case .messageAnimation(let messageAnimation):
            editMessageText = ComposerText.attributed(messageAnimation.caption)
        case .messageAudio(let messageAudio):
            editMessageText = ComposerText.attributed(messageAudio.caption)
        case .messageDocument(let messageDocument):
            editMessageText = ComposerText.attributed(messageDocument.caption)
        case .messageVideo(let messageVideo):
            editMessageText = ComposerText.attributed(messageVideo.caption)
        default:
            break
        }
    }

    private func updateDraft(
        in context: ResolvedSendContext,
        replyTo: InputMessageReplyTo?,
    ) async throws {
        let draftMessage: DraftMessage? =
            if text.characters.isEmpty, replyTo == nil {
                nil
            } else {
                DraftMessage(
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
                    replyTo: replyTo,
                    suggestedPostInfo: nil,
                )
            }
        try await client.setChatDraftMessage(
            chatId: context.chatID,
            draftMessage: draftMessage,
            topicId: context.draftTopic,
        )
    }

    private func retainOutgoingDocumentFiles(
        messages: [Message],
        documents: [SelectedDocument],
    ) {
        for (message, document) in zip(messages, documents) {
            let resolvedMessageID = bufferedDocumentMessageIDAliases[message.id] ?? message.id
            if message.sendingState == nil
                || bufferedTerminalDocumentMessageIDs.contains(message.id)
                || bufferedTerminalDocumentMessageIDs.contains(resolvedMessageID)
            {
                outgoingDocumentURLsByMessageID[resolvedMessageID] = document.url
                releaseOutgoingDocumentFile(messageID: resolvedMessageID)
            } else {
                outgoingDocumentURLsByMessageID[resolvedMessageID] = document.url
            }
        }
        bufferedTerminalDocumentMessageIDs.removeAll()
        bufferedDocumentMessageIDAliases.removeAll()
    }

    private func forumTopicInfo(for topic: MessageTopic?) -> ForumTopicInfo? {
        guard case .messageTopicForum(let forumTopic) = topic else { return nil }
        return forumTopicsByID[forumTopic.forumTopicId]?.info
    }

    private func resolveEditContext(for message: Message) throws -> ResolvedSendContext {
        guard isAllMessagesForum else {
            let context = try resolveSendContext(for: .text, replyingTo: nil)
            guard context.matches(message: message) else {
                throw ChatSendContextError.unexpectedDestination
            }
            return context
        }
        guard let accountID = location.accountID,
              locationContextIsCurrent,
              permissionAllows(.text),
              location.matches(message: message),
              let topic = message.topicId,
              case .messageTopicForum = topic,
              let info = forumTopicInfo(for: topic)
        else { throw ChatSendContextError.topicMetadataUnavailable }
        let topicIsRestricted = info.isClosed || info.isHidden
        guard !topicIsRestricted || info.isOutgoing || canManageForumTopics else {
            throw ChatSendContextError.topicReadOnly
        }
        return ResolvedSendContext(
            accountID: accountID,
            chatID: location.chatID,
            clientID: location.clientID,
            destinationTopic: topic,
            draftTopic: nil,
            replyTo: nil,
        )
    }

    private func resolveFrozenMediaSendContext(
        for kind: ChatSendContentKind,
        destination: ChatDraftKey?,
        sendTopic: MessageTopic?,
        replyTo: InputMessageReplyTo?,
    ) throws -> ResolvedSendContext {
        guard let accountID = location.accountID,
              locationContextIsCurrent
        else { throw ChatSendContextError.accountUnavailable }
        guard permissionAllows(kind) else { throw ChatSendContextError.chatPermissionDenied }
        guard destination == location.draftKey else { throw ChatSendContextError.unexpectedDestination }
        if isAllMessagesForum {
            guard let sendTopic,
                  case .messageTopicForum = sendTopic,
                  let info = forumTopicInfo(for: sendTopic)
            else { throw ChatSendContextError.topicMetadataUnavailable }
            if replyTo != nil {
                guard !info.isClosed, !info.isHidden else {
                    throw ChatSendContextError.topicReadOnly
                }
            } else {
                guard info.isGeneral else { throw ChatSendContextError.unexpectedDestination }
                if info.isClosed || info.isHidden {
                    guard canManageForumTopics else { throw ChatSendContextError.topicReadOnly }
                }
            }
            return ResolvedSendContext(
                accountID: accountID,
                chatID: location.chatID,
                clientID: location.clientID,
                destinationTopic: sendTopic,
                draftTopic: nil,
                replyTo: replyTo,
            )
        }
        let current = try resolveSendContext(for: kind, replyingTo: nil)
        let resolvedSendTopic = sendTopic ?? destination?.topic
        guard current.destinationTopic == resolvedSendTopic else {
            throw ChatSendContextError.unexpectedDestination
        }
        return ResolvedSendContext(
            accountID: current.accountID,
            chatID: current.chatID,
            clientID: current.clientID,
            destinationTopic: resolvedSendTopic,
            draftTopic: current.draftTopic,
            replyTo: replyTo,
        )
    }

    private func refreshForumTopicIfNeeded(_ topic: MessageTopic?) {
        guard isAllMessagesForum,
              case .messageTopicForum(let forumTopic) = topic
        else { return }
        refreshForumTopic(id: forumTopic.forumTopicId)
    }

    private func sendChatAction(
        _ action: ChatAction,
        in context: ResolvedSendContext,
    ) async throws {
        chatActionRouteRevision &+= 1
        let revision = chatActionRouteRevision
        desiredChatAction = action
        desiredChatActionContext = context
        if let active = activeChatActionContext,
           !sameChatActionDestination(active, context)
        {
            _ = try? await client.sendChatAction(
                action: .chatActionCancel,
                businessConnectionId: nil,
                chatId: active.chatID,
                topicId: active.destinationTopic,
            )
        }
        guard chatActionRouteRevision == revision else {
            await reconcileDesiredChatAction(after: revision)
            throw CancellationError()
        }
        try await client.sendChatAction(
            action: action,
            businessConnectionId: nil,
            chatId: context.chatID,
            topicId: context.destinationTopic,
        )
        guard chatActionRouteRevision == revision else {
            await reconcileDesiredChatAction(after: revision)
            throw CancellationError()
        }
        activeChatAction = action
        activeChatActionContext = context
    }

    private func reconcileDesiredChatAction(after staleRevision: UInt64) async {
        let revision = chatActionRouteRevision
        guard revision != staleRevision,
              let context = desiredChatActionContext,
              locationContextIsCurrent
        else { return }
        let action = desiredChatAction ?? .chatActionCancel
        _ = try? await client.sendChatAction(
            action: action,
            businessConnectionId: nil,
            chatId: context.chatID,
            topicId: context.destinationTopic,
        )
        guard chatActionRouteRevision == revision else {
            await reconcileDesiredChatAction(after: revision)
            return
        }
        if let desiredChatAction {
            activeChatAction = desiredChatAction
            activeChatActionContext = context
        } else if activeChatActionContext.map({ sameChatActionDestination($0, context) }) == true {
            activeChatAction = nil
            activeChatActionContext = nil
        }
    }

    private func reconcileActiveChatActionAfterReplyChange() {
        guard let previousContext = desiredChatActionContext ?? activeChatActionContext,
              let previousAction = desiredChatAction ?? activeChatAction
        else { return }
        let nextContext = try? resolveSendContext(
            for: sendContentKind(for: previousAction),
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        guard nextContext.map({ !sameChatActionDestination(previousContext, $0) }) ?? true else { return }
        chatActionRouteRevision &+= 1
        let revision = chatActionRouteRevision
        activeChatAction = nil
        activeChatActionContext = nil
        desiredChatAction = nil
        desiredChatActionContext = previousContext
        let client = client
        Task { [weak self] in
            _ = try? await client.sendChatAction(
                action: .chatActionCancel,
                businessConnectionId: nil,
                chatId: previousContext.chatID,
                topicId: previousContext.destinationTopic,
            )
            guard let self else { return }
            guard chatActionRouteRevision == revision else {
                await reconcileDesiredChatAction(after: revision)
                return
            }
            guard locationContextIsCurrent,
                  case .chatActionTyping = previousAction,
                  !text.characters.isEmpty,
                  let nextContext = try? resolveSendContext(
                      for: .text,
                      replyingTo: replyMessage,
                      useCurrentReplyOverride: true,
                  )
            else { return }
            _ = try? await sendChatAction(.chatActionTyping, in: nextContext)
        }
    }

    private func sendContentKind(for action: ChatAction) -> ChatSendContentKind {
        switch action {
        case .chatActionUploadingDocument:
            .document
        case .chatActionRecordingVoiceNote, .chatActionUploadingVoiceNote:
            .voiceNote
        case .chatActionRecordingVideoNote, .chatActionUploadingVideoNote:
            .videoNote
        case .chatActionUploadingPhoto:
            .photo
        default:
            .text
        }
    }

    private func preservePresentationState(from previous: CustomMessage, in replacement: CustomMessage) {
        replacement.isReplyQuoteExpanded = previous.isReplyQuoteExpanded
        if let forward = previous.forwardPresentation,
           forward.navigationTarget == nil, forward.targetMessageID != nil,
           forward.targetChatID == replacement.forwardPresentation?.targetChatID,
           forward.targetMessageID == replacement.forwardPresentation?.targetMessageID
        {
            replacement.forwardPresentation = replacement.forwardPresentation?.removingNavigationTarget()
        }
    }

    private func canonicalMessages(
        merging existing: [CustomMessage],
        with incoming: [CustomMessage],
        replacingExisting: Bool = false,
    ) -> [CustomMessage] {
        var result = existing
        for candidate in incoming {
            guard let index = result.firstIndex(where: { $0.displayedID == candidate.displayedID }) else {
                if case .album = candidate.displayedID {
                    candidate.album = deduplicatedAlbumMessages(candidate.sourceMessages)
                }
                result.append(candidate)
                continue
            }
            let current = result[index]
            if replacingExisting { preservePresentationState(from: current, in: candidate) }
            guard case .album = candidate.displayedID else {
                if replacingExisting {
                    result[index] = candidate
                    if replyMessage?.id == candidate.id { replyMessage = candidate }
                }
                continue
            }
            let combined = deduplicatedAlbumMessages(replacingExisting
                ? candidate.sourceMessages + current.sourceMessages
                : current.sourceMessages + candidate.sourceMessages)
            let candidateNewest = candidate.newestSourceMessage
            let currentNewest = current.newestSourceMessage
            let candidateIsNewer = candidateNewest.date == currentNewest.date
                ? candidateNewest.id > currentNewest.id
                : candidateNewest.date > currentNewest.date
            let representative = candidateIsNewer || replacingExisting && candidate.id == current.id
                ? candidate
                : current
            representative.album = combined
            result[index] = representative
        }
        return result.sorted { lhs, rhs in
            let left = lhs.newestSourceMessage
            let right = rhs.newestSourceMessage
            return left.date == right.date ? left.id > right.id : left.date > right.date
        }
    }

    private func deduplicatedAlbumMessages(_ messages: [Message]) -> [Message] {
        var seen = Set<Int64>()
        return messages
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date
            }
    }

    private func queueForumTopicDemandRefresh() {
        guard !forumTopicDemandRefreshQueued, !allMessagesTopicReadsRetired, isAllMessagesForum else { return }
        forumTopicDemandRefreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            forumTopicDemandRefreshQueued = false
            refreshAllMessagesForumTopicsIfNeeded()
        }
    }

    private func allMessagesForumReader() -> ChatForumTopicReads? {
        guard isAllMessagesForum, locationContextIsCurrent, !allMessagesTopicReadsRetired else { return nil }
        if let allMessagesTopicReads { return allMessagesTopicReads }
        let client = client
        let chatID = chatID
        let reader = ChatForumTopicReads(
            location: location,
            currentSource: { TDLib.shared.activeUpdateSource },
            read: { try await client.getForumTopic(chatId: chatID, forumTopicId: $0) },
            publish: { [weak self] id, value in
                guard let self else { return }
                if value != nil {
                    guard locationContextIsCurrent, isAllMessagesForum, !allMessagesTopicReadsRetired else { return }
                }
                guard forumTopicsByID[id] != value else { return }
                forumTopicsByID[id] = value
                messagesDidChange.send()
            },
            receiptChanged: { [weak self] id in
                self?.refreshAllMessagesForumDeliveryStates(topicID: id)
            },
        )
        allMessagesTopicReads = reader
        return reader
    }

    private func permissionAllows(_ kind: ChatSendContentKind) -> Bool {
        guard customChat.canPostMessages else { return false }
        let permissions = currentChatPermissions
        return switch kind {
        case .animation, .sticker:
            permissions.canSendOtherMessages
        case .document:
            permissions.canSendDocuments
        case .photo:
            permissions.canSendPhotos
        case .text:
            permissions.canSendBasicMessages
        case .videoNote:
            permissions.canSendVideoNotes
        case .voiceNote:
            permissions.canSendVoiceNotes
        }
    }

    private func removeTemporaryDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            SelectedDocumentFileStore.removeUnleased(urls)
        }
    }

    private func markComposerDirty() {
        composerRevision &+= 1
        composerIsDirty = true
        awaitingAuthoritativeDraftClear = false
        cancelPendingDraftClearRetry()
    }

    private func applyAuthoritativeDraft(
        _ draft: DraftMessage?,
        expectedRevision: UInt64,
    ) {
        guard !composerIsDirty, composerRevision == expectedRevision else { return }
        text =
            if let draft,
            case .draftMessageContentText(let content) = draft.content {
                ComposerText.attributed(content.text)
            } else {
                ""
            }
        let replyTo = draft?.replyTo
        replySelectionGeneration &+= 1
        let generation = replySelectionGeneration
        guard let replyTo else {
            restoreReplyState(message: nil, input: nil)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let replyMessage = await getInputReplyToMessage(replyTo)
            guard !composerIsDirty,
                  composerRevision == expectedRevision,
                  replySelectionGeneration == generation
            else { return }
            if case .inputMessageReplyToMessage = replyTo, replyMessage == nil {
                restoreReplyState(message: nil, input: nil)
            } else {
                restoreReplyState(message: replyMessage, input: replyTo)
            }
        }
    }

    private func validateStoredReply(
        _ replyTo: InputMessageReplyTo?,
        in context: ResolvedSendContext,
    ) async throws {
        guard case .inputMessageReplyToMessage(let reply) = replyTo else { return }
        guard let target = try? await client.getMessage(
            chatId: context.chatID,
            messageId: reply.messageId,
        ),
            context.matches(message: target)
        else { throw ChatSendContextError.crossTopicReply }
    }

    private func cancelChatAction(in context: ResolvedSendContext) async throws {
        guard TDLib.shared.activeAccountID == context.accountID,
              TDLib.shared.activeClient.id == context.clientID
        else { throw ChatSendContextError.accountUnavailable }
        chatActionRouteRevision &+= 1
        let revision = chatActionRouteRevision
        desiredChatAction = nil
        desiredChatActionContext = context
        try await client.sendChatAction(
            action: .chatActionCancel,
            businessConnectionId: nil,
            chatId: context.chatID,
            topicId: context.destinationTopic,
        )
        guard chatActionRouteRevision == revision else {
            await reconcileDesiredChatAction(after: revision)
            return
        }
        if let activeChatActionContext,
           sameChatActionDestination(activeChatActionContext, context)
        {
            activeChatAction = nil
            self.activeChatActionContext = nil
        }
    }

    private func sameChatActionDestination(
        _ lhs: ResolvedSendContext,
        _ rhs: ResolvedSendContext,
    ) -> Bool {
        lhs.accountID == rhs.accountID
            && lhs.clientID == rhs.clientID
            && lhs.chatID == rhs.chatID
            && lhs.destinationTopic == rhs.destinationTopic
    }

    private func loadHistory(
        fromMessageId: Int64,
        limit: Int,
        offset: Int,
    ) async -> [Message]? {
        guard locationContextIsCurrent else { return nil }
        let loaded: [Message]? =
            if let forumTopicID = location.forumTopicID {
                try? await client.getForumTopicHistory(
                    chatId: location.chatID,
                    forumTopicId: forumTopicID,
                    fromMessageId: fromMessageId,
                    limit: limit,
                    offset: offset,
                )
                .messages
            } else {
                try? await client.getChatHistory(
                    chatId: location.chatID,
                    fromMessageId: fromMessageId,
                    limit: limit,
                    offset: offset,
                    onlyLocal: false,
                )
                .messages
            }
        guard locationContextIsCurrent else { return nil }
        return loaded
    }

    private func setMessagePinned(
        _ message: CustomMessage,
        pinned: Bool,
        disableNotification: Bool,
        onlyForSelf: Bool,
    ) {
        guard supportsPinnedMessages,
              message.album.isEmpty,
              message.message.topicId == nil,
              pinMutationTasks.isEmpty,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id,
              messages.contains(where: { $0 === message })
        else { return }
        let generation = UUID()
        let messageID = message.id
        pinnedMessageGeneration &+= 1
        pinnedMessageTask?.cancel()
        pinnedMessageTask = nil
        let previousPinnedState = message.isPinned
        let previousPinnedMessage = pinnedMessage
        let authoritativeRevision = pinAuthoritativeRevisions[messageID, default: 0]
        let bannerRevision = pinnedMessageAuthoritativeRevision
        pinMutationGenerations[messageID] = generation
        messageRefresh?.setMutationBlocked(true, messageID: messageID, owner: .pin)
        let client = client
        pinMutationTasks[messageID] = Task { [weak self, weak message] in
            guard let self else { return }
            defer { settleMessageMutation(messageID, owner: .pin) }
            guard let message else {
                pinMutationTasks[messageID] = nil
                pinMutationGenerations[messageID] = nil
                return
            }
            do {
                guard TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else {
                    throw PinMutationFailure.accountChanged
                }
                let properties = try await client.getMessageProperties(
                    chatId: chatID,
                    messageId: messageID,
                )
                guard properties.canBePinned else {
                    throw PinMutationFailure.unavailable
                }
                guard pinMutationGenerations[messageID] == generation,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else {
                    throw PinMutationFailure.accountChanged
                }
                message.properties = properties
                message.isPinned = pinned
                if pinned {
                    pinnedMessage = message.message
                } else if pinnedMessage?.id == messageID {
                    pinnedMessage = nil
                }
                _ =
                    if pinned {
                        try await client.pinChatMessage(
                            chatId: chatID,
                            disableNotification: disableNotification,
                            messageId: messageID,
                            onlyForSelf: onlyForSelf,
                        )
                    } else {
                        try await client.unpinChatMessage(
                            chatId: chatID,
                            messageId: messageID,
                        )
                    }
                guard pinMutationGenerations[messageID] == generation,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else {
                    throw PinMutationFailure.accountChanged
                }
                pinMutationTasks[messageID] = nil
                pinMutationGenerations[messageID] = nil
                refreshPinnedMessages()
            } catch is CancellationError {
                guard pinMutationGenerations[messageID] == generation else { return }
                pinMutationTasks[messageID] = nil
                pinMutationGenerations[messageID] = nil
            } catch {
                guard pinMutationGenerations[messageID] == generation else { return }
                pinMutationTasks[messageID] = nil
                pinMutationGenerations[messageID] = nil
                if pinAuthoritativeRevisions[messageID, default: 0] == authoritativeRevision,
                   pinnedMessageAuthoritativeRevision == bannerRevision,
                   message.isPinned == pinned
                {
                    message.isPinned = previousPinnedState
                    pinnedMessage = previousPinnedMessage
                }
                pinErrorMessage =
                    switch error as? PinMutationFailure {
                    case .accountChanged:
                        "The active Telegram account changed."
                    case .unavailable:
                        "This message can no longer be pinned."
                    case nil:
                        pinned
                            ? "The message couldn't be pinned."
                            : "The message couldn't be unpinned."
                    }
                if TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id
                {
                    refreshPinnedMessages()
                }
            }
        }
    }

    private func resolveStoredReply(
        replyTo: InputMessageReplyTo?,
        legacyMessageID: Int64?,
    ) async -> CustomMessage? {
        if let resolved = await getInputReplyToMessage(replyTo) {
            return resolved
        }
        let allowsLegacyCurrentChatFallback =
            switch replyTo {
            case .inputMessageReplyToMessage, nil:
                true
            case .inputMessageReplyToEphemeralMessage, .inputMessageReplyToExternalMessage,
                 .inputMessageReplyToStory:
                false
            }
        guard allowsLegacyCurrentChatFallback, let legacyMessageID else { return nil }
        return await getCustomMessage(fromId: legacyMessageID)
    }

    private func inputQuote(from replyTo: InputMessageReplyTo?) -> InputTextQuote? {
        switch replyTo {
        case .inputMessageReplyToMessage(let message):
            message.quote
        case .inputMessageReplyToExternalMessage(let message):
            message.quote
        case .inputMessageReplyToEphemeralMessage, .inputMessageReplyToStory, nil:
            nil
        }
    }

    private func cancelReplyIfMatching(_ frozenReplyTo: InputMessageReplyTo?) {
        guard let frozenReplyTo,
              getMessageReplyTo(from: replyMessage) == frozenReplyTo
        else { return }
        cancelReply()
    }

    private func restoreReplyState(
        message: CustomMessage?,
        input: InputMessageReplyTo?,
    ) {
        if isAllMessagesForum, let topicID = message?.forumTopicID {
            refreshForumTopic(id: topicID)
        }
        replySelectionGeneration &+= 1
        replyMessage = message
        replyQuote = inputQuote(from: input)
        replyInputOverride = input
        replyFallbackPresentation = message == nil
            ? input.map { MessageReplyPresentation.fallback(for: $0, currentChatID: chatID) }
            : nil
        reconcileActiveChatActionAfterReplyChange()
    }

    private func restoreVideoReplyIfNeeded(
        from draft: VideoNoteSendDraft,
        knownReply: CustomMessage?,
    ) {
        guard replyMessage == nil, editCustomMessage == nil else { return }
        if let knownReply {
            restoreReplyState(message: knownReply, input: draft.replyTo)
            return
        }
        guard draft.replyTo != nil || draft.replyMessageID != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let restoredReply = await resolveStoredReply(
                replyTo: draft.replyTo,
                legacyMessageID: draft.replyMessageID,
            )
            guard replyMessage == nil, editCustomMessage == nil else { return }
            restoreReplyState(message: restoredReply, input: draft.replyTo)
        }
    }

    private func activatePendingVideoDraft(_ draft: VideoNoteSendDraft) {
        guard draft.destination == location.draftKey else { return }
        refreshForumTopicIfNeeded(draft.sendTopic)
        pendingVideoNote = draft
        hasPendingVideoNote = true
        videoRetryAvailabilityTask?.cancel()
        if let retryAvailableAt = draft.failedSendState?.retryAvailableAt,
           retryAvailableAt > Foundation.Date()
        {
            videoRetryAvailabilityTask = Task { [weak self] in
                let delay = retryAvailableAt.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task<Never, Never>.sleep(for: .seconds(delay))
                }
                guard let self, pendingVideoNote?.id == draft.id else { return }
                objectWillChange.send()
            }
        }
        guard draft.replyTo != nil || draft.replyMessageID != nil else {
            pendingVideoReplyMessage = nil
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let reply = await resolveStoredReply(replyTo: draft.replyTo, legacyMessageID: draft.replyMessageID)
            guard pendingVideoNote?.id == draft.id else { return }
            pendingVideoReplyMessage = reply
        }
    }

    private func promoteNextPendingVideoDraft() async {
        guard pendingVideoNote == nil, locationContextIsCurrent else { return }
        let drafts = await VideoNoteFileStore.shared.drafts(for: location.draftKey)
        guard pendingVideoNote == nil,
              locationContextIsCurrent,
              let nextDraft = drafts.first(where: { $0.temporaryMessageID == nil })
        else { return }
        activatePendingVideoDraft(nextDraft)
        if nextDraft.enqueueStartedAt != nil {
            videoNoteErrorMessage = "A previous video send was interrupted before its status was confirmed. Check the chat before retrying."
        }
    }

    private func sendMessageVideoNote(_ draft: VideoNoteSendDraft) async throws -> Message {
        let context = try resolveFrozenMediaSendContext(
            for: .videoNote,
            destination: draft.destination,
            sendTopic: draft.sendTopic,
            replyTo: draft.replyTo,
        )
        try await validateStoredReply(draft.replyTo, in: context)
        let thumbnail = await VideoNoteFileStore.shared.inputThumbnail(for: draft)
        guard locationContextIsCurrent else { throw CancellationError() }
        let inputVideoNote = InputVideoNote(
            duration: min(60, max(1, Int(draft.duration))),
            length: min(640, max(1, draft.length)),
            thumbnail: thumbnail,
            videoNote: .inputFileLocal(.init(path: draft.fileURL.path(percentEncoded: false))),
        )
        let message = try await client.sendMessage(
            chatId: context.chatID,
            inputMessageContent: .inputMessageVideoNote(
                .init(selfDestructType: nil, videoNote: inputVideoNote),
            ),
            options: nil,
            replyMarkup: nil,
            replyTo: draft.replyTo,
            topicId: context.destinationTopic,
        )
        guard context.matches(message: message) else {
            throw ChatSendContextError.unexpectedDestination
        }
        return message
    }

    private func beginVoiceRecordingResume(_ draft: VoiceRecordingDraft) {
        guard !voiceRecordingLifecycle.isSuspended else { return }
        guard let recordingContext = try? resolveFrozenMediaSendContext(
            for: .voiceNote,
            destination: draft.destination,
            sendTopic: draft.sendTopic,
            replyTo: draft.replyTo,
        ) else {
            voiceNoteErrorMessage = "The voice message destination is no longer writable."
            return
        }
        activeVoiceRecordingContext = recordingContext
        stopVoiceRecordingPreviewPlayback()
        Media.shared.stop()
        Media.shared.setAudioSessionRecord()
        voiceRecordingInteractionState = .resuming
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav")
        do {
            let recorder = try makeVoiceRecorder(url: url)
            recordingVoiceNoteURL = url
            audioRecorder = recorder
            wave.removeAll(keepingCapacity: true)
            timerCount = draft.exactDuration
            voiceRecordingTimerBaseline = draft.exactDuration
            voiceRecordingLastRecorderTime = recorder.currentTime
            voiceRecordingInteractionState = .locked
            startTimer()
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures") {
                    log("Voice preview smoke: resumed at \(draft.exactDuration)")
                }
            #endif
            Task { [weak self] in
                guard let self else { return }
                _ = try? await sendChatAction(.chatActionRecordingVoiceNote, in: recordingContext)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            Media.shared.endAudioSessionRecord()
            voiceNoteErrorMessage = "Couldn’t resume voice recording."
            voiceRecordingInteractionState = .preview
            loadVoiceRecordingPreview(draft)
        }
    }

    private func makeVoiceRecorder(url: URL) throws -> AVAudioRecorder {
        let recorder = try AVAudioRecorder(url: url, settings: VoiceNotePCMEditor.recordingSettings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw VoiceNoteFailure.couldNotStartRecorder
        }
        return recorder
    }

    private func closeVoiceRecordingSegment(sendAfterPreparation: Bool) {
        guard recordingVoiceNote,
              voiceRecordingInteractionState == .locked,
              canPauseVoiceRecording,
              let audioRecorder,
              let sourceURL = recordingVoiceNoteURL
        else { return }
        audioRecorder.updateMeters()
        wave.append(audioRecorder.peakPower(forChannel: 0))
        updateVoiceRecordingDuration()
        let recordedDuration = timerCount
        let segmentPeaks = wave
        let existingDraft = activeVoiceRecordingDraft
        let reply = pendingVoiceReplyMessage
        let recordingContext = activeVoiceRecordingContext
        let draftID = existingDraft?.id ?? voiceRecordingDraftID ?? UUID()
        voiceRecordingDraftID = draftID
        audioRecorder.stop()
        Media.shared.endAudioSessionRecord()
        self.audioRecorder = nil
        recordingVoiceNoteURL = nil
        pauseVoiceRecordingTimer()
        voiceRecordingInteractionState = .pausing
        voiceRecordingDraftGeneration &+= 1
        let generation = voiceRecordingDraftGeneration
        let interactionGeneration = voiceRecordingLifecycle.generation
        voiceRecordingDraftTask?.cancel()
        voiceRecordingDraftTask = VoiceRecordingDraftPreservation.start(for: location.draftKey) { [self] in
            let mergedURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-merged.wav")
            do {
                let storedDraft: VoiceRecordingDraft
                if let existingDraft {
                    let inspection = try await VoiceNotePCMEditor.concatenate(
                        [existingDraft.fileURL, sourceURL],
                        outputURL: mergedURL,
                    )
                    try Task.checkCancellation()
                    storedDraft = try await VoiceRecordingDraftStore.shared.replaceMedia(
                        in: existingDraft,
                        with: mergedURL,
                        inspection: inspection,
                    )
                    try? FileManager.default.removeItem(at: sourceURL)
                } else {
                    let inspection = try await VoiceNotePCMEditor.inspect(sourceURL)
                    guard inspection.duration >= 0.5 else {
                        throw VoiceNoteFailure.couldNotStartRecorder
                    }
                    let draft = VoiceRecordingDraft(
                        id: draftID,
                        chatID: chatID,
                        caption: FormattedText(entities: getEntities(from: text), text: text.string),
                        createdAt: Foundation.Date(),
                        exactDuration: inspection.duration,
                        fileURL: sourceURL,
                        replyMessageID: reply?.id,
                        replyTo: recordingContext?.replyTo ?? getMessageReplyTo(from: reply),
                        sendTopic: recordingContext?.destinationTopic,
                        revision: 0,
                        trimEnd: nil,
                        trimStart: nil,
                        waveform: inspection.waveform,
                        destination: recordingContext?.draftKey ?? location.draftKey,
                    )
                    storedDraft = try await VoiceRecordingDraftStore.shared.adopt(draft)
                }
                try Task.checkCancellation()
                guard voiceRecordingDraftGeneration == generation else {
                    await VoiceRecordingDraftStore.shared.discard(id: draftID)
                    return
                }
                activeVoiceRecordingDraft = storedDraft
                pendingVoiceReplyMessage = reply
                timerCount = storedDraft.exactDuration
                voiceRecordingDraftTask = nil
                voiceRecordingInteractionState = .preview
                loadVoiceRecordingPreview(storedDraft)
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures") {
                        log(
                            "Voice preview smoke: ready duration=\(storedDraft.exactDuration) "
                                + "revision=\(storedDraft.revision)",
                        )
                    }
                #endif
                if sendAfterPreparation, voiceRecordingLifecycle.permitsContinuation(interactionGeneration) {
                    sendVoiceRecordingPreview()
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: sourceURL)
                try? FileManager.default.removeItem(at: mergedURL)
            } catch {
                try? FileManager.default.removeItem(at: mergedURL)
                guard voiceRecordingDraftGeneration == generation else {
                    try? FileManager.default.removeItem(at: sourceURL)
                    return
                }
                voiceRecordingDraftTask = nil
                if let existingDraft {
                    try? FileManager.default.removeItem(at: sourceURL)
                    activeVoiceRecordingDraft = existingDraft
                    timerCount = existingDraft.exactDuration
                    voiceRecordingInteractionState = .preview
                    voiceNoteErrorMessage = "Couldn’t append the latest recording segment. The previous preview is safe."
                    loadVoiceRecordingPreview(existingDraft)
                    if sendAfterPreparation, voiceRecordingLifecycle.permitsContinuation(interactionGeneration) {
                        sendVoiceRecordingPreview()
                    }
                } else {
                    await fallbackClosedVoiceSegment(
                        sourceURL: sourceURL,
                        duration: recordedDuration,
                        peakPowers: segmentPeaks,
                        reply: reply,
                        context: recordingContext,
                    )
                }
            }
        }
        if let recordingContext {
            Task { [weak self] in
                _ = try? await self?.cancelChatAction(in: recordingContext)
            }
        }
    }

    private func fallbackClosedVoiceSegment(
        sourceURL: URL,
        duration: Double,
        peakPowers: [Float],
        reply: CustomMessage?,
        context: ResolvedSendContext?,
    ) async {
        recordingVoiceNote = false
        voiceRecordingInteractionState = .idle
        activeVoiceRecordingDraft = nil
        voiceRecordingDraftID = nil
        stopTimer()
        pendingVoiceNote = VoiceNoteSendDraft(
            id: UUID(),
            chatID: chatID,
            caption: FormattedText(entities: getEntities(from: text), text: text.string),
            createdAt: Foundation.Date(),
            duration: max(1, Int(duration)),
            enqueueStartedAt: nil,
            failedSendState: nil,
            fileURL: sourceURL,
            isEncoded: false,
            replyMessageID: reply?.id,
            replyTo: context?.replyTo ?? getMessageReplyTo(from: reply),
            sendTopic: context?.destinationTopic,
            temporaryMessageID: nil,
            waveform: VoiceNoteCodec.encodeWaveform(peakPowers: peakPowers),
            destination: context?.draftKey ?? location.draftKey,
        )
        activeVoiceRecordingContext = nil
        pendingVoiceReplyMessage = reply
        cancelReplyIfMatching(context?.replyTo)
        startVoiceFinalization(
            sendWhenReady: false,
            pendingMessage: "Preview preparation failed. The recording was preserved as a retry draft.",
        )
        // Keep the route checkpoint until the fallback has a durable send-store owner.
        await voiceFinalizeTask?.value
    }

    private func materializeVoiceRecordingTrim(
        _ draft: VoiceRecordingDraft,
        continuation: VoiceRecordingTrimContinuation,
    ) {
        guard voiceRecordingInteractionState == .preview,
              voiceRecordingDraftTask == nil,
              voiceRecordingTrimTask == nil,
              !voiceRecordingTrimIsUpdating
        else { return }
        stopVoiceRecordingPreviewPlayback()
        voiceRecordingInteractionState = .pausing
        voiceRecordingDraftGeneration &+= 1
        let generation = voiceRecordingDraftGeneration
        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-trimmed.wav")
        let interactionGeneration = voiceRecordingLifecycle.generation
        voiceRecordingDraftTask = VoiceRecordingDraftPreservation.start(for: location.draftKey) { [self] in
            do {
                let inspection = try await VoiceNotePCMEditor.trim(
                    draft.fileURL,
                    outputURL: outputURL,
                    range: draft.effectiveRange,
                )
                try Task.checkCancellation()
                let materializedDraft = try await VoiceRecordingDraftStore.shared.replaceMedia(
                    in: draft,
                    with: outputURL,
                    inspection: inspection,
                )
                try Task.checkCancellation()
                guard voiceRecordingDraftGeneration == generation else {
                    await VoiceRecordingDraftStore.shared.discard(id: draft.id)
                    return
                }
                activeVoiceRecordingDraft = materializedDraft
                timerCount = materializedDraft.exactDuration
                voiceRecordingTimerBaseline = materializedDraft.exactDuration
                voiceRecordingDraftTask = nil
                voiceRecordingInteractionState = .preview
                loadVoiceRecordingPreview(materializedDraft)
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures") {
                        log(
                            "Voice preview smoke: trim materialized duration=\(materializedDraft.exactDuration) "
                                + "revision=\(materializedDraft.revision)",
                        )
                    }
                #endif
                if voiceRecordingLifecycle.permitsContinuation(interactionGeneration) {
                    switch continuation {
                    case .resume:
                        beginVoiceRecordingResume(materializedDraft)
                    case .send:
                        sendVoiceRecordingPreview()
                    }
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: outputURL)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                guard voiceRecordingDraftGeneration == generation else { return }
                voiceRecordingDraftTask = nil
                voiceRecordingInteractionState = .preview
                voiceNoteErrorMessage = "Couldn’t apply the voice trim range."
                activeVoiceRecordingDraft = draft
                loadVoiceRecordingPreview(draft)
            }
        }
    }

    private func sendVoiceRecordingPreview() {
        guard !voiceRecordingLifecycle.isSuspended,
              voiceRecordingInteractionState == .preview,
              voiceRecordingDraftTask == nil,
              voiceRecordingTrimTask == nil,
              !voiceRecordingTrimIsUpdating,
              let draft = activeVoiceRecordingDraft
        else { return }
        let range = draft.effectiveRange
        if range.lowerBound > 0.000_001 || abs(range.upperBound - draft.exactDuration) > 0.000_001 {
            materializeVoiceRecordingTrim(draft, continuation: .send)
            return
        }
        beginVoiceSendTransition(for: draft.id)
        stopVoiceRecordingPreviewPlayback()
        voiceRecordingInteractionState = .pausing
        voiceRecordingDraftGeneration &+= 1
        let generation = voiceRecordingDraftGeneration
        let reply = pendingVoiceReplyMessage
        let interactionGeneration = voiceRecordingLifecycle.generation
        let sendDraft = VoiceNoteSendDraft(
            id: draft.id,
            chatID: draft.chatID,
            caption: draft.caption,
            createdAt: draft.createdAt,
            duration: max(1, Int(range.upperBound - range.lowerBound)),
            enqueueStartedAt: nil,
            failedSendState: nil,
            fileURL: draft.fileURL,
            isEncoded: false,
            replyMessageID: draft.replyMessageID,
            replyTo: draft.replyTo,
            sendTopic: draft.sendTopic,
            temporaryMessageID: nil,
            waveform: draft.waveform,
            destination: draft.destination,
        )
        voiceRecordingDraftTask = VoiceRecordingDraftPreservation.start(for: location.draftKey) { [self] in
            var adoptedSendDraft: VoiceNoteSendDraft?
            do {
                let adoptedDraft = try await VoiceNoteDraftStore.shared.adopt(sendDraft)
                adoptedSendDraft = adoptedDraft
                try Task.checkCancellation()
                guard voiceRecordingDraftGeneration == generation else {
                    await VoiceNoteDraftStore.shared.remove(adoptedDraft)
                    return
                }
                await VoiceRecordingDraftStore.shared.discard(id: draft.id)
                try Task.checkCancellation()
                guard voiceRecordingDraftGeneration == generation else {
                    await VoiceNoteDraftStore.shared.remove(adoptedDraft)
                    return
                }
                activeVoiceRecordingDraft = nil
                activeVoiceRecordingContext = nil
                voiceRecordingDraftID = nil
                voiceRecordingDraftTask = nil
                pendingVoiceNote = adoptedDraft
                pendingVoiceReplyMessage = reply
                cancelReplyIfMatching(adoptedDraft.replyTo)
                recordingVoiceNote = false
                voiceRecordingInteractionState = .idle
                stopTimer()
                #if DEBUG
                    let shouldSend = !ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-preview-send")
                #else
                    let shouldSend = true
                #endif
                startVoiceFinalization(
                    sendWhenReady: shouldSend,
                    pendingMessage: shouldSend ? nil : "Voice preview promotion smoke retained a retry draft.",
                    intentGeneration: interactionGeneration,
                )
            } catch {
                if let adoptedSendDraft, Task.isCancelled || voiceRecordingDraftGeneration != generation {
                    await VoiceNoteDraftStore.shared.remove(adoptedSendDraft)
                }
                guard voiceRecordingDraftGeneration == generation else { return }
                cancelVoiceSendTransition(for: draft.id)
                voiceRecordingDraftTask = nil
                voiceRecordingInteractionState = .preview
                voiceNoteErrorMessage = "Couldn’t prepare the voice preview for sending."
                loadVoiceRecordingPreview(draft)
            }
        }
    }

    private func restoreVoiceRecordingDraft(_ draft: VoiceRecordingDraft) {
        refreshForumTopicIfNeeded(draft.sendTopic)
        activeVoiceRecordingContext = try? resolveFrozenMediaSendContext(
            for: .voiceNote,
            destination: draft.destination,
            sendTopic: draft.sendTopic,
            replyTo: draft.replyTo,
        )
        activeVoiceRecordingDraft = draft
        voiceRecordingDraftID = draft.id
        recordingVoiceNote = true
        voiceRecordingInteractionState = .preview
        timerCount = draft.exactDuration
        voiceRecordingTimerBaseline = draft.exactDuration
        loadVoiceRecordingPreview(draft)
        guard draft.replyTo != nil || draft.replyMessageID != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let reply = await resolveStoredReply(replyTo: draft.replyTo, legacyMessageID: draft.replyMessageID)
            guard activeVoiceRecordingDraft?.id == draft.id else { return }
            pendingVoiceReplyMessage = reply
        }
    }

    private func observeVoiceRecordingPreviewPlayer() {
        voiceRecordingPreviewPlayer.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let isPlaybackRequested = voiceRecordingPreviewPlayer.isPlaybackRequested
                if !voiceRecordingTrimIsUpdating,
                   voiceRecordingPreviewIsPlaying != isPlaybackRequested
                {
                    voiceRecordingPreviewIsPlaying = isPlaybackRequested
                }
                #if DEBUG
                    if state == .playing,
                       ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures")
                    {
                        log("Voice preview smoke: playing")
                    }
                #endif
                if state == .ended, let draft = activeVoiceRecordingDraft {
                    let start = draft.effectiveRange.lowerBound
                    voiceRecordingPreviewPlayer.seek(to: start)
                    voiceRecordingPreviewPosition = start
                    releaseVoiceRecordingPreviewAudioSession()
                } else if state == .failed {
                    releaseVoiceRecordingPreviewAudioSession()
                    voiceNoteErrorMessage = "Couldn’t play the voice recording preview."
                }
            }
            .store(in: &voiceRecordingPreviewCancellables)
        voiceRecordingPreviewPlayer.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                guard let self else { return }
                voiceRecordingPreviewPosition = position
                guard voiceRecordingPreviewIsPlaying,
                      let draft = activeVoiceRecordingDraft,
                      position >= draft.effectiveRange.upperBound
                else { return }
                voiceRecordingPreviewPlayer.pause()
                voiceRecordingPreviewPlayer.seek(to: draft.effectiveRange.lowerBound)
                voiceRecordingPreviewPosition = draft.effectiveRange.lowerBound
                releaseVoiceRecordingPreviewAudioSession()
            }
            .store(in: &voiceRecordingPreviewCancellables)
        Media.shared
            .$savedMediaPath
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                guard let self,
                      !path.isEmpty,
                      voiceRecordingPreviewPlayer.isPlaybackRequested
                else { return }
                voiceRecordingPreviewPlayer.pause()
                voiceRecordingPreviewIsPlaying = false
                // Media has taken over the shared AVAudioSession; do not deactivate its new ownership.
                voiceRecordingPreviewOwnsAudioSession = false
            }
            .store(in: &voiceRecordingPreviewCancellables)
    }

    private func loadVoiceRecordingPreview(_ draft: VoiceRecordingDraft) {
        voiceRecordingPreviewPlayer.stop()
        voiceRecordingPreviewLoadedURL = draft.fileURL
        voiceRecordingPreviewPosition = draft.effectiveRange.lowerBound
        voiceRecordingPreviewPlayer.load(url: draft.fileURL, autoplay: false)
        voiceRecordingPreviewPlayer.seek(to: draft.effectiveRange.lowerBound)
    }

    private func previewVoiceRecordingTrimEdge(_ draft: VoiceRecordingDraft, updatedEnd: Bool) {
        if voiceRecordingPreviewLoadedURL != draft.fileURL {
            loadVoiceRecordingPreview(draft)
        }
        let range = draft.effectiveRange
        let position = updatedEnd ? max(range.lowerBound, range.upperBound - 1) : range.lowerBound
        activateVoiceRecordingPreviewAudioSession()
        voiceRecordingPreviewPlayer.seek(to: position)
        voiceRecordingPreviewPosition = position
        voiceRecordingPreviewPlayer.play()
    }

    private func stopVoiceRecordingPreviewPlayback() {
        voiceRecordingPreviewPlayer.stop()
        voiceRecordingPreviewLoadedURL = nil
        voiceRecordingPreviewIsPlaying = false
        voiceRecordingPreviewPosition = 0
        releaseVoiceRecordingPreviewAudioSession()
    }

    private func activateVoiceRecordingPreviewAudioSession() {
        Media.shared.stop()
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false)
            try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .default, options: [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
            ])
            try audioSession.setActive(true)
            voiceRecordingPreviewOwnsAudioSession = true
        } catch {
            voiceRecordingPreviewOwnsAudioSession = false
            log("Error setting voice preview audio session: \(error)")
        }
    }

    private func releaseVoiceRecordingPreviewAudioSession() {
        guard voiceRecordingPreviewOwnsAudioSession else { return }
        voiceRecordingPreviewOwnsAudioSession = false
        Media.shared.endAudioSessionRecord()
    }

    private func formatVoiceDuration(_ duration: Double) -> String {
        let clippedDuration = max(0, duration)
        let minutes = Int(clippedDuration) / 60
        let seconds = Int(clippedDuration) % 60
        let hundredths = Int((clippedDuration - floor(clippedDuration)) * 100)
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "%d.%02d", seconds, hundredths)
    }

    private func finishVoiceRecording(sendWhenReady: Bool, pendingMessage: String?) {
        guard let audioRecorder, let sourceURL = recordingVoiceNoteURL else { return }
        updateVoiceRecordingDuration()
        let recordedDuration = timerCount
        let peakPowers = wave
        let recordingContext = activeVoiceRecordingContext
        let reply = pendingVoiceReplyMessage
        Media.shared.stop()
        audioRecorder.stop()
        Media.shared.endAudioSessionRecord()
        self.audioRecorder = nil
        recordingVoiceNoteURL = nil
        recordingVoiceNote = false
        voiceRecordingInteractionState = .idle
        wave.removeAll(keepingCapacity: true)
        stopTimer()
        if let recordingContext {
            Task { [weak self] in
                _ = try? await self?.cancelChatAction(in: recordingContext)
            }
        }
        guard recordedDuration >= 0.5 else {
            activeVoiceRecordingContext = nil
            pendingVoiceReplyMessage = nil
            try? FileManager.default.removeItem(at: sourceURL)
            voiceNoteErrorMessage = pendingMessage ?? "Voice message is too short."
            Task { [weak self] in await self?.promoteNextPendingVoiceDraft() }
            return
        }
        let draftID = UUID()
        if sendWhenReady {
            beginVoiceSendTransition(for: draftID)
        }
        pendingVoiceNote = VoiceNoteSendDraft(
            id: draftID,
            chatID: chatID,
            caption: FormattedText(entities: getEntities(from: text), text: text.string),
            createdAt: Foundation.Date(),
            duration: max(1, Int(recordedDuration)),
            enqueueStartedAt: nil,
            failedSendState: nil,
            fileURL: sourceURL,
            isEncoded: false,
            replyMessageID: reply?.id,
            replyTo: recordingContext?.replyTo ?? getMessageReplyTo(from: reply),
            sendTopic: recordingContext?.destinationTopic,
            temporaryMessageID: nil,
            waveform: VoiceNoteCodec.encodeWaveform(peakPowers: peakPowers),
            destination: recordingContext?.draftKey ?? location.draftKey,
        )
        activeVoiceRecordingContext = nil
        pendingVoiceReplyMessage = reply
        cancelReplyIfMatching(pendingVoiceNote?.replyTo)
        startVoiceFinalization(sendWhenReady: sendWhenReady, pendingMessage: pendingMessage)
    }

    private func pauseVoiceRecordingTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateVoiceRecordingDuration() {
        guard let audioRecorder else { return }
        let recorderTime = max(0, audioRecorder.currentTime)
        if recorderTime + 0.05 < voiceRecordingLastRecorderTime {
            voiceRecordingTimerBaseline = timerCount
        }
        voiceRecordingLastRecorderTime = recorderTime
        timerCount = max(timerCount, voiceRecordingTimerBaseline + recorderTime)
    }

    private func sendMessageVoiceNote(
        fileURL: URL,
        draft: VoiceNoteSendDraft,
        onRequestStart: () throws -> Void,
    ) async throws -> Message {
        let context = try resolveFrozenMediaSendContext(
            for: .voiceNote,
            destination: draft.destination,
            sendTopic: draft.sendTopic,
            replyTo: draft.replyTo,
        )
        try await validateStoredReply(draft.replyTo, in: context)
        try Task.checkCancellation()
        try onRequestStart()
        let message = try await client.sendMessage(
            chatId: context.chatID,
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
            topicId: context.destinationTopic,
        )
        _ = try? await cancelChatAction(in: context)
        return message
    }

    private func startVoiceFinalization(
        sendWhenReady: Bool = true,
        pendingMessage: String? = nil,
        intentGeneration: UInt64? = nil,
    ) {
        guard var draft = pendingVoiceNote else { return }
        voiceFinalizeTask?.cancel()
        voiceFinalizationGeneration &+= 1
        let generation = voiceFinalizationGeneration
        let interactionGeneration = intentGeneration ?? voiceRecordingLifecycle.generation
        voiceFinalizationNeedsCheckpoint = true
        voiceRetryAvailabilityTask?.cancel()
        finalizingVoiceNote = true
        hasPendingVoiceNote = false
        voiceNoteErrorMessage = nil
        voiceFinalizeTask = Task { [weak self] in
            guard let self else { return }
            var finalization: VoiceNoteFinalizationLease?
            var didStartSend = false
            var registeringMessageID: Int64?
            defer {
                if let registeringMessageID { registeringVoiceMessageIDs.remove(registeringMessageID) }
                if voiceFinalizationGeneration == generation {
                    voiceFinalizationNeedsCheckpoint = false
                    bufferedDeletedMessageIDs.removeAll()
                    finalizingVoiceNote = false
                    voiceFinalizeTask = nil
                    if let id = pendingVoiceNote?.id {
                        Task { [weak self] in await self?.refreshPendingVoiceDraft(id: id) }
                    }
                }
            }
            do {
                let claim = try await VoiceNoteDraftStore.shared.claimFinalization(draft)
                finalization = claim.lease
                draft = claim.draft
                try Task.checkCancellation()
                guard voiceFinalizationGeneration == generation else { throw CancellationError() }
                pendingVoiceNote = draft
                if !draft.isEncoded {
                    let sourceURL = draft.fileURL
                    let encodedURL = try await VoiceNoteCodec.encodeOggOpus(from: sourceURL)
                    defer { try? FileManager.default.removeItem(at: encodedURL) }
                    try Task.checkCancellation()
                    guard voiceFinalizationGeneration == generation else { throw CancellationError() }
                    draft = try await VoiceNoteDraftStore.shared.replaceFile(
                        in: draft, with: encodedURL, finalization: claim.lease,
                    )
                    try Task.checkCancellation()
                    guard voiceFinalizationGeneration == generation else { throw CancellationError() }
                    pendingVoiceNote = draft
                }
                // From here the encoded canonical file is durable. Upload actions
                // and reply validation may wait on the network; they are not checkpoints.
                voiceFinalizationNeedsCheckpoint = false
                guard sendWhenReady, voiceRecordingLifecycle.permitsContinuation(interactionGeneration) else {
                    await VoiceNoteDraftStore.shared.finishFinalization(claim.lease)
                    finalization = nil
                    try Task.checkCancellation()
                    guard voiceFinalizationGeneration == generation else { throw CancellationError() }
                    cancelVoiceSendTransition(for: draft.id)
                    activatePendingVoiceDraft(draft)
                    voiceNoteErrorMessage = pendingMessage ?? "Voice recording stopped before it could be sent."
                    #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-preview-send") {
                            log("Voice preview smoke: promoted encoded=\(draft.isEncoded)")
                        }
                    #endif
                    return
                }
                let activeSendContext = try resolveFrozenMediaSendContext(
                    for: .voiceNote,
                    destination: draft.destination,
                    sendTopic: draft.sendTopic,
                    replyTo: draft.replyTo,
                )
                _ = try? await sendChatAction(
                    .chatActionUploadingVoiceNote(.init(progress: 0)),
                    in: activeSendContext,
                )
                try Task.checkCancellation()
                guard voiceFinalizationGeneration == generation else { throw CancellationError() }
                try voiceRecordingLifecycle.requireCurrentIntent(interactionGeneration)
                draft = try await VoiceNoteDraftStore.shared.beginEnqueue(draft, finalization: claim.lease)
                try Task.checkCancellation()
                guard voiceFinalizationGeneration == generation else { throw CancellationError() }
                pendingVoiceNote = draft
                let message: Message
                if let failedSendState = draft.failedSendState {
                    guard failedSendState.canRetryNow else {
                        throw VoiceNoteFailure.resendUnavailable
                    }
                    try voiceRecordingLifecycle.requireCurrentIntent(interactionGeneration)
                    didStartSend = true
                    let resentMessages = try await client.resendMessages(
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
                    message = try await sendMessageVoiceNote(fileURL: draft.fileURL, draft: draft) { [owner = self] in
                        try owner.voiceRecordingLifecycle.requireCurrentIntent(interactionGeneration)
                        didStartSend = true
                    }
                }
                // UI cancellation cannot revoke a send already accepted by TDLib.
                // Register its actual ID before any generation/cancellation return.
                draft.temporaryMessageID = message.id
                registeringVoiceMessageIDs.insert(message.id)
                registeringMessageID = message.id
                var registration: VoiceNoteEnqueueRegistration?
                do {
                    registration = try await VoiceNoteDraftStore.shared.registerEnqueued(
                        draft,
                        temporaryMessageID: message.id,
                        finalization: claim.lease,
                    )
                    finalization = nil
                } catch {
                    log("Voice note enqueue persistence failed: \(error)")
                    if voiceFinalizationGeneration == generation {
                        voiceNoteErrorMessage = "The voice message was queued, but local retry state couldn’t be saved."
                    }
                }
                if let finalization {
                    await VoiceNoteDraftStore.shared.finishFinalization(finalization)
                }
                finalization = nil
                guard activeSendContext.matches(message: message) else {
                    throw ChatSendContextError.unexpectedDestination
                }
                guard voiceFinalizationGeneration == generation, !Task.isCancelled else { return }
                var deletionResolution: VoiceNoteDraftResolution?
                if bufferedDeletedMessageIDs.remove(message.id) != nil {
                    deletionResolution = try? await VoiceNoteDraftStore.shared.handleMessageDeleted(
                        destination: location.draftKey,
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
                registeringMessageID = nil
                bufferedDeletedMessageIDs.removeAll()
                let bufferedResolution = bufferedVoiceOutcomes.removeValue(forKey: message.id)
                pendingVoiceNote = nil
                pendingVoiceReplyMessage = nil
                voiceRetryAvailabilityTask?.cancel()
                hasPendingVoiceNote = false
                await Task.yield()
                guard voiceFinalizationGeneration == generation, !Task.isCancelled else { return }
                acceptVoiceSendTransition(for: draft.id, messageID: message.id)
                let registrationResolution = registration.flatMap { registration -> VoiceNoteDraftResolution? in
                    guard let outcome = registration.outcome else { return nil }
                    return VoiceNoteDraftResolution(
                        chatID: self.chatID,
                        draft: registration.draft,
                        outcome: outcome,
                        temporaryMessageID: message.id,
                    )
                }
                let resolution = bufferedResolution ?? registrationResolution ?? deletionResolution
                if let resolution {
                    applyVoiceNoteDraftResolution(resolution)
                } else {
                    outgoingVoiceNotes[message.id] = registration?.draft ?? draft
                    if registration != nil {
                        await promoteNextPendingVoiceDraft()
                    }
                }
                guard voiceFinalizationGeneration == generation, !Task.isCancelled else { return }
                if resolution?.outcome != .failed {
                    await clearRouteDraftAfterMediaSend(draft.destination, voiceGeneration: generation)
                }
            } catch is CancellationError {
                if let finalization {
                    if !didStartSend, draft.enqueueStartedAt != nil {
                        _ = try? await VoiceNoteDraftStore.shared.markPending(
                            draft, failedSendState: draft.failedSendState, finalization: finalization,
                        )
                    }
                    await VoiceNoteDraftStore.shared.finishFinalization(finalization)
                }
                guard voiceFinalizationGeneration == generation else { return }
                cancelVoiceSendTransition(for: draft.id)
                hasPendingVoiceNote = pendingVoiceNote != nil
            } catch {
                log("Voice note finalization failed: \(error)")
                if let finalization {
                    // Only preflight or an explicit TDLib rejection proves that no
                    // message was accepted. Unknown post-RPC failures stay unresolved.
                    if !didStartSend || error is TDLibKit.Error,
                       draft.enqueueStartedAt != nil, draft.temporaryMessageID == nil
                    {
                        _ = try? await VoiceNoteDraftStore.shared.markPending(
                            draft, failedSendState: draft.failedSendState, finalization: finalization,
                        )
                    }
                    await VoiceNoteDraftStore.shared.finishFinalization(finalization)
                }
                guard voiceFinalizationGeneration == generation else { return }
                cancelVoiceSendTransition(for: draft.id)
                let status = await VoiceNoteDraftStore.shared.status(id: draft.id, destination: location.draftKey)
                guard voiceFinalizationGeneration == generation else { return }
                if let canonical = status.draft, canonical.temporaryMessageID == nil {
                    draft = canonical
                    activatePendingVoiceDraft(canonical)
                    pendingVoiceDraftIsFinalizing = status.isFinalizing
                } else {
                    pendingVoiceNote = nil
                    hasPendingVoiceNote = false
                }
                voiceNoteErrorMessage = pendingVoiceRetryStatusMessage
                    ?? "Couldn’t send the voice message. You can retry without recording again."
                _ = try? await tdSendFrozenMediaChatAction(
                    .chatActionCancel,
                    sendTopic: draft.sendTopic,
                    replyTo: draft.replyTo,
                )
            }
        }
    }

    private func beginVoiceSendTransition(for draftID: UUID) {
        if let previous = voiceSendTransitionIDs[draftID] {
            sendTransitionCancelled.send(previous)
        }
        let id = UUID()
        voiceSendTransitionIDs[draftID] = id
        sendTransitionWillBegin.send(ComposerSendTransitionRequest(id: id, kind: .voiceNote))
    }

    private func acceptVoiceSendTransition(for draftID: UUID, messageID: Int64) {
        guard let id = voiceSendTransitionIDs.removeValue(forKey: draftID) else { return }
        sendTransitionAccepted.send(ComposerSendTransitionAcceptance(id: id, messageIDs: [messageID]))
    }

    private func cancelVoiceSendTransition(for draftID: UUID) {
        guard let id = voiceSendTransitionIDs.removeValue(forKey: draftID) else { return }
        sendTransitionCancelled.send(id)
    }

    private func beginVideoSendTransition(for draftID: UUID) {
        if let previous = videoSendTransitionIDs[draftID] {
            sendTransitionCancelled.send(previous)
        }
        let id = UUID()
        videoSendTransitionIDs[draftID] = id
        sendTransitionWillBegin.send(ComposerSendTransitionRequest(id: id, kind: .videoNote))
    }

    private func acceptVideoSendTransition(for draftID: UUID, messageID: Int64) {
        guard let id = videoSendTransitionIDs.removeValue(forKey: draftID) else { return }
        sendTransitionAccepted.send(ComposerSendTransitionAcceptance(id: id, messageIDs: [messageID]))
    }

    private func cancelVideoSendTransition(for draftID: UUID) {
        guard let id = videoSendTransitionIDs.removeValue(forKey: draftID) else { return }
        sendTransitionCancelled.send(id)
    }

    private func activatePendingVoiceDraft(_ draft: VoiceNoteSendDraft) {
        guard draft.destination == location.draftKey else { return }
        voiceDraftRefreshGeneration &+= 1
        refreshForumTopicIfNeeded(draft.sendTopic)
        pendingVoiceNote = draft
        pendingVoiceDraftIsFinalizing = false
        hasPendingVoiceNote = true
        pendingVoiceReplyMessage = nil
        voiceRetryAvailabilityTask?.cancel()
        Task { [weak self] in await self?.refreshPendingVoiceDraft(id: draft.id) }
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
        guard draft.replyTo != nil || draft.replyMessageID != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let reply = await resolveStoredReply(replyTo: draft.replyTo, legacyMessageID: draft.replyMessageID)
            guard pendingVoiceNote?.id == draft.id else { return }
            pendingVoiceReplyMessage = reply
        }
    }

    private func clearRouteDraftAfterMediaSend(_ destination: ChatDraftKey?, voiceGeneration: UInt64? = nil) async {
        guard let accountID = destination?.accountID,
              destination == location.draftKey,
              voiceGeneration == nil || voiceGeneration == voiceFinalizationGeneration,
              locationContextIsCurrent
        else { return }
        let context = ResolvedSendContext(
            accountID: accountID,
            chatID: location.chatID,
            clientID: location.clientID,
            destinationTopic: location.topic,
            draftTopic: location.topic,
            replyTo: nil,
        )
        let draftClearSucceeded = await clearRouteDraft(context)
        guard locationContextIsCurrent,
              voiceGeneration == nil || voiceGeneration == voiceFinalizationGeneration
        else { return }
        composerRevision &+= 1
        let hasNewComposerState = !text.characters.isEmpty
            || replyMessage != nil
            || !displayedImages.isEmpty
            || !displayedDocuments.isEmpty
        if hasNewComposerState {
            composerIsDirty = true
            awaitingAuthoritativeDraftClear = false
            cancelPendingDraftClearRetry()
            await updateDraft()
        } else {
            awaitingAuthoritativeDraftClear = location.isTopicScoped
            composerIsDirty = awaitingAuthoritativeDraftClear || !draftClearSucceeded
            if location.isTopicScoped {
                loadForumTopic()
            }
        }
    }

    private func clearRouteDraft(_ context: ResolvedSendContext) async -> Bool {
        draftClearGeneration &+= 1
        let generation = draftClearGeneration
        draftClearTask?.cancel()
        do {
            try await client.setChatDraftMessage(
                chatId: context.chatID,
                draftMessage: nil,
                topicId: context.draftTopic,
            )
            guard draftClearGeneration == generation else { return false }
            draftErrorMessage = nil
            draftClearTask = nil
            return true
        } catch {
            scheduleDraftClearRetry(context, generation: generation)
            return false
        }
    }

    private func cancelPendingDraftClearRetry() {
        draftClearGeneration &+= 1
        draftClearTask?.cancel()
        draftClearTask = nil
    }

    private func scheduleDraftUpdateRetry(
        _ context: ResolvedSendContext,
        replyTo: InputMessageReplyTo?,
    ) {
        draftClearGeneration &+= 1
        let generation = draftClearGeneration
        draftClearTask?.cancel()
        draftClearTask = Task { [weak self] in
            guard let self else { return }
            for delay in [0.4, 1.0, 2.0] {
                try? await Task<Never, Never>.sleep(for: .seconds(delay))
                guard !Task.isCancelled,
                      draftClearGeneration == generation,
                      TDLib.shared.activeAccountID == context.accountID,
                      TDLib.shared.activeClient.id == context.clientID,
                      location.draftKey == context.draftKey
                else { return }
                do {
                    try await updateDraft(in: context, replyTo: replyTo)
                    guard draftClearGeneration == generation else { return }
                    draftClearTask = nil
                    draftErrorMessage = nil
                    composerIsDirty = false
                    return
                } catch {
                    continue
                }
            }
            guard draftClearGeneration == generation else { return }
            draftClearTask = nil
            draftErrorMessage = "The sticker was sent, but the reply draft couldn't be updated."
        }
    }

    private func scheduleDraftClearRetry(
        _ context: ResolvedSendContext,
        generation: UInt64,
    ) {
        draftClearTask = Task { [weak self] in
            guard let self else { return }
            for delay in [0.4, 1.0, 2.0] {
                try? await Task<Never, Never>.sleep(for: .seconds(delay))
                guard !Task.isCancelled,
                      draftClearGeneration == generation,
                      TDLib.shared.activeAccountID == context.accountID,
                      TDLib.shared.activeClient.id == context.clientID,
                      location.draftKey == context.draftKey
                else { return }
                do {
                    try await client.setChatDraftMessage(
                        chatId: context.chatID,
                        draftMessage: nil,
                        topicId: context.draftTopic,
                    )
                    guard draftClearGeneration == generation else { return }
                    draftClearTask = nil
                    draftErrorMessage = nil
                    if awaitingAuthoritativeDraftClear, location.isTopicScoped {
                        composerIsDirty = true
                        loadForumTopic()
                    } else {
                        awaitingAuthoritativeDraftClear = false
                        composerIsDirty = false
                    }
                    return
                } catch {
                    continue
                }
            }
            guard draftClearGeneration == generation else { return }
            draftClearTask = nil
            draftErrorMessage = "The sent message is safe, but its old draft couldn't be cleared."
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
        guard pendingVoiceNote == nil, locationContextIsCurrent else { return }
        let generation = voiceFinalizationGeneration
        let refreshGeneration = voiceDraftRefreshGeneration
        let drafts = await VoiceNoteDraftStore.shared.drafts(for: location.draftKey)
        guard pendingVoiceNote == nil,
              voiceFinalizationGeneration == generation,
              voiceDraftRefreshGeneration == refreshGeneration,
              locationContextIsCurrent,
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
        guard replyMessage == nil,
              editCustomMessage == nil,
              draft?.replyTo != nil || draft?.replyMessageID != nil
        else { return }
        if let knownReply {
            restoreReplyState(message: knownReply, input: draft?.replyTo)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let restoredReply = await resolveStoredReply(
                replyTo: draft?.replyTo,
                legacyMessageID: draft?.replyMessageID,
            )
            guard replyMessage == nil, editCustomMessage == nil else { return }
            restoreReplyState(message: restoredReply, input: draft?.replyTo)
        }
    }

    private func observeVoiceRecordingInterruptions() {
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.suspendVoiceRecordingForSystem(.background) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.voiceRecordingLifecycle.resume(.background) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let rawValue = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?
                          .uintValue
                else { return }
                if AVAudioSession.InterruptionType(rawValue: rawValue) == .began {
                    suspendVoiceRecordingForSystem(.audioInterruption)
                } else if AVAudioSession.InterruptionType(rawValue: rawValue) == .ended {
                    voiceRecordingLifecycle.resume(.audioInterruption)
                }
            }
            .store(in: &cancellables)
    }

    private func suspendVoiceRecordingForSystem(_ reason: VoiceRecordingLifecycle.Reason) {
        guard voiceRecordingLifecycle.suspend(reason) else { return }
        // Invalidate permission/trim/send intents even before recordingVoiceNote becomes true.
        preserveVoiceRecordingCheckpoint()
        if reason == .background || UIApplication.shared.applicationState == .background {
            protectVoiceRecordingCheckpoint()
        }
    }

    private func protectVoiceRecordingCheckpoint() {
        let tasks = [
            voiceRecordingDraftTask,
            voiceRecordingTrimTask,
            voiceFinalizationNeedsCheckpoint
                ? voiceFinalizeTask
                : nil,
        ]
            .compactMap(\.self)
        // Expiry only ends the assertion; canonical work and accepted RPCs keep their owners.
        voiceBackgroundCheckpoint.protect(tasks)
    }

    private func memberStatus(memberCount: Int, onlineMemberCount: Int) -> String {
        let members = countStatus(memberCount, singular: "member", plural: "members")
        guard onlineMemberCount > 1 else { return members }
        return "\(members), \(onlineMemberCount.formatted(.number)) online"
    }

    private func countStatus(_ count: Int, singular: String, plural: String) -> String {
        "\(count.formatted(.number)) \(count == 1 ? singular : plural)"
    }
}
