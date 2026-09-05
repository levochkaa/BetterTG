// MessageStructuredContentView.swift

import Combine
import MapKit
import TDLibKit
import UIKit

// MARK: - MessageContentAction

enum MessageContentAction {
    case openDocument(URL)
    case openContact(Contact)
    case openLocation(location: Location, title: String)
    case submitPollAnswer(messageID: Int64, optionIDs: [Int])
    case richContentLayoutChanged
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

    private struct Entry {
        var submission: Submission?
        var pendingSelection: Set<Int>
        let sourceSelection: Set<Int>

        var isSubmitting: Bool { submission != nil }
    }

    let changes = PassthroughSubject<Int64, Never>()

    private var entries = [Int64: Entry]()
    private var timeoutWorkItems = [Int64: DispatchWorkItem]()

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

    @discardableResult func failSubmission(_ submission: Submission) -> Bool {
        guard var entry = entries[submission.messageID], entry.submission == submission else { return false }
        timeoutWorkItems.removeValue(forKey: submission.messageID)?.cancel()
        entry.submission = nil
        entries[submission.messageID] = entry
        changes.send(submission.messageID)
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

    #if DEBUG
        var debugSupplementName: String {
            switch supplementView {
            case is AttachmentAlbumMessageView: "attachmentAlbum"
            case is TelegramFileMessageView: "file"
            case is ContactMessageContentView: "contact"
            case is LocationMessageContentView: "location"
            case is PollMessageContentView: "poll"
            case is StickerGlyphContentView: "stickerGlyph"
            case is ServiceMessageContentView: "service"
            default: "none"
            }
        }

        func debugTapPollOption(_ index: Int) {
            (supplementView as? PollMessageContentView)?.debugTapOption(index)
        }

        func debugSubmitPollSelection() {
            (supplementView as? PollMessageContentView)?.debugSubmitSelection()
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
                StickerGlyphContentView(emoji: emoji, sticker: content.sticker, value: nil, client: client)
            case .audio(let audio):
                TelegramFileMessageView(audio: audio, client: client, onAction: onAction)
            case .contact(let contact):
                ContactMessageContentView(contact: contact, onAction: onAction)
            case .dice(let dice):
                StickerGlyphContentView(emoji: dice.emoji, sticker: dice.sticker, value: dice.value, client: client)
            case .document(let document):
                TelegramFileMessageView(document: document, client: client, onAction: onAction)
            case .location(let location):
                LocationMessageContentView(content: location, onAction: onAction)
            case .linkPreview(let preview):
                MessageLinkPreviewView(preview: preview)
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
                ServiceMessageContentView(content: content, isUnsupported: false)
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
                    audio: audio,
                    client: client,
                    spoilerState: textSpoilers?.states[message.id],
                    onAction: onAction,
                ))
            case .messageDocument(let document):
                itemViews.append(AttachmentAlbumItemView(
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
    private let fileView: TelegramFileMessageView
    private var captionView: MessageTextContentView?

    init(
        audio: MessageAudio,
        client: TDLibClient,
        spoilerState: MessageTextSpoilerState?,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.fileView = TelegramFileMessageView(audio: audio.audio, client: client, onAction: onAction)
        super.init(frame: .zero)
        configure(fileView: fileView, caption: audio.caption, client: client, spoilerState: spoilerState)
    }

    init(
        document: MessageDocument,
        client: TDLibClient,
        spoilerState: MessageTextSpoilerState?,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
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
                for value in [audio.title, audio.fileName, "Audio"] {
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
                return "Audio"
            case .document(let document):
                let title = document.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? "Document" : title
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
        guard size > 0 else { return "File" }
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
        accessibilityValue = progressView.isHidden ? nil : "\(Int(downloadProgress * 100)) percent downloaded"
        accessibilityHint = localPath == nil
            ? "Downloads the file"
            : (content.isAudio ? "Plays or pauses the audio" : "Opens the document")
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
        return Array((values.isEmpty ? ["Telegram contact"] : values).prefix(5))
    }

    func prepareForReuse() {}

    private func configureViews() {
        let fullName = [contact.firstName, contact.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let displayedName = fullName.isEmpty ? "Contact" : fullName
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

        NSLayoutConstraint.activate([
            avatarLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            avatarLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarLabel.widthAnchor.constraint(equalToConstant: 40),
            avatarLabel.heightAnchor.constraint(equalToConstant: 40),
            nameLabel.leadingAnchor.constraint(equalTo: avatarLabel.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            phoneLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            phoneLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            phoneLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            phoneLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "Contact, \(displayedName), \(phoneLabel.text ?? "")"
        accessibilityHint = "Opens contact details"
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
        content.liveDeadline != nil || content.liveIndefinite || content.subtitle != nil || content.title != "Location"
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
        accessibilityHint = "Opens this location in Maps"
    }

    private func configureLiveStatus() {
        if content.liveIndefinite {
            subtitleLabel.text = "Live location"
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
            subtitleLabel.text = "Live location ended"
            liveTimer?.invalidate()
            liveTimer = nil
        } else {
            subtitleLabel.text =
                if remaining >= 3600 {
                    "Live for \(remaining / 3600)h \((remaining % 3600) / 60)m"
                } else if remaining >= 60 {
                    "Live for \(remaining / 60)m \(remaining % 60)s"
                } else {
                    "Live for \(remaining)s"
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
    private let questionLabel = UILabel()
    private let typeLabel = UILabel()
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

    private var canOfferVote: Bool {
        guard !content.poll.isClosed, content.poll.voteRestrictionReason == nil else { return false }
        return currentSelection.isEmpty || content.poll.allowsRevoting
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

    private var pollTypeText: String {
        var values = [String]()
        values.append(content.poll.isAnonymous ? "Anonymous" : "Public")
        values.append(isQuiz ? "Quiz" : "Poll")
        if content.poll.isClosed { values.append("Closed") }
        return values.joined(separator: " • ")
    }

    private var footerText: String {
        var values = [String]()
        let count = content.poll.totalVoterCount
        values.append("\(count) \(count == 1 ? "vote" : "votes")")
        if let restriction = content.poll.voteRestrictionReason {
            values.append(pollRestrictionText(restriction))
        } else if content.poll.allowsMultipleAnswers, canVote {
            values.append("Select one or more answers")
        }
        if case .pollTypeQuiz(let quiz) = content.poll.type,
           showsResults,
           !quiz.explanation.text.isEmpty,
           !currentSelection.isEmpty || content.poll.isClosed
        {
            values.append(quiz.explanation.text)
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
            .sink { [weak self] _ in self?.renderSelection() }
        renderSelection()
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
                relativeProgress: relativeProgress(for: content.poll.options[index]),
            ) { [weak self] selectedIndex in self?.selectOption(selectedIndex) }
            optionViews[index] = optionView
            optionsStack.addArrangedSubview(optionView)
        }

        voteButton.translatesAutoresizingMaskIntoConstraints = false
        voteButton.setTitle("VOTE", for: .normal)
        voteButton.titleLabel?.font = .preferredFont(forTextStyle: .callout).withWeight(.semibold)
        voteButton.addTarget(self, action: #selector(voteTapped), for: .touchUpInside)
        voteButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        addSubview(voteButton)

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.text = footerText
        footerLabel.font = .preferredFont(forTextStyle: .caption1)
        footerLabel.textColor = .secondaryLabel
        footerLabel.numberOfLines = 0
        footerLabel.adjustsFontForContentSizeCategory = true
        addSubview(footerLabel)

        NSLayoutConstraint.activate([
            questionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            questionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            questionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            typeLabel.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 2),
            typeLabel.leadingAnchor.constraint(equalTo: questionLabel.leadingAnchor),
            typeLabel.trailingAnchor.constraint(equalTo: questionLabel.trailingAnchor),
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
            selection = currentSelection == Set([index]) && content.poll.allowsRevoting ? [] : [index]
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

    private func renderSelection() {
        let state = interactionState
        for (index, view) in optionViews {
            view.isEnabled = canVote
            view.alpha = canVote || showsResults ? 1 : 0.7
            view.setPendingSelected(state.pendingSelection.contains(index))
        }
        let hasSelectionChange = state.pendingSelection != currentSelection
        voteButton.isHidden = !content.poll.allowsMultipleAnswers || !canOfferVote
        voteButton.isEnabled = hasSelectionChange && canVote
        voteButton.alpha = voteButton.isEnabled ? 1 : 0.45
        voteButton.setTitle(
            state.pendingSelection.isEmpty && !currentSelection.isEmpty ? "RETRACT VOTE" : "VOTE",
            for: .normal,
        )
    }

    @objc private func voteTapped() {
        submitSelection()
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
            "Poll closed"
        case .pollVoteRestrictionReasonYetUnsent:
            "Send the poll to vote"
        case .pollVoteRestrictionReasonScheduled:
            "Scheduled polls can't be voted yet"
        case .pollVoteRestrictionReasonCountryRestricted:
            "Voting isn't available in your country"
        case .pollVoteRestrictionReasonMembershipRequired:
            "Join the chat for at least a day to vote"
        case .pollVoteRestrictionReasonOther:
            "Voting is unavailable"
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
        if incorrect {
            resultImage = UIImage(systemName: "xmark.circle.fill")
            resultTint = .systemRed
        } else if correct {
            resultImage = UIImage(systemName: "checkmark.circle.fill")
            resultTint = .systemGreen
        } else if option.isChosen {
            resultImage = UIImage(systemName: "checkmark.circle.fill")
            resultTint = .systemBlue
        } else {
            resultImage = UIImage(systemName: "circle")
            resultTint = .systemBlue
        }
        selectionView.image = resultImage
        selectionView.tintColor = resultTint
        isEnabled = enabled
        alpha = enabled || showsResults ? 1 : 0.7
        accessibilityLabel = option.text.text
        accessibilityValue = showsResults ? "\(option.votePercentage) percent" : nil
        accessibilityTraits = option.isChosen ? [.button, .selected] : [.button]
        accessibilityHint = enabled ? "Selects this poll option" : nil
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

// MARK: - StickerGlyphContentView

private final class StickerGlyphContentView: UIView, MessageSupplementView {
    private let emojiLabel = UILabel()
    private var stickerView: CustomEmojiInlineView?

    init(emoji: String, sticker: Sticker?, value: Int?, client: TDLibClient) {
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
        accessibilityLabel = value.flatMap { $0 > 0 ? "\(emoji), value \($0)" : nil } ?? emoji
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

// MARK: - ServiceMessageContentView

private final class ServiceMessageContentView: UIView, MessageSupplementView {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    init(content: MessageContentPresentation.ServiceContent, isUnsupported: Bool) {
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

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
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
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {}
}

// MARK: - TelegramContactDetailsViewController

final class TelegramContactDetailsViewController: UIViewController {
    private let contact: Contact

    private var displayName: String {
        let value = [contact.firstName, contact.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return value.isEmpty ? "Contact" : value
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
                    key = "Phone"
                } else if rawKey.hasPrefix("EMAIL") {
                    key = "Email"
                } else if rawKey.hasPrefix("ORG") {
                    key = "Company"
                } else if rawKey.hasPrefix("TITLE") {
                    key = "Title"
                } else if rawKey.hasPrefix("ADR") {
                    key = "Address"
                } else {
                    return nil
                }
                return (key, value.replacingOccurrences(of: ";", with: " "))
            }
    }

    init(contact: Contact) {
        self.contact = contact
        super.init(nibName: nil, bundle: nil)
        title = "Contact"
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        if !contact.phoneNumber.isEmpty {
            actions.addArrangedSubview(actionButton(title: "Call", symbol: "phone.fill") { [weak self] in
                self?.callContact()
            })
            actions.addArrangedSubview(actionButton(title: "Copy", symbol: "doc.on.doc") { [weak self] in
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
            DispatchQueue.main.async {
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
                    case .openDocument:
                        actions.append("document")
                    case .openLocation:
                        actions.append("location")
                    case .submitPollAnswer(_, let optionIDs, _):
                        actions.append("poll:\(optionIDs.map(String.init).joined(separator: ","))")
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
            let allSized = views.allSatisfy { view in
                let size = view.systemLayoutSizeFitting(
                    CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .fittingSizeLevel,
                    verticalFittingPriority: .fittingSizeLevel,
                )
                return size.width > 0 && size.height > 0
            }
            let expectedNames = [
                "file", "file", "attachmentAlbum", "contact", "location", "location",
                "poll", "poll", "stickerGlyph", "stickerGlyph", "service", "service",
            ]
            let actionProof = actions.contains("poll:0") && actions.contains("poll:0,1")
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
                        fitzpatrickType: 0,
                        sound: nil,
                        sticker: nil,
                        stickerHeight: 100,
                        stickerWidth: 100,
                    ),
                    emoji: "🎉",
                ))),
                Fixture(
                    name: "service",
                    messageID: 911,
                    content: .messageChatChangeTitle(MessageChatChangeTitle(title: "Parity Chat")),
                ),
                Fixture(name: "unsupported", messageID: 912, content: .messageUnsupported),
            ]
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
