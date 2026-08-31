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
        let displayedMessageID: Int64
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

    let messagesDidChange = PassthroughSubject<Void, Never>()

    let customChat: CustomChat
    nonisolated let chatID: Int64
    nonisolated let accountID: UUID?
    nonisolated let location: ChatLocation
    let client: TDLibClient
    let metadataResolver: MessageMetadataResolver
    let pollInteractionStore = MessagePollInteractionStore()
    @Published var actionStatus = ""
    @Published var onlineStatus = ""
    @Published var editCustomMessage: CustomMessage?
    @Published var replyMessage: CustomMessage?
    @Published private(set) var replyQuote: InputTextQuote?
    @Published private(set) var replyInputOverride: InputMessageReplyTo?
    @Published private(set) var replyFallbackPresentation: MessageReplyPresentation?
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
    @Published private(set) var hasPendingVideoNote = false
    @Published private(set) var retryingVideoNote = false
    @Published private(set) var restoredVideoRecordingDraft: VideoNoteRecordingDraft?
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
    @Published var draftErrorMessage: String?
    @Published private(set) var canAddReactions = false
    @Published private(set) var maximumChosenReactionCount = 1
    @Published private(set) var pinnedMessage: Message?
    @Published private(set) var locallyHiddenPinnedMessageID: Int64?
    @Published var pinErrorMessage: String?
    @Published private(set) var forumTopic: ForumTopic?
    @Published private(set) var forumTopicInfo: ForumTopicInfo?
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

    var metadataRefreshGenerations = [Int64: UUID]()

    private let chatOpenLease: ChatOpenLease
    private var currentChatPermissions: ChatPermissions

    private var voiceRecordingTimerBaseline = 0.0
    private var voiceRecordingLastRecorderTime = 0.0
    private var voiceRecordingDraftTask: Task<Void, Never>?
    private var voiceRecordingDraftGeneration = 0
    private var voiceRecordingDraftID: UUID?
    private var activeVoiceRecordingDraft: VoiceRecordingDraft?
    private let voiceRecordingPreviewPlayer = LocalMediaPlayer()
    private var voiceRecordingPreviewLoadedURL: URL?
    private var voiceRecordingPreviewOwnsAudioSession = false
    private var voiceRecordingPreviewCancellables = Set<AnyCancellable>()
    private var voiceRecordingTrimTask: Task<Void, Never>?
    private var voiceRecordingTrimGeneration = 0
    private var voiceRecordingTrimBaseDraft: VoiceRecordingDraft?
    private var pendingVideoNote: VideoNoteSendDraft?
    private var outgoingVideoNotes = [Int64: VideoNoteSendDraft]()
    private var videoRetryAvailabilityTask: Task<Void, Never>?
    private var videoRetryTask: Task<Void, Never>?
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
    private var composerRevision = UInt64.zero
    private var composerIsDirty = false
    private var awaitingAuthoritativeDraftClear = false
    private var draftClearGeneration = UInt64.zero
    private var draftClearTask: Task<Void, Never>?
    private let previewing: Bool

    private var pendingVoiceNote: VoiceNoteSendDraft?
    private var outgoingVoiceNotes = [Int64: VoiceNoteSendDraft]()
    private var registeringVoiceMessageIDs = Set<Int64>()
    private var bufferedVoiceOutcomes = [Int64: VoiceNoteDraftResolution]()
    private var bufferedDeletedMessageIDs = Set<Int64>()
    private var voiceRetryAvailabilityTask: Task<Void, Never>?
    private var hasMoreMessages = true

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

    var canWriteBasicMessages: Bool {
        (try? resolveSendContext(for: .text, replyingTo: nil)) != nil
    }

    var canAttachPhotos: Bool {
        (try? resolveSendContext(for: .photo, replyingTo: replyMessage)) != nil
    }

    var canWriteAnyMessage: Bool {
        canWriteBasicMessages || canAttachPhotos || canRecordVoiceNote || canRecordVideoNote
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
        guard let topicName = forumTopicInfo?.name, location.isTopicScoped else {
            return "Message…"
        }
        return replyMessage == nil
            ? "Message in \(topicName)"
            : "Reply in \(topicName)"
    }

    var composerRestrictionText: String {
        if forumTopicInfo?.isClosed == true || forumTopicInfo?.isHidden == true {
            return "Only the topic creator or an administrator can post here."
        }
        return "You can't send messages in this topic."
    }

    var locationContextIsCurrent: Bool {
        TDLib.shared.activeAccountID == location.accountID
            && TDLib.shared.activeClient.id == location.clientID
            && client.id == location.clientID
    }

    var pendingVoiceReplyMessageID: Int64? {
        activeVoiceRecordingDraft?.replyMessageID ?? pendingVoiceNote?.replyMessageID
    }

    var canRetryPendingVoiceNote: Bool {
        guard canRecordVoiceNote,
              let pendingVoiceNote,
              pendingVoiceNote.enqueueStartedAt == nil
        else { return false }
        return pendingVoiceNote.failedSendState?.canRetryNow ?? true
    }

    var canRetryPendingVideoNote: Bool {
        guard canRecordVideoNote,
              !retryingVideoNote,
              let pendingVideoNote,
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
        switch editCustomMessage.message.content {
        case .messageAnimation, .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
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

    var voiceRecordingPreviewDuration: Int {
        guard let activeVoiceRecordingDraft else { return max(1, Int(ceil(timerCount))) }
        let range = activeVoiceRecordingDraft.effectiveRange
        return max(1, Int(ceil(range.upperBound - range.lowerBound)))
    }

    var canPauseVoiceRecording: Bool {
        recordingVoiceNote
            && voiceRecordingInteractionState == .locked
            && voiceRecordingDraftTask == nil
            && (activeVoiceRecordingDraft != nil || timerCount - voiceRecordingTimerBaseline >= 0.5)
    }

    var voiceRecordingPreviewPath: String? {
        guard voiceRecordingInteractionState == .preview else { return nil }
        return activeVoiceRecordingDraft?.fileURL.path()
    }

    var voiceRecordingPreviewWaveform: [CGFloat] {
        guard let activeVoiceRecordingDraft else { return [] }
        return VoiceNoteCodec.normalizedWaveform(data: activeVoiceRecordingDraft.waveform).map(CGFloat.init)
    }

    var voiceRecordingPreviewProgress: CGFloat {
        guard let draft = activeVoiceRecordingDraft, draft.exactDuration > 0 else { return 0 }
        return min(1, max(0, CGFloat(voiceRecordingPreviewPosition / draft.exactDuration)))
    }

    var voiceRecordingPreviewReady: Bool {
        voiceRecordingInteractionState == .preview
            && activeVoiceRecordingDraft != nil
            && voiceRecordingDraftTask == nil
            && voiceRecordingTrimTask == nil
            && !voiceRecordingTrimIsUpdating
    }

    var voiceRecordingTrimControlsEnabled: Bool {
        voiceRecordingInteractionState == .preview
            && activeVoiceRecordingDraft != nil
            && voiceRecordingDraftTask == nil
            && voiceRecordingTrimTask == nil
    }

    var voiceRecordingPreviewExactDuration: Double {
        activeVoiceRecordingDraft?.exactDuration ?? timerCount
    }

    var voiceRecordingTrimRange: Range<Double>? {
        activeVoiceRecordingDraft?.effectiveRange
    }

    var voiceRecordingResumeRequiresTrimConfirmation: Bool {
        guard let draft = activeVoiceRecordingDraft else { return false }
        let range = draft.effectiveRange
        return range.lowerBound > 0.000_001 || abs(range.upperBound - draft.exactDuration) > 0.000_001
    }

    var formattedVoiceRecordingPreviewDuration: String {
        guard let draft = activeVoiceRecordingDraft else { return formattedTimerCount }
        let range = draft.effectiveRange
        return formatVoiceDuration(range.upperBound - range.lowerBound)
    }

    private var pendingVideoRetryStatusMessage: String? {
        guard let failed = pendingVideoNote?.failedSendState else { return nil }
        if failed.requiredPaidMessageStarCount > 0 {
            return "This video-message retry requires a paid-message flow, which BetterTG doesn’t support."
        }
        if failed.needAnotherReplyQuote || failed.needAnotherSender {
            return "This failed video message can’t be retried with the original reply or sender."
        }
        if !failed.canRetry {
            return "TDLib marked this video message as non-retryable."
        }
        if failed.retryAvailableAt > Foundation.Date() {
            return "This video message can be retried shortly."
        }
        return nil
    }

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

    init(
        customChat: CustomChat,
        location: ChatLocation? = nil,
        forumTopic: ForumTopic? = nil,
        previewing: Bool = false,
    ) {
        let client = td
        let resolvedLocation = location ?? ChatLocation.current(
            chatID: customChat.id,
            client: client,
        )
        self.customChat = customChat
        self.chatID = resolvedLocation.chatID
        self.accountID = resolvedLocation.accountID
        self.location = resolvedLocation
        self.client = client
        self.chatOpenLease = ChatOpenLeaseCoordinator.shared.acquire(
            location: resolvedLocation,
            client: client,
        )
        self.metadataResolver = MessageMetadataResolver(client: client)
        self.currentChatPermissions = customChat.chat.permissions
        self.previewing = previewing
        self.forumTopic = forumTopic
        self.forumTopicInfo = forumTopic?.info
        self.canAddReactions = customChat.chat.permissions.canReactToMessages
        self.maximumChosenReactionCount =
            customChat.chat.availableReactions.maximumChosenReactionCount
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }

        setPublishers()
        observeVoiceRecordingPreviewPlayer()
        observeVoiceRecordingInterruptions()
        loadMessages()
        if isReadOnlyTopic, forumTopicInfo == nil {
            loadForumTopic()
        }
        if supportsPinnedMessages {
            refreshPinnedMessages()
        }
        if !previewing {
            Media.shared.onChatOpen(title: customChat.displayTitle)
        }

        let routeDraftMessage = previewing || !canWriteBasicMessages
            ? nil
            : (resolvedLocation.isTopicScoped ? forumTopic?.draftMessage : customChat.draftMessage)
        applyAuthoritativeDraft(routeDraftMessage, expectedRevision: composerRevision)
        Task { [weak self] in
            guard let self else { return }
            guard !previewing, !isReadOnlyTopic else {
                self.loadingVoiceDraft = false
                return
            }
            let draftKey = self.location.draftKey
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
        voiceFinalizeTask?.cancel()
        voiceRecordingDraftTask?.cancel()
        voiceRecordingTrimTask?.cancel()
        voiceRetryAvailabilityTask?.cancel()
        videoRetryAvailabilityTask?.cancel()
        videoRetryTask?.cancel()
        reactionMutationTasks.values.forEach { $0.cancel() }
        pinnedMessageTask?.cancel()
        forumTopicTask?.cancel()
        draftClearTask?.cancel()
        pinMutationTasks.values.forEach { $0.cancel() }
        voiceRecordingPreviewPlayer.stop()
        timer?.invalidate()
        if audioRecorder != nil {
            Media.shared.endAudioSessionRecord()
        }
        if voiceRecordingPreviewOwnsAudioSession {
            Media.shared.endAudioSessionRecord()
        }
        audioRecorder?.stop()
        if let recordingVoiceNoteURL {
            try? FileManager.default.removeItem(at: recordingVoiceNoteURL)
        }
        chatOpenLease.invalidate()
        if !previewing {
            Media.shared.onChatDismiss()
        }
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
            let canManageTopics = customChat.adminRights?.canManageTopics == true
                || {
                    if case .chatMemberStatusCreator = customChat.supergroup?.status {
                        true
                    } else {
                        false
                    }
                }()
            guard !topicIsRestricted || info.isOutgoing || canManageTopics else {
                throw ChatSendContextError.topicReadOnly
            }
        }
        if let reply,
           reply.message.chatId == location.chatID,
           reply.message.topicId != location.topic
        {
            throw ChatSendContextError.crossTopicReply
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
            destinationTopic: location.topic,
            draftTopic: location.topic,
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
        guard locationContextIsCurrent else {
            loadingMessagesTask = nil
            return
        }
        guard let chatHistory = await loadHistory(
            fromMessageId: fromMessageID,
            limit: 30,
            offset: 0,
        ) else {
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
            guard self.locationContextIsCurrent else {
                self.loadingMessagesTask = nil
                return
            }
            let existingIDs = Set(self.messages.map(\.id))
            let newMessages = savedMessages.filter { !existingIDs.contains($0.id) }
            self.messages.append(contentsOf: newMessages)
            self.hasMoreMessages = !chatHistory.isEmpty && !newMessages.isEmpty
            self.loadingMessagesTask = nil
        }
    }

    func displayedMessageID(containing messageID: Int64) -> Int64? {
        messages.first(where: { message in
            message.id == messageID || message.album.contains(where: { $0.id == messageID })
        })?.id
    }

    func prepareMessageWindow(around id: Int64) async -> PreparedMessageWindow? {
        guard locationContextIsCurrent else { return nil }
        let windowSize = 50
        var history = await loadHistory(
            fromMessageId: id,
            limit: windowSize,
            offset: -(windowSize / 2),
        ) ?? []
        guard !Task.isCancelled, locationContextIsCurrent else { return nil }
        if !history.contains(where: { $0.id == id }),
           let target = try? await client.getMessage(chatId: chatID, messageId: id),
           location.matches(message: target)
        {
            history.append(target)
        }
        guard !history.isEmpty, locationContextIsCurrent else { return nil }

        let loaded = await history.asyncMap { await getCustomMessage(from: $0) }
        guard !Task.isCancelled, locationContextIsCurrent else { return nil }
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

    func viewMessage(id: Int64) {
        let client = client
        let accountID = accountID
        Task {
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            try await client.viewMessages(
                chatId: chatID,
                forceRead: true,
                messageIds: [id],
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

    func submitPollAnswer(messageID: Int64, optionIDs: [Int]) {
        guard !isReadOnlyTopic,
              locationContextIsCurrent,
              messages.contains(where: { message in
                  message.id == messageID || message.album.contains(where: { $0.id == messageID })
              })
        else { return }
        let client = client
        Task {
            do {
                guard locationContextIsCurrent else { return }
                _ = try await client.setPollAnswer(
                    chatId: chatID,
                    messageId: messageID,
                    optionIds: optionIDs,
                )
            } catch {
                log("Couldn't submit poll answer for \(messageID): \(error.localizedDescription)")
                pollInteractionStore.failSubmission(messageID: messageID)
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
        let client = client
        reactionMutationTasks[messageID] = Task { [weak self, weak message] in
            guard let self else { return }
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
        guard info.chatId == location.chatID,
              info.forumTopicId == location.forumTopicID
        else { return }
        forumTopicInfo = info
    }

    func loadForumTopic() {
        guard let forumTopicID = location.forumTopicID else { return }
        forumTopicTask?.cancel()
        let client = client
        let accountID = accountID
        let expectedComposerRevision = composerRevision
        forumTopicTask = Task { [weak self] in
            guard let self else { return }
            do {
                let topic = try await client.getForumTopic(
                    chatId: location.chatID,
                    forumTopicId: forumTopicID,
                )
                guard !Task.isCancelled,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                forumTopic = topic
                forumTopicInfo = topic.info
                if awaitingAuthoritativeDraftClear, topic.draftMessage == nil {
                    awaitingAuthoritativeDraftClear = false
                    composerIsDirty = false
                } else if !awaitingAuthoritativeDraftClear, canWriteBasicMessages {
                    applyAuthoritativeDraft(
                        topic.draftMessage,
                        expectedRevision: expectedComposerRevision,
                    )
                }
                forumTopicTask = nil
            } catch {
                guard !Task.isCancelled,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                forumTopicTask = nil
            }
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
        markComposerDirty()
        replySelectionGeneration &+= 1
        replyMessage = message
        replyQuote = nil
        replyInputOverride = nil
        replyFallbackPresentation = nil
    }

    func beginQuoteReply(to message: CustomMessage) {
        guard location.matches(message: message.message) else { return }
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
    }

    func updateComposerTextFromUser(_ value: AttributedString) {
        markComposerDirty()
        text = value
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
        
        customMessage.formattedText = customMessage.contentPresentation.formattedText
        
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
        if canEditMessage {
            let sentEditID = editCustomMessage?.id
            do {
                _ = try await editMessage()
                guard locationContextIsCurrent else { return }
                if editCustomMessage?.id == sentEditID {
                    editMessageText = ""
                    editCustomMessage = nil
                }
                sendErrorMessage = nil
            } catch {
                sendErrorMessage = error.localizedDescription
            }
            return
        }
        let sentText = text
        let sentImageIDs = Set(displayedImages.map(\.id))
        let sentReplyID = replyMessage?.id
        do {
            let context: ResolvedSendContext
            if !displayedImages.isEmpty {
                context = try await sendMessagePhotos()
            } else if !text.characters.isEmpty {
                context = try await sendMessageText()
            } else {
                return
            }
            let draftClearSucceeded = await clearRouteDraft(context)
            guard locationContextIsCurrent else { return }
            displayedImages.removeAll { sentImageIDs.contains($0.id) }
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
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    func sendMessagePhotos() async throws -> ResolvedSendContext {
        let context = try resolveSendContext(
            for: .photo,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        let images = displayedImages
        guard !images.isEmpty else { throw ChatSendContextError.chatPermissionDenied }
        let caption = FormattedText(entities: getEntities(from: text), text: text.string)
        try await client.sendChatAction(
            action: .chatActionUploadingPhoto(.init(progress: 0)),
            businessConnectionId: nil,
            chatId: context.chatID,
            topicId: context.destinationTopic,
        )
        do {
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
            }
            try? await cancelChatAction(in: context)
            return context
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

    func sendMessageText() async throws -> ResolvedSendContext {
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
        return context
    }

    func submitVideoNote(
        _ asset: VideoNoteAsset,
        thumbnail: VideoNoteInputThumbnailAsset? = nil,
        originRecordingDraftID: UUID? = nil,
        replyingTo reply: CustomMessage?,
        storedReplyMessageID: Int64? = nil,
        storedReplyTo: InputMessageReplyTo? = nil,
    ) async -> VideoNoteSubmissionResult {
        let sendContext: ResolvedSendContext
        do {
            sendContext = try resolveSendContext(for: .videoNote, replyingTo: reply)
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
            return .enqueued
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
            let activeSendContext = try resolveSendContext(for: .videoNote, replyingTo: nil)
            guard draft.destination == activeSendContext.draftKey else {
                throw ChatSendContextError.unexpectedDestination
            }
            try? await tdSendChatAction(.chatActionUploadingVideoNote(.init(progress: 0)))
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
            try? await tdSendChatAction(.chatActionCancel)
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
            return .enqueued
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
            try? await tdSendChatAction(.chatActionCancel)
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
            )
            if case .retained(_, _, let message) = result {
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

    func editMessage() async throws -> ResolvedSendContext {
        let context = try resolveSendContext(for: .text, replyingTo: nil)
        guard let message = editCustomMessage?.message,
              context.matches(message: message)
        else { throw ChatSendContextError.unexpectedDestination }
        
        switch message.content {
        case .messageText:
            _ = try await client.editMessageText(
                chatId: customChat.chat.id,
                inputMessageContent:
                .inputMessageText(
                    .init(
                        clearDraft: false,
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
        case .messageAnimation, .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
            _ = try await client.editMessageCaption(
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
            throw ChatSendContextError.chatPermissionDenied
        }
        return context
    }

    func updateDraft() async {
        guard editCustomMessage == nil else { return }
        do {
            let context = try resolveSendContext(
                for: .text,
                replyingTo: replyMessage,
                useCurrentReplyOverride: true,
            )
            let draftMessage: DraftMessage? =
                if text.characters.isEmpty, context.replyTo == nil {
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
                        replyTo: context.replyTo,
                        suggestedPostInfo: nil,
                    )
                }
            try await client.setChatDraftMessage(
                chatId: context.chatID,
                draftMessage: draftMessage,
                topicId: context.draftTopic,
            )
        } catch {
            if !(error is CancellationError) {
                log("Chat draft update failed: \(error)")
            }
        }
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
        case .messageAudio(let messageAudio):
            editMessageText = getAttributedString(from: messageAudio.caption)
        case .messageDocument(let messageDocument):
            editMessageText = getAttributedString(from: messageDocument.caption)
        case .messageVideo(let messageVideo):
            editMessageText = getAttributedString(from: messageVideo.caption)
        default:
            break
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
            try await client.sendChatAction(
                action: chatAction,
                businessConnectionId: nil,
                chatId: location.chatID,
                topicId: location.topic,
            )
            return
        }
        let kind: ChatSendContentKind =
            switch chatAction {
            case .chatActionRecordingVoiceNote, .chatActionUploadingVoiceNote:
                .voiceNote
            case .chatActionRecordingVideoNote, .chatActionUploadingVideoNote:
                .videoNote
            case .chatActionUploadingPhoto:
                .photo
            default:
                .text
            }
        let context = try resolveSendContext(for: kind, replyingTo: nil)
        try await client.sendChatAction(
            action: chatAction,
            businessConnectionId: nil,
            chatId: context.chatID,
            topicId: context.destinationTopic,
        )
    }

    @MainActor func mediaStartRecordingVoice() async -> Bool {
        guard canRecordVoiceNote, locationContextIsCurrent else { return false }
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
        guard pendingVoiceNote == nil, !recordingVoiceNote, !finalizingVoiceNote else {
            await promoteNextPendingVoiceDraft()
            return false
        }
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

    func resumeVoiceRecording(confirmingTrim: Bool = false) {
        guard recordingVoiceNote,
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
        guard voiceRecordingInteractionState == .preview,
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
        voiceRecordingTrimTask = Task { [weak self] in
            guard let self else { return }
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
                previewVoiceRecordingTrimEdge(storedDraft, updatedEnd: updatedEnd)
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
        let recordingReply = pendingVoiceReplyMessage
        let recordingReplyTo = activeVoiceRecordingDraft?.replyTo
        activeVoiceRecordingDraft = nil
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

    private func permissionAllows(_ kind: ChatSendContentKind) -> Bool {
        guard customChat.canPostMessages else { return false }
        let permissions = currentChatPermissions
        return switch kind {
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
                getAttributedString(from: content.text)
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
        try await client.sendChatAction(
            action: .chatActionCancel,
            businessConnectionId: nil,
            chatId: context.chatID,
            topicId: context.destinationTopic,
        )
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
        return loaded?.filter { location.matches(message: $0) }
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
        let client = client
        pinMutationTasks[messageID] = Task { [weak self, weak message] in
            guard let self else { return }
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

    private func restoreReplyState(
        message: CustomMessage?,
        input: InputMessageReplyTo?,
    ) {
        replySelectionGeneration &+= 1
        replyMessage = message
        replyQuote = inputQuote(from: input)
        replyInputOverride = input
        replyFallbackPresentation = message == nil
            ? input.map { MessageReplyPresentation.fallback(for: $0, currentChatID: chatID) }
            : nil
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
        let context = try resolveSendContext(for: .videoNote, replyingTo: nil)
        guard draft.destination == context.draftKey else {
            throw ChatSendContextError.unexpectedDestination
        }
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
            Task { [weak self] in try? await self?.tdSendChatAction(.chatActionRecordingVoiceNote) }
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
        let reply = pendingVoiceReplyMessage ?? replyMessage
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
        voiceRecordingDraftTask?.cancel()
        voiceRecordingDraftTask = Task { [weak self] in
            guard let self else { return }
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
                        replyTo: getMessageReplyTo(from: reply),
                        revision: 0,
                        trimEnd: nil,
                        trimStart: nil,
                        waveform: inspection.waveform,
                        destination: location.draftKey,
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
                if sendAfterPreparation {
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
                    if sendAfterPreparation {
                        sendVoiceRecordingPreview()
                    }
                } else {
                    fallbackClosedVoiceSegment(
                        sourceURL: sourceURL,
                        duration: recordedDuration,
                        peakPowers: segmentPeaks,
                        reply: reply,
                    )
                }
            }
        }
        Task { [weak self] in try? await self?.tdSendChatAction(.chatActionCancel) }
    }

    private func fallbackClosedVoiceSegment(
        sourceURL: URL,
        duration: Double,
        peakPowers: [Float],
        reply: CustomMessage?,
    ) {
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
            replyTo: getMessageReplyTo(from: reply),
            temporaryMessageID: nil,
            waveform: VoiceNoteCodec.encodeWaveform(peakPowers: peakPowers),
            destination: location.draftKey,
        )
        pendingVoiceReplyMessage = reply
        cancelReply()
        startVoiceFinalization(
            sendWhenReady: false,
            pendingMessage: "Preview preparation failed. The recording was preserved as a retry draft.",
        )
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
        voiceRecordingDraftTask = Task { [weak self] in
            guard let self else { return }
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
                switch continuation {
                case .resume:
                    beginVoiceRecordingResume(materializedDraft)
                case .send:
                    sendVoiceRecordingPreview()
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
        guard voiceRecordingInteractionState == .preview,
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
        stopVoiceRecordingPreviewPlayback()
        voiceRecordingInteractionState = .pausing
        voiceRecordingDraftGeneration &+= 1
        let generation = voiceRecordingDraftGeneration
        let reply = pendingVoiceReplyMessage ?? replyMessage
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
            temporaryMessageID: nil,
            waveform: draft.waveform,
            destination: draft.destination,
        )
        voiceRecordingDraftTask = Task { [weak self] in
            guard let self else { return }
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
                voiceRecordingDraftID = nil
                voiceRecordingDraftTask = nil
                pendingVoiceNote = adoptedDraft
                pendingVoiceReplyMessage = reply
                cancelReply()
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
                )
            } catch {
                if let adoptedSendDraft, Task.isCancelled || voiceRecordingDraftGeneration != generation {
                    await VoiceNoteDraftStore.shared.remove(adoptedSendDraft)
                }
                guard voiceRecordingDraftGeneration == generation else { return }
                voiceRecordingDraftTask = nil
                voiceRecordingInteractionState = .preview
                voiceNoteErrorMessage = "Couldn’t prepare the voice preview for sending."
                loadVoiceRecordingPreview(draft)
            }
        }
    }

    private func restoreVoiceRecordingDraft(_ draft: VoiceRecordingDraft) {
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
        Media.shared.stop()
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
            destination: location.draftKey,
        )
        pendingVoiceReplyMessage = reply
        cancelReply()
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

    private func sendMessageVoiceNote(fileURL: URL, draft: VoiceNoteSendDraft) async throws -> Message {
        let context = try resolveSendContext(for: .voiceNote, replyingTo: nil)
        guard draft.destination == context.draftKey else {
            throw ChatSendContextError.unexpectedDestination
        }
        try await validateStoredReply(draft.replyTo, in: context)
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
        guard context.matches(message: message) else {
            throw ChatSendContextError.unexpectedDestination
        }
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
                    #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-preview-send") {
                            log("Voice preview smoke: promoted encoded=\(draft.isEncoded)")
                        }
                    #endif
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
                    let context = try resolveSendContext(for: .voiceNote, replyingTo: nil)
                    guard draft.destination == context.draftKey else {
                        throw ChatSendContextError.unexpectedDestination
                    }
                    let resentMessages = try await client.resendMessages(
                        chatId: chatID,
                        messageIds: [failedSendState.messageID],
                        paidMessageStarCount: 0,
                        quote: nil,
                    )
                    guard let resentMessage = resentMessages.messages?.first else {
                        throw VoiceNoteFailure.resendUnavailable
                    }
                    guard context.matches(message: resentMessage)
                    else { throw ChatSendContextError.unexpectedDestination }
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
                let resolution = bufferedResolution ?? registrationResolution ?? deletionResolution
                if let resolution {
                    applyVoiceNoteDraftResolution(resolution)
                } else {
                    outgoingVoiceNotes[message.id] = registration?.draft ?? draft
                    if registration != nil {
                        await promoteNextPendingVoiceDraft()
                    }
                }
                if resolution?.outcome != .failed {
                    await clearRouteDraftAfterMediaSend(draft.destination)
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
        guard draft.destination == location.draftKey else { return }
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
        guard draft.replyTo != nil || draft.replyMessageID != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let reply = await resolveStoredReply(replyTo: draft.replyTo, legacyMessageID: draft.replyMessageID)
            guard pendingVoiceNote?.id == draft.id else { return }
            pendingVoiceReplyMessage = reply
        }
    }

    private func clearRouteDraftAfterMediaSend(_ destination: ChatDraftKey?) async {
        guard let accountID = destination?.accountID,
              destination == location.draftKey,
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
        guard locationContextIsCurrent else { return }
        composerRevision &+= 1
        let hasNewComposerState = !text.characters.isEmpty || replyMessage != nil || !displayedImages.isEmpty
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
        let drafts = await VoiceNoteDraftStore.shared.drafts(for: location.draftKey)
        guard pendingVoiceNote == nil,
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
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let rawValue = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?
                          .uintValue,
                          AVAudioSession.InterruptionType(rawValue: rawValue) == .began,
                          recordingVoiceNote
                else { return }
                switch voiceRecordingInteractionState {
                case .holding:
                    updateVoiceRecordingDuration()
                    if timerCount >= 0.5 {
                        voiceRecordingInteractionState = .locked
                        closeVoiceRecordingSegment(sendAfterPreparation: false)
                    } else {
                        finishVoiceRecording(
                            sendWhenReady: false,
                            pendingMessage: "Voice recording was interrupted before a preview could be created.",
                        )
                    }
                case .locked where activeVoiceRecordingDraft == nil:
                    updateVoiceRecordingDuration()
                    if timerCount >= 0.5 {
                        closeVoiceRecordingSegment(sendAfterPreparation: false)
                    } else {
                        finishVoiceRecording(
                            sendWhenReady: false,
                            pendingMessage: "Voice recording was interrupted before a preview could be created.",
                        )
                    }
                case .locked where canPauseVoiceRecording:
                    closeVoiceRecordingSegment(sendAfterPreparation: false)
                case .locked:
                    audioRecorder?.stop()
                    audioRecorder = nil
                    if let recordingVoiceNoteURL {
                        try? FileManager.default.removeItem(at: recordingVoiceNoteURL)
                    }
                    recordingVoiceNoteURL = nil
                    pauseVoiceRecordingTimer()
                    Media.shared.endAudioSessionRecord()
                    if let draft = activeVoiceRecordingDraft {
                        timerCount = draft.exactDuration
                        voiceRecordingInteractionState = .preview
                        loadVoiceRecordingPreview(draft)
                    }
                case .idle, .pausing, .preview, .resuming:
                    break
                }
            }
            .store(in: &cancellables)
    }
}
