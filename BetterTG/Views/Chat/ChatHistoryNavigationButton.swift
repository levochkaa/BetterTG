// ChatHistoryNavigationButton.swift

import UIKit

/// One of Telegram's history navigation buttons (ChatHistoryNavigationButtonNode) above the scroll-to-latest
/// button: a round button with a count badge that jumps to the next unread mention or reaction.
final class ChatHistoryNavigationButton: UIButton {
    // MARK: Internal

    static let hiddenTransform = CGAffineTransform(scaleX: 0.2, y: 0.2)
    /// ChatHistoryNavigationButtonNode's 40 pt circle.
    static let side: CGFloat = 40

    private(set) var count = 0

    // MARK: Private

    private let badgeLabel = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 11)

    init(symbolName: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        tintColor = .label
        self.accessibilityLabel = accessibilityLabel
        applyTelegramFloatingGlass(icon: UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium),
        ))
        alpha = 0
        transform = Self.hiddenTransform
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.backgroundColor = .systemBlue
        badgeLabel.textColor = .white
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
            badgeLabel.topAnchor.constraint(equalTo: topAnchor, constant: -7),
            badgeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCount(_ count: Int) {
        guard self.count != count || badgeLabel.text == nil && count > 0 else { return }
        self.count = count
        badgeLabel.text = count > 0 ? compactNumericCountString(count) : nil
        badgeLabel.isHidden = count == 0
        accessibilityValue = count > 0 ? compactNumericCountString(count) : nil
    }
}
