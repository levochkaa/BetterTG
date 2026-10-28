// ChatSearchPanel.swift

import UIKit

// MARK: - ChatSearchPanel

/// Telegram's in-chat search bottom panel (ChatTagSearchInputPanelNode) with the search navigate buttons: it takes
/// the composer's place while the chat is searched. On the bar's blur, a glass capsule on the left holds the calendar
/// and member buttons and the result position, and one on the right Show as List / Show as Chat, which switches the
/// results between the chat and a list; the list shows the result count instead of the position. The arrows that step
/// to older and newer results are ChatHistoryNavigationButtons' 40 pt glass circles, standing above the panel where
/// the scroll-to-latest button rests, and leave in list mode.
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

    static let contentHeight = capsuleHeight + capsuleInset * 2

    /// The capsules' height (ChatTagSearchInputPanelNode's 40 pt) and the gap above and below them.
    private static let capsuleHeight: CGFloat = 40
    private static let capsuleInset: CGFloat = 8
    /// The capsules' and arrows' distance from the screen's sides, where the scroll-to-latest button rests.
    private static let sideInset: CGFloat = 14
    /// The gap between the arrows, and between the lower one and the capsules (ChatHistoryNavigationButtons' 12 pt).
    private static let arrowSpacing: CGFloat = 12
    private static let hiddenTransform = CGAffineTransform(scaleX: 0.001, y: 0.001)

    var onCalendar: (() -> Void)?
    var onMembers: (() -> Void)?
    var onOlder: (() -> Void)?
    var onNewer: (() -> Void)?
    var onDisplayMode: (() -> Void)?

    private let contentGuide = UILayoutGuide()
    private let blurView = TelegramBarBackgroundView(edge: .bottom)
    private let leadingCapsule = ChatSearchPanel.makeCapsule()
    private let leadingStack = UIStackView()
    private let trailingCapsule = ChatSearchPanel.makeCapsule()
    private let calendarButton = UIButton(type: .system)
    private let membersButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let displayModeButton = UIButton(type: .system)
    private let olderButton = ChatSearchArrowButton(symbolName: "chevron.up")
    private let newerButton = ChatSearchArrowButton(symbolName: "chevron.down")
    private var isPanelVisible = false
    private var showsArrows = false

    /// The bottom of the panel's controls; the chat pins it above the keyboard.
    var contentBottomAnchor: NSLayoutYAxisAnchor { contentGuide.bottomAnchor }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        update(status: .idle, showsMembers: false, showsDisplayMode: false, isListMode: false, resultCount: 0)
        setVisible(false, animated: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The arrows stand above the panel's own bounds.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        return [olderButton, newerButton].contains { button in
            button.isUserInteractionEnabled && button.frame.contains(point)
        }
    }

    private static func makeCapsule() -> UIVisualEffectView {
        let capsule = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        capsule.cornerConfiguration = .capsule()
        capsule.translatesAutoresizingMaskIntoConstraints = false
        return capsule
    }

    /// `resultCount` is the list mode's "N messages".
    func update(status: Status, showsMembers: Bool, showsDisplayMode: Bool, isListMode: Bool, resultCount: Int) {
        membersButton.isHidden = !showsMembers
        // ChatTagSearchInputPanelNode: "Show as %@" with Chat or List.
        trailingCapsule.isHidden = !showsDisplayMode
        let modeKey = isListMode ? "Chat.BottomSearchPanel.DisplayModeChat" : "Chat.BottomSearchPanel.DisplayModeList"
        displayModeButton.configuration?.title = L10n.telegram(
            "Chat.BottomSearchPanel.DisplayModeFormat",
            L10n.telegram(modeKey),
        )
        switch status {
        case .idle:
            statusLabel.text = nil
            activityIndicator.stopAnimating()
            setArrows(nil)
        case .loading:
            statusLabel.text = nil
            activityIndicator.startAnimating()
            setArrows(nil)
        case .noResults:
            statusLabel.text = L10n.telegram("Conversation.SearchNoResults")
            activityIndicator.stopAnimating()
            setArrows(nil)
        case .results(let position, let total, let canGoOlder, let canGoNewer):
            statusLabel.text = isListMode
                ? L10n.telegram(
                    "Chat.BottomSearchPanel.MessageCountFormat",
                    resultCount.formatted(.number),
                    L10n.telegramPlural("Chat.BottomSearchPanel.MessageCount", count: resultCount),
                )
                : L10n.telegram("Items.NOfM", String(position), String(total))
            activityIndicator.stopAnimating()
            setArrows(isListMode ? nil : (older: canGoOlder, newer: canGoNewer))
        }
        statusLabel.isHidden = statusLabel.text == nil
        // The position ends 8 pt before the capsule's end; buttons alone fill it.
        let showsText = !statusLabel.isHidden || activityIndicator.isAnimating
        leadingStack.directionalLayoutMargins.trailing = showsText ? 8 : 0
    }

    /// Shows or hides the panel: its blur fades and its glass grows in or shrinks away, as a glass view's opacity must
    /// not animate.
    func setVisible(_ visible: Bool, animated: Bool) {
        isPanelVisible = visible
        if visible { isHidden = false }
        let changes = {
            self.blurView.alpha = visible ? 1 : 0
            for capsule in [self.leadingCapsule, self.trailingCapsule] {
                capsule.transform = visible ? .identity : Self.hiddenTransform
            }
            self.layoutArrows()
        }
        guard animated else {
            changes()
            if !visible { isHidden = true }
            return
        }
        UIView.animate(
            springDuration: 0.4,
            bounce: 0,
            initialSpringVelocity: 0,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        ) { _ in
            if !self.isPanelVisible { self.isHidden = true }
        }
    }

    /// ChatController's directionButtonState while searching: both arrows with a result, the one that has nowhere to
    /// go dimmed; none without one.
    private func setArrows(_ state: (older: Bool, newer: Bool)?) {
        olderButton.isEnabled = state?.older ?? false
        newerButton.isEnabled = state?.newer ?? false
        guard showsArrows != (state != nil) else { return }
        showsArrows = state != nil
        UIView.animate(
            springDuration: 0.4,
            bounce: 0,
            initialSpringVelocity: 0,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.layoutArrows()
        }
    }

    /// ChatHistoryNavigationButtons shrinks an arrow to 0.2 as it leaves.
    private func layoutArrows() {
        let shown = showsArrows && isPanelVisible
        for button in [olderButton, newerButton] {
            button.transform = shown ? .identity : CGAffineTransform(scaleX: 0.2, y: 0.2)
            button.alpha = shown ? 1 : 0
            button.isUserInteractionEnabled = shown
        }
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        addLayoutGuide(contentGuide)

        configure(calendarButton, symbol: "calendar", label: L10n.telegram("Chat.JumpToDate"))
        calendarButton.addTarget(self, action: #selector(calendarPressed), for: .touchUpInside)
        configure(membersButton, symbol: "person.2", label: L10n.telegram("Conversation.SearchByName.Placeholder"))
        membersButton.addTarget(self, action: #selector(membersPressed), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabel
        statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        activityIndicator.hidesWhenStopped = true

        // The calendar and member buttons are 40 pt squares; the position follows with its own end padding.
        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        leadingStack.axis = .horizontal
        leadingStack.alignment = .center
        leadingStack.spacing = 0
        leadingStack.isLayoutMarginsRelativeArrangement = true
        leadingStack.directionalLayoutMargins = .zero
        for view in [calendarButton, membersButton, activityIndicator, statusLabel] {
            leadingStack.addArrangedSubview(view)
        }
        leadingCapsule.contentView.addSubview(leadingStack)
        addSubview(leadingCapsule)

        var displayModeConfiguration = UIButton.Configuration.plain()
        displayModeConfiguration.baseForegroundColor = .label
        displayModeConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        displayModeConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFont.systemFont(ofSize: 15)
            return attributes
        }
        displayModeButton.configuration = displayModeConfiguration
        displayModeButton.translatesAutoresizingMaskIntoConstraints = false
        displayModeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        displayModeButton.addTarget(self, action: #selector(displayModePressed), for: .touchUpInside)
        trailingCapsule.contentView.addSubview(displayModeButton)
        trailingCapsule.isHidden = true
        addSubview(trailingCapsule)

        olderButton.accessibilityLabel = L10n.betterTG("Accessibility.SearchOlderResult")
        olderButton.addTarget(self, action: #selector(olderPressed), for: .touchUpInside)
        newerButton.accessibilityLabel = L10n.betterTG("Accessibility.SearchNewerResult")
        newerButton.addTarget(self, action: #selector(newerPressed), for: .touchUpInside)
        for button in [olderButton, newerButton] {
            addSubview(button)
        }

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentGuide.topAnchor.constraint(equalTo: topAnchor),
            contentGuide.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Self.sideInset),
            contentGuide.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Self.sideInset,
            ),
            contentGuide.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            leadingCapsule.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            leadingCapsule.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            leadingCapsule.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),
            leadingCapsule.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.capsuleHeight),
            leadingStack.topAnchor.constraint(equalTo: leadingCapsule.contentView.topAnchor),
            leadingStack.bottomAnchor.constraint(equalTo: leadingCapsule.contentView.bottomAnchor),
            leadingStack.leadingAnchor.constraint(equalTo: leadingCapsule.contentView.leadingAnchor),
            leadingStack.trailingAnchor.constraint(equalTo: leadingCapsule.contentView.trailingAnchor),
            leadingCapsule.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingCapsule.leadingAnchor,
                constant: -Self.capsuleInset,
            ),

            trailingCapsule.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            trailingCapsule.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            trailingCapsule.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),
            displayModeButton.topAnchor.constraint(equalTo: trailingCapsule.contentView.topAnchor),
            displayModeButton.bottomAnchor.constraint(equalTo: trailingCapsule.contentView.bottomAnchor),
            displayModeButton.leadingAnchor.constraint(equalTo: trailingCapsule.contentView.leadingAnchor),
            displayModeButton.trailingAnchor.constraint(equalTo: trailingCapsule.contentView.trailingAnchor),

            newerButton.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            newerButton.bottomAnchor.constraint(equalTo: leadingCapsule.topAnchor, constant: -Self.arrowSpacing),
            olderButton.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            olderButton.bottomAnchor.constraint(equalTo: newerButton.topAnchor, constant: -Self.arrowSpacing),
        ])
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
        button.tintColor = .label
        button.accessibilityLabel = label
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.capsuleHeight),
            button.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),
        ])
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

// MARK: - ChatSearchArrowButton

/// ChatHistoryNavigationButtonNode's up or down arrow: a 40 pt circle of interactive glass with the chevron inside,
/// at half opacity while it has nowhere to go.
private final class ChatSearchArrowButton: UIButton {
    override var isEnabled: Bool {
        didSet { iconView?.alpha = isEnabled ? 1 : 0.5 }
    }

    private var iconView: UIView?

    init(symbolName: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyTelegramFloatingGlass(icon: UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium),
        ))
        self.iconView = subviews.lazy.compactMap { ($0 as? UIVisualEffectView)?.contentView.subviews.first }.first
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ChatHistoryNavigationButton.side),
            heightAnchor.constraint(equalToConstant: ChatHistoryNavigationButton.side),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
