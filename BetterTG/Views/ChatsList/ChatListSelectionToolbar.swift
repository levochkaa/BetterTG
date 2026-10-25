// ChatListSelectionToolbar.swift

import UIKit

// MARK: - ChatListSelectionToolbar

/// Telegram's chat list Toolbar (ToolbarNode) while a list selects: text actions at the left and right edges, and
/// one in the middle where the list offers it, over the bar's material, 49 points above the home indicator.
final class ChatListSelectionToolbar: UIView {
    static let contentHeight: CGFloat = 49

    var onLeft: (() -> Void)?
    var onMiddle: (() -> Void)?
    var onRight: (() -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let leftButton = UIButton(type: .system)
    private let middleButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A nil `middle` hides the middle action.
    func update(
        left: String,
        leftEnabled: Bool,
        middle: String? = nil,
        middleEnabled: Bool = false,
        right: String,
        rightEnabled: Bool,
    ) {
        leftButton.setTitle(left, for: .normal)
        leftButton.isEnabled = leftEnabled
        middleButton.setTitle(middle, for: .normal)
        middleButton.isHidden = middle == nil
        middleButton.isEnabled = middleEnabled
        rightButton.setTitle(right, for: .normal)
        rightButton.isEnabled = rightEnabled
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        middleButton.isHidden = true
        for button in [leftButton, middleButton, rightButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .systemBlue
            button.setTitleColor(.tertiaryLabel, for: .disabled)
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            addSubview(button)
        }
        leftButton.addAction(UIAction { [weak self] _ in self?.onLeft?() }, for: .touchUpInside)
        middleButton.addAction(UIAction { [weak self] _ in self?.onMiddle?() }, for: .touchUpInside)
        rightButton.addAction(UIAction { [weak self] _ in self?.onRight?() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),

            leftButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            leftButton.topAnchor.constraint(equalTo: topAnchor),
            leftButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            rightButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            rightButton.topAnchor.constraint(equalTo: topAnchor),
            rightButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            rightButton.leadingAnchor.constraint(greaterThanOrEqualTo: leftButton.trailingAnchor, constant: 16),

            middleButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            middleButton.topAnchor.constraint(equalTo: topAnchor),
            middleButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),
        ])
    }
}
