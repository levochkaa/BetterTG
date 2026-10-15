// MessageStructuredContentView.swift

import Combine
import MapKit
import TDLibKit
import UIKit

// MARK: - MessageContentAction

enum MessageContentAction {
    case openDocument(URL)
    /// The contact card itself: a Telegram user opens their profile, anyone else the contact sheet.
    case openContact(Contact)
    /// The card's MESSAGE button (ChatMessageContactBubbleContentNode.messageButtonPressed).
    case messageContact(userID: Int64)
    /// The card's ADD or VIEW CONTACT button, which opens the contact sheet as Telegram's openMessage does.
    case viewContact(Contact)
    /// A rolled die was tapped: Telegram's displayDiceTooltip offers to send the same emoji.
    case diceTapped(emoji: String)
    /// A service row was tapped: open the message its action refers to.
    case openServiceTarget(messageID: Int64)
    /// A changed chat photo in a service row was tapped.
    case openChatPhoto(ChatPhoto)
    case openLocation(location: Location, title: String)
    case submitPollAnswer(messageID: Int64, optionIDs: [Int], submission: MessagePollInteractionStore.Submission)
    /// Telegram's View Votes button and a public poll's result row (requestOpenMessagePollResults): the poll's
    /// voters, opened at the tapped answer.
    case openPollResults(messageID: Int64, optionID: Int?)
    case richContentLayoutChanged
    /// The disc over an uploading photo or video was tapped: delete the sending message, as Telegram does.
    case cancelSending(messageID: Int64)
    /// An inline keyboard button under the message or inside one of its rich message blocks.
    case pressInlineKeyboardButton(InlineKeyboardButtonPress)
    /// The comments bar under a channel post (ChatMessageCommentFooterContentNode.buttonPressed).
    case openComments(messageID: Int64)
    /// A task the user may mark was tapped (requestToggleTodoMessageItem). The store already shows the new state;
    /// a refused or failed request rolls it back.
    case toggleChecklistTask(MessagePollInteractionStore.ChecklistToggle)
    /// A task the user may not mark was tapped (displayTodoToggleUnavailable).
    case checklistToggleUnavailable(messageID: Int64)
    /// A shared story or a story mention was tapped (openChatMessage): the story opens in the viewer, zooming from
    /// `sourceView`, which is round for a mention.
    case openStory(posterChatID: Int64, storyID: Int, sourceView: UIView, sourceIsRound: Bool)

    /// Rolls back the poll vote or checklist toggle an action carries when the chat refuses it.
    @MainActor func rejectPollSubmission(in store: MessagePollInteractionStore?) {
        switch self {
        case .submitPollAnswer(_, _, let submission):
            store?.failSubmission(submission)
        case .toggleChecklistTask(let toggle):
            store?.failChecklistToggle(toggle)
        default:
            break
        }
    }
}

// MARK: - MessagePollInteractionStore

@MainActor final class MessagePollInteractionStore {
    struct Submission: Equatable {
        let messageID: Int64

        fileprivate let id: UUID
    }

    struct State {
        let isSubmitting: Bool
        let pendingSelection: Set<Int>
    }

    /// A checklist task's new done state, shown before TDLib confirms it as Telegram's
    /// requestUpdateTodoMessageItems does.
    struct ChecklistToggle: Equatable {
        let messageID: Int64
        let taskID: Int
        let isDone: Bool

        fileprivate let id: UUID
    }

    private struct Entry {
        var submission: Submission?
        var pendingSelection: Set<Int>
        let sourceSelection: Set<Int>

        var isSubmitting: Bool { submission != nil }
    }

    private struct ChecklistEntry {
        let toggle: ChecklistToggle
        /// The task's done state in the checklist the toggle was made on.
        let sourceIsDone: Bool
    }

    let changes = PassthroughSubject<Int64, Never>()

    /// The quiz whose explanation is open (Telegram's `currentPollMessageWithTooltip`), one at a time.
    private(set) var explanationMessageID: Int64?

    private var entries = [Int64: Entry]()
    private var timeoutWorkItems = [Int64: DispatchWorkItem]()
    private var checklistEntries = [Int64: [Int: ChecklistEntry]]()
    private var checklistTimeouts = [UUID: DispatchWorkItem]()

    func state(messageID: Int64, sourceSelection: Set<Int>) -> State {
        if let entry = entries[messageID], entry.sourceSelection == sourceSelection {
            return State(
                isSubmitting: entry.isSubmitting,
                pendingSelection: entry.pendingSelection,
            )
        }
        timeoutWorkItems.removeValue(forKey: messageID)?.cancel()
        let entry = Entry(
            submission: nil,
            pendingSelection: sourceSelection,
            sourceSelection: sourceSelection,
        )
        entries[messageID] = entry
        return State(isSubmitting: false, pendingSelection: sourceSelection)
    }

    func setPendingSelection(
        _ selection: Set<Int>,
        messageID: Int64,
        sourceSelection: Set<Int>,
    ) {
        var entry = entry(messageID: messageID, sourceSelection: sourceSelection)
        guard !entry.isSubmitting, entry.pendingSelection != selection else { return }
        entry.pendingSelection = selection
        entries[messageID] = entry
        changes.send(messageID)
    }

