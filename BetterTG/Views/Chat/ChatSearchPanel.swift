// ChatSearchPanel.swift

import UIKit

// MARK: - ChatSearchPanel

/// Telegram's in-chat search bottom panel (ChatTagSearchInputPanelNode with the search navigate buttons): it takes
/// the composer's place while the chat is searched, with the calendar and member buttons, the result position and
/// the arrows that step to older and newer results.
final class ChatSearchPanel: UIView {
    enum Status: Equatable {
        case idle
        case loading
        case noResults
        /// `position` counts from the newest result, as Telegram's "N of M".
        case results(position: Int, total: Int, canGoOlder: Bool, canGoNewer: Bool)
    }

    static let contentHeight: CGFloat = 44

    var onCalendar: (() -> Void)?
    var onMembers: (() -> Void)?
    var onOlder: (() -> Void)?
    var onNewer: (() -> Void)?

    private let contentGuide = UILayoutGuide()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let calendarButton = UIButton(type: .system)
    private let membersButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let olderButton = UIButton(type: .system)
    private let newerButton = UIButton(type: .system)
    private var membersHiddenConstraint: NSLayoutConstraint!

    /// The bottom of the panel's controls; the chat pins it above the keyboard.
    var contentBottomAnchor: NSLayoutYAxisAnchor { contentGuide.bottomAnchor }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        update(status: .idle, showsMembers: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(status: Status, showsMembers: Bool) {
        membersButton.isHidden = !showsMembers
        membersHiddenConstraint.isActive = !showsMembers
        switch status {
        case .idle:
            statusLabel.text = nil
            activityIndicator.stopAnimating()
            setArrows(older: false, newer: false)
        case .loading:
            statusLabel.text = nil
            activityIndicator.startAnimating()
            setArrows(older: false, newer: false)
        case .noResults:
            statusLabel.text = L10n.telegram("Conversation.SearchNoResults")
            activityIndicator.stopAnimating()
            setArrows(older: false, newer: false)
        case .results(let position, let total, let canGoOlder, let canGoNewer):
            statusLabel.text = L10n.telegram("Items.NOfM", String(position), String(total))
            activityIndicator.stopAnimating()
            setArrows(older: canGoOlder, newer: canGoNewer)
        }
    }

    private func setArrows(older: Bool, newer: Bool) {
        olderButton.isEnabled = older
        newerButton.isEnabled = newer
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        addLayoutGuide(contentGuide)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        configure(calendarButton, symbol: "calendar", label: L10n.telegram("Chat.JumpToDate"))
        calendarButton.addTarget(self, action: #selector(calendarPressed), for: .touchUpInside)
        configure(membersButton, symbol: "person.2", label: L10n.telegram("Conversation.SearchByName.Placeholder"))
        membersButton.addTarget(self, action: #selector(membersPressed), for: .touchUpInside)
        configure(olderButton, symbol: "chevron.up", label: L10n.betterTG("Accessibility.SearchOlderResult"))
        olderButton.addTarget(self, action: #selector(olderPressed), for: .touchUpInside)
        configure(newerButton, symbol: "chevron.down", label: L10n.betterTG("Accessibility.SearchNewerResult"))
        newerButton.addTarget(self, action: #selector(newerPressed), for: .touchUpInside)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        addSubview(statusLabel)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)

        membersHiddenConstraint = membersButton.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),

            contentGuide.topAnchor.constraint(equalTo: topAnchor),
            contentGuide.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            contentGuide.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            contentGuide.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            calendarButton.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            membersButton.leadingAnchor.constraint(equalTo: calendarButton.trailingAnchor),
            newerButton.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            olderButton.trailingAnchor.constraint(equalTo: newerButton.leadingAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: membersButton.trailingAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: olderButton.leadingAnchor, constant: -4),
            activityIndicator.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
        ])
        for button in [calendarButton, membersButton, olderButton, newerButton] {
            NSLayoutConstraint.activate([
                button.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
                button.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            ])
            let width = button.widthAnchor.constraint(equalToConstant: Self.contentHeight)
            width.priority = .defaultHigh
            width.isActive = true
        }
    }

    private func configure(_ button: UIButton, symbol: String, label: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
            ),
            for: .normal,
        )
        button.accessibilityLabel = label
        button.clipsToBounds = true
        addSubview(button)
    }

    @objc private func calendarPressed() {
        onCalendar?()
    }

    @objc private func membersPressed() {
        onMembers?()
    }

    @objc private func olderPressed() {
        onOlder?()
    }

    @objc private func newerPressed() {
        onNewer?()
    }
}
