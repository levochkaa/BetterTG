// TelegramNavigationBar.swift

import TDLibKit
import UIKit

// MARK: - TelegramListNavigationBar

final class TelegramListNavigationBar: UIView {
    // MARK: Internal

    static let titleHeight: CGFloat = 44
    static let expandedContentHeight = titleHeight + ChatListNavigationSearchView.scrollHeight

    var onSearchActiveChange: ((Bool) -> Void)?
    var onVisibleHeightChange: ((CGFloat) -> Void)?

    var onQueryChange: ((String) -> Void)? {
        didSet { searchView.onQueryChange = onQueryChange }
    }

    /// Makes the title a button, like Telegram's ChatTitleComponent opening the peer's info.
    var onTitleTap: (() -> Void)? {
        didSet { updateTitleInteraction() }
    }

    /// The proxy shield's tap: Telegram opens the proxy settings.
    var onProxyTap: (() -> Void)?

    /// ChatListTitleLockView's tap: the app locks.
    var onLockTap: (() -> Void)?

    // MARK: Private

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let titleControl = TelegramNavigationTitleControl()
    private let titleStack = UIStackView()
    /// The title with ChatListTitleView's activity indicator to its left while a network status replaces it.
    private let titleRow = UIStackView()
    private let networkActivityContainer = UIView()
    private let networkActivityIndicator = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    /// An optional second button left of the right one, such as the chat list's compose button.
    private let secondaryRightButton = UIButton(type: .system)
    /// ChatListController's proxyButton, left of the right buttons while a proxy is saved.
    private let proxyButton = ChatListProxyButton()
    /// ChatListTitleLockView: the open padlock after the title while a passcode is set.
    private let lockButton = UIButton(type: .system)
    private var proxyTitleConstraint: NSLayoutConstraint?
    /// Telegram's Done while a list edits (ChatListControllerImpl.editPressed outside the root list).
    private let doneButton = UIButton(type: .system)
    private var doneAction: (() -> Void)?
    /// A text button at the trailing edge in place of the right buttons, such as PeerSelectionController's Select.
    private let textActionButton = UIButton(type: .system)
    private var textAction: (() -> Void)?
    private var title: String
    /// A selection count such as "2 Topics Selected" replacing the title while editing.
    private var editingTitle: String?
    /// "Connecting..." and the like, replacing any title (ChatListControllerImpl's NetworkStatusTitle).
    private var networkStatus: String?
    private let searchView: ChatListNavigationSearchView
    private let leftAction: (() -> Void)?
    private let rightAction: (() -> Void)?
    private let secondaryRightAction: (() -> Void)?
    private let showsBackButton: Bool
    private var currentScrollOffset = CGFloat.zero

    var rightButtonView: UIView { rightButton }

    var isSearchActive: Bool { searchView.isActive }
    var hasMarkedText: Bool { searchView.hasMarkedText }
    #if DEBUG
    var probeSearchField: UISearchTextField { searchView.probeField }
    #endif

