// SessionReviewNoticeView.swift

import UIKit

// MARK: - SessionReviewNoticeView

/// ChatListNoticeItem's reviewLogin in the chat list's header panels: "Someone just got access to your messages!"
/// (with "1/N" before it while several logins wait), the device and place, and Yes, it's me / No, it's not me! under
/// them, all centred.
final class SessionReviewNoticeView: UIView {
    private static let verticalInset: CGFloat = 9
    private static let spacing: CGFloat = 2
    private static let buttonHeight: CGFloat = 32

    var onConfirm: (() -> Void)?
    var onReject: (() -> Void)?

    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let confirmButton = UIButton(type: .system)
    private let rejectButton = UIButton(type: .system)

    /// ChatListNoticeItem's 16 pt sides, the right one wider by the close button's room.
    private var textInsets: UIEdgeInsets {
        UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16 + 24)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
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
        for subview in [titleLabel, textLabel, confirmButton, rejectButton] {
            addSubview(subview)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let insets = textInsets
        let available = max(1, width - insets.left - insets.right)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        titleLabel.frame = CGRect(
            x: floor((width - min(titleSize.width, available)) / 2), y: Self.verticalInset + 1,
            width: min(titleSize.width, available), height: titleSize.height,
        )
        let textSize = textLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        textLabel.frame = CGRect(
            x: floor((width - min(textSize.width, available)) / 2), y: titleLabel.frame.maxY + Self.spacing,
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
    }

    func configure(_ review: UnconfirmedSessionStore.Review) {
        let title = L10n.telegram("ChatList.SessionReview.PanelTitle")
        titleLabel.text = review.count > 1 ? "1/\(review.count) \(title)" : title
        textLabel.text = L10n.telegram("ChatList.SessionReview.PanelText", review.device, review.location)
        setNeedsLayout()
    }

    /// The panel's height at `width`: the insets, the title, the text and the buttons' row.
    func height(forWidth width: CGFloat) -> CGFloat {
        let insets = textInsets
        let available = max(1, width - insets.left - insets.right)
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)).height
        let textHeight = textLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)).height
        return Self.verticalInset * 2 + titleHeight + Self.spacing + textHeight + 6 + Self.buttonHeight
    }
}
