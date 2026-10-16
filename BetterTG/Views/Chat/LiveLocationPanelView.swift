// LiveLocationPanelView.swift

import UIKit

// MARK: - LiveLocationPanelView

/// Telegram's LocationBroadcastNavigationAccessoryPanel: the waves icon, "Live Location" over who sees it, and close,
/// under the navigation bar while the account shares its live location. Tapping it opens the shared location, and
/// close asks before stopping.
final class LiveLocationPanelView: UIView {
    static let contentHeight = CGFloat(37)

    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    private let iconView = UIImageView()
    private let openControl = UIControl()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        openControl.translatesAutoresizingMaskIntoConstraints = false
        openControl.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        openControl.isAccessibilityElement = true
        openControl.accessibilityTraits = .button
        addSubview(openControl)

        // LiveLocationWavesNode: waves pulse around the location while it is shared.
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(
            systemName: "dot.radiowaves.left.and.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold),
        )
        iconView.tintColor = .systemBlue
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        iconView.addSymbolEffect(.variableColor.iterative, options: .repeat(.continuous))
        openControl.addSubview(iconView)

        for (label, size) in [(titleLabel, CGFloat(12)), (subtitleLabel, CGFloat(10))] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
                for: .systemFont(ofSize: size, weight: .regular),
                maximumPointSize: size + 2,
            )
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.isUserInteractionEnabled = false
            openControl.addSubview(label)
        }
        titleLabel.textColor = .label
        titleLabel.text = L10n.telegram("Conversation.LiveLocation")
        subtitleLabel.textColor = .secondaryLabel

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = .secondaryLabel
        closeButton.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            ),
            for: .normal,
        )
        closeButton.accessibilityLabel = L10n.telegram("Map.StopLiveLocation")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
            closeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: topAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            openControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            openControl.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor),
            openControl.topAnchor.constraint(equalTo: topAnchor),
            openControl.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            iconView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: openControl.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            // Telegram centers the text in the panel, 40 pt clear of either edge.
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -88),
            titleLabel.bottomAnchor.constraint(equalTo: openControl.centerYAnchor, constant: 1),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -88),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
        ])
        accessibilityElements = [openControl, closeButton]
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// LiveLocationHeaderPanelComponent's close for one chat: Stop Sharing Location under Cancel.
    @MainActor static func stopSheet(sourceView: UIView, stop: @escaping () -> Void) -> UIAlertController {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.telegram("Map.StopLiveLocation"), style: .destructive) { _ in
            stop()
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        return sheet
    }

    /// The subtitle names who sees the location: "You" in its chat in the accent color, the chat or chat count in
    /// the chat list.
    func configure(subtitle: String, isAccent: Bool) {
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = isAccent ? .systemBlue : .secondaryLabel
        openControl.accessibilityLabel = "\(L10n.telegram("Conversation.LiveLocation")). \(subtitle)"
    }

    @objc private func openTapped() {
        onOpen?()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
