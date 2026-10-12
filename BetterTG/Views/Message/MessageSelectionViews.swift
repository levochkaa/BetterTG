// MessageSelectionViews.swift

import UIKit

// MARK: - MessageSelectionIndicatorView

final class MessageSelectionIndicatorView: UIView {
    private let checkmarkView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .systemBackground
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 14
        layer.cornerCurve = .circular

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold),
        )
        checkmarkView.tintColor = .white
        addSubview(checkmarkView)
        NSLayoutConstraint.activate([
            checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 14),
            checkmarkView.heightAnchor.constraint(equalToConstant: 14),
        ])
        setSelected(false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        backgroundColor = selected ? .systemBlue : .systemBackground
        checkmarkView.isHidden = !selected
    }
}

// MARK: - MessageSelectionToolbar

final class MessageSelectionToolbar: UIView {
    static let contentHeight: CGFloat = 52

    var onDelete: (() -> Void)?
    var onForward: (() -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let deleteButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let forwardButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        selectedCount: Int,
        canDelete: Bool,
        canForward: Bool,
        isBusy: Bool = false,
    ) {
        countLabel.text = L10n.telegramPlural("Conversation.ForwardOptions.Title", count: selectedCount)
        deleteButton.isEnabled = canDelete && !isBusy
        forwardButton.isEnabled = canForward && !isBusy
        deleteButton.alpha = deleteButton.isEnabled ? 1 : 0.35
        forwardButton.alpha = forwardButton.isEnabled ? 1 : 0.35
        isUserInteractionEnabled = !isBusy
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setImage(
            UIImage(
                systemName: "trash",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular),
            ),
            for: .normal,
        )
        deleteButton.tintColor = .systemRed
        deleteButton.accessibilityLabel = L10n.betterTG("Accessibility.DeleteSelectedMessages")
        deleteButton.addTarget(self, action: #selector(deletePressed), for: .touchUpInside)
        addSubview(deleteButton)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.textAlignment = .center
        countLabel.textColor = .secondaryLabel
        countLabel.adjustsFontForContentSizeCategory = true
        addSubview(countLabel)

        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.setImage(
            UIImage(
                systemName: "arrowshape.turn.up.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular),
            ),
            for: .normal,
        )
        forwardButton.accessibilityLabel = L10n.betterTG("Accessibility.ForwardSelectedMessages")
        forwardButton.addTarget(self, action: #selector(forwardPressed), for: .touchUpInside)
        addSubview(forwardButton)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),

            deleteButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            deleteButton.topAnchor.constraint(equalTo: topAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 52),
            deleteButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            forwardButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            forwardButton.topAnchor.constraint(equalTo: topAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 52),
            forwardButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            countLabel.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: forwardButton.leadingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
        ])
    }

    @objc private func deletePressed() {
        onDelete?()
    }

    @objc private func forwardPressed() {
        onForward?()
    }
}
