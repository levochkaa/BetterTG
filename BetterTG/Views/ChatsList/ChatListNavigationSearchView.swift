// ChatListNavigationSearchView.swift

import UIKit

/// Telegram-style search content embedded into the app's custom navigation chrome: NavigationBarSearchContentNode's
/// 44 pt glass field, 8 pt below the bar's row and 8 pt above its edge (`navigationBarSearchContentHeight` 60). The
/// field sits inside interactive glass; an active search gives it SearchBarPlaceholderNode's close button, a 44 pt
/// glass circle 8 pt to its right that grows in from beyond the edge while the field narrows for it. A chat's search
/// (ChatSearchNavigationContentNode) uses the same field, opened and closed by its bar rather than by focus.
final class ChatListNavigationSearchView: UIView, UITextFieldDelegate {
    // MARK: Internal

    static let fieldHeight: CGFloat = 44
    static let verticalInset: CGFloat = 8
    static let scrollHeight = fieldHeight + verticalInset * 2

    /// The gap between the field and its close button.
    private static let closeSpacing: CGFloat = 8

    /// The close button away: past the edge (its width and 40 pt) and shrunk to nothing.
    private static let closedTransform = CGAffineTransform(translationX: fieldHeight + 40, y: 0)
        .scaledBy(x: 0.001, y: 0.001)

    /// SearchBarPlaceholderNode's cross: two 2 pt round-capped strokes across 16 pt of a 40 pt square.
    private static let closeIcon = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        .image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 28, y: 28))
            path.move(to: CGPoint(x: 28, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 28))
            path.lineWidth = 2
            path.lineCapStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }
        .withRenderingMode(.alwaysTemplate)

    var onQueryChange: ((String) -> Void)?
    var onActiveChange: ((Bool) -> Void)?
    /// The close button's action in place of clearing the field and its focus, for an owner that closes the search
    /// itself.
    var onClose: (() -> Void)?
    /// Whether the field's focus opens and closes the search. A chat's search stays open with the keyboard down, its
    /// bar presenting the field (`setPresented`).
    var followsFocus = true

    // MARK: Private

    private let searchField: UISearchTextField
    private let glassView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        return view
    }()

    private let closeButton = UIButton.telegramGlassIcon(
        ChatListNavigationSearchView.closeIcon,
        accessibilityLabel: L10n.betterTG("Accessibility.CloseSearch"),
    )
    private let closePlatter = TelegramGlassPlatter(role: .trailing(0))
    private var placeholder: String
    private var fieldTrailingConstraint: NSLayoutConstraint!
    private var searchHeightConstraint: NSLayoutConstraint!
    private var searchCenterYConstraint: NSLayoutConstraint!
    private var requestedScrollOffset = CGFloat.zero
    /// Whether the close button shows: the search is open.
    private var isOpen = false
    private var lastContentAlpha: CGFloat = 1
    /// The alpha the text colours and placeholder were last built with.
    private var appliedTextAlpha: CGFloat?

    var isActive: Bool { searchField.isFirstResponder }
    var hasMarkedText: Bool { searchField.markedTextRange != nil }
    #if DEBUG
    var probeField: UISearchTextField { searchField }
    #endif

    /// `field` lets an owner bring its own field, such as one with member tokens.
    init(
        placeholder: String = L10n.telegram("DialogList.SearchLabel"),
        field: UISearchTextField = UISearchTextField(),
    ) {
        self.placeholder = placeholder
        self.searchField = field
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

    /// Opens or closes the search for an owner that does not follow focus: the field's glass materializes and its
    /// text fades in, or the reverse, as the close button grows in or out.
    func setPresented(_ presented: Bool) {
        guard presented != isOpen else { return }
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        if presented {
            isHidden = false
            glassView.effect = nil
            searchField.alpha = 0
        }
        setActive(presented)
        // Glass materializes from no effect; animating a glass view's opacity breaks its rendering.
        UIView.animate(withDuration: 0.25) {
            self.glassView.effect = presented ? effect : nil
            self.searchField.alpha = presented ? 1 : 0
        } completion: { _ in
            guard !self.isOpen else { return }
            self.isHidden = true
            self.glassView.effect = effect
        }
    }

    func textFieldDidBeginEditing(_: UITextField) {
        if followsFocus { setActive(true) }
    }

    func textFieldDidEndEditing(_: UITextField) {
        if followsFocus { setActive(false) }
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
        // Inside the glass, so the glass answers the finger on the field.
        glassView.contentView.addSubview(searchField)

        closeButton.addTarget(self, action: #selector(closeSearch), for: .touchUpInside)
        closePlatter.translatesAutoresizingMaskIntoConstraints = false
        closePlatter.setItems([closeButton])
        closePlatter.transform = Self.closedTransform
        closePlatter.isHidden = true
        addSubview(closePlatter)

        fieldTrailingConstraint = glassView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -TelegramGlassPlatter.edgeInset,
        )
        searchHeightConstraint = glassView.heightAnchor.constraint(equalToConstant: Self.fieldHeight)
        searchCenterYConstraint = glassView.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([
            closePlatter.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TelegramGlassPlatter.edgeInset),
            closePlatter.centerYAnchor.constraint(equalTo: glassView.centerYAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TelegramGlassPlatter.edgeInset),
            fieldTrailingConstraint,
            searchCenterYConstraint,
            searchHeightConstraint,
            searchField.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            searchField.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])
    }

    private func setActive(_ active: Bool) {
        layoutIfNeeded()
        isOpen = active
        onActiveChange?(active)
        fieldTrailingConstraint.constant = -TelegramGlassPlatter.edgeInset
            - (active ? Self.fieldHeight + Self.closeSpacing : 0)
        if active {
            searchHeightConstraint.constant = Self.fieldHeight
            searchCenterYConstraint.constant = 0
            if followsFocus { searchField.alpha = 1 }
            glassView.isHidden = false
            lastContentAlpha = 1
            updateSearchContentAlpha(1)
            isUserInteractionEnabled = true
        }
        if active { closePlatter.isHidden = false }
        // The search bar's spring (ChatListSearchContainerNode's 0.4 s).
        UIView.animate(
            springDuration: 0.4,
            bounce: 0,
            initialSpringVelocity: 0,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.closePlatter.transform = active ? .identity : Self.closedTransform
            self.layoutIfNeeded()
        } completion: { _ in
            if !active {
                // A search reopened meanwhile keeps its button.
                self.closePlatter.isHidden = !self.isOpen
                if self.followsFocus { self.applyScroll(offset: self.requestedScrollOffset, animated: true) }
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
        if let onClose {
            onClose()
            return
        }
        searchField.text = ""
        onQueryChange?("")
        searchField.resignFirstResponder()
    }
}
