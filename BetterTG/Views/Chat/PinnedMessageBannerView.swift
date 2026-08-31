// PinnedMessageBannerView.swift

import TDLibKitDynamic
import UIKit

// MARK: - PinnedMessageBannerView

final class PinnedMessageBannerView: UIView {
    static let contentHeight = CGFloat(50)

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let accentView = UIView()
    private let thumbnailView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let textStack = UIStackView()
    private let openControl = UIControl()
    private let actionButton = UIButton(type: .system)
    private var thumbnailWidthConstraint: NSLayoutConstraint!
    private var textLeadingConstraint: NSLayoutConstraint!
    private var onOpen: (() -> Void)?
    private var onHide: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        accentView.translatesAutoresizingMaskIntoConstraints = false
        accentView.backgroundColor = .systemBlue
        accentView.layer.cornerRadius = 1
        addSubview(accentView)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        addSubview(thumbnailView)

        titleLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold),
            maximumPointSize: 15,
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isAccessibilityElement = false
        titleLabel.textColor = .systemBlue
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        bodyLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .regular),
            maximumPointSize: 15,
        )
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.isAccessibilityElement = false
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = 1
        bodyLabel.lineBreakMode = .byTruncatingTail

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 0
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.isUserInteractionEnabled = false
        addSubview(textStack)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.accessibilityIdentifier = "pinned-message-hide"
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        addSubview(actionButton)

        openControl.translatesAutoresizingMaskIntoConstraints = false
        openControl.accessibilityIdentifier = "pinned-message-open"
        openControl.addTarget(self, action: #selector(openPressed), for: .touchUpInside)
        addSubview(openControl)

        self.thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 0)
        self.textLeadingConstraint = textStack.leadingAnchor.constraint(
            equalTo: thumbnailView.trailingAnchor,
            constant: 0,
        )
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
            accentView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 10),
            accentView.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            accentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            accentView.widthAnchor.constraint(equalToConstant: 2),
            thumbnailView.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 6),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 35),
            thumbnailWidthConstraint,
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            textLeadingConstraint,
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -6),
            actionButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -2),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 44),
            openControl.topAnchor.constraint(equalTo: topAnchor),
            openControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            openControl.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            openControl.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func previewText(for message: Message) -> String {
        let presentation = MessageContentPresentation.make(message)
        guard let formattedText = presentation.formattedText else {
            return ChatSummary.summary(for: message)
        }
        let spoilerRanges = formattedText.entities.compactMap { entity -> NSRange? in
            guard case .textEntityTypeSpoiler = entity.type else { return nil }
            return NSRange(location: entity.offset, length: entity.length)
        }
        guard !spoilerRanges.isEmpty else {
            return ChatSummary.summary(for: message)
        }
        let redacted = NSMutableString(string: formattedText.text)
        for range in spoilerRanges.sorted(by: { $0.location > $1.location })
            where NSMaxRange(range) <= redacted.length
        {
            redacted.replaceCharacters(in: range, with: "•••")
        }
        return redacted.length == 0 ? "Spoiler" : String(redacted)
    }

    func configure(
        message: Message,
        onOpen: @escaping () -> Void,
        onHide: @escaping () -> Void,
    ) {
        prepareForReuse()
        titleLabel.text = "Pinned Message"
        bodyLabel.text = Self.previewText(for: message)
        if let thumbnail = MessageReplyThumbnail.make(for: message.content) {
            thumbnailWidthConstraint.constant = 35
            textLeadingConstraint.constant = 6
            thumbnailView.isHidden = false
            thumbnailView.layer.cornerRadius = thumbnail.isRound ? 17.5 : 2
            thumbnailView.load(
                file: thumbnail.file,
                placeholderData: thumbnail.minithumbnailData,
                maximumPixelSize: 160,
            )
        } else {
            thumbnailWidthConstraint.constant = 0
            textLeadingConstraint.constant = 0
            thumbnailView.isHidden = true
        }
        actionButton.setImage(
            UIImage(systemName: "xmark"),
            for: .normal,
        )
        actionButton.accessibilityLabel = "Hide Pinned Message"
        self.onOpen = onOpen
        self.onHide = onHide
        openControl.isAccessibilityElement = true
        openControl.accessibilityLabel = "Pinned message, \(bodyLabel.text ?? "")"
        openControl.accessibilityHint = "Opens the pinned message"
        openControl.accessibilityTraits = [.button]
    }

    func prepareForReuse() {
        thumbnailView.cancel()
        thumbnailView.image = nil
        thumbnailView.isHidden = true
        thumbnailWidthConstraint.constant = 0
        textLeadingConstraint.constant = 0
        titleLabel.text = nil
        bodyLabel.text = nil
        onOpen = nil
        onHide = nil
        openControl.accessibilityLabel = nil
        openControl.accessibilityHint = nil
        actionButton.accessibilityLabel = nil
    }

    #if DEBUG
        func simulateOpenForProbe() {
            openPressed()
        }

        func simulateActionForProbe() {
            actionPressed()
        }
    #endif

    @objc private func openPressed() {
        onOpen?()
    }

    @objc private func actionPressed() {
        onHide?()
    }
}
