// ChatBottomArea.swift

import TDLibKitDynamic
import UIKit

final class ChatComposerView: UIView {
    // MARK: Lifecycle

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

    // MARK: Internal

    var onPickPhotos: (() -> Void)?
    var onTakePhoto: (() -> Void)?
    var onScrollToMessage: ((Int64) -> Void)?
    var onVoiceGestureActivityChange: ((Bool) -> Void)?

    var isInputFocused: Bool {
        textView.isFirstResponder
    }

    func focusInput() {
        textView.becomeFirstResponder()
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

        if let edited = chatVM.editCustomMessage {
            replyRow.isHidden = false
            closeReplyButton.isHidden = false
            replySnippet.configure(title: "Edit message", message: edited.message) { [weak self] in
                self?.onScrollToMessage?(edited.id)
            }
        } else if targetText.characters.isEmpty,
                  let pendingReplyID = chatVM.pendingVoiceReplyMessageID,
                  chatVM.hasPendingVoiceNote || chatVM.finalizingVoiceNote
        {
            replyRow.isHidden = false
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
            replyRow.isHidden = false
            closeReplyButton.isHidden = false
            replySnippet
                .configure(title: reply.senderUser?.firstName ?? "Reply", message: reply.message) { [weak self] in
                    self?.onScrollToMessage?(reply.id)
                }
        } else {
            replyRow.isHidden = true
            closeReplyButton.isHidden = false
        }

        let imageIDs = chatVM.displayedImages.map(\.id)
        if displayedImageIDs != imageIDs {
            displayedImageIDs = imageIDs
            rebuildPhotos()
        }
        photosScroll.isHidden = chatVM.displayedImages.isEmpty

        inputRow.isHidden = chatVM.recordingVoiceNote
        recordingRow.isHidden = !chatVM.recordingVoiceNote
        if chatVM.recordingVoiceNote {
            setVoiceGestureDeferral(
                chatVM.voiceRecordingInteractionState == .holding
                    && voiceGestureIsTracking
                    && !voiceGestureContactEnded,
            )
            if chatVM.timer == nil {
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

    // MARK: Private

    private enum VoiceGestureOutcome {
        case cancel
        case lock
        case send
    }

    private let chatVM: ChatVM
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let rootStack = UIStackView()
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
        rootStack.spacing = 6
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rootStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -7),
        ])

