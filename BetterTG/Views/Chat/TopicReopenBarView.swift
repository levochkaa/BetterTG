// TopicReopenBarView.swift

import UIKit

// MARK: - TopicReopenBarView

/// Telegram's Restart Topic title panel (ChatReportPeerTitlePanelNode, `.restartTopic`): one centred accent button
/// under the navigation bar of a closed topic, without a close button.
final class TopicReopenBarView: UIView {
    static let contentHeight = CGFloat(40)

    var onReopen: (() -> Void)?

    /// A sent request disables the button until TDLib reports the topic open or the request fails.
    var isBusy = false {
        didSet { button.isEnabled = !isBusy }
    }

    private let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(L10n.telegram("Chat.PanelRestartTopic"), for: .normal)
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16),
            maximumPointSize: 20,
        )
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "topic-restart"
        button.addAction(UIAction { [weak self] _ in self?.onReopen?() }, for: .touchUpInside)
        addSubview(button)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            // Unbound below, so the button keeps its height while the clipped bar collapses.
            button.heightAnchor.constraint(equalToConstant: Self.contentHeight),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
