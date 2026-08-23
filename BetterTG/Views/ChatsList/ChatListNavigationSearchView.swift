// ChatListNavigationSearchView.swift

import UIKit

/// Telegram-style search content embedded into the app's custom navigation chrome.
final class ChatListNavigationSearchView: UIView, UITextFieldDelegate {
    static let scrollHeight: CGFloat = 52

    var onQueryChange: ((String) -> Void)?
    var onActiveChange: ((Bool) -> Void)?

    init(placeholder: String = "Search chats…") {
        self.placeholder = placeholder
        super.init(frame: .zero)
        configureViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        searchField.layer.cornerRadius = searchField.bounds.height / 2
        updateSearchContentAlpha(lastContentAlpha)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isActive: Bool { searchField.isFirstResponder }

    func applyScroll(offset: CGFloat, animated: Bool = false) {
        requestedScrollOffset = min(max(0, offset), Self.scrollHeight)
        guard !isActive else { return }
        let appliedOffset = requestedScrollOffset
        let fraction = appliedOffset / Self.scrollHeight
        let fieldHeight = 36 * (1 - fraction)
        let contentAlpha = min(1, max(0, (fieldHeight - 28) / 8))
        let capsuleAlpha = min(1, max(0, fieldHeight / 10))
        let changes = {
            self.searchHeightConstraint.constant = max(0.01, fieldHeight)
            self.searchCenterYConstraint.constant = -appliedOffset / 2
            self.searchField.alpha = capsuleAlpha
            self.lastContentAlpha = contentAlpha
            self.updateSearchContentAlpha(contentAlpha)
            self.isUserInteractionEnabled = self.isActive || fieldHeight > 12
            self.layoutIfNeeded()
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
    }

    func focus() {
        searchField.becomeFirstResponder()
    }

    private let searchField = UISearchTextField()
    private let closeButton = UIButton(type: .system)
    private let placeholder: String
    private var closeWidthConstraint: NSLayoutConstraint!
    private var searchHeightConstraint: NSLayoutConstraint!
    private var searchCenterYConstraint: NSLayoutConstraint!
    private var requestedScrollOffset = CGFloat.zero
    private var lastContentAlpha: CGFloat = 1

    private func configureViews() {
        clipsToBounds = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = placeholder
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.borderStyle = .none
        searchField.backgroundColor = UIColor(white: 0.13, alpha: 0.96)
        searchField.layer.cornerCurve = .continuous
        searchField.clipsToBounds = true
        searchField.textColor = .label
        searchField.tintColor = .systemBlue
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        addSubview(searchField)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "Close Search"
        closeButton.alpha = 0
        closeButton.transform = CGAffineTransform(translationX: 60, y: 0)
        closeButton.addTarget(self, action: #selector(closeSearch), for: .touchUpInside)
        addSubview(closeButton)

        closeWidthConstraint = closeButton.widthAnchor.constraint(equalToConstant: 0)
        searchHeightConstraint = searchField.heightAnchor.constraint(equalToConstant: 36)
        searchCenterYConstraint = searchField.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            closeWidthConstraint,
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            searchCenterYConstraint,
            searchHeightConstraint,
        ])
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

    private func setActive(_ active: Bool) {
        layoutIfNeeded()
        onActiveChange?(active)
        closeWidthConstraint.constant = active ? 36 : 0
        if active {
            searchHeightConstraint.constant = 36
            searchCenterYConstraint.constant = 0
            searchField.alpha = 1
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
