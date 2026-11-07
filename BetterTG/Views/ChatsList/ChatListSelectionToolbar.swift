// ChatListSelectionToolbar.swift

import UIKit

// MARK: - ChatListSelectionToolbar

/// Telegram 13's chat list toolbar while a list selects (TabBarControllerNode's GlassControlPanelComponent): text
/// actions in glass capsules at the left and right edges, and one in the middle where the list offers it, with no bar
/// material behind them, 44 points tall over the home indicator. The view spans the bottom; only the capsules take
/// touches.
final class ChatListSelectionToolbar: UIView {
    static let contentHeight: CGFloat = 49

    /// GlassControlPanelComponent's metrics: the capsules' height, their text inset and the least gap between them.
    private static let capsuleHeight: CGFloat = 44
    private static let textInset: CGFloat = 10
    private static let minSpacing: CGFloat = 8

    var onLeft: (() -> Void)?
    var onMiddle: (() -> Void)?
    var onRight: (() -> Void)?

    private let container: UIVisualEffectView = {
        let effect = UIGlassContainerEffect()
        effect.spacing = ChatListSelectionToolbar.minSpacing
        return UIVisualEffectView(effect: effect)
    }()

    private let leftCapsule = ChatListSelectionToolbar.makeCapsule()
    private let middleCapsule = ChatListSelectionToolbar.makeCapsule()
    private let rightCapsule = ChatListSelectionToolbar.makeCapsule()
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

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        // The list stays under the gaps, as the panel has no material of its own.
        [leftCapsule, middleCapsule, rightCapsule].contains { capsule in
            !capsule.isHidden && capsule.frame.contains(convert(point, to: container.contentView))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        container.frame = bounds
        // TabBarControllerNode: the panel stands on the bottom inset (8 pt without one), 12 pt from the sides over
        // the home indicator and 20 pt otherwise.
        let bottomInset = max(8, window?.safeAreaInsets.bottom ?? safeAreaInsets.bottom)
        let sideInset: CGFloat = bottomInset <= 28 ? 20 : 12
        let height = Self.capsuleHeight
        let y = bounds.height - bottomInset - height
        let minX = safeAreaInsets.left + sideInset
        let maxX = bounds.width - safeAreaInsets.right - sideInset
        let width = maxX - minX

        let leftWidth = capsuleWidth(for: leftButton, limit: width)
        let leftFrame = CGRect(x: minX, y: y, width: leftWidth, height: height)
        let rightWidth = capsuleWidth(for: rightButton, limit: width)
        let rightFrame = CGRect(x: maxX - rightWidth, y: y, width: rightWidth, height: height)
        place(leftCapsule, button: leftButton, frame: leftFrame)
        place(rightCapsule, button: rightButton, frame: rightFrame)

        guard !middleCapsule.isHidden else { return }
        // The central item keeps clear of the sides and centres on the panel where it fits (centerAlignmentIfPossible).
        var leftInset = leftFrame.maxX - minX + Self.minSpacing
        var rightInset = maxX - rightFrame.minX + Self.minSpacing
        if leftInset <= 48, rightInset <= 48 {
            leftInset = max(leftInset, rightInset)
            rightInset = leftInset
        }
        let room = max(1, width - leftInset - rightInset)
        let middleWidth = capsuleWidth(for: middleButton, limit: room)
        var middleX = minX + leftInset + floor((room - middleWidth) / 2)
        let maxInset = max(leftInset, rightInset)
        if width - maxInset * 2 > middleWidth {
            middleX = minX + maxInset + floor((width - maxInset * 2 - middleWidth) / 2)
        }
        place(middleCapsule, button: middleButton, frame: CGRect(x: middleX, y: y, width: middleWidth, height: height))
    }

    /// Interactive glass with its button inside, as GlassControlGroupComponent's GlassBackgroundView.
    private static func makeCapsule() -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        return view
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
        apply(left, enabled: leftEnabled, to: leftButton, in: leftCapsule)
        apply(middle ?? "", enabled: middleEnabled, to: middleButton, in: middleCapsule)
        middleCapsule.isHidden = middle == nil
        apply(right, enabled: rightEnabled, to: rightButton, in: rightCapsule)
        setNeedsLayout()
    }

    private func configureViews() {
        container.isUserInteractionEnabled = true
        addSubview(container)
        middleCapsule.isHidden = true
        for (capsule, button) in [
            (leftCapsule, leftButton),
            (middleCapsule, middleButton),
            (rightCapsule, rightButton),
        ] {
            button.tintColor = .label
            button.titleLabel?.font = UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: .systemFont(ofSize: 17, weight: .medium))
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            capsule.contentView.addSubview(button)
            container.contentView.addSubview(capsule)
        }
        leftButton.addAction(UIAction { [weak self] _ in self?.onLeft?() }, for: .touchUpInside)
        middleButton.addAction(UIAction { [weak self] _ in self?.onMiddle?() }, for: .touchUpInside)
        rightButton.addAction(UIAction { [weak self] _ in self?.onRight?() }, for: .touchUpInside)
    }

    /// A disabled action shows at half strength, and its glass doesn't respond, as the component's item without an
    /// action.
    private func apply(_ title: String, enabled: Bool, to button: UIButton, in capsule: UIVisualEffectView) {
        button.setTitle(title, for: .normal)
        button.isEnabled = enabled
        button.setTitleColor(.label, for: .normal)
        button.setTitleColor(.label.withAlphaComponent(0.5), for: .disabled)
        capsule.isUserInteractionEnabled = enabled
    }

    private func capsuleWidth(for button: UIButton, limit: CGFloat) -> CGFloat {
        let text = button.titleLabel?.intrinsicContentSize.width ?? 0
        return min(limit, max(Self.capsuleHeight, ceil(text) + Self.textInset * 2))
    }

    private func place(_ capsule: UIVisualEffectView, button: UIButton, frame: CGRect) {
        capsule.frame = frame
        button.frame = CGRect(
            x: Self.textInset,
            y: 0,
            width: max(0, frame.width - Self.textInset * 2),
            height: frame.height,
        )
    }
}
