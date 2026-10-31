// ChatBottomArea.swift

import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - ChatMediaRecordingMode

enum ChatMediaRecordingMode: Equatable {
    case video
    case voice
}

// MARK: - ComposerSendTransitionSnapshot

struct ComposerSendTransitionSnapshot {
    let sourceFrame: CGRect
    let view: UIView
    /// The input's text, which turns into the bubble; the reply panel and media fly in alongside.
    var isText = false
    /// Where the text's first line starts inside `view`.
    var textInset = CGPoint.zero
}

// MARK: - ChatComposerView

final class ChatComposerView: UIView {
    struct ClientViewState {
        let selection: NSRange
        let wasFocused: Bool
        let recordingMode: ChatMediaRecordingMode
    }

    // MARK: Private

    private enum VoiceGestureOutcome {
        case cancel
        case lock
        case send
    }

    /// The modes of ChatTextInputPanelNode's `.input` accessory item (ChatTextInputAccessoryItem.InputMode).
    private enum MediaInputButtonIcon {
        case emoji
        case keyboard
        case stickers
    }

    /// The single line's height: the field's minimum.
    private static let singleLineTextHeight: CGFloat = 36

    private static var floatingGlass: UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }

    // MARK: Internal

    /// Telegram's attach button: the attachment sheet.
    var onOpenAttachments: (() -> Void)?
    /// The media panel's search field: the chat opens the expanded search in this tab.
    var onExpandMediaSearch: ((ComposerMediaPickerViewController.Mode) -> Void)?
    var onPasteImages: (([UIImage]) -> Void)?
    var onInteractionSettled: (() -> Void)?
    var onUserInteraction: (() -> Void)?
    var onNavigateToMessage: ((MessageMetadataNavigationTarget) -> Void)?
    /// Change Recipient in the forward options: reopens the Forward picker for this forward.
    var onChangeForwardRecipient: ((PendingMessageForward) -> Void)?
    /// Telegram's reply panel opens the reply options (ChatMessageActionOptions) from the panel, its source view.
    var onOpenReplyOptions: ((UIView) -> Void)?
    var onVoiceGestureActivityChange: ((Bool) -> Void)?
    var onConfirmVoiceTrimResume: (() -> Void)?
    var onCancelVideoNoteRecording: (() -> Void)?
    var onLockVideoNoteRecording: (() -> Void)?
    var onPauseVideoNoteRecording: (() -> Void)?
    var onRecordMoreVideoNoteRecording: (() -> Void)?
    var onSendVideoNoteRecording: (() -> Void)?
    var onStartVideoNoteRecording: (() async -> Bool)?
    var onToggleVideoNotePreview: (() -> Void)?
    var onUpdateVideoNoteTrim: ((Double, Double, Bool, Bool) -> Void)?
    /// Shows Telegram's tooltip when play-once is turned on.
    var onViewOnceEnabled: ((String) -> Void)?
    /// A reply keyboard button and the message whose keyboard it belongs to.
    var onReplyKeyboardButton: ((TDNativeKeyboardButton, Int64) -> Void)?
    /// Schedule Message (or Set a Reminder) in the send button's menu: the chat shows the date picker.
    var onScheduleMessage: (() -> Void)?
    /// The input panel's scheduled messages button.
    var onOpenScheduledMessages: (() -> Void)?
    /// The input's auto-delete timer; the button is the source for a tooltip.
    var onAutoDeleteTimer: ((UIView) -> Void)?
    /// The Send As avatar was tapped; the chat lists the senders over it.
    var onSendAs: ((UIView) -> Void)?
    /// The menu button of a bot whose menu is a Web App (`botMenuButton == .webView`): the chat opens it.
    var onOpenBotMenuWebApp: ((TDNativeBotMenuButton) -> Void)?
    /// The peek menu of a sticker suggested for the typed emoji, from the chat.
    var suggestedStickerPeekActions: ((Sticker) -> [TelegramContextMenuAction])?
    /// The chat's Send Silently and Schedule Message at the top of a sticker's peek menu in the media panel.
    var stickerPeekSendActions: ((Sticker) -> [TelegramContextMenuAction])?

    /// Where the chat's bar and banners end, for the input to stop under them.
    var topContentLimit: CGFloat = 0 {
        didSet {
            if topContentLimit != oldValue { setNeedsLayout() }
        }
    }

    private var lastLacksRoomForMultilineText = false

    private let chatVM: ChatVM
    /// Above the keyboard the composer is a pill of interactive Liquid Glass; docked at the bottom it has no glass
    /// and stands on the bars' light blur instead.
    private let glassView = UIVisualEffectView(effect: nil)
    private let dockedBackground = TelegramBarBackgroundView(edge: .bottom)

    private var glassLeadingConstraint: NSLayoutConstraint!
    private var glassTrailingConstraint: NSLayoutConstraint!
    private var glassBottomConstraint: NSLayoutConstraint!
    private let rootStack = UIStackView()
    private let replyContainer = UIView()
    private let replyRow = UIStackView()
    private let replySnippet = ReplySnippetView()
    private let closeReplyButton = UIButton(type: .system)
    private let photosScroll = UIScrollView()
    private let photosStack = UIStackView()
    private let documentsScroll = UIScrollView()
    private let documentsStack = UIStackView()
    private let inputRow = UIStackView()
    private let attachmentButton = UIButton(type: .system)
    private let textView = FormattedTextView(placeholder: L10n.telegram("Conversation.InputTextPlaceholder"))
    /// Telegram's input button that switches between a bot's keyboard and the system keyboard.
    private let replyKeyboardButton = UIButton(type: .system)
    /// ChatTextInputPanelNode's scheduled messages accessory, shown while the input is empty.
    private let scheduledMessagesButton = UIButton(type: .system)
    /// ChatTextInputAccessoryItem's `.messageAutoremoveTimeout`: the timer's short interval, or a clock while a secret
    /// chat has none.
    private let autoDeleteButton = UIButton(type: .system)
    /// ChatTextInputAccessoryItem's `.silentPost`: a channel's bell, slashed while posts go out silently.
    private let silentPostButton = UIButton(type: .system)
    private var canPostSilently = false
    /// ChatTextInputPanelNode's `.input` accessory: stickers or emoji open the media panel, the keyboard closes it.
    private let mediaInputButton = UIButton(type: .system)
    private let replyKeyboardResponder = ComposerInputResponder()
    private let replyKeyboardInputView = ReplyKeyboardInputView()
    private let mediaInputResponder = ComposerInputResponder()
    private let actionButton = UIButton(type: .system)
    private let restrictionLabel = UILabel()
    private let botStartButton = UIButton(type: .system)
    /// ChatTextInputPanelNode's menu button: a bot's command list labelled "Menu", or its Web App labelled with the
    /// button's text, while the input is empty.
    private let botMenuButton = UIButton(type: .system)
    private let sendAsButton = ComposerSendAsButton()
    private var botMenuButtonSymbol = "line.3.horizontal"
    /// The input context panel: a bot's commands or an inline bot's results above the input.
    private let suggestionsView = ChatInputSuggestionsView()
    private let recordingRow = UIStackView()
    private lazy var recordingRowHeightConstraint = recordingRow.heightAnchor.constraint(equalToConstant: 36)
    private let cancelRecordingButton = UIButton(type: .system)
    private let recordingPauseResumeButton = UIButton(type: .system)
    private let recordingPreviewPlayButton = UIButton(type: .system)
    private let recordingPreviewContainer = UIView()
    private let recordingPreviewWaveform = TelegramWaveformView()
    private let recordingTrimView = VoiceRecordingTrimView()
    private let videoNoteThumbnailStrip = VideoNoteThumbnailStripView()
    private let recordingLabel = UILabel()
    private let recordingGestureOverlay = RecordingGestureOverlayView()
    private let recordingSendButton = UIButton(type: .system)
    /// Telegram's play-once toggle for a locked or previewed voice recording (ChatRecordingViewOnceButtonNode).
    private let recordingViewOnceButton = UIButton(type: .system)
    private lazy var recordingGestureRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(actionLongPressed(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = 1000
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    /// Telegram's send button opens its send options on a long press (ChatSendMessageContextScreen).
    private lazy var sendOptionsGestureRecognizer = UILongPressGestureRecognizer(
        target: self,
        action: #selector(showSendOptions(_:)),
    )

    private var displayedImageIDs = [UUID]()
    /// The picked items shown hidden with a spoiler, so the strip redraws when the send menu toggles them.
    private var displayedSpoilerImageIDs = Set<UUID>()
    private var displayedDocumentIDs = [UUID]()
    private var contentSizeCategoryObserver: NSObjectProtocol?
    private var draftTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    /// When "typing" was last sent. Telegram sends it on the first keystroke, again while typing goes on (the server
    /// shows it for a few seconds), and cancels it 4 s after the last keystroke.
    private var lastTypingActionDate: Date?
    private var isApplyingState = false
    /// The reply slot shows the link panel, whose × turns the preview off.
    private var showsLinkPreviewPanel = false
    private var hiddenForSearch = false
    private var keyboardAttached = false
    private var lastReplyID: Int64?
    private var lastEditID: Int64?
    private var replyContainerHeightConstraint: NSLayoutConstraint!
    private var documentsScrollHeightConstraint: NSLayoutConstraint!
    private var replyPreviewVisible = false
    private var voiceGestureStartPoint = CGPoint.zero
    private var voiceGestureLastPoint = CGPoint.zero
    private var voiceGestureLastTimestamp = TimeInterval.zero
    private var voiceGestureTranslation = CGPoint.zero
    private var voiceGestureVelocity = CGPoint.zero
    private var pendingVoiceGestureOutcome: VoiceGestureOutcome?
    private var voiceGestureFinished = false
    private var voiceGestureIsArmed = false
    private var recordingStartInFlight = false
    private var voiceGestureIsTracking = false
    private var voiceGestureGeneration = 0
    private var voiceGestureArmTask: Task<Void, Never>?
    private var voiceGestureSuppressesButtonAction = false
    private var voiceGestureDeferralActive = false
    private var voiceGestureContactEnded = false
    private var voiceGestureAwaitingPrearmLock = false
    private var voiceGestureIgnoresRecognizerSequence = false
    private var activeMediaRecordingMode = ChatMediaRecordingMode.voice
    private var selectedMediaRecordingMode = ChatMediaRecordingMode.voice
    private var videoNoteState = VideoNoteComposerState.idle
    private var videoNoteReplyMessage: CustomMessage?
    private var videoNoteReplyFallback: MessageReplyPresentation?
    private var videoNoteTrimEditing = false
    private var videoNoteTrimSaving = false
    private var replyKeyboardButtonShowsSystemKeyboard: Bool?
    private var mediaInputButtonIcon: MediaInputButtonIcon?
    /// Telegram's input mode icon (AccessoryItemIconButton): its `input_anim_*` Lottie, 32 pt.
    private let mediaInputIcon = TelegramLottieIconView(side: 32)
    /// ChatTextInputMediaRecordingButton's microphone and camera: `anim_micToVideo` and back, 30 pt.
    private let recordModeIcon = TelegramLottieIconView(side: 30)
    private var showsRecordModeIcon = false
    private let sendIcon = ComposerSendIconView()
    private var shownRecordMode: ChatMediaRecordingMode?
    /// The text's slot in the button row: the field lies over it while the text fits beside the buttons, and it
    /// keeps the row's place once the text moves above them.
    private let textSlot = UIView()
    /// Swiftgram's full-width multiline text (`wideGlassTextFieldMultiline`): once the text wraps beside the buttons
    /// it moves above them into this slot and takes the panel's width, the buttons staying in a row below.
    private let multilineTextSlot = UIView()
    /// ChatTextInputPanelNode's expand button: the input fills the space above the keyboard, and collapses again.
    private let expandInputButton = UIButton(type: .system)
    private var compactTextConstraints = [NSLayoutConstraint]()
    private var multilineTextConstraints = [NSLayoutConstraint]()
    private var isMultilineText = false
    /// Return in an empty input opened the multiline layout (`isEmptyMultilineInput`); Backspace in the empty input
    /// or the end of editing closes it.
    private var isEmptyMultilineInput = false
    private var isInputExpanded = false
    private var lastMultilineMeasureWidth: CGFloat = 0
    /// What the media panel may hold, as `update(from:)` last found it: whether the composer takes input at all, text
    /// and stickers or GIFs.
    private var mediaInputIsAvailable = false
    private var mediaInputCanWriteText = false
    private var mediaInputStickersEnabled = false

    var isInputFocused: Bool {
        textView.isFirstResponder
    }

    /// A bot's keyboard stands in for the system keyboard (Telegram's `.inputButtons` input mode).
    var isReplyKeyboardActive: Bool {
        replyKeyboardResponder.isFirstResponder
    }

    /// The attach button, which the attachment sheet grows out of and shrinks back into.
    var attachmentSourceView: UIView? {
        attachmentButton.window != nil && !attachmentButton.isHidden ? attachmentButton : nil
    }

    private var isHoldingVideoNote: Bool {
        if case .holding = videoNoteState { return true }
        return false
    }

    private var isVideoNoteBusy: Bool {
        switch videoNoteState {
        case .preparing,
             .sending,
             .stopping:
            true
        case .failed,
             .holding,
             .idle,
             .locked,
             .preview:
            false
        }
    }

    /// In landscape over the keyboard there's room for the text only beside the buttons, not above them.
    private var lacksRoomForMultilineText: Bool {
        guard let window else { return false }
        return convert(bounds, to: window).maxY - topContentLimit < 130
    }

    init(chatVM: ChatVM) {
        self.chatVM = chatVM
        super.init(frame: .zero)
        ReplyKeyboardInputView.observeSystemKeyboard()
        configureViews()
        configureActions()
        update(from: chatVM)
        self.contentSizeCategoryObserver = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.updateDocumentsScrollHeight()
        }
    }

    deinit {
        if let contentSizeCategoryObserver {
            NotificationCenter.default.removeObserver(contentSizeCategoryObserver)
        }
        draftTask?.cancel()
        typingTask?.cancel()
        voiceGestureArmTask?.cancel()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextHeightLimit()
        updateRecordingGesturePresentation()
        if abs(lastMultilineMeasureWidth - bounds.width) > 0.5 {
            lastMultilineMeasureWidth = bounds.width
            DispatchQueue.main.async { [weak self] in self?.updateMultilineText(animated: false) }
        }
    }

    static func restorationSelection(_ selection: NSRange, length: Int) -> NSRange {
        let start = min(selection.location, length)
        return NSRange(location: start, length: min(selection.length, length - start))
    }

    /// shortTimeIntervalString: "30s", "5m", "1h", "1d", "1w", "1mo" or "1y".
    static func shortTimeInterval(_ seconds: Int) -> String {
        let (key, count) =
            switch seconds {
            case ..<60: ("MessageTimer.ShortSeconds", max(1, seconds))
            case ..<(60 * 60): ("MessageTimer.ShortMinutes", seconds / 60)
            case ..<(60 * 60 * 24): ("MessageTimer.ShortHours", seconds / (60 * 60))
            case ..<(60 * 60 * 24 * 7): ("MessageTimer.ShortDays", seconds / (60 * 60 * 24))
            case ..<(60 * 60 * 24 * 31): ("MessageTimer.ShortWeeks", seconds / (60 * 60 * 24 * 7))
            case ..<(60 * 60 * 24 * 365): ("MessageTimer.ShortMonths", seconds / (60 * 60 * 24 * 30))
            default: ("MessageTimer.ShortYears", seconds / (60 * 60 * 24 * 365))
            }
        return L10n.telegramPlural(key, count: max(1, count), formattedCount: "\(max(1, count))")
    }

    private static func mentionText(_ mention: ChatMentionSuggestion) -> FormattedText {
        if let username = mention.username, !username.isEmpty {
            return FormattedText(entities: [], text: "@" + username + " ")
        }
        return FormattedText(
            entities: [TextEntity(
                length: (mention.compactTitle as NSString).length,
                offset: 0,
                type: .textEntityTypeMentionName(.init(userId: mention.userID)),
            )],
            text: mention.compactTitle + " ",
        )
    }

    func insertEmoji(_ emoji: String, customID: Int64? = nil) {
        textView.insertEmoji(emoji, customID: customID)
    }

    func clientRestorationState() -> ClientViewState? {
        guard textView.permitsClientRestoration, !voiceGestureIsTracking, !voiceGestureIsArmed,
              voiceGestureArmTask == nil, !videoNoteState.isActive, !videoNoteTrimEditing, !videoNoteTrimSaving
        else { return nil }
        return ClientViewState(
            selection: textView.selectedRange, wasFocused: isInputFocused, recordingMode: selectedMediaRecordingMode,
        )
    }

    func restoreClientViewState(_ state: ClientViewState, focus: Bool) {
        selectedMediaRecordingMode = state.recordingMode
        let length = textView.attributedText.length
        textView.selectedRange = Self.restorationSelection(state.selection, length: length)
        updateActionButton()
        func containsOtherResponder(_ view: UIView) -> Bool {
            view !== textView && view.isFirstResponder || view.subviews.contains(where: containsOtherResponder)
        }
        if focus, state.wasFocused, let window = textView.window, !containsOtherResponder(window) {
            textView.becomeFirstResponder()
        }
    }

    func retireClientView() {
        draftTask?.cancel()
        typingTask?.cancel()
        onInteractionSettled = nil
        onUserInteraction = nil
        onPasteImages = nil
        onReplyKeyboardButton = nil
        if textView.isFirstResponder { textView.resignFirstResponder() }
        if replyKeyboardResponder.isFirstResponder { replyKeyboardResponder.resignFirstResponder() }
        if mediaInputResponder.isFirstResponder { mediaInputResponder.resignFirstResponder() }
    }

    func focusInput() {
        textView.becomeFirstResponder()
    }

    /// Shows the chat's offered keyboard in place of the system keyboard; false when there's none to show.
    @discardableResult func showReplyKeyboard() -> Bool {
        guard window != nil, !hiddenForSearch, chatVM.canWriteBasicMessages, chatVM.editCustomMessage == nil,
              configureReplyKeyboardInputView() else { return false }
        return replyKeyboardResponder.isFirstResponder || replyKeyboardResponder.becomeFirstResponder()
    }

    /// Telegram's `.media` input mode: the emoji, sticker and GIF panel in place of the system keyboard, opened on
    /// the given tab; false when the composer can't take it.
    @discardableResult func showMediaInput(mode: ComposerMediaPickerViewController.Mode) -> Bool {
        guard window != nil, !hiddenForSearch, mediaInputIsAvailable, chatVM.locationContextIsCurrent,
              let picker = makeMediaInputPicker(mode: mode) else { return false }
        let containerSize = window?.bounds.size ?? bounds.size
        let height = ReplyKeyboardInputView.standardHeight(
            containerSize: containerSize,
            bottomInset: window?.safeAreaInsets.bottom ?? 0,
        )
        mediaInputResponder.keyboardInputViewController = ComposerMediaInputViewController(
            picker: picker,
            size: CGSize(width: containerSize.width, height: height),
        )
        if mediaInputResponder.isFirstResponder {
            mediaInputResponder.reloadInputViews()
            return true
        }
        return mediaInputResponder.becomeFirstResponder()
    }

    /// The panels in place of the keyboard follow a rotation or a fold, which the system leaves to a self-sizing input
    /// view.
    func inputPanelsWillResize(to size: CGSize) {
        let bottomInset = window?.safeAreaInsets.bottom ?? 0
        if let controller = mediaInputResponder.keyboardInputViewController as? ComposerMediaInputViewController {
            controller.setPanelWidth(size.width)
            controller.setPanelHeight(ReplyKeyboardInputView.standardHeight(
                containerSize: size,
                bottomInset: bottomInset,
            ))
        }
        replyKeyboardInputView.frame.size.width = size.width
        guard let keyboard = chatVM.replyKeyboard.offeredKeyboard else { return }
        let messageID = keyboard.messageID
        replyKeyboardInputView.configure(keyboard: keyboard, containerSize: size, bottomInset: bottomInset) {
            [weak self] button in
            self?.onReplyKeyboardButton?(button, messageID)
        }
    }

    func makeSendTransitionSnapshots(
        kind: ComposerSendTransitionKind,
        in container: UIView,
    ) -> [ComposerSendTransitionSnapshot] {
        var sources = [UIView]()
        if !replyContainer.isHidden, replyContainer.alpha > 0.01 {
            sources.append(replyContainer)
        }
        switch kind {
        case .media:
            if !photosScroll.isHidden {
                sources.append(photosScroll)
            }
            if !documentsScroll.isHidden {
                sources.append(documentsScroll)
            }
            if !textView.text.isEmpty {
                sources.append(textView)
            }
        case .text:
            sources.append(textView)
        case .videoNote,
             .voiceNote:
            if !recordingRow.isHidden {
                sources.append(recordingRow)
            } else if !actionButton.isHidden {
                sources.append(actionButton)
            }
        }
        return sources.compactMap { source in
            guard source.window != nil, !source.bounds.isEmpty else { return nil }
            let isText = source === textView
            let snapshot: UIView
            if isText {
                snapshot = textView.makeSendTransitionView()
            } else {
                guard let captured = source.snapshotView(afterScreenUpdates: false) else { return nil }
                snapshot = captured
            }
            snapshot.isUserInteractionEnabled = false
            return ComposerSendTransitionSnapshot(
                sourceFrame: source.convert(source.bounds, to: container),
                view: snapshot,
                isText: isText,
                textInset: isText
                    ? CGPoint(
                        x: textView.textContainerInset.left - textView.contentOffset.x,
                        y: textView.textContainerInset.top - textView.contentOffset.y,
                    )
                    : .zero,
            )
        }
    }

    func cancelActiveRecordingGesture(preservingVoiceDraft: Bool = false) {
        voiceGestureGeneration &+= 1
        voiceGestureArmTask?.cancel()
        voiceGestureArmTask = nil
        if preservingVoiceDraft {
            chatVM.suspendVoiceRecording()
        }
        if chatVM.recordingVoiceNote, !preservingVoiceDraft {
            chatVM.cancelVoiceRecording()
        } else if activeMediaRecordingMode == .video, videoNoteState.isActive {
            onCancelVideoNoteRecording?()
        }
        finishVoiceGestureAfterExternalStop()
    }

    func updateVideoNoteState(_ state: VideoNoteComposerState) {
        let wasActive = videoNoteState.isActive
        videoNoteState = state
        if wasActive, !state.isActive, voiceGestureIsArmed {
            finishVoiceGestureAfterExternalStop()
        }
        update(from: chatVM)
    }

    func updateVideoNotePreview(
        draft: VideoNoteRecordingDraft,
        thumbnails: [VideoNoteThumbnailSample],
    ) {
        videoNoteTrimEditing = false
        videoNoteTrimSaving = false
        videoNoteThumbnailStrip.update(
            samples: thumbnails,
            segmentIDs: draft.segments.map(\.id),
            duration: draft.totalDuration,
            range: draft.effectiveRange,
            editingEnabled: true,
        )
        updateRecordingStatus()
    }

    func updateVideoNoteThumbnails(
        _ thumbnails: [VideoNoteThumbnailSample],
        segmentIDs: [UUID],
    ) {
        videoNoteThumbnailStrip.updateImages(
            samples: thumbnails,
            segmentIDs: segmentIDs,
        )
    }

    func setVideoNoteReplyContext(
        message: CustomMessage?,
        input: InputMessageReplyTo?,
    ) {
        videoNoteReplyMessage = message
        videoNoteReplyFallback = message == nil
            ? input.map { MessageReplyPresentation.fallback(for: $0, currentChatID: chatVM.chatID) }
            : nil
        update(from: chatVM)
    }

    func setKeyboardAttached(_ attached: Bool, animated: Bool) {
        guard keyboardAttached != attached else { return }
        keyboardAttached = attached
        // Move the docked glass rim past the screen edges; keep its top edge visible.
        glassLeadingConstraint.constant = attached ? 0 : -16
        glassTrailingConstraint.constant = attached ? 0 : 16
        glassBottomConstraint.constant = attached ? 0 : 16
        // The glass materializes as the bar's blur fades, in the keyboard's 0.25 s, so the composer never jumps.
        let surface = {
            self.dockedBackground.alpha = attached ? 0 : 1
            self.glassView.effect = attached ? Self.floatingGlass : nil
        }
        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction],
                animations: surface,
            )
        } else {
            surface()
        }
        let radius: CGFloat = attached ? 22 : 0
        for target in [layer, glassView.layer] {
            let previous = target.presentation()?.cornerRadius ?? target.cornerRadius
            target.cornerRadius = radius
            guard animated else {
                target.removeAnimation(forKey: "composerCornerRadius")
                continue
            }
            let animation = CABasicAnimation(keyPath: "cornerRadius")
            animation.fromValue = previous
            animation.toValue = radius
            animation.duration = 0.25
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            target.add(animation, forKey: "composerCornerRadius")
        }
    }

    func setHiddenForSearch(_ hidden: Bool) {
        hiddenForSearch = hidden
        if hidden {
            textView.resignFirstResponder()
            replyKeyboardResponder.resignFirstResponder()
            mediaInputResponder.resignFirstResponder()
        } else {
            isHidden = false
            alpha = 0
            transform = CGAffineTransform(translationX: 0, y: max(bounds.height, 72) + 12)
        }
        isUserInteractionEnabled = !hidden
        UIView.animate(
            withDuration: hidden ? 0.28 : 0.24,
            delay: 0,
            usingSpringWithDamping: hidden ? 1 : 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
        ) {
            self.alpha = hidden ? 0 : 1
            self.transform = hidden
                ? CGAffineTransform(translationX: 0, y: max(self.bounds.height, 72) + 12)
                : .identity
        } completion: { _ in
            if self.hiddenForSearch == hidden {
                self.isHidden = hidden
            }
        }
    }

    func update(from chatVM: ChatVM) {
        isApplyingState = true
        // A reply the bot's keyboard set up keeps the bot keyboard up instead of raising the system one.
        let replyID = chatVM.replyMessage?.id
        let replyFocuses = lastReplyID != replyID
            && !(replyID.map { chatVM.replyKeyboard.takeUnfocusedReply($0) } ?? false)
        let shouldFocus = replyFocuses || lastEditID != chatVM.editCustomMessage?.id
        let beginsEditing = chatVM.editCustomMessage != nil && lastEditID != chatVM.editCustomMessage?.id
        lastReplyID = chatVM.replyMessage?.id
        lastEditID = chatVM.editCustomMessage?.id
        let targetText = chatVM.editCustomMessage == nil ? chatVM.text : chatVM.editMessageText
        // A bot link's Start, or a new bot chat's, replaces the input until it's sent (ChatTextInputPanelNode).
        let showsBotStart = chatVM.showsBotStart
        let canWrite = (chatVM.canWriteAnyMessage || chatVM.pendingForward != nil) && !showsBotStart
        let canWriteText = chatVM.canWriteBasicMessages
        textView.isEditable = canWriteText
        textView.isSelectable = canWriteText
        textView.alpha = canWriteText ? 1 : 0.5
        let canAttach = chatVM.canAttachPhotos
            || chatVM.canAttachVideos
            || chatVM.canAttachDocuments
            || chatVM.canSendStickersAndAnimations
            || chatVM.canWriteBasicMessages
            || chatVM.canCreatePoll
            || chatVM.canCreateChecklist
        attachmentButton.isHidden = !canAttach
        attachmentButton.isEnabled = canAttach
        if selectedMediaRecordingMode == .voice,
           !chatVM.canRecordVoiceNote,
           chatVM.canRecordVideoNote
        {
            selectedMediaRecordingMode = .video
        } else if selectedMediaRecordingMode == .video,
                  !chatVM.canRecordVideoNote,
                  chatVM.canRecordVoiceNote
        {
            selectedMediaRecordingMode = .voice
        }
        textView.setPlaceholder(chatVM.composerPlaceholder)
        canPostSilently = chatVM.isBroadcastChannel && canWrite && canWriteText
        textView.customEmojiClient = chatVM.client
        let previousText = textView.text
        textView.setAttributedText(targetText)
        let replacedText = textView.text != previousText
        // ChatTextInputPanelNode's contextPlaceholder: an inline bot's placeholder follows "@bot " inside the input.
        textView.setContextPlaceholder(
            canWrite && canWriteText ? chatVM.inlineBotPlaceholder : nil,
            after: targetText.string,
        )
        // Telegram builds the edit state with ChatTextInputState(inputText:), whose selection is after the text.
        if beginsEditing { textView.moveCaretToEnd() }

        let showsReplyPreview: Bool
        showsLinkPreviewPanel = false
        if chatVM.editCustomMessage != nil, let preview = chatVM.visibleComposerLinkPreview {
            // ChatInterfaceStateAccessoryPanels: an edited text's link preview takes the edit panel's place.
            showsReplyPreview = true
            configureLinkPreviewPanel(preview)
        } else if let edited = chatVM.editCustomMessage {
            showsReplyPreview = true
            closeReplyButton.isHidden = false
            replySnippet.configure(
                title: L10n.telegram("Conversation.EditingMessagePanelTitle"),
                message: edited.message,
            ) { [weak self] in
                guard let self else { return }
                onNavigateToMessage?(navigationTarget(for: edited))
            }
        } else if videoNoteState.isActive, let videoNoteReplyMessage {
            showsReplyPreview = true
            closeReplyButton.isHidden = true
            replySnippet.configure(
                title: L10n.betterTG(
                    "Composer.VideoReplyTo",
                    replyAuthorName(for: videoNoteReplyMessage) ?? L10n.betterTG("Message.Generic"),
                ),
                message: videoNoteReplyMessage.message,
            ) { [weak self] in
                guard let self else { return }
                onNavigateToMessage?(navigationTarget(for: videoNoteReplyMessage))
            }
        } else if videoNoteState.isActive, let videoNoteReplyFallback {
            showsReplyPreview = true
            closeReplyButton.isHidden = true
            replySnippet
                .configure(
                    presentation: videoNoteReplyFallback,
                    expanded: false,
                    client: chatVM.client,
                ) { [weak self] _ in
                    guard let self, let target = videoNoteReplyFallback.navigationTarget else { return }
                    onNavigateToMessage?(target)
                }
        } else if targetText.characters.isEmpty,
                  let pendingReplyID = chatVM.pendingVideoReplyMessageID,
                  chatVM.hasPendingVideoNote
        {
            showsReplyPreview = true
            closeReplyButton.isHidden = true
            if let pendingReply = chatVM.pendingVideoReplyMessage {
                replySnippet.configure(
                    title: L10n.betterTG(
                        "Composer.VideoReplyTo",
                        replyAuthorName(for: pendingReply) ?? L10n.betterTG("Message.Generic"),
                    ),
                    message: pendingReply.message,
                ) { [weak self] in
                    guard let self else { return }
                    onNavigateToMessage?(navigationTarget(for: pendingReply))
                }
            } else {
                replySnippet.configure(
                    title: L10n.betterTG("Composer.VideoReply"),
                    text: L10n.betterTG("Composer.OriginalRepliedMessage"),
                ) { [weak self] in
                    guard let self else { return }
                    onNavigateToMessage?(
                        chatVM.pendingVideoReplyNavigationTarget
                            ?? .message(chatID: chatVM.chatID, messageID: pendingReplyID, quote: nil),
                    )
                }
            }
        } else if targetText.characters.isEmpty,
                  let pendingReplyID = chatVM.pendingVoiceReplyMessageID,
                  chatVM.hasPendingVoiceNote || chatVM.finalizingVoiceNote || chatVM.recordingVoiceNote
        {
            showsReplyPreview = true
            closeReplyButton.isHidden = true
            if let pendingReply = chatVM.pendingVoiceReplyMessage {
                replySnippet.configure(
                    title: L10n.betterTG(
                        "Composer.VoiceReplyTo",
                        replyAuthorName(for: pendingReply) ?? L10n.betterTG("Message.Generic"),
                    ),
                    message: pendingReply.message,
                ) { [weak self] in
                    guard let self else { return }
                    onNavigateToMessage?(navigationTarget(for: pendingReply))
                }
            } else {
                replySnippet.configure(
                    title: L10n.betterTG("Composer.VoiceReply"),
                    text: L10n.betterTG("Composer.OriginalRepliedMessage"),
                ) { [weak self] in
                    guard let self else { return }
                    onNavigateToMessage?(
                        chatVM.pendingVoiceReplyNavigationTarget
                            ?? .message(chatID: chatVM.chatID, messageID: pendingReplyID, quote: nil),
                    )
                }
            }
        } else if let preview = chatVM.visibleComposerLinkPreview {
            showsReplyPreview = true
            configureLinkPreviewPanel(preview)
        } else if let forward = chatVM.pendingForward {
            showsReplyPreview = true
            closeReplyButton.isHidden = false
            replySnippet.configure(title: forward.title, text: forward.text) { [weak self] in
                self?.showForwardOptions()
            }
        } else if let reply = chatVM.replyMessage {
            showsReplyPreview = true
            closeReplyButton.isHidden = false
            // ChatInputMessageAccessoryPanel: "Reply to" the author, or "Reply to Quote by" them.
            let author = replyAuthorName(for: reply) ?? L10n.betterTG("Message.Generic")
            let title = chatVM.replyQuote == nil
                ? L10n.telegram("Conversation.ReplyMessagePanelTitle", author)
                : L10n.telegram("Chat.ReplyPanel.ReplyToQuoteBy", author)
            let openReplyOptions = { [weak self] in
                guard let self else { return }
                if let onOpenReplyOptions {
                    onOpenReplyOptions(replySnippet)
                } else {
                    onNavigateToMessage?(navigationTarget(for: reply, quote: chatVM.replyQuote))
                }
            }
            if let quote = chatVM.replyQuote {
                replySnippet.configure(title: title, quote: quote, onTap: openReplyOptions)
            } else if let task = chatVM.replyChecklistTask {
                replySnippet.configure(
                    title: L10n.telegram("Chat.ReplyPanel.ReplyToTodoItem"),
                    checklistTask: task.text,
                    isDone: task.completedBy != nil,
                    onTap: openReplyOptions,
                )
            } else if let reply = chatVM.replyPollOption {
                replySnippet.configure(
                    title: L10n.telegram("Chat.ReplyPanel.ReplyToPollOption"),
                    checklistTask: reply.option.text,
                    isDone: true,
                    isSquare: reply.allowsMultipleAnswers,
                    onTap: openReplyOptions,
                )
            } else {
                replySnippet.configure(title: title, message: reply.message, onTap: openReplyOptions)
            }
        } else if let fallback = chatVM.replyFallbackPresentation {
            showsReplyPreview = true
            closeReplyButton.isHidden = false
            replySnippet.configure(presentation: fallback, expanded: false, client: chatVM.client) { [weak self] _ in
                guard let self, let target = fallback.navigationTarget else { return }
                onNavigateToMessage?(target)
            }
        } else {
            showsReplyPreview = false
            closeReplyButton.isHidden = false
        }
        setReplyPreviewVisible(canWrite && showsReplyPreview, animated: window != nil)

        let imageIDs = chatVM.displayedImages.map(\.id)
        let spoilerImageIDs = Set(chatVM.displayedImages.filter(\.hasSpoiler).map(\.id))
        if displayedImageIDs != imageIDs || displayedSpoilerImageIDs != spoilerImageIDs {
            displayedImageIDs = imageIDs
            displayedSpoilerImageIDs = spoilerImageIDs
            rebuildPhotos()
        }
        let documentIDs = chatVM.displayedDocuments.map(\.id)
        if displayedDocumentIDs != documentIDs {
            displayedDocumentIDs = documentIDs
            rebuildDocuments()
        }
        restrictionLabel.text = chatVM.composerRestrictionText
        restrictionLabel.isHidden = canWrite || showsBotStart
        botStartButton.isHidden = !showsBotStart
        botStartButton.isEnabled = !chatVM.isStartingBot
        if showsBotStart, botStartButton.title(for: .normal) != chatVM.botStartTitle {
            botStartButton.setTitle(chatVM.botStartTitle, for: .normal)
        }
        if showsBotStart, textView.isFirstResponder { textView.resignFirstResponder() }
        let showsBotMenu = chatVM.showsBotMenuButton && canWrite && canWriteText
        botMenuButton.isHidden = !showsBotMenu
        updateSendAsButton(canWrite: canWrite && canWriteText)
        if showsBotMenu { updateBotMenuButton(expanded: targetText.characters.isEmpty) }
        updateSuggestions(enabled: canWrite && canWriteText)
        updateScheduledMessagesButton()
        updateSilentPostButton()
        updateAutoDeleteButton()
        mediaInputCanWriteText = canWriteText
        mediaInputStickersEnabled = chatVM.canSendStickersAndAnimations
        mediaInputIsAvailable = canWrite
            && (chatVM.editCustomMessage != nil || mediaInputCanWriteText || mediaInputStickersEnabled)
        if !mediaInputIsAvailable, mediaInputResponder.isFirstResponder {
            mediaInputResponder.resignFirstResponder()
        }
        updateMediaInputButton()
        let isRecordingVideoNote = videoNoteState.isActive
        let isRecordingMedia = chatVM.recordingVoiceNote || isRecordingVideoNote
        photosScroll.isHidden = !canWrite || chatVM.displayedImages.isEmpty
        documentsScroll.isHidden = !canWrite || chatVM.displayedDocuments.isEmpty
        let showsRecording = canWrite && isRecordingMedia
        if showsRecording, !recordingRowHeightConstraint.isActive {
            recordingRowHeightConstraint.constant = max(
                36,
                inputRow.bounds.height,
                textView.intrinsicContentSize.height,
            )
            recordingRowHeightConstraint.isActive = true
        } else if !showsRecording {
            recordingRowHeightConstraint.isActive = false
        }
        inputRow.isHidden = !canWrite || isRecordingMedia
        textView.isHidden = inputRow.isHidden
        recordingRow.isHidden = !showsRecording
        if isRecordingVideoNote {
            setVoiceGestureDeferral(
                isHoldingVideoNote
                    && voiceGestureIsTracking
                    && !voiceGestureContactEnded,
            )
            if chatVM.timer != nil {
                chatVM.stopTimer()
            }
            updateRecordingStatus()
        } else if chatVM.recordingVoiceNote {
            setVoiceGestureDeferral(
                chatVM.voiceRecordingInteractionState == .holding
                    && voiceGestureIsTracking
                    && !voiceGestureContactEnded,
            )
            if chatVM.voiceRecordingInteractionState == .holding
                || chatVM.voiceRecordingInteractionState == .locked, chatVM.timer == nil
            {
                chatVM.startTimer()
            }
            updateRecordingStatus()
        } else {
            if voiceGestureIsArmed, !chatVM.startingVoiceNote, !recordingStartInFlight {
                finishVoiceGestureAfterExternalStop()
            }
            if chatVM.timer != nil {
                chatVM.stopTimer()
            }
            if !voiceGestureIsTracking {
                setVoiceGestureDeferral(false)
            }
        }
        updateActionButton()
        updateRecordingGesturePresentation()
        updateReplyKeyboard()
        if chatVM.text.characters.isEmpty, chatVM.editCustomMessage == nil, replacedText {
            // A send or a cleared draft leaves the empty input's multiline layout and the expanded input.
            isEmptyMultilineInput = false
            isInputExpanded = false
        }
        updateMultilineText(animated: window != nil)
        isApplyingState = false
        // ChatInterfaceStateContextQueries follows the input state: text replaced here, as a send clears it, takes
        // its sticker, emoji, hashtag and mention suggestions along.
        if replacedText { refreshMentionQuery() }
        if shouldFocus, lastReplyID != nil || lastEditID != nil {
            textView.becomeFirstResponder()
        }
    }

    /// The recording tick refreshes only the recording row instead of the whole composer.
    func updateRecordingTime() {
        guard chatVM.recordingVoiceNote, !videoNoteState.isActive else { return }
        updateRecordingStatus()
    }

    /// Sends the composer, with the send menu's options when it chose some.
    func send(options: TDNativeMessageSendOptions?, mediaMode: ComposerMediaSendMode = .grouped) {
        guard !chatVM.sendingComposerMessage, chatVM.editCustomMessage == nil || options == nil else { return }
        draftTask?.cancel()
        draftTask = nil
        typingTask?.cancel()
        typingTask = nil
        lastTypingActionDate = nil
        chatVM.sendMessageTask = Task { [weak chatVM] in
            await chatVM?.sendMessage(options: options, mediaMode: mediaMode)
        }
    }

    /// Raise to Speak (activateRaiseGesture's requestAudioRecorder): with no finger on the button, Telegram's
    /// recording starts locked. It always records voice, whichever mode the button shows.
    func startRaisedVoiceRecording() async -> Bool {
        guard !videoNoteState.isActive, !chatVM.recordingVoiceNote else { return false }
        activeMediaRecordingMode = .voice
        guard await chatVM.mediaStartRecordingVoice() else { return false }
        chatVM.lockVoiceRecording()
        return true
    }

    /// InlineReactionSearchPanel's tap: the sticker goes out and the emoji that found it leaves the input
    /// (sendSticker with clearInput). The sticker menu's Send Silently passes its options.
    func sendSuggestedSticker(_ sticker: Sticker, options: TDNativeMessageSendOptions? = nil) {
        guard let query = textView.contextQuery(), case .stickers = query.query else { return }
        textView.replaceText(
            in: NSRange(location: 0, length: textView.attributedText.length),
            with: NSAttributedString(),
        )
        let chatVM = chatVM
        Task { await chatVM.sendSticker(sticker, options: options) }
    }

    /// chatComposerInsertMention, from a member's avatar menu: the mention goes in at the caret and the input takes the
    /// keyboard.
    func insertMention(of user: User) {
        guard let mention = ChatMentionSuggestion(user: user) else { return }
        textView.replaceText(in: textView.selectedRange, with: ComposerText.uiKit(ComposerText.attributed(
            Self.mentionText(mention),
        )))
        textView.becomeFirstResponder()
    }

    /// While the senders' menu is open the avatar gives way to the menu button's close icon.
    func setSendAsMenuOpen(_ open: Bool) {
        sendAsButton.setMenuOpen(open)
    }

    private func configureViews() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = 0
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        clipsToBounds = false

        dockedBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dockedBackground)
        glassView.clipsToBounds = true
        glassView.layer.cornerRadius = 0
        glassView.layer.cornerCurve = .continuous
        glassView.layer.maskedCorners = layer.maskedCorners
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        glassLeadingConstraint = glassView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -16)
        glassTrailingConstraint = glassView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 16)
        glassBottomConstraint = glassView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 16)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.spacing = 0
        // Inside the glass: UIKit swells interactive glass only under a touch that lands inside it, as Telegram's
        // input capsule and buttons swell under the finger. Docked, the glass has no effect and only hosts it.
        glassView.contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            dockedBackground.topAnchor.constraint(equalTo: topAnchor),
            dockedBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            dockedBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            dockedBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassLeadingConstraint,
            glassTrailingConstraint,
            glassBottomConstraint,
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -7),
        ])

        replyContainer.translatesAutoresizingMaskIntoConstraints = false
        replyContainer.clipsToBounds = true
        replyRow.translatesAutoresizingMaskIntoConstraints = false
        replyRow.axis = .horizontal
        replyRow.alignment = .center
        replyRow.spacing = 8
        replyRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10)
        replyRow.isLayoutMarginsRelativeArrangement = true
        var closeReplyConfiguration = UIButton.Configuration.plain()
        closeReplyConfiguration.image = UIImage(systemName: "xmark")
        closeReplyConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 11,
            weight: .semibold,
        )
        closeReplyConfiguration.contentInsets = .zero
        closeReplyButton.configuration = closeReplyConfiguration
        closeReplyButton.contentHorizontalAlignment = .center
        closeReplyButton.tintColor = .secondaryLabel
        closeReplyButton.accessibilityLabel = L10n.betterTG("Accessibility.CancelReply")
        replyRow.addArrangedSubview(replySnippet)
        replyRow.addArrangedSubview(closeReplyButton)
        replySnippet.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replySnippet.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        closeReplyButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        closeReplyButton.heightAnchor.constraint(equalToConstant: 45).isActive = true
        replyContainer.addSubview(replyRow)
        replyContainerHeightConstraint = replyContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            replyContainerHeightConstraint,
            replyRow.topAnchor.constraint(equalTo: replyContainer.topAnchor),
            replyRow.leadingAnchor.constraint(equalTo: replyContainer.leadingAnchor),
            replyRow.trailingAnchor.constraint(equalTo: replyContainer.trailingAnchor),
            replyRow.heightAnchor.constraint(equalToConstant: 45),
        ])
        replyRow.alpha = 0
        replyRow.transform = CGAffineTransform(translationX: 0, y: 45)
        replyRow.isUserInteractionEnabled = false

        photosScroll.translatesAutoresizingMaskIntoConstraints = false
        photosScroll.showsHorizontalScrollIndicator = false
        photosStack.translatesAutoresizingMaskIntoConstraints = false
        photosStack.axis = .horizontal
        photosStack.spacing = 6
        photosScroll.addSubview(photosStack)
        NSLayoutConstraint.activate([
            photosScroll.heightAnchor.constraint(equalToConstant: 104),
            photosStack.topAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.topAnchor),
            photosStack.leadingAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.leadingAnchor),
            photosStack.trailingAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.trailingAnchor),
            photosStack.bottomAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.bottomAnchor),
            photosStack.heightAnchor.constraint(equalTo: photosScroll.frameLayoutGuide.heightAnchor),
        ])

        documentsScroll.translatesAutoresizingMaskIntoConstraints = false
        documentsScroll.showsHorizontalScrollIndicator = false
        documentsStack.translatesAutoresizingMaskIntoConstraints = false
        documentsStack.axis = .horizontal
        documentsStack.spacing = 6
        documentsScroll.addSubview(documentsStack)
        documentsScrollHeightConstraint = documentsScroll.heightAnchor.constraint(equalToConstant: 54)
        NSLayoutConstraint.activate([
            documentsScrollHeightConstraint,
            documentsStack.topAnchor.constraint(equalTo: documentsScroll.contentLayoutGuide.topAnchor),
            documentsStack.leadingAnchor.constraint(equalTo: documentsScroll.contentLayoutGuide.leadingAnchor),
            documentsStack.trailingAnchor.constraint(equalTo: documentsScroll.contentLayoutGuide.trailingAnchor),
            documentsStack.bottomAnchor.constraint(equalTo: documentsScroll.contentLayoutGuide.bottomAnchor),
            documentsStack.heightAnchor.constraint(equalTo: documentsScroll.frameLayoutGuide.heightAnchor),
        ])
        updateDocumentsScrollHeight()

        inputRow.axis = .horizontal
        inputRow.alignment = .bottom
        // Match the outer 10pt gutters at the visible text, including its 5pt inset.
        inputRow.spacing = 10 - textView.textContainerInset.left
        inputRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10)
        inputRow.isLayoutMarginsRelativeArrangement = true
        attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
        attachmentButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .regular),
            forImageIn: .normal,
        )
        attachmentButton.accessibilityLabel = L10n.telegram("VoiceOver.AttachMedia")
        textView.backgroundColor = .clear
        var menuConfiguration = UIButton.Configuration.filled()
        menuConfiguration.cornerStyle = .capsule
        menuConfiguration.image = UIImage(
            systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
        )
        menuConfiguration.imagePadding = 4
        menuConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        menuConfiguration.titleLineBreakMode = .byTruncatingTail
        botMenuButton.configuration = menuConfiguration
        botMenuButton.accessibilityLabel = L10n.telegram("Conversation.InputMenu")
        botMenuButton.isHidden = true
        botMenuButton.setContentHuggingPriority(.required, for: .horizontal)
        botMenuButton.setContentCompressionResistancePriority(.required - 1, for: .horizontal)
        inputRow.addArrangedSubview(sendAsButton)
        inputRow.addArrangedSubview(botMenuButton)
        inputRow.addArrangedSubview(attachmentButton)
        inputRow.addArrangedSubview(textSlot)
        inputRow.addArrangedSubview(expandInputButton)
        inputRow.addArrangedSubview(autoDeleteButton)
        inputRow.addArrangedSubview(scheduledMessagesButton)
        inputRow.addArrangedSubview(silentPostButton)
        inputRow.addArrangedSubview(mediaInputButton)
        inputRow.addArrangedSubview(replyKeyboardButton)
        inputRow.addArrangedSubview(actionButton)
        NSLayoutConstraint.activate([
            botMenuButton.heightAnchor.constraint(equalToConstant: 36),
            // The Web App button's text gets at most half the panel less 60 points, as `menuButtonTextNode` does.
            botMenuButton.widthAnchor.constraint(
                lessThanOrEqualTo: inputRow.widthAnchor,
                multiplier: 0.5,
                constant: -20,
            ),
            attachmentButton.widthAnchor.constraint(equalToConstant: 34),
            attachmentButton.heightAnchor.constraint(equalToConstant: 36),
            sendAsButton.widthAnchor.constraint(equalToConstant: 33),
            sendAsButton.heightAnchor.constraint(equalToConstant: 36),
            scheduledMessagesButton.widthAnchor.constraint(equalToConstant: 34),
            scheduledMessagesButton.heightAnchor.constraint(equalToConstant: 36),
            autoDeleteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            autoDeleteButton.heightAnchor.constraint(equalToConstant: 36),
            silentPostButton.widthAnchor.constraint(equalToConstant: 34),
            silentPostButton.heightAnchor.constraint(equalToConstant: 36),
            mediaInputButton.widthAnchor.constraint(equalToConstant: 34),
            mediaInputButton.heightAnchor.constraint(equalToConstant: 36),
            replyKeyboardButton.widthAnchor.constraint(equalToConstant: 34),
            replyKeyboardButton.heightAnchor.constraint(equalToConstant: 36),
            actionButton.widthAnchor.constraint(equalToConstant: 34),
            actionButton.heightAnchor.constraint(equalToConstant: 36),
            expandInputButton.widthAnchor.constraint(equalToConstant: 34),
            expandInputButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        scheduledMessagesButton.setImage(UIImage(systemName: "calendar.badge.clock"), for: .normal)
        scheduledMessagesButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
            forImageIn: .normal,
        )
        scheduledMessagesButton.tintColor = .secondaryLabel
        scheduledMessagesButton.accessibilityLabel = L10n.telegram("ScheduledMessages.Title")
        scheduledMessagesButton.isHidden = true
        // AccessoryItemIconButton: the interval in 14 pt medium, 5 pt in from each side.
        var autoDeleteConfiguration = UIButton.Configuration.plain()
        autoDeleteConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 5)
        autoDeleteConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 19,
            weight: .regular,
        )
        autoDeleteConfiguration.baseForegroundColor = .secondaryLabel
        autoDeleteConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 14, weight: .medium)
            return attributes
        }
        autoDeleteButton.configuration = autoDeleteConfiguration
        autoDeleteButton.isHidden = true
        autoDeleteButton.setContentHuggingPriority(.required, for: .horizontal)
        silentPostButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 19, weight: .regular),
            forImageIn: .normal,
        )
        silentPostButton.tintColor = .secondaryLabel
        silentPostButton.isHidden = true
        replyKeyboardButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
            forImageIn: .normal,
        )
        replyKeyboardButton.tintColor = .secondaryLabel
        replyKeyboardButton.isHidden = true
        replyKeyboardResponder.frame = .zero
        replyKeyboardResponder.isUserInteractionEnabled = false
        replyKeyboardResponder.keyboardInputView = replyKeyboardInputView
        replyKeyboardResponder.onActiveChange = { [weak self] in
            self?.updateReplyKeyboardButton()
            self?.updateMediaInputButton()
        }
        addSubview(replyKeyboardResponder)
        var mediaInputConfiguration = UIButton.Configuration.plain()
        mediaInputConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .regular,
        )
        mediaInputConfiguration.baseForegroundColor = .secondaryLabel
        mediaInputConfiguration.contentInsets = .zero
        mediaInputButton.configuration = mediaInputConfiguration
        mediaInputButton.isHidden = true
        // Telegram morphs the icon between stickers, emoji and the keyboard with `input_anim_stickerToKey` and the
        // others.
        mediaInputIcon.tintColor = .secondaryLabel
        mediaInputIcon.translatesAutoresizingMaskIntoConstraints = false
        mediaInputButton.addSubview(mediaInputIcon)
        recordModeIcon.translatesAutoresizingMaskIntoConstraints = false
        recordModeIcon.isHidden = true
        actionButton.addSubview(recordModeIcon)
        sendIcon.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(sendIcon)
        NSLayoutConstraint.activate([
            sendIcon.centerXAnchor.constraint(equalTo: actionButton.centerXAnchor),
            sendIcon.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            sendIcon.widthAnchor.constraint(equalToConstant: ComposerSendIconView.side),
            sendIcon.heightAnchor.constraint(equalToConstant: ComposerSendIconView.side),
            mediaInputIcon.centerXAnchor.constraint(equalTo: mediaInputButton.centerXAnchor),
            mediaInputIcon.centerYAnchor.constraint(equalTo: mediaInputButton.centerYAnchor),
            mediaInputIcon.widthAnchor.constraint(equalToConstant: 32),
            mediaInputIcon.heightAnchor.constraint(equalToConstant: 32),
            recordModeIcon.centerXAnchor.constraint(equalTo: actionButton.centerXAnchor),
            recordModeIcon.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            recordModeIcon.widthAnchor.constraint(equalToConstant: 30),
            recordModeIcon.heightAnchor.constraint(equalToConstant: 30),
        ])
        mediaInputResponder.frame = .zero
        mediaInputResponder.isUserInteractionEnabled = false
        mediaInputResponder.onActiveChange = { [weak self] in self?.mediaInputActiveChanged() }
        addSubview(mediaInputResponder)

        restrictionLabel.textColor = .secondaryLabel
        restrictionLabel.font = .preferredFont(forTextStyle: .subheadline)
        restrictionLabel.numberOfLines = 2
        restrictionLabel.textAlignment = .center
        restrictionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        botStartButton.setTitle(L10n.telegram("Bot.Start"), for: .normal)
        botStartButton.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17),
            maximumPointSize: 22,
        )
        botStartButton.titleLabel?.adjustsFontForContentSizeCategory = true
        botStartButton.accessibilityIdentifier = "bot-start"
        botStartButton.isHidden = true
        botStartButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        botStartButton.addAction(UIAction { [weak self] _ in self?.chatVM.sendBotStart() }, for: .touchUpInside)

        recordingRowHeightConstraint.priority = UILayoutPriority(999)
        recordingRow.axis = .horizontal
        recordingRow.alignment = .center
        recordingRow.spacing = 8
        recordingRow.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: 0,
            bottom: 0,
            trailing: 10,
        )
        recordingRow.isLayoutMarginsRelativeArrangement = true
        cancelRecordingButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelRecordingButton.accessibilityLabel = L10n.betterTG("Accessibility.CancelVoiceRecording")
        recordingPauseResumeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold),
            forImageIn: .normal,
        )
        recordingPreviewPlayButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold),
            forImageIn: .normal,
        )
        recordingPreviewWaveform.playedColor = .systemBlue
        recordingPreviewWaveform.unplayedColor = UIColor.secondaryLabel.withAlphaComponent(0.55)
        recordingPreviewWaveform.accessibilityLabel = L10n.betterTG("Accessibility.VoicePreviewWaveform")
        recordingPreviewWaveform.onSeek = { [weak self] progress in
            self?.seekRecordingPreview(to: progress)
        }
        recordingPreviewContainer.translatesAutoresizingMaskIntoConstraints = false
        recordingPreviewWaveform.translatesAutoresizingMaskIntoConstraints = false
        recordingTrimView.translatesAutoresizingMaskIntoConstraints = false
        recordingPreviewContainer.addSubview(recordingPreviewWaveform)
        recordingPreviewContainer.addSubview(recordingTrimView)
        videoNoteThumbnailStrip.translatesAutoresizingMaskIntoConstraints = false
        videoNoteThumbnailStrip.isHidden = true
        recordingPreviewContainer.addSubview(videoNoteThumbnailStrip)
        NSLayoutConstraint.activate([
            recordingPreviewWaveform.topAnchor.constraint(equalTo: recordingPreviewContainer.topAnchor),
            recordingPreviewWaveform.leadingAnchor.constraint(equalTo: recordingPreviewContainer.leadingAnchor),
            recordingPreviewWaveform.trailingAnchor.constraint(equalTo: recordingPreviewContainer.trailingAnchor),
            recordingPreviewWaveform.bottomAnchor.constraint(equalTo: recordingPreviewContainer.bottomAnchor),
            recordingTrimView.topAnchor.constraint(equalTo: recordingPreviewContainer.topAnchor),
            recordingTrimView.leadingAnchor.constraint(equalTo: recordingPreviewContainer.leadingAnchor),
            recordingTrimView.trailingAnchor.constraint(equalTo: recordingPreviewContainer.trailingAnchor),
            recordingTrimView.bottomAnchor.constraint(equalTo: recordingPreviewContainer.bottomAnchor),
            videoNoteThumbnailStrip.topAnchor.constraint(equalTo: recordingPreviewContainer.topAnchor),
            videoNoteThumbnailStrip.leadingAnchor.constraint(equalTo: recordingPreviewContainer.leadingAnchor),
            videoNoteThumbnailStrip.trailingAnchor.constraint(equalTo: recordingPreviewContainer.trailingAnchor),
            videoNoteThumbnailStrip.bottomAnchor.constraint(equalTo: recordingPreviewContainer.bottomAnchor),
        ])
        recordingTrimView.onRangeChange = { [weak self] start, end, updatedEnd, finished in
            guard let self else { return }
            if !finished {
                let selectedDuration = max(0, end - start)
                recordingLabel.text = String(format: "%.2f", selectedDuration)
                recordingPauseResumeButton.isEnabled = false
                recordingPauseResumeButton.alpha = 0.45
                recordingPreviewPlayButton.isEnabled = false
                recordingPreviewPlayButton.alpha = 0.45
                recordingSendButton.isEnabled = false
                recordingSendButton.alpha = 0.45
            }
            chatVM.updateVoiceRecordingTrim(
                start: start,
                end: end,
                updatedEnd: updatedEnd,
                finished: finished,
            )
        }
        videoNoteThumbnailStrip.onRangeChange = { [weak self] start, end, updatedEnd, finished in
            guard let self else { return }
            videoNoteTrimEditing = !finished
            videoNoteTrimSaving = finished
            videoNoteThumbnailStrip.setEditingEnabled(!finished)
            recordingPauseResumeButton.isEnabled = false
            recordingPauseResumeButton.alpha = 0.45
            recordingPreviewPlayButton.isEnabled = false
            recordingPreviewPlayButton.alpha = 0.45
            recordingSendButton.isEnabled = false
            recordingSendButton.alpha = 0.45
            onUpdateVideoNoteTrim?(start, end, updatedEnd, finished)
        }
        recordingLabel.textColor = .label
        recordingLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        recordingLabel.textAlignment = .center
        recordingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recordingPreviewContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recordingSendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        recordingSendButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 28),
            forImageIn: .normal,
        )
        recordingSendButton.accessibilityLabel = L10n.betterTG("Accessibility.SendVoiceMessage")
        recordingRow.addArrangedSubview(cancelRecordingButton)
        recordingRow.addArrangedSubview(recordingPauseResumeButton)
        recordingRow.addArrangedSubview(recordingPreviewPlayButton)
        recordingRow.addArrangedSubview(recordingPreviewContainer)
        recordingRow.addArrangedSubview(recordingLabel)
        recordingViewOnceButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium),
            forImageIn: .normal,
        )
        recordingViewOnceButton.isHidden = true
        recordingRow.addArrangedSubview(recordingViewOnceButton)
        recordingRow.addArrangedSubview(recordingSendButton)
        for button in [
            cancelRecordingButton,
            recordingPauseResumeButton,
            recordingPreviewPlayButton,
            recordingViewOnceButton,
            recordingSendButton,
        ] {
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
        recordingPreviewContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        recordingPreviewContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        rootStack.addArrangedSubview(suggestionsView)
        rootStack.addArrangedSubview(replyContainer)
        rootStack.addArrangedSubview(photosScroll)
        rootStack.addArrangedSubview(documentsScroll)
        rootStack.addArrangedSubview(multilineTextSlot)
        rootStack.addArrangedSubview(inputRow)
        rootStack.addArrangedSubview(recordingRow)
        rootStack.addArrangedSubview(restrictionLabel)
        rootStack.addArrangedSubview(botStartButton)
        rootStack.setCustomSpacing(6, after: photosScroll)
        rootStack.setCustomSpacing(6, after: documentsScroll)
        configureMultilineText()
    }

    // MARK: Multiline text

    /// The field lies over its slot in the button row, or over the multiline slot above it; one set of constraints
    /// is active at a time, so a switch animates the field's frame with the panel. The field lies in the glass with
    /// the row, as the glass swells only under a touch that lands inside it.
    private func configureMultilineText() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(textView)
        textSlot.translatesAutoresizingMaskIntoConstraints = false
        textSlot.isUserInteractionEnabled = false
        multilineTextSlot.translatesAutoresizingMaskIntoConstraints = false
        multilineTextSlot.isUserInteractionEnabled = false
        multilineTextSlot.isHidden = true
        compactTextConstraints = [
            textView.leadingAnchor.constraint(equalTo: textSlot.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textSlot.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: textSlot.bottomAnchor),
            textSlot.heightAnchor.constraint(equalTo: textView.heightAnchor),
        ]
        multilineTextConstraints = [
            // The text starts at the panel's gutter and ends where the send button's column ends.
            textView.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textView.topAnchor.constraint(equalTo: multilineTextSlot.topAnchor),
            multilineTextSlot.heightAnchor.constraint(equalTo: textView.heightAnchor),
            textSlot.heightAnchor.constraint(equalToConstant: 36),
        ]
        NSLayoutConstraint.activate(compactTextConstraints)

        expandInputButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expandInputButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium),
            forImageIn: .normal,
        )
        expandInputButton.tintColor = .secondaryLabel
        expandInputButton.accessibilityLabel = L10n.betterTG("Accessibility.ExpandInput")
        expandInputButton.isHidden = true
        expandInputButton.addAction(UIAction { [weak self] _ in self?.toggleInputExpanded() }, for: .touchUpInside)

        textView.onReturnInEmpty = { [weak self] in
            guard let self, !isMultilineText, !inputRow.isHidden else { return false }
            isEmptyMultilineInput = true
            updateMultilineText(animated: true)
            return true
        }
        textView.onBackspaceWhileEmpty = { [weak self] in
            guard let self, isEmptyMultilineInput else { return }
            isEmptyMultilineInput = false
            updateMultilineText(animated: true)
        }
        textView.onEndEditing = { [weak self] in
            guard let self, isEmptyMultilineInput || isInputExpanded else { return }
            isEmptyMultilineInput = false
            if isInputExpanded { setInputExpanded(false) }
            updateMultilineText(animated: true)
        }
    }

    /// Swiftgram's rule (ChatTextInputPanelNode 1514): the text goes above the buttons when it would take more than one
    /// line beside them, or while an empty input asked for the multiline layout with Return.
    private func updateMultilineText(animated: Bool) {
        guard !compactTextConstraints.isEmpty else { return }
        let compactWidth = isMultilineText ? textSlot.bounds.width : textView.bounds.width
        let wraps: Bool =
            if compactWidth > 0 {
                textView.sizeThatFits(CGSize(width: compactWidth, height: .greatestFiniteMagnitude)).height
                    > Self.singleLineTextHeight + 10
            } else {
                isMultilineText
            }
        let multiline = !inputRow.isHidden && !lacksRoomForMultilineText
            && (isEmptyMultilineInput || isInputExpanded || wraps)
        let hasText = chatVM.text.characters.contains { !$0.isWhitespace }
            || chatVM.editMessageText.characters.contains { !$0.isWhitespace }
        // The expand button joins the row once the text is a few lines tall (Swiftgram: 70 pt), or while expanded.
        let showsExpand = multiline && hasText && (isInputExpanded || textView.naturalHeight >= 70)
        if !showsExpand, isInputExpanded { setInputExpanded(false) }
        guard multiline != isMultilineText || expandInputButton.isHidden == showsExpand else { return }
        let changesLayout = multiline != isMultilineText
        isMultilineText = multiline
        let apply = {
            if changesLayout {
                NSLayoutConstraint.deactivate(multiline ? self.compactTextConstraints : self.multilineTextConstraints)
                NSLayoutConstraint.activate(multiline ? self.multilineTextConstraints : self.compactTextConstraints)
                self.multilineTextSlot.isHidden = !multiline
            }
            self.expandInputButton.isHidden = !showsExpand
            self.expandInputButton.alpha = showsExpand ? 1 : 0
            self.expandInputButton.transform = showsExpand ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
        }
        guard animated, window != nil else {
            apply()
            return
        }
        superview?.layoutIfNeeded()
        // Telegram's `.spring` transition of 0.4 s: the bezier (0.38, 0.7, 0.125, 1).
        let animator = UIViewPropertyAnimator(
            duration: 0.4,
            controlPoint1: CGPoint(x: 0.38, y: 0.7),
            controlPoint2: CGPoint(x: 0.125, y: 1),
        )
        animator.addAnimations {
            apply()
            self.superview?.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    private func toggleInputExpanded() {
        setInputExpanded(!isInputExpanded)
        updateMultilineText(animated: true)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
            self.superview?.layoutIfNeeded()
        }
    }

    /// Expanded, the input takes the space between the navigation bar and the keyboard.
    private func setInputExpanded(_ expanded: Bool) {
        isInputExpanded = expanded
        let symbol = expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        expandInputButton.setImage(UIImage(systemName: symbol), for: .normal)
        expandInputButton.accessibilityLabel = L10n.betterTG(
            expanded ? "Accessibility.CollapseInput" : "Accessibility.ExpandInput",
        )
        if expanded, let window {
            let height = max(Self.singleLineTextHeight, availableTextHeight(in: window))
            textView.maximumHeight = height
            textView.minimumHeight = height
        } else {
            textView.minimumHeight = Self.singleLineTextHeight
            textView.maximumHeight = 240
            updateTextHeightLimit()
        }
    }

    /// The room for the text between the navigation bar and the keyboard.
    private func availableTextHeight(in window: UIWindow) -> CGFloat {
        let bottom = convert(bounds, to: window).maxY
        let chrome = bounds.height - textView.bounds.height
        return bottom - window.safeAreaInsets.top - 44 - 24 - chrome
    }

    /// ChatTextInputPanelNode's textFieldMaxHeight: the input stops growing at 240 pt, or sooner where the bar and the
    /// keyboard leave less, as they do in landscape and on iPhone Duo's cover screen.
    private func updateTextHeightLimit() {
        guard let window, !isInputExpanded else { return }
        // The chat's banners take room under the bar too.
        let bannersHeight = max(0, topContentLimit - window.safeAreaInsets.top - 44 - 24)
        let limit = min(240, max(Self.singleLineTextHeight, availableTextHeight(in: window) - bannersHeight))
        if textView.maximumHeight != limit { textView.maximumHeight = limit }
        if lacksRoomForMultilineText != lastLacksRoomForMultilineText {
            lastLacksRoomForMultilineText = lacksRoomForMultilineText
            DispatchQueue.main.async { [weak self] in self?.updateMultilineText(animated: false) }
        }
    }

    private func configureActions() {
        attachmentButton.addTarget(self, action: #selector(showAttachmentActions), for: .touchUpInside)
        replyKeyboardButton.addTarget(self, action: #selector(toggleReplyKeyboard), for: .touchUpInside)
        mediaInputButton.addTarget(self, action: #selector(toggleMediaInput), for: .touchUpInside)
        scheduledMessagesButton.addAction(
            UIAction { [weak self] _ in self?.onOpenScheduledMessages?() },
            for: .touchUpInside,
        )
        silentPostButton.addAction(UIAction { [weak self] _ in self?.toggleSilentPost() }, for: .touchUpInside)
        autoDeleteButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onAutoDeleteTimer?(autoDeleteButton)
        }, for: .touchUpInside)
        closeReplyButton.addTarget(self, action: #selector(cancelReplyOrEdit), for: .touchUpInside)
        sendAsButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onSendAs?(sendAsButton)
        }, for: .touchUpInside)
        botMenuButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                if let button = chatVM.botMenuWebApp {
                    onOpenBotMenuWebApp?(button)
                } else {
                    chatVM.showsBotCommandMenu.toggle()
                }
            },
            for: .touchUpInside,
        )
        suggestionsView.onSendCommand = { [weak self] command in self?.chatVM.sendBotCommand(command) }
        suggestionsView.onInsertCommand = { [weak self] command in
            guard let self else { return }
            chatVM.insertBotCommand(command)
            update(from: chatVM)
            focusInput()
            textView.moveCaretToEnd()
        }
        suggestionsView.onSelectInlineResult = { [weak self] item in self?.chatVM.sendInlineBotResult(item) }
        suggestionsView.onLoadMoreInlineResults = { [weak self] in self?.chatVM.loadMoreInlineBotResults() }
        suggestionsView.onInlineButton = { [weak self] username, parameter in
            // HorizontalListContextResults' switchPeer: the bot's chat with its Start, sent only on the user's tap.
            var components = URLComponents()
            components.scheme = "https"
            components.host = "t.me"
            components.path = "/" + username
            components.queryItems = [URLQueryItem(name: "start", value: parameter)]
            guard let url = components.url else { return }
            TelegramLinkRouter.shared.open(url, from: self?.nearestViewController)
        }
        cancelRecordingButton.addTarget(self, action: #selector(cancelRecording), for: .touchUpInside)
        recordingPauseResumeButton.addTarget(self, action: #selector(toggleRecordingPause), for: .touchUpInside)
        recordingPreviewPlayButton.addTarget(self, action: #selector(toggleRecordingPreview), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionTouchDown(_:)), for: .touchDown)
        actionButton.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        sendOptionsGestureRecognizer.minimumPressDuration = 0.4
        sendOptionsGestureRecognizer.isEnabled = false
        actionButton.addGestureRecognizer(sendOptionsGestureRecognizer)
        actionButton.addAction(UIAction { [weak self] _ in self?.sendIcon.setHighlighted(true) }, for: [
            .touchDown, .touchDragEnter,
        ])
        actionButton.addAction(UIAction { [weak self] _ in self?.sendIcon.setHighlighted(false) }, for: [
            .touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel,
        ])
        recordingSendButton.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        recordingViewOnceButton.addTarget(self, action: #selector(toggleViewOnce), for: .touchUpInside)
        addGestureRecognizer(recordingGestureRecognizer)
        addSubview(recordingGestureOverlay)

        textView.onTextChange = { [weak self] text in self?.textChanged(text) }
        textView.onPasteImages = { [weak self] in self?.onPasteImages?($0) }
        textView.onInteractionSettled = { [weak self] in self?.onInteractionSettled?() }
        textView.onUserInteraction = { [weak self] in self?.onUserInteraction?() }
        textView.onSelectionChange = { [weak self] in
            guard let self, !isApplyingState else { return }
            refreshMentionQuery()
        }
        suggestionsView.onSelectMention = { [weak self] mention in self?.insertMention(mention) }
        suggestionsView.onSelectHashtag = { [weak self] hashtag in self?.insertHashtag(hashtag) }
        suggestionsView.onRemoveHashtag = { [weak self] hashtag in self?.chatVM.removeRecentHashtag(hashtag) }
        suggestionsView.onSelectEmoji = { [weak self] emoji in self?.insertSuggestedEmoji(emoji) }
        suggestionsView.onSelectSticker = { [weak self] sticker in self?.sendSuggestedSticker(sticker) }
        suggestionsView.stickerPeekActions = { [weak self] sticker in
            self?.suggestedStickerPeekActions?(sticker) ?? []
        }
    }

    /// Telegram's attach button opens the attachment sheet. While editing, the custom menu morphs out of the button.
    @objc private func showAttachmentActions() {
        // Editing a message with replaceable media opens the attachment menu to replace it
        // (`presentAttachmentMenu(subject: .edit)`); otherwise an edit takes only text and emoji.
        let editOptions = chatVM.editMediaOptions
        guard chatVM.editCustomMessage == nil || editOptions.photoOrVideo || editOptions.file else {
            nearestViewController?.presentTelegramContextMenu(
                sourceView: attachmentButton,
                actions: [
                    TelegramContextMenuAction(
                        title: L10n.telegram("EmojiInput.TabEmoji"),
                        image: UIImage(systemName: "face.smiling"),
                    ) { [weak self] in self?.showMediaInput(mode: .emoji) },
                ],
                presentationStyle: .sourceMorph,
            )
            return
        }
        onOpenAttachments?()
    }

    /// Fills the panel with the chat's offered keyboard; false when it offers none.
    private func configureReplyKeyboardInputView() -> Bool {
        guard let keyboard = chatVM.replyKeyboard.offeredKeyboard else { return false }
        let messageID = keyboard.messageID
        let heightChanged = replyKeyboardInputView.configure(
            keyboard: keyboard,
            containerSize: window?.bounds.size ?? bounds.size,
            bottomInset: window?.safeAreaInsets.bottom ?? 0,
        ) { [weak self] button in
            self?.onReplyKeyboardButton?(button, messageID)
        }
        if heightChanged, replyKeyboardResponder.isFirstResponder {
            replyKeyboardResponder.reloadInputViews()
        }
        return true
    }

    /// Keeps a shown keyboard current. When the bot removes it, or a one-time keyboard was used, Telegram switches
    /// the input to text (`.inputButtons` becomes `.text`).
    private func updateReplyKeyboard() {
        if replyKeyboardResponder.isFirstResponder,
           chatVM.editCustomMessage != nil || !configureReplyKeyboardInputView()
        {
            if chatVM.canWriteBasicMessages, !hiddenForSearch {
                textView.becomeFirstResponder()
            } else {
                replyKeyboardResponder.resignFirstResponder()
            }
        }
        updateReplyKeyboardButton()
    }

    /// Telegram's input buttons: the bot keyboard button while the input is empty, and the system keyboard button
    /// while the bot keyboard is up (`ChatTextInputAccessoryItem.botInput`). The media panel shows only its own
    /// keyboard button.
    private func updateReplyKeyboardButton() {
        let isActive = replyKeyboardResponder.isFirstResponder
        let isOffered = chatVM.replyKeyboard.offeredKeyboard != nil
            && chatVM.canWriteBasicMessages
            && chatVM.editCustomMessage == nil
        let isVisible = isOffered && !mediaInputResponder.isFirstResponder
            && (isActive || chatVM.text.characters.isEmpty)
        if replyKeyboardButton.isHidden == isVisible {
            replyKeyboardButton.isHidden = !isVisible
        }
        guard replyKeyboardButtonShowsSystemKeyboard != isActive else { return }
        replyKeyboardButtonShowsSystemKeyboard = isActive
        replyKeyboardButton.setImage(UIImage(systemName: isActive ? "keyboard" : "square.grid.2x2"), for: .normal)
        replyKeyboardButton.accessibilityLabel = L10n
            .telegram(isActive ? "VoiceOver.Keyboard" : "VoiceOver.BotKeyboard")
    }

    @objc private func toggleReplyKeyboard() {
        guard chatVM.locationContextIsCurrent else { return }
        if replyKeyboardResponder.isFirstResponder {
            // Closed with this button, a keyboard stays closed until the user opens it again.
            chatVM.replyKeyboard.setClosed(true)
            textView.becomeFirstResponder()
        } else {
            chatVM.replyKeyboard.setClosed(false)
            showReplyKeyboard()
        }
    }

    /// ChatInterfaceInputContexts' `.messageAutoremoveTimeout` item: outside Saved Messages while the input is empty,
    /// for a chat with a timer, or any secret chat.
    private func updateAutoDeleteButton() {
        let time = chatVM.messageAutoDeleteTime
        let isSecret = chatVM.customChat.secretChatID != nil
        let shows = !chatVM.customChat.isSavedMessages && (time > 0 || isSecret)
            && chatVM.editCustomMessage == nil && chatVM.text.characters.isEmpty
            && !mediaInputResponder.isFirstResponder
        if autoDeleteButton.isHidden == shows { autoDeleteButton.isHidden = !shows }
        guard shows else { return }
        if time > 0 {
            autoDeleteButton.configuration?.image = nil
            autoDeleteButton.configuration?.title = Self.shortTimeInterval(time)
            autoDeleteButton.accessibilityLabel = L10n.telegram(
                "VoiceOver.SelfDestructTimerOn",
                Self.shortTimeInterval(time),
            )
        } else {
            autoDeleteButton.configuration?.title = nil
            autoDeleteButton.configuration?.image = UIImage(systemName: "timer")
            autoDeleteButton.accessibilityLabel = L10n.telegram("VoiceOver.SelfDestructTimerOff")
        }
    }

    /// ChatInterfaceInputContexts' `.silentPost` item: in a channel the user posts to, while the input is empty
    /// outside editing and the media panel.
    private func updateSilentPostButton() {
        let shows = canPostSilently && chatVM.editCustomMessage == nil && chatVM.text.characters.isEmpty
            && !mediaInputResponder.isFirstResponder
        if silentPostButton.isHidden == shows { silentPostButton.isHidden = !shows }
        let silent = chatVM.silentPosting
        silentPostButton.setImage(UIImage(systemName: silent ? "bell.slash" : "bell"), for: .normal)
        silentPostButton.accessibilityLabel = L10n.telegram(silent
            ? "VoiceOver.SilentPostOn"
            : "VoiceOver.SilentPostOff")
    }

    /// toggleSilentPost: the setting flips and a tooltip over the bell says what posts do now.
    private func toggleSilentPost() {
        chatVM.toggleSilentPosting()
        guard let host = window else { return }
        let text = L10n.telegram(chatVM.silentPosting
            ? "Conversation.SilentBroadcastTooltipOff"
            : "Conversation.SilentBroadcastTooltipOn")
        TelegramTextTooltipView.show(
            text,
            source: silentPostButton.convert(silentPostButton.bounds, to: host),
            in: host,
            topInset: host.safeAreaInsets.top,
        )
    }

    /// ChatTextInputPanelNode's scheduled messages accessory, while the input is empty outside the media panel.
    private func updateScheduledMessagesButton() {
        let showsScheduledMessages = chatVM.hasScheduledMessages && chatVM.canScheduleMessages
            && chatVM.editCustomMessage == nil && chatVM.text.characters.isEmpty
            && !mediaInputResponder.isFirstResponder
        if scheduledMessagesButton.isHidden == showsScheduledMessages {
            scheduledMessagesButton.isHidden = !showsScheduledMessages
        }
    }

    /// ChatTextInputPanelNode's `.input` accessory item (`textInputAccessoryItems`): the keyboard while the media
    /// panel is up; emoji while editing, with text or with a forward; otherwise stickers, or nothing where stickers
    /// are banned and text can't be sent. The bot keyboard's own button stands alone while that keyboard is up.
    private func updateMediaInputButton() {
        let icon: MediaInputButtonIcon?
        if mediaInputResponder.isFirstResponder {
            icon = .keyboard
        } else if !mediaInputIsAvailable || replyKeyboardResponder.isFirstResponder {
            icon = nil
        } else if chatVM.editCustomMessage != nil {
            icon = .emoji
        } else {
            // Text made only of spaces and line breaks keeps the stickers icon, as it is not sent.
            let prefersEmoji = chatVM.text.characters.contains { !$0.isWhitespace } || chatVM.pendingForward != nil
            icon =
                if mediaInputStickersEnabled, !prefersEmoji {
                    .stickers
                } else {
                    mediaInputCanWriteText ? .emoji : nil
                }
        }
        if mediaInputButton.isHidden != (icon == nil) {
            mediaInputButton.isHidden = icon == nil
        }
        guard let icon, mediaInputButtonIcon != icon else { return }
        let previous = mediaInputButtonIcon
        mediaInputButtonIcon = icon
        // AccessoryItemIconButton's transitions: each mode's animation ends on its icon, played from the mode before.
        let (animation, animates) =
            switch (previous, icon) {
            case (.stickers, .keyboard): ("input_anim_stickerToKey", true)
            case (.emoji, .keyboard): ("input_anim_smileToKey", true)
            case (_, .keyboard): ("input_anim_stickerToKey", false)
            case (.keyboard, .stickers): ("input_anim_keyToSticker", true)
            case (.emoji, .stickers): ("input_anim_smileToSticker", true)
            case (_, .stickers): ("input_anim_keyToSticker", false)
            case (.keyboard, .emoji): ("input_anim_keyToSmile", true)
            case (.stickers, .emoji): ("input_anim_stickerToSmile", true)
            case (_, .emoji): ("input_anim_keyToSmile", false)
            }
        mediaInputIcon.show(animation, animated: animates && window != nil)
        mediaInputButton.accessibilityLabel =
            switch icon {
            case .emoji,
                 .stickers: L10n.telegram("VoiceOver.Stickers")
            case .keyboard: L10n.telegram("VoiceOver.Keyboard")
            }
    }

    /// Telegram drops the media panel once the input leaves `.media`; the next opening builds it on its tab again.
    private func mediaInputActiveChanged() {
        if !mediaInputResponder.isFirstResponder {
            mediaInputResponder.keyboardInputViewController = nil
        }
        updateMediaInputButton()
        updateReplyKeyboardButton()
        updateScheduledMessagesButton()
        updateSilentPostButton()
        updateAutoDeleteButton()
    }

    /// The keyboard icon returns to text input (`.text`); stickers and emoji open the panel on that tab, as
    /// `openStickers` does with `defaultToEmojiTab`.
    @objc private func toggleMediaInput() {
        guard chatVM.locationContextIsCurrent else { return }
        switch mediaInputButtonIcon {
        case .keyboard:
            if !mediaInputCanWriteText || !textView.becomeFirstResponder() {
                mediaInputResponder.resignFirstResponder()
            }
        case .emoji:
            showMediaInput(mode: .emoji)
        case .stickers:
            showMediaInput(mode: .stickers)
        case nil:
            break
        }
    }

    /// ChatEntityKeyboardInputNode's interaction: emoji go into the input at the caret, the backspace deletes there,
    /// and stickers and GIFs are sent at once while the panel stays up.
    private func makeMediaInputPicker(mode: ComposerMediaPickerViewController.Mode)
        -> ComposerMediaPickerViewController?
    {
        guard let accountID = chatVM.accountID else { return nil }
        let picker = ComposerMediaPickerViewController(
            accountID: accountID,
            chatID: chatVM.chatID,
            client: chatVM.client,
        )
        picker.presentationStyle = .input
        picker.initialMode = mode
        picker.allowsStickersAndGIFs = chatVM.editCustomMessage == nil && mediaInputStickersEnabled
        picker.presentationHost = nearestViewController
        picker.onEmoji = { [weak self] emoji in self?.textView.insertEmoji(emoji) }
        picker.onCustomEmoji = { [weak self] sticker in
            guard case .stickerFullTypeCustomEmoji(let type) = sticker.fullType else { return }
            self?.textView.insertEmoji(sticker.emoji, customID: type.customEmojiId)
        }
        picker.onDeleteBackward = { [weak self] in self?.textView.deleteBackwardFromPanel() }
        picker.onSwitchToKeyboard = { [weak self] in self?.textView.becomeFirstResponder() }
        picker.onSticker = { [weak self] sticker, fromPack in
            guard let self, chatVM.locationContextIsCurrent else { return }
            let chatVM = chatVM
            Task { await chatVM.sendSticker(sticker, fromPack: fromPack) }
        }
        picker.stickerSendActions = { [weak self] sticker in self?.stickerPeekSendActions?(sticker) ?? [] }
        picker.onAnimation = { [weak self] animation in
            guard let self, chatVM.locationContextIsCurrent else { return }
            let chatVM = chatVM
            Task { await chatVM.sendAnimation(animation) }
        }
        picker.onInlineAnimation = { [weak self] queryID, resultID in
            guard let self, chatVM.locationContextIsCurrent else { return }
            let chatVM = chatVM
            Task { await chatVM.sendInlineAnimation(queryID: queryID, resultID: resultID) }
        }
        picker.onExpandSearch = { [weak self] mode in self?.onExpandMediaSearch?(mode) }
        picker.onDismiss = { [weak self] in
            guard let self, mediaInputResponder.isFirstResponder else { return }
            mediaInputResponder.resignFirstResponder()
        }
        return picker
    }

    private func setReplyPreviewVisible(_ visible: Bool, animated: Bool) {
        guard replyPreviewVisible != visible else { return }
        replyPreviewVisible = visible

        superview?.layoutIfNeeded()
        layoutIfNeeded()
        replyContainerHeightConstraint.constant = visible ? 45 : 0
        replyRow.isUserInteractionEnabled = visible

        let changes = {
            self.replyRow.alpha = visible ? 1 : 0
            self.replyRow.transform = visible
                ? .identity
                : CGAffineTransform(translationX: 0, y: 45)
            self.superview?.layoutIfNeeded()
            self.layoutIfNeeded()
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
            animations: changes,
        )
    }

    private func rebuildPhotos() {
        for arrangedSubview in photosStack.arrangedSubviews {
            photosStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        for selectedImage in chatVM.displayedImages {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.layer.cornerRadius = 12
            container.clipsToBounds = true
            let imageView = UIImageView(image: selectedImage.image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            let removeButton = UIButton(type: .system)
            removeButton.translatesAutoresizingMaskIntoConstraints = false
            removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            removeButton.tintColor = .white
            removeButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
            removeButton.layer.cornerRadius = 12
            removeButton.addAction(UIAction { [weak self] _ in
                self?.chatVM.removeDisplayedImage(id: selectedImage.id)
            }, for: .touchUpInside)
            container.addSubview(imageView)
            if selectedImage.hasSpoiler {
                // Telegram's picker covers a spoilered item with its spoiler dust; a blur stands in for it here.
                let spoilerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
                spoilerView.translatesAutoresizingMaskIntoConstraints = false
                spoilerView.isUserInteractionEnabled = false
                container.addSubview(spoilerView)
                NSLayoutConstraint.activate([
                    spoilerView.topAnchor.constraint(equalTo: container.topAnchor),
                    spoilerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    spoilerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    spoilerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }
            container.addSubview(removeButton)
            if let video = selectedImage.video {
                // Telegram's gallery marks a video with its duration in the bottom corner, a trimmed one with the
                // trim's.
                let durationBadge = UIView()
                durationBadge.translatesAutoresizingMaskIntoConstraints = false
                durationBadge.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                durationBadge.layer.cornerRadius = 5
                let durationLabel = UILabel()
                durationLabel.translatesAutoresizingMaskIntoConstraints = false
                durationLabel.textColor = .white
                durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
                durationLabel.text = formatVideoDuration(video.sentDuration)
                durationBadge.addSubview(durationLabel)
                container.addSubview(durationBadge)
                NSLayoutConstraint.activate([
                    durationLabel.topAnchor.constraint(equalTo: durationBadge.topAnchor, constant: 2),
                    durationLabel.bottomAnchor.constraint(equalTo: durationBadge.bottomAnchor, constant: -2),
                    durationLabel.leadingAnchor.constraint(equalTo: durationBadge.leadingAnchor, constant: 5),
                    durationLabel.trailingAnchor.constraint(equalTo: durationBadge.trailingAnchor, constant: -5),
                    durationBadge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                    durationBadge.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
                ])
            }
            if selectedImage.livePhotoVideoURL != nil {
                let liveButton = UIButton(type: .system)
                liveButton.translatesAutoresizingMaskIntoConstraints = false
                liveButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                liveButton.layer.cornerRadius = 5
                liveButton.tintColor = .white
                liveButton.titleLabel?.font = .systemFont(ofSize: 10, weight: .semibold)
                let liveEnabled = selectedImage.isLivePhotoEnabled && chatVM.canSendLivePhotos
                liveButton.setTitle(
                    liveEnabled ? L10n.betterTG("Composer.LiveOn") : L10n.betterTG("Composer.LiveOff"),
                    for: .normal,
                )
                liveButton.accessibilityLabel = L10n.telegram("Message.LivePhoto")
                liveButton.accessibilityValue = liveEnabled
                    ? L10n.telegram("VoiceOver.Common.On")
                    : L10n.telegram("VoiceOver.Common.Off")
                liveButton.isEnabled = chatVM.canSendLivePhotos
                liveButton.addAction(UIAction { [weak self, weak liveButton] _ in
                    guard let self,
                          let index = chatVM.displayedImages.firstIndex(where: { $0.id == selectedImage.id })
                    else { return }
                    chatVM.displayedImages[index].isLivePhotoEnabled.toggle()
                    let enabled = chatVM.displayedImages[index].isLivePhotoEnabled
                    liveButton?.setTitle(
                        enabled ? L10n.betterTG("Composer.LiveOn") : L10n.betterTG("Composer.LiveOff"),
                        for: .normal,
                    )
                    liveButton?.accessibilityValue = enabled
                        ? L10n.telegram("VoiceOver.Common.On")
                        : L10n.telegram("VoiceOver.Common.Off")
                }, for: .touchUpInside)
                container.addSubview(liveButton)
                NSLayoutConstraint.activate([
                    liveButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                    liveButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
                    liveButton.widthAnchor.constraint(equalToConstant: 58),
                    liveButton.heightAnchor.constraint(equalToConstant: 22),
                ])
            }
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: 92),
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                removeButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                removeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                removeButton.widthAnchor.constraint(equalToConstant: 24),
                removeButton.heightAnchor.constraint(equalToConstant: 24),
            ])
            photosStack.addArrangedSubview(container)
        }
    }

    private func rebuildDocuments() {
        for arrangedSubview in documentsStack.arrangedSubviews {
            documentsStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        for document in chatVM.displayedDocuments {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.backgroundColor = .tertiarySystemFill
            container.layer.cornerCurve = .continuous
            container.layer.cornerRadius = 10

            // A music file goes as music (ComposerAudioMetadata), so it shows a note.
            let isMusic = UTType(filenameExtension: document.url.pathExtension)?.conforms(to: .audio) == true
            let iconView = UIImageView(image: UIImage(systemName: isMusic ? "music.note" : "doc.fill"))
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .systemBlue

            let titleLabel = UILabel()
            titleLabel.font = .preferredFont(forTextStyle: .subheadline)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.lineBreakMode = .byTruncatingMiddle
            titleLabel.text = document.name

            let sizeLabel = UILabel()
            sizeLabel.font = .preferredFont(forTextStyle: .caption1)
            sizeLabel.adjustsFontForContentSizeCategory = true
            sizeLabel.textColor = .secondaryLabel
            sizeLabel.text = ByteCountFormatter.string(fromByteCount: document.size, countStyle: .file)

            let labels = UIStackView(arrangedSubviews: [titleLabel, sizeLabel])
            labels.translatesAutoresizingMaskIntoConstraints = false
            labels.axis = .vertical
            labels.spacing = 1

            let removeButton = UIButton(type: .system)
            removeButton.translatesAutoresizingMaskIntoConstraints = false
            removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            removeButton.tintColor = .secondaryLabel
            removeButton.accessibilityLabel = L10n.betterTG("Accessibility.RemoveAttachment", document.name)
            removeButton.addAction(UIAction { [weak self] _ in
                self?.chatVM.removeDisplayedDocument(id: document.id)
            }, for: .touchUpInside)

            container.addSubview(iconView)
            container.addSubview(labels)
            container.addSubview(removeButton)
            titleLabel.accessibilityLabel = "\(document.name), \(sizeLabel.text ?? L10n.telegram("Message.File"))"
            sizeLabel.isAccessibilityElement = false
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: 220),
                iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
                iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 28),
                iconView.heightAnchor.constraint(equalToConstant: 28),
                labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                labels.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                labels.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -6),
                removeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                removeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                removeButton.widthAnchor.constraint(equalToConstant: 32),
                removeButton.heightAnchor.constraint(equalToConstant: 40),
            ])
            documentsStack.addArrangedSubview(container)
        }
    }

    private func updateDocumentsScrollHeight() {
        guard documentsScrollHeightConstraint != nil else { return }
        let titleHeight = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        let captionHeight = UIFont.preferredFont(forTextStyle: .caption1).lineHeight
        documentsScrollHeightConstraint.constant = max(54, ceil(titleHeight + captionHeight + 15))
        superview?.setNeedsLayout()
    }

    /// ChatTextInputPanelNode's updateHeight: a line added or removed moves the panel in 0.1 s, picking up from where a
    /// quick run of lines has it instead of stepping there.
    /// `updateActionButtons`: the microphone fades as the send button comes and goes.
    private func setRecordModeIconShown(_ shown: Bool, animated: Bool) {
        guard shown != showsRecordModeIcon else { return }
        showsRecordModeIcon = shown
        guard animated else {
            recordModeIcon.isHidden = !shown
            recordModeIcon.alpha = 1
            return
        }
        if recordModeIcon.isHidden {
            recordModeIcon.alpha = 0
            recordModeIcon.isHidden = false
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.recordModeIcon.alpha = shown ? 1 : 0
        } completion: { [weak self] _ in
            guard let self, showsRecordModeIcon == shown else { return }
            recordModeIcon.isHidden = !shown
            recordModeIcon.alpha = 1
        }
    }

    private func animateTextHeightChange() {
        guard window != nil else { return }
        UIView.animate(
            withDuration: 0.1,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
        ) {
            self.superview?.layoutIfNeeded()
        }
    }

    private func textChanged(_ text: AttributedString) {
        guard !isApplyingState else { return }
        if chatVM.editCustomMessage == nil {
            chatVM.updateComposerTextFromUser(text)
        } else {
            chatVM.editMessageText = text
        }
        refreshMentionQuery()
        updateActionButton()
        updateReplyKeyboardButton()
        updateMediaInputButton()
        updateMultilineText(animated: true)
        animateTextHeightChange()
        draftTask?.cancel()
        draftTask = Task { [weak chatVM] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await chatVM?.updateDraft()
        }
        typingTask?.cancel()
        typingTask = nil
        // Editing an existing message is not typing a new one.
        guard chatVM.editCustomMessage == nil else { return }
        guard !text.characters.isEmpty else {
            guard lastTypingActionDate != nil else { return }
            lastTypingActionDate = nil
            Task { [weak chatVM] in try? await chatVM?.tdSendChatAction(.chatActionCancel) }
            return
        }
        if lastTypingActionDate.map({ Date().timeIntervalSince($0) >= 4 }) ?? true {
            lastTypingActionDate = Date()
            Task { [weak chatVM] in try? await chatVM?.tdSendChatAction(.chatActionTyping) }
        }
        typingTask = Task { [weak self, weak chatVM] in
            try? await Task<Never, Never>.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.lastTypingActionDate = nil
            try? await chatVM?.tdSendChatAction(.chatActionCancel)
        }
    }

    private func updateActionButton() {
        let hasContent = !chatVM.displayedImages.isEmpty
            || !chatVM.displayedDocuments.isEmpty
            || chatVM.text.characters.contains { !$0.isWhitespace }
            || !chatVM.editMessageText.characters.isEmpty
            || chatVM.editCustomMessage != nil
            || chatVM.pendingForward != nil
        let isPreparingVoice = chatVM.loadingVoiceDraft || chatVM.startingVoiceNote || chatVM.finalizingVoiceNote
        let isSendingComposer = chatVM.sendingComposerMessage
        let isFinalizingVoice = isPreparingVoice && !hasContent
        let isFinalizingVideo = isVideoNoteBusy && !hasContent
        let isRetryingVoice = chatVM.canRetryPendingVoiceNote && !hasContent
        let isUncertainVoice = chatVM.hasPendingVoiceNote && !chatVM.canRetryPendingVoiceNote && !hasContent
        let isRetryingVideo = chatVM.canRetryPendingVideoNote && !hasContent
        let isUncertainVideo = chatVM.hasPendingVideoNote && !chatVM.canRetryPendingVideoNote && !hasContent
        let isRecordingMedia = chatVM.recordingVoiceNote || videoNoteState.isActive
        let canRecordSelectedMode = selectedMediaRecordingMode == .voice
            ? chatVM.canRecordVoiceNote
            : chatVM.canRecordVideoNote
        let symbol =
            if isFinalizingVoice || isFinalizingVideo || isSendingComposer {
                "clock.circle"
            } else if isRetryingVoice {
                "arrow.clockwise.circle.fill"
            } else if isUncertainVoice {
                "exclamationmark.circle.fill"
            } else if isRetryingVideo {
                "arrow.clockwise.circle.fill"
            } else if isUncertainVideo {
                "exclamationmark.circle.fill"
            } else if isRecordingMedia || hasContent {
                "arrow.up.circle.fill"
            } else {
                selectedMediaRecordingMode == .video ? "video.fill" : "mic.fill"
            }
        // The microphone and the camera are Telegram's, morphing into each other as the recording mode changes.
        let showsRecordMode = symbol == "mic.fill" || symbol == "video.fill"
        let showsSend = symbol == "arrow.up.circle.fill"
        actionButton.setImage(showsRecordMode || showsSend ? nil : UIImage(systemName: symbol), for: .normal)
        let animatesIcons = window != nil && !UIAccessibility.isReduceMotionEnabled
        setRecordModeIconShown(showsRecordMode, animated: animatesIcons)
        sendIcon.setShown(showsSend, animated: animatesIcons)
        if showsRecordMode, shownRecordMode != selectedMediaRecordingMode {
            let animates = shownRecordMode != nil && window != nil
            shownRecordMode = selectedMediaRecordingMode
            recordModeIcon.show(
                selectedMediaRecordingMode == .video ? "anim_micToVideo" : "anim_videoToMic",
                animated: animates,
            )
        }
        actionButton.isHidden = !hasContent && !canRecordSelectedMode
        actionButton.isEnabled = hasContent || canRecordSelectedMode
        actionButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(
                pointSize: isRecordingMedia || hasContent ? 28 : 20,
                weight: isRecordingMedia || hasContent ? .regular : .medium,
            ),
            forImageIn: .normal,
        )
        actionButton.isEnabled = !isFinalizingVoice && !isFinalizingVideo && !isSendingComposer
            && (chatVM.editCustomMessage == nil || chatVM.canEditMessage)
        actionButton.alpha = actionButton.isEnabled ? 1 : 0.55
        let canBeginRecordingGesture = !chatVM.startingVoiceNote
            && !chatVM.loadingVoiceDraft
            && !chatVM.finalizingVoiceNote
            && !chatVM.hasPendingVoiceNote
            && !chatVM.hasPendingVideoNote
            && !videoNoteState.isActive
            && !hasContent
        recordingGestureRecognizer.isEnabled = voiceGestureIsTracking || canBeginRecordingGesture
        // Text or media the composer would send; an edit or a forward alone has no send options.
        let hasSendableContent = !chatVM.displayedImages.isEmpty || !chatVM.displayedDocuments.isEmpty
            || chatVM.text.characters.contains { !$0.isWhitespace }
        sendOptionsGestureRecognizer.isEnabled = hasSendableContent && chatVM.editCustomMessage == nil
            && !isRecordingMedia && !isSendingComposer
        if chatVM.hasPendingVoiceNote {
            var voiceActions = [UIAction]()
            if chatVM.canRetryPendingVoiceNote {
                voiceActions.append(UIAction(
                    title: L10n.betterTG("Composer.RetryVoiceMessage"),
                    image: UIImage(systemName: "arrow.clockwise"),
                ) { [weak self] _ in
                    self?.chatVM.retryPendingVoiceNote()
                })
            }
            voiceActions.append(UIAction(
                title: L10n.telegram("Conversation.DiscardVoiceMessageTitle"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { [weak self] _ in
                self?.chatVM.discardPendingVoiceNote()
            })
            actionButton.menu = UIMenu(children: voiceActions)
            actionButton.accessibilityHint = chatVM.canRetryPendingVoiceNote
                ? L10n.betterTG("Accessibility.PendingMediaRetryHint")
                : L10n.betterTG("Accessibility.PendingMediaUncertainHint")
        } else if chatVM.hasPendingVideoNote {
            var videoActions = [UIAction]()
            if chatVM.canRetryPendingVideoNote {
                videoActions.append(UIAction(
                    title: L10n.betterTG("Composer.RetryVideoMessage"),
                    image: UIImage(systemName: "arrow.clockwise"),
                ) { [weak self] _ in
                    self?.chatVM.retryPendingVideoNote()
                })
            }
            videoActions.append(UIAction(
                title: L10n.betterTG("Composer.DiscardVideoMessage"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { [weak self] _ in
                self?.chatVM.discardPendingVideoNote()
            })
            actionButton.menu = UIMenu(children: videoActions)
            actionButton.accessibilityHint = chatVM.canRetryPendingVideoNote
                ? L10n.betterTG("Accessibility.PendingMediaRetryHint")
                : L10n.betterTG("Accessibility.PendingMediaUncertainHint")
        } else {
            actionButton.menu = nil
            actionButton.accessibilityHint = UIAccessibility.isVoiceOverRunning && !hasContent
                ? (selectedMediaRecordingMode == .video
                    ? L10n.betterTG("Accessibility.LockedVideoRecordingHint")
                    : L10n.betterTG("Accessibility.LockedVoiceRecordingHint"))
                : nil
        }
        actionButton.accessibilityLabel =
            if isFinalizingVoice || isFinalizingVideo {
                selectedMediaRecordingMode == .video
                    ? L10n.betterTG("Accessibility.PreparingVideoMessage")
                    : L10n.betterTG("Accessibility.PreparingVoiceMessage")
            } else if isRetryingVoice {
                L10n.betterTG("Accessibility.RetryVoiceMessage")
            } else if isUncertainVoice {
                L10n.betterTG("Accessibility.VoiceSendStatusUnknown")
            } else if isRetryingVideo {
                L10n.betterTG("Accessibility.RetryVideoMessage")
            } else if isUncertainVideo {
                L10n.betterTG("Accessibility.VideoSendStatusUnknown")
            } else {
                isRecordingMedia || hasContent
                    ? L10n.telegram("MediaPicker.Send")
                    : selectedMediaRecordingMode == .video
                        ? L10n.betterTG("Accessibility.RecordVideoMessage")
                        : L10n.betterTG("Accessibility.RecordVoiceMessage")
            }
    }

    private func updateRecordingStatus() {
        defer { updateRecordingGesturePresentation() }
        recordingViewOnceButton.isHidden = true
        if videoNoteState.isActive {
            updateVideoRecordingStatus()
            return
        }
        cancelRecordingButton.accessibilityLabel = L10n.betterTG("Accessibility.CancelVoiceRecording")
        videoNoteThumbnailStrip.isHidden = true
        recordingPreviewWaveform.isHidden = false
        recordingSendButton.accessibilityLabel = L10n.betterTG("Accessibility.SendVoiceMessage")
        recordingLabel.textColor = .systemRed
        recordingPreviewPlayButton.isHidden = true
        recordingPreviewContainer.isHidden = true
        recordingPauseResumeButton.isHidden = true
        recordingSendButton.isEnabled = true
        recordingSendButton.alpha = 1
        switch chatVM.voiceRecordingInteractionState {
        case .locked:
            recordingLabel.text = L10n.betterTG("Composer.RecordingLocked", chatVM.formattedTimerCount)
            recordingLabel.accessibilityLabel = L10n.betterTG(
                "Accessibility.VoiceRecordingLocked",
                chatVM.formattedTimerCount,
            )
            recordingPauseResumeButton.isHidden = false
            recordingPauseResumeButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = L10n.betterTG("Accessibility.PauseVoiceRecording")
            recordingPauseResumeButton.isEnabled = chatVM.canPauseVoiceRecording
            recordingPauseResumeButton.alpha = chatVM.canPauseVoiceRecording ? 1 : 0.45
            recordingSendButton.isHidden = false
            updateViewOnceButton()
        case .holding:
            recordingLabel.text = "● \(chatVM.formattedTimerCount)"
            recordingLabel.accessibilityLabel = L10n.betterTG(
                "Accessibility.RecordingVoiceMessage",
                chatVM.formattedTimerCount,
            )
            recordingSendButton.isHidden = true
        case .preview:
            let previewPath = chatVM.voiceRecordingPreviewPath
            let isPlaying = chatVM.voiceRecordingPreviewIsPlaying
            recordingPauseResumeButton.isHidden = false
            recordingPauseResumeButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = L10n.betterTG("Accessibility.ResumeVoiceRecording")
            recordingPauseResumeButton.isEnabled = chatVM.voiceRecordingPreviewReady
            recordingPauseResumeButton.alpha = chatVM.voiceRecordingPreviewReady ? 1 : 0.45
            recordingPreviewPlayButton.isHidden = false
            recordingPreviewPlayButton.setImage(
                UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"),
                for: .normal,
            )
            recordingPreviewPlayButton.accessibilityLabel = isPlaying
                ? L10n.betterTG("Accessibility.PauseVoicePreview")
                : L10n.betterTG("Accessibility.PlayVoicePreview")
            recordingPreviewPlayButton.isEnabled = chatVM.voiceRecordingPreviewReady && previewPath != nil
            recordingPreviewContainer.isHidden = false
            recordingPreviewWaveform.isEnabled = chatVM.voiceRecordingPreviewReady && previewPath != nil
            recordingPreviewWaveform.samples = chatVM.voiceRecordingPreviewWaveform
            recordingPreviewWaveform.progress = chatVM.voiceRecordingPreviewProgress
            if let range = chatVM.voiceRecordingTrimRange {
                recordingTrimView.update(duration: chatVM.voiceRecordingPreviewExactDuration, range: range)
            }
            recordingTrimView.setEditingEnabled(chatVM.voiceRecordingTrimControlsEnabled)
            recordingLabel.text = chatVM.formattedVoiceRecordingPreviewDuration
            recordingLabel.accessibilityLabel =
                L10n.betterTG("Accessibility.VoicePreview", chatVM.formattedVoiceRecordingPreviewDuration)
            recordingSendButton.isHidden = false
            recordingSendButton.isEnabled = chatVM.voiceRecordingPreviewReady
            recordingSendButton.alpha = chatVM.voiceRecordingPreviewReady ? 1 : 0.45
            updateViewOnceButton()
        case .pausing:
            recordingLabel.text = L10n.betterTG("Composer.Preparing")
            recordingLabel.accessibilityLabel = L10n.betterTG("Accessibility.PreparingVoicePreview")
            recordingSendButton.isHidden = true
        case .resuming:
            recordingLabel.text = L10n.betterTG("Composer.Resuming")
            recordingLabel.accessibilityLabel = L10n.betterTG("Accessibility.ResumingVoiceRecording")
            recordingSendButton.isHidden = true
        case .idle:
            recordingPauseResumeButton.isEnabled = true
            recordingPauseResumeButton.alpha = 1
            recordingLabel.text = nil
            recordingLabel.accessibilityLabel = nil
            recordingSendButton.isHidden = true
        }
    }

    private func updateVideoRecordingStatus() {
        cancelRecordingButton.accessibilityLabel = L10n.betterTG("Accessibility.CancelVideoMessage")
        recordingLabel.textColor = .systemRed
        recordingPreviewPlayButton.isHidden = true
        recordingPreviewContainer.isHidden = true
        recordingPreviewWaveform.isHidden = true
        recordingTrimView.isHidden = true
        videoNoteThumbnailStrip.isHidden = true
        recordingPauseResumeButton.isHidden = true
        recordingSendButton.isHidden = true
        recordingSendButton.isEnabled = true
        recordingSendButton.alpha = 1
        recordingTrimView.setEditingEnabled(false)
        switch videoNoteState {
        case .preparing:
            recordingLabel.text = L10n.betterTG("VideoNote.PreparingCamera")
            recordingLabel.accessibilityLabel = L10n.betterTG("Accessibility.PreparingVideoCamera")
        case .holding(let duration):
            recordingLabel.text = "● \(formatVideoDuration(duration))"
            recordingLabel.accessibilityLabel = L10n.betterTG(
                "Accessibility.RecordingVideoMessage",
                formatVideoDuration(duration),
            )
        case .locked(let duration):
            recordingLabel.text = L10n.betterTG("Composer.RecordingLocked", formatVideoDuration(duration))
            recordingLabel.accessibilityLabel = L10n.betterTG(
                "Accessibility.VideoRecordingLocked",
                formatVideoDuration(duration),
            )
            recordingPauseResumeButton.isHidden = false
            recordingPauseResumeButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = L10n.betterTG("Accessibility.StopVideoRecordingForPreview")
            recordingSendButton.isHidden = false
            recordingSendButton.accessibilityLabel = L10n.betterTG("Accessibility.SendVideoMessage")
        case .preview(let duration, let isPlaying, let canRecordMore):
            let trimControlsBlocked = videoNoteTrimEditing || videoNoteTrimSaving
            recordingLabel.textColor = .label
            recordingLabel.text = formatVideoDuration(duration)
            recordingLabel.accessibilityLabel = L10n.betterTG(
                "Accessibility.VideoPreview",
                formatVideoDuration(duration),
            )
            recordingPreviewPlayButton.isHidden = false
            recordingPreviewPlayButton.setImage(
                UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"),
                for: .normal,
            )
            recordingPreviewPlayButton.accessibilityLabel = isPlaying
                ? L10n.betterTG("Accessibility.PauseVideoPreview")
                : L10n.betterTG("Accessibility.PlayVideoPreview")
            recordingPreviewContainer.isHidden = false
            videoNoteThumbnailStrip.isHidden = false
            videoNoteThumbnailStrip.setEditingEnabled(!videoNoteTrimSaving)
            recordingPauseResumeButton.isHidden = !canRecordMore
            recordingPauseResumeButton.setImage(UIImage(systemName: "video.badge.plus"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = L10n.betterTG("Accessibility.RecordMoreVideo")
            recordingSendButton.isHidden = false
            recordingSendButton.accessibilityLabel = L10n.betterTG("Accessibility.SendVideoMessage")
            for button in [recordingPauseResumeButton, recordingPreviewPlayButton, recordingSendButton] {
                button.isEnabled = !trimControlsBlocked
                button.alpha = trimControlsBlocked ? 0.45 : 1
            }
        case .stopping:
            recordingLabel.text = L10n.betterTG("VideoNote.PreparingPreview")
            recordingLabel.accessibilityLabel = L10n.betterTG("Accessibility.PreparingVideoPreview")
        case .sending:
            recordingLabel.text = L10n.betterTG("VideoNote.Sending")
            recordingLabel.accessibilityLabel = L10n.betterTG("Accessibility.SendingVideoMessage")
        case .failed(let message):
            recordingLabel.text = message
            recordingLabel.accessibilityLabel = message
        case .idle:
            recordingLabel.text = nil
            recordingLabel.accessibilityLabel = nil
        }
    }

    private func updateRecordingGesturePresentation() {
        guard recordingGestureOverlay.superview != nil else { return }
        let holding = voiceGestureIsTracking && !voiceGestureFinished
            && (recordingStartInFlight || chatVM.voiceRecordingInteractionState == .holding || isHoldingVideoNote)
        recordingGestureOverlay.frame = bounds
        let row = recordingRow.convert(recordingRow.bounds, to: self)
        recordingGestureOverlay.update(
            active: holding,
            video: activeMediaRecordingMode == .video,
            translation: voiceGestureTranslation,
            anchor: CGPoint(x: bounds.width - 29, y: row.midY),
        )
        cancelRecordingButton.isHidden = holding
        recordingLabel.textAlignment = holding ? .left : .center
        bringSubviewToFront(recordingGestureOverlay)
    }

    private func formatVideoDuration(_ duration: Double) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// ReplyAccessoryPanelNode names the message's effective author: a channel post or an anonymous admin's message
    /// reads as its sender chat, as the bubbles' reply headers do. A chat TDLib hasn't returned yet updates the panel.
    /// The replied message's author by EnginePeer.displayTitle: a user's full name, or the chat's title.
    private func replyAuthorName(for message: CustomMessage) -> String? {
        switch message.message.senderId {
        case .messageSenderUser:
            return message.senderUser.map(ServiceMessageText.displayTitle)
        case .messageSenderChat(let sender):
            if sender.chatId == chatVM.chatID { return chatVM.customChat.chat.title }
            return MessagePeerNames.chat(sender.chatId, client: chatVM.client) { [weak self] _ in
                guard let self else { return }
                update(from: chatVM)
            }?.title
        }
    }

    private func navigationTarget(
        for message: CustomMessage,
        quote: InputTextQuote? = nil,
    ) -> MessageMetadataNavigationTarget {
        let quoteHighlight = quote.flatMap { MessageQuoteHighlight(text: $0.text.text, position: $0.position) }
        return .message(
            chatID: message.message.chatId,
            messageID: message.id,
            quote: quoteHighlight,
        )
    }

    /// Telegram's forward options (ChatMessageActionOptions `chatForwardOptions`) for the pending forward: sender
    /// names, captions, Change Recipient and Do Not Forward. A secret chat always drops names, so it offers no names
    /// item.
    private func showForwardOptions() {
        guard let forward = chatVM.pendingForward else { return }
        let prepared = forward.prepared
        var actions = [TelegramContextMenuAction]()
        if prepared.canToggleSenderNames, chatVM.customChat.secretChatID == nil {
            let hidden = forward.mode.removesSender
            let key =
                switch (hidden, forward.authorCount == 1) {
                case (true, true): "Conversation.ForwardOptions.ShowSendersName"
                case (true, false): "Conversation.ForwardOptions.ShowSendersNames"
                case (false, true): "Conversation.ForwardOptions.HideSendersName"
                case (false, false): "Conversation.ForwardOptions.HideSendersNames"
                }
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(key),
                image: UIImage(systemName: hidden ? "person.crop.circle" : "person.crop.circle.badge.xmark"),
            ) { [weak self] in
                self?.updatePendingForward(forward.id) { $0.withSenderNames(shown: hidden) }
            })
        }
        if prepared.hasCaptions, prepared.canCopy {
            let hidden = forward.mode.removesCaption
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(
                    hidden ? "Conversation.ForwardOptions.ShowCaption" : "Conversation.ForwardOptions.HideCaption",
                ),
                image: UIImage(systemName: hidden ? "text.bubble" : "text.bubble.fill"),
            ) { [weak self] in
                self?.updatePendingForward(forward.id) { $0.withCaptions(shown: hidden) }
            })
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("Conversation.ForwardOptions.ChangeRecipient"),
            image: UIImage(systemName: "arrow.triangle.2.circlepath"),
            startsNewSection: !actions.isEmpty,
        ) { [weak self] in
            guard let self, chatVM.pendingForward?.id == forward.id,
                  let current = chatVM.pendingForward else { return }
            onChangeForwardRecipient?(current)
        })
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("Conversation.ForwardOptionsCancel"),
            image: UIImage(systemName: "trash"),
            isDestructive: true,
        ) { [weak self] in
            guard let self, chatVM.pendingForward?.id == forward.id else { return }
            chatVM.pendingForward = nil
        })
        nearestViewController?.presentTelegramContextMenu(
            sourceView: replySnippet,
            actions: actions,
            presentationStyle: .menuOnly,
        )
    }

    private func updatePendingForward(
        _ id: UUID,
        _ transform: (PendingMessageForward) -> PendingMessageForward,
    ) {
        guard let forward = chatVM.pendingForward, forward.id == id else { return }
        chatVM.pendingForward = transform(forward)
    }

    /// ChatTextInputPanelNode's send-as avatar: the current sender in the menu button's place while the chat offers a
    /// choice and no message is being edited.
    private func updateSendAsButton(canWrite: Bool) {
        let senders = chatVM.messageSenders
        let shows = canWrite && !senders.isEmpty && chatVM.editCustomMessage == nil
        if sendAsButton.isHidden == shows { sendAsButton.isHidden = !shows }
        guard shows, let sender = chatVM.messageSenderID ?? senders.first?.sender else { return }
        sendAsButton.show(sender, client: chatVM.client)
    }

    /// ChatTextInputPanelNode's menu button reads "Menu", or a Web App menu's text with the app icon, while the input
    /// is empty and folds to its icon while typing.
    private func updateBotMenuButton(expanded: Bool) {
        guard var configuration = botMenuButton.configuration else { return }
        let webApp = chatVM.botMenuWebApp
        let text = webApp?.text ?? L10n.telegram("Conversation.InputMenu")
        let symbol = webApp == nil ? "line.3.horizontal" : "macwindow"
        let title: AttributedString? = expanded
            ? AttributedString(
                text,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]),
            )
            : nil
        botMenuButton.accessibilityLabel = text
        guard configuration.attributedTitle != title || botMenuButtonSymbol != symbol else { return }
        configuration.attributedTitle = title
        if botMenuButtonSymbol != symbol {
            botMenuButtonSymbol = symbol
            configuration.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
            )
        }
        botMenuButton.configuration = configuration
    }

    /// ChatInterfaceInputContextPanels: stickers for a lone emoji, hashtags, mentions, emoji for a ":" keyword, an
    /// inline bot's results, the commands matching the typed "/", or the Menu's whole command list, in that order.
    /// Editing a message keeps the hashtag, mention and emoji panels, as Telegram's edit mode does.
    private func updateSuggestions(enabled: Bool) {
        let commands = chatVM.commandSuggestions
        let isEditing = chatVM.editCustomMessage != nil
        let content: ChatInputSuggestionsView.Content =
            if !enabled {
                .hidden
            } else if !isEditing, chatVM.canSendStickersAndAnimations, !chatVM.stickerSuggestions.isEmpty {
                .stickers(chatVM.stickerSuggestions)
            } else if let hashtags = chatVM.hashtagSuggestions, !hashtags.rows.isEmpty {
                .hashtags(hashtags)
            } else if !chatVM.mentionSuggestions.isEmpty {
                .mentions(chatVM.mentionSuggestions)
            } else if !chatVM.emojiSuggestions.isEmpty {
                .emojis(chatVM.emojiSuggestions, caretX: suggestionsCaretX())
            } else if isEditing {
                .hidden
            } else if let inline = chatVM.inlineBotQuery {
                .inline(inline)
            } else if !commands.isEmpty {
                .commands(commands, showsBotNames: Set(chatVM.botCommands.map(\.botUserID)).count > 1)
            } else if chatVM.showsBotCommandMenu, chatVM.showsBotMenuButton {
                .commands(chatVM.botCommands, showsBotNames: false)
            } else {
                .hidden
            }
        suggestionsView.configure(content, client: chatVM.client)
    }

    /// MentionChatInputContextPanelNode follows the "@" word at the caret; an "@" opening the input also lists
    /// recently used inline bots.
    private func refreshMentionQuery() {
        let mention = textView.mentionQueryRange()
        chatVM.updateMentionQuery(mention?.query, includesInlineBots: mention?.range.location == 0)
        let context = textView.contextQuery()?.query
        let allowsContext =
            switch context {
            case .stickers: chatVM.editCustomMessage == nil && chatVM.canSendStickersAndAnimations
            case .emojiSearch,
                 .hashtag,
                 nil: true
            }
        chatVM.updateContextQuery(allowsContext ? context : nil)
    }

    /// ChatTextInputPanelNode's caret in the suggestions panel, where the emoji bubble's arrow points.
    private func suggestionsCaretX() -> CGFloat? {
        guard let position = textView.selectedTextRange?.end else { return nil }
        let caret = textView.caretRect(for: position)
        guard caret.origin.x.isFinite else { return nil }
        return textView.convert(caret, to: suggestionsView).midX
    }

    /// HashtagChatInputPanelItem's pick: "hashtag " in place of the word after "#".
    private func insertHashtag(_ hashtag: String) {
        guard let query = textView.contextQuery(), case .hashtag = query.query else { return }
        textView.replaceText(in: query.range, with: NSAttributedString(string: hashtag + " "))
    }

    /// EmojisChatInputContextPanelNode's pick: the emoji in place of ":keyword".
    private func insertSuggestedEmoji(_ emoji: String) {
        guard let query = textView.contextQuery(), case .emojiSearch = query.query else { return }
        textView.replaceText(in: query.range, with: NSAttributedString(string: emoji))
    }

    /// MentionChatInputContextPanelNode's pick: "@username " in place of the typed word, or for someone without a
    /// username their short name as a text mention (ChatTextInputTextMentionAttribute).
    private func insertMention(_ mention: ChatMentionSuggestion) {
        guard let query = textView.mentionQueryRange() else { return }
        textView.replaceText(
            in: query.range,
            with: ComposerText.uiKit(ComposerText.attributed(Self.mentionText(mention))),
        )
    }

    /// WebpagePreviewAccessoryPanelNode: the site, then the page's title or description; a tap opens the options.
    private func configureLinkPreviewPanel(_ preview: TDNativeLinkPreview) {
        showsLinkPreviewPanel = true
        closeReplyButton.isHidden = false
        let pageDescription = preview.description.text.trimmingCharacters(in: .whitespacesAndNewlines)
        replySnippet.configure(
            title: preview.siteName.isEmpty ? preview.displayUrl : preview.siteName,
            text: preview.title.isEmpty
                ? (pageDescription.isEmpty ? preview.displayUrl : pageDescription)
                : preview.title,
        ) { [weak self] in
            self?.showLinkPreviewOptions()
        }
    }

    /// ChatMessageActionOptions' link options: Move Up / Move Down, Enlarge or Shrink the media where the preview
    /// can change its size, and Do Not Preview.
    private func showLinkPreviewOptions() {
        guard let preview = chatVM.visibleComposerLinkPreview else { return }
        let options = chatVM.visibleLinkPreviewOptions
        let isAbove = options?.showAboveText ?? preview.showAboveText
        var actions = [TelegramContextMenuAction(
            title: L10n.telegram(isAbove
                ? "Conversation.MessageOptionsLinkMoveDown"
                : "Conversation.MessageOptionsLinkMoveUp"),
            image: UIImage(systemName: isAbove ? "arrow.down.to.line" : "arrow.up.to.line"),
        ) { [weak self] in
            self?.chatVM.setComposerLinkPreviewAboveText(!isAbove)
        }]
        if preview.hasLargeMedia {
            let isLarge = options.map { $0.forceLargeMedia || (!$0.forceSmallMedia && preview.showLargeMedia) }
                ?? preview.showLargeMedia
            let isVideo =
                switch preview.type {
                case .linkPreviewTypeAnimation,
                     .linkPreviewTypeEmbeddedAnimationPlayer,
                     .linkPreviewTypeEmbeddedVideoPlayer,
                     .linkPreviewTypeExternalVideo,
                     .linkPreviewTypeVideo:
                    true
                default:
                    false
                }
            let key =
                switch (isLarge, isVideo) {
                case (true, true): "Conversation.MessageOptionsShrinkVideo"
                case (true, false): "Conversation.MessageOptionsShrinkImage"
                case (false, true): "Conversation.MessageOptionsEnlargeVideo"
                case (false, false): "Conversation.MessageOptionsEnlargeImage"
                }
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(key),
                image: UIImage(systemName: isLarge
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right"),
            ) { [weak self] in
                self?.chatVM.setComposerLinkPreviewLargeMedia(!isLarge)
            })
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("Conversation.LinkOptionsCancel"),
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in
            self?.chatVM.disableComposerLinkPreview()
        })
        nearestViewController?.presentTelegramContextMenu(
            sourceView: replySnippet,
            actions: actions,
            presentationStyle: .menuOnly,
        )
    }

    @objc private func cancelReplyOrEdit() {
        // The link panel's × turns the preview off, also while editing. Editing hides a pending forward without
        // owning it: closing the edit brings the forward panel back.
        if showsLinkPreviewPanel {
            chatVM.disableComposerLinkPreview()
        } else if chatVM.editCustomMessage != nil {
            chatVM.cancelMessageEditing()
        } else {
            chatVM.pendingForward = nil
            chatVM.cancelReply()
        }
    }

    @objc private func actionTapped(_ sender: UIButton) {
        if sender === actionButton, voiceGestureSuppressesButtonAction {
            voiceGestureSuppressesButtonAction = false
            return
        }
        if videoNoteState.isActive {
            setVoiceGestureDeferral(false)
            switch videoNoteState {
            case .holding,
                 .locked,
                 .preview:
                onSendVideoNoteRecording?()
            case .failed,
                 .idle,
                 .preparing,
                 .sending,
                 .stopping:
                break
            }
            return
        }
        if chatVM.recordingVoiceNote {
            setVoiceGestureDeferral(false)
            chatVM.mediaStopRecordingVoice()
            return
        }
        let hasContent = !chatVM.displayedImages.isEmpty
            || !chatVM.displayedDocuments.isEmpty
            || !chatVM.text.characters.isEmpty
            || !chatVM.editMessageText.characters.isEmpty
            || chatVM.editCustomMessage != nil
            || chatVM.pendingForward != nil
        if chatVM.hasPendingVoiceNote, !hasContent {
            if chatVM.canRetryPendingVoiceNote {
                chatVM.retryPendingVoiceNote()
            }
            return
        }
        if chatVM.hasPendingVideoNote, !hasContent {
            if chatVM.canRetryPendingVideoNote {
                chatVM.retryPendingVideoNote()
            }
            return
        }
        guard hasContent else {
            if UIAccessibility.isVoiceOverRunning {
                startLockedRecordingForAccessibility()
            } else {
                toggleMediaRecordingMode()
                showMediaRecordingModeTooltip()
            }
            return
        }
        guard !chatVM.sendingComposerMessage else { return }
        send(options: nil)
    }

    /// ChatSendMessageContextScreen's items: Move Caption Up or Down for captioned media, Send Without Sound and Send
    /// When Online (not for reminders), then Schedule Message or, in Saved Messages, Set a Reminder. Picked photos and
    /// videos add MediaPickerScreen's menu: Send as File, Send Without Grouping and Hide With Spoiler.
    @objc private func showSendOptions(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, chatVM.locationContextIsCurrent else { return }
        let reminders = chatVM.customChat.isSavedMessages
        let mediaCount = chatVM.editCustomMessage == nil ? chatVM.displayedImages.count : 0
        var actions = [TelegramContextMenuAction]()
        if mediaCount > 0, !chatVM.text.characters.isEmpty {
            let isAbove = chatVM.mediaCaptionIsAbove
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isAbove
                    ? "Chat.SendMessageMenu.MoveCaptionDown"
                    : "Chat.SendMessageMenu.MoveCaptionUp"),
                image: UIImage(systemName: isAbove ? "text.below.photo" : "text.above.photo"),
            ) { [weak self] in
                self?.toggleMediaCaptionPosition()
            })
        }
        if !reminders {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.SendMessage.SendSilently"),
                image: UIImage(systemName: "bell.slash"),
                startsNewSection: !actions.isEmpty,
            ) { [weak self] in
                self?.send(options: ChatVM.sendOptions(silent: true))
            })
            if chatVM.canSendWhenOnline {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.SendMessage.SendWhenOnline"),
                    image: UIImage(systemName: "person.crop.circle.badge.clock"),
                ) { [weak self] in
                    self?.send(options: ChatVM.sendOptions(schedulingState: .messageSchedulingStateSendWhenOnline))
                })
            }
        }
        if chatVM.canScheduleMessages {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(reminders
                    ? "Conversation.SendMessage.SetReminder"
                    : "Conversation.SendMessage.ScheduleMessage"),
                image: UIImage(systemName: "calendar.badge.clock"),
                startsNewSection: reminders && !actions.isEmpty,
            ) { [weak self] in
                self?.onScheduleMessage?()
            })
        }
        if mediaCount > 0 {
            actions += mediaSendActions(count: mediaCount)
        }
        nearestViewController?.presentTelegramContextMenu(
            sourceView: actionButton,
            actions: actions,
            tracking: gesture,
            presentationStyle: .sourceMorph,
        )
    }

    /// MediaPickerScreen's media menu: Send as File(s) without spoilers, Send Without Grouping for several items, and
    /// Hide With Spoiler or Disable Spoiler outside secret chats.
    private func mediaSendActions(count: Int) -> [TelegramContextMenuAction] {
        var actions = [TelegramContextMenuAction]()
        let hasSpoilers = chatVM.displayedImages.contains(where: \.hasSpoiler)
        let hasGeneric = chatVM.displayedImages.contains { !$0.hasSpoiler }
        if !hasSpoilers, chatVM.canAttachDocuments {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(count > 1 ? "Attachment.SendAsFiles" : "Attachment.SendAsFile"),
                image: UIImage(systemName: "doc"),
                startsNewSection: true,
            ) { [weak self] in
                self?.send(options: nil, mediaMode: .files)
            })
        }
        if count > 1 {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Attachment.SendWithoutGrouping"),
                image: UIImage(systemName: "rectangle.split.2x2"),
                startsNewSection: actions.isEmpty,
            ) { [weak self] in
                self?.send(options: nil, mediaMode: .separately)
            })
        }
        if chatVM.canHideMediaWithSpoiler {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(hasGeneric ? "Attachment.EnableSpoiler" : "Attachment.DisableSpoiler"),
                image: UIImage(systemName: hasGeneric ? "eye.slash" : "eye"),
                startsNewSection: true,
            ) { [weak self] in
                self?.chatVM.setDisplayedMediaSpoiler(hasGeneric)
            })
        }
        return actions
    }

    /// ChatSendMessageContextScreen's caption position, with MediaPickerScreen's toast naming where it went.
    private func toggleMediaCaptionPosition() {
        chatVM.mediaCaptionIsAbove.toggle()
        guard let host = nearestViewController?.view else { return }
        TelegramUndoToast.show(
            text: L10n.telegram(chatVM.mediaCaptionIsAbove
                ? "MediaPicker.InvertCaption.Updated.Up.Title"
                : "MediaPicker.InvertCaption.Updated.Down.Title"),
            in: host,
            bottomInset: bounds.height + 8,
            undo: nil,
        )
    }

    @objc private func actionTouchDown(_ sender: UIButton) {
        guard sender === actionButton else { return }
        voiceGestureSuppressesButtonAction = false
    }

    private func startLockedRecordingForAccessibility() {
        let mode = selectedMediaRecordingMode
        Task { [weak self, weak chatVM] in
            guard let self, let chatVM else { return }
            let started: Bool =
                switch mode {
                case .voice:
                    await chatVM.mediaStartRecordingVoice()
                case .video:
                    await onStartVideoNoteRecording?() ?? false
                }
            guard started else { return }
            switch mode {
            case .voice:
                chatVM.lockVoiceRecording()
            case .video:
                onLockVideoNoteRecording?()
            }
        }
    }

    /// ChatController's displayMediaRecordingModeTooltip: how to record in the mode the tap left, and how to switch
    /// where both are allowed.
    private func showMediaRecordingModeTooltip() {
        guard !videoNoteState.isActive, !chatVM.recordingVoiceNote, let host = window else { return }
        let canSwitch = chatVM.canRecordVoiceNote && chatVM.canRecordVideoNote
        let key =
            switch (selectedMediaRecordingMode, canSwitch) {
            case (.voice, true): "Conversation.HoldForAudio"
            case (.voice, false): "Conversation.HoldForAudioOnly"
            case (.video, true): "Conversation.HoldForVideo"
            case (.video, false): "Conversation.HoldForVideoOnly"
            }
        TelegramTextTooltipView.show(
            L10n.telegram(key),
            source: actionButton.convert(actionButton.bounds, to: host),
            in: host,
            topInset: host.safeAreaInsets.top,
            padding: 2,
        )
    }

    private func toggleMediaRecordingMode() {
        guard !videoNoteState.isActive, !chatVM.recordingVoiceNote, chatVM.canRecordVoiceNote,
              chatVM.canRecordVideoNote else { return }
        selectedMediaRecordingMode = selectedMediaRecordingMode == .voice ? .video : .voice
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        updateActionButton()
    }

    @objc private func actionLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if voiceGestureIgnoresRecognizerSequence {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                voiceGestureIgnoresRecognizerSequence = false
            }
            return
        }
        if voiceGestureAwaitingPrearmLock {
            if gesture.state == .began {
                voiceGestureIgnoresRecognizerSequence = true
            } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                voiceGestureContactEnded = true
                setVoiceGestureDeferral(false)
                resetVoiceGestureButtonSuppressionAfterCurrentEvent()
            }
            return
        }
        if gesture.state != .began, voiceGestureFinished {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                voiceGestureContactEnded = true
                setVoiceGestureDeferral(false)
                resetVoiceGestureButtonSuppressionAfterCurrentEvent()
            }
            return
        }
        switch gesture.state {
        case .began:
            guard !chatVM.finalizingVoiceNote,
                  !chatVM.startingVoiceNote,
                  !chatVM.loadingVoiceDraft,
                  !chatVM.hasPendingVoiceNote,
                  !chatVM.hasPendingVideoNote,
                  !videoNoteState.isActive,
                  chatVM.displayedImages.isEmpty,
                  chatVM.text.characters.isEmpty,
                  chatVM.editCustomMessage == nil
            else {
                voiceGestureIgnoresRecognizerSequence = true
                return
            }
            let point = gesture.location(in: self)
            voiceGestureStartPoint = point
            voiceGestureLastPoint = point
            voiceGestureLastTimestamp = CACurrentMediaTime()
            voiceGestureTranslation = .zero
            voiceGestureVelocity = .zero
            pendingVoiceGestureOutcome = nil
            voiceGestureFinished = false
            voiceGestureIsArmed = false
            voiceGestureIsTracking = true
            voiceGestureSuppressesButtonAction = false
            voiceGestureContactEnded = false
            voiceGestureAwaitingPrearmLock = false
            activeMediaRecordingMode = selectedMediaRecordingMode
            setVoiceGestureDeferral(true)
            voiceGestureGeneration &+= 1
            let generation = voiceGestureGeneration
            #if DEBUG
                if activeMediaRecordingMode == .voice,
                   ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures")
                {
                    log("Voice gesture smoke: began")
                }
            #endif
            voiceGestureArmTask?.cancel()
            let recordingMode = activeMediaRecordingMode
            voiceGestureArmTask = Task { [weak self] in
                guard let self else { return }
                try? await Task<Never, Never>.sleep(for: .milliseconds(190))
                guard !Task.isCancelled,
                      voiceGestureGeneration == generation,
                      voiceGestureIsTracking,
                      !voiceGestureFinished
                else { return }
                voiceGestureIsArmed = true
                voiceGestureSuppressesButtonAction = true
                recordingStartInFlight = true
                let started = await beginRecording(mode: recordingMode)
                recordingStartInFlight = false
                guard voiceGestureGeneration == generation else {
                    if started {
                        cancelRecordingForMode(recordingMode)
                    }
                    return
                }
                #if DEBUG
                    if recordingMode == .voice,
                       ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures")
                    {
                        log("Voice gesture smoke: recording=\(started)")
                    }
                    if recordingMode == .voice,
                       started,
                       ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-lock")
                    {
                        voiceGestureFinished = true
                        voiceGestureIsTracking = false
                        applyVoiceGestureOutcome(.lock)
                        if voiceGestureContactEnded {
                            resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                        }
                        return
                    }
                #endif
                if started, let outcome = pendingVoiceGestureOutcome {
                    pendingVoiceGestureOutcome = nil
                    voiceGestureAwaitingPrearmLock = false
                    voiceGestureFinished = true
                    voiceGestureIsTracking = false
                    applyVoiceGestureOutcome(outcome)
                    voiceGestureIsArmed = false
                    if voiceGestureContactEnded {
                        resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                    }
                } else if !started {
                    pendingVoiceGestureOutcome = nil
                    voiceGestureAwaitingPrearmLock = false
                    voiceGestureIsArmed = false
                    voiceGestureIsTracking = false
                    voiceGestureFinished = true
                    setVoiceGestureDeferral(false)
                    if voiceGestureContactEnded {
                        resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                    }
                }
            }
        case .changed:
            updateVoiceGestureMotion(gesture)
            if voiceGestureTranslation.x < -150 {
                if voiceGestureIsArmed {
                    finishVoiceGesture(with: .cancel)
                } else {
                    finishUnarmedVoiceGesture(consumed: true)
                }
            } else if voiceGestureTranslation.y < -110 {
                if voiceGestureIsArmed {
                    finishVoiceGesture(with: .lock)
                } else {
                    queuePrearmVoiceLock()
                }
            } else {
                updateRecordingStatus()
            }
        case .ended:
            voiceGestureContactEnded = true
            setVoiceGestureDeferral(false)
            updateVoiceGestureMotion(gesture, updateVelocity: false)
            if voiceGestureFinished {
                resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                return
            }
            guard voiceGestureIsArmed else {
                if pendingVoiceGestureOutcome == .lock {
                    resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                    return
                }
                finishUnarmedVoiceGesture()
                return
            }
            var horizontalDistance = min(0, voiceGestureTranslation.x)
            var verticalDistance = min(0, voiceGestureTranslation.y)
            if abs(horizontalDistance) > abs(verticalDistance) {
                verticalDistance = 0
            } else {
                horizontalDistance = 0
            }
            if horizontalDistance < -100 || voiceGestureVelocity.x < -400 {
                finishVoiceGesture(with: .cancel)
            } else if verticalDistance < -60 || voiceGestureVelocity.y < -400 {
                finishVoiceGesture(with: .lock)
            } else {
                finishVoiceGesture(with: .send)
            }
            resetVoiceGestureButtonSuppressionAfterCurrentEvent()
        case .cancelled,
             .failed:
            voiceGestureContactEnded = true
            setVoiceGestureDeferral(false)
            if voiceGestureFinished {
                resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                return
            }
            if !voiceGestureIsArmed {
                queuePrearmVoiceLock()
                resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                return
            }
            finishVoiceGesture(with: .lock)
            resetVoiceGestureButtonSuppressionAfterCurrentEvent()
        case .possible:
            break
        @unknown default:
            voiceGestureContactEnded = true
            setVoiceGestureDeferral(false)
            if voiceGestureFinished {
                resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                return
            }
            if !voiceGestureIsArmed {
                queuePrearmVoiceLock()
                resetVoiceGestureButtonSuppressionAfterCurrentEvent()
                return
            }
            finishVoiceGesture(with: .lock)
            resetVoiceGestureButtonSuppressionAfterCurrentEvent()
        }
    }

    private func beginRecording(mode: ChatMediaRecordingMode) async -> Bool {
        switch mode {
        case .voice:
            await chatVM.mediaStartRecordingVoice()
        case .video:
            await onStartVideoNoteRecording?() ?? false
        }
    }

    private func cancelRecordingForMode(_ mode: ChatMediaRecordingMode) {
        switch mode {
        case .voice:
            chatVM.cancelVoiceRecording()
        case .video:
            onCancelVideoNoteRecording?()
        }
    }

    private func finishUnarmedVoiceGesture(consumed: Bool = false) {
        voiceGestureArmTask?.cancel()
        voiceGestureIsTracking = false
        voiceGestureIsArmed = false
        voiceGestureFinished = true
        pendingVoiceGestureOutcome = nil
        voiceGestureAwaitingPrearmLock = false
        voiceGestureTranslation = .zero
        voiceGestureSuppressesButtonAction = consumed
        setVoiceGestureDeferral(false)
    }

    private func updateVoiceGestureMotion(
        _ gesture: UILongPressGestureRecognizer,
        updateVelocity: Bool = true,
    ) {
        let point = gesture.location(in: self)
        let timestamp = CACurrentMediaTime()
        let elapsed = max(0.001, timestamp - voiceGestureLastTimestamp)
        voiceGestureTranslation = CGPoint(
            x: point.x - voiceGestureStartPoint.x,
            y: point.y - voiceGestureStartPoint.y,
        )
        if updateVelocity {
            voiceGestureVelocity = CGPoint(
                x: (point.x - voiceGestureLastPoint.x) / elapsed,
                y: (point.y - voiceGestureLastPoint.y) / elapsed,
            )
        }
        voiceGestureLastPoint = point
        voiceGestureLastTimestamp = timestamp
    }

    private func finishVoiceGesture(with outcome: VoiceGestureOutcome) {
        guard !voiceGestureFinished else { return }
        voiceGestureFinished = true
        voiceGestureIsTracking = false
        if !voiceGestureIsArmed {
            voiceGestureArmTask?.cancel()
        }
        voiceGestureSuppressesButtonAction = true
        voiceGestureTranslation = .zero
        if !isRecordingReady(mode: activeMediaRecordingMode) {
            pendingVoiceGestureOutcome = outcome
            return
        }
        applyVoiceGestureOutcome(outcome)
    }

    private func applyVoiceGestureOutcome(_ outcome: VoiceGestureOutcome) {
        voiceGestureAwaitingPrearmLock = false
        #if DEBUG
            if activeMediaRecordingMode == .voice,
               ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures")
            {
                let name =
 switch outcome {
                case .cancel: "cancel"
                case .lock: "lock"
                case .send: "release"
                }
                log("Voice gesture smoke: \(name)")
            }
        #endif
        switch outcome {
        case .cancel:
            setVoiceGestureDeferral(false)
            cancelRecordingForMode(activeMediaRecordingMode)
        case .lock:
            setVoiceGestureDeferral(false)
            switch activeMediaRecordingMode {
            case .voice:
                chatVM.lockVoiceRecording()
            case .video:
                onLockVideoNoteRecording?()
            }
            updateRecordingStatus()
        case .send:
            guard isHoldingRecording(mode: activeMediaRecordingMode) else { return }
            setVoiceGestureDeferral(false)
            #if DEBUG
                if activeMediaRecordingMode == .voice,
                   ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures")
                {
                    chatVM.cancelVoiceRecording()
                    return
                }
            #endif
            switch activeMediaRecordingMode {
            case .voice:
                chatVM.mediaStopRecordingVoice()
            case .video:
                onSendVideoNoteRecording?()
            }
        }
        voiceGestureIsArmed = false
    }

    private func resetVoiceGestureButtonSuppressionAfterCurrentEvent() {
        // The matching touchUpInside consumes suppression. If UIKit omits that event,
        // the next intentional touchDown clears it before a new action can fire.
    }

    private func isRecordingReady(mode: ChatMediaRecordingMode) -> Bool {
        switch mode {
        case .voice:
            chatVM.recordingVoiceNote
        case .video:
            switch videoNoteState {
            case .holding,
                 .locked:
                true
            case .failed,
                 .idle,
                 .preparing,
                 .preview,
                 .sending,
                 .stopping:
                false
            }
        }
    }

    private func isHoldingRecording(mode: ChatMediaRecordingMode) -> Bool {
        switch mode {
        case .voice:
            return chatVM.voiceRecordingInteractionState == .holding
        case .video:
            if case .holding = videoNoteState { return true }
            return false
        }
    }

    private func finishVoiceGestureAfterExternalStop() {
        voiceGestureFinished = true
        voiceGestureIsTracking = false
        voiceGestureIsArmed = false
        pendingVoiceGestureOutcome = nil
        voiceGestureAwaitingPrearmLock = false
        voiceGestureTranslation = .zero
        voiceGestureSuppressesButtonAction = true
        setVoiceGestureDeferral(false)
    }

    private func queuePrearmVoiceLock() {
        pendingVoiceGestureOutcome = .lock
        voiceGestureAwaitingPrearmLock = true
        voiceGestureSuppressesButtonAction = true
    }

    private func setVoiceGestureDeferral(_ active: Bool) {
        guard voiceGestureDeferralActive != active else { return }
        voiceGestureDeferralActive = active
        onVoiceGestureActivityChange?(active)
    }

    @objc private func cancelRecording() {
        setVoiceGestureDeferral(false)
        if videoNoteState.isActive {
            onCancelVideoNoteRecording?()
        } else {
            chatVM.cancelVoiceRecording()
        }
    }

    private func updateViewOnceButton() {
        guard chatVM.canSendVoiceViewOnce else { return }
        let isOn = chatVM.sendsVoiceViewOnce
        recordingViewOnceButton.isHidden = false
        recordingViewOnceButton.setImage(UIImage(systemName: isOn ? "1.circle.fill" : "1.circle"), for: .normal)
        recordingViewOnceButton.tintColor = isOn ? .systemBlue : .secondaryLabel
        recordingViewOnceButton.accessibilityLabel = L10n.betterTG("Accessibility.PlayOnce")
        recordingViewOnceButton.accessibilityTraits = isOn ? [.button, .selected] : .button
    }

    /// ChatTextInputPanelNode.viewOncePressed: toggles play-once and explains it when turned on.
    @objc private func toggleViewOnce() {
        guard chatVM.canSendVoiceViewOnce else { return }
        chatVM.sendsVoiceViewOnce.toggle()
        updateViewOnceButton()
        if chatVM.sendsVoiceViewOnce {
            onViewOnceEnabled?(L10n.telegram("Chat.PlayVoiceMessageOnceTooltip"))
        }
    }

    @objc private func toggleRecordingPause() {
        if videoNoteState.isActive {
            if case .locked = videoNoteState {
                onPauseVideoNoteRecording?()
            } else if case .preview = videoNoteState {
                onRecordMoreVideoNoteRecording?()
            }
            return
        }
        switch chatVM.voiceRecordingInteractionState {
        case .locked:
            chatVM.pauseVoiceRecording()
        case .preview:
            if chatVM.voiceRecordingResumeRequiresTrimConfirmation {
                onConfirmVoiceTrimResume?()
            } else {
                chatVM.resumeVoiceRecording()
            }
        case .holding,
             .idle,
             .pausing,
             .resuming:
            break
        }
    }

    @objc private func toggleRecordingPreview() {
        if videoNoteState.isActive {
            onToggleVideoNotePreview?()
        } else {
            chatVM.toggleVoiceRecordingPreview()
        }
    }

    private func seekRecordingPreview(to progress: CGFloat) {
        chatVM.seekVoiceRecordingPreview(to: progress)
    }
}

