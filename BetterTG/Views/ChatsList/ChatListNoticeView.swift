// ChatListNoticeView.swift

import UIKit

// MARK: - ChatListNotice

/// The chat list notices of Telegram's ChatListNotice that BetterTG shows, in GlobalControlPanelsContext's order: a
/// login to review, a password to set up, a photo, a birthday, then a server's own suggestion.
enum ChatListNotice: Equatable {
    case reviewLogin(UnconfirmedSessionStore.Review)
    case setupPassword
    case setupPhoto
    case setupBirthday
    case link(name: String, title: String, text: String, url: String)

    /// ChatListNoticeItem's close button; the others show an arrow, and a login to review its two answers.
    var hasCloseButton: Bool {
        switch self {
        case .link,
             .setupBirthday,
             .setupPhoto: true
        case .reviewLogin,
             .setupPassword: false
        }
    }
}

// MARK: - ChatListNoticeView

/// ChatListNoticeItem in the chat list's header panels. A login to review: "Someone just got access to your
/// messages!" (with "1/N" before it while several logins wait), the device and place, and Yes, it's me / No, it's not
/// me! under them, all centred. Any other notice: its title and text from the left (after the camera avatar for a
/// photo), with an arrow or a close button on the right; a tap on it opens what it suggests.
final class ChatListNoticeView: UIView {
    private static let sideInset: CGFloat = 16
    private static let verticalInset: CGFloat = 9
    private static let buttonHeight: CGFloat = 32
    private static let avatarSide: CGFloat = 40

    var onConfirm: (() -> Void)?
    var onReject: (() -> Void)?
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?

    private(set) var notice: ChatListNotice?

    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let confirmButton = UIButton(type: .system)
    private let rejectButton = UIButton(type: .system)
    private let arrowView = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let closeButton = UIButton(type: .system)
    private let avatarView = UIImageView()

    private var isReview: Bool {
        if case .reviewLogin = notice {
            true
        } else {
            false
        }
    }

    private var leftInset: CGFloat {
        notice == .setupPhoto ? Self.sideInset + Self.avatarSide + 6 : Self.sideInset
    }

    /// ChatListNoticeItem's right side, wider by the arrow's or close button's room.
    private var rightInset: CGFloat {
        Self.sideInset + 24
    }

