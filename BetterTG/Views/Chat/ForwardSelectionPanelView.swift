// ForwardSelectionPanelView.swift

import UIKit

// MARK: - ForwardSelectionPanelView

/// PeerSelectionControllerNode's panel while choosing several chats: ForwardAccessoryPanelNode's preview of what is
/// forwarded over AttachmentTextInputPanelNode's comment field and send button, which needs a chosen chat.
final class ForwardSelectionPanelView: UIView, UITextFieldDelegate {
    var onSend: (() -> Void)?

    private let blurView = TelegramBarBackgroundView(edge: .bottom)
    private let accentBar = UIView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let textField = UITextField()
    private let fieldBackground = UIView()
    private let sendButton = UIButton(type: .system)

    var comment: String { textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    override init(frame: CGRect) {
        super.init(frame: frame)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.backgroundColor = .systemBlue
        accentBar.layer.cornerRadius = 1
        addSubview(accentBar)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .systemBlue
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .label
        textLabel.lineBreakMode = .byTruncatingTail
        let labels = UIStackView(arrangedSubviews: [titleLabel, textLabel])
        labels.axis = .vertical
        labels.spacing = 1
        labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)

        fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.backgroundColor = .tertiarySystemFill
        fieldBackground.layer.cornerRadius = 18
        fieldBackground.layer.cornerCurve = .continuous
        addSubview(fieldBackground)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = L10n.telegram("ShareMenu.Comment")
        textField.font = .systemFont(ofSize: 17)
        textField.returnKeyType = .send
        textField.delegate = self
        fieldBackground.addSubview(textField)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(
            systemName: "arrow.up.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular),
        ), for: .normal)
        sendButton.accessibilityLabel = L10n.telegram("ShareMenu.Send")
        sendButton.addAction(UIAction { [weak self] _ in self?.onSend?() }, for: .touchUpInside)
        addSubview(sendButton)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            accentBar.topAnchor.constraint(equalTo: labels.topAnchor, constant: 1),
            accentBar.bottomAnchor.constraint(equalTo: labels.bottomAnchor, constant: -1),
            accentBar.widthAnchor.constraint(equalToConstant: 2),
            labels.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            labels.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 8),
            labels.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            fieldBackground.topAnchor.constraint(equalTo: labels.bottomAnchor, constant: 8),
            fieldBackground.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            fieldBackground.heightAnchor.constraint(equalToConstant: 36),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textField.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -14),
            textField.centerYAnchor.constraint(equalTo: fieldBackground.centerYAnchor),
            sendButton.leadingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: 6),
            sendButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: fieldBackground.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        setSendEnabled(false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, text: String) {
        titleLabel.text = title
        textLabel.text = text
    }

    /// updateSendButtonEnabled: the button sends once a chat is chosen.
    func setSendEnabled(_ enabled: Bool) {
        sendButton.isEnabled = enabled
        sendButton.tintColor = enabled ? .systemBlue : .tertiaryLabel
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        if sendButton.isEnabled { onSend?() }
        return false
    }
}