// MARK: UIGestureRecognizerDelegate

/// The recognizer lives on the persistent composer, so hiding the input row when
/// recording starts cannot cancel the touch sequence.
extension ChatComposerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === recordingGestureRecognizer else { return true }
        return !inputRow.isHidden && !actionButton.isHidden
            && actionButton.bounds.contains(touch.location(in: actionButton))
    }
}

// MARK: - ComposerSendAsButton

/// ChatTextInputPanelNode's sendAsAvatarButtonNode: the sender's 33 pt avatar, which shrinks to 0.85 while pressed
/// and gives way to the menu button's close icon, an accent circle with a cross, while the senders are listed.
final class ComposerSendAsButton: UIControl {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.2) {
                self.avatarView.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.85, y: 0.85) : .identity
            }
        }
    }

    private let avatarView = ProfileAvatarView()
    private let closeView = UIImageView()
    private var shownSenderID: Int64?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        addSubview(avatarView)
        closeView.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
        )
        closeView.contentMode = .center
        // The cross is white on the accent; the view's own tint would turn `.tintColor` white too.
        closeView.backgroundColor = .systemBlue
        closeView.tintColor = .white
        closeView.isUserInteractionEnabled = false
        closeView.alpha = 0
        closeView.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
        addSubview(closeView)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = L10n.telegram("Conversation.SendMesageAs")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 33
        let frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        avatarView.bounds = CGRect(origin: .zero, size: frame.size)
        avatarView.center = CGPoint(x: frame.midX, y: frame.midY)
        closeView.bounds = avatarView.bounds
        closeView.center = avatarView.center
        closeView.layer.cornerRadius = side / 2
    }

    /// The sender's avatar, loaded once per sender.
    func show(_ sender: MessageSender, client: TDLibClient) {
        let id: Int64 =
            switch sender {
            case .messageSenderUser(let user): user.userId
            case .messageSenderChat(let chat): chat.chatId
            }
        guard shownSenderID != id else { return }
        shownSenderID = id
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let peer = await SettingsPeer.resolve(sender, client: client), !Task.isCancelled, let self else {
                return
            }
            avatarView.configure(
                file: peer.file,
                minithumbnail: peer.minithumbnail,
                placeholder: peer.placeholder,
                accountUserID: 0,
                client: client,
            )
            accessibilityValue = peer.title
        }
    }

    func setMenuOpen(_ open: Bool) {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.avatarView.alpha = open ? 0 : 1
            self.avatarView.transform = open ? CGAffineTransform(scaleX: 0.001, y: 0.001) : .identity
            self.closeView.alpha = open ? 1 : 0
            self.closeView.transform = open ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
        }
    }
}