    @discardableResult func beginSubmission(messageID: Int64, sourceSelection: Set<Int>) -> Submission? {
        var entry = entry(messageID: messageID, sourceSelection: sourceSelection)
        guard !entry.isSubmitting, entry.pendingSelection != sourceSelection else { return nil }
        let submission = Submission(messageID: messageID, id: UUID())
        entry.submission = submission
        entries[messageID] = entry

        let workItem = DispatchWorkItem { [weak self] in
            self?.submissionTimedOut(submission)
        }
        timeoutWorkItems.removeValue(forKey: messageID)?.cancel()
        timeoutWorkItems[messageID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
        changes.send(messageID)
        return submission
    }

    func currentSubmission(messageID: Int64) -> Submission? {
        entries[messageID]?.submission
    }

    func setExplanationVisible(_ visible: Bool, messageID: Int64) {
        let previous = explanationMessageID
        if visible {
            guard previous != messageID else { return }
            explanationMessageID = messageID
            if let previous { changes.send(previous) }
        } else {
            guard previous == messageID else { return }
            explanationMessageID = nil
        }
        changes.send(messageID)
    }

    @discardableResult func failSubmission(_ submission: Submission) -> Bool {
        guard var entry = entries[submission.messageID], entry.submission == submission else { return false }
        timeoutWorkItems.removeValue(forKey: submission.messageID)?.cancel()
        entry.submission = nil
        entries[submission.messageID] = entry
        changes.send(submission.messageID)
        return true
    }

    // MARK: Checklist tasks

    /// The done state a task shows: its pending toggle until TDLib's checklist changes that task, or the request
    /// fails or times out.
    func checklistTaskIsDone(messageID: Int64, taskID: Int, sourceIsDone: Bool) -> Bool {
        guard let entry = checklistEntries[messageID]?[taskID] else { return sourceIsDone }
        guard entry.sourceIsDone == sourceIsDone else {
            removeChecklistEntry(entry.toggle)
            return sourceIsDone
        }
        return entry.toggle.isDone
    }

    /// Flips a task's shown state. A task waits for its request before it toggles again.
    func beginChecklistToggle(messageID: Int64, taskID: Int, sourceIsDone: Bool) -> ChecklistToggle? {
        if let entry = checklistEntries[messageID]?[taskID] {
            guard entry.sourceIsDone != sourceIsDone else { return nil }
            removeChecklistEntry(entry.toggle)
        }
        let toggle = ChecklistToggle(messageID: messageID, taskID: taskID, isDone: !sourceIsDone, id: UUID())
        checklistEntries[messageID, default: [:]][taskID] = ChecklistEntry(toggle: toggle, sourceIsDone: sourceIsDone)
        let workItem = DispatchWorkItem { [weak self] in
            self?.failChecklistToggle(toggle)
        }
        checklistTimeouts[toggle.id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
        changes.send(messageID)
        return toggle
    }

    func isCurrent(_ toggle: ChecklistToggle) -> Bool {
        checklistEntries[toggle.messageID]?[toggle.taskID]?.toggle == toggle
    }

    /// Restores the task's TDLib state. A toggle already replaced or confirmed stays silent.
    @discardableResult func failChecklistToggle(_ toggle: ChecklistToggle) -> Bool {
        guard isCurrent(toggle) else { return false }
        removeChecklistEntry(toggle)
        changes.send(toggle.messageID)
        return true
    }

    private func submissionTimedOut(_ submission: Submission) {
        failSubmission(submission)
    }

    private func entry(messageID: Int64, sourceSelection: Set<Int>) -> Entry {
        if let entry = entries[messageID], entry.sourceSelection == sourceSelection {
            return entry
        }
        timeoutWorkItems.removeValue(forKey: messageID)?.cancel()
        return Entry(
            submission: nil,
            pendingSelection: sourceSelection,
            sourceSelection: sourceSelection,
        )
    }

    private func removeChecklistEntry(_ toggle: ChecklistToggle) {
        checklistTimeouts.removeValue(forKey: toggle.id)?.cancel()
        checklistEntries[toggle.messageID]?[toggle.taskID] = nil
        if checklistEntries[toggle.messageID]?.isEmpty == true {
            checklistEntries[toggle.messageID] = nil
        }
    }
}

#if DEBUG
    extension MessagePollInteractionStore {
        static func runDebugSubmissionProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-poll-submission") else { return }
            let store = MessagePollInteractionStore()
            var notifications = 0
            let observer = store.changes.sink { _ in notifications += 1 }
            var passed = true
            func require(_ value: Bool) { passed = passed && value }
            let messageID = Int64(31)
            let source = Set<Int>()
            store.setPendingSelection([1], messageID: messageID, sourceSelection: source)
            require(store.beginSubmission(messageID: messageID, sourceSelection: source) != nil)
            if let first = store.currentSubmission(messageID: messageID),
               let timeout = store.timeoutWorkItems[messageID]
            {
                require(store.beginSubmission(messageID: messageID, sourceSelection: source) == nil)
                // Run the actual registered deadline before retry, without waiting ten seconds.
                timeout.perform()
                require(!store.state(messageID: messageID, sourceSelection: source).isSubmitting)
                require(store.beginSubmission(messageID: messageID, sourceSelection: source) != nil)
                if let second = store.currentSubmission(messageID: messageID),
                   let secondTimeout = store.timeoutWorkItems[messageID]
                {
                    let previousNotifications = notifications
                    require(!store.failSubmission(first))
                    // An already executing deadline may outlive cancellation of its work item.
                    store.submissionTimedOut(first)
                    require(store.currentSubmission(messageID: messageID) == second)
                    require(store.timeoutWorkItems[messageID] === secondTimeout)
                    require(notifications == previousNotifications)
                    // Authoritative choice resets local submission, including A→B→A.
                    require(!store.state(messageID: messageID, sourceSelection: [1]).isSubmitting)
                    _ = store.state(messageID: messageID, sourceSelection: source)
                    store.setPendingSelection([2], messageID: messageID, sourceSelection: source)
                    require(store.beginSubmission(messageID: messageID, sourceSelection: source) != nil)
                    if let third = store.currentSubmission(messageID: messageID) {
                        require(!store.failSubmission(second))
                        store.submissionTimedOut(second)
                        require(store.currentSubmission(messageID: messageID) == third)
                        require(store.state(messageID: messageID, sourceSelection: source).pendingSelection == [2])
                        require(store.failSubmission(third))
                        require(!store.failSubmission(third))
                        require(store.timeoutWorkItems[messageID] == nil)
                    } else { passed = false }
                } else { passed = false }
            } else { passed = false }
            withExtendedLifetime(observer) {}
            let result = passed
                ? "Poll submission probe passed: production-store/deadline=true; timeout-retry-late-error=fenced; "
                    + "obsolete-timeout/new-deadline=fenced; authoritative-A-B-A=fenced; duplicate-completion=false; "
                    + "pending-selection-preserved; stale-notifications=0; ChatVM-wiring=source-reviewed; server-votes=0"
                : "Poll submission probe failed"
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("poll-submission-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }
    }
#endif

// MARK: - MessageSupplementView

protocol MessageSupplementView where Self: UIView {
    func prepareForReuse()
    func setPlaybackVisible(_ isVisible: Bool)
}

extension MessageSupplementView {
    func setPlaybackVisible(_: Bool) {}
}

// MARK: - MessageStructuredContentView

final class MessageStructuredContentView: UIView {
    private(set) var handlesAlbumCaptions = false

    private var supplementView: (UIView & MessageSupplementView)?

    /// A file or music album's items, top to bottom, each with its caption view if it has a caption.
    var albumCaptionItems: [(messageID: Int64, view: UIView, caption: MessageTextContentView?)] {
        (supplementView as? AttachmentAlbumMessageView)?.captionItems ?? []
    }

    #if DEBUG
        var debugSupplementName: String {
            switch supplementView {
            case is AttachmentAlbumMessageView: "attachmentAlbum"
            case is TelegramFileMessageView: "file"
            case is ContactMessageContentView: "contact"
            case is LocationMessageContentView: "location"
            case is PollMessageContentView: "poll"
            case is DiceMessageContentView: "dice"
            case is StickerGlyphContentView: "stickerGlyph"
            case is ServiceMessageContentView: "service"
            case is ChecklistMessageContentView: "checklist"
            case is GameMessageContentView: "game"
            case is StoryMessageContentView: "story"
            default: "none"
            }
        }

        func debugTapPollOption(_ index: Int) {
            (supplementView as? PollMessageContentView)?.debugTapOption(index)
        }

        func debugSubmitPollSelection() {
            (supplementView as? PollMessageContentView)?.debugSubmitSelection()
        }

        func debugTapChecklistTask(_ index: Int) {
            (supplementView as? ChecklistMessageContentView)?.debugTapTask(index)
        }
    #endif

    @discardableResult func configure(
        presentation: MessageContentPresentation,
        messageID: Int64,
        chatID: Int64 = 0,
        album: [Message],
        client: TDLibClient,
        pollInteractionStore: MessagePollInteractionStore,
        richContentState: MessageRichContentState? = nil,
        textSpoilers: MessageTextSpoilerStore? = nil,
        onAction: @escaping (MessageContentAction) -> Void,
    ) -> Bool {
        prepareForReuse()
        if let albumView = AttachmentAlbumMessageView(
            messages: album,
            client: client,
            textSpoilers: textSpoilers,
            onAction: onAction,
        ) {
            handlesAlbumCaptions = true
            return install(albumView)
        }
        let view: (UIView & MessageSupplementView)? =
            switch presentation.supplement {
            case .animatedEmoji(let emoji, let content):
                StickerGlyphContentView(emoji: emoji, sticker: content.sticker, client: client)
            case .audio(let audio):
                TelegramFileMessageView(audio: audio, client: client, onAction: onAction)
            case .checklist(let checklist):
                ChecklistMessageContentView(
                    messageID: messageID,
                    content: checklist,
                    client: client,
                    interactionStore: pollInteractionStore,
                    onAction: onAction,
                )
            case .contact(let contact):
                ContactMessageContentView(contact: contact, onAction: onAction)
            case .dice(let dice):
                DiceMessageContentView(
                    content: dice,
                    messageID: messageID,
                    chatID: chatID,
                    client: client,
                    onAction: onAction,
                )
            case .document(let document):
                TelegramFileMessageView(document: document, client: client, onAction: onAction)
            case .game(let game):
                GameMessageContentView(game: game, messageID: messageID, client: client, onAction: onAction)
            case .location(let location):
                LocationMessageContentView(content: location, onAction: onAction)
            case .linkPreview(let preview):
                MessageLinkPreviewView(preview: preview, client: client)
            case .none:
                nil
            case .poll(let poll):
                PollMessageContentView(
                    messageID: messageID,
                    content: poll,
                    interactionStore: pollInteractionStore,
                    onAction: onAction,
                )
            case .richMessage(let richMessage):
                MessageRichContentView(
                    content: richMessage, messageID: messageID, chatID: chatID,
                    client: client, state: richContentState ?? MessageRichContentState(), onAction: onAction,
                )
            case .service(let content):
                ServiceMessageContentView(content: content, isUnsupported: false, client: client, onAction: onAction)
            case .story(let story):
                StoryMessageContentView(content: story, chatID: chatID, client: client, onAction: onAction)
            case .unsupported(let content):
                ServiceMessageContentView(content: content, isUnsupported: true)
            }
        guard let view else { return false }
        return install(view)
    }

    func prepareForReuse() {
        supplementView?.prepareForReuse()
        supplementView?.removeFromSuperview()
        supplementView = nil
        handlesAlbumCaptions = false
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        supplementView?.setPlaybackVisible(isVisible)
    }

    private func install(_ view: UIView & MessageSupplementView) -> Bool {
        supplementView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        return true
    }
}

// MARK: - AttachmentAlbumMessageView

private final class AttachmentAlbumMessageView: UIView, MessageSupplementView {
    private let itemViews: [AttachmentAlbumItemView]

    var captionItems: [(messageID: Int64, view: UIView, caption: MessageTextContentView?)] {
        itemViews.map { ($0.messageID, $0, $0.captionView) }
    }

    init?(
        messages: [Message],
        client: TDLibClient,
        textSpoilers: MessageTextSpoilerStore?,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        guard messages.count > 1 else { return nil }
        var itemViews = [AttachmentAlbumItemView]()
        for message in messages {
            switch message.content {
            case .messageAudio(let audio):
                itemViews.append(AttachmentAlbumItemView(
                    messageID: message.id,
                    audio: audio,
                    client: client,
                    spoilerState: textSpoilers?.states[message.id],
                    onAction: onAction,
                ))
            case .messageDocument(let document):
                itemViews.append(AttachmentAlbumItemView(
                    messageID: message.id,
                    document: document,
                    client: client,
                    spoilerState: textSpoilers?.states[message.id],
                    onAction: onAction,
                ))
            default:
                return nil
            }
        }
        self.itemViews = itemViews
        super.init(frame: .zero)
        let stack = UIStackView(arrangedSubviews: itemViews)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        itemViews.forEach { $0.prepareForReuse() }
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        itemViews.forEach { $0.setPlaybackVisible(isVisible) }
    }
}

// MARK: - AttachmentAlbumItemView

private final class AttachmentAlbumItemView: UIView {
    let messageID: Int64
    private(set) var captionView: MessageTextContentView?

    private let fileView: TelegramFileMessageView

    init(
        messageID: Int64,
        audio: MessageAudio,
        client: TDLibClient,
        spoilerState: MessageTextSpoilerState?,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.messageID = messageID
        self.fileView = TelegramFileMessageView(audio: audio.audio, client: client, onAction: onAction)
        super.init(frame: .zero)
        configure(fileView: fileView, caption: audio.caption, client: client, spoilerState: spoilerState)
    }

    init(
        messageID: Int64,
        document: MessageDocument,
        client: TDLibClient,
        spoilerState: MessageTextSpoilerState?,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.messageID = messageID
        self.fileView = TelegramFileMessageView(document: document.document, client: client, onAction: onAction)
        super.init(frame: .zero)
        configure(fileView: fileView, caption: document.caption, client: client, spoilerState: spoilerState)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 { captionView?.setMaximumLayoutWidth(bounds.width) }
    }

    func prepareForReuse() {
        fileView.prepareForReuse()
        captionView?.prepareForReuse()
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        fileView.setPlaybackVisible(isVisible)
        captionView?.setCustomEmojiPlaybackVisible(isVisible)
    }

    private func configure(
        fileView: TelegramFileMessageView, caption: FormattedText, client: TDLibClient,
        spoilerState: MessageTextSpoilerState?,
    ) {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3
        stack.addArrangedSubview(fileView)
        if !caption.text.isEmpty {
            let captionView = MessageTextContentView()
            captionView.configure(
                formattedText: caption, client: client, statusText: "", statusColor: .secondaryLabel,
                spoilerState: spoilerState,
            )
            self.captionView = captionView
            stack.addArrangedSubview(captionView)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

// MARK: - TelegramFileMessageView

final class TelegramFileMessageView: UIView, MessageSupplementView {
    private enum Content {
        case audio(Audio)
        case document(Document)

        var duration: Int {
            if case .audio(let audio) = self { return audio.duration }
            return 0
        }

        var file: File {
            switch self {
            case .audio(let audio): audio.audio
            case .document(let document): document.document
            }
        }

        var subtitle: String {
            switch self {
            case .audio(let audio):
                let performer = audio.performer.trimmingCharacters(in: .whitespacesAndNewlines)
                let duration = TelegramFileMessageView.durationString(audio.duration)
                return performer.isEmpty ? duration : "\(performer) • \(duration)"
            case .document(let document):
                let size = TelegramFileMessageView.fileSizeString(document.document)
                let type = document.mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
                return [size, type].filter { !$0.isEmpty }.joined(separator: " • ")
            }
        }

        var title: String {
            switch self {
            case .audio(let audio):
                for value in [audio.title, audio.fileName, L10n.betterTG("Message.AudioFallback")] {
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
                return L10n.betterTG("Message.AudioFallback")
            case .document(let document):
                let title = document.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? L10n.betterTG("Message.DocumentFallback") : title
            }
        }

        var isAudio: Bool {
            if case .audio = self { return true }
            return false
        }
    }

    private let actionButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let client: TDLibClient
    private let content: Content
    private let onAction: (MessageContentAction) -> Void
    private var representedFile: File
    private var downloadTask: Task<Void, Never>?
    private var fileCancellable: AnyCancellable?
    private var mediaCancellable: AnyCancellable?
    private var requestedCancellation = false

    private var completedLocalPath: String? {
        guard representedFile.local.isDownloadingCompleted,
              !representedFile.local.path.isEmpty,
              FileManager.default.fileExists(atPath: representedFile.local.path)
        else { return nil }
        return representedFile.local.path
    }

    private var downloadProgress: Float {
        let size = max(representedFile.size, representedFile.expectedSize)
        guard size > 0 else { return representedFile.local.isDownloadingCompleted ? 1 : 0 }
        return min(1, max(0, Float(representedFile.local.downloadedSize) / Float(size)))
    }

    private var statusSubtitle: String {
        if let localPath = completedLocalPath, content.isAudio, localPath == Media.shared.savedMediaPath {
            return "\(Self.durationString(Int(Media.shared.currentTime))) / \(Self.durationString(content.duration))"
        }
        if representedFile.local.isDownloadingActive, !representedFile.local.isDownloadingCompleted {
            return "\(Int(downloadProgress * 100))% • \(content.subtitle)"
        }
        return content.subtitle
    }

    init(
        audio: Audio,
        client: TDLibClient,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.client = client
        self.content = .audio(audio)
        self.onAction = onAction
        self.representedFile = audio.audio
        super.init(frame: .zero)
        configureViews()
        observeUpdates()
        refreshCurrentFile()
        render()
    }

    init(
        document: Document,
        client: TDLibClient,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.client = client
        self.content = .document(document)
        self.onAction = onAction
        self.representedFile = document.document
        super.init(frame: .zero)
        configureViews()
        observeUpdates()
        refreshCurrentFile()
        render()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func durationString(_ duration: Int) -> String {
        String(format: "%d:%02d", max(0, duration) / 60, max(0, duration) % 60)
    }

    private static func fileSizeString(_ file: File) -> String {
        let size = max(file.size, file.expectedSize)
        guard size > 0 else { return L10n.telegram("Message.File") }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func prepareForReuse() {
        downloadTask?.cancel()
        downloadTask = nil
        fileCancellable?.cancel()
        fileCancellable = nil
        mediaCancellable?.cancel()
        mediaCancellable = nil
    }

    private func configureViews() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.tintColor = .white
        actionButton.backgroundColor = .systemBlue
        actionButton.layer.cornerRadius = 22
        actionButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
            forImageIn: .normal,
        )
        actionButton.addTarget(self, action: #selector(performPrimaryAction), for: .touchUpInside)
        addSubview(actionButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.adjustsFontForContentSizeCategory = true
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.adjustsFontForContentSizeCategory = true
        addSubview(subtitleLabel)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = .systemBlue
        progressView.trackTintColor = UIColor.tertiaryLabel.withAlphaComponent(0.25)
        addSubview(progressView)

        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 44),
            actionButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            progressView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 5),
            progressView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            progressView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -5),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 238),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])

        isAccessibilityElement = true
        accessibilityTraits = [.button]
    }

    private func observeUpdates() {
        fileCancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { [fileID = representedFile.id] in $0.file.id == fileID }
            .sink { [weak self] update in
                guard let self, TDLib.shared.activeClient.id == client.id else { return }
                representedFile = update.file
                requestedCancellation = false
                render()
            }
        if content.isAudio {
            mediaCancellable = Media.shared
                .objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in DispatchQueue.main.async { self?.render() } }
        }
    }

    private func refreshCurrentFile() {
        let client = client
        let fileID = representedFile.id
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            let file = try? await client.getFile(fileId: fileID)
            guard let self, !Task.isCancelled, let file else { return }
            await MainActor.run {
                guard self.representedFile.id == fileID else { return }
                self.representedFile = file
                self.requestedCancellation = false
                self.render()
            }
        }
    }

    private func render() {
        titleLabel.text = content.title
        subtitleLabel.text = statusSubtitle
        let localPath = completedLocalPath
        let isCurrentAudio = content.isAudio && localPath == Media.shared.savedMediaPath
        let imageName =
            if isCurrentAudio, Media.shared.isPlaying {
                "pause.fill"
            } else if localPath != nil {
                content.isAudio ? "play.fill" : "doc.fill"
            } else if representedFile.local.isDownloadingActive, !requestedCancellation {
                "xmark"
            } else {
                "arrow.down"
            }
        actionButton.setImage(UIImage(systemName: imageName), for: .normal)
        progressView.isHidden = !representedFile.local.isDownloadingActive || representedFile.local
            .isDownloadingCompleted
        progressView.progress = downloadProgress
        accessibilityLabel = "\(content.title), \(statusSubtitle)"
        accessibilityValue = progressView.isHidden
            ? nil
            : L10n.betterTG("Accessibility.PercentDownloaded", Int(downloadProgress * 100))
        accessibilityHint = localPath == nil
            ? L10n.betterTG("Accessibility.DownloadFileHint")
            : (content.isAudio
                ? L10n.betterTG("Accessibility.PlayPauseAudioHint")
                : L10n.betterTG("Accessibility.OpenDocumentHint"))
    }

    @objc private func performPrimaryAction() {
        if let path = completedLocalPath {
            if content.isAudio {
                Media.shared.toggle(with: path, duration: content.duration)
            } else {
                onAction(.openDocument(URL(fileURLWithPath: path)))
            }
            render()
            return
        }
        if representedFile.local.isDownloadingActive, !requestedCancellation {
            requestedCancellation = true
            downloadTask?.cancel()
            downloadTask = nil
            let client = client
            let fileID = representedFile.id
            downloadTask = Task { [weak self] in
                _ = try? await client.cancelDownloadFile(fileId: fileID, onlyIfPending: false)
                let file = try? await client.getFile(fileId: fileID)
                guard let self, !Task.isCancelled, let file else { return }
                await MainActor.run {
                    guard self.representedFile.id == fileID else { return }
                    self.representedFile = file
                    self.requestedCancellation = false
                    self.render()
                }
            }
            render()
            return
        }
        requestedCancellation = false
        let client = client
        let fileID = representedFile.id
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            let file = try? await client.downloadFile(
                fileId: fileID,
                limit: 0,
                offset: 0,
                priority: 16,
                synchronous: false,
            )
            guard let self, !Task.isCancelled, let file else { return }
            await MainActor.run {
                guard self.representedFile.id == fileID else { return }
                self.representedFile = file
                self.render()
            }
        }
    }
}