    init(
        title: String,
        placeholder: String,
        leftImage: UIImage?,
        rightImage: UIImage?,
        leftAction: (() -> Void)?,
        rightAction: (() -> Void)?,
        secondaryRightImage: UIImage? = nil,
        secondaryRightAction: (() -> Void)? = nil,
        secondaryRightAccessibilityLabel: String? = nil,
        showsBackButton: Bool = false,
        leftAccessibilityLabel: String? = nil,
        rightAccessibilityLabel: String? = nil,
    ) {
        self.searchView = ChatListNavigationSearchView(placeholder: placeholder)
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.secondaryRightAction = secondaryRightAction
        self.showsBackButton = showsBackButton
        self.title = title
        super.init(frame: .zero)
        titleLabel.text = title
        leftButton.setImage(leftImage, for: .normal)
        rightButton.setImage(rightImage, for: .normal)
        secondaryRightButton.setImage(secondaryRightImage, for: .normal)
        secondaryRightButton.isHidden = secondaryRightImage == nil
        configureViews()
        // Symbol images otherwise read their symbol names ("Gear shape") to VoiceOver.
        if let leftAccessibilityLabel { leftButton.accessibilityLabel = leftAccessibilityLabel }
        if let rightAccessibilityLabel { rightButton.accessibilityLabel = rightAccessibilityLabel }
        if let secondaryRightAccessibilityLabel {
            secondaryRightButton.accessibilityLabel = secondaryRightAccessibilityLabel
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyScroll(offset: CGFloat, animated: Bool = false) {
        let clipped = min(max(0, offset), ChatListNavigationSearchView.scrollHeight)
        currentScrollOffset = clipped
        guard !isSearchActive else {
            searchView.applyScroll(offset: clipped, animated: false)
            onVisibleHeightChange?(ChatListNavigationSearchView.scrollHeight)
            return
        }
        searchView.applyScroll(offset: clipped, animated: animated)
        onVisibleHeightChange?(Self.expandedContentHeight - clipped)
    }

    func focusSearch() {
        searchView.focus()
    }

    func restoreSearchQuery(_ query: String) {
        searchView.restoreQuery(query)
    }

    func setLeftButtonHidden(_ hidden: Bool) {
        leftButton.isHidden = hidden
    }

    /// A secondary line under the title, as Telegram shows a forum's member status.
    func setSubtitle(_ text: String?) {
        subtitleLabel.text = text
        updateTitle()
    }

    /// Telegram's chat list network status: "Connecting..." or the like with an activity indicator in place of the
    /// title; nil restores the title.
    func setNetworkStatus(_ status: String?) {
        guard status != networkStatus else { return }
        networkStatus = status
        updateTitle()
    }

    /// Telegram's editing state outside the root list: Done replaces the right buttons, and a selection title such as
    /// Shows the padlock after the title while the app has a passcode.
    func setLockVisible(_ visible: Bool) {
        lockButton.isHidden = !visible
    }

    /// ChatTitleProxyNode's status, or nil to hide the shield. The title keeps clear of it while it shows.
    func setProxyStatus(_ status: ChatListProxyStatus?) {
        proxyButton.status = status
        let shows = status != nil
        proxyButton.isHidden = !shows
        if shows, proxyTitleConstraint == nil {
            let constraint = titleControl.trailingAnchor.constraint(
                lessThanOrEqualTo: proxyButton.leadingAnchor,
                constant: -8,
            )
            constraint.isActive = true
            proxyTitleConstraint = constraint
        }
        proxyTitleConstraint?.isActive = shows
    }

    /// "2 Topics Selected" replaces the title and status (ChatTitleComponent's custom content). A nil title shows the
    /// regular one; a nil action ends editing.
    func setEditing(title: String?, done: (() -> Void)?) {
        let editing = done != nil
        doneAction = done
        editingTitle = editing ? title : nil
        rightButton.isHidden = editing
        secondaryRightButton.isHidden = editing || secondaryRightButton.image(for: .normal) == nil
        doneButton.isHidden = !editing
        updateTitle()
    }

    /// Shows `title` as a text button at the trailing edge in place of the right buttons; nil removes it.
    func setTextAction(_ title: String?, action: (() -> Void)?) {
        textAction = title == nil ? nil : action
        textActionButton.setTitle(title, for: .normal)
        textActionButton.isHidden = title == nil
        rightButton.isHidden = title != nil || doneAction != nil
    }

    private func updateTitle() {
        titleLabel.text = networkStatus ?? editingTitle ?? title
        subtitleLabel.isHidden = subtitleLabel.text?.isEmpty != false || editingTitle != nil
        let showsActivity = networkStatus != nil
        networkActivityContainer.isHidden = !showsActivity
        if showsActivity {
            networkActivityIndicator.startAnimating()
        } else {
            networkActivityIndicator.stopAnimating()
        }
        // ChatListTitleView pads the title by the indicator plus 6 and sets the indicator 4 left of the title.
        titleRow.directionalLayoutMargins.leading = showsActivity ? 2 : 0
        updateTitleInteraction()
    }

    private func updateTitleInteraction() {
        let tappable = onTitleTap != nil && doneAction == nil
        titleControl.isUserInteractionEnabled = tappable
        // Without an action the labels stay separate static text, as before.
        titleControl.isAccessibilityElement = tappable
        titleControl.accessibilityTraits = tappable ? .button : []
        let subtitle = subtitleLabel.isHidden ? nil : subtitleLabel.text
        titleControl.accessibilityLabel = [titleLabel.text, subtitle].compactMap(\.self).joined(separator: ", ")
    }

    private func configureViews() {
        clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        for button in [leftButton, rightButton, secondaryRightButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .systemBlue
            if button !== leftButton || !showsBackButton {
                button.setPreferredSymbolConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 18, weight: .medium),
                    forImageIn: .normal,
                )
            }
            addSubview(button)
        }
        if showsBackButton { leftButton.accessibilityLabel = L10n.telegram("Common.Back") }
        leftButton.addTarget(self, action: #selector(leftPressed), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(rightPressed), for: .touchUpInside)
        secondaryRightButton.addTarget(self, action: #selector(secondaryRightPressed), for: .touchUpInside)
        proxyButton.translatesAutoresizingMaskIntoConstraints = false
        proxyButton.isHidden = true
        proxyButton.addAction(UIAction { [weak self] _ in self?.onProxyTap?() }, for: .touchUpInside)
        addSubview(proxyButton)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.tintColor = .systemBlue
        doneButton.setTitle(L10n.telegram("Common.Done"), for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
        doneButton.isHidden = true
        doneButton.addAction(UIAction { [weak self] _ in self?.doneAction?() }, for: .touchUpInside)
        addSubview(doneButton)
        textActionButton.translatesAutoresizingMaskIntoConstraints = false
        textActionButton.tintColor = .systemBlue
        textActionButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        textActionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        textActionButton.isHidden = true
        textActionButton.addAction(UIAction { [weak self] _ in self?.textAction?() }, for: .touchUpInside)
        addSubview(textActionButton)

        titleLabel.textColor = .label
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textAlignment = .center
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isHidden = true
        // ActivityIndicator `.custom(primaryTextColor, 22, 1.5, false)`: the large system spinner scaled into 22 pt,
        // gray for black text.
        networkActivityIndicator.color = UIColor { $0.userInterfaceStyle == .dark ? .white : .gray }
        networkActivityIndicator.transform = CGAffineTransform(scaleX: 22 / 37, y: 22 / 37)
        networkActivityIndicator.hidesWhenStopped = false
        networkActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        networkActivityContainer.translatesAutoresizingMaskIntoConstraints = false
        networkActivityContainer.isHidden = true
        networkActivityContainer.addSubview(networkActivityIndicator)
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 4
        titleRow.isLayoutMarginsRelativeArrangement = true
        titleRow.directionalLayoutMargins = .zero
        titleRow.addArrangedSubview(networkActivityContainer)
        titleRow.addArrangedSubview(titleLabel)
        lockButton.setImage(UIImage(
            systemName: "lock.open.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
        ), for: .normal)
        lockButton.tintColor = .label
        lockButton.accessibilityLabel = L10n.telegram("PasscodeSettings.Title")
        lockButton.isHidden = true
        lockButton.addAction(UIAction { [weak self] _ in self?.onLockTap?() }, for: .touchUpInside)
        // ChatListTitleView: outside the title, whose views take no touches.
        lockButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lockButton)
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.isUserInteractionEnabled = false
        titleStack.addArrangedSubview(titleRow)
        titleStack.addArrangedSubview(subtitleLabel)
        titleControl.translatesAutoresizingMaskIntoConstraints = false
        titleControl.highlightedContentView = titleStack
        titleControl.addTarget(self, action: #selector(titlePressed), for: .touchUpInside)
        titleControl.addSubview(titleStack)
        addSubview(titleControl)
        updateTitleInteraction()

        searchView.translatesAutoresizingMaskIntoConstraints = false
        searchView.onActiveChange = { [weak self] active in
            self?.setSearchActive(active)
        }
        addSubview(searchView)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        // The title keeps clear of the leftmost right button.
        let rightmostTitleNeighbor = secondaryRightButton.isHidden ? rightButton : secondaryRightButton
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leftButton.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: showsBackButton
                    ? 2
                    : 6,
            ),
            leftButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            leftButton.widthAnchor.constraint(equalToConstant: 44),
            leftButton.heightAnchor.constraint(equalToConstant: Self.titleHeight),
            rightButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            rightButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            rightButton.widthAnchor.constraint(equalToConstant: 44),
            rightButton.heightAnchor.constraint(equalToConstant: Self.titleHeight),
            secondaryRightButton.trailingAnchor.constraint(equalTo: rightButton.leadingAnchor),
            secondaryRightButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            secondaryRightButton.widthAnchor.constraint(equalToConstant: 44),
            secondaryRightButton.heightAnchor.constraint(equalToConstant: Self.titleHeight),
            // Centered 12 pt before the title's text.
            lockButton.centerXAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -12),
            lockButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: 28),
            lockButton.heightAnchor.constraint(equalToConstant: 32),
            proxyButton.trailingAnchor.constraint(equalTo: rightmostTitleNeighbor.leadingAnchor),
            proxyButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            proxyButton.widthAnchor.constraint(equalToConstant: 44),
            proxyButton.heightAnchor.constraint(equalToConstant: Self.titleHeight),
            doneButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: Self.titleHeight),
            textActionButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            textActionButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            textActionButton.heightAnchor.constraint(equalToConstant: Self.titleHeight),

