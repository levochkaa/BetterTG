// ChatSearchPanel.swift

import UIKit

// MARK: - ChatSearchPanel

/// Telegram's in-chat search bottom panel (ChatTagSearchInputPanelNode with the search navigate buttons): it takes
/// the composer's place while the chat is searched, with the calendar and member buttons, the result position and
/// the arrows that step to older and newer results. Its Show as List / Show as Chat button switches the results between
/// the chat and a list; the list shows the result count instead of the position and has no arrows.
final class ChatSearchPanel: UIView {
    enum Status: Equatable {
        case idle
        case loading
        case noResults
        /// `position` counts from the newest result, as Telegram's "N of M".
        case results(position: Int, total: Int, canGoOlder: Bool, canGoNewer: Bool)

        /// Telegram's canChangeListMode: the list mode switch shows with a current result.
        var hasResults: Bool {
            if case .results = self {
                true
            } else {
                false
            }
        }
    }

    static let contentHeight: CGFloat = 44

    var onCalendar: (() -> Void)?
    var onMembers: (() -> Void)?
    var onOlder: (() -> Void)?
    var onNewer: (() -> Void)?
    var onDisplayMode: (() -> Void)?

    private let contentGuide = UILayoutGuide()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let calendarButton = UIButton(type: .system)
    private let membersButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let trailingStack = UIStackView()
    private let displayModeButton = UIButton(type: .system)
    private let olderButton = UIButton(type: .system)
    private let newerButton = UIButton(type: .system)
    private var membersHiddenConstraint: NSLayoutConstraint!

    /// The bottom of the panel's controls; the chat pins it above the keyboard.
    var contentBottomAnchor: NSLayoutYAxisAnchor { contentGuide.bottomAnchor }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        update(status: .idle, showsMembers: false, showsDisplayMode: false, isListMode: false, resultCount: 0)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `resultCount` is the list mode's "N messages".
    func update(status: Status, showsMembers: Bool, showsDisplayMode: Bool, isListMode: Bool, resultCount: Int) {
        membersButton.isHidden = !showsMembers
        membersHiddenConstraint.isActive = !showsMembers
        // ChatTagSearchInputPanelNode: "Show as %@" with Chat or List.
        displayModeButton.isHidden = !showsDisplayMode
        let modeKey = isListMode ? "Chat.BottomSearchPanel.DisplayModeChat" : "Chat.BottomSearchPanel.DisplayModeList"
        displayModeButton.configuration?.title = L10n.telegram(
            "Chat.BottomSearchPanel.DisplayModeFormat",
            L10n.telegram(modeKey),
        )
        olderButton.isHidden = isListMode
        newerButton.isHidden = isListMode
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
            statusLabel.text = isListMode
                ? L10n.telegram(
                    "Chat.BottomSearchPanel.MessageCountFormat",
                    resultCount.formatted(.number),
                    L10n.telegramPlural("Chat.BottomSearchPanel.MessageCount", count: resultCount),
                )
                : L10n.telegram("Items.NOfM", String(position), String(total))
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
        var displayModeConfiguration = UIButton.Configuration.plain()
        displayModeConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)
        displayModeConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return attributes
        }
        displayModeButton.configuration = displayModeConfiguration
        displayModeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        displayModeButton.addTarget(self, action: #selector(displayModePressed), for: .touchUpInside)
        displayModeButton.isHidden = true

        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        for button in [displayModeButton, olderButton, newerButton] {
            button.removeFromSuperview()
            trailingStack.addArrangedSubview(button)
        }
        addSubview(trailingStack)

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
        // The position stays centred unless Show as List and the arrows need its room; then it moves left.
        let statusCenter = statusLabel.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor)
        statusCenter.priority = .defaultHigh
        statusLabel.setContentCompressionResistancePriority(
            UILayoutPriority(UILayoutPriority.defaultHigh.rawValue + 1),
            for: .horizontal,
        )
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
            trailingStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            trailingStack.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            trailingStack.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            statusCenter,
            statusLabel.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: membersButton.trailingAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -4),
            activityIndicator.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
        ])
        for button in [calendarButton, membersButton] {
            NSLayoutConstraint.activate([
                button.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
                button.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            ])
            let width = button.widthAnchor.constraint(equalToConstant: Self.contentHeight)
            width.priority = .defaultHigh
            width.isActive = true
        }
        for button in [olderButton, newerButton] {
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: Self.contentHeight),
                button.widthAnchor.constraint(equalToConstant: Self.contentHeight),
            ])
        }
        displayModeButton.heightAnchor.constraint(equalToConstant: Self.contentHeight).isActive = true
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

    @objc private func displayModePressed() {
        onDisplayMode?()
    }
}
