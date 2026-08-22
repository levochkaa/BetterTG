// ChatBottomArea.swift

import TDLibKit
import UIKit

final class ChatComposerView: UIView {
    init(chatVM: ChatVM) {
        self.chatVM = chatVM
        super.init(frame: .zero)
        configureViews()
        configureActions()
        update(from: chatVM)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var onPickPhotos: (() -> Void)?
    var onTakePhoto: (() -> Void)?
    var onScrollToMessage: ((Int64) -> Void)?

    var isInputFocused: Bool {
        textView.isFirstResponder
    }

    func focusInput() {
        textView.becomeFirstResponder()
    }

    private let chatVM: ChatVM
    private let blurView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        effect.tintColor = UIColor(white: 0, alpha: 0.18)
        return UIVisualEffectView(effect: effect)
    }()
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
    private var displayedImageIDs = [UUID]()
    private var draftTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var isApplyingState = false
    private var lastReplyID: Int64?
    private var lastEditID: Int64?

    private func configureViews() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
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
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
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
        attachmentButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        attachmentButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 26), forImageIn: .normal)
        attachmentButton.showsMenuAsPrimaryAction = true
        attachmentButton.accessibilityLabel = "Attach"
        textView.backgroundColor = .tertiarySystemBackground
        textView.layer.cornerRadius = 15
        textView.layer.cornerCurve = .continuous
        actionButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 28), forImageIn: .normal)
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
        cancelRecordingButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelRecordingButton.accessibilityLabel = "Cancel voice recording"
        recordingLabel.textColor = .white
        recordingLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        recordingLabel.textAlignment = .center
        recordingSendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        recordingSendButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 28),
            forImageIn: .normal,
        )
        recordingSendButton.accessibilityLabel = "Send voice message"
        recordingRow.addArrangedSubview(cancelRecordingButton)
        recordingRow.addArrangedSubview(recordingLabel)
        recordingRow.addArrangedSubview(recordingSendButton)
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
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        recordingSendButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        actionButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(actionLongPressed(_:))))

        textView.onTextChange = { [weak self] text in self?.textChanged(text) }
        textView.onPasteImages = { [weak self] images in
            guard let self else { return }
            self.chatVM.displayedImages = Array(images.prefix(10))
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
            replySnippet.configure(title: "Edit message", message: edited.message) { [weak self] in
                self?.onScrollToMessage?(edited.id)
            }
        } else if let reply = chatVM.replyMessage {
            replyRow.isHidden = false
            replySnippet.configure(title: reply.senderUser?.firstName ?? "Reply", message: reply.message) { [weak self] in
                self?.onScrollToMessage?(reply.id)
            }
        } else {
            replyRow.isHidden = true
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
            if chatVM.timer == nil {
                chatVM.startTimer()
            }
            recordingLabel.text = "● \(chatVM.formattedTimerCount)"
            recordingLabel.textColor = .systemRed
        } else if chatVM.timer != nil {
            chatVM.stopTimer()
        }
        updateActionButton()
        isApplyingState = false
        if shouldFocus, lastReplyID != nil || lastEditID != nil {
            textView.becomeFirstResponder()
        }
    }

    private func rebuildPhotos() {
        photosStack.arrangedSubviews.forEach {
            photosStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
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
        let symbol = chatVM.recordingVoiceNote || hasContent ? "arrow.up.circle.fill" : "mic.fill"
        actionButton.setImage(UIImage(systemName: symbol), for: .normal)
        actionButton.accessibilityLabel = chatVM.recordingVoiceNote || hasContent ? "Send" : "Record voice message"
    }

    @objc private func cancelReplyOrEdit() {
        chatVM.replyMessage = nil
        chatVM.editCustomMessage = nil
        chatVM.editMessageText = ""
    }

    @objc private func actionTapped() {
        if chatVM.recordingVoiceNote {
            chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave)
            return
        }
        let hasContent = !chatVM.displayedImages.isEmpty
            || !chatVM.text.characters.isEmpty
            || !chatVM.editMessageText.characters.isEmpty
            || chatVM.editCustomMessage != nil
        guard hasContent else { return }
        chatVM.sendMessageTask?.cancel()
        chatVM.sendMessageTask = Task { [weak chatVM] in await chatVM?.sendMessage() }
    }

    @objc private func actionLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              chatVM.displayedImages.isEmpty,
              chatVM.text.characters.isEmpty,
              chatVM.editCustomMessage == nil
        else { return }
        Task { [weak chatVM] in await chatVM?.mediaStartRecordingVoice() }
    }

    @objc private func cancelRecording() {
        chatVM.cancelVoiceRecording()
    }
}