            titleControl.leadingAnchor.constraint(greaterThanOrEqualTo: leftButton.trailingAnchor, constant: 8),
            titleControl.trailingAnchor.constraint(
                lessThanOrEqualTo: rightmostTitleNeighbor.leadingAnchor,
                constant: -8,
            ),
            titleControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleControl.topAnchor.constraint(equalTo: leftButton.topAnchor),
            titleControl.bottomAnchor.constraint(equalTo: leftButton.bottomAnchor),
            titleStack.leadingAnchor.constraint(equalTo: titleControl.leadingAnchor),
            titleStack.trailingAnchor.constraint(equalTo: titleControl.trailingAnchor),
            titleStack.centerYAnchor.constraint(equalTo: titleControl.centerYAnchor),
            networkActivityContainer.widthAnchor.constraint(equalToConstant: 22),
            networkActivityContainer.heightAnchor.constraint(equalToConstant: 22),
            networkActivityIndicator.centerXAnchor.constraint(equalTo: networkActivityContainer.centerXAnchor),
            networkActivityIndicator.centerYAnchor.constraint(equalTo: networkActivityContainer.centerYAnchor),

            searchView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: Self.titleHeight),
            searchView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            searchView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            searchView.heightAnchor.constraint(equalToConstant: ChatListNavigationSearchView.scrollHeight),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }

    @objc private func leftPressed() { leftAction?() }
    @objc private func rightPressed() { rightAction?() }
    @objc private func secondaryRightPressed() { secondaryRightAction?() }
    @objc private func titlePressed() { onTitleTap?() }

    private func setSearchActive(_ active: Bool) {
        let parentView = superview
        parentView?.layoutIfNeeded()
        onVisibleHeightChange?(active
            ? ChatListNavigationSearchView.scrollHeight
            : Self.expandedContentHeight - currentScrollOffset)
        onSearchActiveChange?(active)

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
        ) {
            self.titleControl.alpha = active ? 0 : 1
            self.lockButton.alpha = active ? 0 : 1
            self.leftButton.alpha = active ? 0 : 1
            self.rightButton.alpha = active ? 0 : 1
            self.secondaryRightButton.alpha = active ? 0 : 1
            self.proxyButton.alpha = active ? 0 : 1
            self.doneButton.alpha = active ? 0 : 1
            self.textActionButton.alpha = active ? 0 : 1
            self.searchView.transform = active
                ? CGAffineTransform(translationX: 0, y: -Self.titleHeight)
                : .identity
            parentView?.layoutIfNeeded()
        }
    }
}

