// TelegramNavigationBar.swift

import TDLibKit
import UIKit

final class TelegramListNavigationBar: UIView {
    static let titleHeight: CGFloat = 44
    static let expandedContentHeight = titleHeight + ChatListNavigationSearchView.scrollHeight

    var onQueryChange: ((String) -> Void)? {
        didSet { searchView.onQueryChange = onQueryChange }
    }
    var onSearchActiveChange: ((Bool) -> Void)?
    var onVisibleHeightChange: ((CGFloat) -> Void)?

    init(
        title: String,
        placeholder: String,
        leftImage: UIImage?,
        rightImage: UIImage?,
        leftAction: (() -> Void)?,
        rightAction: (() -> Void)?
    ) {
        searchView = ChatListNavigationSearchView(placeholder: placeholder)
        self.leftAction = leftAction
        self.rightAction = rightAction
        super.init(frame: .zero)
        titleLabel.text = title
        leftButton.setImage(leftImage, for: .normal)
        rightButton.setImage(rightImage, for: .normal)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isSearchActive: Bool { searchView.isActive }

    func applyScroll(offset: CGFloat, animated: Bool = false) {
        let clipped = min(max(0, offset), ChatListNavigationSearchView.scrollHeight)
        currentScrollOffset = clipped
        guard !isSearchActive else {
            searchView.applyScroll(offset: clipped, animated: false)
            onVisibleHeightChange?(Self.titleHeight)
            return
        }
        searchView.applyScroll(offset: clipped, animated: animated)
        onVisibleHeightChange?(Self.expandedContentHeight - clipped)
    }

    func focusSearch() {
        searchView.focus()
    }

    func setLeftButtonHidden(_ hidden: Bool) {
        leftButton.isHidden = hidden
    }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let titleLabel = UILabel()
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    private let searchView: ChatListNavigationSearchView
    private let leftAction: (() -> Void)?
    private let rightAction: (() -> Void)?
    private var currentScrollOffset = CGFloat.zero

    private func configureViews() {
        clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        for button in [leftButton, rightButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .systemBlue
            button.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 18, weight: .medium),
                forImageIn: .normal,
            )
            addSubview(button)
        }
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

            leftButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
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
        onVisibleHeightChange?(active ? Self.titleHeight : Self.expandedContentHeight - currentScrollOffset)
        onSearchActiveChange?(active)

        let titleTranslation = -(safeAreaInsets.top + Self.titleHeight)
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
        ) {
            let titleTransform = active
                ? CGAffineTransform(translationX: 0, y: titleTranslation)
                : .identity
            self.titleLabel.transform = titleTransform
            self.leftButton.transform = titleTransform
            self.rightButton.transform = titleTransform
            self.titleLabel.alpha = active ? 0 : 1
            self.leftButton.alpha = active ? 0 : 1
            self.rightButton.alpha = active ? 0 : 1
            self.searchView.transform = active
                ? CGAffineTransform(translationX: 0, y: -(Self.titleHeight + 4))
                : .identity
            parentView?.layoutIfNeeded()
        }
    }
}

final class TelegramChatNavigationBar: UIView, UITextFieldDelegate {
    static let contentHeight: CGFloat = 44

    var onBack: (() -> Void)?
    var onSearchQueryChange: ((String) -> Void)?
    var onSearchActiveChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, status: String, statusColor: UIColor) {
        titleLabel.text = title
        statusLabel.text = status
        statusLabel.textColor = statusColor
        statusLabel.isHidden = status.isEmpty
    }

    func configureAvatar(file: File?, minithumbnail: Minithumbnail?, title: String, id: Int64) {
        avatarView.configure(file: file, minithumbnail: minithumbnail, title: title, id: id)
    }

    func setSearchResultFound(_ found: Bool?) {
        searchField.textColor = found == false ? .systemRed : .label
    }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let backButton = UIButton(type: .system)
    private let titleStack = UIStackView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let avatarView = ProfileAvatarView()
    private let searchField = UISearchTextField()
    private let closeButton = UIButton(type: .system)
    private var searchActive = false

    private func configureViews() {
        clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        addSubview(backButton)

        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityHint = "Long press to search messages"
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(statusLabel)
        titleStack.isUserInteractionEnabled = true
        titleStack.addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(titleLongPressed(_:))),
        )
        addSubview(titleStack)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarView)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search messages"
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.borderStyle = .none
        searchField.backgroundColor = UIColor(white: 0.13, alpha: 0.96)
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
        closeButton.accessibilityLabel = "Close Search"
        closeButton.alpha = 0
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(endSearch), for: .touchUpInside)
        addSubview(closeButton)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

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

            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 4),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: avatarView.leadingAnchor, constant: -8),
            titleStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleStack.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 38),
            closeButton.heightAnchor.constraint(equalToConstant: 38),
            searchField.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            searchField.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc private func backPressed() { onBack?() }

    @objc private func titleLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        beginSearch()
    }

    @objc private func beginSearch() {
        guard !searchActive else { return }
        searchActive = true
        searchField.isHidden = false
        closeButton.isHidden = false
        searchField.textColor = .label
        onSearchActiveChange?(true)
        searchField.becomeFirstResponder()
        UIView.animate(withDuration: 0.2) {
            self.titleStack.alpha = 0
            self.avatarView.alpha = 0
            self.backButton.alpha = 0
            self.backButton.transform = CGAffineTransform(translationX: -20, y: 0)
            self.searchField.alpha = 1
            self.closeButton.alpha = 1
        }
    }

    @objc private func endSearch() {
        guard searchActive else { return }
        searchActive = false
        searchField.text = ""
        searchField.resignFirstResponder()
        onSearchQueryChange?("")
        onSearchActiveChange?(false)
        UIView.animate(withDuration: 0.2) {
            self.titleStack.alpha = 1
            self.avatarView.alpha = 1
            self.backButton.alpha = 1
            self.backButton.transform = .identity
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