        replyRow.axis = .horizontal
        replyRow.alignment = .center
        replyRow.spacing = 6
        closeReplyButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeReplyButton.accessibilityLabel = "Cancel reply or edit"
        replyRow.addArrangedSubview(replySnippet)
        replyRow.addArrangedSubview(closeReplyButton)
        replySnippet.setContentHuggingPriority(.defaultLow, for: .horizontal)

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
        recordingRow.spacing = 10
        cancelRecordingButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelRecordingButton.accessibilityLabel = "Cancel voice recording"
        recordingLabel.textColor = .label
        recordingLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        recordingLabel.textAlignment = .center
        recordingSendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        recordingSendButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 28),
            forImageIn: .normal,
        )
        recordingSendButton.accessibilityLabel = "Send voice message"
        recordingRow.addArrangedSubview(cancelRecordingButton)
        let leadingRecordingSpacer = UIView()
        leadingRecordingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recordingRow.addArrangedSubview(leadingRecordingSpacer)
        recordingRow.addArrangedSubview(recordingLabel)
        let trailingRecordingSpacer = UIView()
        trailingRecordingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recordingRow.addArrangedSubview(trailingRecordingSpacer)
        recordingRow.addArrangedSubview(recordingSendButton)
        cancelRecordingButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        cancelRecordingButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        leadingRecordingSpacer.widthAnchor.constraint(equalTo: trailingRecordingSpacer.widthAnchor).isActive = true
        recordingSendButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        recordingSendButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        rootStack.addArrangedSubview(replyRow)
        rootStack.addArrangedSubview(photosScroll)
        rootStack.addArrangedSubview(inputRow)
        rootStack.addArrangedSubview(recordingRow)
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
        actionButton.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        recordingSendButton.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        actionButton.addGestureRecognizer(recordingGestureRecognizer)

        textView.onTextChange = { [weak self] text in self?.textChanged(text) }
        textView.onPasteImages = { [weak self] images in
            guard let self else { return }
            chatVM.displayedImages = Array(images.prefix(10))
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
        recordingRow.spacing = 10
        recordingRow.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: 0,
            bottom: 0,
            trailing: 10,
        )
        recordingRow.isLayoutMarginsRelativeArrangement = true
        cancelRecordingButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelRecordingButton.accessibilityLabel = "Cancel voice recording"
        recordingLabel.textColor = .label
        recordingLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        recordingLabel.textAlignment = .center
        recordingSendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        recordingSendButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 28),
            forImageIn: .normal,
        )
        recordingSendButton.accessibilityLabel = "Send voice message"
        recordingRow.addArrangedSubview(cancelRecordingButton)
        let leadingRecordingSpacer = UIView()
        leadingRecordingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recordingRow.addArrangedSubview(leadingRecordingSpacer)
        recordingRow.addArrangedSubview(recordingLabel)
        let trailingRecordingSpacer = UIView()
        trailingRecordingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recordingRow.addArrangedSubview(trailingRecordingSpacer)
        recordingRow.addArrangedSubview(recordingSendButton)
        cancelRecordingButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        cancelRecordingButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        leadingRecordingSpacer.widthAnchor.constraint(equalTo: trailingRecordingSpacer.widthAnchor).isActive = true
        recordingSendButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        recordingSendButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

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
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        recordingSendButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        actionButton.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self,
            action: #selector(actionLongPressed(_:)),
        ))

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
        let isRetryingVoice = chatVM.canRetryPendingVoiceNote && !hasContent
        let isUncertainVoice = chatVM.hasPendingVoiceNote && !chatVM.canRetryPendingVoiceNote && !hasContent
        let symbol =
            if isFinalizingVoice {
                "clock.circle"
            } else if isRetryingVoice {
                "arrow.clockwise.circle.fill"
            } else if isUncertainVoice {
                "exclamationmark.circle.fill"
            } else {
                chatVM.recordingVoiceNote || hasContent ? "arrow.up.circle.fill" : "mic.fill"
            }
        actionButton.setImage(UIImage(systemName: symbol), for: .normal)
        actionButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(
                pointSize: chatVM.recordingVoiceNote || hasContent ? 28 : 20,
                weight: chatVM.recordingVoiceNote || hasContent ? .regular : .medium,
            ),
            forImageIn: .normal,
        )
        actionButton.isEnabled = !isFinalizingVoice
        actionButton.alpha = isFinalizingVoice ? 0.55 : 1
        let canBeginVoiceGesture = !chatVM.startingVoiceNote
            && !chatVM.loadingVoiceDraft
            && !chatVM.finalizingVoiceNote
            && !chatVM.hasPendingVoiceNote
            && !hasContent
        recordingGestureRecognizer.isEnabled = voiceGestureIsTracking || canBeginVoiceGesture
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
        } else {
            actionButton.menu = nil
            actionButton.accessibilityHint = UIAccessibility.isVoiceOverRunning && !hasContent
                ? "Double-tap to start a locked voice recording."
                : nil
        }
        actionButton.accessibilityLabel =
            if isFinalizingVoice {
                "Preparing voice message"
            } else if isRetryingVoice {
                "Retry voice message"
            } else if isUncertainVoice {
                "Voice message send status unknown"
            } else {
                chatVM.recordingVoiceNote || hasContent ? "Send" : "Record voice message"
            }
    }

    private func updateRecordingStatus() {
        recordingLabel.textColor = .systemRed
        switch chatVM.voiceRecordingInteractionState {
        case .locked:
            recordingLabel.text = "● \(chatVM.formattedTimerCount)  Locked"
            recordingLabel.accessibilityLabel = "Voice recording locked, \(chatVM.formattedTimerCount)"
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
        case .idle:
            recordingLabel.text = nil
            recordingLabel.accessibilityLabel = nil
            recordingSendButton.isHidden = true
        }
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
        guard hasContent else {
            if UIAccessibility.isVoiceOverRunning {
                Task { [weak chatVM] in
                    guard let chatVM else { return }
                    if await chatVM.mediaStartRecordingVoice() {
                        chatVM.lockVoiceRecording()
                    }
                }
            }
            return
        }
        chatVM.sendMessageTask?.cancel()
        chatVM.sendMessageTask = Task { [weak chatVM] in await chatVM?.sendMessage() }
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
            setVoiceGestureDeferral(true)
            voiceGestureGeneration &+= 1
            let generation = voiceGestureGeneration
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures") {
                    log("Voice gesture smoke: began")
                }
            #endif
            voiceGestureArmTask?.cancel()
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
                let started = await chatVM.mediaStartRecordingVoice()
                guard voiceGestureGeneration == generation else {
                    if started {
                        chatVM.cancelVoiceRecording()
                    }
                    return
                }
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures") {
                        log("Voice gesture smoke: recording=\(started)")
                    }
                    if started, ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-lock") {
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
        if chatVM.startingVoiceNote || !chatVM.recordingVoiceNote {
            pendingVoiceGestureOutcome = outcome
            return
        }
        applyVoiceGestureOutcome(outcome)
    }

    private func applyVoiceGestureOutcome(_ outcome: VoiceGestureOutcome) {
        voiceGestureAwaitingPrearmLock = false
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures") {
                let name = switch outcome {
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
            chatVM.cancelVoiceRecording()
        case .lock:
            setVoiceGestureDeferral(false)
            chatVM.lockVoiceRecording()
            updateRecordingStatus()
        case .send:
            guard chatVM.voiceRecordingInteractionState == .holding else { return }
            setVoiceGestureDeferral(false)
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-smoke-voice-gestures") {
                    chatVM.cancelVoiceRecording()
                    return
                }
            #endif
            chatVM.mediaStopRecordingVoice()
        }
        voiceGestureIsArmed = false
    }

    private func resetVoiceGestureButtonSuppressionAfterCurrentEvent() {
        let generation = voiceGestureGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, voiceGestureGeneration == generation else { return }
            voiceGestureSuppressesButtonAction = false
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
        chatVM.cancelVoiceRecording()
    }
}