// MARK: - TelegramChatNavigationBar

final class TelegramChatNavigationBar: UIView, UITextFieldDelegate {
    // MARK: Internal

    /// Telegram's search domains (ChatSearchDomain): the whole chat, picking a member after "from:", or one member.
    enum SearchMemberScope: Equatable {
        case none
        case choosing
        case chosen(String)
    }

    struct TitleIcons: Equatable {
        var lock = false
        var mute = false
    }

    static let contentHeight: CGFloat = 44

    var onBack: (() -> Void)?
    var onSelectionCancel: (() -> Void)?
    var onSearchQueryChange: ((String) -> Void)?
    var onSearchActiveChange: ((Bool) -> Void)?
    /// The "from:" prefix or the member token was erased; receives the scope it left.
    var onSearchMemberScopeCleared: ((SearchMemberScope) -> Void)?
    var onProfile: (() -> Void)?
    /// Shown instead of the avatar by `setShowsMoreButton(true)`; receives the button as the menu source.
    var onMore: ((UIView) -> Void)?

    /// ChatTitleView's titleLeftIcon (a secret chat's lock) and titleRightIcon (a muted chat's speaker).
    var titleIcons = TitleIcons() {
        didSet {
            guard titleIcons != oldValue, selectionCount == nil else { return }
            applyTitle(
                title: configuredTitle,
                status: configuredStatus,
                statusColor: configuredStatusColor,
                activity: configuredActivity,
            )
        }
    }