// MARK: - ContactMessageContentView

private final class ContactMessageContentView: UIControl, MessageSupplementView {
    private let avatarLabel = UILabel()
    private let nameLabel = UILabel()
    private let phoneLabel = UILabel()
    private let buttonSeparator = UIView()
    private let buttonStack = UIStackView()
    private let contact: Contact
    private let onAction: (MessageContentAction) -> Void

    init(contact: Contact, onAction: @escaping (MessageContentAction) -> Void) {
        self.contact = contact
        self.onAction = onAction
        super.init(frame: .zero)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func details(for contact: Contact) -> [String] {
        var values = [String]()
        if !contact.phoneNumber.isEmpty {
            values.append(contact.phoneNumber)
        }
        for rawLine in contact.vcard.split(whereSeparator: \.isNewline) {
            let components = rawLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { continue }
            let key = components[0].uppercased()
            guard key.hasPrefix("TEL") || key.hasPrefix("EMAIL") || key.hasPrefix("ORG") else { continue }
            let value = String(components[1])
                .replacingOccurrences(of: "\\,", with: ",")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !values.contains(value) {
                values.append(value)
            }
        }
        return Array((values.isEmpty ? [L10n.betterTG("Message.TelegramContact")] : values).prefix(5))
    }

    func prepareForReuse() {}

    private func configureViews() {
        let fullName = [contact.firstName, contact.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let displayedName = fullName.isEmpty ? L10n.telegram("Message.Contact") : fullName
        let initials = [contact.firstName.first, contact.lastName.first]
            .compactMap(\.self)
            .map(String.init)
            .joined()

        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarLabel.text = initials.isEmpty ? "•" : initials.uppercased()
        avatarLabel.textAlignment = .center
        avatarLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        avatarLabel.textColor = .white
        avatarLabel.backgroundColor = .systemTeal
        avatarLabel.layer.cornerRadius = 20
        avatarLabel.clipsToBounds = true
        addSubview(avatarLabel)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = displayedName
        nameLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        nameLabel.textColor = .label
        nameLabel.adjustsFontForContentSizeCategory = true
        addSubview(nameLabel)

        phoneLabel.translatesAutoresizingMaskIntoConstraints = false
        phoneLabel.text = Self.details(for: contact).joined(separator: "\n")
        phoneLabel.font = .preferredFont(forTextStyle: .caption1)
        phoneLabel.textColor = .secondaryLabel
        phoneLabel.numberOfLines = 5
        phoneLabel.adjustsFontForContentSizeCategory = true
        addSubview(phoneLabel)

        configureButtons()

        NSLayoutConstraint.activate([
            avatarLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            avatarLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            avatarLabel.widthAnchor.constraint(equalToConstant: 40),
            avatarLabel.heightAnchor.constraint(equalToConstant: 40),
            nameLabel.leadingAnchor.constraint(equalTo: avatarLabel.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            phoneLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            phoneLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            phoneLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            buttonSeparator.topAnchor.constraint(greaterThanOrEqualTo: phoneLabel.bottomAnchor, constant: 8),
            buttonSeparator.topAnchor.constraint(greaterThanOrEqualTo: avatarLabel.bottomAnchor, constant: 8),
            buttonSeparator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            buttonSeparator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            buttonSeparator.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
            buttonStack.topAnchor.constraint(equalTo: buttonSeparator.bottomAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 33),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "\(L10n.telegram("Message.Contact")), \(displayedName), \(phoneLabel.text ?? "")"
        accessibilityHint = L10n.betterTG("Accessibility.OpenContactHint")
    }

    /// ChatMessageContactBubbleContentNode's buttons: MESSAGE for a Telegram user, and ADD, which opens the contact
    /// sheet with its Add Contact action. Without a device address book, a non-Telegram contact gets VIEW CONTACT,
    /// Telegram's title when there is nothing to add or message.
    private func configureButtons() {
        buttonSeparator.translatesAutoresizingMaskIntoConstraints = false
        buttonSeparator.backgroundColor = UIColor.tintColor.withAlphaComponent(0.2)
        addSubview(buttonSeparator)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        addSubview(buttonStack)

        let userID = contact.userId
        let contact = contact
        if userID != 0 {
            buttonStack.addArrangedSubview(button(title: L10n.telegram("Conversation.ContactMessage")) { [weak self] in
                self?.onAction(.messageContact(userID: userID))
            })
        }
        let viewTitle = userID != 0
            ? L10n.telegram("Conversation.ContactAddContact")
            : L10n.telegram("Conversation.ViewContactDetails")
        buttonStack.addArrangedSubview(button(title: viewTitle) { [weak self] in
            self?.onAction(.viewContact(contact))
        })
        // The card is one accessibility element, so its buttons are offered as its actions.
        accessibilityCustomActions = buttonStack.arrangedSubviews.compactMap { view in
            guard let button = view as? UIButton, let title = button.configuration?.attributedTitle else { return nil }
            return UIAccessibilityCustomAction(name: String(title.characters).capitalized) { _ in
                button.sendActions(for: .primaryActionTriggered)
                return true
            }
        }
    }

    private func button(title: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = AttributedString(
            title.uppercased(),
            attributes: AttributeContainer([
                .font: UIFontMetrics(forTextStyle: .footnote).scaledFont(
                    for: .systemFont(ofSize: 14, weight: .semibold),
                    maximumPointSize: 18,
                ),
            ]),
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        configuration.titleLineBreakMode = .byTruncatingTail
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.tintColor = .tintColor
        return button
    }

    @objc private func tapped() {
        onAction(.openContact(contact))
    }
}

// MARK: - LocationMessageContentView

private final class LocationMessageContentView: UIControl, MessageSupplementView {
    private let mapImageView = UIImageView()
    private let markerView = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let content: MessageContentPresentation.LocationContent
    private let onAction: (MessageContentAction) -> Void
    private var snapshotter: MKMapSnapshotter?
    private var generation = UUID()
    private var liveTimer: Timer?

    private var showsMetadata: Bool {
        // Venues always carry an address or coordinates; a plain location has neither.
        content.liveDeadline != nil || content.liveIndefinite || content.subtitle != nil
    }

    init(
        content: MessageContentPresentation.LocationContent,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.content = content
        self.onAction = onAction
        super.init(frame: .zero)
        configureViews()
        configureLiveStatus()
        loadSnapshot()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        liveTimer?.invalidate()
    }

    func prepareForReuse() {
        generation = UUID()
        snapshotter?.cancel()
        snapshotter = nil
        liveTimer?.invalidate()
        liveTimer = nil
        mapImageView.image = nil
    }

    private func configureViews() {
        mapImageView.translatesAutoresizingMaskIntoConstraints = false
        mapImageView.backgroundColor = .tertiarySystemFill
        mapImageView.contentMode = .scaleAspectFill
        mapImageView.clipsToBounds = true
        mapImageView.layer.cornerRadius = 11
        addSubview(mapImageView)

        markerView.translatesAutoresizingMaskIntoConstraints = false
        markerView.tintColor = .systemRed
        markerView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 31, weight: .semibold)
        addSubview(markerView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = content.title
        titleLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isHidden = !showsMetadata
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = content.subtitle
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isHidden = !showsMetadata
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            mapImageView.topAnchor.constraint(equalTo: topAnchor),
            mapImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapImageView.widthAnchor.constraint(greaterThanOrEqualToConstant: 238),
            mapImageView.heightAnchor.constraint(equalTo: mapImageView.widthAnchor, multiplier: 0.5),
            markerView.centerXAnchor.constraint(equalTo: mapImageView.centerXAnchor),
            markerView.centerYAnchor.constraint(equalTo: mapImageView.centerYAnchor, constant: -8),
            markerView.widthAnchor.constraint(equalToConstant: 34),
            markerView.heightAnchor.constraint(equalToConstant: 34),
            titleLabel.topAnchor.constraint(equalTo: mapImageView.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
        if showsMetadata {
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2).isActive = true
        } else {
            mapImageView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = [.button, .image]
        accessibilityLabel = [content.title, content.subtitle].compactMap(\.self).joined(separator: ", ")
        accessibilityHint = L10n.betterTG("Accessibility.OpenLocationHint")
    }

    private func configureLiveStatus() {
        if content.liveIndefinite {
            subtitleLabel.text = L10n.telegram("Message.LiveLocation")
            updateAccessibilityLabel()
            return
        }
        guard content.liveDeadline != nil else { return }
        updateLiveStatus()
        guard let deadline = content.liveDeadline, deadline > Foundation.Date() else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLiveStatus()
        }
        liveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateLiveStatus() {
        guard let liveDeadline = content.liveDeadline else { return }
        let remaining = max(0, Int(ceil(liveDeadline.timeIntervalSinceNow)))
        if remaining == 0 {
            subtitleLabel.text = L10n.betterTG("Message.LiveLocationEnded")
            liveTimer?.invalidate()
            liveTimer = nil
        } else {
            subtitleLabel.text =
                if remaining >= 3600 {
                    L10n.betterTG("Message.LiveForHours", remaining / 3600, (remaining % 3600) / 60)
                } else if remaining >= 60 {
                    L10n.betterTG("Message.LiveForMinutes", remaining / 60, remaining % 60)
                } else {
                    L10n.betterTG("Message.LiveForSeconds", remaining)
                }
        }
        updateAccessibilityLabel()
    }

    private func updateAccessibilityLabel() {
        accessibilityLabel = [content.title, subtitleLabel.text].compactMap(\.self).joined(separator: ", ")
    }

    private func loadSnapshot() {
        let coordinate = CLLocationCoordinate2D(
            latitude: content.location.latitude,
            longitude: content.location.longitude,
        )
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1200,
            longitudinalMeters: 1200,
        )
        options.size = CGSize(width: 280, height: 140)
        options.scale = max(1, Utils.screen.scale)
        options.traitCollection = traitCollection
        let snapshotter = MKMapSnapshotter(options: options)
        let requestGeneration = generation
        self.snapshotter = snapshotter
        snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { [weak self] snapshot, _ in
            guard let image = snapshot?.image else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration else { return }
                self.mapImageView.image = image
                self.snapshotter = nil
            }
        }
    }

    @objc private func tapped() {
        onAction(.openLocation(location: content.location, title: content.title))
    }
}

// MARK: - PollMessageContentView

private final class PollMessageContentView: UIView, MessageSupplementView {
    /// What the button under the answers does.
    private enum FooterAction {
        case vote
        case viewVotes
    }

    private let explanationView = PollExplanationView()
    private let questionLabel = UILabel()
    private let typeLabel = UILabel()
    private let solutionButton = UIButton(type: .system)
    private let optionsStack = UIStackView()
    private let footerLabel = UILabel()
    private let voteButton = UIButton(type: .system)
    private let messageID: Int64
    private let content: MessagePoll
    private let interactionStore: MessagePollInteractionStore
    private let onAction: (MessageContentAction) -> Void
    private var optionViews = [Int: PollOptionContentView]()
    private var currentSelection = Set<Int>()
    private var storeCancellable: AnyCancellable?
    private var questionTopToView: NSLayoutConstraint!
    private var questionTopToExplanation: NSLayoutConstraint!
    private var voteButtonHeight: NSLayoutConstraint!
    private var voteButtonCollapsed: NSLayoutConstraint!

    private var interactionState: MessagePollInteractionStore.State {
        interactionStore.state(messageID: messageID, sourceSelection: currentSelection)
    }

    private var pendingSelection: Set<Int> {
        interactionState.pendingSelection
    }

    private var isQuiz: Bool {
        if case .pollTypeQuiz = content.poll.type { return true }
        return false
    }

    /// Telegram stops taking answers once one is chosen: results replace the choices, and the message menu's
    /// Retract Vote clears the answer.
    private var canOfferVote: Bool {
        !content.poll.isClosed && content.poll.voteRestrictionReason == nil && currentSelection.isEmpty
    }

    private var canVote: Bool {
        canOfferVote
            && !content.poll.options.contains(where: \.isBeingChosen)
            && !interactionState.isSubmitting
    }

    private var showsResults: Bool {
        content.poll.canSeeResults
            && (content.poll.isClosed || !currentSelection.isEmpty || content.poll.voteRestrictionReason != nil)
    }

    private var displayedOptionIndices: [Int] {
        var result = content.poll.optionOrder.filter(content.poll.options.indices.contains)
        result.append(contentsOf: content.poll.options.indices.filter { !result.contains($0) })
        return result
    }

    private var correctOptionIndices: Set<Int> {
        if case .pollTypeQuiz(let quiz) = content.poll.type {
            return Set(quiz.correctOptionIds)
        }
        return []
    }

    private var hasAuthoritativeQuizAnswer: Bool {
        isQuiz && showsResults && !correctOptionIndices.isEmpty
    }

    /// A public poll whose voters TDLib lists now (`canGetVoters`): voted, closed, or the creator's own.
    private var canViewVoters: Bool {
        !content.poll.isAnonymous && content.poll.canGetVoters && content.poll.totalVoterCount > 0
    }

    /// ChatMessagePollOptionNode.resultPressed: a public poll's result row opens the voters of that answer.
    private var resultsOpenVoters: Bool {
        showsResults && canViewVoters && !canVote
    }

    /// ChatMessagePollBubbleContentNode shows the lamp for a quiz's solution once the quiz is answered or closed.
    private var quizExplanation: FormattedText? {
        guard case .pollTypeQuiz(let quiz) = content.poll.type, !quiz.explanation.text.isEmpty,
              content.poll.isClosed || !currentSelection.isEmpty else { return nil }
        return quiz.explanation
    }

    /// ChatMessagePollBubbleContentNode.updateSelection: a multiple-answer poll offers Vote until it is answered,
    /// except to someone who already sees its voters (its creator) with nothing checked. A public poll otherwise
    /// offers View Votes.
    private var footerAction: FooterAction? {
        if content.poll.allowsMultipleAnswers, canOfferVote,
           !canViewVoters || !interactionState.pendingSelection.isEmpty
        {
            return .vote
        }
        return canViewVoters ? .viewVotes : nil
    }

    private var pollTypeText: String {
        if content.poll.isClosed { return L10n.telegram("MessagePoll.LabelClosed") }
        return switch (isQuiz, content.poll.isAnonymous) {
        case (false, true): L10n.telegram("MessagePoll.LabelAnonymous")
        case (false, false): L10n.telegram("MessagePoll.LabelPoll")
        case (true, true): L10n.telegram("MessagePoll.LabelAnonymousQuiz")
        case (true, false): L10n.telegram("MessagePoll.LabelQuiz")
        }
    }

    /// Telegram's voters line: No votes or N votes, and Nobody answered yet or N answered for a quiz.
    private var votersText: String {
        let count = content.poll.totalVoterCount
        if isQuiz {
            return count == 0
                ? L10n.telegram("MessagePoll.QuizNoUsers")
                : L10n.telegramPlural("MessagePoll.QuizCount", count: count)
        }
        return count == 0
            ? L10n.telegram("MessagePoll.NoVotes")
            : L10n.telegramPlural("MessagePoll.VotedCount", count: count)
    }

    private var footerText: String {
        var values = [String]()
        // The voters line gives way to the Vote or View Votes button, as in Telegram.
        if footerAction == nil { values.append(votersText) }
        if let restriction = content.poll.voteRestrictionReason {
            values.append(pollRestrictionText(restriction))
        } else if content.poll.allowsMultipleAnswers, canVote {
            values.append(L10n.betterTG("Poll.SelectMultiple"))
        }
        return values.joined(separator: " • ")
    }

    init(
        messageID: Int64,
        content: MessagePoll,
        interactionStore: MessagePollInteractionStore,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.messageID = messageID
        self.content = content
        self.interactionStore = interactionStore
        self.onAction = onAction
        super.init(frame: .zero)
        self.currentSelection = Set(content.poll.options.indices.filter { content.poll.options[$0].isChosen })
        _ = interactionStore.state(messageID: messageID, sourceSelection: currentSelection)
        configureViews()
        self.storeCancellable = interactionStore.changes
            .filter { $0 == messageID }
            .sink { [weak self] _ in self?.interactionStoreChanged() }
        renderSelection()
        renderExplanation()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        storeCancellable?.cancel()
        storeCancellable = nil
        optionViews.removeAll()
    }

    #if DEBUG
        func debugTapOption(_ index: Int) {
            selectOption(index)
        }

        func debugSubmitSelection() {
            submitSelection()
        }
    #endif

    private func configureViews() {
        explanationView.translatesAutoresizingMaskIntoConstraints = false
        explanationView.isHidden = true
        explanationView.closeButton.addTarget(self, action: #selector(closeExplanationTapped), for: .touchUpInside)
        if let quizExplanation { explanationView.configure(text: quizExplanation) }
        addSubview(explanationView)

        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        questionLabel.attributedText = NSAttributedString(getAttributedString(from: content.poll.question))
        questionLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        questionLabel.textColor = .label
        questionLabel.numberOfLines = 0
        questionLabel.adjustsFontForContentSizeCategory = true
        addSubview(questionLabel)

        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.text = pollTypeText
        typeLabel.font = .preferredFont(forTextStyle: .caption1).withWeight(.semibold)
        typeLabel.textColor = .systemBlue
        typeLabel.adjustsFontForContentSizeCategory = true
        addSubview(typeLabel)

        solutionButton.translatesAutoresizingMaskIntoConstraints = false
        solutionButton.setImage(
            UIImage(systemName: "lightbulb", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15)),
            for: .normal,
        )
        solutionButton.tintColor = .systemBlue
        solutionButton.accessibilityLabel = L10n.telegram("MessagePoll.Explanation")
        solutionButton.addTarget(self, action: #selector(solutionTapped), for: .touchUpInside)
        addSubview(solutionButton)

        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        optionsStack.axis = .vertical
        optionsStack.spacing = 7
        addSubview(optionsStack)

        for index in displayedOptionIndices {
            let optionView = PollOptionContentView()
            optionView.configure(
                option: content.poll.options[index],
                index: index,
                showsResults: showsResults,
                correct: hasAuthoritativeQuizAnswer && correctOptionIndices.contains(index),
                incorrect: hasAuthoritativeQuizAnswer
                    && content.poll.options[index].isChosen
                    && !correctOptionIndices.contains(index),
                enabled: canVote,
                opensVoters: resultsOpenVoters,
                relativeProgress: relativeProgress(for: content.poll.options[index]),
            ) { [weak self] selectedIndex in self?.optionTapped(selectedIndex) }
            optionViews[index] = optionView
            optionsStack.addArrangedSubview(optionView)
        }

        voteButton.translatesAutoresizingMaskIntoConstraints = false
        voteButton.setTitle(L10n.telegram("MessagePoll.SubmitVote"), for: .normal)
        voteButton.titleLabel?.font = .preferredFont(forTextStyle: .callout).withWeight(.semibold)
        voteButton.addTarget(self, action: #selector(voteTapped), for: .touchUpInside)
        voteButtonHeight = voteButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 38)
        voteButtonCollapsed = voteButton.heightAnchor.constraint(equalToConstant: 0)
        addSubview(voteButton)

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .preferredFont(forTextStyle: .caption1)
        footerLabel.textColor = .secondaryLabel
        footerLabel.numberOfLines = 0
        footerLabel.adjustsFontForContentSizeCategory = true
        addSubview(footerLabel)

        questionTopToView = questionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3)
        questionTopToExplanation = questionLabel.topAnchor.constraint(
            equalTo: explanationView.bottomAnchor,
            constant: 8,
        )
        NSLayoutConstraint.activate([
            explanationView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            explanationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            explanationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            questionTopToView,
            questionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            questionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            typeLabel.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 2),
            typeLabel.leadingAnchor.constraint(equalTo: questionLabel.leadingAnchor),
            typeLabel.trailingAnchor.constraint(lessThanOrEqualTo: solutionButton.leadingAnchor, constant: -4),
            solutionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            solutionButton.centerYAnchor.constraint(equalTo: typeLabel.centerYAnchor),
            solutionButton.widthAnchor.constraint(equalToConstant: 32),
            solutionButton.heightAnchor.constraint(equalToConstant: 28),
            optionsStack.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 9),
            optionsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            optionsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            voteButton.topAnchor.constraint(equalTo: optionsStack.bottomAnchor, constant: 4),
            voteButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            voteButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerLabel.topAnchor.constraint(equalTo: voteButton.bottomAnchor, constant: 2),
            footerLabel.leadingAnchor.constraint(equalTo: questionLabel.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: questionLabel.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
    }

    private func relativeProgress(for option: PollOption) -> CGFloat {
        let maximumVoters = content.poll.options.map(\.voterCount).max() ?? 0
        guard maximumVoters > 0 else { return 0 }
        return min(1, max(0, CGFloat(option.voterCount) / CGFloat(maximumVoters)))
    }

    private func selectOption(_ index: Int) {
        guard canVote, content.poll.options.indices.contains(index) else { return }
        var selection = pendingSelection
        if content.poll.allowsMultipleAnswers {
            if selection.contains(index) {
                selection.remove(index)
            } else {
                selection.insert(index)
            }
        } else {
            selection = [index]
        }
        interactionStore.setPendingSelection(
            selection,
            messageID: messageID,
            sourceSelection: currentSelection,
        )
        if !content.poll.allowsMultipleAnswers {
            submitSelection()
        }
    }

    private func optionTapped(_ index: Int) {
        if canVote {
            selectOption(index)
        } else if resultsOpenVoters, content.poll.options.indices.contains(index) {
            onAction(.openPollResults(messageID: messageID, optionID: index))
        }
    }

    /// Returns whether the button under the answers or the footer changed, which changes the poll's height.
    @discardableResult private func renderSelection() -> Bool {
        let state = interactionState
        let opensVoters = resultsOpenVoters
        for (index, view) in optionViews {
            view.isEnabled = canVote || opensVoters
            view.alpha = canVote || showsResults ? 1 : 0.7
            view.setPendingSelected(state.pendingSelection.contains(index))
        }
        let hasSelectionChange = state.pendingSelection != currentSelection
        let action = footerAction
        let showsButton = action != nil
        let previousFooter = footerLabel.text
        let buttonVisibilityChanged = voteButton.isHidden == showsButton
        voteButton.isHidden = !showsButton
        if showsButton {
            voteButtonCollapsed.isActive = false
            voteButtonHeight.isActive = true
        } else {
            voteButtonHeight.isActive = false
            voteButtonCollapsed.isActive = true
        }
        switch action {
        case .vote:
            voteButton.setTitle(L10n.telegram("MessagePoll.SubmitVote"), for: .normal)
            voteButton.isEnabled = hasSelectionChange && canVote
        case .viewVotes:
            voteButton.setTitle(
                L10n.telegram("MessagePoll.ViewVotes", compactNumericCountString(content.poll.totalVoterCount)),
                for: .normal,
            )
            voteButton.isEnabled = !state.isSubmitting
        case nil:
            voteButton.isEnabled = false
        }
        voteButton.alpha = voteButton.isEnabled ? 1 : 0.45
        footerLabel.text = footerText
        return buttonVisibilityChanged || footerLabel.text != previousFooter
    }

    /// Shows the quiz's explanation above the poll while it is open, and the lamp otherwise. Returns whether the
    /// explanation appeared or went away.
    @discardableResult private func renderExplanation() -> Bool {
        let shown = quizExplanation != nil && interactionStore.explanationMessageID == messageID
        solutionButton.isHidden = quizExplanation == nil || shown
        guard shown == explanationView.isHidden else { return false }
        explanationView.isHidden = !shown
        if shown {
            questionTopToView.isActive = false
            questionTopToExplanation.isActive = true
        } else {
            questionTopToExplanation.isActive = false
            questionTopToView.isActive = true
        }
        return true
    }

    private func interactionStoreChanged() {
        let selectionLayoutChanged = renderSelection()
        let explanationLayoutChanged = renderExplanation()
        if selectionLayoutChanged || explanationLayoutChanged { onAction(.richContentLayoutChanged) }
    }

    @objc private func solutionTapped() {
        interactionStore.setExplanationVisible(true, messageID: messageID)
    }

    @objc private func closeExplanationTapped() {
        interactionStore.setExplanationVisible(false, messageID: messageID)
    }

    @objc private func voteTapped() {
        switch footerAction {
        case .vote:
            submitSelection()
        case .viewVotes:
            onAction(.openPollResults(messageID: messageID, optionID: nil))
        case nil:
            break
        }
    }

    private func submitSelection() {
        let selection = pendingSelection
        guard canVote,
              selection != currentSelection,
              let submission = interactionStore.beginSubmission(messageID: messageID, sourceSelection: currentSelection)
        else { return }
        onAction(.submitPollAnswer(messageID: messageID, optionIDs: selection.sorted(), submission: submission))
    }

    private func pollRestrictionText(_ restriction: PollVoteRestrictionReason) -> String {
        switch restriction {
        case .pollVoteRestrictionReasonClosed:
            L10n.betterTG("Poll.RestrictionClosed")
        case .pollVoteRestrictionReasonYetUnsent:
            L10n.betterTG("Poll.RestrictionUnsent")
        case .pollVoteRestrictionReasonScheduled:
            L10n.betterTG("Poll.RestrictionScheduled")
        case .pollVoteRestrictionReasonCountryRestricted:
            L10n.betterTG("Poll.RestrictionCountry")
        case .pollVoteRestrictionReasonMembershipRequired:
            L10n.betterTG("Poll.RestrictionMembership")
        case .pollVoteRestrictionReasonOther:
            L10n.betterTG("Poll.RestrictionOther")
        }
    }
}

// MARK: - PollOptionContentView

private final class PollOptionContentView: UIControl {
    private let progressView = UIView()
    private let selectionView = UIImageView()
    private let textLabel = UILabel()
    private let percentageLabel = UILabel()
    private var index = 0
    private var onTap: ((Int) -> Void)?
    private var relativeProgress = CGFloat.zero
    private var resultImage: UIImage?
    private var resultTint = UIColor.systemBlue
    private var showsResults = false
    private var sourceChosen = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.55).cgColor
        clipsToBounds = true

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        progressView.isUserInteractionEnabled = false
        insertSubview(progressView, at: 0)

        selectionView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.contentMode = .center
        selectionView.tintColor = .systemBlue
        addSubview(selectionView)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.font = .preferredFont(forTextStyle: .subheadline)
        textLabel.textColor = .label
        textLabel.adjustsFontForContentSizeCategory = true
        addSubview(textLabel)

        percentageLabel.translatesAutoresizingMaskIntoConstraints = false
        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentageLabel.textColor = .secondaryLabel
        percentageLabel.textAlignment = .right
        addSubview(percentageLabel)

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            selectionView.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionView.widthAnchor.constraint(equalToConstant: 22),
            selectionView.heightAnchor.constraint(equalToConstant: 22),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            textLabel.leadingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: 7),
            percentageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textLabel.trailingAnchor, constant: 5),
            percentageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            percentageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 42),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        progressView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width * relativeProgress,
            height: bounds.height,
        )
    }

