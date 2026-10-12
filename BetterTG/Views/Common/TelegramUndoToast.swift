// TelegramUndoToast.swift

import UIKit

/// Telegram's bottom undo overlay (UndoOverlayController), in BetterTG's dark-glass style: a message with an
/// optional Undo action that dismisses itself after five seconds. A new toast replaces the visible one.
@MainActor final class TelegramUndoToast: UIView {
    // MARK: Private

    private weak static var current: TelegramUndoToast?
    private static let duration: TimeInterval = 5

    private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let label = UILabel()
    private let undoButton = UIButton(type: .system)
    private var undo: (() -> Void)?
    private var dismissWork: DispatchWorkItem?

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(text: String, undo: (() -> Void)?) {
        self.undo = undo
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = 14
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        addSubview(effectView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = .white
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .regular),
            maximumPointSize: 19,
        )
        label.numberOfLines = 2
        label.adjustsFontForContentSizeCategory = true
        effectView.contentView.addSubview(label)

        undoButton.translatesAutoresizingMaskIntoConstraints = false
        undoButton.setTitle(L10n.telegram("Undo.Undo"), for: .normal)
        undoButton.titleLabel?.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold),
            maximumPointSize: 19,
        )
        undoButton.titleLabel?.adjustsFontForContentSizeCategory = true
        undoButton.tintColor = .systemBlue
        undoButton.isHidden = undo == nil
        undoButton.setContentHuggingPriority(.required, for: .horizontal)
        undoButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        effectView.contentView.addSubview(undoButton)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            label.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 16),
            label.topAnchor.constraint(greaterThanOrEqualTo: effectView.contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(lessThanOrEqualTo: effectView.contentView.bottomAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: effectView.contentView.centerYAnchor),
            undoButton.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            undoButton.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -16),
            undoButton.centerYAnchor.constraint(equalTo: effectView.contentView.centerYAnchor),
        ])
        accessibilityElements = undo == nil ? [label] : [label, undoButton]
    }

    // MARK: Internal

    /// Telegram's undo button spans the panel's full height from 8 pt before its title to the right edge
    /// (UndoOverlayControllerNode, undoButtonFrame); the rest of the panel absorbs touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        guard undo != nil, !undoButton.isHidden else { return hit }
        let buttonFrame = undoButton.convert(undoButton.bounds, to: self)
        return point.x >= buttonFrame.minX - 8 ? undoButton : hit
    }

    static func show(text: String, in host: UIView, bottomInset: CGFloat, undo: (() -> Void)?) {
        current?.dismiss(animated: false)
        let toast = TelegramUndoToast(text: text, undo: undo)
        toast.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            toast.trailingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            toast.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -bottomInset),
        ])
        current = toast
        toast.present()
    }

    private func present() {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 16)
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.3,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.alpha = 1
            self.transform = .identity
        }
        UIAccessibility.post(notification: .announcement, argument: label.text)
        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    private func dismiss(animated: Bool) {
        dismissWork?.cancel()
        dismissWork = nil
        undo = nil
        guard animated, superview != nil else {
            removeFromSuperview()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: 16)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    @objc private func undoTapped() {
        let action = undo
        dismiss(animated: true)
        action?()
    }
}