    /// ChatTitleView's credibility icon after the title; selection titles go without it.
    var titleBadge: PeerCredibilityBadge? {
        didSet {
            guard titleBadge != oldValue, selectionCount == nil else { return }
            applyTitle(
                title: configuredTitle,
                status: configuredStatus,
                statusColor: configuredStatusColor,
                activity: configuredActivity,
            )
        }
    }

    // MARK: Private

    private let separator = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let backButton = UIButton(type: .system)
    private let titleControl = TelegramNavigationTitleControl()
    private let titleStack = UIStackView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    /// ChatTitleActivityNode's indicator before an activity's status, centred with it.
    private let statusActivityView = ChatActivityIndicatorView(frame: CGRect(
        origin: .zero,
        size: ChatActivityIndicatorView.size,
    ))
    private lazy var statusRow = UIStackView(arrangedSubviews: [statusActivityView, statusLabel])
    private let avatarView = ProfileAvatarView()
    private let moreButton = UIButton(type: .system)
    private var showsMoreButton = false
    private let searchField = ChatSearchTextField()
    private var searchMemberScope = SearchMemberScope.none
    private var defaultSearchLeftView: UIView?
    private let searchMemberPrefixLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let selectionCancelButton = UIButton(type: .system)
    private var searchActive = false
    private var selectionCount: Int?
    private var backButtonExplicitlyHidden = false
    private var regularTitleLeadingConstraint: NSLayoutConstraint!
    private var regularTitleTrailingConstraint: NSLayoutConstraint!
    private var selectionTitleLeadingConstraint: NSLayoutConstraint!
    private var selectionTitleTrailingConstraint: NSLayoutConstraint!
    private var configuredTitle = ""
    private var configuredStatus = ""
    private var configuredStatusColor = UIColor.secondaryLabel
    private var configuredActivity: ChatActivityIndicatorView.Kind?

    var visibleContentHeight: CGFloat { searchActive ? ChatListNavigationSearchView.scrollHeight : Self.contentHeight }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The title with the lock 6 pt before it, the credibility badge after it and the speaker 3 pt after both.
    private static func decoratedTitle(
        _ title: String,
        badge: PeerCredibilityBadge?,
        icons: TitleIcons,
        font: UIFont,
        color: UIColor,
    ) -> NSAttributedString {
        func icon(_ name: String, pointSize: CGFloat, tint: UIColor) -> NSAttributedString {
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            guard let image = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(tint, renderingMode: .alwaysOriginal) else { return NSAttributedString() }
            let attachment = NSTextAttachment(image: image)
            attachment.bounds = CGRect(
                x: 0,
                y: (font.capHeight - image.size.height) / 2,
                width: image.size.width,
                height: image.size.height,
            )
            return NSAttributedString(attachment: attachment)
        }
        func gap(_ width: CGFloat) -> NSAttributedString {
            NSAttributedString(string: "\u{200A}", attributes: [.font: font, .kern: width])
        }
        let result = NSMutableAttributedString()
        if icons.lock {
            result.append(icon("lock.fill", pointSize: font.pointSize * 0.62, tint: color))
            result.append(gap(4))
        }
        result.append(PeerCredibilityBadge.title(title, badge: badge, font: font, color: color))
        if icons.mute {
            result.append(gap(2))
            result.append(icon("speaker.slash.fill", pointSize: font.pointSize * 0.55, tint: .secondaryLabel))
        }
        return result
    }

    func useSharedBackground() {
        blurView.isHidden = true
    }

    /// `activity` adds its animated indicator before the status, for a status that words an activity.
    func configure(
        title: String,
        status: String,
        statusColor: UIColor,
        activity: ChatActivityIndicatorView.Kind? = nil,
    ) {
        configuredTitle = title
        configuredStatus = status
        configuredStatusColor = statusColor
        configuredActivity = activity
        guard selectionCount == nil else { return }
        applyTitle(title: title, status: status, statusColor: statusColor, activity: activity)
    }