    func configure(
        option: PollOption,
        index: Int,
        showsResults: Bool,
        correct: Bool,
        incorrect: Bool,
        enabled: Bool,
        opensVoters: Bool,
        relativeProgress: CGFloat,
        onTap: @escaping (Int) -> Void,
    ) {
        self.index = index
        self.onTap = onTap
        self.showsResults = showsResults
        sourceChosen = option.isChosen
        textLabel.attributedText = NSAttributedString(getAttributedString(from: option.text))
        percentageLabel.text = showsResults ? "\(option.votePercentage)%" : nil
        percentageLabel.accessibilityValue = String(showsResults ? option.votePercentage : 0)
        self.relativeProgress = showsResults ? min(1, max(0, relativeProgress)) : 0
        progressView.isHidden = !showsResults
        // ChatMessagePollOptionNode: a chosen quiz answer is green or red, the right answer you didn't choose is
        // marked in the poll's color, and other results carry no mark.
        if incorrect {
            resultImage = UIImage(systemName: "xmark.circle.fill")
            resultTint = .systemRed
        } else if option.isChosen {
            resultImage = UIImage(systemName: "checkmark.circle.fill")
            resultTint = correct ? .systemGreen : .systemBlue
        } else if correct {
            resultImage = UIImage(systemName: "checkmark.circle.fill")
            resultTint = .systemBlue
        } else {
            resultImage = showsResults ? nil : UIImage(systemName: "circle")
            resultTint = .systemBlue
        }
        progressView.backgroundColor = (option.isChosen ? resultTint : UIColor.systemBlue).withAlphaComponent(0.12)
        selectionView.image = resultImage
        selectionView.tintColor = resultTint
        isEnabled = enabled || opensVoters
        alpha = enabled || showsResults ? 1 : 0.7
        accessibilityLabel = option.text.text
        accessibilityValue = showsResults ? L10n.betterTG("Accessibility.Percent", Int(option.votePercentage)) : nil
        accessibilityTraits = option.isChosen ? [.button, .selected] : [.button]
        accessibilityHint =
            if enabled {
                L10n.betterTG("Accessibility.SelectPollOptionHint")
            } else if opensVoters {
                L10n.betterTG("Accessibility.OpenPollVotersHint")
            } else {
                nil
            }
        setNeedsLayout()
    }

