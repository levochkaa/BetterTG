// ChatVM.swift

import AVFoundation
import Combine
import ImageIO
import TDLibKit
import UIKit

// MARK: - ChatVM

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
        let rawNewestMessageID: Int64?
        let readToken: ChatHistoryRestorationRefresh.ReadToken?
    }

    /// History a jump skipped: no message with `olderBoundID < id < newerBoundID` is loaded, though the chat may
    /// have some. Telegram's history view never shows such a hole, so scrolling toward one loads it.
    struct HistoryGap: Equatable {
        var olderBoundID: Int64
        var newerBoundID: Int64
    }

    /// What a vote turned out to be, for Telegram's feedback after requestSelectMessagePollOptions: a quiz answer is
    /// right or wrong once TDLib reveals the right ones, and a poll hiding its results until it closes says so.
    struct PollAnswerOutcome {
        /// nil for a regular poll, or a quiz whose right answers stay hidden.
        let quizAnswerIsRight: Bool?
        /// The quiz has an explanation to open after a wrong answer.
        let hasExplanation: Bool
        let resultsHidden: Bool
    }

    /// ChatChannelSubscriberInputPanelNode's actions (`actionForPeer`).
    enum SubscriberPanelAction: Equatable {
        case join
        case joinGroup
        case applyToJoin
        case mute
        case unmute

        var title: String {
            switch self {
            case .join: L10n.telegram("Channel.JoinChannel")
            case .joinGroup: L10n.telegram("Group.JoinGroup")
            case .applyToJoin: L10n.telegram("Group.ApplyToJoin")
            case .mute: L10n.telegram("Conversation.Mute")
            case .unmute: L10n.telegram("Conversation.Unmute")
            }
        }

        var isJoin: Bool {
            switch self {
            case .applyToJoin,
                 .join,
                 .joinGroup: true
            case .mute,
                 .unmute: false
            }
        }
    }

    /// The input panels of inputPanelForChatPresentationIntefaceState that stand in for the composer.
    enum StatusPanel: Equatable {
        case subscriber(SubscriberPanelAction)
        /// ChatUnblockInputPanelNode.
        case unblock
        /// ChatRestrictedInputPanelNode with its text.
        case restricted(String)
        /// DeleteChatInputPanelNode: a group the user left or was removed from, a channel or group they were banned
        /// from.
        case deleteChat
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

    #if DEBUG
        /// `-ui-probe-bot-menu-button`: a made-up Web App menu button for one chat.
        static var probeBotMenuButton: (chatID: Int64, button: TDNativeBotMenuButton)?
    #endif

    private static let historyPageSize = 30

    let messagesDidChange = PassthroughSubject<Void, Never>()
    /// The 50 ms recording tick publishes here instead of `objectWillChange`, so only the composer's recording row
    /// follows it, as Telegram updates only ChatTextInputAudioRecordingTimeNode.
    let recordingTimeChanged = PassthroughSubject<Void, Never>()
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
    /// The chat's bot reply keyboard, shown by the composer in place of the system keyboard.
    lazy var replyKeyboard = ChatReplyKeyboardModel(
        chatID: chatID,
        accountID: accountID,
        client: client,
        isCurrent: { [weak self] in self?.locationContextIsCurrent == true },
    )
    /// Who acts in this chat, one entry per sender and topic, oldest first (Telegram's input activities).
    @Published var chatActions = [ChatActionEntry]()
    @Published var onlineStatus = ""
    private(set) var isUserOnline = false
    /// The other user is offline with a known last-seen time, the presence Telegram offers Send When Online for.
    private(set) var userLastSeenIsKnown = false
    /// TDLib's `hasScheduledMessages`: the composer then offers the chat's Scheduled Messages.
    @Published var hasScheduledMessages = false
    /// A composer send that only scheduled its message; the chat opens Scheduled Messages, as Telegram does.
    let scheduledComposerSend = PassthroughSubject<Void, Never>()
    @Published var memberCount = 0
    @Published var onlineMemberCount = 0
    @Published private(set) var editCustomMessage: CustomMessage? {
        didSet { queueForumTopicDemandRefresh() }
    }

    @Published var pendingForward: PendingMessageForward? {
        didSet {
            if pendingForward != oldValue { storePendingForward() }
        }
    }

    /// Telegram's `botStartPayload`: a bot link's start parameter waits for the user's Start
    /// (ChatBotStartInputPanelNode) instead of the text input.
    @Published private(set) var botStartParameter: String?
    @Published private(set) var isStartingBot = false
    /// ChatBotInfoItem: the bot's "What can this bot do?" description, photo and animation for its chat.
    @Published private(set) var botInfo: TDNativeBotInfo?
    /// Telegram's peerCommands: the commands of the chat's bot or of the group's bots.
    @Published private(set) var botCommands = [ChatBotCommand]()
    /// ChatTextInputPanelNode's Menu opens the whole command list (CommandMenuChatInputContextPanelNode).
    @Published var showsBotCommandMenu = false
    /// The inline bot the input addresses and its results (contextRequestResult).
    @Published private(set) var inlineBotQuery: InlineBotQueryState?
    /// An inline bot that needs the location and hasn't been answered yet: the chat screen asks
    /// Conversation.ShareInlineBotLocationConfirmation (requestBotLocationStatus).
    @Published private(set) var inlineBotLocationRequest: Int64?
    /// The history was read to its start without a message (`chatHistoryState == .loaded(isEmpty: true)`).
    @Published private(set) var historyLoadedEmpty = false
    /// The history is read back to the chat's first message, where Telegram puts a bot's info.
    @Published private(set) var historyReachedStart = false
    /// MentionChatInputContextPanelNode's results for the "@" word at the caret.
    @Published private(set) var mentionSuggestions = [ChatMentionSuggestion]()
    /// HashtagChatInputContextPanelNode's results for the "#" word at the caret.
    @Published private(set) var hashtagSuggestions: ChatHashtagSuggestions?
    /// EmojisChatInputContextPanelNode's results for the ":" word at the caret.
    @Published private(set) var emojiSuggestions = [ChatEmojiSuggestion]()
    /// InlineReactionSearchPanel's stickers for a lone emoji in the input.
    @Published private(set) var stickerSuggestions = [Sticker]()
    /// The user blocked this chat's person or bot (`chat.block_list`); a blocked bot offers Restart Bot.
    @Published private(set) var isChatBlocked = false
    /// The chat's latest `updateChatNotificationSettings`; a navigation-hydrated chat isn't updated by the chat list.
    @Published private(set) var chatNotificationSettings: ChatNotificationSettings?
    /// ChatChannelSubscriberInputPanelNode's `isJoining`: from the Join tap until TDLib answers, a channel shows Mute.
    @Published private(set) var isJoiningChat = false
    /// ChatUnblockInputPanelNode's `unblockingPeer`.
    @Published private(set) var isUnblockingChat = false

    @Published var replyMessage: CustomMessage? {
        didSet {
            queueForumTopicDemandRefresh()
            if let oldID = oldValue?.id, oldID != replyMessage?.id, supportsReplyKeyboard {
                replyKeyboard.noteReplyEnded(messageID: oldID)
            }
        }
    }

    @Published private(set) var replyQuote: InputTextQuote?
    @Published private(set) var replyInputOverride: InputMessageReplyTo?
    @Published private(set) var replyFallbackPresentation: MessageReplyPresentation?
    @Published var highlightedMessageId: Int64?
    @Published var displayedImages = [SelectedImage]()
    @Published var displayedDocuments = [SelectedDocument]()
    /// MediaPickerScreen's Move Caption Up for the composer's photos and videos (`showCaptionAboveMedia`).
    @Published var mediaCaptionIsAbove = false
    @Published var text: AttributedString = "" {
        didSet {
            if text != oldValue {
                scheduleComposerLinkPreview()
                updateInlineBotQuery()
                if text.characters.isEmpty,
                   editCustomMessage == nil { updateMentionQuery(nil, includesInlineBots: false) }
            }
        }
    }

    /// Telegram's `urlPreview` for the composer: the preview of the input's first link, from `getLinkPreview`.
    @Published private(set) var composerLinkPreview: TDNativeLinkPreview?
    /// The link panel's choices for that link: Do Not Preview, above or below the text, larger or smaller media.
    @Published private(set) var composerLinkPreviewOptions: TDNativeLinkPreviewOptions?

    @Published var editMessageText: AttributedString = "" {
        didSet {
            if editMessageText != oldValue {
                composerEditState.changeText()
                scheduleEditLinkPreview()
                if editMessageText.characters.isEmpty { updateMentionQuery(nil, includesInlineBots: false) }
            }
        }
    }

    /// Telegram's `editingUrlPreview`: the preview of the first link in a text message being edited.
    @Published private(set) var editLinkPreview: TDNativeLinkPreview?
    /// The edit's link panel choices, starting from the message's own.
    @Published private(set) var editLinkPreviewOptions: TDNativeLinkPreviewOptions?

    @Published var recordingVoiceNote = false
    /// Telegram's play-once toggle on a locked or previewed voice recording (ChatTextInputPanelNode.viewOnce).
    @Published var sendsVoiceViewOnce = false
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
    /// A failed poll vote, Retract Vote, Stop Poll or Stop Sharing, shown once by the chat.
    @Published var messageActionErrorMessage: String?
    @Published private(set) var forumTopic: ForumTopic?
    /// The chat's unread mentions and reactions behind Telegram's history navigation buttons. A forum topic route
    /// counts from its `ForumTopic`, and TDLib keeps no count for a reply thread.
    @Published var chatUnreadMentionCount = 0
    @Published var chatUnreadReactionCount = 0
    @Published private(set) var forumTopicInfo: ForumTopicInfo?
    @Published private(set) var forumTopicsByID = [Int: ForumTopic]()
    /// A thread route's `getMessageThread` answer. Its root messages head the history, as Telegram's thread head.
    @Published private(set) var messageThread: MessageThreadInfo?
    /// The thread root's reply info, kept current by `updateMessageInteractionInfo`: the reply count that titles the
    /// chat and the thread's read watermarks.
    @Published private(set) var messageThreadReplyInfo: MessageReplyInfo?
    @Published var errorShown = false
    var loadingMessagesTask: Task<Void, Never>?
    var cancellables = Set<AnyCancellable>()
    var timer: Timer?
    var wave = [Float]()
    var sendMessageTask: Task<Void, Never>?
    var voiceFinalizeTask: Task<Void, Never>?
    var recordingVoiceNoteURL: URL?
    var chatInfoTask: Task<Void, Never>?
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

    private(set) var historyGaps = [HistoryGap]()

    /// The private chat's user doesn't accept voice and video notes (`hasRestrictedVoiceAndVideoNoteMessages`).
    private(set) var recipientRestrictsVoiceAndVideoNotes = false
    /// A secret chat sends nothing until TDLib reports its state ready; nil until the state is known.
    private(set) var secretChatIsReady: Bool?

    private var timerCountStorage = 0.0
    private var voiceFinalizationGeneration = UInt64.zero
    private var voiceDraftRefreshGeneration = UInt64.zero
    @Published private var pendingVoiceDraftIsFinalizing = false

    private let chatOpenLease: ChatOpenLease
    private var deliveryReceipts: ChatDeliveryReceiptState
    private var deliveryReadTask: Task<Void, Never>?
    private var currentChatPermissions: ChatPermissions
    /// When the supergroup's slow mode lets this account send again (`slowModeDelayExpiresIn`); TDLib reports 0 for
    /// admins and chats without slow mode.
    private var slowModeExpiresAt: Date?

    private var recordingActionRefreshTask: Task<Void, Never>?
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
    private var messageThreadTask: Task<MessageThreadInfo?, Never>?
    private var messageThreadReplyInfoRevision = UInt64.zero

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
    private var hasMoreMessages = true {
        didSet {
            if historyReachedStart == hasMoreMessages { historyReachedStart = !hasMoreMessages }
        }
    }

    private var oldestHistoryMessageID: Int64?
    private var historyGapTask: Task<Void, Never>?
    private var messageRefresh: ChatHistoryRestorationRefresh?
    private var messageRefreshTask: Task<Void, Never>?
    private var latestRestorationCursor: ChatHistoryLatestRefreshCursor?
    private var restorationWaitsForViewport = false
    private var latestRestorationFailed = false
    private var messageReplacementIDs = [Int64: Int64]()
    /// The album `sendMessageAlbum` is creating. TDLib announces its members one `updateNewMessage` at a time, and
    /// each one reaches `messages` after its own hydration; Telegram inserts a sent album in one transaction, so the
    /// timeline waits for the whole album.
    private var outgoingAlbumHold: (id: UUID, count: Int)?
    /// A composer media send TDLib is still creating. Telegram inserts the sent message in the transaction that clears
    /// the input; the timeline holds the messages this send creates until the composer clears, so both change at once.
    /// Until the send call returns, any new pending outgoing message may be one of them; then only the returned ones.
    private var composerSendHold: (id: UUID, earlierMessageIDs: Set<Int64>, sentMessageIDs: Set<Int64>?)?
    /// The send-button menu's options for the composer send in progress (silent, scheduled or when online).
    private var composerSendOptions: TDNativeMessageSendOptions?
    /// How the send menu asked the composer's photos and videos to go.
    private var composerMediaSendMode = ComposerMediaSendMode.grouped
    private var composerLinkPreviewTask: Task<Void, Never>?
    private var composerLinkPreviewRequest: FormattedText?
    private var editLinkPreviewTask: Task<Void, Never>?
    private var editLinkPreviewRequest: FormattedText?
    private var botInfoTask: Task<Void, Never>?
    private var inlineBotQueryTask: Task<Void, Never>?
    private var inlineBotMoreTask: Task<Void, Never>?
    private var mentionQueryTask: Task<Void, Never>?
    private var mentionQuery: (query: String, includesInlineBots: Bool)?
    private var contextQueryTask: Task<Void, Never>?
    private var contextQuery: ChatInputContextQuery?

    /// Discrete changes (start, stop, restored drafts) publish like the other state; the tick writes the storage.
    var timerCount: Double {
        get { timerCountStorage }
        set {
            objectWillChange.send()
            timerCountStorage = newValue
        }
    }

    var canSendLivePhotos: Bool {
        if case .chatTypeSecret = customChat.chat.type {
            false
        } else {
            true
        }
    }

    /// MediaPickerScreen's isSpoilerAvailable: spoilers aren't offered in secret chats.
    var canHideMediaWithSpoiler: Bool {
        canSendLivePhotos
    }

    /// LegacyMediaPickerGallery's `hasCoverButton`: a video's cover is chosen in broadcast channels and Saved
    /// Messages.
    var allowsVideoCover: Bool {
        customChat.isBroadcastChannel || customChat.isSavedMessages
    }

    /// ChatSendMessageContextScreen's `canSchedule`: secret chats and channel direct messages can't schedule.
    var canScheduleMessages: Bool {
        if previewing || customChat.supergroup?.isDirectMessagesGroup == true { return false }
        if case .chatTypeSecret = customChat.chat.type { return false }
        return true
    }

    /// Telegram offers Send When Online in a chat with a person whose last seen time is known and past, other than
    /// the service notifications account; Saved Messages sets reminders instead.
    var canSendWhenOnline: Bool {
        guard canScheduleMessages, !customChat.isSavedMessages, case .user(let user) = customChat.type,
              user.id != 777_000 else { return false }
        return userLastSeenIsKnown
    }

    var visiblePinnedMessage: Message? {
        PinnedMessageState.visibleMessage(
            newest: pinnedMessage,
            locallyHiddenMessageID: locallyHiddenPinnedMessageID,
            supported: supportsPinnedMessages,
        )
    }

    /// The pinned message request is still in flight, so a missing banner message is not an answer yet.
    var pinnedMessageIsLoading: Bool { pinnedMessageTask != nil }

    /// Telegram shows a forum topic's own pins, and a forum read as messages shows the forum's
    /// (ChatController.topPinnedMessageSignal: `.peer` and forum-post `.replyThread` locations).
    var supportsPinnedMessages: Bool {
        guard !previewing, customChat.supergroup?.isDirectMessagesGroup != true else { return false }
        if location.forumTopicID != nil { return true }
        return !location.isTopicScoped
            && (customChat.supergroup?.isForum != true || isAllMessagesForum)
            && !customChat.chat.viewAsTopics
    }

    /// A forum topic keeps its composer to explain why it can't be written to. A reply thread without write access
    /// behaves like a chat without it.
    var isReadOnlyTopic: Bool {
        location.forumTopicID != nil && !canWriteAnyMessage
    }

    /// Telegram's Restart Topic panel in a closed topic, for the forum's creator, topic managers and the topic's
    /// creator (ChatInterfaceTitlePanelNodes, ChatReportPeerTitlePanelNode `.restartTopic`). General can't close.
    var canReopenTopic: Bool {
        guard !previewing, location.forumTopicID != nil, let info = forumTopicInfo, info.isClosed, !info.isGeneral
        else { return false }
        return customChat.canManageForumTopics || info.isOutgoing
    }

    /// Telegram's Close/Reopen in a topic's avatar menu: the forum's creator, topic managers and the topic's creator,
    /// never for General (ChatController, `canOpenClose` for `.replyThread`).
    var canToggleTopicClosed: Bool {
        guard !previewing, location.forumTopicID != nil, let info = forumTopicInfo,
              !info.isGeneral else { return false }
        return customChat.canManageForumTopics || info.isOutgoing
    }

    /// Telegram's `ChatReplyThreadMessage.isChannelPost`: the thread starts at a channel post that the channel
    /// forwarded to its discussion group (`SourceReferenceMessageAttribute`, TDLib's `forwardInfo.source`). Nil
    /// until the thread is read.
    var messageThreadIsChannelPost: Bool? {
        guard let threadID = location.messageThreadID, let messageThread else { return nil }
        let root = messageThread.messages.first { $0.id == threadID } ?? messageThread.messages.last
        return root.map { $0.forwardInfo?.source != nil }
    }

    /// The displayed thread root once the history reaches it (ChatHistoryEntriesForView, `addedThreadHead`), and
    /// whether a reply follows it, for the notice under it.
    var messageThreadHeadDisplay: (id: DisplayedMessageID, hasReplies: Bool)? {
        guard location.messageThreadID != nil, let messageThread else { return nil }
        let rootIDs = Set(messageThread.messages.map(\.id))
        guard let head = messages.last(where: { message in
            message.sourceMessages.contains { rootIDs.contains($0.id) }
        }) else { return nil }
        return (head.displayedID, messages.contains { $0.displayedID != head.displayedID })
    }

    /// Telegram's `ChatTitleContent.replyThread` (ChatTitleView): "N Comments" in a channel post's discussion and
    /// "N Replies" in a group message's thread, or the bare noun before the first one. Until the thread is read, a
    /// channel's discussion group is assumed to show comments.
    var messageThreadTitle: String? {
        guard location.messageThreadID != nil else { return nil }
        let key = messageThreadShowsComments ? "Conversation.TitleComments" : "Conversation.TitleReplies"
        let count = messageThreadReplyInfo?.replyCount ?? 0
        guard count > 0 else { return L10n.telegram(key + "Empty") }
        // The plural form brackets its count, as in "[%@]Comments"; the format places the count itself.
        var noun = L10n.telegramPlural(key, count: count)
        if let start = noun.firstIndex(of: "["), let end = noun.firstIndex(of: "]"), start < end {
            noun.removeSubrange(start...end)
        } else {
            noun = noun.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789-,."))
        }
        return L10n.telegram(key + "Format", "\(count)", noun)
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

    var canAttachVideos: Bool {
        (try? resolveSendContext(
            for: .video,
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

    /// Telegram's attachment menu offers Location and Contact where text can be sent (`banSendText`); TDLib sends
    /// both under `canSendBasicMessages`.
    var canSendLocationAndContact: Bool {
        editCustomMessage == nil && canWriteBasicMessages
    }

    /// Telegram's attachment menu `canSendPolls`: no polls in secret chats or channel direct messages, in a private
    /// chat only with a bot or in Saved Messages, and only where the chat allows them.
    var canCreatePoll: Bool {
        guard editCustomMessage == nil, customChat.secretChatID == nil else { return false }
        switch customChat.type {
        case .user:
            guard customChat.isSavedMessages else { return false }
        case .supergroup(let group):
            guard !group.isDirectMessagesGroup else { return false }
        case .bot,
             .group:
            break
        }
        return (try? resolveSendContext(
            for: .poll,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    /// Telegram's location picker `hasLiveLocation`: live locations aren't shared in secret chats or Saved Messages.
    var canShareLiveLocation: Bool {
        customChat.secretChatID == nil && !customChat.isSavedMessages
    }

    /// The other user's name for the live location description, Telegram's `compactDisplayTitle` of a private chat's
    /// peer; nil in groups and channels.
    var liveLocationPeerName: String? {
        guard let user = customChat.user, !customChat.isSavedMessages else { return nil }
        let firstName = user.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firstName.isEmpty { return firstName }
        let lastName = user.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastName.isEmpty ? customChat.displayTitle : lastName
    }

    /// A channel's polls are anonymous and offer neither Show Who Voted nor adding options (ComposePollScreen).
    var createsChannelPoll: Bool {
        customChat.supergroup?.isChannel == true
    }

    /// ChatControllerOpenAttachmentMenu's `canSendTodos`: not in secret chats or channels, and TDLib also refuses
    /// channel direct messages chats.
    var canCreateChecklist: Bool {
        guard editCustomMessage == nil, customChat.secretChatID == nil else { return false }
        if let group = customChat.supergroup, group.isChannel || group.isDirectMessagesGroup { return false }
        return (try? resolveSendContext(
            for: .checklist,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )) != nil
    }

    var canWriteAnyMessage: Bool {
        canWriteBasicMessages || canAttachPhotos || canAttachVideos || canAttachDocuments
            || canSendStickersAndAnimations || canRecordVoiceNote || canRecordVideoNote || canCreatePoll
            || canCreateChecklist
    }

    var canShowComposer: Bool {
        !previewing && !showsUnblockPanel && (canWriteAnyMessage || pendingForward != nil)
    }

    /// The panel in the composer's place for the whole chat; threads, topics and direct messages chats keep theirs.
    var statusPanel: StatusPanel? {
        guard !previewing, location.messageThreadID == nil, location.forumTopicID == nil else { return nil }
        if showsUnblockPanel { return .unblock }
        return Self.statusPanel(
            for: customChat.type,
            canWrite: canShowComposer,
            isJoining: isJoiningChat,
            isMuted: isNotificationMuted,
        )
    }

    /// RootVM.isMuted for the chat's latest settings: its own mute, else its scope's.
    var isNotificationMuted: Bool {
        let settings = chatNotificationSettings ?? customChat.chat.notificationSettings
        if settings.useDefaultMuteFor,
           let scope = RootVM.shared.scopeNotificationSettings[customChat.notificationSettingsScope]
        {
            return scope.muteFor > 0
        }
        return settings.muteFor > 0
    }

    /// Telegram offers play-once voice only in a cloud chat with another user that isn't a bot.
    var canSendVoiceViewOnce: Bool {
        guard case .chatTypePrivate = customChat.chat.type, case .user = customChat.type else { return false }
        return !customChat.isSavedMessages
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
        // Telegram's keyboard placeholder replaces the chat's own (`visibleReplyMarkupPlaceholder`).
        if supportsReplyKeyboard, editCustomMessage == nil,
           let placeholder = replyKeyboard.placeholder(replyMessageID: replyMessage?.id)
        {
            return placeholder
        }
        if location.messageThreadID != nil {
            return L10n.telegram(messageThreadShowsComments
                ? "Conversation.InputTextPlaceholderComment"
                : "Conversation.InputTextPlaceholderReply")
        }
        if isAllMessagesForum {
            let info = replyMessage
                .flatMap { forumTopicInfo(for: $0.message.topicId) }
                ?? generalForumTopic?.info
            guard let topicName = info?.name else { return L10n.telegram("Conversation.InputTextPlaceholder") }
            return replyMessage == nil
                ? L10n.telegram("Chat.InputPlaceholderMessageInTopic", topicName)
                : L10n.telegram("Chat.InputPlaceholderReplyInTopic", topicName)
        }
        guard let topicName = forumTopicInfo?.name, location.isTopicScoped else {
            return L10n.telegram("Conversation.InputTextPlaceholder")
        }
        return replyMessage == nil
            ? L10n.telegram("Chat.InputPlaceholderMessageInTopic", topicName)
            : L10n.telegram("Chat.InputPlaceholderReplyInTopic", topicName)
    }

    /// Bot keyboards belong to the whole chat; a topic or a preview has none.
    var supportsReplyKeyboard: Bool {
        !previewing && location.topic == nil && !isAllMessagesForum
    }

    var composerRestrictionText: String {
        if isAllMessagesForum {
            if let replyMessage,
               let info = forumTopicInfo(for: replyMessage.message.topicId),
               info.isClosed || info.isHidden
            {
                return L10n.betterTG("Composer.ClosedTopicReplies")
            }
            if generalForumTopic == nil {
                return L10n.betterTG("Composer.LoadingGeneralTopic")
            }
        }
        if forumTopicInfo?.isClosed == true || forumTopicInfo?.isHidden == true {
            return L10n.betterTG("Composer.ClosedTopicRestriction")
        }
        return L10n.betterTG("Composer.TopicRestriction")
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
        guard !customChat.isSavedMessages else { return "" }
        guard actionStatus.isEmpty else { return actionStatus }
        switch customChat.type {
        case .bot,
             .user:
            return onlineStatus
        case .group:
            return Self.memberStatus(memberCount: memberCount, onlineMemberCount: onlineMemberCount)
        case .supergroup(let group):
            guard memberCount > 0 else {
                return group.isChannel ? L10n.telegram("Channel.Status") : L10n.telegram("Group.Status")
            }
            if group.isChannel {
                return Self.countStatus("Conversation.StatusSubscribers", count: memberCount)
            }
            return Self.memberStatus(memberCount: memberCount, onlineMemberCount: onlineMemberCount)
        }
    }

    var headerStatusIsActive: Bool {
        if location.forumTopicID != nil { return topicActivityStatus != nil }
        if !actionStatus.isEmpty { return true }
        guard !customChat.isSavedMessages else { return false }
        switch customChat.type {
        case .bot,
             .user: return isUserOnline
        case .group,
             .supergroup: return false
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

    var canContinueVoiceRecording: Bool {
        if let draft = activeVoiceRecordingDraft {
            return (try? resolveFrozenMediaSendContext(
                for: .voiceNote,
                destination: draft.destination,
                sendTopic: draft.sendTopic,
                replyTo: draft.replyTo,
            )) != nil
        }
        if let context = activeVoiceRecordingContext {
            return (try? resolveFrozenMediaSendContext(
                for: .voiceNote,
                destination: context.draftKey,
                sendTopic: context.destinationTopic,
                replyTo: context.replyTo,
            )) != nil
        }
        return canRecordVoiceNote
    }

    var voiceRecordingPreviewPath: String? {
        guard voiceRecordingInteractionState == .preview else { return nil }
        return activeVoiceRecordingDraft?.fileURL.path(percentEncoded: false)
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

    #if DEBUG
        var historyDiagnosticSummary: String {
            let ids = messages.flatMap { $0.sourceMessages.map(\.id) }
            let gaps = historyGaps.lazy.map { "\($0.olderBoundID)...\($0.newerBoundID)" }.joined(separator: ",")
            return "rows \(messages.count) newest \(ids.max() ?? 0) oldest \(ids.min() ?? 0) gaps [\(gaps)] "
                + "latestCursor \(latestRestorationCursor != nil) latestFailed \(latestRestorationFailed) "
                + "waitsForViewport \(restorationWaitsForViewport) more \(hasMoreMessages)"
        }
    #endif

    /// The message the reply goes to: an album item a quote came from, or the replied message.
    var replyTargetMessageID: Int64? {
        switch replyInputOverride {
        case .inputMessageReplyToMessage(let reply): reply.messageId
        case .inputMessageReplyToExternalMessage(let reply): reply.messageId
        case .inputMessageReplyToEphemeralMessage,
             .inputMessageReplyToStory,
             nil: replyMessage?.id
        }
    }

    /// The link panel shown in the reply slot: a text message's preview the user hasn't turned off. Telegram's
    /// accessory panels put it ahead of a forward or a reply, and while editing ahead of the edit panel; a media
    /// caption has no link preview.
    var visibleComposerLinkPreview: TDNativeLinkPreview? {
        if editCustomMessage != nil {
            guard let preview = editLinkPreview, currentEditLinkPreviewOptions?.isDisabled != true else { return nil }
            return preview
        }
        guard editCustomMessage == nil, displayedImages.isEmpty, displayedDocuments.isEmpty,
              let preview = composerLinkPreview, currentLinkPreviewOptions?.isDisabled != true else { return nil }
        return preview
    }

    /// The choices of the link panel on screen: the edit's while editing, otherwise the composer's.
    var visibleLinkPreviewOptions: TDNativeLinkPreviewOptions? {
        editCustomMessage == nil ? currentLinkPreviewOptions : currentEditLinkPreviewOptions
    }

    /// The options the composer sends and keeps in its draft; nil leaves TDLib's own preview.
    var composerLinkPreviewSendOptions: TDNativeLinkPreviewOptions? {
        currentLinkPreviewOptions
    }

    /// ChatTextInputPanelNode's Start: after a bot link, or in a bot chat whose history is empty and has no topic.
    var showsBotStart: Bool {
        guard editCustomMessage == nil, !previewing else { return false }
        if botStartParameter != nil { return true }
        guard case .bot = customChat.type else { return false }
        // ChatUnblockInputPanelNode: a blocked bot's input is Restart Bot.
        if isChatBlocked { return true }
        guard location.topic == nil, location.messageThreadID == nil else { return false }
        return historyLoadedEmpty && messages.isEmpty
    }

    /// "Restart Bot" for a blocked bot (Bot.Unblock), otherwise "Start".
    var botStartTitle: String {
        L10n.telegram(isChatBlocked ? "Bot.Unblock" : "Bot.Start")
    }

    // MARK: Bots

    /// CommandChatInputContextPanelNode's results: the commands starting with the "/" word the input is.
    var commandSuggestions: [ChatBotCommand] {
        guard editCustomMessage == nil, !botCommands.isEmpty,
              case .command(let query) = ChatInputQuery.parse(text.string) else { return [] }
        let normalized = query.lowercased()
        return botCommands.filter { $0.command.lowercased().hasPrefix(normalized) }
    }

    /// inputTextPanelStateForChatPresentationInterfaceState's contextPlaceholder: the resolved inline bot's
    /// placeholder while the input is "@bot " with an empty query.
    var inlineBotPlaceholder: String? {
        guard editCustomMessage == nil, let state = inlineBotQuery, !state.placeholder.isEmpty,
              case .inlineBot(let username, let query) = ChatInputQuery.parse(text.string), query.isEmpty,
              username.lowercased() == state.username.lowercased() else { return nil }
        return state.placeholder
    }

    /// ChatTextInputPanelNode's menu button: a bot chat with commands or with a Web App menu button
    /// (`hasBotCommands` or `botMenuButton == .webView`), outside editing.
    var showsBotMenuButton: Bool {
        guard editCustomMessage == nil, !showsBotStart else { return false }
        if botMenuWebApp != nil { return true }
        guard case .bot = customChat.type else { return false }
        return !botCommands.isEmpty
    }

    /// The bot's `.webView` menu button (`BotInfo.menuButton`): its text names the Menu button, and its URL opens the
    /// bot's Web App in place of the command list. Nil for the commands menu.
    var botMenuWebApp: TDNativeBotMenuButton? {
        #if DEBUG
            if let probe = Self.probeBotMenuButton, probe.chatID == chatID { return probe.button }
        #endif
        guard case .bot = customChat.type else { return nil }
        return botInfo?.menuButton
    }

    /// The poll answer the composer's reply is to, for the reply panel's "Reply to Poll Option".
    var replyPollOption: (option: PollOption, allowsMultipleAnswers: Bool)? {
        guard case .inputMessageReplyToMessage(let reply)? = replyInputOverride, !reply.pollOptionId.isEmpty,
              let message = replyMessage, case .messagePoll(let content) = message.message.content,
              let option = content.poll.options.first(where: { $0.id == reply.pollOptionId })
        else { return nil }
        return (option, content.poll.allowsMultipleAnswers)
    }

    /// ChatUnblockInputPanelNode replaces the composer of a person the user blocked; a blocked bot's composer offers
    /// Restart Bot instead, and a secret chat keeps its own.
    private var showsUnblockPanel: Bool {
        guard isChatBlocked, case .user = customChat.type, customChat.secretChatID == nil else { return false }
        return !customChat.isSavedMessages
    }

    private var usesOrdinaryDeliveryReceipts: Bool {
        guard location.topic == nil, !customChat.chat.viewAsTopics, !customChat.isSavedMessages else { return false }
        if case .chatTypeSupergroup(let type) = customChat.chat.type {
            guard let group = customChat.supergroup, group.id == type.supergroupId else { return false }
            return !type.isChannel && !group.isForum && !group.isDirectMessagesGroup && !group.isChannel
        }
        return customChat.supergroup == nil
    }

    private var usesForumDeliveryReceipts: Bool {
        guard let id = location.forumTopicID, id > 0, !customChat.isSavedMessages else { return false }
        switch customChat.chat.type {
        case .chatTypeSupergroup(let type):
            guard let group = customChat.supergroup, group.id == type.supergroupId else { return false }
            return group.isForum && !type.isChannel && !group.isChannel && !group.isDirectMessagesGroup
        case .chatTypePrivate(let type):
            return customChat.user?.id == type.userId && customChat.bot?.hasTopics == true
        default: return false
        }
    }

    private var messageThreadShowsComments: Bool {
        messageThreadIsChannelPost ?? (customChat.supergroup?.hasLinkedChat == true)
    }

    /// A reply thread lives in a non-forum supergroup, and its root's reply info carries the thread's watermark.
    private var usesThreadDeliveryReceipts: Bool {
        guard let id = location.messageThreadID, id > 0, !customChat.isSavedMessages,
              case .chatTypeSupergroup(let type) = customChat.chat.type,
              let group = customChat.supergroup, group.id == type.supergroupId else { return false }
        return !type.isChannel && !group.isChannel && !group.isForum && !group.isDirectMessagesGroup
    }

    private var pendingVideoRetryStatusMessage: String? {
        guard let failed = pendingVideoNote?.failedSendState else { return nil }
        if failed.requiredPaidMessageStarCount > 0 {
            return L10n.betterTG("VideoNote.RetryPaidUnsupported")
        }
        if failed.needAnotherReplyQuote || failed.needAnotherSender {
            return L10n.betterTG("VideoNote.RetryNeedsAnotherReply")
        }
        if !failed.canRetry {
            return L10n.betterTG("VideoNote.RetryNotAllowed")
        }
        if failed.retryAvailableAt > Foundation.Date() {
            return L10n.betterTG("VideoNote.RetrySoon")
        }
        return nil
    }

    private var pendingVoiceRetryStatusMessage: String? {
        guard let draft = pendingVoiceNote else { return nil }
        if draft.enqueueStartedAt != nil {
            return L10n.betterTG("Voice.SendUnconfirmed")
        }
        guard let failedState = draft.failedSendState else { return nil }
        if failedState.requiredPaidMessageStarCount > 0 {
            return L10n.betterTG("Voice.RetryPaidUnsupported")
        }
        if failedState.needAnotherReplyQuote || failedState.needAnotherSender {
            return L10n.betterTG("Voice.RetryNeedsAnotherReply")
        }
        guard failedState.canRetry else {
            return L10n.betterTG("Voice.RetryNotAllowed")
        }
        if failedState.retryAvailableAt > Foundation.Date() {
            let seconds = max(1, Int(ceil(failedState.retryAvailableAt.timeIntervalSinceNow)))
            return L10n.betterTG("Voice.RetryAvailableIn", seconds)
        }
        return nil
    }

    private var canManageForumTopics: Bool {
        customChat.adminRights?.canManageTopics == true
            || {
                if case .chatMemberStatusCreator = customChat.supergroup?.status {
                    true
                } else {
                    false
                }
            }()
    }

    private var generalForumTopic: ForumTopic? {
        forumTopicsByID.values.first(where: { $0.info.isGeneral })
    }

    private var composerCanTransfer: Bool {
        !previewing && !composerRestorationLifetime.isRetired
            && !sendingComposerMessage && sendMessageTask == nil
            && !loadingVoiceDraft && !startingVoiceNote && !finalizingVoiceNote
            && !pendingVoiceDraftIsFinalizing && voiceFinalizeTask == nil
            && !recordingVoiceNote && audioRecorder == nil && recordingVoiceNoteURL == nil
            && voiceRecordingDraftTask == nil && voiceRecordingTrimTask == nil
            && !voiceRecordingTrimIsUpdating && !hasPendingVoiceNote && !hasPendingVideoNote
            && pendingVoiceNote == nil && activeVoiceRecordingDraft == nil && pendingVideoNote == nil
            && !retryingVideoNote && videoRetryTask == nil && submittingVideoDraftIDs.isEmpty
            && restoredVideoRecordingDraft == nil
    }

    /// Options belong to the link they were chosen for; a draft's options wait for its link's preview.
    private var currentLinkPreviewOptions: TDNativeLinkPreviewOptions? {
        guard let options = composerLinkPreviewOptions else { return nil }
        if let preview = composerLinkPreview, !options.url.isEmpty, options.url != preview.url { return nil }
        return options
    }

    private var currentEditLinkPreviewOptions: TDNativeLinkPreviewOptions? {
        guard let options = editLinkPreviewOptions else { return nil }
        if let preview = editLinkPreview, !options.url.isEmpty, options.url != preview.url { return nil }
        return options
    }

    /// A group's commands name their bot ("/command@bot"), as ChatControllerLoadDisplayNode's sendBotCommand does.
    private var sendsCommandsToGroup: Bool {
        switch customChat.type {
        case .bot,
             .user: false
        case .group,
             .supergroup: true
        }
    }

    convenience init(
        customChat: CustomChat,
        location: ChatLocation? = nil,
        forumTopic: ForumTopic? = nil,
        messageThread: MessageThreadInfo? = nil,
        previewing: Bool = false,
        client: TDLibClient? = nil,
    ) {
        self.init(
            customChat: customChat, location: location, forumTopic: forumTopic, messageThread: messageThread,
            previewing: previewing, restoration: nil, history: nil, visibleMessageIDs: [], client: client ?? td,
        )
    }

    deinit {
        deliveryReadTask?.cancel()
        log("deinit \(chatID)")
        loadingMessagesTask?.cancel()
        messageRefreshTask?.cancel()
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
        composerMediaDraftTask?.cancel()
        pinMutationTasks.values.forEach { $0.cancel() }
        voiceRecordingPreviewPlayer.stop()
        chatInfoTask?.cancel()
        timer?.invalidate()
        recordingActionRefreshTask?.cancel()
        audioRecorder?.stop()
        MainActor.assumeIsolated {
            RecordingIdleTimer.release(self)
            allMessagesTopicReads?.retire()
            voiceBackgroundCheckpoint.finish()
            messageRefresh?.cancel()
            composerRestorationLifetime.finish {
                if audioRecorder != nil {
                    Media.shared.endAudioSessionRecord()
                }
                if voiceRecordingPreviewOwnsAudioSession {
                    Media.shared.endAudioSessionRecord()
                }
                if let recordingVoiceNoteURL {
                    try? FileManager.default.removeItem(at: recordingVoiceNoteURL)
                }
                let outgoingDocumentURLs = Set(outgoingDocumentURLsByMessageID.values.map(\.standardizedFileURL))
                SelectedDocumentFileStore.removeUnleased(displayedDocuments.map(\.url).filter {
                    !outgoingDocumentURLs.contains($0.standardizedFileURL)
                })
                // A sent item's files are leased to its message, so only the composer's own copies go.
                SelectedDocumentFileStore.removeUnleased(displayedImages.flatMap(\.fileURLs))
                if !previewing { Media.shared.onChatDismiss() }
            }
        }
        chatOpenLease.invalidate()
    }

    private init(
        customChat: CustomChat,
        location: ChatLocation?,
        forumTopic: ForumTopic?,
        messageThread: MessageThreadInfo?,
        previewing: Bool,
        restoration: ChatComposerRestorationState?,
        history: ChatHistoryRestorationState?,
        visibleMessageIDs: [Int64],
        client: TDLibClient,
    ) {
        let resolvedLocation = location ?? ChatLocation.current(
            chatID: customChat.id,
            client: client,
        )
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
        self.forumTopic = forumTopic
        self.forumTopicInfo = forumTopic?.info
        self.canAddReactions = customChat.chat.permissions.canReactToMessages
        self.maximumChosenReactionCount =
            customChat.chat.availableReactions.maximumChosenReactionCount
        if UIApplication.shared.applicationState == .background {
            _ = voiceRecordingLifecycle.suspend(.background)
        }
        self.memberCount = customChat.group?.memberCount ?? customChat.supergroup?.memberCount ?? 0
        if let messageThread, messageThread.chatId == resolvedLocation.chatID,
           messageThread.messageThreadId == resolvedLocation.messageThreadID
        {
            self.messageThread = messageThread
            self.messageThreadReplyInfo = messageThread.replyInfo
            // The route's thread read is fresh: it seeds the thread's receipt like the read below would.
            if usesThreadDeliveryReceipts,
               let read = deliveryReceipts.beginRead(
                   source: TDLib.shared.activeUpdateSource,
                   location: resolvedLocation,
               )
            {
                deliveryReceipts.finishThreadRead(
                    read, thread: messageThread, source: TDLib.shared.activeUpdateSource, location: resolvedLocation,
                )
            }
        }
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            updateOnlineStatus(from: user.status)
        }

        // Install local intent before any publisher, server draft, or async load
        // can fill the new composer. Only the one-shot factory can pass this seed.
        if let restoration {
            seedComposerRestoration(restoration)
        }
        if let history {
            self.messages = history.makeMessages()
            self.oldestHistoryMessageID = history.oldestHistoryMessageID
            self.hasMoreMessages = history.hasMoreMessages
            self.historyReachedStart = !history.hasMoreMessages
            self.latestRestorationCursor = ChatHistoryLatestRefreshCursor(seed: history)
            self.restorationWaitsForViewport = true
        }
        configureMessageRefresh(seedIDs: history?.sourceMessageIDs ?? [], visibleIDs: visibleMessageIDs)

        setPublishers()
        if supportsReplyKeyboard {
            bindReplyKeyboard()
        }
        loadDeliveryReceiptIfNeeded()
        refreshAllMessagesForumTopicsIfNeeded()
        refreshDeliveryStates()
        observeVoiceRecordingPreviewPlayer()
        observeVoiceRecordingInterruptions()
        loadGroupInfo()
        if resolvedLocation.messageThreadID != nil, self.messageThread == nil {
            loadMessageThread()
        }
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
            } else if resolvedLocation.messageThreadID != nil {
                canWriteBasicMessages ? self.messageThread?.draftMessage : nil
            } else if resolvedLocation.isTopicScoped {
                canWriteBasicMessages ? forumTopic?.draftMessage : nil
            } else {
                customChat.draftMessage
            }
        applyAuthoritativeDraft(routeDraftMessage, expectedRevision: composerRevision)
        restoreStoredForwardIfNeeded()
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
                    self.voiceNoteErrorMessage = L10n.betterTG("Voice.SendInterrupted")
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
                    self.videoNoteErrorMessage = L10n.betterTG("VideoNote.SendInterrupted")
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

    /// The panel a group or channel shows where the user can't write: Delete and Exit once they left or were removed,
    /// the restriction for a member of an ordinary group, else the subscriber panel.
    static func statusPanel(
        for type: CustomChat.CustomChatType,
        canWrite: Bool,
        isJoining: Bool,
        isMuted: Bool,
    ) -> StatusPanel? {
        switch type {
        case .bot,
             .user:
            return nil
        case .group(let group):
            guard group.status.isChatMember else { return .deleteChat }
            return canWrite ? nil : .restricted(restrictionText(status: group.status))
        case .supergroup(let supergroup):
            guard !supergroup.isDirectMessagesGroup else { return nil }
            if case .chatMemberStatusBanned = supergroup.status { return .deleteChat }
            guard !canWrite else { return nil }
            if !supergroup.isChannel, !supergroup.isBroadcastGroup, supergroup.status.isChatMember {
                return .restricted(restrictionText(status: supergroup.status))
            }
            return subscriberPanelAction(for: supergroup, isJoining: isJoining, isMuted: isMuted)
                .map { .subscriber($0) }
        }
    }

    /// ChatRestrictedInputPanelNode's text from `hasBannedPermission(.banSendText)`: the member's own restriction,
    /// with its end date unless it is forever, else the group's.
    static func restrictionText(status: ChatMemberStatus) -> String {
        guard case .chatMemberStatusRestricted(let restricted) = status,
              !restricted.permissions.canSendBasicMessages
        else {
            return L10n.telegram("Conversation.DefaultRestrictedText")
        }
        let until = restricted.restrictedUntilDate
        guard until != 0, until != Int(Int32.max) else { return L10n.telegram("Conversation.RestrictedText") }
        return L10n.telegram(
            "Conversation.RestrictedTextTimed",
            fullDateString(Date(timeIntervalSince1970: TimeInterval(until))),
        )
    }

    /// Telegram's stringForFullDate: "Time.PreciseDate_m<month>" with the day, year and short time.
    static func fullDateString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .month, .year], from: date)
        let time = date.formatted(date: .omitted, time: .shortened)
        guard let day = components.day, let month = components.month, let year = components.year else { return time }
        return L10n.telegram("Time.PreciseDate_m\(month)", "\(day)", "\(year)", time)
    }

    /// `actionForPeer` for a supergroup the user can't write to: a channel offers Join until joined (or while joining),
    /// then Mute or Unmute; a group the user isn't in offers Apply to Join, Join for a forum, or Join Group; a
    /// broadcast
    /// group's member gets Mute or Unmute.
    static func subscriberPanelAction(
        for supergroup: Supergroup,
        isJoining: Bool,
        isMuted: Bool,
    ) -> SubscriberPanelAction? {
        guard !supergroup.isDirectMessagesGroup else { return nil }
        if case .chatMemberStatusBanned = supergroup.status { return nil }
        let isMember = supergroup.status.isChatMember
        if supergroup.isChannel {
            guard isMember || isJoining else { return .join }
        } else if !isMember {
            if supergroup.joinByRequest { return .applyToJoin }
            return supergroup.isForum ? .join : .joinGroup
        } else if !supergroup.isBroadcastGroup {
            return nil
        }
        return isMuted ? .unmute : .mute
    }

    /// The send-button menu's choice as TDLib send options.
    static func sendOptions(
        silent: Bool = false,
        schedulingState: TDNativeMessageSchedulingState? = nil,
    ) -> TDNativeMessageSendOptions {
        TDNativeMessageSendOptions(
            suggestedPostInfo: nil,
            disableNotification: silent,
            fromBackground: false,
            protectContent: false,
            allowPaidBroadcast: false,
            paidMessageStarCount: 0,
            updateOrderOfInstalledStickerSets: false,
            schedulingState: schedulingState,
            effectId: 0,
            sendingId: 0,
            onlyPreview: false,
        )
    }

    static func restoringComposer(
        from transfer: ChatComposerRestorationTransfer,
        customChat: CustomChat,
        location: ChatLocation,
        forumTopic: ForumTopic? = nil,
        history: ChatHistoryRestorationState? = nil,
        visibleMessageIDs: [Int64] = [],
        client: TDLibClient? = nil,
    ) -> ChatVM? {
        let client = client ?? td
        guard location.chatID == customChat.id, location.clientID == client.id,
              history.map({ $0.location.accountID == location.accountID
                      && $0.location.chatID == location.chatID && $0.location.topic == location.topic }) ?? true
        else { return nil }
        return transfer.commit(to: location, currentSource: TDLib.shared.activeUpdateSource) { snapshot in
            ChatVM(
                customChat: customChat, location: location, forumTopic: forumTopic, messageThread: nil,
                previewing: false, restoration: snapshot, history: history,
                visibleMessageIDs: visibleMessageIDs, client: client,
            )
        }
    }

    /// Telegram's group subtitle: "N members", plus ", M online" once more than one member is online.
    static func memberStatus(memberCount: Int, onlineMemberCount: Int) -> String {
        let members = countStatus("Conversation.StatusMembers", count: memberCount)
        guard onlineMemberCount > 1 else { return members }
        return "\(members), \(countStatus("Conversation.StatusOnline", count: onlineMemberCount))"
    }

    static func countStatus(_ key: String, count: Int) -> String {
        L10n.telegramPlural(key, count: count, formattedCount: count.formatted(.number))
    }

    /// A caption edit keeps the caption on the side of the media it was sent on.
    private static func showsCaptionAboveMedia(_ content: MessageContent) -> Bool {
        switch content {
        case .messageAnimation(let value): value.showCaptionAboveMedia
        case .messagePhoto(let value): value.showCaptionAboveMedia
        case .messageVideo(let value): value.showCaptionAboveMedia
        default: false
        }
    }

    /// The inline bot behind a username (`searchPublicChat`) with its query placeholder; nil for anything else.
    private static func inlineBot(
        username: String,
        client: TDLibClient,
    ) async -> (id: Int64, placeholder: String, needsLocation: Bool)? {
        guard let chat = try? await client.send(TDNativeRequests.searchPublicChat(username: username)),
              case .chatTypePrivate(let privateChat) = chat.type,
              let user = try? await client.getUser(userId: privateChat.userId),
              case .userTypeBot(let bot) = user.type, bot.isInline
        else { return nil }
        return (user.id, bot.inlineQueryPlaceholder, bot.needLocation)
    }

    /// MediaPickerScreen's Send as File: the picked photo, or the original video with its first frame as the
    /// thumbnail, sent as a document without TDLib's type detection.
    private static func makeInputMessageFile(_ image: SelectedImage, caption: FormattedText) -> InputMessageContent {
        let file = image.video?.url ?? image.url
        let thumbnail = image.video.map { video in
            TDNativeInputThumbnail(
                thumbnail: .inputFileLocal(InputFileLocal(path: image.url.path(percentEncoded: false))),
                width: Int(video.thumbnailSize.width),
                height: Int(video.thumbnailSize.height),
            )
        }
        return .inputMessageDocument(TDNativeInputMessageDocument(
            document: TDNativeInputDocument(
                document: .inputFileLocal(InputFileLocal(path: file.path(percentEncoded: false))),
                thumbnail: thumbnail,
                disableContentTypeDetection: true,
            ),
            caption: caption.text.isEmpty ? nil : caption,
        ))
    }

    /// The coordinate an inline query carries (`getInlineQueryResults`' userLocation).
    private static func tdLocation(_ coordinate: (latitude: Double, longitude: Double)?) -> TDNativeLocation? {
        coordinate.map { TDNativeLocation(latitude: $0.latitude, longitude: $0.longitude, horizontalAccuracy: 0) }
    }

    /// A muted video goes as a GIF (`LegacyMediaPickers` adds `.Animated` for `sendAsGif`). TDLib's animations
    /// can't self-destruct, so a video with a timer stays a video, and TDLib takes an animation's MIME type from the
    /// original's extension, which `PhotoAssetSelectionLoader` makes `mp4` for a GIF.
    private nonisolated static func sendsAsAnimation(_ image: SelectedImage) -> Bool {
        guard let video = image.video, video.sendsAsGIF, image.selfDestructTimer == nil else { return false }
        return video.url.pathExtension.lowercased() == "mp4"
    }

    /// `updateChatNotificationSettings` for this chat.
    func updateChatNotificationSettings(_ settings: ChatNotificationSettings) {
        chatNotificationSettings = settings
    }

    /// TelegramEngine.togglePeerMuted: a muted chat is unmuted, any other is muted forever; the panel turns at once and
    /// turns back if TDLib refuses.
    func toggleSubscriberMute() {
        guard locationContextIsCurrent else { return }
        let previous = chatNotificationSettings ?? customChat.chat.notificationSettings
        let updated = previous.replacingMuteFor(isNotificationMuted ? 0 : Int(Int32.max))
        chatNotificationSettings = updated
        let client = client
        let chatID = chatID
        Task { [weak self] in
            do {
                _ = try await client.setChatNotificationSettings(chatId: chatID, notificationSettings: updated)
            } catch {
                guard let self, locationContextIsCurrent, chatNotificationSettings == updated else { return }
                chatNotificationSettings = previous
            }
        }
    }

    /// ChatChannelSubscriberInputPanelNode's join: `joinChat`, with the channel showing Mute meanwhile.
    func joinSubscribedChat() async throws -> TDNativeChatJoinResult? {
        guard locationContextIsCurrent, !isJoiningChat else { return nil }
        isJoiningChat = true
        defer { isJoiningChat = false }
        return try await client.send(TDNativeRequests.joinChat(chatId: chatID))
    }

    /// ChatController.unblockPeer: `setMessageSenderBlockList` without a list, the panel dimmed until TDLib answers;
    /// `updateChatBlockList` then brings the composer.
    func unblockChat() {
        guard locationContextIsCurrent, !isUnblockingChat, let userID = customChat.user?.id else { return }
        isUnblockingChat = true
        let client = client
        Task { [weak self] in
            _ = try? await client.send(TDNativeRequests.setMessageSenderBlockList(
                senderId: .messageSenderUser(MessageSenderUser(userId: userID)),
                blockList: nil,
            ))
            self?.isUnblockingChat = false
        }
    }

    /// ChatController.deleteChat's removePeerChat for a group the user left or a chat they were removed from, as the
    /// chat list's Delete does: a basic group's history goes with the chat from the lists, a supergroup is left.
    /// Telegram's accompanying block of the peer is left out.
    func removeChatFromList() {
        guard locationContextIsCurrent else { return }
        let client = client
        let chatID = chatID
        let isBasicGroup = customChat.group != nil
        Task {
            _ =
                if isBasicGroup {
                    try? await client.deleteChatHistory(chatId: chatID, removeFromChatList: true, revoke: false)
                } else {
                    try? await client.send(TDNativeRequests.leaveChat(chatId: chatID))
                }
        }
    }

    /// An album this chat is still announcing: show it once every member arrived, or a moment after the send call.
    func holdsIncompleteOutgoingAlbum(_ message: CustomMessage) -> Bool {
        guard let outgoingAlbumHold, message.message.mediaAlbumId != 0, message.message.isOutgoing else {
            return false
        }
        let members = message.sourceMessages
        return members.count < outgoingAlbumHold.count && members.allSatisfy {
            if case .messageSendingStatePending = $0.sendingState {
                true
            } else {
                false
            }
        }
    }

    /// A message the composer send in flight created; it appears together with the cleared composer.
    func holdsComposerSendMessage(_ message: CustomMessage) -> Bool {
        guard let composerSendHold, message.message.isOutgoing else { return false }
        return message.sourceMessages.allSatisfy {
            guard case .messageSendingStatePending = $0.sendingState else { return false }
            if let sentMessageIDs = composerSendHold.sentMessageIDs { return sentMessageIDs.contains($0.id) }
            return !composerSendHold.earlierMessageIDs.contains($0.id)
        }
    }

    /// Chat-level pins cover messages outside topics. Saved Messages also tags every message with its
    /// saved-messages sublist, and Telegram pins there for the user, so that topic does not block a pin. A forum
    /// topic pins its own messages, and a forum read as messages pins any topic's.
    func acceptsChatLevelPin(_ message: Message) -> Bool {
        guard let topic = message.topicId else { return true }
        switch topic {
        case .messageTopicSavedMessages:
            return customChat.isSavedMessages
        case .messageTopicForum(let forumTopic):
            if let id = location.forumTopicID { return forumTopic.forumTopicId == id }
            return isAllMessagesForum
        case .messageTopicDirectMessages,
             .messageTopicThread:
            return false
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
                permitsFinalStatus: (usesOrdinaryDeliveryReceipts || usesForumDeliveryReceipts
                    || usesThreadDeliveryReceipts) && current
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
        if location.messageThreadID != nil {
            if usesThreadDeliveryReceipts, locationContextIsCurrent, deliveryReceipts.lastReadOutbox == nil {
                loadMessageThread()
            }
            return
        }
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
        // The seed has no gap list: keep only the contiguous history above the newest gap and page on from there.
        if let gap = historyGaps.first {
            return ChatHistoryRestorationState(
                location: location,
                messages: messages.filter { row in row.sourceMessages.allSatisfy { $0.id >= gap.newerBoundID } }
                    .map(ChatHistoryMessageValue.init),
                oldestHistoryMessageID: gap.newerBoundID, hasMoreMessages: true,
            )
        }
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
            if previous.message.content.constructorID == message.content.constructorID {
                display.serviceText = previous.serviceText
            }
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
        if location.messageThreadID != nil, messageThread == nil { loadMessageThread() }
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
                destinationTopic = .messageTopicForum(MessageTopicForum(forumTopicId: general.info.forumTopicId))
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
               reply.message.topicId != location.topic,
               !(customChat.isSavedMessages && location.topic == nil
                   && reply.message.topicId.map { if case .messageTopicSavedMessages = $0 { return true }
                       return false
                   } == true)
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
            allowsSavedMessagesTopic: customChat.isSavedMessages && location.topic == nil,
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

    func updateOnlineStatus(from userStatus: UserStatus) {
        isUserOnline =
            if case .userStatusOnline = userStatus {
                true
            } else {
                false
            }
        userLastSeenIsKnown =
            if case .userStatusOffline = userStatus {
                true
            } else {
                false
            }
        onlineStatus = getOnlineStatus(from: userStatus)
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
        let client = client
        switch customChat.type {
        case .supergroup(let group):
            chatInfoTask = Task { [weak self] in
                guard let info = try? await client.getSupergroupFullInfo(supergroupId: group.id),
                      !Task.isCancelled,
                      let self,
                      locationContextIsCurrent
                else { return }
                updateSlowMode(expiresIn: info.slowModeDelayExpiresIn)
                if info.memberCount > 0 { memberCount = info.memberCount }
            }
        case .group(let group) where group.memberCount == 0:
            chatInfoTask = Task { [weak self] in
                guard let info = try? await client.getBasicGroupFullInfo(basicGroupId: group.id),
                      !Task.isCancelled,
                      let self,
                      locationContextIsCurrent
                else { return }
                memberCount = info.members.count
            }
        case .user(let user):
            let secretChatID = customChat.secretChatID
            chatInfoTask = Task { [weak self] in
                if let secretChatID,
                   let secret = try? await client.send(TDNativeRequests.getSecretChat(secretChatId: secretChatID))
                {
                    guard !Task.isCancelled, let self, locationContextIsCurrent else { return }
                    updateSecretChatState(secret.state)
                }
                guard let info = try? await client.getUserFullInfo(userId: user.id),
                      !Task.isCancelled, let self, locationContextIsCurrent else { return }
                updateRecipientNoteRestriction(info.hasRestrictedVoiceAndVideoNoteMessages)
            }
        case .bot,
             .group:
            break
        }
        loadBotInfo()
    }

    func updateSlowMode(expiresIn seconds: Double) {
        slowModeExpiresAt = seconds > 0 ? Date().addingTimeInterval(seconds) : nil
    }

    /// Telegram's secret chat accepts messages only once the other side has joined, and none once it is closed.
    func updateSecretChatState(_ state: TDNativeSecretChatState) {
        let ready =
            if case .secretChatStateReady = state {
                true
            } else {
                false
            }
        guard secretChatIsReady != ready else { return }
        secretChatIsReady = ready
        objectWillChange.send()
    }

    func updateRecipientNoteRestriction(_ restricted: Bool) {
        guard recipientRestrictsVoiceAndVideoNotes != restricted else { return }
        recipientRestrictsVoiceAndVideoNotes = restricted
        objectWillChange.send()
    }

    /// Telegram keeps the input during slow mode and explains the wait when the user sends
    /// (`Chat.SlowmodeTooltip`). Nil when a message may go out now.
    func slowModeWaitMessage() -> String? {
        guard let slowModeExpiresAt else { return nil }
        let remaining = Int(ceil(slowModeExpiresAt.timeIntervalSinceNow))
        guard remaining > 0 else {
            self.slowModeExpiresAt = nil
            return nil
        }
        let time = String(format: "%d:%02d", remaining / 60, remaining % 60)
        return L10n.telegram("Chat.SlowmodeTooltip", time).replacing("\n", with: " ")
    }

    func loadMessages() {
        guard !restorationWaitsForViewport, latestRestorationCursor == nil,
              loadingMessagesTask == nil, hasMoreMessages else { return }
        let fromMessageID = oldestHistoryMessageID ?? messages.last?.oldestSourceMessageID ?? 0
        loadingMessagesTask = Task { [weak self] in
            await self?._loadMessages(fromMessageID: fromMessageID)
        }
    }

    func _loadMessages(fromMessageID: Int64) async {
        guard !Task.isCancelled, locationContextIsCurrent else {
            loadingMessagesTask = nil
            return
        }
        // The thread's root heads its history, so a thread page waits for the thread's read.
        if location.messageThreadID != nil, messageThread == nil {
            _ = await loadMessageThread()?.value
            guard !Task.isCancelled, locationContextIsCurrent else {
                loadingMessagesTask = nil
                return
            }
        }
        let readToken = messageRefresh?.beginRead()
        // TDLib may return a short page while it fills its local cache. Keep reading until a
        // full page arrives, the history ends, or two reads in a row make no progress.
        var knownIDs = Set(messages.flatMap { $0.sourceMessages.map(\.id) })
        var cursor = fromMessageID
        var history = [Message]()
        var noProgressCount = 0
        var reachedEnd = false
        while history.count < Self.historyPageSize, noProgressCount < 2, !Task.isCancelled {
            let remaining = Self.historyPageSize - history.count
            guard let fetched = await loadHistory(
                fromMessageId: cursor,
                limit: min(100, remaining + (cursor == 0 ? 0 : 1)),
                offset: 0,
            ), !Task.isCancelled, locationContextIsCurrent else {
                loadingMessagesTask = nil
                return
            }
            guard !fetched.isEmpty else {
                reachedEnd = true
                break
            }
            let previousCount = history.count
            var nextCursor = cursor
            for message in fetched {
                nextCursor = message.id
                if knownIDs.insert(message.id).inserted {
                    history.append(message)
                    if history.count == Self.historyPageSize { break }
                }
            }
            if history.count == previousCount || nextCursor == cursor {
                noProgressCount += 1
                await Task.yield()
            } else {
                noProgressCount = 0
            }
            cursor = nextCursor
        }
        guard !Task.isCancelled, locationContextIsCurrent else {
            loadingMessagesTask = nil
            return
        }
        // `getMessageThreadHistory` lists the replies only; Telegram adds the thread's root once the history reaches
        // its start (ChatHistoryEntriesForView, `addedThreadHead`).
        if location.messageThreadID != nil, reachedEnd || noProgressCount >= 2 {
            history.append(contentsOf: messageThreadHead(excluding: knownIDs))
        }
        let customMessages = await history.filter { routeIncludes($0) }.asyncMap { chatMessage in
            await getCustomMessage(from: chatMessage)
        }
        guard !Task.isCancelled, locationContextIsCurrent else {
            loadingMessagesTask = nil
            return
        }
        let current = readToken.map {
            messageRefresh?
                .takeCurrentValues(customMessages.map(ChatHistoryMessageValue.init), token: $0)
                .map { $0.makeMessage() } ?? []
        } ?? customMessages
        messages = canonicalMessages(
            merging: messages,
            with: current,
            replacingExisting: true,
        )
        oldestHistoryMessageID = cursor
        hasMoreMessages = !reachedEnd && noProgressCount < 2 && cursor != fromMessageID
        historyLoadedEmpty = !hasMoreMessages && messages.isEmpty
        loadingMessagesTask = nil
        driveMessageRefresh()
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
        let rawNewestMessageID = history.first?.id
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
            rawOldestMessageID: rawOldestMessageID, rawNewestMessageID: rawNewestMessageID, readToken: readToken,
        )
    }

    func applyMessageWindow(_ window: PreparedMessageWindow) {
        guard !Task.isCancelled, locationContextIsCurrent else { return }
        let current = window.readToken.map {
            messageRefresh?.takeCurrentValues(window.messages.map(ChatHistoryMessageValue.init), token: $0)
                .map { $0.makeMessage() } ?? []
        } ?? window.messages
        let windowIDs = current.flatMap { $0.sourceMessages.map(\.id) }
            + [window.rawOldestMessageID, window.rawNewestMessageID].compactMap(\.self)
        if let windowOldest = windowIDs.min(), let windowNewest = windowIDs.max() {
            recordHistoryWindow(oldest: windowOldest, newest: windowNewest)
        }
        messages = canonicalMessages(merging: messages, with: current, replacingExisting: true)
        if let oldest = window.rawOldestMessageID, oldestHistoryMessageID.map({ oldest < $0 }) ?? true {
            oldestHistoryMessageID = oldest
        }
        driveMessageRefresh()
    }

    /// The window at the chat's newest message when the loaded rows don't include it, as Telegram's scroll to the end
    /// of history reloads at the upper bound. Nil when the newest message is already loaded.
    func prepareLatestMessageWindow() async -> (window: PreparedMessageWindow, messageID: Int64)? {
        guard locationContextIsCurrent,
              let newest = await loadHistory(fromMessageId: 0, limit: 1, offset: 0)?
                .first(where: { location.matches(message: $0) }),
              !Task.isCancelled, locationContextIsCurrent, displayedMessageID(containing: newest.id) == nil,
              let window = await prepareMessageWindow(around: newest.id)
        else { return nil }
        return (window, newest.id)
    }

    /// Loads a gap once the rows next to it come within reach, from the side the user is looking at, as Telegram's
    /// history view loads the next page in the scroll direction.
    func loadHistoryGaps(near visibleIDs: Set<DisplayedMessageID>) {
        guard historyGapTask == nil, !historyGaps.isEmpty, !restorationWaitsForViewport, locationContextIsCurrent
        else { return }
        let visibleIndices = messages.indices.filter { visibleIDs.contains(messages[$0].displayedID) }
        guard !visibleIndices.isEmpty else { return }
        let reach = 12
        for gap in historyGaps {
            // `messages` is newest first: the gap sits between the last row reaching its newer bound and the next one.
            guard let newerIndex = messages.lastIndex(where: { row in
                row.sourceMessages.contains { $0.id >= gap.newerBoundID }
            }) else { continue }
            let olderIndex = newerIndex + 1
            let newerDistance = visibleIndices.map { abs($0 - newerIndex) }.min() ?? .max
            let olderDistance = olderIndex < messages.count
                ? visibleIndices.map { abs($0 - olderIndex) }.min() ?? .max
                : Int.max
            guard min(newerDistance, olderDistance) <= reach else { continue }
            let fillsFromOlderSide = olderDistance < newerDistance
            historyGapTask = Task { [weak self] in
                await self?.loadHistoryGap(gap, fromOlderSide: fillsFromOlderSide)
            }
            return
        }
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

    /// The failed items of a row that TDLib can send again. Voice and video notes the composer still owns keep their
    /// own retry there.
    func resendableMessageIDs(in message: CustomMessage) -> [Int64] {
        guard !isReadOnlyTopic, locationContextIsCurrent else { return [] }
        let composerOwnedIDs = Set([
            pendingVoiceNote?.failedSendState?.messageID, pendingVideoNote?.failedSendState?.messageID,
        ].compactMap(\.self))
        return (message.album.isEmpty ? [message.message] : message.album).compactMap { source in
            guard case .messageSendingStateFailed(let state) = source.sendingState, state.canRetry,
                  !composerOwnedIDs.contains(source.id) else { return nil }
            return source.id
        }
    }

    /// Telegram's failed-message menu: Resend for the row, and Resend All for every failed row
    /// (`requestRedeliveryOfFailedMessages`). An album is one row.
    func resendableMessageGroups() -> [[Int64]] {
        messages.map(resendableMessageIDs(in:)).filter { !$0.isEmpty }
    }

    func resendMessages(ids: [Int64]) {
        guard !isReadOnlyTopic, locationContextIsCurrent, !ids.isEmpty else { return }
        let client = client
        let chatID = chatID
        let accountID = accountID
        let messageIDs = ids.sorted()
        // TDLib deletes each failed message as it resends it. The message's files wait under a hold until the new
        // messages exist, so that deletion does not release a file the resend uploads.
        let holdIDs = messageIDs.map { _ in -Int64.random(in: 1...Int64.max) }
        for (messageID, holdID) in zip(messageIDs, holdIDs) {
            try? SelectedDocumentFileStore.replaceMessageID(
                accountID: accountID, chatID: chatID, old: messageID, new: holdID,
            )
        }
        // TDLib replaces each failed message with a new pending one through its usual updates.
        Task { [weak self] in
            do {
                let resent = try await client.resendMessages(
                    chatId: chatID, messageIds: messageIDs, paidMessageStarCount: 0, quote: nil,
                )
                // TDLib answers null for a message it could not resend, which the native list drops. Only a full
                // answer pairs holds with messages; otherwise the files stay held until the stale-lease cleanup.
                if resent.messages.count == messageIDs.count {
                    for (holdID, message) in zip(holdIDs, resent.messages) {
                        try? SelectedDocumentFileStore.replaceMessageID(
                            accountID: accountID, chatID: chatID, old: holdID, new: message.id,
                        )
                    }
                }
            } catch {
                for (messageID, holdID) in zip(messageIDs, holdIDs) {
                    try? SelectedDocumentFileStore.replaceMessageID(
                        accountID: accountID, chatID: chatID, old: holdID, new: messageID,
                    )
                }
                guard let self, locationContextIsCurrent else { return }
                sendErrorMessage = error.localizedDescription
            }
        }
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
        // A thread's messages are read in the thread (`messages.readDiscussion`) and a forum topic's in the topic
        // (`ReadForumTopicQuery`); without the source TDLib reads the whole chat inbox up to them, which marks
        // older unread messages of other topics as read.
        let source: MessageSource? =
            if location.forumTopicID != nil {
                .messageSourceForumTopicHistory
            } else if location.messageThreadID != nil {
                .messageSourceMessageThreadHistory
            } else {
                nil
            }
        Task {
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            _ = try? await client.viewMessages(
                chatId: chatID,
                forceRead: true,
                messageIds: ids,
                source: source,
            )
        }
    }

    func readAllReactions() {
        // TDLib reads reactions per chat or forum topic only; a thread must not clear the whole discussion group.
        guard location.messageThreadID == nil else { return }
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

    func submitPollAnswer(
        messageID: Int64,
        optionIDs: [Int],
        submission: MessagePollInteractionStore.Submission,
        onAnswered: @escaping @MainActor (PollAnswerOutcome) -> Void = { _ in },
    ) {
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
        let chatID = chatID
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
                guard !optionIDs.isEmpty,
                      let answered = try? await client.getMessage(chatId: chatID, messageId: messageID),
                      case .messagePoll(let content) = answered.content,
                      locationContextIsCurrent
                else { return }
                let poll = content.poll
                var quizAnswerIsRight: Bool?
                var hasExplanation = false
                if case .pollTypeQuiz(let quiz) = poll.type, !quiz.correctOptionIds.isEmpty {
                    let chosen = Set(poll.options.indices.filter { poll.options[$0].isChosen })
                    quizAnswerIsRight = chosen == Set(quiz.correctOptionIds)
                    hasExplanation = !quiz.explanation.text.isEmpty
                }
                onAnswered(PollAnswerOutcome(
                    quizAnswerIsRight: quizAnswerIsRight,
                    hasExplanation: hasExplanation,
                    resultsHidden: !poll.canSeeResults,
                ))
            } catch {
                // Telegram rolls the choice back on a failed vote (requestSelectMessagePollOptions). A submission
                // that already timed out or was replaced stays silent.
                guard pollInteractionStore.failSubmission(submission) else { return }
                log("Couldn't submit poll answer for \(messageID): \(error.localizedDescription)")
                guard locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else { return }
                messageActionErrorMessage = (error as? TDLibError)?.message ?? error.localizedDescription
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
                    let isPremium = try await client.getMe().isPremium
                    guard available.contextReactionTypes(isPremium: isPremium).contains(type) else {
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
                        L10n.betterTG("Error.AccountChanged")
                    case .unavailable:
                        L10n.betterTG("Chat.ReactionUnavailable")
                    case nil:
                        wasChosen
                            ? L10n.betterTG("Chat.ReactionRemoveFailed")
                            : L10n.betterTG("Chat.ReactionAddFailed")
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

    /// Reads the thread route's `MessageThreadInfo` on this chat's client; concurrent callers share one read. A
    /// thread already read is read again only for a missing receipt watermark.
    @discardableResult func loadMessageThread() -> Task<MessageThreadInfo?, Never>? {
        guard let threadID = location.messageThreadID else { return nil }
        if let messageThreadTask { return messageThreadTask }
        let needsReceipt = usesThreadDeliveryReceipts && deliveryReceipts.lastReadOutbox == nil
        guard messageThread == nil || needsReceipt, locationContextIsCurrent else { return nil }
        let receiptRead = needsReceipt
            ? deliveryReceipts.beginRead(source: TDLib.shared.activeUpdateSource, location: location)
            : nil
        let client = client
        let location = location
        let expectedComposerRevision = composerRevision
        let expectedReplyInfoRevision = messageThreadReplyInfoRevision
        let task = Task<MessageThreadInfo?, Never> { [weak self] in
            let info = try? await client.getMessageThread(chatId: location.chatID, messageId: threadID)
            guard let self else { return nil }
            messageThreadTask = nil
            let accepted = info.flatMap { $0.chatId == location.chatID && $0.messageThreadId == threadID ? $0 : nil }
            if let receiptRead, deliveryReceipts.finishThreadRead(
                receiptRead, thread: accepted, source: TDLib.shared.activeUpdateSource, location: location,
            ) {
                refreshDeliveryStates()
            }
            guard !Task.isCancelled, locationContextIsCurrent, let info = accepted else { return nil }
            let isFirstRead = messageThread == nil
            messageThread = info
            // A root update that arrived during the read is newer than the read's reply info.
            if messageThreadReplyInfoRevision == expectedReplyInfoRevision {
                messageThreadReplyInfo = info.replyInfo
            }
            guard isFirstRead else { return info }
            if canWriteBasicMessages {
                applyAuthoritativeDraft(info.draftMessage, expectedRevision: expectedComposerRevision)
            }
            // Rows built before the read kept their reply to the post; fence their in-flight reads and drop it.
            let rootReplies = messages.filter {
                $0.replyPresentation != nil && self.hidesReplyToThreadRoot($0.message)
            }
            notePartialMessageUpdate(rootReplies.map(\.id))
            rootReplies.forEach { $0.replyPresentation = nil }
            insertMessageThreadHeadIfNeeded()
            return info
        }
        messageThreadTask = task
        return task
    }

    /// TDLib republishes the thread root's reply info as replies arrive and are read.
    func receiveMessageThreadRootInteractionInfo(
        _ info: MessageInteractionInfo?,
        messageID: Int64,
        source: TdUpdateSource?,
    ) {
        guard messageID == location.messageThreadID, locationContextIsCurrent,
              let replyInfo = info?.replyInfo else { return }
        messageThreadReplyInfoRevision &+= 1
        messageThreadReplyInfo = replyInfo
        if usesThreadDeliveryReceipts, deliveryReceipts.receiveThreadRoot(
            replyInfo, chatID: location.chatID, messageID: messageID, source: source, location: location,
        ) {
            refreshDeliveryStates()
        }
    }

    func refreshPinnedMessages() {
        guard supportsPinnedMessages else { return }
        pinnedMessageGeneration &+= 1
        let generation = pinnedMessageGeneration
        pinnedMessageTask?.cancel()
        let client = client
        let accountID = accountID
        // A topic's newest pin comes from its pinned history; TDLib keeps only the chat's newest pin.
        let topic = location.forumTopicID == nil ? nil : location.topic
        pinnedMessageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let message: Message? =
                    if let topic {
                        try await client.searchChatMessages(
                            chatId: chatID,
                            filter: .searchMessagesFilterPinned,
                            fromMessageId: 0,
                            limit: 1,
                            offset: 0,
                            query: "",
                            senderId: nil,
                            topicId: topic,
                        )
                        .messages
                        .first
                    } else {
                        try await client.getChatPinnedMessage(chatId: chatID)
                    }
                guard !Task.isCancelled,
                      pinnedMessageGeneration == generation,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                pinnedMessageAuthoritativeRevision &+= 1
                pinnedMessage = message.flatMap { self.acceptsChatLevelPin($0) ? $0 : nil }
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

    /// Whether fresh TDLib properties let the account unpin this message (Telegram's canManagePin for the panel).
    func canUnpinMessage(id messageID: Int64) async -> Bool {
        guard supportsPinnedMessages,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return false }
        return await (try? client.getMessageProperties(chatId: chatID, messageId: messageID))?.canBePinned == true
    }

    /// Unpins the banner's message when it is outside the loaded history. TDLib's updateMessageIsPinned then
    /// refreshes the banner through applyPinnedMessageUpdate.
    func unpinBannerMessage(id messageID: Int64) {
        guard supportsPinnedMessages, pinMutationTasks.isEmpty,
              TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { return }
        let generation = UUID()
        let client = client
        pinMutationGenerations[messageID] = generation
        pinMutationTasks[messageID] = Task { [weak self] in
            guard let self else { return }
            var failure: Error?
            do {
                let properties = try await client.getMessageProperties(chatId: chatID, messageId: messageID)
                guard properties.canBePinned else { throw PinMutationFailure.unavailable }
                guard pinMutationGenerations[messageID] == generation,
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { throw PinMutationFailure.accountChanged }
                _ = try await client.unpinChatMessage(chatId: chatID, messageId: messageID)
            } catch is CancellationError {
            } catch {
                failure = error
            }
            guard pinMutationGenerations[messageID] == generation else { return }
            pinMutationTasks[messageID] = nil
            pinMutationGenerations[messageID] = nil
            guard TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id else { return }
            if let failure {
                pinErrorMessage =
                    switch failure as? PinMutationFailure {
                    case .accountChanged: L10n.betterTG("Error.AccountChanged")
                    case .unavailable: L10n.betterTG("Chat.PinUnavailable")
                    case nil: L10n.betterTG("Chat.UnpinFailed")
                    }
            }
            refreshPinnedMessages()
        }
    }

    func unpinMessage(_ message: CustomMessage) {
        setMessagePinned(
            message,
            pinned: false,
            disableNotification: true,
            onlyForSelf: false,
        )
    }

    /// Telegram's Stop Poll / Stop Quiz (requestClosePoll). For a poll, TDLib's `canBeEdited` means `stopPoll` can
    /// be used; the closed poll arrives through updateMessageContent.
    func stopPoll(_ message: CustomMessage) {
        guard message.properties.canBeEdited,
              case .messagePoll(let poll) = message.message.content, !poll.poll.isClosed else { return }
        performMessageContentRequest(message) { client, chatID, messageID in
            _ = try await client.stopPoll(chatId: chatID, messageId: messageID, replyMarkup: nil)
        }
    }

    /// Telegram's Retract Vote (ChatInterfaceStateContextMenus): an open, sent poll with a chosen answer that may be
    /// answered again (`revotingDisabled` there, `allowsRevoting` here). TDLib answers a quiz only once.
    func canRetractPollVote(_ message: CustomMessage) -> Bool {
        guard !isReadOnlyTopic, locationContextIsCurrent, location.matches(message: message.message),
              message.message.sendingState == nil, message.message.schedulingState == nil,
              case .messagePoll(let content) = message.message.content,
              pollInteractionStore.currentSubmission(messageID: message.id) == nil
        else { return false }
        let poll = content.poll
        if case .pollTypeQuiz = poll.type { return false }
        return !poll.isClosed && poll.allowsRevoting
            && poll.options.contains(where: \.isChosen)
            && !poll.options.contains(where: \.isBeingChosen)
    }

    /// Retract Vote (requestUnvoteInMessage) is `setPollAnswer` with no options; the cleared poll arrives through
    /// updateMessageContent.
    func retractPollVote(_ message: CustomMessage) {
        guard canRetractPollVote(message) else { return }
        performMessageContentRequest(message) { client, chatID, messageID in
            _ = try await client.setPollAnswer(chatId: chatID, messageId: messageID, optionIds: [])
        }
    }

    /// The answer menu's Vote: an open, sent poll without a pending answer that the user hasn't answered yet or may
    /// answer again (ChatControllerOpenPollContextMenu's `canVote`).
    func canVoteInPoll(_ message: CustomMessage) -> Bool {
        guard !isReadOnlyTopic, locationContextIsCurrent, location.matches(message: message.message),
              message.message.sendingState == nil, message.message.schedulingState == nil,
              case .messagePoll(let content) = message.message.content,
              pollInteractionStore.currentSubmission(messageID: message.id) == nil
        else { return false }
        let poll = content.poll
        let isPastCloseDate = poll.closeDate > 0 && poll.closeDate <= Int(Date().timeIntervalSince1970)
        return !poll.isClosed && !isPastCloseDate && poll.voteRestrictionReason == nil
            && !poll.options.contains(where: \.isBeingChosen)
            && (!poll.options.contains(where: \.isChosen) || poll.allowsRevoting)
    }

    /// The answer menu's Vote and Retract Vote (requestSelectMessagePollOptions): the answer joins the chosen ones
    /// in a multiple-answer poll and replaces them otherwise, or leaves them. The poll arrives through
    /// updateMessageContent.
    func setPollOption(_ message: CustomMessage, index: Int, isChosen: Bool) {
        guard canVoteInPoll(message), case .messagePoll(let content) = message.message.content,
              content.poll.options.indices.contains(index) else { return }
        let poll = content.poll
        var selection = poll.options.indices.filter { poll.options[$0].isChosen }
        if isChosen {
            if !poll.allowsMultipleAnswers { selection = [] }
            if !selection.contains(index) { selection.append(index) }
        } else {
            selection.removeAll { $0 == index }
        }
        let optionIDs = selection.sorted()
        performMessageContentRequest(message) { client, chatID, messageID in
            _ = try await client.setPollAnswer(chatId: chatID, messageId: messageID, optionIds: optionIDs)
        }
    }

    /// The answer menu's Remove: deletePollOption, which TDLib's pollOptionProperties allow. The poll without the
    /// answer arrives through updateMessageContent.
    func deletePollOption(_ message: CustomMessage, optionID: String) {
        guard !optionID.isEmpty else { return }
        performMessageContentRequest(message) { client, chatID, messageID in
            _ = try await client.send(TDNativeRequests.deletePollOption(
                chatId: chatID,
                messageId: messageID,
                optionId: optionID,
            ))
        }
    }

    /// The poll's Add an Option (requestAddMessagePollOption): TDLib's addPollOption with the typed text and the
    /// attached media, whose picked file TDLib uploads with the request. The poll with the answer arrives through
    /// updateMessageContent; `onSaved` plays Telegram's success haptic.
    func addPollOption(
        messageID: Int64,
        text: FormattedText,
        submission: MessagePollInteractionStore.AddOptionSubmission,
        onSaved: @escaping @MainActor () -> Void,
    ) {
        guard submission.messageID == messageID, pollInteractionStore.isCurrent(submission) else { return }
        guard !isReadOnlyTopic, locationContextIsCurrent,
              let message = messages.first(where: { $0.id == messageID }),
              case .messagePoll(let content) = message.message.content, content.canAddOption
        else {
            pollInteractionStore.finishAddOption(submission, succeeded: false)
            return
        }
        let client = client
        let chatID = message.message.chatId
        let option = TDNativeInputPollOption(
            text: text,
            media: pollInteractionStore.addOptionMedia(messageID: messageID)?.input,
        )
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.addPollOption(
                    chatId: chatID,
                    messageId: messageID,
                    option: option,
                ))
                guard let self, pollInteractionStore.finishAddOption(submission, succeeded: true) else { return }
                onSaved()
            } catch {
                guard let self, pollInteractionStore.finishAddOption(submission, succeeded: false) else { return }
                log("Couldn't add a poll option to \(messageID): \(error.localizedDescription)")
                guard locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else { return }
                messageActionErrorMessage = (error as? TDLibError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Stops sharing an outgoing live location: `editMessageLiveLocation` with no location, which `canBeEdited`
    /// allows for a live location.
    func stopLiveLocation(_ message: CustomMessage) {
        guard message.properties.canBeEdited, message.message.isOutgoing,
              case .messageLiveLocation(let live) = message.message.content, live.expiresIn > 0 else { return }
        performMessageContentRequest(message) { client, chatID, messageID in
            _ = try await client.editMessageLiveLocation(
                chatId: chatID,
                messageId: messageID,
                replyMarkup: nil,
                location: nil,
            )
        }
    }

    func beginForward(_ forward: PendingMessageForward) {
        cancelReply()
        editCustomMessage = nil
        editMessageText = ""
        pendingForward = forward
    }

    func beginReply(to message: CustomMessage) {
        guard location.matches(message: message.message) else { return }
        pendingForward = nil
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

    /// Telegram's Reply to Item (ChatControllerOpenTodoContextMenu): a reply to one task of a checklist.
    func beginChecklistTaskReply(to message: CustomMessage, taskID: Int) {
        beginReply(to: message)
        guard replyMessage === message else { return }
        replyInputOverride = .inputMessageReplyToMessage(InputMessageReplyToMessage(
            checklistTaskId: taskID,
            messageId: message.id,
            pollOptionId: "",
            quote: nil,
        ))
    }

    /// Reply to Option: a reply to the poll that names the answer (setupReplyMessage with `.pollOption`).
    func beginPollOptionReply(to message: CustomMessage, optionID: String) {
        guard !optionID.isEmpty else { return }
        beginReply(to: message)
        guard replyMessage === message else { return }
        replyInputOverride = .inputMessageReplyToMessage(InputMessageReplyToMessage(
            checklistTaskId: 0,
            messageId: message.id,
            pollOptionId: optionID,
            quote: nil,
        ))
    }

    /// A quote from a file or music album's caption replies to the item it is in (`sourceMessageID`), as Telegram
    /// replies to the file whose caption is quoted.
    func beginQuoteReply(to message: CustomMessage, range: NSRange, sourceMessageID: Int64? = nil) {
        guard location.matches(message: message.message) else { return }
        pendingForward = nil
        if isAllMessagesForum, let topicID = message.forumTopicID {
            refreshForumTopic(id: topicID)
        }
        let source = sourceMessageID.flatMap { id in
            message.sourceMessages.first { $0.id == id && id != message.id }
        }
        let quotedText = source.flatMap { MessageContentPresentation.make($0).formattedText } ?? message.formattedText
        guard let formattedText = quotedText, !formattedText.text.isEmpty else {
            beginReply(to: message)
            return
        }
        markComposerDirty()
        replySelectionGeneration &+= 1
        replyMessage = message
        // Built synchronously so a send right after choosing Quote keeps it.
        replyQuote = MessageQuoteBuilder.make(
            from: formattedText,
            maximumLength: MessageQuoteLengthStore.maximumLength(clientID: client.id),
            range: range,
        )
        replyInputOverride = source.map { item -> InputMessageReplyTo in
            .inputMessageReplyToMessage(InputMessageReplyToMessage(
                checklistTaskId: 0,
                messageId: item.id,
                pollOptionId: "",
                quote: replyQuote,
            ))
        }
        replyFallbackPresentation = nil
        reconcileActiveChatActionAfterReplyChange()
    }

    /// Reply in Another Chat (Telegram's moveReplyToChat): the reply, with its quote, comes to this chat as a reply
    /// to `targetMessageID` of the message's chat. The chat's draft text stays.
    func beginExternalReply(to message: CustomMessage, targetMessageID: Int64, quote: InputTextQuote?) {
        guard message.message.chatId != chatID else { return }
        pendingForward = nil
        markComposerDirty()
        replySelectionGeneration &+= 1
        replyMessage = message
        replyQuote = quote
        replyInputOverride = .inputMessageReplyToExternalMessage(InputMessageReplyToExternalMessage(
            chatId: message.message.chatId,
            checklistTaskId: 0,
            messageId: targetMessageID,
            pollOptionId: "",
            quote: quote,
        ))
        replyFallbackPresentation = nil
        reconcileActiveChatActionAfterReplyChange()
    }

    /// OpenResolvedUrl's `.botStart` with interactive behaviour: a `t.me/bot?start=` link shows Start in the bot's
    /// chat, and nothing is sent until the user taps it.
    func beginBotStart(parameter: String) {
        guard !previewing, case .bot = customChat.type else { return }
        botStartParameter = parameter
    }

    /// ChatController.startBot: `sendBotStartMessage` sends /start with the parameter; the panel goes once it's sent.
    /// Without a parameter Telegram's requestStartBot sends a plain "/start".
    func sendBotStart() {
        if isChatBlocked {
            restartBot()
            return
        }
        guard botStartParameter != nil else {
            guard showsBotStart, !isStartingBot else { return }
            isStartingBot = true
            Task { [weak self] in
                await self?.sendBotCommandText("/start")
                self?.isStartingBot = false
            }
            return
        }
        guard let parameter = botStartParameter, !isStartingBot, locationContextIsCurrent,
              case .chatTypePrivate(let privateChat) = customChat.chat.type else { return }
        isStartingBot = true
        let client = client
        let chatID = chatID
        Task { [weak self] in
            let message = try? await client.send(TDNativeRequests.sendBotStartMessage(
                botUserId: privateChat.userId,
                chatId: chatID,
                parameter: parameter,
            ))
            guard let self else { return }
            isStartingBot = false
            guard locationContextIsCurrent else { return }
            if message != nil, botStartParameter == parameter { botStartParameter = nil }
        }
    }

    /// `updateChatBlockList` for this chat.
    func updateChatBlocked(_ isBlocked: Bool) {
        if isChatBlocked != isBlocked { isChatBlocked = isBlocked }
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

    /// Remove Quote in the reply options keeps the reply to the whole message (ChatMessageActionOptions).
    func removeReplyQuote() {
        guard replyQuote != nil else { return }
        markComposerDirty()
        replySelectionGeneration &+= 1
        replyQuote = nil
        replyInputOverride = replyInputOverride.map { input -> InputMessageReplyTo in
            switch input {
            case .inputMessageReplyToMessage(let reply):
                .inputMessageReplyToMessage(InputMessageReplyToMessage(
                    checklistTaskId: reply.checklistTaskId,
                    messageId: reply.messageId,
                    pollOptionId: reply.pollOptionId,
                    quote: nil,
                ))
            case .inputMessageReplyToExternalMessage(let reply):
                .inputMessageReplyToExternalMessage(InputMessageReplyToExternalMessage(
                    chatId: reply.chatId,
                    checklistTaskId: reply.checklistTaskId,
                    messageId: reply.messageId,
                    pollOptionId: reply.pollOptionId,
                    quote: nil,
                ))
            case .inputMessageReplyToEphemeralMessage,
                 .inputMessageReplyToStory:
                input
            }
        }
    }

    func updateComposerTextFromUser(_ value: AttributedString) {
        markComposerDirty()
        text = value
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

    func replaceDisplayedImages(_ images: [SelectedImage]) {
        let keptIDs = Set(images.map(\.id))
        let removed = displayedImages.filter { !keptIDs.contains($0.id) }
        displayedImages = images
        mediaCaptionIsAbove = false
        removeTemporaryImages(removed)
    }

    func removeDisplayedImage(id: UUID) {
        let removed = displayedImages.filter { $0.id == id }
        displayedImages.removeAll { $0.id == id }
        removeTemporaryImages(removed)
    }

    func discardDisplayedImages() {
        let removed = displayedImages
        displayedImages = []
        mediaCaptionIsAbove = false
        removeTemporaryImages(removed)
    }

    /// MediaPickerScreen's Hide With Spoiler and Disable Spoiler, for every picked item at once.
    func setDisplayedMediaSpoiler(_ hasSpoiler: Bool) {
        for index in displayedImages.indices {
            displayedImages[index].hasSpoiler = hasSpoiler
        }
    }

    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = try? await client.getMessage(chatId: customChat.chat.id, messageId: id),
              location.matches(message: message)
        else { return nil }
        return await getCustomMessage(from: message)
    }

    func getCustomMessage(from message: Message) async -> CustomMessage {
        async let replyPresentation = threadAwareReplyPresentation(for: message)
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
        if customMessage.contentPresentation.isService {
            customMessage.serviceText = await ServiceMessageText.resolve(
                message,
                senderUser: customMessage.senderUser,
                isChannel: customChat.supergroup?.isChannel == true,
                client: client,
            )
        }
        
        customMessage.formattedText = customMessage.contentPresentation.formattedText
        if case .messageSendingStateFailed = message.sendingState { customMessage.sendFailed = true }
        
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
        case .inputMessageReplyToEphemeralMessage,
             .inputMessageReplyToStory,
             nil:
            return nil
        }
    }

    /// Sends the composer. `options` carries the send-button menu's choice: without sound, at a date or when the
    /// user comes online; `mediaMode` how picked photos and videos go. A scheduled send never reaches this history,
    /// so it skips the bubble transition.
    func sendMessage(
        options: TDNativeMessageSendOptions? = nil,
        mediaMode: ComposerMediaSendMode = .grouped,
    ) async {
        guard !sendingComposerMessage else { return }
        sendingComposerMessage = true
        composerSendOptions = options
        composerMediaSendMode = mediaMode
        defer {
            sendingComposerMessage = false
            sendMessageTask = nil
            composerSendOptions = nil
            composerMediaSendMode = .grouped
        }
        switch composerEditState.prepare(message: editCustomMessage?.message, text: editMessageText) {
        case .ordinary:
            break
        case .invalidEdit:
            // An invalid edit is never an intent to send the preserved compose draft.
            return
        case .edit(let attempt):
            let linkPreviewOptions = currentEditLinkPreviewOptions
            let completion = await composerEditState.perform(attempt) { [self] attempt in
                try await editMessage(attempt, linkPreviewOptions: linkPreviewOptions)
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
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
        let forward = pendingForward
        if let forward, text.characters.isEmpty, displayedImages.isEmpty, displayedDocuments.isEmpty {
            await sendPendingForward(forward)
            return
        }
        let sentText = text
        let sentImageIDs = Set(displayedImages.map(\.id))
        let sentDocumentIDs = Set(displayedDocuments.map(\.id))
        let sentReplyID = replyMessage?.id
        let transitionID = UUID()
        let isScheduled = options?.schedulingState != nil
        let transitionKind: ComposerSendTransitionKind = displayedImages.isEmpty && displayedDocuments.isEmpty
            ? .text
            : .media
        let holdsMedia = transitionKind == .media && !isScheduled
        if holdsMedia { beginComposerSendHold(transitionID) }
        defer { endComposerSendHold(transitionID) }
        if !isScheduled {
            sendTransitionWillBegin.send(ComposerSendTransitionRequest(id: transitionID, kind: transitionKind))
        }
        do {
            let result: (context: ResolvedSendContext, messages: [Message])
            if !displayedDocuments.isEmpty {
                result = try await sendMessageDocuments()
            } else if !displayedImages.isEmpty {
                result = try await sendMessageMedia()
            } else if !ComposerTextBreaker.trimmed(text).characters.isEmpty {
                result = try await sendMessageText()
            } else {
                if !isScheduled { sendTransitionCancelled.send(transitionID) }
                return
            }
            if holdsMedia { narrowComposerSendHold(transitionID, to: result.messages.map(\.id)) }
            let draftClearSucceeded = await clearRouteDraft(result.context)
            if holdsMedia {
                await waitUntilTimelineShows(result.messages.map(\.id))
            }
            guard locationContextIsCurrent else {
                if !isScheduled { sendTransitionCancelled.send(transitionID) }
                return
            }
            displayedImages.removeAll { sentImageIDs.contains($0.id) }
            displayedDocuments.removeAll { sentDocumentIDs.contains($0.id) }
            if displayedImages.isEmpty { mediaCaptionIsAbove = false }
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
            // Only a forum topic reports its cleared draft back; TDLib keeps a thread's draft locally.
            awaitingAuthoritativeDraftClear = location.forumTopicID != nil && !hasNewComposerState
            composerIsDirty = awaitingAuthoritativeDraftClear
                || hasNewComposerState
                || !draftClearSucceeded
            sendErrorMessage = nil
            let acceptance = ComposerSendTransitionAcceptance(id: transitionID, messageIDs: result.messages.map(\.id))
            if holdsMedia {
                // Accept in the turn that cleared the composer, so the view inserts the media and shrinks the
                // composer together.
                endComposerSendHold(transitionID)
                sendTransitionAccepted.send(acceptance)
            }
            if hasNewComposerState {
                cancelPendingDraftClearRetry()
                await updateDraft()
            } else if location.forumTopicID != nil {
                loadForumTopic()
            }
            if transitionKind != .media, !isScheduled {
                await Task.yield()
                sendTransitionAccepted.send(acceptance)
            }
            if isScheduled {
                hasScheduledMessages = true
                scheduledComposerSend.send()
            }
            // A forward waiting under a scheduled message stays for the next send.
            if let forward, !isScheduled { await sendPendingForward(forward) }
        } catch {
            if !isScheduled { sendTransitionCancelled.send(transitionID) }
            sendErrorMessage = error.localizedDescription
        }
    }

    func sendMessageDocuments() async throws -> (context: ResolvedSendContext, messages: [Message]) {
        let documents = displayedDocuments
        // Telegram's file picker sends an mp3, m4a or flac file as music with its tags (iCloudFileDescription);
        // music and other files need their own permissions.
        var musicMetadata = [UUID: ComposerAudioMetadata]()
        for document in documents {
            if let metadata = await ComposerAudioMetadata.read(document.url) {
                musicMetadata[document.id] = metadata
            }
        }
        let sendsMusic = !musicMetadata.isEmpty
        let sendsOtherFiles = musicMetadata.count < documents.count
        if sendsMusic, sendsOtherFiles {
            _ = try resolveSendContext(for: .audio, replyingTo: replyMessage, useCurrentReplyOverride: true)
        }
        let context = try resolveSendContext(
            for: sendsOtherFiles ? .document : .audio,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        guard !documents.isEmpty else { throw ChatSendContextError.chatPermissionDenied }
        let caption = try await composerCaption()
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
            try await sendChatAction(
                .chatActionUploadingDocument(ChatActionUploadingDocument(progress: 0)),
                in: context,
            )
            let contents = documents.enumerated().map { index, document in
                let file = InputFile.inputFileLocal(InputFileLocal(path: document.url.path(percentEncoded: false)))
                if let music = musicMetadata[document.id] {
                    return InputMessageContent.inputMessageAudio(TDNativeInputMessageAudio(
                        audio: TDNativeInputAudio(
                            audio: file,
                            albumCoverThumbnail: music.coverURL.map { cover in
                                TDNativeInputThumbnail(
                                    thumbnail: .inputFileLocal(InputFileLocal(path: cover.path(percentEncoded: false))),
                                    width: Int(music.coverSize.width),
                                    height: Int(music.coverSize.height),
                                )
                            },
                            duration: music.duration,
                            title: music.title,
                            performer: music.performer,
                        ),
                        caption: index == 0 ? caption : nil,
                    ))
                }
                return InputMessageContent.inputMessageDocument(InputMessageDocument(
                    caption: index == 0 ? caption : nil,
                    document: InputDocument(
                        disableContentTypeDetection: true,
                        document: file,
                        thumbnail: nil,
                    ),
                ))
            }
            guard locationContextIsCurrent else { throw ChatSendContextError.accountUnavailable }
            let messages: [Message]
            if contents.count > 1, !(sendsMusic && sendsOtherFiles) {
                // Telegram starts a new group every ten files (`messages.count % 10 == 0`). A failure after the
                // first group keeps what went out, which the partial check below reports.
                var sent = [Message]()
                var start = 0
                groups: while start < contents.count {
                    let end = min(start + 10, contents.count)
                    let group = Array(contents[start..<end])
                    do {
                        if group.count == 1, let content = group.first {
                            try await sent.append(client.sendMessage(
                                chatId: context.chatID,
                                inputMessageContent: content,
                                options: composerSendOptions,
                                replyMarkup: nil,
                                replyTo: context.replyTo,
                                topicId: context.destinationTopic,
                            ))
                        } else {
                            let hold = beginOutgoingAlbum(count: group.count)
                            defer { endOutgoingAlbum(hold) }
                            let groupMessages = try await client.sendMessageAlbum(
                                chatId: context.chatID,
                                inputMessageContents: group,
                                options: composerSendOptions,
                                replyTo: context.replyTo,
                                topicId: context.destinationTopic,
                            )
                            .messages
                            sent += groupMessages
                            guard groupMessages.count == group.count else { break groups }
                        }
                    } catch {
                        if sent.isEmpty { throw error }
                        break
                    }
                    start = end
                }
                messages = sent
            } else {
                // Telegram groups files only when all are music or none are; a mix goes one message each. A failure
                // after the first keeps what went out, which the partial check below reports.
                var sent = [Message]()
                for content in contents {
                    do {
                        try await sent.append(client.sendMessage(
                            chatId: context.chatID,
                            inputMessageContent: content,
                            options: composerSendOptions,
                            replyMarkup: nil,
                            replyTo: context.replyTo,
                            topicId: context.destinationTopic,
                        ))
                    } catch {
                        if sent.isEmpty { throw error }
                        break
                    }
                }
                messages = sent
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

    func sendSticker(_ sticker: Sticker, options: TDNativeMessageSendOptions? = nil) async {
        // A sticker or GIF chosen while the composer's message is still sending goes out after it, as Telegram
        // queues sends, instead of being dropped.
        await waitForComposerSend()
        guard !sendingComposerMessage else { return }
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
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
                inputMessageContent: .inputMessageSticker(InputMessageSticker(
                    emoji: sticker.emoji,
                    sticker: InputSticker(
                        height: sticker.height,
                        sticker: .inputFileId(InputFileId(id: sticker.sticker.id)),
                        thumbnail: nil,
                        width: sticker.width,
                    ),
                )),
                options: options,
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

    /// Telegram's dice tooltip Send action: the same emoji goes out as a new roll, without the composer's reply.
    func sendDice(_ emoji: String) async {
        await waitForComposerSend()
        guard !sendingComposerMessage else { return }
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
        sendingComposerMessage = true
        defer { sendingComposerMessage = false }
        do {
            let context = try resolveSendContext(for: .sticker, replyingTo: nil)
            let message = try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: .inputMessageDice(InputMessageDice(clearDraft: false, emoji: emoji)),
                options: nil,
                replyMarkup: nil,
                replyTo: context.replyTo,
                topicId: context.destinationTopic,
            )
            guard locationContextIsCurrent,
                  context.matches(message: message)
            else { throw ChatSendContextError.unexpectedDestination }
            sendErrorMessage = nil
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    /// Sends a location, venue, contact or poll from the attachment menu. Each message replies to the composer's
    /// reply, which is then cleared, as Telegram's attachment sends do (`withUpdatedReplyMessageSubject(nil)` in
    /// ChatControllerOpenAttachmentMenu). Several contacts go out as separate messages.
    func sendAttachmentContents(_ contents: [InputMessageContent], kind: ChatSendContentKind) async {
        guard !contents.isEmpty else { return }
        await waitForComposerSend()
        guard !sendingComposerMessage else { return }
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
        sendingComposerMessage = true
        let sentReplyID = replyMessage?.id
        defer { sendingComposerMessage = false }
        do {
            let context = try resolveSendContext(
                for: kind,
                replyingTo: replyMessage,
                useCurrentReplyOverride: true,
            )
            for content in contents {
                let message = try await client.sendMessage(
                    chatId: context.chatID,
                    inputMessageContent: content,
                    options: nil,
                    replyMarkup: nil,
                    replyTo: context.replyTo,
                    topicId: context.destinationTopic,
                )
                guard locationContextIsCurrent,
                      context.matches(message: message)
                else { throw ChatSendContextError.unexpectedDestination }
            }
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
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    func sendAnimation(_ animation: Animation) async {
        let client = client
        await sendPanelAnimation { context in
            try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: .inputMessageAnimation(InputMessageAnimation(
                    animation: InputAnimation(
                        addedStickerFileIds: [],
                        animation: .inputFileId(InputFileId(id: animation.animation.id)),
                        duration: animation.duration,
                        height: animation.height,
                        thumbnail: nil,
                        width: animation.width,
                    ),
                    caption: nil,
                    hasSpoiler: false,
                    showCaptionAboveMedia: false,
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: context.replyTo,
                topicId: context.destinationTopic,
            )
        }
    }

    /// A GIF found through the GIF search bot, sent as its inline result with the bot hidden, as Telegram sends GIF
    /// search results (sendBotContextResultAsGif with hideVia).
    func sendInlineAnimation(queryID: Int64, resultID: String) async {
        let client = client
        await sendPanelAnimation { context in
            try await client.send(TDNativeRequests.sendInlineQueryResultMessage(
                chatId: context.chatID,
                topicId: context.destinationTopic,
                replyTo: context.replyTo,
                options: nil,
                queryId: queryID,
                resultId: resultID,
                hideViaBot: true,
            ))
        }
    }

    /// A command picked from the suggestions or the menu.
    func sendBotCommand(_ command: ChatBotCommand) {
        showsBotCommandMenu = false
        let messageText = command.messageText(inGroup: sendsCommandsToGroup)
        Task { [weak self] in await self?.sendBotCommandText(messageText) }
    }

    /// CommandChatInputContextPanelNode's insert arrow: "/command " replaces the typed command.
    func insertBotCommand(_ command: ChatBotCommand) {
        showsBotCommandMenu = false
        updateComposerTextFromUser(AttributedString("/" + command.command + " "))
    }

    /// ChatInterfaceStateContextQueries' `.mention`: for the "@" word at the caret, recently used inline bots when the
    /// "@" opens the input (getRecentInlineBots), then the group's members (searchChatMembers with the mention
    /// filter), sorted by name as Telegram sorts them. nil clears the suggestions.
    func updateMentionQuery(_ query: String?, includesInlineBots: Bool) {
        guard let query, !previewing else {
            mentionQueryTask?.cancel()
            mentionQuery = nil
            if !mentionSuggestions.isEmpty { mentionSuggestions = [] }
            return
        }
        if let current = mentionQuery, current.query == query, current.includesInlineBots == includesInlineBots {
            return
        }
        mentionQuery = (query, includesInlineBots)
        mentionQueryTask?.cancel()
        let client = client
        let chatID = chatID
        let topic = location.topic
        let searchesMembers =
            switch customChat.type {
            case .group,
                 .supergroup: true
            case .bot,
                 .user: false
            }
        let accountUserID = TDLib.shared.activeAccount?.userID
        mentionQueryTask = Task { [weak self] in
            let normalized = query.lowercased()
            var bots = [ChatMentionSuggestion]()
            if includesInlineBots, let recent = try? await client.send(TDNativeRequests.getRecentInlineBots()) {
                for userID in recent.userIds {
                    guard let user = try? await client.getUser(userId: userID),
                          let suggestion = ChatMentionSuggestion(user: user), suggestion.matches(normalized)
                    else { continue }
                    bots.append(suggestion)
                }
            }
            var members = [(suggestion: ChatMentionSuggestion, sortKey: String)]()
            if searchesMembers, let found = try? await client.send(TDNativeRequests.searchChatMembers(
                chatId: chatID,
                query: query,
                limit: 50,
                filter: .chatMembersFilterMention(.init(topicId: topic)),
            )) {
                let botIDs = Set(bots.map(\.userID))
                for member in found.members {
                    guard case .messageSenderUser(let sender) = member.memberId, sender.userId != accountUserID,
                          !botIDs.contains(sender.userId),
                          let user = try? await client.getUser(userId: sender.userId),
                          let suggestion = ChatMentionSuggestion(user: user)
                    else { continue }
                    members.append((suggestion, [user.lastName, user.firstName].joined(separator: " ")))
                }
            }
            guard !Task.isCancelled, let self, locationContextIsCurrent,
                  mentionQuery?.query == query else { return }
            mentionSuggestions = bots + members.sorted {
                $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending
            }
            .map(\.suggestion)
        }
    }

    /// ChatInterfaceStateContextQueries' `.emoji`, `.hashtag` and `.emojiSearch`: stickers for a lone emoji
    /// (getStickers, installed sets first, then TDLib's other matches), recently used hashtags (searchHashtags) or
    /// emoji by keyword (getKeywordEmojis for one letter, searchEmojis after). A query of another kind clears the
    /// previous kind's results at once; nil clears them all.
    func updateContextQuery(_ query: ChatInputContextQuery?) {
        guard let query, !previewing else {
            contextQueryTask?.cancel()
            contextQuery = nil
            if hashtagSuggestions != nil { hashtagSuggestions = nil }
            if !emojiSuggestions.isEmpty { emojiSuggestions = [] }
            if !stickerSuggestions.isEmpty { stickerSuggestions = [] }
            return
        }
        guard query != contextQuery else { return }
        contextQuery = query
        contextQueryTask?.cancel()
        switch query {
        case .stickers:
            if hashtagSuggestions != nil { hashtagSuggestions = nil }
            if !emojiSuggestions.isEmpty { emojiSuggestions = [] }
        case .hashtag:
            if !stickerSuggestions.isEmpty { stickerSuggestions = [] }
            if !emojiSuggestions.isEmpty { emojiSuggestions = [] }
        case .emojiSearch:
            if !stickerSuggestions.isEmpty { stickerSuggestions = [] }
            if hashtagSuggestions != nil { hashtagSuggestions = nil }
        }
        let client = client
        let chatID = chatID
        let publicChat: (username: String, isChannel: Bool, peer: SettingsPeer)? =
            if case .supergroup(let supergroup) = customChat.type,
            let username = supergroup.usernames?.activeUsernames.first {
                (username, supergroup.isChannel, SettingsPeer(chat: customChat.chat))
            } else {
                nil
            }
        contextQueryTask = Task { [weak self] in
            switch query {
            case .stickers(let emoji):
                let result = try? await client.getStickers(
                    chatId: chatID,
                    limit: 100,
                    query: emoji,
                    stickerType: .stickerTypeRegular,
                )
                guard !Task.isCancelled, let self, locationContextIsCurrent, contextQuery == query else { return }
                var seen = Set<Int>()
                stickerSuggestions = (result?.stickers ?? []).filter { seen.insert($0.sticker.id).inserted }
            case .hashtag(let prefix):
                let result = try? await client.send(TDNativeRequests.searchHashtags(prefix: prefix, limit: 50))
                guard !Task.isCancelled, let self, locationContextIsCurrent, contextQuery == query else { return }
                hashtagSuggestions = ChatHashtagSuggestions(
                    query: prefix,
                    hashtags: result?.hashtags ?? [],
                    publicUsername: publicChat?.username,
                    isChannel: publicChat?.isChannel ?? false,
                    chat: publicChat?.peer,
                )
            case .emojiSearch(let text, let languageCodes):
                var found = [ChatEmojiSuggestion]()
                if text.count < 2 {
                    let result = try? await client.send(TDNativeRequests.getKeywordEmojis(
                        text: text,
                        inputLanguageCodes: languageCodes,
                    ))
                    found = (result?.emojis ?? []).map { ChatEmojiSuggestion(emoji: $0, keyword: text) }
                } else {
                    let result = try? await client.send(TDNativeRequests.searchEmojis(
                        text: text,
                        inputLanguageCodes: languageCodes,
                    ))
                    found = (result?.emojiKeywords ?? []).map {
                        ChatEmojiSuggestion(emoji: $0.emoji, keyword: $0.keyword)
                    }
                }
                guard !Task.isCancelled, let self, locationContextIsCurrent, contextQuery == query else { return }
                var seen = Set<String>()
                emojiSuggestions = found.filter { seen.insert($0.emoji).inserted }
            }
        }
    }

    /// HashtagChatInputPanelItem's Delete: removeRecentHashtag, and the row goes at once.
    func removeRecentHashtag(_ hashtag: String) {
        let client = client
        Task { _ = try? await client.send(TDNativeRequests.removeRecentHashtag(hashtag: hashtag)) }
        guard let current = hashtagSuggestions else { return }
        hashtagSuggestions = ChatHashtagSuggestions(
            query: current.query,
            hashtags: current.hashtags.filter { $0 != hashtag },
            publicUsername: current.publicUsername,
            isChannel: current.isChannel,
            chat: current.chat,
        )
    }

    /// ChatController's sendBotCommand: the command goes as a message with the current reply, and the input and the
    /// reply are cleared.
    func sendBotCommandText(_ command: String) async {
        guard locationContextIsCurrent, canWriteBasicMessages else { return }
        await sendClearingComposer(for: .text) { client, context in
            try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: .inputMessageText(InputMessageText(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: command),
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: context.replyTo,
                topicId: context.destinationTopic,
            )
        }
    }

    /// A tapped inline result goes with the current reply (sendInlineQueryResultMessage); the input is cleared.
    func sendInlineBotResult(_ item: InlineBotResult) {
        guard inlineBotQuery != nil else { return }
        Task { [weak self] in
            await self?.sendClearingComposer(for: .text) { client, context in
                try await client.send(TDNativeRequests.sendInlineQueryResultMessage(
                    chatId: context.chatID,
                    topicId: context.destinationTopic,
                    replyTo: context.replyTo,
                    options: nil,
                    queryId: item.queryID,
                    resultId: item.resultID,
                    hideViaBot: false,
                ))
            }
        }
    }

    /// The inline results' next page once the list scrolls to its end (`next_offset`).
    func loadMoreInlineBotResults() {
        guard let state = inlineBotQuery, !state.isLoading, !state.nextOffset.isEmpty, inlineBotMoreTask == nil
        else { return }
        let client = client
        let chatID = chatID
        inlineBotMoreTask = Task { [weak self] in
            let page = try? await client.send(TDNativeRequests.getInlineQueryResults(
                botUserId: state.botUserID, chatId: chatID, userLocation: Self.tdLocation(state.userLocation),
                query: state.query, offset: state.nextOffset,
            ))
            guard let self else { return }
            inlineBotMoreTask = nil
            guard !Task.isCancelled, locationContextIsCurrent, let page, var current = inlineBotQuery,
                  current.botUserID == state.botUserID, current.query == state.query,
                  current.nextOffset == state.nextOffset else { return }
            current.results += page.results.map { InlineBotResult(queryID: page.inlineQueryId, result: $0) }
            current.nextOffset = page.nextOffset
            inlineBotQuery = current
        }
    }

    /// Conversation.ShareInlineBotLocationConfirmation was answered. OK lets the bot have the location from now on
    /// (setInlineBotLocationRequest(value: 0)) and its waiting query goes; Cancel keeps it waiting, and the bot is
    /// asked again after 10 minutes.
    func answerInlineBotLocationRequest(allowed: Bool) {
        guard let botUserID = inlineBotLocationRequest else { return }
        inlineBotLocationRequest = nil
        guard allowed else { return }
        InlineBotLocationConsent.grant(botUserID: botUserID)
        guard locationContextIsCurrent, inlineBotQuery?.botUserID == botUserID else { return }
        updateInlineBotQuery(retry: true)
    }

    /// A bot's updated full info (`updateUserFullInfo`) refreshes its description and commands.
    func applyBotFullInfo(_ info: TDNativeBotInfo?, botUserID: Int64) {
        guard case .bot = customChat.type else { return }
        botInfo = info
        botCommands = (info?.commands ?? []).map {
            ChatBotCommand(botUserID: botUserID, botUsername: nil, command: $0.command, description: $0.description)
        }
    }

    /// Telegram's shareAccountContact for a request-phone button: the account's own contact card.
    func ownContactContent() async -> InputMessageContent? {
        guard let me = try? await client.getMe(), !me.phoneNumber.isEmpty else { return nil }
        return .inputMessageContact(TDNativeInputMessageContact(contact: TDNativeContact(
            phoneNumber: me.phoneNumber,
            firstName: me.firstName,
            lastName: me.lastName,
            vcard: "",
            userId: me.id,
        )))
    }

    /// shareAccountContact and shareCurrentLocation after the user confirmed a request button: the contact or the
    /// location goes as a reply to the keyboard's message, and a one-time keyboard goes away.
    func sendKeyboardRequest(_ content: InputMessageContent, keyboardMessageID: Int64) async {
        guard supportsReplyKeyboard, locationContextIsCurrent else { return }
        await waitForComposerSend()
        guard !sendingComposerMessage, locationContextIsCurrent else { return }
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
        sendingComposerMessage = true
        defer { sendingComposerMessage = false }
        replyKeyboard.noteButtonUsed(messageID: keyboardMessageID)
        do {
            let context = try resolveSendContext(for: .text, replyingTo: nil)
            let message = try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: .inputMessageReplyToMessage(TDNativeInputMessageReplyToMessage(
                    messageId: keyboardMessageID,
                    quote: nil,
                    checklistTaskId: 0,
                    pollOptionId: "",
                )),
                topicId: context.destinationTopic,
            )
            guard locationContextIsCurrent, context.matches(message: message)
            else { throw ChatSendContextError.unexpectedDestination }
            sendErrorMessage = nil
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    /// A users or chat request button was answered (shareUsersWithBot / shareChatWithBot).
    func noteKeyboardRequestAnswered(keyboardMessageID: Int64) {
        replyKeyboard.noteButtonUsed(messageID: keyboardMessageID)
    }

    /// A reply keyboard's text button sends its title with the current reply, then clears that reply, as Telegram's
    /// `controllerInteraction.sendMessage` does; a one-time keyboard goes away at once.
    func pressReplyKeyboardButton(_ button: TDNativeKeyboardButton, keyboardMessageID: Int64) async {
        guard supportsReplyKeyboard, locationContextIsCurrent,
              replyKeyboard.offeredKeyboard?.messageID == keyboardMessageID else { return }
        guard case .keyboardButtonTypeText = button.type else {
            // Creating a managed bot and Web Apps need screens BetterTG doesn't have yet; the phone, location, poll,
            // users and chat requests are answered by the chat screen.
            messageActionErrorMessage = L10n.betterTG("Chat.UnsupportedButtonBetterTG")
            return
        }
        await waitForComposerSend()
        guard !sendingComposerMessage, locationContextIsCurrent else { return }
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
        sendingComposerMessage = true
        defer { sendingComposerMessage = false }
        let sentReplyID = replyMessage?.id
        replyKeyboard.noteButtonUsed(messageID: keyboardMessageID)
        do {
            let context = try resolveSendContext(
                for: .text,
                replyingTo: replyMessage,
                useCurrentReplyOverride: true,
            )
            let message = try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: .inputMessageText(InputMessageText(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: button.text),
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: context.replyTo,
                topicId: context.destinationTopic,
            )
            guard locationContextIsCurrent,
                  context.matches(message: message)
            else { throw ChatSendContextError.unexpectedDestination }
            // As for a sticker: the draft keeps its text and loses only the reply the button used.
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
        } catch {
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

    /// Sends the composer's photos and videos as Telegram's media picker does: albums of up to ten that may mix both,
    /// one message each (Send Without Grouping) or the picked files themselves (Send as File). The caption goes with
    /// the first item, above the media when it was moved up, marked items are hidden with a spoiler and a View Once
    /// item self-destructs once opened. A muted video goes as a GIF, and then nothing is grouped
    /// (`TGMediaAssetsController`'s `sendAsGif`).
    func sendMessageMedia() async throws -> (context: ResolvedSendContext, messages: [Message]) {
        let images = displayedImages
        let mode = composerMediaSendMode
        let sendsVideos = images.contains { $0.video != nil }
        let sendsGIFs = mode != .files && images.contains(where: Self.sendsAsAnimation)
        if mode != .files, sendsVideos, images.contains(where: { $0.video == nil }) {
            _ = try resolveSendContext(for: .photo, replyingTo: replyMessage, useCurrentReplyOverride: true)
        }
        if sendsGIFs {
            _ = try resolveSendContext(for: .animation, replyingTo: replyMessage, useCurrentReplyOverride: true)
        }
        let kind: ChatSendContentKind = mode == .files ? .document : sendsVideos ? .video : .photo
        let context = try resolveSendContext(for: kind, replyingTo: replyMessage, useCurrentReplyOverride: true)
        guard !images.isEmpty else { throw ChatSendContextError.chatPermissionDenied }
        for image in images {
            MediaUploadProgressRegistry.rememberSentPreview(image.image, path: image.url.path(percentEncoded: false))
        }
        // Telegram attaches the input's caption to the first item of a group (`TGMediaAssetsController`).
        let noCaption = FormattedText(entities: [], text: "")
        let caption = try await composerCaption() ?? noCaption
        let captionIsAbove = mediaCaptionIsAbove && !caption.text.isEmpty
        let action: ChatAction =
            switch mode {
            case .files: .chatActionUploadingDocument(ChatActionUploadingDocument(progress: 0))
            case .grouped,
                 .separately:
                sendsVideos
                    ? .chatActionUploadingVideo(ChatActionUploadingVideo(progress: 0))
                    : .chatActionUploadingPhoto(ChatActionUploadingPhoto(progress: 0))
            }
        try await sendChatAction(action, in: context)
        let provisionalMessageIDs = images.map { _ in -Int64.random(in: 1...Int64.max) }
        do {
            try leaseOutgoingMedia(images, as: provisionalMessageIDs, in: context)
        } catch {
            try? await cancelChatAction(in: context)
            throw error
        }
        var boundCount = 0
        var sentMessages = [Message]()
        do {
            var messageContents = [InputMessageContent]()
            for (index, image) in images.enumerated() {
                let caption = index == 0 ? caption : noCaption
                let showsCaptionAbove = index == 0 && captionIsAbove
                if mode == .files {
                    messageContents.append(Self.makeInputMessageFile(image, caption: caption))
                    continue
                }
                let selfDestructType: TDNativeMessageSelfDestructType? =
                    switch image.selfDestructTimer {
                    case .viewOnce: .messageSelfDestructTypeImmediately
                    case .seconds(let seconds): .messageSelfDestructTypeTimer(.init(selfDestructTime: seconds))
                    case nil: nil
                    }
                if let video = image.video, Self.sendsAsAnimation(image) {
                    messageContents.append(makeInputMessageAnimation(
                        video,
                        thumbnail: image.url,
                        caption: caption,
                        hasSpoiler: image.hasSpoiler,
                        showCaptionAboveMedia: showsCaptionAbove,
                    ))
                    continue
                }
                if let video = image.video {
                    messageContents.append(makeInputMessageVideo(
                        video,
                        thumbnail: image.url,
                        caption: caption,
                        hasSpoiler: image.hasSpoiler,
                        showCaptionAboveMedia: showsCaptionAbove,
                        selfDestructType: selfDestructType,
                    ))
                    continue
                }
                await messageContents.append(makeInputMessageContent(
                    for: image.url,
                    caption: caption,
                    livePhotoVideoURL: image
                        .isLivePhotoEnabled && canSendLivePhotos
                        ? image.livePhotoVideoURL
                        : nil,
                    livePhotoConversion: image.livePhotoConversion,
                    hasSpoiler: image.hasSpoiler,
                    showCaptionAboveMedia: showsCaptionAbove,
                    selfDestructType: selfDestructType,
                ))
            }
            guard locationContextIsCurrent else { throw ChatSendContextError.accountUnavailable }
            // Telegram groups up to ten items a message (`legacyAssetPickerEnqueueMessages`); without grouping
            // every item is its own message, and a GIF among them turns grouping off.
            let groupSize = mode == .separately || sendsGIFs ? 1 : 10
            var start = 0
            while start < messageContents.count {
                let end = min(start + groupSize, messageContents.count)
                let group = Array(messageContents[start..<end])
                let groupMessages: [Message]
                if group.count == 1, let content = group.first {
                    groupMessages = try await [client.sendMessage(
                        chatId: context.chatID,
                        inputMessageContent: content,
                        options: composerSendOptions,
                        replyMarkup: nil,
                        replyTo: context.replyTo,
                        topicId: context.destinationTopic,
                    )]
                } else {
                    let hold = beginOutgoingAlbum(count: group.count)
                    defer { endOutgoingAlbum(hold) }
                    groupMessages = try await client.sendMessageAlbum(
                        chatId: context.chatID,
                        inputMessageContents: group,
                        options: composerSendOptions,
                        replyTo: context.replyTo,
                        topicId: context.destinationTopic,
                    )
                    .messages
                }
                boundCount += bindOutgoingMedia(
                    groupMessages,
                    leasedAs: Array(provisionalMessageIDs[start..<end]),
                    in: context,
                )
                guard groupMessages.count == group.count else {
                    throw ChatSendContextError.partialAlbum(
                        sent: sentMessages.count + groupMessages.count,
                        expected: messageContents.count,
                    )
                }
                guard groupMessages.allSatisfy({ context.matches(message: $0) }) else {
                    throw ChatSendContextError.unexpectedDestination
                }
                sentMessages += groupMessages
                start = end
            }
            for (image, message) in zip(images, sentMessages) {
                guard let video = image.video else { continue }
                let fileID: Int
                switch message.content {
                case .messageVideo(let content):
                    fileID = content.video.video.id
                    MediaUploadProgressRegistry.rememberSentVideoPoster(
                        image.image,
                        for: MediaUploadProgressRegistry.Key(chatID: message.chatId, messageID: message.id),
                    )
                case .messageAnimation(let content):
                    fileID = content.animation.animation.id
                default:
                    continue
                }
                VideoSendConversionProgress.register(
                    fileID: fileID,
                    clientID: client.id,
                    originalPath: video.url.path(percentEncoded: false),
                )
            }
            try? await cancelChatAction(in: context)
            return (context, sentMessages)
        } catch {
            // Items already sent leave the composer, so retrying sends only the rest.
            let sentIDs = Set(images.prefix(sentMessages.count).map(\.id))
            displayedImages.removeAll { sentIDs.contains($0.id) }
            releaseOutgoingMedia(images, leasedAs: provisionalMessageIDs, from: boundCount, in: context)
            try? await cancelChatAction(in: context)
            throw error
        }
    }

    /// A picked video as Telegram sends it from the gallery: converted to its preset when TDLib generates the file
    /// (`VideoSendGenerationCoordinator`), with the converted size, a 320 pt thumbnail and streaming. A trimmed
    /// video has the trim's length, and a chosen cover goes as the video's `cover` (LegacyMediaPickers'
    /// `videoCover`); TDLib takes no cover for self-destructing media.
    func makeInputMessageVideo(
        _ video: SelectedVideo,
        thumbnail: URL,
        caption: FormattedText,
        hasSpoiler: Bool = false,
        showCaptionAboveMedia: Bool = false,
        selfDestructType: TDNativeMessageSelfDestructType? = nil,
    ) -> InputMessageContent {
        let dimensions = video.sentDimensions
        let cover: InputFile? = selfDestructType == nil
            ? video.coverURL.map { InputFile.inputFileLocal(InputFileLocal(path: $0.path(percentEncoded: false))) }
            : nil
        return .inputMessageVideo(InputMessageVideo(
            video: InputVideo(
                video: .inputFileGenerated(InputFileGenerated(
                    originalPath: video.url.path(percentEncoded: false),
                    conversion: video.conversion,
                    expectedSize: video.estimatedSize,
                )),
                thumbnail: InputThumbnail(
                    thumbnail: .inputFileLocal(InputFileLocal(path: thumbnail.path(percentEncoded: false))),
                    width: Int(video.thumbnailSize.width),
                    height: Int(video.thumbnailSize.height),
                ),
                cover: cover,
                startTimestamp: 0,
                addedStickerFileIds: [],
                duration: Int(video.sentDuration.rounded()),
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                supportsStreaming: true,
            ),
            caption: caption,
            showCaptionAboveMedia: showCaptionAboveMedia,
            selfDestructType: selfDestructType,
            hasSpoiler: hasSpoiler,
        ))
    }

    /// A muted video as a GIF: converted without sound at the Animation preset, with its thumbnail.
    func makeInputMessageAnimation(
        _ video: SelectedVideo,
        thumbnail: URL,
        caption: FormattedText,
        hasSpoiler: Bool = false,
        showCaptionAboveMedia: Bool = false,
    ) -> InputMessageContent {
        let dimensions = video.sentDimensions
        return .inputMessageAnimation(InputMessageAnimation(
            animation: InputAnimation(
                animation: .inputFileGenerated(InputFileGenerated(
                    originalPath: video.url.path(percentEncoded: false),
                    conversion: video.conversion,
                    expectedSize: video.estimatedSize,
                )),
                thumbnail: InputThumbnail(
                    thumbnail: .inputFileLocal(InputFileLocal(path: thumbnail.path(percentEncoded: false))),
                    width: Int(video.thumbnailSize.width),
                    height: Int(video.thumbnailSize.height),
                ),
                addedStickerFileIds: [],
                duration: Int(video.sentDuration.rounded()),
                width: Int(dimensions.width),
                height: Int(dimensions.height),
            ),
            caption: caption,
            showCaptionAboveMedia: showCaptionAboveMedia,
            hasSpoiler: hasSpoiler,
        ))
    }

    func makeInputMessageContent(
        for url: URL,
        caption: FormattedText,
        livePhotoVideoURL: URL? = nil,
        livePhotoConversion: String? = nil,
        hasSpoiler: Bool = false,
        showCaptionAboveMedia: Bool = false,
        selfDestructType: TDNativeMessageSelfDestructType? = nil,
    ) async -> InputMessageContent {
        let path = url.path(percentEncoded: false)
        let dimensions = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return CGSize.zero }
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            return CGSize(width: width, height: height)
        }.value
        let input = InputFile.inputFileLocal(InputFileLocal(path: path))
        // Telegram converts a Live Photo's motion while it uploads (LocalFileVideoMediaResource), so the motion
        // goes as a generated file for `VideoSendGenerationCoordinator`.
        let motion: InputFile? = livePhotoVideoURL.map { url in
            .inputFileGenerated(InputFileGenerated(
                originalPath: url.path(percentEncoded: false),
                conversion: livePhotoConversion ?? VideoSendPreset.medium.conversion,
                expectedSize: 0,
            ))
        }
        let photo = InputPhoto(
            addedStickerFileIds: [],
            height: Int(dimensions.height),
            photo: input,
            thumbnail: InputThumbnail(
                height: Int(dimensions.height),
                thumbnail: input,
                width: Int(dimensions.width),
            ),
            video: motion,
            width: Int(dimensions.width),
        )
        return .inputMessagePhoto(
            InputMessagePhoto(
                caption: caption,
                hasSpoiler: hasSpoiler,
                photo: photo,
                selfDestructType: selfDestructType,
                showCaptionAboveMedia: showCaptionAboveMedia,
            ),
        )
    }

    func sendMessageText() async throws -> (context: ResolvedSendContext, messages: [Message]) {
        if let dice = try await sendTextAsDice() { return dice }
        let context = try resolveSendContext(
            for: .text,
            replyingTo: replyMessage,
            useCurrentReplyOverride: true,
        )
        // TDLib accepts longer text from a user account and the server rejects it after the composer cleared, so the
        // text is split as Telegram does; every part keeps the reply, as in `ChatControllerNode`.
        var messages = [Message]()
        // The link panel's choices go with the first part, the one Telegram shows the panel for.
        let linkPreviewOptions = composerLinkPreviewSendOptions
        for (index, part) in ComposerTextBreaker.messages(text).enumerated() {
            let message = try await client.sendMessage(
                chatId: context.chatID,
                inputMessageContent: .inputMessageText(
                    InputMessageText(
                        clearDraft: false,
                        linkPreviewOptions: index == 0 ? linkPreviewOptions : nil,
                        text: FormattedText(entities: getEntities(from: part), text: part.string),
                    ),
                ),
                options: composerSendOptions,
                replyMarkup: nil,
                replyTo: context.replyTo,
                topicId: context.destinationTopic,
            )
            guard context.matches(message: message) else {
                throw ChatSendContextError.unexpectedDestination
            }
            messages.append(message)
        }
        guard !messages.isEmpty else { throw ChatSendContextError.chatPermissionDenied }
        try? await cancelChatAction(in: context)
        return (context, messages)
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
                message: L10n.betterTG("VideoNote.PreserveFailed"),
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
                message: L10n.betterTG("VideoNote.AnotherSending"),
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
                .chatActionUploadingVideoNote(ChatActionUploadingVideoNote(progress: 0)),
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
                guard let resentMessage = resent.messages.first else { throw CancellationError() }
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
                videoNoteErrorMessage = L10n.betterTG("VideoNote.QueuedStateNotSaved")
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
                    message: L10n.betterTG("VideoNote.UploadFailed"),
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
                message: L10n.betterTG("VideoNote.SendCancelled"),
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
                message: L10n.betterTG("VideoNote.SendFailed"),
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
            videoNoteErrorMessage = L10n.betterTG("VideoNote.RetryInProgress")
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
                    ?? L10n.betterTG("VideoNote.UploadFailed")
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
        editLinkPreviewTask?.cancel()
        editLinkPreviewRequest = nil
        if case .messageText(let content) = message.message.content {
            editLinkPreview = content.linkPreview
            editLinkPreviewOptions = content.linkPreviewOptions
        } else {
            editLinkPreview = nil
            editLinkPreviewOptions = nil
        }
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

    /// Move Up / Move Down in Telegram's link options.
    func setComposerLinkPreviewAboveText(_ isAbove: Bool) {
        updateComposerLinkPreviewOptions { current, url in
            TDNativeLinkPreviewOptions(
                isDisabled: false,
                url: url,
                forceSmallMedia: current?.forceSmallMedia ?? false,
                forceLargeMedia: current?.forceLargeMedia ?? false,
                showAboveText: isAbove,
            )
        }
    }

    /// Enlarge or Shrink Photo/Video in Telegram's link options.
    func setComposerLinkPreviewLargeMedia(_ isLarge: Bool) {
        updateComposerLinkPreviewOptions { current, url in
            TDNativeLinkPreviewOptions(
                isDisabled: false,
                url: url,
                forceSmallMedia: !isLarge,
                forceLargeMedia: isLarge,
                showAboveText: current?.showAboveText ?? false,
            )
        }
    }

    /// The panel's × and Do Not Preview: the message goes without a preview for this link.
    func disableComposerLinkPreview() {
        updateComposerLinkPreviewOptions { _, url in
            TDNativeLinkPreviewOptions(
                isDisabled: true,
                url: url,
                forceSmallMedia: false,
                forceLargeMedia: false,
                showAboveText: false,
            )
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
        RecordingIdleTimer.hold(self)
        startRecordingActionRefresh()
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
        RecordingIdleTimer.release(self)
        recordingActionRefreshTask?.cancel()
        recordingActionRefreshTask = nil
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
                _ = try await client.sendChatAction(
                    action: chatAction,
                    businessConnectionId: "",
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
              ), !loadingVoiceDraft,
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
        // Playback lets go of the session first, as the video note capture does; switching under a loaded player
        // can fail the deactivation and leave the session unable to record.
        Media.shared.stop()
        nc.post(name: .voiceRecordingWillStart, object: nil)
        Media.shared.setAudioSessionRecord()
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).wav")
        recordingVoiceNoteURL = url
        
        do {
            let recorder = try makeVoiceRecorder(url: url)
            audioRecorder = recorder
            recordingVoiceNote = true
            sendsVoiceViewOnce = false
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
            voiceNoteErrorMessage = L10n.betterTG("Voice.StartFailed")
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
        case .holding,
             .locked:
            finishVoiceRecording(sendWhenReady: true, pendingMessage: nil)
        case .idle,
             .pausing,
             .resuming:
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
                voiceNoteErrorMessage = L10n.betterTG("Voice.TrimSaveFailed")
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
                    voiceNoteErrorMessage = L10n.betterTG("Voice.StillSending")
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

    /// The route's own messages and a reply thread's root members. TDLib files only one member of an automatically
    /// forwarded album under the thread; the rest still head it.
    func routeIncludes(_ message: Message) -> Bool {
        if location.matches(message: message) { return true }
        guard location.messageThreadID != nil, let messageThread,
              message.chatId == location.chatID else { return false }
        return messageThread.messages.contains { $0.id == message.id }
    }

    /// ChatControllerReport's unblockPeer for a bot: the bot is unblocked (setMessageSenderBlockList), then started
    /// with the link's parameter or a plain "/start", only after the user's tap.
    private func restartBot() {
        guard isChatBlocked, !isStartingBot, locationContextIsCurrent, case .bot(let user) = customChat.type else {
            return
        }
        isStartingBot = true
        let client = client
        Task { [weak self] in
            let unblocked = await (try? client.send(TDNativeRequests.setMessageSenderBlockList(
                senderId: .messageSenderUser(.init(userId: user.id)),
                blockList: nil,
            ))) != nil
            guard let self else { return }
            guard unblocked, locationContextIsCurrent else {
                isStartingBot = false
                return
            }
            isChatBlocked = false
            if botStartParameter != nil {
                isStartingBot = false
                sendBotStart()
            } else {
                await sendBotCommandText("/start")
                isStartingBot = false
            }
        }
    }

    /// ChatInterfaceStateContextQueries' contextRequest: "@bot query" at the start of the input asks the inline bot
    /// once the query has stopped changing for 0.4 s; the previous results stay until the new ones arrive.
    /// A bot that needs the location gets it once the user agreed (requestChatContextResults' location); until then
    /// its query waits, as Telegram's does for inlineBotLocationRequestStatus. `retry` repeats the current query.
    private func updateInlineBotQuery(retry: Bool = false) {
        guard editCustomMessage == nil, !previewing,
              case .inlineBot(let username, let query) = ChatInputQuery.parse(text.string)
        else {
            inlineBotQueryTask?.cancel()
            inlineBotMoreTask?.cancel()
            if inlineBotQuery != nil { inlineBotQuery = nil }
            return
        }
        if !retry, let current = inlineBotQuery, current.username.lowercased() == username.lowercased(),
           current.query == query { return }
        inlineBotQueryTask?.cancel()
        inlineBotMoreTask?.cancel()
        var known = inlineBotQuery.flatMap { $0.username.lowercased() == username.lowercased() ? $0 : nil }
        if known != nil {
            known?.query = query
            known?.isLoading = true
            inlineBotQuery = known
        }
        let client = client
        let chatID = chatID
        let resolvedBot = known
        inlineBotQueryTask = Task { [weak self] in
            var state: InlineBotQueryState
            if let resolvedBot {
                state = resolvedBot
            } else {
                let bot = await Self.inlineBot(username: username, client: client)
                guard !Task.isCancelled, let self, locationContextIsCurrent else { return }
                guard let bot else {
                    inlineBotQuery = nil
                    return
                }
                state = InlineBotQueryState(
                    botUserID: bot.id,
                    username: username,
                    placeholder: bot.placeholder,
                    needsLocation: bot.needsLocation,
                    query: query,
                )
                inlineBotQuery = state
            }
            if !retry { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
            var userLocation: (latitude: Double, longitude: Double)?
            if state.needsLocation {
                guard InlineBotLocationConsent.isGranted(botUserID: state.botUserID) else {
                    // requestBotLocationStatus asks at most once in 10 minutes; the query waits for the consent.
                    guard let self, locationContextIsCurrent else { return }
                    if InlineBotLocationConsent.beginRequest(botUserID: state.botUserID) {
                        inlineBotLocationRequest = state.botUserID
                    }
                    return
                }
                // currentLocationManagerCoordinate(timeout: 5): without a fix the query goes without the location.
                userLocation = await OneShotLocation.current(timeout: .seconds(5))
                guard !Task.isCancelled else { return }
            }
            let page = try? await client.send(TDNativeRequests.getInlineQueryResults(
                botUserId: state.botUserID, chatId: chatID, userLocation: Self.tdLocation(userLocation), query: query,
                offset: "",
            ))
            guard !Task.isCancelled, let self, locationContextIsCurrent else { return }
            state.isLoading = false
            state.userLocation = userLocation
            state.results = page.map { found in
                found.results.map { InlineBotResult(queryID: found.inlineQueryId, result: $0) }
            } ?? []
            state.nextOffset = page?.nextOffset ?? ""
            state.button = page?.button
            inlineBotQuery = state
        }
    }

    /// ChatHistoryEntriesForView's bot info and peerCommands: a bot chat's description and commands, and the
    /// commands of every bot in a group.
    private func loadBotInfo() {
        botInfoTask?.cancel()
        updateChatBlocked(customChat.chat.blockList != nil)
        let client = client
        let type = customChat.type
        botInfoTask = Task { [weak self] in
            var info: TDNativeBotInfo?
            var sources = [(botUserID: Int64, commands: [TDNativeBotCommand])]()
            switch type {
            case .bot(let user):
                info = try? await client.getUserFullInfo(userId: user.id).botInfo
                if let info { sources = [(user.id, info.commands)] }
            case .supergroup(let group):
                if let full = try? await client.getSupergroupFullInfo(supergroupId: group.id) {
                    sources = full.botCommands.map { ($0.botUserId, $0.commands) }
                }
            case .group(let group):
                if let full = try? await client.getBasicGroupFullInfo(basicGroupId: group.id) {
                    sources = full.botCommands.map { ($0.botUserId, $0.commands) }
                }
            case .user:
                return
            }
            let isBotChat =
                if case .bot = type {
                    true
                } else {
                    false
                }
            var commands = [ChatBotCommand]()
            for source in sources {
                var username: String?
                if !isBotChat, let bot = try? await client.getUser(userId: source.botUserID) {
                    username = bot.usernames?.activeUsernames.first
                }
                commands += source.commands.map {
                    ChatBotCommand(
                        botUserID: source.botUserID,
                        botUsername: username,
                        command: $0.command,
                        description: $0.description,
                    )
                }
            }
            guard !Task.isCancelled, let self, locationContextIsCurrent else { return }
            botInfo = info
            botCommands = commands
        }
    }

    /// Sends a message a panel made in place of the input's text, then clears the input and its reply, as Telegram's
    /// sendBotCommand and inline result sends do.
    private func sendClearingComposer(
        for kind: ChatSendContentKind,
        _ send: (TDLibClient, ResolvedSendContext) async throws -> Message,
    ) async {
        await waitForComposerSend()
        guard !sendingComposerMessage else { return }
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
        sendingComposerMessage = true
        defer { sendingComposerMessage = false }
        do {
            let context = try resolveSendContext(for: kind, replyingTo: replyMessage, useCurrentReplyOverride: true)
            let message = try await send(client, context)
            guard locationContextIsCurrent, context.matches(message: message)
            else { throw ChatSendContextError.unexpectedDestination }
            markComposerDirty()
            text = ""
            composerLinkPreviewOptions = nil
            cancelReply(markDirty: false)
            do {
                try await updateDraft(in: context, replyTo: nil)
                draftErrorMessage = nil
            } catch {
                composerIsDirty = true
                scheduleDraftUpdateRetry(context, replyTo: nil)
            }
            sendErrorMessage = nil
        } catch {
            sendErrorMessage = error.localizedDescription
        }
    }

    /// ChatControllerLinkPreview: the input's preview, asked for once the text stops changing.
    private func scheduleComposerLinkPreview() {
        composerLinkPreviewTask?.cancel()
        let formatted = FormattedText(entities: getEntities(from: text), text: text.string)
        var canPreview = !previewing && formatted.text.contains(".")
        if case .chatTypeSecret = customChat.chat.type { canPreview = false }
        guard canPreview else {
            composerLinkPreviewRequest = nil
            if composerLinkPreview != nil { composerLinkPreview = nil }
            if text.characters.isEmpty, composerLinkPreviewOptions != nil { composerLinkPreviewOptions = nil }
            return
        }
        guard formatted != composerLinkPreviewRequest else { return }
        let client = client
        composerLinkPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let preview = try? await client.send(TDNativeRequests.getLinkPreview(
                text: formatted,
                linkPreviewOptions: nil,
            ))
            guard let self, !Task.isCancelled, locationContextIsCurrent else { return }
            composerLinkPreviewRequest = formatted
            if let preview, let options = composerLinkPreviewOptions, !options.url.isEmpty,
               options.url != preview.url
            {
                composerLinkPreviewOptions = nil
            }
            composerLinkPreview = preview
        }
    }

    /// UpdateChatPresentationInterfaceState's editingUrlPreview: a text message being edited previews its first link
    /// the same way; an edited caption doesn't.
    private func scheduleEditLinkPreview() {
        editLinkPreviewTask?.cancel()
        guard let editCustomMessage, case .messageText = editCustomMessage.message.content else {
            editLinkPreviewRequest = nil
            if editLinkPreview != nil { editLinkPreview = nil }
            return
        }
        let formatted = FormattedText(entities: getEntities(from: editMessageText), text: editMessageText.string)
        guard formatted.text.contains(".") else {
            editLinkPreviewRequest = nil
            if editLinkPreview != nil { editLinkPreview = nil }
            return
        }
        guard formatted != editLinkPreviewRequest else { return }
        let client = client
        let messageID = editCustomMessage.id
        editLinkPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let preview = try? await client.send(TDNativeRequests.getLinkPreview(
                text: formatted,
                linkPreviewOptions: nil,
            ))
            guard let self, !Task.isCancelled, locationContextIsCurrent, self.editCustomMessage?.id == messageID
            else { return }
            editLinkPreviewRequest = formatted
            if let preview, let options = editLinkPreviewOptions, !options.url.isEmpty, options.url != preview.url {
                editLinkPreviewOptions = nil
            }
            editLinkPreview = preview
        }
    }

    private func updateComposerLinkPreviewOptions(
        _ make: (TDNativeLinkPreviewOptions?, String) -> TDNativeLinkPreviewOptions,
    ) {
        if editCustomMessage != nil {
            // The edit's choices go with the edit; the compose draft keeps its own.
            guard let preview = editLinkPreview, locationContextIsCurrent else { return }
            editLinkPreviewOptions = make(currentEditLinkPreviewOptions, preview.url)
            return
        }
        guard let preview = composerLinkPreview, locationContextIsCurrent else { return }
        markComposerDirty()
        composerLinkPreviewOptions = make(currentLinkPreviewOptions, preview.url)
        Task { [weak self] in await self?.updateDraft() }
    }

    private func sendPanelAnimation(_ send: (ResolvedSendContext) async throws -> Message) async {
        await waitForComposerSend()
        guard !sendingComposerMessage else { return }
        if let wait = slowModeWaitMessage() {
            sendErrorMessage = wait
            return
        }
        sendingComposerMessage = true
        let transitionID = UUID()
        let sentReplyID = replyMessage?.id
        sendTransitionWillBegin.send(ComposerSendTransitionRequest(id: transitionID, kind: .media))
        defer { sendingComposerMessage = false }
        do {
            let context = try resolveSendContext(
                for: .animation,
                replyingTo: replyMessage,
                useCurrentReplyOverride: true,
            )
            // Telegram sends a GIF from the panel without the input's text, keeps that text and clears only the reply
            // (`ChatController` `sendMessages` for a gif result).
            let message = try await send(context)
            guard locationContextIsCurrent,
                  context.matches(message: message)
            else { throw ChatSendContextError.unexpectedDestination }
            // As for a sticker: the draft keeps its text and loses only the reply the GIF used.
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

    /// Telegram keeps a pending forward in the destination's interface state; BetterTG saves it per account and chat
    /// location, and sending, Do Not Forward, a reply or another forward clears or replaces it.
    private func storePendingForward() {
        guard !previewing, accountID != nil else { return }
        let destination = location.draftKey
        if let pendingForward, let stored = StoredMessageForward(pendingForward, destination: destination) {
            PendingMessageForwardStore.shared.save(stored)
        } else {
            PendingMessageForwardStore.shared.remove(destination: destination)
        }
    }

    /// Brings back the forward saved for this chat location. Its messages are prepared again on the current client;
    /// a forward they no longer allow, or one a reply or edit has since replaced, is dropped.
    private func restoreStoredForwardIfNeeded() {
        guard !previewing, pendingForward == nil, let accountID,
              let stored = PendingMessageForwardStore.shared.forward(for: location.draftKey) else { return }
        guard stored.source.accountID == accountID,
              let request = try? MessageForwardRequest(
                  sourceLocation: ChatLocation(
                      accountID: accountID, chatID: stored.source.chatID, clientID: client.id,
                      topic: stored.source.topic,
                  ),
                  messageIDs: stored.messageIDs,
              )
        else {
            PendingMessageForwardStore.shared.remove(stored)
            return
        }
        let client = client
        Task { [weak self] in
            do {
                let prepared = try await MessageForwardingService.prepare(request: request, client: client)
                guard let self, locationContextIsCurrent, pendingForward == nil else { return }
                guard replyMessage == nil, editCustomMessage == nil else {
                    PendingMessageForwardStore.shared.remove(stored)
                    return
                }
                pendingForward = stored.pending(prepared: prepared)
            } catch MessageForwardingError.accountChanged {
                // Another account or client is active; the forward waits for this one.
            } catch is CancellationError {
            } catch {
                guard let self, locationContextIsCurrent else { return }
                PendingMessageForwardStore.shared.remove(stored)
            }
        }
    }

    /// The root messages that head the thread, every member of a root album: getMessageThread returns them all, and
    /// Telegram heads the thread with the whole group (ChatHistoryEntriesForView, `MessageGroupEntry`).
    private func messageThreadHead(excluding knownIDs: Set<Int64>) -> [Message] {
        guard location.messageThreadID != nil, let messageThread else { return [] }
        return messageThread.messages.filter { $0.chatId == location.chatID && !knownIDs.contains($0.id) }
    }

    /// A history that reached its start before the thread was read gets its head now.
    private func insertMessageThreadHeadIfNeeded() {
        guard !hasMoreMessages, loadingMessagesTask == nil, !restorationWaitsForViewport,
              latestRestorationCursor == nil, locationContextIsCurrent else { return }
        let head = messageThreadHead(excluding: Set(messages.flatMap { $0.sourceMessages.map(\.id) }))
        guard !head.isEmpty else { return }
        loadingMessagesTask = Task { [weak self] in
            guard let self else { return }
            let readToken = messageRefresh?.beginRead()
            let loaded = await head.asyncMap { await self.getCustomMessage(from: $0) }
            guard !Task.isCancelled, locationContextIsCurrent else {
                loadingMessagesTask = nil
                return
            }
            let current = readToken.map {
                self.messageRefresh?
                    .takeCurrentValues(loaded.map(ChatHistoryMessageValue.init), token: $0)
                    .map { $0.makeMessage() } ?? []
            } ?? loaded
            messages = canonicalMessages(merging: messages, with: current, replacingExisting: true)
            loadingMessagesTask = nil
            driveMessageRefresh()
        }
    }

    /// Telegram drops a comment's reply header when it answers the channel post itself without a quote: the post
    /// heads the thread (ChatMessageBubbleItemNode, `replyThread.isChannelPost`).
    private func hidesReplyToThreadRoot(_ message: Message) -> Bool {
        guard let threadID = location.messageThreadID, messageThreadIsChannelPost == true,
              case .messageReplyToMessage(let reply) = message.replyTo else { return false }
        return reply.chatId == message.chatId && reply.messageId == threadID && reply.quote == nil
    }

    private func threadAwareReplyPresentation(for message: Message) async -> MessageReplyPresentation? {
        guard !hidesReplyToThreadRoot(message) else { return nil }
        return await metadataResolver.replyPresentation(for: message)
    }

    /// ChatControllerNode.sendCurrentMessage: outside secret chats, text that is only one of the server's dice emoji
    /// (without a custom emoji) is rolled as a die and keeps the reply.
    private func sendTextAsDice() async throws -> (context: ResolvedSendContext, messages: [Message])? {
        if case .chatTypeSecret = customChat.chat.type { return nil }
        let emoji = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard DiceEmojiStore.contains(emoji, clientID: client.id),
              !getEntities(from: text).contains(where: {
                  if case .textEntityTypeCustomEmoji = $0.type {
                      true
                  } else {
                      false
                  }
              }),
              let context = try? resolveSendContext(
                  for: .sticker,
                  replyingTo: replyMessage,
                  useCurrentReplyOverride: true,
              )
        else { return nil }
        let message = try await client.sendMessage(
            chatId: context.chatID,
            inputMessageContent: .inputMessageDice(InputMessageDice(clearDraft: false, emoji: emoji)),
            options: composerSendOptions,
            replyMarkup: nil,
            replyTo: context.replyTo,
            topicId: context.destinationTopic,
        )
        guard context.matches(message: message) else { throw ChatSendContextError.unexpectedDestination }
        try? await cancelChatAction(in: context)
        return (context, [message])
    }

    /// TDLib expires a chat action after a few seconds; Telegram repeats "recording audio" while the recording lasts.
    private func startRecordingActionRefresh() {
        recordingActionRefreshTask?.cancel()
        recordingActionRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self, recordingVoiceNote,
                      let context = activeVoiceRecordingContext else { return }
                _ = try? await sendChatAction(.chatActionRecordingVoiceNote, in: context)
            }
        }
    }

    /// Sends a request that changes a message's content on this chat's client and shows its failure once.
    private func performMessageContentRequest(
        _ message: CustomMessage,
        request: @escaping (TDLibClient, Int64, Int64) async throws -> Void,
    ) {
        guard locationContextIsCurrent, location.matches(message: message.message),
              messages.contains(where: { $0 === message }) else { return }
        let client = client
        let chatID = message.message.chatId
        let messageID = message.id
        Task { [weak self] in
            do {
                try await request(client, chatID, messageID)
            } catch {
                guard let self, locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else { return }
                messageActionErrorMessage = (error as? TDLibError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Waits up to 30 s for the composer's own send (text, media or documents) to finish.
    private func waitForComposerSend() async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(30)
        while sendingComposerMessage, clock.now < deadline, !Task.isCancelled, locationContextIsCurrent {
            if let task = sendMessageTask {
                await task.value
            } else {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Each sent item's files are leased before sending, as documents are: removing the item from the composer during
    /// the send, or the send failing, never deletes a file TDLib reads. A Live Photo sent without its motion leases
    /// the motion too, so it goes with the message.
    private func leaseOutgoingMedia(
        _ images: [SelectedImage],
        as provisionalMessageIDs: [Int64],
        in context: ResolvedSendContext,
    ) throws {
        var leasedMessageIDs = [Int64]()
        do {
            for (image, provisionalMessageID) in zip(images, provisionalMessageIDs) {
                try SelectedDocumentFileStore.lease(
                    image.fileURLs,
                    accountID: context.accountID,
                    chatID: context.chatID,
                    messageID: provisionalMessageID,
                    defersRemoval: true,
                )
                leasedMessageIDs.append(provisionalMessageID)
            }
        } catch {
            for provisionalMessageID in leasedMessageIDs {
                SelectedDocumentFileStore.unlease(
                    accountID: context.accountID,
                    chatID: context.chatID,
                    messageID: provisionalMessageID,
                )
            }
            throw error
        }
    }

    /// Moves the leases to the sent messages, in order; TDLib's send updates release them from there.
    private func bindOutgoingMedia(
        _ messages: [Message],
        leasedAs provisionalMessageIDs: [Int64],
        in context: ResolvedSendContext,
    ) -> Int {
        for (message, provisionalMessageID) in zip(messages, provisionalMessageIDs) {
            try? SelectedDocumentFileStore.replaceMessageID(
                accountID: context.accountID,
                chatID: context.chatID,
                old: provisionalMessageID,
                new: message.id,
            )
        }
        return min(messages.count, provisionalMessageIDs.count)
    }

    /// Unleases the items no message took. The composer keeps their files unless it dropped the item during the send.
    private func releaseOutgoingMedia(
        _ images: [SelectedImage],
        leasedAs provisionalMessageIDs: [Int64],
        from boundCount: Int,
        in context: ResolvedSendContext,
    ) {
        for provisionalMessageID in provisionalMessageIDs.dropFirst(boundCount) {
            SelectedDocumentFileStore.unlease(
                accountID: context.accountID,
                chatID: context.chatID,
                messageID: provisionalMessageID,
            )
        }
        let displayedIDs = Set(displayedImages.map(\.id))
        removeTemporaryImages(images.dropFirst(boundCount).filter { !displayedIDs.contains($0.id) })
    }

    /// The input as a media caption, trimmed as sent text is, or nil when nothing is left. A caption over TDLib's
    /// limit stops the send while the composer still holds it.
    private func composerCaption() async throws -> FormattedText? {
        let caption = ComposerTextBreaker.trimmed(text)
        guard !caption.characters.isEmpty else { return nil }
        let limit: Int =
            if case .optionValueInteger(let value) = try? await client.getOption(name: "message_caption_length_max") {
                max(1, Int(clamping: value.value))
            } else {
                1024
            }
        guard ComposerTextBreaker.length(of: caption) <= limit else { throw ComposerCaptionTooLongError(limit: limit) }
        return FormattedText(entities: getEntities(from: caption), text: caption.string)
    }

    /// A window is contiguous history from `oldest` to `newest`. It splits any gap it lands in, and a window older
    /// than everything loaded leaves a gap up to the previous oldest message. Call before merging the window.
    private func recordHistoryWindow(oldest: Int64, newest: Int64) {
        let loadedIDs = messages.flatMap { $0.sourceMessages.map(\.id) }
        guard let tailOldest = oldestHistoryMessageID ?? loadedIDs.min() else { return }
        var gaps = [HistoryGap]()
        for gap in historyGaps {
            guard oldest < gap.newerBoundID, newest > gap.olderBoundID else {
                gaps.append(gap)
                continue
            }
            if gap
                .olderBoundID < oldest { gaps.append(HistoryGap(olderBoundID: gap.olderBoundID, newerBoundID: oldest)) }
            if newest < gap
                .newerBoundID { gaps.append(HistoryGap(olderBoundID: newest, newerBoundID: gap.newerBoundID)) }
        }
        if newest < tailOldest { gaps.append(HistoryGap(olderBoundID: newest, newerBoundID: tailOldest)) }
        // A window newer than every sent row, such as the latest one, leaves a gap down to the loaded history.
        let sentIDs = messages.flatMap(\.sourceMessages).filter { $0.sendingState == nil }.map(\.id)
        if let headNewest = sentIDs.max(), oldest > headNewest {
            gaps.append(HistoryGap(olderBoundID: headNewest, newerBoundID: oldest))
        }
        historyGaps = gaps.sorted { $0.newerBoundID > $1.newerBoundID }
    }

    private func loadHistoryGap(_ gap: HistoryGap, fromOlderSide: Bool) async {
        defer { historyGapTask = nil }
        let readToken = messageRefresh?.beginRead()
        let pageSize = 50
        guard let fetched = await loadHistory(
            fromMessageId: fromOlderSide ? gap.olderBoundID : gap.newerBoundID,
            limit: pageSize,
            offset: fromOlderSide ? -(pageSize - 1) : 0,
        ), !Task.isCancelled, locationContextIsCurrent, historyGaps.contains(gap) else { return }
        let inside = fetched.filter { $0.id > gap.olderBoundID && $0.id < gap.newerBoundID }
        let closes = fromOlderSide
            ? fetched.contains { $0.id >= gap.newerBoundID }
            : fetched.contains { $0.id <= gap.olderBoundID }
        // TDLib can return an empty page while it fills its cache; the next scroll near the gap retries.
        guard closes || !inside.isEmpty else { return }
        let loaded = await inside.filter { location.matches(message: $0) }.asyncMap { await getCustomMessage(from: $0) }
        guard !Task.isCancelled, locationContextIsCurrent, let index = historyGaps.firstIndex(of: gap) else { return }
        if closes {
            historyGaps.remove(at: index)
        } else if fromOlderSide, let newest = inside.map(\.id).max() {
            historyGaps[index].olderBoundID = newest
        } else if let oldest = inside.map(\.id).min() {
            historyGaps[index].newerBoundID = oldest
        }
        let current = readToken.map {
            messageRefresh?.takeCurrentValues(loaded.map(ChatHistoryMessageValue.init), token: $0)
                .map { $0.makeMessage() } ?? []
        } ?? loaded
        if !current.isEmpty {
            messages = canonicalMessages(merging: messages, with: current, replacingExisting: true)
        }
        driveMessageRefresh()
    }

    private func beginOutgoingAlbum(count: Int) -> UUID {
        let id = UUID()
        outgoingAlbumHold = (id, count)
        return id
    }

    private func beginComposerSendHold(_ id: UUID) {
        composerSendHold = (id, Set(messages.flatMap(\.sourceMessages).map(\.id)), nil)
        // A bound for a send that never settles.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.endComposerSendHold(id)
        }
    }

    private func endComposerSendHold(_ id: UUID) {
        guard composerSendHold?.id == id else { return }
        composerSendHold = nil
        messagesDidChange.send()
    }

    /// The send call named its messages: release any other pending outgoing row the hold caught.
    private func narrowComposerSendHold(_ id: UUID, to messageIDs: [Int64]) {
        guard composerSendHold?.id == id else { return }
        composerSendHold?.sentMessageIDs = Set(messageIDs)
        messagesDidChange.send()
    }

    /// The send call returned before every member reached `messages`. Keep holding a partial album for a moment
    /// longer, then show whatever arrived.
    private func endOutgoingAlbum(_ id: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, outgoingAlbumHold?.id == id else { return }
            outgoingAlbumHold = nil
            messagesDidChange.send()
        }
    }

    /// Telegram clears the input in the transaction that inserts the sent message. The sent messages reach
    /// `messages` shortly after the send call returns; wait for them, within a bound, before the composer clears and
    /// the timeline shows them.
    private func waitUntilTimelineShows(_ ids: [Int64]) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(1)
        while clock.now < deadline, !Task.isCancelled, locationContextIsCurrent {
            let shown = Set(messages.flatMap(\.sourceMessages).map(\.id)).union(messageReplacementIDs.values)
            if ids.allSatisfy(shown.contains), !messages.contains(where: holdsIncompleteOutgoingAlbum) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func sendPendingForward(_ forward: PendingMessageForward) async {
        guard locationContextIsCurrent, let accountID else { return }
        do {
            _ = try await MessageForwardingService.send(
                forward.prepared,
                to: MessageForwardDestination(chatID: chatID, topic: location.topic),
                mode: forward.mode,
                client: client,
                accountID: accountID,
            )
            guard locationContextIsCurrent else { return }
            if pendingForward?.id == forward.id { pendingForward = nil }
            sendErrorMessage = nil
        } catch {
            // An ambiguous partial result must not be offered for automatic retry.
            let ambiguous: Bool =
                if case MessageForwardingError.partialDelivery = error {
                    true
                } else {
                    error is DecodingError
                }
            if ambiguous, pendingForward?.id == forward.id { pendingForward = nil }
            sendErrorMessage = error.localizedDescription
        }
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
        case .holding,
             .locked:
            updateVoiceRecordingDuration()
            voiceRecordingInteractionState = .locked
            if canPauseVoiceRecording {
                closeVoiceRecordingSegment(sendAfterPreparation: false)
            } else {
                finishVoiceRecording(
                    sendWhenReady: false,
                    pendingMessage: L10n.betterTG("Voice.StoppedBeforePreview"),
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
        case .idle,
             .pausing,
             .resuming:
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
            includes: { [weak self] message in
                self?.routeIncludes(message) ?? location.matches(message: message)
            },
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
                      !Task.isCancelled, locationContextIsCurrent, cursor.accept(
                          rawPage: page,
                          requestedFromMessageID: cursor.fromMessageID,
                      ),
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
            forward: pendingForward,
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
        pendingForward = seed.forward?.renewed(for: location)
    }

    private func editMessage(
        _ attempt: ChatComposerEditState.Attempt,
        linkPreviewOptions: TDNativeLinkPreviewOptions?,
    ) async throws {
        let message = attempt.message
        let context = try resolveEditContext(for: message)
        try Task.checkCancellation()
        switch message.content {
        case .messageText:
            // The edit's link panel choices, which start from the message's own (Telegram's editingUrlPreview).
            _ = try await client.editMessageText(
                chatId: context.chatID,
                inputMessageContent:
                .inputMessageText(
                    .init(
                        clearDraft: false,
                        linkPreviewOptions: linkPreviewOptions,
                        text: attempt.text,
                    ),
                ),
                messageId: message.id,
                replyMarkup: nil,
            )
        case .messageAnimation,
             .messageAudio,
             .messageDocument,
             .messagePhoto,
             .messageVideo,
             .messageVoiceNote:
            _ = try await client.editMessageCaption(
                caption: attempt.text,
                chatId: context.chatID,
                messageId: message.id,
                replyMarkup: nil,
                showCaptionAboveMedia: Self.showsCaptionAboveMedia(message.content),
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
                        DraftMessageContentText(
                            linkPreviewOptions: composerLinkPreviewSendOptions,
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
        _ = try await client.setChatDraftMessage(
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
            allowsSavedMessagesTopic: current.allowsSavedMessagesTopic,
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
                businessConnectionId: "",
                chatId: active.chatID,
                topicId: active.destinationTopic,
            )
        }
        guard chatActionRouteRevision == revision else {
            await reconcileDesiredChatAction(after: revision)
            throw CancellationError()
        }
        _ = try await client.sendChatAction(
            action: action,
            businessConnectionId: "",
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
            businessConnectionId: "",
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
                businessConnectionId: "",
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
        case .chatActionRecordingVoiceNote,
             .chatActionUploadingVoiceNote:
            .voiceNote
        case .chatActionRecordingVideoNote,
             .chatActionUploadingVideoNote:
            .videoNote
        case .chatActionUploadingPhoto:
            .photo
        case .chatActionUploadingVideo:
            .video
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
        if customChat.secretChatID != nil, secretChatIsReady != true { return false }
        // Telegram's recipient restriction on voice and video notes (`Conversation.VoiceMessagesRestricted`).
        switch kind {
        case .videoNote,
             .voiceNote: if recipientRestrictsVoiceAndVideoNotes { return false }
        default: break
        }
        let permission: KeyPath<ChatPermissions, Bool> =
            switch kind {
            case .animation,
                 .sticker:
                \.canSendOtherMessages
            case .audio:
                \.canSendAudios
            case .document:
                \.canSendDocuments
            case .photo:
                \.canSendPhotos
            // TDLib sends checklists under the poll permission.
            case .checklist,
                 .poll:
                \.canSendPolls
            case .text:
                \.canSendBasicMessages
            case .video:
                \.canSendVideos
            case .videoNote:
                \.canSendVideoNotes
            case .voiceNote:
                \.canSendVoiceNotes
            }
        return customChat.allowsSending(
            permission, defaults: currentChatPermissions, inReplyThread: location.messageThreadID != nil,
        )
    }

    private func removeTemporaryDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            SelectedDocumentFileStore.removeUnleased(urls)
        }
    }

    /// Removes the composer's copies of photos and videos; a file leased to a sent message stays.
    private func removeTemporaryImages(_ images: [SelectedImage]) {
        removeTemporaryDocuments(images.flatMap(\.fileURLs))
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
        // A draft keeps its link preview choices (DraftMessageContentText.linkPreviewOptions).
        composerLinkPreviewOptions =
            if let draft, case .draftMessageContentText(let content) = draft.content {
                content.linkPreviewOptions
            } else {
                nil
            }
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
        _ = try await client.sendChatAction(
            action: .chatActionCancel,
            businessConnectionId: "",
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
            } else if let threadID = location.messageThreadID {
                // Any message of the thread names it; the root is the one the route keeps.
                try? await client.getMessageThreadHistory(
                    chatId: location.chatID,
                    fromMessageId: fromMessageId,
                    limit: limit,
                    messageId: threadID,
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
              acceptsChatLevelPin(message.message),
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
                        L10n.betterTG("Error.AccountChanged")
                    case .unavailable:
                        L10n.betterTG("Chat.PinUnavailable")
                    case nil:
                        pinned
                            ? L10n.betterTG("Chat.PinFailed")
                            : L10n.betterTG("Chat.UnpinFailed")
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
            case .inputMessageReplyToMessage,
                 nil:
                true
            case .inputMessageReplyToEphemeralMessage,
                 .inputMessageReplyToExternalMessage,
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
        case .inputMessageReplyToEphemeralMessage,
             .inputMessageReplyToStory,
             nil:
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
            videoNoteErrorMessage = L10n.betterTG("VideoNote.SendInterrupted")
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
            videoNote: .inputFileLocal(InputFileLocal(path: draft.fileURL.path(percentEncoded: false))),
        )
        let message = try await client.sendMessage(
            chatId: context.chatID,
            inputMessageContent: .inputMessageVideoNote(
                InputMessageVideoNote(videoNote: inputVideoNote, selfDestructType: nil),
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
            voiceNoteErrorMessage = L10n.betterTG("Voice.DestinationNotWritable")
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
            voiceNoteErrorMessage = L10n.betterTG("Voice.ResumeFailed")
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
                        caption: FormattedText(
                            entities: getEntities(from: text),
                            text: text.string,
                        ),
                        createdAt: Foundation.Date(),
                        exactDuration: inspection.duration,
                        fileURL: sourceURL,
                        replyMessageID: reply?.id,
                        replyTo: (recordingContext?.replyTo ?? getMessageReplyTo(from: reply)),
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
                    voiceNoteErrorMessage = L10n.betterTG("Voice.AppendFailed")
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
            replyTo: (context?.replyTo ?? getMessageReplyTo(from: reply)),
            sendTopic: context?.destinationTopic,
            temporaryMessageID: nil,
            waveform: VoiceNoteCodec.encodeWaveform(peakPowers: peakPowers),
            destination: context?.draftKey ?? location.draftKey,
            isViewOnce: takeVoiceViewOnce(),
        )
        activeVoiceRecordingContext = nil
        pendingVoiceReplyMessage = reply
        cancelReplyIfMatching(context?.replyTo)
        startVoiceFinalization(
            sendWhenReady: false,
            pendingMessage: L10n.betterTG("Voice.PreviewFailedPreserved"),
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
                voiceNoteErrorMessage = L10n.betterTG("Voice.TrimApplyFailed")
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
            isViewOnce: takeVoiceViewOnce(),
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
                voiceNoteErrorMessage = L10n.betterTG("Voice.PreparePreviewFailed")
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
                    voiceNoteErrorMessage = L10n.betterTG("Voice.PreviewPlaybackFailed")
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
            voiceNoteErrorMessage = pendingMessage ?? L10n.betterTG("Voice.TooShort")
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
            replyTo: (recordingContext?.replyTo ?? getMessageReplyTo(from: reply)),
            sendTopic: recordingContext?.destinationTopic,
            temporaryMessageID: nil,
            waveform: VoiceNoteCodec.encodeWaveform(peakPowers: peakPowers),
            destination: recordingContext?.draftKey ?? location.draftKey,
            isViewOnce: takeVoiceViewOnce(),
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
            voiceRecordingTimerBaseline = timerCountStorage
        }
        voiceRecordingLastRecorderTime = recorderTime
        let couldPause = canPauseVoiceRecording
        timerCountStorage = max(timerCountStorage, voiceRecordingTimerBaseline + recorderTime)
        // Pause becomes available half a second in; that one change still refreshes the whole composer.
        if canPauseVoiceRecording != couldPause { objectWillChange.send() }
        recordingTimeChanged.send()
    }

    /// The play-once choice belongs to the recording being sent and resets, as Telegram's does after a send.
    private func takeVoiceViewOnce() -> Bool? {
        defer { sendsVoiceViewOnce = false }
        return sendsVoiceViewOnce && canSendVoiceViewOnce ? true : nil
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
                InputMessageVoiceNote(
                    voiceNote: .init(
                        voiceNote: .inputFileLocal(InputFileLocal(path: fileURL.path(percentEncoded: false))),
                        duration: draft.duration,
                        waveform: draft.waveform,
                    ),
                    caption: draft.caption,
                    selfDestructType: draft.isViewOnce == true ? .messageSelfDestructTypeImmediately : nil,
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
                    // Telegram draws the waveform from the recorded samples; the meter readings taken while
                    // holding are only an estimate, so the PCM peaks replace them as the trim editor's do.
                    let pcmWaveform = try? await VoiceNotePCMEditor.inspect(sourceURL).waveform
                    let encodedURL = try await VoiceNoteCodec.encodeOggOpus(from: sourceURL)
                    defer { try? FileManager.default.removeItem(at: encodedURL) }
                    try Task.checkCancellation()
                    guard voiceFinalizationGeneration == generation else { throw CancellationError() }
                    draft = try await VoiceNoteDraftStore.shared.replaceFile(
                        in: draft, with: encodedURL, finalization: claim.lease, waveform: pcmWaveform,
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
                    voiceNoteErrorMessage = pendingMessage ?? L10n.betterTG("Voice.StoppedBeforeSend")
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
                    .chatActionUploadingVoiceNote(ChatActionUploadingVoiceNote(progress: 0)),
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
                    guard let resentMessage = resentMessages.messages.first else {
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
                        voiceNoteErrorMessage = L10n.betterTG("Voice.QueuedStateNotSaved")
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
                    if !didStartSend || error is TDLibError,
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
                    ?? L10n.betterTG("Voice.SendFailed")
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
            awaitingAuthoritativeDraftClear = location.forumTopicID != nil
            composerIsDirty = awaitingAuthoritativeDraftClear || !draftClearSucceeded
            if location.forumTopicID != nil {
                loadForumTopic()
            }
        }
    }

    private func clearRouteDraft(_ context: ResolvedSendContext) async -> Bool {
        draftClearGeneration &+= 1
        let generation = draftClearGeneration
        draftClearTask?.cancel()
        do {
            _ = try await client.setChatDraftMessage(
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
            draftErrorMessage = L10n.betterTG("Composer.StickerDraftUpdateFailed")
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
                    _ = try await client.setChatDraftMessage(
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
            draftErrorMessage = L10n.betterTG("Composer.OldDraftClearFailed")
        }
    }

    private func applyVoiceNoteDraftResolution(_ resolution: VoiceNoteDraftResolution) {
        outgoingVoiceNotes.removeValue(forKey: resolution.temporaryMessageID)
        switch resolution.outcome {
        case .failed:
            if pendingVoiceNote == nil, !recordingVoiceNote, !startingVoiceNote {
                activatePendingVoiceDraft(resolution.draft)
                voiceNoteErrorMessage = pendingVoiceRetryStatusMessage
                    ?? L10n.betterTG("Voice.UploadFailed")
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
            voiceNoteErrorMessage = L10n.betterTG("Voice.SendInterrupted")
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
}

private extension ChatMemberStatus {
    /// Telegram's `participationStatus == .member`.
    var isChatMember: Bool {
        switch self {
        case .chatMemberStatusCreator(let creator): creator.isMember
        case .chatMemberStatusAdministrator,
             .chatMemberStatusMember: true
        case .chatMemberStatusRestricted(let restricted): restricted.isMember
        case .chatMemberStatusBanned,
             .chatMemberStatusLeft: false
        }
    }
}