    func setSelectionCount(_ count: Int?) {
        if count != nil, searchActive {
            endSearch()
        }
        selectionCount = count
        if let count {
            regularTitleLeadingConstraint.isActive = false
            regularTitleTrailingConstraint.isActive = false
            selectionTitleLeadingConstraint.isActive = true
            selectionTitleTrailingConstraint.isActive = true
            backButton.isHidden = true
            selectionCancelButton.isHidden = false
            avatarView.isHidden = true
            moreButton.isHidden = true
            titleControl.isUserInteractionEnabled = false
            applyTitle(
                title: L10n.telegramPlural("Conversation.SelectedMessagesFormat", count: count)
                    .replacing("{}", with: String(count)),
                status: "",
                statusColor: .secondaryLabel,
            )
        } else {
            selectionTitleLeadingConstraint.isActive = false
            selectionTitleTrailingConstraint.isActive = false
            regularTitleLeadingConstraint.isActive = true
            regularTitleTrailingConstraint.isActive = true
            backButton.isHidden = backButtonExplicitlyHidden
            selectionCancelButton.isHidden = true
            avatarView.isHidden = showsMoreButton
            moreButton.isHidden = !showsMoreButton
            titleControl.isUserInteractionEnabled = true
            applyTitle(
                title: configuredTitle,
                status: configuredStatus,
                statusColor: configuredStatusColor,
                activity: configuredActivity,
            )
        }
    }

    func configureAvatar(
        file: File?,
        largeFile: File?,
        minithumbnail: Minithumbnail?,
        placeholder: TelegramAvatarPlaceholder,
        client: TDLibClient,
    ) {
        avatarView.configure(
            file: file,
            largeFile: largeFile,
            minithumbnail: minithumbnail,
            placeholder: placeholder,
            client: client,
        )
        avatarView.onOpenProfile = { [weak self] in self?.onProfile?() }
        avatarView.onSearch = { [weak self] in self?.beginSearch() }
    }

    /// The avatar's menu items in place of Open Profile / Search / Save Image; nil restores those.
    func setAvatarMenuActions(_ actions: (() -> [TelegramContextMenuAction])?) {
        avatarView.contextMenuActions = actions
    }

    func setSearchResultFound(_ found: Bool?) {
        searchField.textColor = found == false ? .systemRed : .label
    }

    /// ChatSearchNavigationContentNode: the "from:" prefix while a member is picked, then the member's token.
    func setSearchMemberScope(_ scope: SearchMemberScope) {
        searchMemberScope = scope
        searchField.text = ""
        searchField.textColor = .label
        switch scope {
        case .none:
            searchField.tokens = []
            searchField.leftView = defaultSearchLeftView
            searchField.placeholder = L10n.telegram("Conversation.SearchPlaceholder")
        case .choosing:
            searchField.tokens = []
            searchMemberPrefixLabel.sizeToFit()
            searchField.leftView = searchMemberPrefixLabel
            searchField.placeholder = L10n.telegram("Conversation.SearchByName.Placeholder")
        case .chosen(let title):
            searchField.leftView = defaultSearchLeftView
            searchField.placeholder = nil
            searchField.tokens = [UISearchToken(icon: UIImage(systemName: "person.fill"), text: title)]
        }
    }

    func dismissSearchKeyboard() {
        searchField.resignFirstResponder()
    }

    func focusSearchField() {
        guard searchActive else { return }
        searchField.becomeFirstResponder()
    }

    /// Closes the search as its close button does.
    func cancelSearch() {
        endSearch()
    }

    /// Telegram shows More in place of the avatar for a forum read as messages
    /// (rightNavigationButtonForChatInterfaceState, moreInfoNavigationButton).
    func setShowsMoreButton(_ shows: Bool) {
        showsMoreButton = shows
        let selecting = selectionCount != nil
        avatarView.isHidden = selecting || shows
        moreButton.isHidden = selecting || !shows
    }