    func setPendingSelected(_ selected: Bool) {
        if showsResults, !isEnabled || selected == sourceChosen {
            selectionView.image = resultImage
            selectionView.tintColor = resultTint
            accessibilityTraits = sourceChosen ? [.button, .selected] : [.button]
            return
        }
        selectionView.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        selectionView.tintColor = .systemBlue
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }

    @objc private func tapped() {
        onTap?(index)
    }
}

// MARK: - PollExplanationView

/// Telegram's quiz answer block (ChatMessageQuizAnswerBubbleContentNode): Explanation with the solution and a close
/// button, above the poll.
private final class PollExplanationView: UIView {
    let closeButton = UIButton(type: .system)

    private let accentView = UIView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true

        accentView.translatesAutoresizingMaskIntoConstraints = false
        accentView.backgroundColor = .systemBlue
        addSubview(accentView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = L10n.telegram("MessagePoll.Explanation")
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.textColor = .systemBlue
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        addSubview(titleLabel)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.adjustsFontForContentSizeCategory = true
        addSubview(textLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            ),
            for: .normal,
        )
        closeButton.tintColor = .systemBlue
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            accentView.topAnchor.constraint(equalTo: topAnchor),
            accentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentView.widthAnchor.constraint(equalToConstant: 3),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            textLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
        accessibilityElements = [titleLabel, textLabel, closeButton]
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: FormattedText) {
        textLabel.attributedText = NSAttributedString(getAttributedString(from: text))
        textLabel.font = .preferredFont(forTextStyle: .subheadline)
        textLabel.textColor = .label
    }
}

