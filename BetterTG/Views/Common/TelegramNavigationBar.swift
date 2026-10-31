// TelegramNavigationBar.swift

import TDLibKit
import UIKit

// MARK: - TelegramListNavigationBar

final class TelegramListNavigationBar: UIView {
    // MARK: Internal

    static let titleHeight: CGFloat = 44
    static let expandedContentHeight = titleHeight + ChatListNavigationSearchView.contentHeight

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

    /// A long press on the right button, such as Settings opening the account switcher; receives the button's glass
    /// circle, which the menu morphs out of, and the press, which goes on to pick an item.
    var onRightLongPress: ((UIView, UIGestureRecognizer) -> Void)? {
        didSet { rightLongPress.isEnabled = onRightLongPress != nil }
    }

    // MARK: Private

    private let blurView = TelegramBarBackgroundView(edge: .top)
    private let titleControl = TelegramNavigationTitleControl()
    private let titleStack = UIStackView()
    /// The title with ChatListTitleView's activity indicator to its left while a network status replaces it.
    private let titleRow = UIStackView()
    private let networkActivityContainer = UIView()
    private let networkActivityIndicator = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let leftButton = UIButton.telegramGlassIcon(nil)
    private let rightButton = UIButton.telegramGlassIcon(nil)
    /// An optional second button left of the right one, such as the chat list's compose button.
    private let secondaryRightButton = UIButton.telegramGlassIcon(nil)
    /// The left button's circle; each right button, Done and a text action in a circle or pill of its own, 12 pt
    /// apart, as Telegram 13's chat list keeps compose and its other buttons apart.
    private let leadingPlatter = TelegramGlassPlatter(role: .leading)
    private let trailingPlatter = TelegramGlassPlatter(role: .trailing(0))
    private let secondaryTrailingPlatter = TelegramGlassPlatter(role: .trailing(1))
    private let proxyPlatter = TelegramGlassPlatter(role: .trailing(2))
    private let doneButtonPlatter = TelegramGlassPlatter(role: .trailing(0))
    private let textActionPlatter = TelegramGlassPlatter(role: .trailing(0))
    private lazy var rightLongPress: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(rightLongPressed(_:)))
        recognizer.minimumPressDuration = 0.4
        recognizer.isEnabled = false
        return recognizer
    }()

    private let trailingStack = UIStackView()
    /// iPhone Duo's strip, which holds the left and the icon buttons in place of the row. It stands beside the bar,
    /// which is only as tall as its row.
    private let columnStack = UIStackView()
    /// Clips the search field as it collapses with the list.
    private let searchClipView = UIView()
    private var leadingRowConstraints = [NSLayoutConstraint]()
    private var titleLeadingRowConstraint: NSLayoutConstraint?
    private var titleLeadingColumnConstraint: NSLayoutConstraint!
    private var columnXConstraint: NSLayoutConstraint?
    private var columnYConstraint: NSLayoutConstraint?
    private var trailingEdgeConstraint: NSLayoutConstraint!
    private var searchTrailingConstraint: NSLayoutConstraint!
    private var appliedDuoLayout: IPhoneDuoLayout?
    /// ChatListController's proxyButton, left of the right buttons while a proxy is saved.
    private let proxyButton = ChatListProxyButton()
    /// ChatListTitleLockView: the open padlock after the title while a passcode is set.
    private let lockButton = UIButton(type: .system)
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
    /// How far the list is pulled past its top.
    private var currentOverscroll = CGFloat.zero
    /// The last scroll state applied: the search field's collapse, the pull and whether search was active.
    private var appliedScroll: (CGFloat, CGFloat, Bool)?
    private var searchTopConstraint: NSLayoutConstraint!
    /// Whether the bar clipped before a chat preview's title travelled over it.
    private var clipsBeforeExpansion: Bool?

    /// The right button's glass circle; a menu opened from it morphs the whole pill, as Telegram's do.
    var rightButtonView: UIView { trailingPlatter }

    /// The bar's glass platters for the push and pop morph, leading first.
    var glassPlatters: [TelegramGlassPlatter] {
        allPlatters.filter { !$0.isHidden }
    }

    var isSearchActive: Bool { searchView.isActive }
    var hasMarkedText: Bool { searchView.hasMarkedText }
    #if DEBUG
    var probeSearchField: UISearchTextField { searchView.probeField }
    #endif

    private var allPlatters: [TelegramGlassPlatter] {
        [
            leadingPlatter, trailingPlatter, secondaryTrailingPlatter, proxyPlatter, doneButtonPlatter,
            textActionPlatter,
        ]
    }

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

    override func layoutSubviews() {
        // Off screen there's no window to read; the navigation controller gives an incoming screen its layout.
        if window != nil { applyIPhoneDuoLayout(superview?.iPhoneDuoLayout) }
        super.layoutSubviews()
    }

    /// The bar's height with the search field scrolled `clipped` away. It shrinks with the list, so the first row
    /// stays at its edge, and stops with UIKit's space under the row of platters.
    private static func visibleHeight(clipped: CGFloat) -> CGFloat {
        expandedContentHeight - clipped
    }

    /// The owner extends one backdrop behind this bar and its accessory panels.
    func useSharedBackground() {
        blurView.isHidden = true
    }

    /// `offset` is the list's distance from its top; a negative one pulls the list past it. ChatListNavigationBar
    /// leaves that pull unclipped: the bar grows with it and the search field rides down above the first row.
    func applyScroll(offset: CGFloat, animated: Bool = false) {
        let clipped = min(max(0, offset), ChatListNavigationSearchView.scrollHeight)
        let overscroll = isSearchActive ? 0 : max(0, -offset)
        // ChatListNavigationBar's applyScroll returns early too: a list scrolled past the search field changes
        // nothing here, and restyling the field on every scroll event cost the scrolling list frames.
        if !animated, let last = appliedScroll, last == (clipped, overscroll, isSearchActive) { return }
        appliedScroll = (clipped, overscroll, isSearchActive)
        currentScrollOffset = clipped
        currentOverscroll = overscroll
        searchTopConstraint.constant = Self.titleHeight + currentOverscroll
        guard !isSearchActive else {
            searchView.applyScroll(offset: clipped, animated: false)
            onVisibleHeightChange?(ChatListNavigationSearchView.contentHeight)
            return
        }
        searchView.applyScroll(offset: clipped, animated: animated)
        onVisibleHeightChange?(Self.visibleHeight(clipped: clipped) + currentOverscroll)
    }

    func focusSearch() {
        searchView.focus()
    }

    func restoreSearchQuery(_ query: String) {
        searchView.restoreQuery(query)
    }

    func setLeftButtonHidden(_ hidden: Bool) {
        leftButton.isHidden = hidden
        leadingPlatter.refresh()
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

    /// ChatTitleProxyNode's status, or nil to hide the shield, which joins the right buttons' pill.
    func setProxyStatus(_ status: ChatListProxyStatus?) {
        proxyButton.status = status
        let shows = status != nil
        proxyButton.isHidden = !shows
        refreshPlatters()
    }

    /// "2 Topics Selected" replaces the title and status (ChatTitleComponent's custom content). A nil title shows the
    /// regular one; a nil action ends editing.
    func setEditing(title: String?, done: (() -> Void)?) {
        let editing = done != nil
        doneAction = done
        editingTitle = editing ? title : nil
        rightButton.isHidden = editing
        secondaryRightButton.isHidden = editing || secondaryRightButton.image(for: .normal) == nil
        proxyButton.isHidden = editing || proxyButton.status == nil
        doneButton.isHidden = !editing
        refreshPlatters()
        updateTitle()
    }

    /// Shows `title` as a text button at the trailing edge in place of the right buttons; nil removes it.
    func setTextAction(_ title: String?, action: (() -> Void)?) {
        textAction = title == nil ? nil : action
        textActionButton.setTitle(title, for: .normal)
        textActionButton.isHidden = title == nil
        rightButton.isHidden = title != nil || doneAction != nil
        refreshPlatters()
    }

    /// Moves back and the icon buttons between the row and iPhone Duo's strip, as the system's bar does, and keeps the
    /// row clear of the status island.
    func applyIPhoneDuoLayout(_ layout: IPhoneDuoLayout?) {
        let inset = layout?.trailingButtonsInset(rowTop: safeAreaInsets.top) ?? 0
        // The system's bar keeps a text button against the band beside its vertical bar.
        trailingEdgeConstraint.constant = layout?.sideColumn == nil ? -TelegramGlassPlatter.edgeInset - inset : 0
        searchTrailingConstraint.constant = -inset
        guard layout != appliedDuoLayout else { return }
        let hadColumn = appliedDuoLayout?.sideColumn != nil
        appliedDuoLayout = layout
        let columnPlatters = [leadingPlatter, trailingPlatter, secondaryTrailingPlatter, proxyPlatter]
        if let column = layout?.sideColumn {
            if !hadColumn {
                NSLayoutConstraint.deactivate(leadingRowConstraints)
                titleLeadingRowConstraint?.isActive = false
                for platter in columnPlatters {
                    platter.isInSideColumn = true
                    columnStack.addArrangedSubview(platter)
                }
                columnStack.isHidden = false
                titleLeadingColumnConstraint.isActive = true
            }
            if let superview, columnStack.superview !== superview {
                superview.insertSubview(columnStack, aboveSubview: self)
                let x = columnStack.leadingAnchor.constraint(equalTo: superview.leadingAnchor)
                let y = columnStack.topAnchor.constraint(equalTo: superview.topAnchor)
                NSLayoutConstraint.activate([
                    x, y,
                    columnStack.widthAnchor.constraint(equalToConstant: IPhoneDuoLayout.Metrics.columnWidth),
                ])
                columnXConstraint = x
                columnYConstraint = y
            }
            columnXConstraint?.constant = column.x
            columnYConstraint?.constant = column.minY
        } else if hadColumn {
            for platter in columnPlatters {
                platter.isInSideColumn = false
            }
            columnStack.isHidden = true
            titleLeadingColumnConstraint.isActive = false
            addSubview(leadingPlatter)
            activateLeadingRowConstraints()
            for (index, platter) in [proxyPlatter, secondaryTrailingPlatter, trailingPlatter].enumerated() {
                trailingStack.insertArrangedSubview(platter, at: index)
            }
        }
    }

    private func refreshPlatters() {
        for platter in allPlatters {
            platter.refresh()
        }
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

    private func activateLeadingRowConstraints() {
        leadingRowConstraints = [
            leadingPlatter.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: TelegramGlassPlatter.edgeInset,
            ),
            leadingPlatter.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
        ]
        let titleLeading = titleControl.leadingAnchor.constraint(
            greaterThanOrEqualTo: leadingPlatter.trailingAnchor,
            constant: 8,
        )
        titleLeadingRowConstraint = titleLeading
        NSLayoutConstraint.activate(leadingRowConstraints + [titleLeading])
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        searchClipView.translatesAutoresizingMaskIntoConstraints = false
        searchClipView.clipsToBounds = true
        addSubview(searchClipView)

        if showsBackButton {
            leftButton.accessibilityLabel = L10n.telegram("Common.Back")
            let backHold = UILongPressGestureRecognizer(target: self, action: #selector(backLongPressed(_:)))
            backHold.minimumPressDuration = 0.4
            leftButton.addGestureRecognizer(backHold)
        }
        leftButton.addTarget(self, action: #selector(leftPressed), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(rightPressed), for: .touchUpInside)
        secondaryRightButton.addTarget(self, action: #selector(secondaryRightPressed), for: .touchUpInside)
        proxyButton.isHidden = true
        proxyButton.addAction(UIAction { [weak self] _ in self?.onProxyTap?() }, for: .touchUpInside)
        // UIKit's Done is a prominent item: a pill of the tint color with white text.
        doneButton.tintColor = .white
        doneButton.setTitle(L10n.telegram("Common.Done"), for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.isHidden = true
        doneButton.addAction(UIAction { [weak self] _ in self?.doneAction?() }, for: .touchUpInside)
        textActionButton.tintColor = .label
        textActionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        textActionButton.isHidden = true
        textActionButton.addAction(UIAction { [weak self] _ in self?.textAction?() }, for: .touchUpInside)
        leadingPlatter.setItems([leftButton])
        trailingPlatter.setItems([rightButton])
        rightButton.addGestureRecognizer(rightLongPress)
        secondaryTrailingPlatter.setItems([secondaryRightButton])
        proxyPlatter.setItems([proxyButton])
        doneButtonPlatter.setItems([doneButton])
        let prominent = UIGlassEffect(style: .regular)
        prominent.isInteractive = true
        prominent.tintColor = .systemBlue
        doneButtonPlatter.glassView.effect = prominent
        textActionPlatter.setItems([textActionButton])
        leadingPlatter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leadingPlatter)
        trailingStack.axis = .horizontal
        trailingStack.spacing = TelegramGlassPlatter.interSectionSpacing
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        for platter in [proxyPlatter, secondaryTrailingPlatter, trailingPlatter, textActionPlatter, doneButtonPlatter] {
            trailingStack.addArrangedSubview(platter)
        }
        addSubview(trailingStack)
        columnStack.axis = .vertical
        columnStack.spacing = IPhoneDuoLayout.Metrics.columnSpacing
        columnStack.alignment = .fill
        columnStack.translatesAutoresizingMaskIntoConstraints = false
        columnStack.isHidden = true

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
        searchClipView.addSubview(searchView)

        searchTopConstraint = searchView.topAnchor.constraint(
            equalTo: safeAreaLayoutGuide.topAnchor,
            constant: Self.titleHeight,
        )
        let edge = TelegramGlassPlatter.edgeInset
        trailingEdgeConstraint = trailingStack.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -edge,
        )
        searchTrailingConstraint = searchView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
        titleLeadingColumnConstraint = titleControl.leadingAnchor.constraint(
            greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
            constant: edge,
        )
        activateLeadingRowConstraints()
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchClipView.topAnchor.constraint(equalTo: topAnchor),
            searchClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchClipView.bottomAnchor.constraint(equalTo: bottomAnchor),

            trailingEdgeConstraint,
            trailingStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            // Centered 12 pt before the title's text.
            lockButton.centerXAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -12),
            lockButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: 28),
            lockButton.heightAnchor.constraint(equalToConstant: 32),

            titleControl.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingStack.leadingAnchor,
                constant: -8,
            ),
            // Over the list: beside iPhone Duo's strip that isn't the screen's middle.
            titleControl.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            titleControl.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            titleControl.heightAnchor.constraint(equalToConstant: Self.titleHeight),
            titleStack.leadingAnchor.constraint(equalTo: titleControl.leadingAnchor),
            titleStack.trailingAnchor.constraint(equalTo: titleControl.trailingAnchor),
            titleStack.centerYAnchor.constraint(equalTo: titleControl.centerYAnchor),
            networkActivityContainer.widthAnchor.constraint(equalToConstant: 22),
            networkActivityContainer.heightAnchor.constraint(equalToConstant: 22),
            networkActivityIndicator.centerXAnchor.constraint(equalTo: networkActivityContainer.centerXAnchor),
            networkActivityIndicator.centerYAnchor.constraint(equalTo: networkActivityContainer.centerYAnchor),

            searchTopConstraint,
            searchView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            searchTrailingConstraint,
            searchView.heightAnchor.constraint(equalToConstant: ChatListNavigationSearchView.contentHeight),
        ])
        refreshPlatters()
    }

    @objc private func leftPressed() { leftAction?() }

    /// UIKit's back button menu: holding Back lists the screens under this one.
    @objc private func backLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !leftButton.isHidden else { return }
        leftButton.cancelTracking(with: nil)
        presentTelegramBackMenu(from: leadingPlatter, tracking: gesture)
    }

    @objc private func rightPressed() { rightAction?() }

    @objc private func rightLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // The press must not end as a tap that opens Settings too.
        rightButton.cancelTracking(with: nil)
        onRightLongPress?(trailingPlatter, recognizer)
    }

    @objc private func secondaryRightPressed() { secondaryRightAction?() }
    @objc private func titlePressed() { onTitleTap?() }

    private func setSearchActive(_ active: Bool) {
        let parentView = superview
        parentView?.layoutIfNeeded()
        if active {
            currentOverscroll = 0
            searchTopConstraint.constant = Self.titleHeight
        }
        onVisibleHeightChange?(active
            ? ChatListNavigationSearchView.contentHeight
            : Self.visibleHeight(clipped: currentScrollOffset) + currentOverscroll)
        onSearchActiveChange?(active)
        // The bar clips its collapsing field; an open search's glass swells past the bar's edge under the finger.
        if active { searchClipView.clipsToBounds = false }

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
        ) {
            self.titleControl.alpha = active ? 0 : 1
            self.lockButton.alpha = active ? 0 : 1
            self.leadingPlatter.alpha = active ? 0 : 1
            self.trailingStack.alpha = active ? 0 : 1
            self.columnStack.alpha = active ? 0 : 1
            self.searchView.transform = active
                ? CGAffineTransform(translationX: 0, y: -Self.titleHeight)
                : .identity
            parentView?.layoutIfNeeded()
        } completion: { _ in
            if !self.isSearchActive { self.searchClipView.clipsToBounds = true }
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

    static let contentHeight = TelegramGlassPlatter.height + TelegramGlassPlatter.barBottomInset
    /// The avatar inside its 44 pt glass circle.
    static let avatarSide: CGFloat = 38

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

    private let blurView = TelegramBarBackgroundView(edge: .top)
    private let backButton = UIButton.telegramGlassIcon(UIImage(systemName: "chevron.left"))
    /// The back button's circle, the title's pill and the avatar's circle, as Telegram 13's glass chat header.
    private let leadingPlatter = TelegramGlassPlatter(role: .leading)
    private let titlePlatter = TelegramGlassPlatter(role: .title)
    private let trailingPlatter = TelegramGlassPlatter(role: .trailing(0))
    private let selectionCancelPlatter = TelegramGlassPlatter(role: .trailing(0))
    private let rowGlassContainer: UIVisualEffectView = {
        let effect = UIGlassContainerEffect()
        effect.spacing = TelegramGlassPlatter.interSectionSpacing
        return UIVisualEffectView(effect: effect)
    }()

    private let titleControl = TelegramNavigationTitleControl()
    private let titleStack = UIStackView()
    /// ChatTitleView's title line: the lock and the title, the status icon 3 pt after it, then the credibility badge
    /// and the speaker, which stay whole while the title truncates.
    private let titleRow = UIStackView()
    private let titleLabel = UILabel()
    private let titleStatusView = PeerEmojiStatusView()
    private let titleTrailingLabel = UILabel()
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
    private var avatarSlotView: UIView?
    private let searchField = ChatSearchTextField()
    /// ChatSearchNavigationContentNode: the chat list's glass field and close button in place of the bar's row.
    private lazy var searchView = ChatListNavigationSearchView(
        placeholder: L10n.telegram("Conversation.SearchPlaceholder"),
        field: searchField,
    )
    private var searchMemberScope = SearchMemberScope.none
    private var defaultSearchLeftView: UIView?
    private let searchMemberPrefixLabel = UILabel()
    private let selectionCancelButton = UIButton(type: .system)
    private var searchActive = false
    private var selectionCount: Int?
    private var backButtonExplicitlyHidden = false
    private var regularTitleLeadingConstraint: NSLayoutConstraint!
    private var regularTitleTrailingConstraint: NSLayoutConstraint!
    private var selectionTitleLeadingConstraint: NSLayoutConstraint!
    private var selectionTitleTrailingConstraint: NSLayoutConstraint!
    private var trailingEdgeConstraint: NSLayoutConstraint!
    private var selectionCancelEdgeConstraint: NSLayoutConstraint!
    private var searchTrailingConstraint: NSLayoutConstraint!
    private var configuredTitle = ""
    private var configuredStatus = ""
    private var configuredStatusColor = UIColor.secondaryLabel
    private var configuredActivity: ChatActivityIndicatorView.Kind?
    /// How the title's glass clipped before a chat preview's title travelled out of it.
    private var clippingBeforeExpansion: [(view: UIView, clips: Bool)]?

    /// The bar keeps its height while searching: the field takes the row's place.
    var visibleContentHeight: CGFloat { Self.contentHeight }

    /// The bar's glass platters for the push and pop morph, leading first.
    var glassPlatters: [TelegramGlassPlatter] {
        [leadingPlatter, titlePlatter, trailingPlatter, selectionCancelPlatter].filter { !$0.isHidden }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        // A chat keeps its bar in the row beside iPhone Duo's strip, as the side column would have to leave it as the
        // keyboard rises; the row only keeps clear of the status island.
        let inset = superview?.iPhoneDuoLayout?.trailingButtonsInset(rowTop: safeAreaInsets.top) ?? 0
        trailingEdgeConstraint.constant = -TelegramGlassPlatter.edgeInset - inset
        selectionCancelEdgeConstraint.constant = -TelegramGlassPlatter.edgeInset - inset
        searchTrailingConstraint.constant = -inset
        super.layoutSubviews()
    }

    /// The title with the lock 6 pt before it.
    private static func decoratedTitle(
        _ title: String,
        lock: Bool,
        font: UIFont,
        color: UIColor,
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if lock {
            result.append(titleIcon("lock.fill", pointSize: font.pointSize * 0.62, tint: color, font: font))
            result.append(titleGap(4, font: font))
        }
        result.append(NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color]))
        return result
    }

    /// The credibility badge after the title and the speaker 3 pt after both.
    private static func titleTrailing(badge: PeerCredibilityBadge?, mute: Bool, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let badge { result.append(badge.attributedSuffix(font: font)) }
        if mute {
            result.append(titleGap(2, font: font))
            result.append(titleIcon(
                "speaker.slash.fill",
                pointSize: font.pointSize * 0.55,
                tint: .secondaryLabel,
                font: font,
            ))
        }
        return result
    }

    private static func titleGap(_ width: CGFloat, font: UIFont) -> NSAttributedString {
        NSAttributedString(string: "\u{200A}", attributes: [.font: font, .kern: width])
    }

    private static func titleIcon(
        _ name: String,
        pointSize: CGFloat,
        tint: UIColor,
        font: UIFont,
    ) -> NSAttributedString {
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

    /// ChatTitleView's emoji status (or Premium star) after the title; selection titles go without it.
    func setTitleStatus(_ status: PeerEmojiStatus?, client: TDLibClient?) {
        titleStatusView.configure(status, client: client)
        titleStatusView.isHidden = status == nil || selectionCount != nil
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
            refreshPlatters()
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
            refreshPlatters()
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

    /// Calls `ready` once the header shows what it will, for a chat that waits to be shown ready: the title's emoji
    /// status and the avatar's photo.
    func whenContentShown(_ ready: @escaping () -> Void) {
        let group = DispatchGroup()
        group.enter()
        titleStatusView.whenShown { group.leave() }
        group.enter()
        avatarView.whenImageShown { group.leave() }
        group.notify(queue: .main, execute: ready)
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
            searchView.setPlaceholder(L10n.telegram("Conversation.SearchPlaceholder"))
        case .choosing:
            searchField.tokens = []
            searchMemberPrefixLabel.sizeToFit()
            searchField.leftView = searchMemberPrefixLabel
            searchView.setPlaceholder(L10n.telegram("Conversation.SearchByName.Placeholder"))
        case .chosen(let title):
            searchField.leftView = defaultSearchLeftView
            searchView.setPlaceholder("")
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
        refreshPlatters()
    }

    func setBackButtonHidden(_ hidden: Bool) {
        backButtonExplicitlyHidden = hidden
        if selectionCount == nil {
            backButton.isHidden = hidden
            refreshPlatters()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc func beginSearch() {
        guard !searchActive, selectionCount == nil else { return }
        searchActive = true
        searchField.textColor = .label
        onSearchActiveChange?(true)
        // The title's pill becomes the field and the avatar's circle the close button, while Back dematerializes.
        let row = rowGlassShapes()
        searchView.setPresented(true)
        let search = searchView.glassShapes(in: self)
        searchField.becomeFirstResponder()
        TelegramGlassInPlaceMorph.run(in: self, shapes: [
            .init(from: row.title?.frame, fromItems: row.title?.items, to: search[0].frame, toItems: search[0].items),
            .init(
                from: row.trailing?.frame,
                fromItems: row.trailing?.items,
                to: search[1].frame,
                toItems: search[1].items,
            ),
            .init(from: row.leading?.frame, fromItems: row.leading?.items),
        ], spacing: TelegramGlassPlatter.interSectionSpacing, handOver: { [weak self] in
            self?.setRowGlassHidden(true)
            self?.searchView.setGlassHidden(true)
        }, completion: { [weak self] in
            self?.searchView.setGlassHidden(false)
        })
    }

    /// The row's glass pills that show, in the bar's coordinates, with their items for the search morph to borrow.
    private func rowGlassShapes() -> (
        leading: (frame: CGRect, items: TelegramGlassLoan)?,
        title: (frame: CGRect, items: TelegramGlassLoan)?,
        trailing: (frame: CGRect, items: TelegramGlassLoan)?,
    ) {
        layoutIfNeeded()
        func shape(of platter: TelegramGlassPlatter) -> (frame: CGRect, items: TelegramGlassLoan)? {
            guard !platter.isHidden, platter.hasVisibleItems else { return nil }
            return (platter.convert(platter.bounds, to: self), TelegramGlassLoan(platter: platter))
        }
        return (shape(of: leadingPlatter), shape(of: titlePlatter), shape(of: trailingPlatter))
    }

    /// The row's glass gives its place to the search's, which the morph draws meanwhile; hiding, not fading, as a glass
    /// view's opacity must not change.
    private func setRowGlassHidden(_ hidden: Bool) {
        for platter in [leadingPlatter, titlePlatter, trailingPlatter] {
            platter.glassView.isHidden = hidden
            platter.isUserInteractionEnabled = !hidden
        }
    }

    private func refreshPlatters() {
        avatarSlotView?.isHidden = avatarView.isHidden
        for platter in [leadingPlatter, trailingPlatter, selectionCancelPlatter] {
            platter.refresh()
        }
        titlePlatter.isHidden = false
    }

    private func applyTitle(
        title: String,
        status: String,
        statusColor: UIColor,
        activity: ChatActivityIndicatorView.Kind? = nil,
    ) {
        let decorated = selectionCount == nil
        if decorated, titleBadge != nil || titleIcons != TitleIcons() {
            titleLabel.attributedText = Self.decoratedTitle(
                title,
                lock: titleIcons.lock,
                font: titleLabel.font,
                color: titleLabel.textColor ?? .label,
            )
            titleTrailingLabel.attributedText = Self.titleTrailing(
                badge: titleBadge,
                mute: titleIcons.mute,
                font: titleLabel.font,
            )
        } else {
            titleLabel.text = title
            titleTrailingLabel.attributedText = nil
        }
        titleTrailingLabel.isHidden = titleTrailingLabel.attributedText?.length ?? 0 == 0
        titleStatusView.isHidden = !decorated || titleStatusView.status == nil
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
        // Glass swells past its pill under the finger, past the bar's edge for a button on the row; the bar does not
        // clip it, and the chat keeps the bar above the banners under it.
        clipsToBounds = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        backButton.accessibilityLabel = L10n.telegram("Common.Back")
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        let backHold = UILongPressGestureRecognizer(target: self, action: #selector(backLongPressed(_:)))
        backHold.minimumPressDuration = 0.4
        backButton.addGestureRecognizer(backHold)
        leadingPlatter.setItems([backButton])

        titleControl.translatesAutoresizingMaskIntoConstraints = false
        titleControl.accessibilityHint = L10n.betterTG("Accessibility.OpenProfileHint")
        titleControl.accessibilityTraits = .button
        titleControl.addTarget(self, action: #selector(profilePressed), for: .touchUpInside)
        titleControl.addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(titleLongPressed(_:))),
        )
        titlePlatter.glassView.contentView.addSubview(titleControl)
        titlePlatter.customContent = titleControl

        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh - 1, for: .horizontal)
        titleTrailingLabel.font = titleLabel.font
        titleTrailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleTrailingLabel.isHidden = true
        titleStatusView.isHidden = true
        titleStatusView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleStatusView.widthAnchor.constraint(equalToConstant: titleStatusView.side),
            titleStatusView.heightAnchor.constraint(equalToConstant: titleStatusView.side),
        ])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(titleStatusView)
        titleRow.addArrangedSubview(titleTrailingLabel)
        titleRow.setCustomSpacing(3, after: titleLabel)
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        titleStack.addArrangedSubview(titleRow)
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

        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profilePressed)))
        let avatarSlot = UIView()
        avatarSlot.addSubview(avatarView)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.centerXAnchor.constraint(equalTo: avatarSlot.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: avatarSlot.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: Self.avatarSide),
            avatarView.heightAnchor.constraint(equalToConstant: Self.avatarSide),
            avatarSlot.widthAnchor.constraint(equalToConstant: TelegramGlassPlatter.iconWidth),
        ])
        avatarSlotView = avatarSlot

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.setPreferredSymbolConfiguration(UIButton.telegramGlassIconConfiguration, forImageIn: .normal)
        moreButton.tintColor = .label
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.isHidden = true
        moreButton.addTarget(self, action: #selector(morePressed), for: .touchUpInside)
        trailingPlatter.setItems([avatarSlot, moreButton])

        searchView.translatesAutoresizingMaskIntoConstraints = false
        searchView.followsFocus = false
        searchView.onClose = { [weak self] in self?.endSearch() }
        searchView.isHidden = true
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
        addSubview(searchView)

        selectionCancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        selectionCancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        selectionCancelButton.tintColor = .label
        selectionCancelButton.accessibilityLabel = L10n.betterTG("Accessibility.CancelSelection")
        selectionCancelButton.isHidden = true
        selectionCancelButton.addTarget(self, action: #selector(selectionCancelPressed), for: .touchUpInside)
        selectionCancelPlatter.setItems([selectionCancelButton])

        // The row's glass in one container, as UIKit groups a bar's glass, which the search morph draws alike.
        rowGlassContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowGlassContainer)
        NSLayoutConstraint.activate([
            rowGlassContainer.topAnchor.constraint(equalTo: topAnchor),
            rowGlassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowGlassContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowGlassContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for platter in [leadingPlatter, titlePlatter, trailingPlatter, selectionCancelPlatter] {
            platter.translatesAutoresizingMaskIntoConstraints = false
            rowGlassContainer.contentView.addSubview(platter)
        }
        // The search covers the row while it is open.
        bringSubviewToFront(searchView)
        // The title pill hugs the title, at least ChatTitleComponent's 150 pt of content wide so that a short name does
        // not shrink it, and stays centred while it fits between the buttons.
        let titleEnd = TelegramGlassPlatter.titleInset
        let minimumTitleWidth = titleStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        minimumTitleWidth.priority = .defaultHigh + 1
        regularTitleLeadingConstraint = titlePlatter.leadingAnchor.constraint(
            greaterThanOrEqualTo: leadingPlatter.trailingAnchor,
            constant: TelegramGlassPlatter.interSectionSpacing,
        )
        regularTitleTrailingConstraint = titlePlatter.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingPlatter.leadingAnchor,
            constant: -TelegramGlassPlatter.interSectionSpacing,
        )
        selectionTitleLeadingConstraint = titlePlatter.leadingAnchor.constraint(
            greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
            constant: 80,
        )
        selectionTitleTrailingConstraint = titlePlatter.trailingAnchor.constraint(
            lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -80,
        )
        let titleCentre = titlePlatter.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        titleCentre.priority = .defaultHigh
        trailingEdgeConstraint = trailingPlatter.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -TelegramGlassPlatter.edgeInset,
        )
        selectionCancelEdgeConstraint = selectionCancelPlatter.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -TelegramGlassPlatter.edgeInset,
        )
        searchTrailingConstraint = searchView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leadingPlatter.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: TelegramGlassPlatter.edgeInset,
            ),
            leadingPlatter.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            trailingEdgeConstraint,
            trailingPlatter.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            selectionCancelEdgeConstraint,
            selectionCancelPlatter.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),

            regularTitleLeadingConstraint,
            regularTitleTrailingConstraint,
            titleCentre,
            minimumTitleWidth,
            titlePlatter.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            titleControl.topAnchor.constraint(equalTo: titlePlatter.glassView.contentView.topAnchor),
            titleControl.bottomAnchor.constraint(equalTo: titlePlatter.glassView.contentView.bottomAnchor),
            titleControl.leadingAnchor.constraint(equalTo: titlePlatter.glassView.contentView.leadingAnchor),
            titleControl.trailingAnchor.constraint(equalTo: titlePlatter.glassView.contentView.trailingAnchor),
            titleStack.leadingAnchor.constraint(equalTo: titleControl.leadingAnchor, constant: titleEnd),
            titleStack.trailingAnchor.constraint(equalTo: titleControl.trailingAnchor, constant: -titleEnd),
            titleStack.centerYAnchor.constraint(equalTo: titleControl.centerYAnchor),

            // The field and its close button on the row the buttons leave.
            searchView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            searchTrailingConstraint,
            searchView.centerYAnchor.constraint(equalTo: leadingPlatter.centerYAnchor),
            searchView.heightAnchor.constraint(equalToConstant: ChatListNavigationSearchView.contentHeight),
        ])
        refreshPlatters()
    }

    @objc private func backPressed() {
        onBack?()
    }

    /// UIKit's back button menu: holding Back lists the screens under the chat. A chat shown outside the navigation
    /// stack (a preview, a sheet) has no Back to hold.
    @objc private func backLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, onBack != nil, !backButton.isHidden else { return }
        backButton.cancelTracking(with: nil)
        presentTelegramBackMenu(from: leadingPlatter, tracking: gesture)
    }

    @objc private func profilePressed() {
        onProfile?()
    }

    @objc private func morePressed() {
        // A menu opened from a pill morphs the whole pill (Telegram 528c8e5e79).
        onMore?(trailingPlatter)
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
        // The reverse of the opening: the field becomes the title's pill and the close button the avatar's circle.
        let search = searchView.glassShapes(in: self)
        let row = rowGlassShapes()
        TelegramGlassInPlaceMorph.run(in: self, shapes: [
            .init(from: search[0].frame, fromItems: search[0].items, to: row.title?.frame, toItems: row.title?.items),
            .init(
                from: search[1].frame,
                fromItems: search[1].items,
                to: row.trailing?.frame,
                toItems: row.trailing?.items,
            ),
            .init(to: row.leading?.frame, toItems: row.leading?.items),
        ], spacing: TelegramGlassPlatter.interSectionSpacing, handOver: { [weak self] in
            self?.searchView.setGlassHidden(true)
        }, completion: { [weak self] in
            guard let self else { return }
            searchView.setPresented(false)
            searchView.setGlassHidden(false)
            setRowGlassHidden(false)
        })
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

// MARK: - TelegramListNavigationBar + TelegramContextExpansionHeader

extension TelegramListNavigationBar: TelegramContextExpansionHeader {
    var contextExpansionTitle: UIView { titleLabel }
    var contextExpansionTitleLabel: UILabel { titleLabel }
    var contextExpansionFadingViews: [UIView] { [subtitleLabel] + glassPlatters.flatMap(\.visibleItems) }

    func insertContextExpansionBackdrop(_ backdrop: UIView) {
        insertSubview(backdrop, aboveSubview: blurView)
    }

    /// The row's picture reaches past the bar while the title travels.
    func setContextExpansionTraveling(_ traveling: Bool) {
        if traveling {
            guard clipsBeforeExpansion == nil else { return }
            clipsBeforeExpansion = clipsToBounds
            clipsToBounds = false
        } else if let clips = clipsBeforeExpansion {
            clipsToBounds = clips
            clipsBeforeExpansion = nil
        }
    }

    func setContextExpansionCollapsed(_ collapsed: Bool) {
        for platter in glassPlatters {
            platter.setGlassMaterialized(!collapsed)
        }
    }
}

// MARK: - TelegramChatNavigationBar + TelegramContextExpansionHeader

extension TelegramChatNavigationBar: TelegramContextExpansionHeader {
    var contextExpansionTitle: UIView { titleRow }
    var contextExpansionTitleLabel: UILabel { titleLabel }
    var contextExpansionFadingViews: [UIView] { [statusRow] + trailingPlatter.visibleItems }

    func insertContextExpansionBackdrop(_ backdrop: UIView) {
        insertSubview(backdrop, belowSubview: rowGlassContainer)
    }

    /// The title travels out of its pill: the pill and the row's glass let it out while it does.
    func setContextExpansionTraveling(_ traveling: Bool) {
        if traveling {
            guard clippingBeforeExpansion == nil else { return }
            let views: [UIView] = [
                rowGlassContainer,
                rowGlassContainer.contentView,
                titlePlatter,
                titlePlatter.glassView,
                titlePlatter.glassView.contentView,
            ]
            clippingBeforeExpansion = views.map { ($0, $0.clipsToBounds) }
            views.forEach { $0.clipsToBounds = false }
        } else if let clipping = clippingBeforeExpansion {
            clipping.forEach { $0.view.clipsToBounds = $0.clips }
            clippingBeforeExpansion = nil
        }
    }

    /// The title's and the avatar's glass materialize, and the avatar grows in where it is.
    func setContextExpansionCollapsed(_ collapsed: Bool) {
        titlePlatter.setGlassMaterialized(!collapsed)
        trailingPlatter.setGlassMaterialized(!collapsed)
        trailingPlatter.transform = collapsed ? CGAffineTransform(scaleX: 0.5, y: 0.5) : .identity
    }
}
