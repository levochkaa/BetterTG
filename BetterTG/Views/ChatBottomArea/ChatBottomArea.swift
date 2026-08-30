// ChatBottomArea.swift

import TDLibKitDynamic
import UIKit

// MARK: - ChatMediaRecordingMode

enum ChatMediaRecordingMode: Equatable {
    case video
    case voice
}

// MARK: - ChatComposerView

final class ChatComposerView: UIView {
    // MARK: Private

    private enum VoiceGestureOutcome {
        case cancel
        case lock
        case send
    }

    // MARK: Internal

    var onPickPhotos: (() -> Void)?
    var onTakePhoto: (() -> Void)?
    var onScrollToMessage: ((Int64) -> Void)?
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

    private let chatVM: ChatVM
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let rootStack = UIStackView()
    private let replyContainer = UIView()
    private let replyRow = UIStackView()
    private let replySnippet = ReplySnippetView()
    private let closeReplyButton = UIButton(type: .system)
    private let photosScroll = UIScrollView()
    private let photosStack = UIStackView()
    private let inputRow = UIStackView()
    private let attachmentButton = UIButton(type: .system)
    private let textView = FormattedTextView(placeholder: "Message…")
    private let actionButton = UIButton(type: .system)
    private let recordingRow = UIStackView()
    private let cancelRecordingButton = UIButton(type: .system)
    private let recordingPauseResumeButton = UIButton(type: .system)
    private let recordingPreviewPlayButton = UIButton(type: .system)
    private let recordingPreviewContainer = UIView()
    private let recordingPreviewWaveform = TelegramWaveformView()
    private let recordingTrimView = VoiceRecordingTrimView()
    private let videoNoteThumbnailStrip = VideoNoteThumbnailStripView()
    private let recordingLabel = UILabel()
    private let recordingSendButton = UIButton(type: .system)
    private lazy var recordingGestureRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(actionLongPressed(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = 1000
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private var displayedImageIDs = [UUID]()
    private var draftTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var isApplyingState = false
    private var hiddenForSearch = false
    private var keyboardAttached = false
    private var lastReplyID: Int64?
    private var lastEditID: Int64?
    private var replyContainerHeightConstraint: NSLayoutConstraint!
    private var replyPreviewVisible = false
    private var voiceGestureStartPoint = CGPoint.zero
    private var voiceGestureLastPoint = CGPoint.zero
    private var voiceGestureLastTimestamp = TimeInterval.zero
    private var voiceGestureTranslation = CGPoint.zero
    private var voiceGestureVelocity = CGPoint.zero
    private var pendingVoiceGestureOutcome: VoiceGestureOutcome?
    private var voiceGestureFinished = false
    private var voiceGestureIsArmed = false
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
    private var videoNoteTrimEditing = false
    private var videoNoteTrimSaving = false

    var isInputFocused: Bool {
        textView.isFirstResponder
    }

    private var isHoldingVideoNote: Bool {
        if case .holding = videoNoteState { return true }
        return false
    }

    private var isVideoNoteBusy: Bool {
        switch videoNoteState {
        case .preparing, .sending, .stopping:
            true
        case .failed, .holding, .idle, .locked, .preview:
            false
        }
    }

    init(chatVM: ChatVM) {
        self.chatVM = chatVM
        super.init(frame: .zero)
        configureViews()
        configureActions()
        update(from: chatVM)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focusInput() {
        textView.becomeFirstResponder()
    }

    func cancelActiveRecordingGesture() {
        voiceGestureGeneration &+= 1
        voiceGestureArmTask?.cancel()
        voiceGestureArmTask = nil
        if chatVM.recordingVoiceNote {
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

    func setVideoNoteReplyMessage(_ message: CustomMessage?) {
        videoNoteReplyMessage = message
        update(from: chatVM)
    }

    func setKeyboardAttached(_ attached: Bool) {
        guard keyboardAttached != attached else { return }
        keyboardAttached = attached
        layer.maskedCorners = attached
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    func setHiddenForSearch(_ hidden: Bool) {
        hiddenForSearch = hidden
        if hidden {
            textView.resignFirstResponder()
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
        let shouldFocus = lastReplyID != chatVM.replyMessage?.id || lastEditID != chatVM.editCustomMessage?.id
        lastReplyID = chatVM.replyMessage?.id
        lastEditID = chatVM.editCustomMessage?.id
        let targetText = chatVM.editCustomMessage == nil ? chatVM.text : chatVM.editMessageText
        textView.setAttributedText(targetText)

        let showsReplyPreview: Bool
        if let edited = chatVM.editCustomMessage {
            showsReplyPreview = true
            closeReplyButton.isHidden = false
            replySnippet.configure(title: "Edit message", message: edited.message) { [weak self] in
                self?.onScrollToMessage?(edited.id)
            }
        } else if videoNoteState.isActive, let videoNoteReplyMessage {
            showsReplyPreview = true
            closeReplyButton.isHidden = true
            replySnippet.configure(
                title: "Video reply · \(videoNoteReplyMessage.senderUser?.firstName ?? "Message")",
                message: videoNoteReplyMessage.message,
            ) { [weak self] in
                self?.onScrollToMessage?(videoNoteReplyMessage.id)
            }
        } else if targetText.characters.isEmpty,
                  let pendingReplyID = chatVM.pendingVideoReplyMessageID,
                  chatVM.hasPendingVideoNote
        {
            showsReplyPreview = true
            closeReplyButton.isHidden = true
            if let pendingReply = chatVM.pendingVideoReplyMessage {
                replySnippet.configure(
                    title: "Video reply · \(pendingReply.senderUser?.firstName ?? "Message")",
                    message: pendingReply.message,
                ) { [weak self] in
                    self?.onScrollToMessage?(pendingReply.id)
                }
            } else {
                replySnippet.configure(title: "Video reply", text: "Original replied message") { [weak self] in
                    self?.onScrollToMessage?(pendingReplyID)
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
                    title: "Voice reply · \(pendingReply.senderUser?.firstName ?? "Message")",
                    message: pendingReply.message,
                ) { [weak self] in
                    self?.onScrollToMessage?(pendingReply.id)
                }
            } else {
                replySnippet.configure(title: "Voice reply", text: "Original replied message") { [weak self] in
                    self?.onScrollToMessage?(pendingReplyID)
                }
            }
        } else if let reply = chatVM.replyMessage {
            showsReplyPreview = true
            closeReplyButton.isHidden = false
            replySnippet
                .configure(title: reply.senderUser?.firstName ?? "Reply", message: reply.message) { [weak self] in
                    self?.onScrollToMessage?(reply.id)
                }
        } else {
            showsReplyPreview = false
            closeReplyButton.isHidden = false
        }
        setReplyPreviewVisible(showsReplyPreview, animated: window != nil)

        let imageIDs = chatVM.displayedImages.map(\.id)
        if displayedImageIDs != imageIDs {
            displayedImageIDs = imageIDs
            rebuildPhotos()
        }
        photosScroll.isHidden = chatVM.displayedImages.isEmpty

        let isRecordingVideoNote = videoNoteState.isActive
        let isRecordingMedia = chatVM.recordingVoiceNote || isRecordingVideoNote
        inputRow.isHidden = isRecordingMedia
        recordingRow.isHidden = !isRecordingMedia
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
            if voiceGestureIsArmed, !chatVM.startingVoiceNote {
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
        isApplyingState = false
        if shouldFocus, lastReplyID != nil || lastEditID != nil {
            textView.becomeFirstResponder()
        }
    }

    private func configureViews() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.spacing = 0
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        closeReplyButton.accessibilityLabel = "Cancel reply or edit"
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

        inputRow.axis = .horizontal
        inputRow.alignment = .bottom
        inputRow.spacing = 8
        inputRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10)
        inputRow.isLayoutMarginsRelativeArrangement = true
        attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
        attachmentButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .regular),
            forImageIn: .normal,
        )
        attachmentButton.showsMenuAsPrimaryAction = true
        attachmentButton.accessibilityLabel = "Attach"
        textView.backgroundColor = .clear
        inputRow.addArrangedSubview(attachmentButton)
        inputRow.addArrangedSubview(textView)
        inputRow.addArrangedSubview(actionButton)
        NSLayoutConstraint.activate([
            attachmentButton.widthAnchor.constraint(equalToConstant: 34),
            attachmentButton.heightAnchor.constraint(equalToConstant: 36),
            actionButton.widthAnchor.constraint(equalToConstant: 34),
            actionButton.heightAnchor.constraint(equalToConstant: 36),
        ])

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
        cancelRecordingButton.accessibilityLabel = "Cancel voice recording"
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
        recordingPreviewWaveform.accessibilityLabel = "Voice recording preview waveform"
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
        recordingSendButton.accessibilityLabel = "Send voice message"
        recordingRow.addArrangedSubview(cancelRecordingButton)
        recordingRow.addArrangedSubview(recordingPauseResumeButton)
        recordingRow.addArrangedSubview(recordingPreviewPlayButton)
        recordingRow.addArrangedSubview(recordingPreviewContainer)
        recordingRow.addArrangedSubview(recordingLabel)
        recordingRow.addArrangedSubview(recordingSendButton)
        for button in [
            cancelRecordingButton,
            recordingPauseResumeButton,
            recordingPreviewPlayButton,
            recordingSendButton,
        ] {
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
        recordingPreviewContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        recordingPreviewContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        rootStack.addArrangedSubview(replyContainer)
        rootStack.addArrangedSubview(photosScroll)
        rootStack.addArrangedSubview(inputRow)
        rootStack.addArrangedSubview(recordingRow)
        rootStack.setCustomSpacing(6, after: photosScroll)
    }

    private func configureActions() {
        attachmentButton.menu = UIMenu(children: [
            UIAction(title: "Attach Photos", image: UIImage(systemName: "photo")) { [weak self] _ in
                self?.onPickPhotos?()
            },
            UIAction(title: "Take Photo", image: UIImage(systemName: "camera.fill")) { [weak self] _ in
                self?.onTakePhoto?()
            },
        ])
        closeReplyButton.addTarget(self, action: #selector(cancelReplyOrEdit), for: .touchUpInside)
        cancelRecordingButton.addTarget(self, action: #selector(cancelRecording), for: .touchUpInside)
        recordingPauseResumeButton.addTarget(self, action: #selector(toggleRecordingPause), for: .touchUpInside)
        recordingPreviewPlayButton.addTarget(self, action: #selector(toggleRecordingPreview), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionTouchDown(_:)), for: .touchDown)
        actionButton.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        recordingSendButton.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        actionButton.addGestureRecognizer(recordingGestureRecognizer)

        textView.onTextChange = { [weak self] text in self?.textChanged(text) }
        textView.onPasteImages = { [weak self] images in
            guard let self else { return }
            chatVM.displayedImages = Array(images.prefix(10))
        }
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
                self?.chatVM.displayedImages.removeAll(where: { $0.id == selectedImage.id })
            }, for: .touchUpInside)
            container.addSubview(imageView)
            container.addSubview(removeButton)
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

    private func textChanged(_ text: AttributedString) {
        guard !isApplyingState else { return }
        if chatVM.editCustomMessage == nil {
            chatVM.text = text
        } else {
            chatVM.editMessageText = text
        }
        updateActionButton()
        draftTask?.cancel()
        draftTask = Task { [weak chatVM] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await chatVM?.updateDraft()
        }
        typingTask?.cancel()
        typingTask = Task { [weak chatVM] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let chatVM else { return }
            try? await chatVM.tdSendChatAction(text.characters.isEmpty ? .chatActionCancel : .chatActionTyping)
        }
    }

    private func updateActionButton() {
        let hasContent = !chatVM.displayedImages.isEmpty
            || !chatVM.text.characters.isEmpty
            || !chatVM.editMessageText.characters.isEmpty
            || chatVM.editCustomMessage != nil
        let isPreparingVoice = chatVM.loadingVoiceDraft || chatVM.startingVoiceNote || chatVM.finalizingVoiceNote
        let isFinalizingVoice = isPreparingVoice && !hasContent
        let isFinalizingVideo = isVideoNoteBusy && !hasContent
        let isRetryingVoice = chatVM.canRetryPendingVoiceNote && !hasContent
        let isUncertainVoice = chatVM.hasPendingVoiceNote && !chatVM.canRetryPendingVoiceNote && !hasContent
        let isRetryingVideo = chatVM.canRetryPendingVideoNote && !hasContent
        let isUncertainVideo = chatVM.hasPendingVideoNote && !chatVM.canRetryPendingVideoNote && !hasContent
        let isRecordingMedia = chatVM.recordingVoiceNote || videoNoteState.isActive
        let symbol =
            if isFinalizingVoice || isFinalizingVideo {
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
        actionButton.setImage(UIImage(systemName: symbol), for: .normal)
        actionButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(
                pointSize: isRecordingMedia || hasContent ? 28 : 20,
                weight: isRecordingMedia || hasContent ? .regular : .medium,
            ),
            forImageIn: .normal,
        )
        actionButton.isEnabled = !isFinalizingVoice && !isFinalizingVideo
        actionButton.alpha = actionButton.isEnabled ? 1 : 0.55
        let canBeginRecordingGesture = !chatVM.startingVoiceNote
            && !chatVM.loadingVoiceDraft
            && !chatVM.finalizingVoiceNote
            && !chatVM.hasPendingVoiceNote
            && !chatVM.hasPendingVideoNote
            && !videoNoteState.isActive
            && !hasContent
        recordingGestureRecognizer.isEnabled = voiceGestureIsTracking || canBeginRecordingGesture
        if chatVM.hasPendingVoiceNote {
            var voiceActions = [UIAction]()
            if chatVM.canRetryPendingVoiceNote {
                voiceActions.append(UIAction(
                    title: "Retry Voice Message",
                    image: UIImage(systemName: "arrow.clockwise"),
                ) { [weak self] _ in
                    self?.chatVM.retryPendingVoiceNote()
                })
            }
            voiceActions.append(UIAction(
                title: "Discard Voice Message",
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { [weak self] _ in
                self?.chatVM.discardPendingVoiceNote()
            })
            actionButton.menu = UIMenu(children: voiceActions)
            actionButton.accessibilityHint = chatVM.canRetryPendingVoiceNote
                ? "Touch and hold for retry and discard options."
                : "Check the chat for the previous send, or touch and hold to discard."
        } else if chatVM.hasPendingVideoNote {
            var videoActions = [UIAction]()
            if chatVM.canRetryPendingVideoNote {
                videoActions.append(UIAction(
                    title: "Retry Video Message",
                    image: UIImage(systemName: "arrow.clockwise"),
                ) { [weak self] _ in
                    self?.chatVM.retryPendingVideoNote()
                })
            }
            videoActions.append(UIAction(
                title: "Discard Video Message",
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { [weak self] _ in
                self?.chatVM.discardPendingVideoNote()
            })
            actionButton.menu = UIMenu(children: videoActions)
            actionButton.accessibilityHint = chatVM.canRetryPendingVideoNote
                ? "Touch and hold for retry and discard options."
                : "Check the chat for the previous send, or touch and hold to discard."
        } else {
            actionButton.menu = nil
            actionButton.accessibilityHint = UIAccessibility.isVoiceOverRunning && !hasContent
                ? "Double-tap to start a locked \(selectedMediaRecordingMode == .video ? "video" : "voice") recording."
                : nil
        }
        actionButton.accessibilityLabel =
            if isFinalizingVoice || isFinalizingVideo {
                selectedMediaRecordingMode == .video ? "Preparing video message" : "Preparing voice message"
            } else if isRetryingVoice {
                "Retry voice message"
            } else if isUncertainVoice {
                "Voice message send status unknown"
            } else if isRetryingVideo {
                "Retry video message"
            } else if isUncertainVideo {
                "Video message send status unknown"
            } else {
                isRecordingMedia || hasContent
                    ? "Send"
                    : selectedMediaRecordingMode == .video ? "Record video message" : "Record voice message"
            }
    }

    private func updateRecordingStatus() {
        if videoNoteState.isActive {
            updateVideoRecordingStatus()
            return
        }
        cancelRecordingButton.accessibilityLabel = "Cancel voice recording"
        videoNoteThumbnailStrip.isHidden = true
        recordingPreviewWaveform.isHidden = false
        recordingSendButton.accessibilityLabel = "Send voice message"
        recordingLabel.textColor = .systemRed
        recordingPreviewPlayButton.isHidden = true
        recordingPreviewContainer.isHidden = true
        recordingPauseResumeButton.isHidden = true
        recordingSendButton.isEnabled = true
        recordingSendButton.alpha = 1
        switch chatVM.voiceRecordingInteractionState {
        case .locked:
            recordingLabel.text = "● \(chatVM.formattedTimerCount)  Locked"
            recordingLabel.accessibilityLabel = "Voice recording locked, \(chatVM.formattedTimerCount)"
            recordingPauseResumeButton.isHidden = false
            recordingPauseResumeButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = "Pause voice recording"
            recordingPauseResumeButton.isEnabled = chatVM.canPauseVoiceRecording
            recordingPauseResumeButton.alpha = chatVM.canPauseVoiceRecording ? 1 : 0.45
            recordingSendButton.isHidden = false
        case .holding:
            if voiceGestureTranslation.x <= -70 {
                recordingLabel.text = "← Release to cancel"
            } else if voiceGestureTranslation.y <= -45 {
                recordingLabel.text = "↑ Release to lock"
            } else {
                recordingLabel.text = "● \(chatVM.formattedTimerCount)  ← Cancel  ↑ Lock"
            }
            recordingLabel.accessibilityLabel = "Recording voice message, \(chatVM.formattedTimerCount)"
            recordingSendButton.isHidden = true
        case .preview:
            let previewPath = chatVM.voiceRecordingPreviewPath
            let isPlaying = chatVM.voiceRecordingPreviewIsPlaying
            recordingPauseResumeButton.isHidden = false
            recordingPauseResumeButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = "Resume voice recording"
            recordingPauseResumeButton.isEnabled = chatVM.voiceRecordingPreviewReady
            recordingPauseResumeButton.alpha = chatVM.voiceRecordingPreviewReady ? 1 : 0.45
            recordingPreviewPlayButton.isHidden = false
            recordingPreviewPlayButton.setImage(
                UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"),
                for: .normal,
            )
            recordingPreviewPlayButton.accessibilityLabel = isPlaying
                ? "Pause voice recording preview"
                : "Play voice recording preview"
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
                "Voice recording preview, \(chatVM.formattedVoiceRecordingPreviewDuration)"
            recordingSendButton.isHidden = false
            recordingSendButton.isEnabled = chatVM.voiceRecordingPreviewReady
            recordingSendButton.alpha = chatVM.voiceRecordingPreviewReady ? 1 : 0.45
        case .pausing:
            recordingLabel.text = "Preparing…"
            recordingLabel.accessibilityLabel = "Preparing voice recording preview"
            recordingSendButton.isHidden = true
        case .resuming:
            recordingLabel.text = "Resuming…"
            recordingLabel.accessibilityLabel = "Resuming voice recording"
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
        cancelRecordingButton.accessibilityLabel = "Cancel video message"
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
            recordingLabel.text = "Preparing camera…"
            recordingLabel.accessibilityLabel = "Preparing video-message camera"
        case .holding(let duration):
            if voiceGestureTranslation.x <= -70 {
                recordingLabel.text = "← Release to cancel"
            } else if voiceGestureTranslation.y <= -45 {
                recordingLabel.text = "↑ Release to lock"
            } else {
                recordingLabel.text = "● \(formatVideoDuration(duration))  ← Cancel  ↑ Lock"
            }
            recordingLabel.accessibilityLabel = "Recording video message, \(formatVideoDuration(duration))"
        case .locked(let duration):
            recordingLabel.text = "● \(formatVideoDuration(duration))  Locked"
            recordingLabel.accessibilityLabel = "Video recording locked, \(formatVideoDuration(duration))"
            recordingPauseResumeButton.isHidden = false
            recordingPauseResumeButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = "Stop video recording for preview"
            recordingSendButton.isHidden = false
            recordingSendButton.accessibilityLabel = "Send video message"
        case .preview(let duration, let isPlaying, let canRecordMore):
            let trimControlsBlocked = videoNoteTrimEditing || videoNoteTrimSaving
            recordingLabel.textColor = .label
            recordingLabel.text = formatVideoDuration(duration)
            recordingLabel.accessibilityLabel = "Video message preview, \(formatVideoDuration(duration))"
            recordingPreviewPlayButton.isHidden = false
            recordingPreviewPlayButton.setImage(
                UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"),
                for: .normal,
            )
            recordingPreviewPlayButton.accessibilityLabel = isPlaying
                ? "Pause video message preview"
                : "Play video message preview"
            recordingPreviewContainer.isHidden = false
            videoNoteThumbnailStrip.isHidden = false
            videoNoteThumbnailStrip.setEditingEnabled(!videoNoteTrimSaving)
            recordingPauseResumeButton.isHidden = !canRecordMore
            recordingPauseResumeButton.setImage(UIImage(systemName: "video.badge.plus"), for: .normal)
            recordingPauseResumeButton.accessibilityLabel = "Record more video"
            recordingSendButton.isHidden = false
            recordingSendButton.accessibilityLabel = "Send video message"
            for button in [recordingPauseResumeButton, recordingPreviewPlayButton, recordingSendButton] {
                button.isEnabled = !trimControlsBlocked
                button.alpha = trimControlsBlocked ? 0.45 : 1
            }
        case .stopping:
            recordingLabel.text = "Preparing preview…"
            recordingLabel.accessibilityLabel = "Preparing video message preview"
        case .sending:
            recordingLabel.text = "Sending…"
            recordingLabel.accessibilityLabel = "Sending video message"
        case .failed(let message):
            recordingLabel.text = message
            recordingLabel.accessibilityLabel = message
        case .idle:
            recordingLabel.text = nil
            recordingLabel.accessibilityLabel = nil
        }
    }

    private func formatVideoDuration(_ duration: Double) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @objc private func cancelReplyOrEdit() {
        chatVM.replyMessage = nil
        chatVM.editCustomMessage = nil
        chatVM.editMessageText = ""
    }

    @objc private func actionTapped(_ sender: UIButton) {
        if sender === actionButton, voiceGestureSuppressesButtonAction {
            voiceGestureSuppressesButtonAction = false
            return
        }
        if videoNoteState.isActive {
            setVoiceGestureDeferral(false)
            switch videoNoteState {
            case .holding, .locked, .preview:
                onSendVideoNoteRecording?()
            case .failed, .idle, .preparing, .sending, .stopping:
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
            || !chatVM.text.characters.isEmpty
            || !chatVM.editMessageText.characters.isEmpty
            || chatVM.editCustomMessage != nil
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
            }
            return
        }
        chatVM.sendMessageTask?.cancel()
        chatVM.sendMessageTask = Task { [weak chatVM] in await chatVM?.sendMessage() }
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

    private func toggleMediaRecordingMode() {
        guard !videoNoteState.isActive, !chatVM.recordingVoiceNote else { return }
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
                let started = await beginRecording(mode: recordingMode)
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
        case .cancelled, .failed:
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
            case .holding, .locked:
                true
            case .failed, .idle, .preparing, .preview, .sending, .stopping:
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
        case .holding, .idle, .pausing, .resuming:
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