// MARK: - StickerGlyphContentView

private final class StickerGlyphContentView: UIView, MessageSupplementView {
    private let emojiLabel = UILabel()
    private var stickerView: CustomEmojiInlineView?

    init(emoji: String, sticker: Sticker?, client: TDLibClient) {
        super.init(frame: .zero)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.text = emoji
        emojiLabel.textAlignment = .center
        emojiLabel.font = .systemFont(ofSize: 96)
        emojiLabel.adjustsFontSizeToFitWidth = true
        addSubview(emojiLabel)

        if let sticker {
            let stickerView = CustomEmojiInlineView()
            stickerView.translatesAutoresizingMaskIntoConstraints = false
            stickerView.configure(sticker: sticker, client: client)
            addSubview(stickerView)
            self.stickerView = stickerView
            NSLayoutConstraint.activate([
                stickerView.topAnchor.constraint(equalTo: topAnchor),
                stickerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                stickerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                stickerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            emojiLabel.topAnchor.constraint(equalTo: topAnchor),
            emojiLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            emojiLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            emojiLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 184),
            heightAnchor.constraint(equalToConstant: 184),
        ])
        isAccessibilityElement = true
        accessibilityLabel = emoji
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        stickerView?.prepareForReuse()
        stickerView = nil
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        stickerView?.setPlaybackVisible(isVisible)
    }
}

// MARK: - DiceRollPlayback

/// Decides how a die animates. Telegram plays the roll once when a rolling die gets its value and when an incoming
/// result is inserted (ChatMessageAnimatedStickerItemNode.setupItem and animateInsertion), and otherwise shows the
/// roll's last frame. Rows here are rebuilt on every content update, so the roll's start time outlives the view.
@MainActor private enum DiceRollPlayback {
    private struct Key: Hashable {
        let clientID: Int32
        let chatID: Int64
        let messageID: Int64
    }

    /// A result first shown within this window of its message date counts as freshly inserted. An outgoing die
    /// changes its message ID when it's sent, so the rolling-to-value transition is also caught this way.
    private static let freshRollWindow: ClosedRange<TimeInterval> = -30...10
    private static let capacity = 512
    private static var rolling = Set<Key>()
    private static var rollStarts = [Key: CFTimeInterval]()

    static func mode(
        clientID: Int32,
        chatID: Int64,
        messageID: Int64,
        value: Int,
        messageDate: Int,
    ) -> TGSStickerView.PlaybackMode {
        let key = Key(clientID: clientID, chatID: chatID, messageID: messageID)
        guard value > 0 else {
            if rolling.count >= capacity { rolling.removeAll() }
            rolling.insert(key)
            return .loop
        }
        if let start = rollStarts[key] {
            return start.isFinite ? .once(startedAt: start) : .stillEnd
        }
        if rollStarts.count >= capacity { rollStarts.removeAll() }
        let wasRolling = rolling.remove(key) != nil
        let age = Foundation.Date().timeIntervalSince1970 - TimeInterval(messageDate)
        let isFresh = wasRolling || (messageDate > 0 && freshRollWindow.contains(age))
        let start = isFresh ? CACurrentMediaTime() : -.infinity
        rollStarts[key] = start
        return isFresh ? .once(startedAt: start) : .stillEnd
    }
}

// MARK: - DiceMessageContentView

/// Telegram's dice bubble (ManagedDiceAnimationNode, SlotMachineAnimationNode): a rolling die loops its initial
/// state, a result plays or shows the final state that lands on the value, and the slot machine stacks its
/// background, reels and lever. Tapping a rolled die asks the chat to offer sending the same emoji.
private final class DiceMessageContentView: UIControl, MessageSupplementView {
    private let emojiLabel = UILabel()
    private let emoji: String
    private let isRolled: Bool
    private let onAction: (MessageContentAction) -> Void
    private var stickerViews = [TGSStickerView]()
    private var fallbackViews = [CustomEmojiInlineView]()

    init(
        content: MessageContentPresentation.DiceContent,
        messageID: Int64,
        chatID: Int64,
        client: TDLibClient,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.emoji = content.emoji
        self.isRolled = content.value > 0
        self.onAction = onAction
        super.init(frame: .zero)

        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.text = content.emoji
        emojiLabel.textAlignment = .center
        emojiLabel.font = .systemFont(ofSize: 96)
        emojiLabel.adjustsFontSizeToFitWidth = true
        emojiLabel.isHidden = !content.stickers.isEmpty
        addSubview(emojiLabel)
        pin(emojiLabel)

        let mode = DiceRollPlayback.mode(
            clientID: client.id,
            chatID: chatID,
            messageID: messageID,
            value: content.value,
            messageDate: content.messageDate,
        )
        for sticker in content.stickers {
            let layerView: UIView
            if case .stickerFormatTgs = sticker.format {
                let view = TGSStickerView()
                view.configure(
                    file: sticker.sticker,
                    client: client,
                    thumbnail: sticker.thumbnail,
                    displaySize: nil,
                    onTap: nil,
                )
                view.playbackMode = mode
                stickerViews.append(view)
                layerView = view
            } else {
                let view = CustomEmojiInlineView()
                view.configure(sticker: sticker, client: client)
                fallbackViews.append(view)
                layerView = view
            }
            layerView.isUserInteractionEnabled = false
            addSubview(layerView)
            pin(layerView)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 184),
            heightAnchor.constraint(equalToConstant: 184),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = isRolled ? [.image, .button] : [.image]
        accessibilityLabel = isRolled ? L10n.betterTG("Accessibility.DiceValue", emoji, content.value) : emoji
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        stickerViews.forEach { $0.prepareForReuse() }
        fallbackViews.forEach { $0.prepareForReuse() }
        stickerViews = []
        fallbackViews = []
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        stickerViews.forEach { $0.setPlaybackVisible(isVisible) }
        fallbackViews.forEach { $0.setPlaybackVisible(isVisible) }
    }

    private func pin(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Telegram's displayDiceTooltip returns early until the die has a value.
    @objc private func tapped() {
        guard isRolled else { return }
        onAction(.diceTapped(emoji: emoji))
    }
}

// MARK: - ServiceMessageContentView

private final class ServiceMessageContentView: UIControl, MessageSupplementView {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var photoView: TDImageLoadingView?
    private let content: MessageContentPresentation.ServiceContent
    private let onAction: ((MessageContentAction) -> Void)?