    func setBackButtonHidden(_ hidden: Bool) {
        backButtonExplicitlyHidden = hidden
        if selectionCount == nil {
            backButton.isHidden = hidden
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc func beginSearch() {
        guard !searchActive, selectionCount == nil else { return }
        searchActive = true
        searchField.isHidden = false
        closeButton.isHidden = false
        searchField.textColor = .label
        onSearchActiveChange?(true)
        searchField.becomeFirstResponder()
        UIView.animate(withDuration: 0.2) {
            self.titleControl.alpha = 0
            self.avatarView.alpha = 0
            self.moreButton.alpha = 0
            self.backButton.alpha = 0
            self.searchField.alpha = 1
            self.closeButton.alpha = 1
        }
    }

    private func applyTitle(
        title: String,
        status: String,
        statusColor: UIColor,
        activity: ChatActivityIndicatorView.Kind? = nil,
    ) {
        if selectionCount == nil, titleBadge != nil || titleIcons != TitleIcons() {
            titleLabel.attributedText = Self.decoratedTitle(
                title,
                badge: titleBadge,
                icons: titleIcons,
                font: titleLabel.font,
                color: titleLabel.textColor ?? .label,
            )
        } else {
            titleLabel.text = title
        }
        statusLabel.text = status
        statusLabel.textColor = statusColor
        statusRow.isHidden = status.isEmpty
        if let activity {
            statusActivityView.kind = activity
            statusActivityView.color = statusColor
        }
        statusActivityView.isHidden = activity == nil
        titleControl.accessibilityLabel = status.isEmpty ? title : "\(title), \(status)"
    }

    private func configureViews() {
        clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.accessibilityLabel = L10n.telegram("Common.Back")
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        addSubview(backButton)

        titleControl.translatesAutoresizingMaskIntoConstraints = false
        titleControl.accessibilityHint = L10n.betterTG("Accessibility.OpenProfileHint")
        titleControl.accessibilityTraits = .button
        titleControl.addTarget(self, action: #selector(profilePressed), for: .touchUpInside)
        titleControl.addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(titleLongPressed(_:))),
        )
        addSubview(titleControl)

        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        titleStack.addArrangedSubview(titleLabel)
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusActivityView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusActivityView.widthAnchor.constraint(equalToConstant: ChatActivityIndicatorView.size.width),
            statusActivityView.heightAnchor.constraint(equalToConstant: ChatActivityIndicatorView.size.height),
        ])
        statusActivityView.isHidden = true
        titleStack.addArrangedSubview(statusRow)
        titleStack.isUserInteractionEnabled = false
        titleControl.highlightedContentView = titleStack
        titleControl.addSubview(titleStack)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profilePressed)))
        addSubview(avatarView)

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .medium),
            forImageIn: .normal,
        )
        moreButton.tintColor = .systemBlue
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.isHidden = true
        moreButton.addTarget(self, action: #selector(morePressed), for: .touchUpInside)
        addSubview(moreButton)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = L10n.telegram("Conversation.SearchPlaceholder")
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.borderStyle = .none
        searchField.backgroundColor = .tertiarySystemFill
        searchField.layer.cornerRadius = 18
        searchField.layer.cornerCurve = .continuous
        searchField.clipsToBounds = true
        searchField.delegate = self
        searchField.alpha = 0
        searchField.isHidden = true
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.onDeleteBackward = { [weak self] wasEmpty in
            guard let self else { return }
            switch searchMemberScope {
            case .choosing where wasEmpty: clearSearchMemberScopeFromInput()
            case .chosen where searchField.tokens.isEmpty: clearSearchMemberScopeFromInput()
            case .choosing,
                 .chosen,
                 .none: break
            }
        }
        defaultSearchLeftView = searchField.leftView
        searchMemberPrefixLabel.text = L10n.telegram("Conversation.SearchByName.Prefix")
        searchMemberPrefixLabel.font = .preferredFont(forTextStyle: .body)
        searchMemberPrefixLabel.textColor = .label
        addSubview(searchField)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = L10n.betterTG("Accessibility.CloseSearch")
        closeButton.alpha = 0
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(endSearch), for: .touchUpInside)
        addSubview(closeButton)

        selectionCancelButton.translatesAutoresizingMaskIntoConstraints = false
        selectionCancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        selectionCancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        selectionCancelButton.accessibilityLabel = L10n.betterTG("Accessibility.CancelSelection")
        selectionCancelButton.isHidden = true
        selectionCancelButton.addTarget(self, action: #selector(selectionCancelPressed), for: .touchUpInside)
        addSubview(selectionCancelButton)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        regularTitleLeadingConstraint = titleControl.leadingAnchor.constraint(equalTo: backButton.trailingAnchor)
        regularTitleTrailingConstraint = titleControl.trailingAnchor.constraint(equalTo: avatarView.leadingAnchor)
        selectionTitleLeadingConstraint = titleControl.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor,
            constant: 80,
        )
        selectionTitleTrailingConstraint = titleControl.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -80,
        )
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 2),
            backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            avatarView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            avatarView.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 34),
            avatarView.heightAnchor.constraint(equalToConstant: 34),
            moreButton.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            moreButton.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            regularTitleLeadingConstraint,
            regularTitleTrailingConstraint,
            titleControl.topAnchor.constraint(equalTo: backButton.topAnchor),
            titleControl.bottomAnchor.constraint(equalTo: backButton.bottomAnchor),
            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleControl.leadingAnchor, constant: 4),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: titleControl.trailingAnchor, constant: -4),
            titleStack.centerXAnchor.constraint(equalTo: titleControl.centerXAnchor),
            titleStack.centerYAnchor.constraint(equalTo: titleControl.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 38),
            closeButton.heightAnchor.constraint(equalToConstant: 38),
            selectionCancelButton.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -4,
            ),
            selectionCancelButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            selectionCancelButton.widthAnchor.constraint(equalToConstant: 72),
            selectionCancelButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            searchField.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            searchField.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }

    @objc private func backPressed() {
        onBack?()
    }

    @objc private func profilePressed() {
        onProfile?()
    }

    @objc private func morePressed() {
        onMore?(moreButton)
    }

    @objc private func selectionCancelPressed() {
        onSelectionCancel?()
    }

    @objc private func titleLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        beginSearch()
    }

    @objc private func endSearch() {
        guard searchActive else { return }
        searchActive = false
        setSearchMemberScope(.none)
        searchField.text = ""
        searchField.resignFirstResponder()
        onSearchQueryChange?("")
        onSearchActiveChange?(false)
        UIView.animate(withDuration: 0.2) {
            self.titleControl.alpha = 1
            self.avatarView.alpha = 1
            self.moreButton.alpha = 1
            self.backButton.alpha = 1
            self.searchField.alpha = 0
            self.closeButton.alpha = 0
        } completion: { _ in
            self.searchField.isHidden = true
            self.closeButton.isHidden = true
        }
    }

    @objc private func searchChanged() {
        searchField.textColor = .label
        if case .chosen = searchMemberScope, searchField.tokens.isEmpty {
            clearSearchMemberScopeFromInput()
            return
        }
        onSearchQueryChange?(searchField.text ?? "")
    }

    private func clearSearchMemberScopeFromInput() {
        let previous = searchMemberScope
        guard previous != .none else { return }
        searchMemberScope = .none
        onSearchMemberScopeCleared?(previous)
    }
}

