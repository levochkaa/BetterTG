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

    // MARK: Private

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let titleLabel = UILabel()
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    private let searchView: ChatListNavigationSearchView
    private let leftAction: (() -> Void)?
    private let rightAction: (() -> Void)?
    private let showsBackButton: Bool
    private var currentScrollOffset = CGFloat.zero

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
        showsBackButton: Bool = false,
    ) {
        self.searchView = ChatListNavigationSearchView(placeholder: placeholder)
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.showsBackButton = showsBackButton
        super.init(frame: .zero)
        titleLabel.text = title
        leftButton.setImage(leftImage, for: .normal)
        rightButton.setImage(rightImage, for: .normal)
        configureViews()
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

    private func configureViews() {
        clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        for button in [leftButton, rightButton] {
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

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        addSubview(titleLabel)

        searchView.translatesAutoresizingMaskIntoConstraints = false
        searchView.onActiveChange = { [weak self] active in
            self?.setSearchActive(active)
        }
        addSubview(searchView)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

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

            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightButton.leadingAnchor, constant: -8),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: leftButton.centerYAnchor),

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
            self.titleLabel.alpha = active ? 0 : 1
            self.leftButton.alpha = active ? 0 : 1
            self.rightButton.alpha = active ? 0 : 1
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

    static let contentHeight: CGFloat = 44

    var onBack: (() -> Void)?
    var onSelectionCancel: (() -> Void)?
    var onSearchQueryChange: ((String) -> Void)?
    var onSearchActiveChange: ((Bool) -> Void)?
    var onProfile: (() -> Void)?

    // MARK: Private

    private let separator = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let backButton = UIButton(type: .system)
    private let titleControl = TelegramNavigationTitleControl()
    private let titleStack = UIStackView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let avatarView = ProfileAvatarView()
    private let searchField = UISearchTextField()
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

    func configure(title: String, status: String, statusColor: UIColor) {
        configuredTitle = title
        configuredStatus = status
        configuredStatusColor = statusColor
        guard selectionCount == nil else { return }
        applyTitle(title: title, status: status, statusColor: statusColor)
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
            titleControl.isUserInteractionEnabled = false
            applyTitle(
                title: L10n.telegramPlural("Conversation.SelectedMessagesFormat", count: count)
                    .replacingOccurrences(of: "{}", with: String(count)),
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
            avatarView.isHidden = false
            titleControl.isUserInteractionEnabled = true
            applyTitle(
                title: configuredTitle,
                status: configuredStatus,
                statusColor: configuredStatusColor,
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

    func setSearchResultFound(_ found: Bool?) {
        searchField.textColor = found == false ? .systemRed : .label
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
            self.backButton.alpha = 0
            self.searchField.alpha = 1
            self.closeButton.alpha = 1
        }
    }

    private func applyTitle(title: String, status: String, statusColor: UIColor) {
        titleLabel.text = title
        statusLabel.text = status
        statusLabel.textColor = statusColor
        statusLabel.isHidden = status.isEmpty
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
        titleStack.addArrangedSubview(statusLabel)
        titleStack.isUserInteractionEnabled = false
        titleControl.highlightedContentView = titleStack
        titleControl.addSubview(titleStack)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profilePressed)))
        addSubview(avatarView)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = L10n.telegram("Conversation.ContextMenuSearchMessages")
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
        searchField.text = ""
        searchField.resignFirstResponder()
        onSearchQueryChange?("")
        onSearchActiveChange?(false)
        UIView.animate(withDuration: 0.2) {
            self.titleControl.alpha = 1
            self.avatarView.alpha = 1
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
        onSearchQueryChange?(searchField.text ?? "")
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