    private var spacing: CGFloat {
        isReview ? 2 : 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 10
        for (button, title, color) in [
            (confirmButton, "ChatList.SessionReview.PanelConfirm", UIColor.tintColor),
            (rejectButton, "ChatList.SessionReview.PanelReject", UIColor.systemRed),
        ] {
            button.setTitle(L10n.telegram(title), for: .normal)
            button.setTitleColor(color, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
        }
        confirmButton.addAction(UIAction { [weak self] _ in self?.onConfirm?() }, for: .touchUpInside)
        rejectButton.addAction(UIAction { [weak self] _ in self?.onReject?() }, for: .touchUpInside)
        arrowView.tintColor = .tertiaryLabel
        arrowView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)),
            for: .normal,
        )
        closeButton.tintColor = .tertiaryLabel
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        // AvatarNode's cameraIcon over the account's missing photo.
        avatarView.image = UIImage(
            systemName: "camera.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium),
        )
        avatarView.tintColor = .white
        avatarView.backgroundColor = .tintColor
        avatarView.contentMode = .center
        avatarView.layer.cornerRadius = Self.avatarSide / 2
        avatarView.clipsToBounds = true
        for subview in [avatarView, titleLabel, textLabel, confirmButton, rejectButton, arrowView, closeButton] {
            addSubview(subview)
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let available = max(1, width - leftInset - rightInset)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        let textSize = textLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        if isReview {
            titleLabel.frame = CGRect(
                x: floor((width - min(titleSize.width, available)) / 2), y: Self.verticalInset + 1,
                width: min(titleSize.width, available), height: titleSize.height,
            )
            textLabel.frame = CGRect(
                x: floor((width - min(textSize.width, available)) / 2), y: titleLabel.frame.maxY + spacing,
                width: min(textSize.width, available), height: textSize.height,
            )
            // Two halves of a row up to 300 pt wide, or as wide as both titles need.
            let titlesWidth = confirmButton.intrinsicContentSize.width + rejectButton.intrinsicContentSize.width + 32
            let buttonsWidth = min(width, max(min(300, width), titlesWidth))
            let buttonWidth = floor(buttonsWidth / 2)
            let buttonY = textLabel.frame.maxY + 6
            confirmButton.frame = CGRect(
                x: floor((width - buttonsWidth) / 2), y: buttonY, width: buttonWidth, height: Self.buttonHeight,
            )
            rejectButton.frame = CGRect(
                x: confirmButton.frame.maxX, y: buttonY, width: buttonWidth, height: Self.buttonHeight,
            )
        } else {
            titleLabel.frame = CGRect(
                x: leftInset, y: Self.verticalInset + 1, width: available, height: titleSize.height,
            )
            textLabel.frame = CGRect(
                x: leftInset, y: titleLabel.frame.maxY + spacing, width: available, height: textSize.height,
            )
        }
        avatarView.frame = CGRect(
            x: Self.sideInset - 6, y: floor((bounds.height - Self.avatarSide) / 2),
            width: Self.avatarSide, height: Self.avatarSide,
        )
        let arrowSize = arrowView.intrinsicContentSize
        arrowView.frame = CGRect(
            x: width - Self.sideInset - arrowSize.width + 4, y: floor((bounds.height - arrowSize.height) / 2),
            width: arrowSize.width, height: arrowSize.height,
        )
        closeButton.frame = CGRect(
            x: width - Self.sideInset - 28, y: floor((bounds.height - 32) / 2), width: 32, height: 32,
        )
    }

    func configure(_ notice: ChatListNotice) {
        self.notice = notice
        var textFont = UIFont.systemFont(ofSize: 15)
        switch notice {
        case .reviewLogin(let review):
            let title = L10n.telegram("ChatList.SessionReview.PanelTitle")
            titleLabel.text = review.count > 1 ? "1/\(review.count) \(title)" : title
            textLabel.text = L10n.telegram("ChatList.SessionReview.PanelText", review.device, review.location)
        case .setupPassword:
            titleLabel.text = L10n.telegram("Settings.SuggestSetupPasswordTitle")
            textLabel.text = L10n.telegram("Settings.SuggestSetupPasswordText")
        case .setupPhoto:
            titleLabel.text = L10n.telegram("ChatList.AddPhoto.Title")
            textLabel.text = L10n.telegram("ChatList.AddPhoto.Text")
            textFont = .systemFont(ofSize: 14)
        case .setupBirthday:
            titleLabel.text = L10n.telegram("ChatList.AddBirthdayTitle")
            textLabel.text = L10n.telegram("ChatList.AddBirthdayText")
        case .link(_, let title, let text, _):
            titleLabel.text = title
            textLabel.text = text
        }
        textLabel.font = textFont
        let alignment: NSTextAlignment = isReview ? .center : .natural
        titleLabel.textAlignment = alignment
        textLabel.textAlignment = alignment
        confirmButton.isHidden = !isReview
        rejectButton.isHidden = !isReview
        closeButton.isHidden = !notice.hasCloseButton
        arrowView.isHidden = isReview || notice.hasCloseButton
        avatarView.isHidden = notice != .setupPhoto
        accessibilityTraits = isReview ? [] : .button
        setNeedsLayout()
    }

    /// The panel's height at `width`: the insets, the title, the text, and a login's answers.
    func height(forWidth width: CGFloat) -> CGFloat {
        let available = max(1, width - leftInset - rightInset)
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)).height
        let textHeight = textLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)).height
        var height = Self.verticalInset * 2 + titleHeight + spacing + textHeight
        if isReview { height += 6 + Self.buttonHeight }
        return height
    }

    @objc private func tapped() {
        guard notice != nil, !isReview else { return }
        onActivate?()
    }
}
