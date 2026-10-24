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

    // MARK: Private

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let titleControl = TelegramNavigationTitleControl()
    private let titleStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    /// An optional second button left of the right one, such as the chat list's compose button.
    private let secondaryRightButton = UIButton(type: .system)
    /// Telegram's Done while a list edits (ChatListControllerImpl.editPressed outside the root list).
    private let doneButton = UIButton(type: .system)
    private var doneAction: (() -> Void)?
    /// The title shown outside editing while a selection count replaces it.
    private var regularTitle: String?
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
        subtitleLabel.isHidden = text?.isEmpty != false || regularTitle != nil
        updateTitleInteraction()
    }

    /// Telegram's editing state outside the root list: Done replaces the right buttons, and a selection title such as
    /// "2 Topics Selected" replaces the title and status (ChatTitleComponent's custom content). A nil title shows the
    /// regular one; a nil action ends editing.
    func setEditing(title: String?, done: (() -> Void)?) {
        let editing = done != nil
        doneAction = done
        if let title, editing {
            if regularTitle == nil { regularTitle = titleLabel.text ?? "" }
            titleLabel.text = title
        } else if let regularTitle {
            titleLabel.text = regularTitle
            self.regularTitle = nil
        }
        subtitleLabel.isHidden = subtitleLabel.text?.isEmpty != false || regularTitle != nil
        rightButton.isHidden = editing
        secondaryRightButton.isHidden = editing || secondaryRightButton.image(for: .normal) == nil
        doneButton.isHidden = !editing
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
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.tintColor = .systemBlue
        doneButton.setTitle(L10n.telegram("Common.Done"), for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
        doneButton.isHidden = true
        doneButton.addAction(UIAction { [weak self] _ in self?.doneAction?() }, for: .touchUpInside)
        addSubview(doneButton)

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
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.isUserInteractionEnabled = false
        titleStack.addArrangedSubview(titleLabel)
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
            doneButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: Self.titleHeight),

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
            self.leftButton.alpha = active ? 0 : 1
            self.rightButton.alpha = active ? 0 : 1
            self.secondaryRightButton.alpha = active ? 0 : 1
            self.doneButton.alpha = active ? 0 : 1
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
        if let titleBadge, selectionCount == nil {
            titleLabel.attributedText = PeerCredibilityBadge.title(
                title,
                badge: titleBadge,
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
