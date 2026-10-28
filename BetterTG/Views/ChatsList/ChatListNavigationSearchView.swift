// ChatListNavigationSearchView.swift

import UIKit

/// Telegram-style search content embedded into the app's custom navigation chrome: NavigationBarSearchContentNode's
/// 44 pt glass field, 8 pt below the bar's row and 8 pt above its edge (`navigationBarSearchContentHeight` 60).
final class ChatListNavigationSearchView: UIView, UITextFieldDelegate {
    // MARK: Internal

    static let fieldHeight: CGFloat = 44
    static let verticalInset: CGFloat = 8
    static let scrollHeight = fieldHeight + verticalInset * 2

    var onQueryChange: ((String) -> Void)?
    var onActiveChange: ((Bool) -> Void)?

    // MARK: Private

    private let searchField = UISearchTextField()
    private let glassView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        view.isUserInteractionEnabled = false
        return view
    }()

    private let closeButton = UIButton(type: .system)
    private var placeholder: String
    private var closeWidthConstraint: NSLayoutConstraint!
    private var searchHeightConstraint: NSLayoutConstraint!
    private var searchCenterYConstraint: NSLayoutConstraint!
    private var requestedScrollOffset = CGFloat.zero
    private var lastContentAlpha: CGFloat = 1
    /// The alpha the text colours and placeholder were last built with.
    private var appliedTextAlpha: CGFloat?

    var isActive: Bool { searchField.isFirstResponder }
    var hasMarkedText: Bool { searchField.markedTextRange != nil }
    #if DEBUG
    var probeField: UISearchTextField { searchField }
    #endif

    init(placeholder: String = L10n.telegram("DialogList.SearchLabel")) {
        self.placeholder = placeholder
        super.init(frame: .zero)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        searchField.layer.cornerRadius = searchField.bounds.height / 2
        updateSearchContentAlpha(lastContentAlpha)
    }

    func applyScroll(offset: CGFloat, animated: Bool = false) {
        requestedScrollOffset = min(max(0, offset), Self.scrollHeight)
        guard !isActive else { return }
        let appliedOffset = requestedScrollOffset
        let fraction = appliedOffset / Self.scrollHeight
        let fieldHeight = Self.fieldHeight * (1 - fraction)
        let contentAlpha = min(1, max(0, (fieldHeight - (Self.fieldHeight - 8)) / 8))
        let capsuleAlpha = min(1, max(0, fieldHeight / 10))
        let changes = {
            self.searchHeightConstraint.constant = max(0.01, fieldHeight)
            // The field stays centred in the part of the row the collapsing bar still shows.
            self.searchCenterYConstraint.constant = -appliedOffset / 2
            self.searchField.alpha = capsuleAlpha
            self.glassView.isHidden = fieldHeight < 2
            self.lastContentAlpha = contentAlpha
            self.updateSearchContentAlpha(contentAlpha)
            self.isUserInteractionEnabled = self.isActive || fieldHeight > 12
        }
        guard animated else {
            // The frame's layout pass applies the constraints; forcing it on every scroll event cost frames.
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            changes()
            self.layoutIfNeeded()
        }
    }

    func setPlaceholder(_ value: String) {
        guard placeholder != value else { return }
        placeholder = value
        searchField.placeholder = value
        appliedTextAlpha = nil
        updateSearchContentAlpha(lastContentAlpha)
    }

    func focus() {
        searchField.becomeFirstResponder()
    }

    func restoreQuery(_ query: String) {
        searchField.text = query
    }

    /// Ends the search as the close button does.
    func endSearch() {
        closeSearch()
    }

    func textFieldDidBeginEditing(_: UITextField) {
        setActive(true)
    }

    func textFieldDidEndEditing(_: UITextField) {
        setActive(false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func configureViews() {
        clipsToBounds = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = placeholder
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.borderStyle = .none
        searchField.backgroundColor = .clear
        searchField.layer.cornerCurve = .continuous
        searchField.clipsToBounds = true
        searchField.textColor = .label
        searchField.tintColor = .systemBlue
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        addSubview(searchField)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = L10n.betterTG("Accessibility.CloseSearch")
        closeButton.alpha = 0
        closeButton.transform = CGAffineTransform(translationX: 60, y: 0)
        closeButton.addTarget(self, action: #selector(closeSearch), for: .touchUpInside)
        addSubview(closeButton)

        closeWidthConstraint = closeButton.widthAnchor.constraint(equalToConstant: 0)
        searchHeightConstraint = searchField.heightAnchor.constraint(equalToConstant: Self.fieldHeight)
        searchCenterYConstraint = searchField.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TelegramGlassPlatter.edgeInset),
            closeButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
            closeWidthConstraint,
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TelegramGlassPlatter.edgeInset),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            searchCenterYConstraint,
            searchHeightConstraint,
            glassView.topAnchor.constraint(equalTo: searchField.topAnchor),
            glassView.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: searchField.bottomAnchor),
        ])
    }

    private func setActive(_ active: Bool) {
        layoutIfNeeded()
        onActiveChange?(active)
        closeWidthConstraint.constant = active ? Self.fieldHeight : 0
        if active {
            searchHeightConstraint.constant = Self.fieldHeight
            searchCenterYConstraint.constant = 0
            searchField.alpha = 1
            glassView.isHidden = false
            lastContentAlpha = 1
            updateSearchContentAlpha(1)
            isUserInteractionEnabled = true
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.closeButton.alpha = active ? 1 : 0
            self.closeButton.transform = active
                ? .identity
                : CGAffineTransform(translationX: 60, y: 0)
            self.layoutIfNeeded()
        } completion: { _ in
            if !active {
                self.applyScroll(offset: self.requestedScrollOffset, animated: true)
            }
        }
    }

    private func updateSearchContentAlpha(_ alpha: CGFloat) {
        searchField.leftView?.alpha = alpha
        // The colours and placeholder change only with the alpha; rebuilding them on every scroll step cost frames.
        guard alpha != appliedTextAlpha else { return }
        appliedTextAlpha = alpha
        searchField.textColor = UIColor.label.withAlphaComponent(alpha)
        searchField.tintColor = UIColor.systemBlue.withAlphaComponent(alpha)
        searchField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.placeholderText.withAlphaComponent(alpha)],
        )
    }

    @objc private func queryChanged() {
        onQueryChange?(searchField.text ?? "")
    }

    @objc private func closeSearch() {
        searchField.text = ""
        onQueryChange?("")
        searchField.resignFirstResponder()
    }
}