    init(
        content: MessageContentPresentation.ServiceContent,
        isUnsupported: Bool,
        client: TDLibClient? = nil,
        onAction: ((MessageContentAction) -> Void)? = nil,
    ) {
        self.content = content
        self.onAction = onAction
        super.init(frame: .zero)
        backgroundColor = isUnsupported ? .clear : UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        layer.cornerRadius = isUnsupported ? 0 : 11
        layer.cornerCurve = .continuous

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = content.title
        titleLabel.font = isUnsupported
            ? .italicSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
            : .preferredFont(forTextStyle: .caption1).withWeight(.semibold)
        titleLabel.textColor = isUnsupported ? .label : .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = content.detail
        detailLabel.font = .preferredFont(forTextStyle: .caption2)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.isHidden = content.detail == nil
        addSubview(detailLabel)

        // ChatMessageActionBubbleContentNode shows a changed chat photo above the text.
        let titleTop: NSLayoutConstraint
        if let photo = content.photo, let client, !isUnsupported {
            let photoView = TDImageLoadingView()
            photoView.translatesAutoresizingMaskIntoConstraints = false
            photoView.contentMode = .scaleAspectFill
            photoView.clipsToBounds = true
            photoView.layer.cornerRadius = 32
            photoView.isUserInteractionEnabled = true
            photoView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTapped)))
            photoView.load(
                photo: Photo(hasStickers: false, minithumbnail: photo.minithumbnail, sizes: photo.sizes),
                preferredSize: .bCrop,
                maximumPixelSize: 320,
                client: client,
            )
            addSubview(photoView)
            self.photoView = photoView
            NSLayoutConstraint.activate([
                photoView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                photoView.centerXAnchor.constraint(equalTo: centerXAnchor),
                photoView.widthAnchor.constraint(equalToConstant: 64),
                photoView.heightAnchor.constraint(equalToConstant: 64),
            ])
            titleTop = titleLabel.topAnchor.constraint(equalTo: photoView.bottomAnchor, constant: 6)
        } else {
            titleTop = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7)
        }

        NSLayoutConstraint.activate([
            titleTop,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
        isAccessibilityElement = true
        accessibilityLabel = [content.title, content.detail].compactMap(\.self).joined(separator: ", ")
        if content.targetMessageID != nil, !isUnsupported {
            addTarget(self, action: #selector(tapped), for: .touchUpInside)
            accessibilityTraits = .button
        } else if content.photo != nil, !isUnsupported {
            accessibilityTraits = .button
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        if content.targetMessageID != nil {
            tapped()
            return true
        }
        if content.photo != nil {
            photoTapped()
            return true
        }
        return false
    }

    func prepareForReuse() {
        photoView?.cancel()
    }

    /// ChatController's action taps open the message the action refers to.
    @objc private func tapped() {
        guard let messageID = content.targetMessageID else { return }
        onAction?(.openServiceTarget(messageID: messageID))
    }

    @objc private func photoTapped() {
        guard let photo = content.photo else { return }
        onAction?(.openChatPhoto(photo))
    }
}

// MARK: - TelegramContactDetailsViewController

final class TelegramContactDetailsViewController: UIViewController {
    /// Called with the contact's user ID when Send Message is chosen; the presenter dismisses and opens the chat.
    var onSendMessage: ((Int64) -> Void)?

    private let contact: Contact
    private let client: TDLibClient?
    private var addContactButton: UIButton?
    private var contactStateTask: Task<Void, Never>?

    private var displayName: String {
        let value = [contact.firstName, contact.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return value.isEmpty ? L10n.telegram("Message.Contact") : value
    }

    private var contactInitials: String {
        let value = [contact.firstName.first, contact.lastName.first]
            .compactMap(\.self)
            .map(String.init)
            .joined()
            .uppercased()
        return value.isEmpty ? "•" : value
    }

    private var vCardRows: [(key: String, value: String)] {
        contact.vcard
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> (String, String)? in
                let components = rawLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard components.count == 2 else { return nil }
                let rawKey = String(components[0]).uppercased()
                let value = String(components[1])
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\,", with: ",")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                let key: String
                if rawKey.hasPrefix("TEL") {
                    key = L10n.betterTG("Contact.Phone")
                } else if rawKey.hasPrefix("EMAIL") {
                    key = L10n.betterTG("Contact.Email")
                } else if rawKey.hasPrefix("ORG") {
                    key = L10n.betterTG("Contact.Company")
                } else if rawKey.hasPrefix("TITLE") {
                    key = L10n.betterTG("Contact.JobTitle")
                } else if rawKey.hasPrefix("ADR") {
                    key = L10n.betterTG("Contact.Address")
                } else {
                    return nil
                }
                return (key, value.replacingOccurrences(of: ";", with: " "))
            }
    }

    init(contact: Contact, client: TDLibClient? = nil) {
        self.contact = contact
        self.client = client
        super.init(nibName: nil, bundle: nil)
        title = L10n.telegram("Message.Contact")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        contactStateTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        scrollView.addSubview(stack)

        let avatarLabel = UILabel()
        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarLabel.text = contactInitials
        avatarLabel.textAlignment = .center
        avatarLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        avatarLabel.textColor = .white
        avatarLabel.backgroundColor = .systemTeal
        avatarLabel.layer.cornerRadius = 44
        avatarLabel.clipsToBounds = true
        avatarLabel.widthAnchor.constraint(equalToConstant: 88).isActive = true
        avatarLabel.heightAnchor.constraint(equalToConstant: 88).isActive = true

        let avatarContainer = UIView()
        avatarContainer.addSubview(avatarLabel)
        NSLayoutConstraint.activate([
            avatarLabel.topAnchor.constraint(equalTo: avatarContainer.topAnchor, constant: 8),
            avatarLabel.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            avatarLabel.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
        ])
        stack.addArrangedSubview(avatarContainer)

        let nameLabel = UILabel()
        nameLabel.text = displayName
        nameLabel.font = .preferredFont(forTextStyle: .title2).withWeight(.semibold)
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(nameLabel)

        if !contact.phoneNumber.isEmpty {
            let phoneLabel = UILabel()
            phoneLabel.text = contact.phoneNumber
            phoneLabel.font = .preferredFont(forTextStyle: .body)
            phoneLabel.textColor = .secondaryLabel
            phoneLabel.textAlignment = .center
            phoneLabel.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(phoneLabel)
        }

        let actions = UIStackView()
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 10
        // DeviceContactInfoController's vcard screen: Send Message for a Telegram user, then adding them.
        if contact.userId != 0, client != nil {
            let userID = contact.userId
            actions.addArrangedSubview(actionButton(
                title: L10n.telegram("UserInfo.SendMessage"),
                symbol: "message.fill",
            ) { [weak self] in
                self?.onSendMessage?(userID)
            })
            let addButton = actionButton(
                title: L10n.telegram("UserInfo.AddContact"),
                symbol: "person.crop.circle.badge.plus",
            ) { [weak self] in
                self?.presentAddContact()
            }
            addButton.isHidden = true
            addContactButton = addButton
            actions.addArrangedSubview(addButton)
            loadContactState()
        }
        if !contact.phoneNumber.isEmpty {
            actions
                .addArrangedSubview(actionButton(
                    title: L10n.telegram("Conversation.Call"),
                    symbol: "phone.fill",
                ) { [weak self] in
                    self?.callContact()
                })
            actions.addArrangedSubview(actionButton(
                title: L10n.telegram("Conversation.ContextMenuCopy"),
                symbol: "doc.on.doc",
            ) { [weak self] in
                UIPasteboard.general.string = self?.contact.phoneNumber
            })
        }
        if !actions.arrangedSubviews.isEmpty {
            stack.addArrangedSubview(actions)
        }

        for row in vCardRows.prefix(5) {
            let rowView = UIView()
            let keyLabel = UILabel()
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            keyLabel.text = row.key
            keyLabel.font = .preferredFont(forTextStyle: .caption1).withWeight(.semibold)
            keyLabel.textColor = .secondaryLabel
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)
            rowView.addSubview(keyLabel)

            let valueLabel = UILabel()
            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            valueLabel.text = row.value
            valueLabel.font = .preferredFont(forTextStyle: .body)
            valueLabel.textColor = .label
            valueLabel.numberOfLines = 0
            rowView.addSubview(valueLabel)
            NSLayoutConstraint.activate([
                keyLabel.topAnchor.constraint(equalTo: rowView.topAnchor, constant: 8),
                keyLabel.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 12),
                keyLabel.widthAnchor.constraint(equalToConstant: 64),
                valueLabel.topAnchor.constraint(equalTo: rowView.topAnchor, constant: 8),
                valueLabel.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 8),
                valueLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -12),
                valueLabel.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -8),
            ])
            rowView.backgroundColor = .secondarySystemBackground
            rowView.layer.cornerRadius = 12
            stack.addArrangedSubview(rowView)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func actionButton(title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.cornerStyle = .medium
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
        return button
    }

    private func callContact() {
        let digits = contact.phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    /// Add Contact shows only for a user who isn't already in this account's contacts.
    private func loadContactState() {
        guard let client else { return }
        let userID = contact.userId
        contactStateTask = Task { [weak self] in
            let user = try? await client.getUser(userId: userID)
            guard !Task.isCancelled, let self, TDLib.shared.activeClient.id == client.id, let user else { return }
            addContactButton?.isHidden = user.isContact
        }
    }

    /// Telegram's New Contact step, reduced to the name: the user is added to this account's contacts without
    /// sharing the phone number.
    private func presentAddContact() {
        guard let client, presentedViewController == nil else { return }
        let alert = UIAlertController(title: L10n.telegram("AddContact.Title"), message: nil, preferredStyle: .alert)
        alert.addTextField { [contact] field in
            field.placeholder = L10n.telegram("UserInfo.FirstNamePlaceholder")
            field.text = contact.firstName
            field.autocapitalizationType = .words
        }
        alert.addTextField { [contact] field in
            field.placeholder = L10n.telegram("UserInfo.LastNamePlaceholder")
            field.text = contact.lastName
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        let create = UIAlertAction(title: L10n.telegram("Compose.Create"), style: .default) { [
            weak self,
            weak alert,
        ] _ in
            let firstName = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lastName = alert?.textFields?.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.addContact(client: client, firstName: firstName, lastName: lastName)
        }
        alert.addAction(create)
        alert.preferredAction = create
        present(alert, animated: true)
    }

    private func addContact(client: TDLibClient, firstName: String, lastName: String) {
        guard !firstName.isEmpty || !lastName.isEmpty else { return }
        let userID = contact.userId
        let phoneNumber = contact.phoneNumber
        addContactButton?.isEnabled = false
        Task { [weak self] in
            do {
                _ = try await client.addContact(
                    contact: ImportedContact(
                        firstName: firstName,
                        lastName: lastName,
                        note: FormattedText(entities: [], text: ""),
                        phoneNumber: phoneNumber,
                    ),
                    sharePhoneNumber: false,
                    userId: userID,
                )
                guard let self, TDLib.shared.activeClient.id == client.id else { return }
                addContactButton?.isHidden = true
                let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                TelegramUndoToast.show(
                    text: L10n.telegram("AddContact.StatusSuccess", name),
                    in: view,
                    bottomInset: 8,
                    undo: nil,
                )
            } catch {
                guard let self else { return }
                addContactButton?.isEnabled = true
                let alert = UIAlertController(
                    title: nil,
                    message: L10n.telegram("Login.UnknownError"),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }
}

#if DEBUG
    @MainActor enum MessageContentDebugProbe {
        private final class ProbeViewController: UIViewController {
            let stack = UIStackView()

            override func viewDidLoad() {
                super.viewDidLoad()
                title = "MessageContent Probe"
                view.backgroundColor = .systemBackground
                let scrollView = UIScrollView()
                scrollView.translatesAutoresizingMaskIntoConstraints = false
                scrollView.alwaysBounceVertical = true
                view.addSubview(scrollView)

                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.axis = .vertical
                stack.alignment = .center
                stack.spacing = 14
                scrollView.addSubview(stack)
                NSLayoutConstraint.activate([
                    scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
                    stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
                    stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
                    stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
                ])
            }
        }

        private struct Fixture {
            let album: [Message]
            let content: MessageContent
            let messageID: Int64
            let name: String

            init(name: String, messageID: Int64, content: MessageContent, album: [Message] = []) {
                self.name = name
                self.messageID = messageID
                self.content = content
                self.album = album
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-message-content") else { return }
            Task { @MainActor in
                try? await ProbeFixtures.waitForActiveAccount()
                run(in: window)
            }
        }

        private static func run(in window: UIWindow) {
            let controller = ProbeViewController()
            let navigation = TelegramNavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            guard let presenter = window.rootViewController else { return }
            presenter.present(navigation, animated: false)

            let client = TDLib.shared.activeClient
            let pollInteractionStore = MessagePollInteractionStore()
            let fixtures = makeFixtures()
            var actions = [String]()
            var installedNames = [String]()
            var views = [MessageStructuredContentView]()
            for fixture in fixtures {
                let heading = UILabel()
                heading.text = fixture.name
                heading.font = .preferredFont(forTextStyle: .caption1).withWeight(.semibold)
                heading.textColor = .secondaryLabel
                heading.accessibilityIdentifier = "message-content-heading-\(fixture.name)"
                controller.stack.addArrangedSubview(heading)

                let contentView = MessageStructuredContentView()
                contentView.accessibilityIdentifier = "message-content-\(fixture.name)"
                let installed = contentView.configure(
                    presentation: MessageContentPresentation.make(fixture.content),
                    messageID: fixture.messageID,
                    album: fixture.album,
                    client: client,
                    pollInteractionStore: pollInteractionStore,
                ) { action in
                    switch action {
                    case .richContentLayoutChanged:
                        break
                    case .openContact:
                        actions.append("contact")
                    case .messageContact:
                        actions.append("contact-message")
                    case .viewContact:
                        actions.append("contact-view")
                    case .diceTapped:
                        actions.append("dice")
                    case .openServiceTarget:
                        actions.append("service-target")
                    case .openChatPhoto:
                        actions.append("chat-photo")
                    case .openDocument:
                        actions.append("document")
                    case .openLocation:
                        actions.append("location")
                    case .submitPollAnswer(_, let optionIDs, _):
                        actions.append("poll:\(optionIDs.map(String.init).joined(separator: ","))")
                    case .openPollResults:
                        actions.append("poll-results")
                    case .cancelSending:
                        actions.append("cancel")
                    case .pressInlineKeyboardButton:
                        actions.append("button")
                    case .openComments:
                        actions.append("comments")
                    case .toggleChecklistTask(let toggle):
                        actions.append("checklist:\(toggle.taskID):\(toggle.isDone)")
                    case .checklistToggleUnavailable:
                        actions.append("checklist-unavailable")
                    case .openStory:
                        actions.append("story")
                    }
                }
                precondition(installed, "Fixture \(fixture.name) didn't install")
                installedNames.append(contentView.debugSupplementName)
                controller.stack.addArrangedSubview(contentView)
                views.append(contentView)
            }
            controller.view.layoutIfNeeded()

            if let quizIndex = fixtures.firstIndex(where: { $0.name == "quiz" }) {
                views[quizIndex].debugTapPollOption(0)
            }
            if let multiIndex = fixtures.firstIndex(where: { $0.name == "multi-poll" }) {
                views[multiIndex].debugTapPollOption(0)
                views[multiIndex].debugTapPollOption(1)
                views[multiIndex].debugSubmitPollSelection()
            }
            if let checklistIndex = fixtures.firstIndex(where: { $0.name == "checklist" }) {
                views[checklistIndex].debugTapChecklistTask(1)
                // A second tap waits for the first request.
                views[checklistIndex].debugTapChecklistTask(1)
            }
            if let readOnlyIndex = fixtures.firstIndex(where: { $0.name == "checklist-readonly" }) {
                views[readOnlyIndex].debugTapChecklistTask(0)
            }
            let allSized = views.allSatisfy { view in
                let size = view.systemLayoutSizeFitting(
                    CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .fittingSizeLevel,
                    verticalFittingPriority: .fittingSizeLevel,
                )
                return size.width > 0 && size.height > 0
            }
            let expectedNames = [
                "file", "file", "attachmentAlbum", "contact", "contact", "location", "location",
                "poll", "poll", "dice", "stickerGlyph", "service", "service", "checklist", "checklist", "game",
                "story", "story",
            ]
            let actionProof = actions.contains("poll:0") && actions.contains("poll:0,1")
                && actions.filter { $0 == "checklist:2:true" }.count == 1
                && actions.contains("checklist-unavailable")
            let proof = "MessageContent probe: tdlib=\(MessageContentPresentation.auditedTDLibRevision), "
                + "exhaustive-cases=\(MessageContentPresentation.auditedTDLibCaseCount), "
                + "views=\(installedNames.joined(separator: ",")), sized=\(allSized), "
                + "poll-actions=\(actions.joined(separator: ",")), action-proof=\(actionProof), "
                + "uikit=true, swiftui=false"
            write(proof)
            if installedNames != expectedNames || !allSized || !actionProof {
                assertionFailure(proof)
            }
        }

        private static func makeFixtures() -> [Fixture] {
            let file = probeFile(id: 91)
            let audio = Audio(
                albumCoverMinithumbnail: nil,
                albumCoverThumbnail: nil,
                audio: file,
                duration: 187,
                externalAlbumCovers: [],
                fileName: "probe-audio.ogg",
                mimeType: "audio/ogg",
                performer: "BetterTG",
                title: "Audio attachment",
            )
            let document = Document(
                document: probeFile(id: 92),
                fileName: "parity-report.pdf",
                mimeType: "application/pdf",
                minithumbnail: nil,
                thumbnail: nil,
            )
            let audioMessage = MessageContent.messageAudio(MessageAudio(
                audio: audio,
                caption: FormattedText(entities: [], text: "Audio caption"),
            ))
            let documentMessage = MessageContent.messageDocument(MessageDocument(
                caption: FormattedText(entities: [], text: "Document caption"),
                document: document,
            ))
            let albumMessages = [
                probeMessage(id: 921, content: audioMessage, albumID: 44),
                probeMessage(id: 922, content: documentMessage, albumID: 44),
            ]
            let contact = Contact(
                firstName: "Ada",
                lastName: "Lovelace",
                phoneNumber: "+9955550101",
                userId: 0,
                vcard: "BEGIN:VCARD\nTEL:+9955550101\nEMAIL:ada@example.com\nORG:Analytical Engine\nEND:VCARD",
            )
            let location = Location(horizontalAccuracy: 4, latitude: 41.7151, longitude: 44.8271)
            return [
                Fixture(name: "audio", messageID: 901, content: audioMessage),
                Fixture(name: "document", messageID: 902, content: documentMessage),
                Fixture(name: "attachment-album", messageID: 903, content: audioMessage, album: albumMessages),
                Fixture(name: "contact", messageID: 904, content: .messageContact(MessageContact(contact: contact))),
                Fixture(name: "contact-user", messageID: 914, content: .messageContact(MessageContact(contact: Contact(
                    firstName: contact.firstName,
                    lastName: contact.lastName,
                    phoneNumber: contact.phoneNumber,
                    userId: 777_000,
                    vcard: "",
                )))),
                Fixture(
                    name: "location",
                    messageID: 905,
                    content: .messageLocation(MessageLocation(location: location)),
                ),
                Fixture(name: "live-location", messageID: 906, content: .messageLiveLocation(MessageLiveLocation(
                    expiresIn: 65,
                    location: LiveLocation(
                        heading: 0,
                        livePeriod: 300,
                        location: location,
                        proximityAlertRadius: 0,
                    ),
                ))),
                Fixture(name: "quiz", messageID: 907, content: .messagePoll(makePoll(quiz: true, multiple: false))),
                Fixture(
                    name: "multi-poll",
                    messageID: 908,
                    content: .messagePoll(makePoll(quiz: false, multiple: true)),
                ),
                Fixture(name: "dice", messageID: 909, content: .messageDice(MessageDice(
                    emoji: "🎲",
                    finalState: nil,
                    initialState: nil,
                    successAnimationFrameNumber: 0,
                    value: 6,
                ))),
                Fixture(name: "animated-emoji", messageID: 910, content: .messageAnimatedEmoji(MessageAnimatedEmoji(
                    animatedEmoji: AnimatedEmoji(
                        sticker: nil,
                        stickerWidth: 100,
                        stickerHeight: 100,
                        fitzpatrickType: 0,
                        sound: nil,
                        isRegularEmoji: false,
                    ),
                    emoji: "🎉",
                ))),
                Fixture(
                    name: "service",
                    messageID: 911,
                    content: .messageChatChangeTitle(MessageChatChangeTitle(title: "Parity Chat")),
                ),
                Fixture(name: "unsupported", messageID: 912, content: .messageUnsupported),
                Fixture(
                    name: "checklist",
                    messageID: 913,
                    content: .messageChecklist(MessageChecklist(list: makeChecklist(markable: true))),
                ),
                Fixture(
                    name: "checklist-readonly",
                    messageID: 915,
                    content: .messageChecklist(MessageChecklist(list: makeChecklist(markable: false))),
                ),
                Fixture(name: "game", messageID: 916, content: .messageGame(MessageGame(game: Game(
                    animation: nil,
                    description: "A game without media.",
                    id: 1,
                    photo: Photo(hasStickers: false, minithumbnail: nil, sizes: []),
                    shortName: "probe",
                    text: FormattedText(entities: [], text: ""),
                    title: "Parity Game",
                )))),
                // No poster chat: the story reads as expired without a request.
                Fixture(name: "story", messageID: 917, content: .messageStory(MessageStory(
                    storyId: 1,
                    storyPosterChatId: 0,
                    viaMention: false,
                ))),
                Fixture(name: "story-mention", messageID: 918, content: .messageStory(MessageStory(
                    storyId: 1,
                    storyPosterChatId: 0,
                    viaMention: true,
                ))),
            ]
        }

        /// A group checklist the account may mark, or a personal one it may only read. The first task is done.
        private static func makeChecklist(markable: Bool) -> Checklist {
            Checklist(
                canAddTasks: markable,
                canMarkTasksAsDone: markable,
                othersCanAddTasks: markable,
                othersCanMarkTasksAsDone: markable,
                tasks: [
                    ChecklistTask(
                        completedBy: .messageSenderUser(MessageSenderUser(userId: 777_000)),
                        completionDate: 1,
                        id: 1,
                        text: FormattedText(entities: [], text: "Port the checklist bubble"),
                    ),
                    ChecklistTask(
                        completedBy: nil,
                        completionDate: 0,
                        id: 2,
                        text: FormattedText(entities: [], text: "Mark this task as done"),
                    ),
                ],
                title: FormattedText(entities: [], text: markable ? "Group checklist" : "Read-only checklist"),
            )
        }

        private static func makePoll(quiz: Bool, multiple: Bool) -> MessagePoll {
            let options = [
                PollOption(
                    additionDate: 0,
                    author: nil,
                    id: "first",
                    isBeingChosen: false,
                    isChosen: false,
                    media: nil,
                    recentVoterIds: [],
                    text: FormattedText(entities: [], text: "First answer"),
                    votePercentage: 60,
                    voterCount: 6,
                ),
                PollOption(
                    additionDate: 0,
                    author: nil,
                    id: "second",
                    isBeingChosen: false,
                    isChosen: false,
                    media: nil,
                    recentVoterIds: [],
                    text: FormattedText(entities: [], text: "Second answer"),
                    votePercentage: 40,
                    voterCount: 4,
                ),
            ]
            let type: PollType = quiz
                ? .pollTypeQuiz(PollTypeQuiz(
                    correctOptionIds: [0],
                    explanation: FormattedText(entities: [], text: "Because it is first."),
                    explanationMedia: nil,
                ))
                : .pollTypeRegular
            return MessagePoll(
                canAddOption: false,
                description: FormattedText(entities: [], text: "Poll caption"),
                media: nil,
                poll: Poll(
                    allowsMultipleAnswers: multiple,
                    allowsRevoting: true,
                    canGetVoters: true,
                    canSeeResults: true,
                    closeDate: 0,
                    countryCodes: [],
                    id: 700,
                    isAnonymous: false,
                    isClosed: false,
                    membersOnly: false,
                    openPeriod: 0,
                    optionOrder: [1, 0],
                    options: options,
                    question: FormattedText(entities: [], text: quiz ? "Which answer is correct?" : "Choose answers"),
                    recentVoterIds: [],
                    totalVoterCount: 10,
                    type: type,
                    voteRestrictionReason: nil,
                ),
            )
        }

        private static func probeFile(id: Int) -> File {
            File(
                expectedSize: 1024,
                id: id,
                local: LocalFile(
                    canBeDeleted: false,
                    canBeDownloaded: true,
                    downloadOffset: 0,
                    downloadedPrefixSize: 0,
                    downloadedSize: 0,
                    isDownloadingActive: false,
                    isDownloadingCompleted: false,
                    path: "",
                ),
                remote: RemoteFile(
                    id: "probe-\(id)",
                    isUploadingActive: false,
                    isUploadingCompleted: true,
                    uniqueId: "probe-\(id)",
                    uploadedSize: 1024,
                ),
                size: 1024,
            )
        }

        private static func probeMessage(id: Int64, content: MessageContent, albumID: Int64) -> Message {
            Message(
                authorSignature: "",
                autoDeleteIn: 0,
                canBeSaved: true,
                chatId: 1,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                content: content,
                date: 1,
                editDate: 0,
                effectId: 0,
                ephemeralMessageId: 0,
                factCheck: nil,
                forwardInfo: nil,
                guestBotCallerId: nil,
                hasTimestampedMedia: false,
                id: id,
                importInfo: nil,
                interactionInfo: nil,
                isChannelPost: false,
                isFromOffline: false,
                isOutgoing: false,
                isPaidGramSuggestedPost: false,
                isPaidStarSuggestedPost: false,
                isPinned: false,
                mediaAlbumId: albumID,
                paidMessageStarCount: 0,
                receiverId: nil,
                replyMarkup: nil,
                replyTo: nil,
                restrictionInfo: nil,
                schedulingState: nil,
                selfDestructIn: 0,
                selfDestructType: nil,
                senderBoostCount: 0,
                senderBusinessBotUserId: 0,
                senderId: .messageSenderUser(MessageSenderUser(userId: 1)),
                senderTag: "",
                sendingState: nil,
                suggestedPostInfo: nil,
                summaryLanguageCode: "",
                topicId: nil,
                unreadReactions: [],
                viaBotUserId: 0,

            ephemeralContent: nil,
                chatInstance: 0,
            )
        }

        private static func write(_ proof: String) {
            log(proof)
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            try? proof.write(
                to: documents.appendingPathComponent("message-content-probe.txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }
#endif

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
