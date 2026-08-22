// ChatListNavigationSearchView.swift

import UIKit

final class ChatListNavigationSearchView: UIView, UITextFieldDelegate {
    static let scrollHeight: CGFloat = 54

    var onQueryChange: ((String) -> Void)?
    var onActiveChange: ((Bool) -> Void)?

    init(placeholder: String = "Search chats…") {
        self.placeholder = placeholder
        super.init(frame: .zero)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isActive: Bool {
        searchField.isFirstResponder
    }

    func applyScroll(offset: CGFloat, animated: Bool = false) {
        requestedScrollOffset = min(max(0, offset), Self.scrollHeight)
        let appliedOffset = isActive ? CGFloat.zero : requestedScrollOffset
        let fraction = appliedOffset / Self.scrollHeight
        let changes = {
            self.transform = CGAffineTransform(translationX: 0, y: -appliedOffset)
            self.searchField.transform = CGAffineTransform(translationX: 0, y: -8 * fraction)
            let contentAlpha = 1 - min(1, max(0, fraction - 0.62) / 0.38)
            self.searchField.alpha = contentAlpha
            self.cancelButton.alpha = (self.isActive ? 1 : 0) * contentAlpha
            self.isUserInteractionEnabled = fraction < 0.98
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

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let searchField = UISearchTextField()
    private let cancelButton = UIButton(type: .system)
    private let placeholder: String
    private var cancelWidthConstraint: NSLayoutConstraint!
    private var requestedScrollOffset = CGFloat.zero

    private func configureViews() {
        clipsToBounds = false

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = placeholder
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.backgroundColor = UIColor.tertiarySystemFill.withAlphaComponent(0.9)
        searchField.textColor = .label
        searchField.tintColor = .systemBlue
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        addSubview(searchField)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.contentHorizontalAlignment = .right
        cancelButton.alpha = 0
        cancelButton.clipsToBounds = true
        cancelButton.addTarget(self, action: #selector(cancelSearch), for: .touchUpInside)
        addSubview(cancelButton)

        cancelWidthConstraint = cancelButton.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            cancelWidthConstraint,
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            searchField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
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
        cancelWidthConstraint.constant = active ? 56 : 0
        if active {
            transform = .identity
            searchField.transform = .identity
            searchField.alpha = 1
            isUserInteractionEnabled = true
        }
        onActiveChange?(active)
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.cancelButton.alpha = active ? 1 : 0
            self.layoutIfNeeded()
        } completion: { _ in
            if !active {
                self.applyScroll(offset: self.requestedScrollOffset, animated: true)
            }
        }
    }

    @objc private func queryChanged() {
        onQueryChange?(searchField.text ?? "")
    }

    @objc private func cancelSearch() {
        searchField.text = ""
        onQueryChange?("")
        searchField.resignFirstResponder()
    }
}