// MARK: - ChatSearchTextField

/// Reports Backspace, so an empty field can drop Telegram's "from:" prefix or the member token.
private final class ChatSearchTextField: UISearchTextField {
    var onDeleteBackward: ((_ wasEmpty: Bool) -> Void)?

    override func deleteBackward() {
        let wasEmpty = (text ?? "").isEmpty && tokens.isEmpty
        super.deleteBackward()
        onDeleteBackward?(wasEmpty)
    }
}

// MARK: - TelegramNavigationTitleControl

private final class TelegramNavigationTitleControl: UIControl {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            ) {
                self.highlightedContentView?.alpha = self.isHighlighted ? 0.2 : 1
            }
        }
    }

    weak var highlightedContentView: UIView?

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isHighlighted = true
        return super.beginTracking(touch, with: event)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isHighlighted = bounds.contains(touch.location(in: self))
        return super.continueTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        isHighlighted = false
        super.endTracking(touch, with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
        super.cancelTracking(with: event)
    }
}

// MARK: - ChatListProxyButton

/// ChatTitleProxyNode in a 44 pt button: the shield with a check while connected through the proxy, with the power
/// sign while no proxy is on, and with a small spinner while connecting.
final class ChatListProxyButton: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.4 : 1 }
    }

    var status: ChatListProxyStatus? {
        didSet { update() }
    }

    private let shieldView = UIImageView(image: UIImage(
        systemName: "shield",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular),
    ))
    private let badgeView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [shieldView, badgeView, activityIndicator] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        shieldView.tintColor = .systemBlue
        badgeView.tintColor = .systemBlue
        activityIndicator.color = .systemBlue
        activityIndicator.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        NSLayoutConstraint.activate([
            shieldView.centerXAnchor.constraint(equalTo: centerXAnchor),
            shieldView.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeView.centerXAnchor.constraint(equalTo: centerXAnchor),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = L10n.telegram("SocksProxySetup.Title")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func update() {
        let badge: String? =
            switch status {
            case .connected: "checkmark"
            case .available: "power"
            case .connecting,
                 nil: nil
            }
        badgeView.image = badge.map {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        } ?? nil
        if status == .connecting {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        accessibilityValue =
            switch status {
            case .connected: L10n.telegram("SocksProxySetup.ProxyStatusConnected")
            case .connecting: L10n.telegram("SocksProxySetup.ProxyStatusConnecting")
            case .available,
                 nil: nil
            }
    }
}
