// TelegramUndoToast.swift

import UIKit

/// Telegram's bottom undo overlay (UndoOverlayController), in BetterTG's dark-glass style: a message, with a bold title
/// above it for content such as setProximityAlert, and an optional action (Undo by default) that dismisses itself
/// after five seconds. A new toast replaces the visible one.
@MainActor final class TelegramUndoToast: UIView {
    // MARK: Private

    private weak static var current: TelegramUndoToast?

    private var duration: TimeInterval = 5
    /// The panel's own action (UndoOverlayControllerNode's buttonPressed with `.info`): a tap anywhere on it.
    private var tapAction: (() -> Void)?
    private var entersFromTop = false

    private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let label = UILabel()
    private let undoButton = UIButton(type: .system)
    private var undo: (() -> Void)?
    private var dismissWork: DispatchWorkItem?

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(title: String?, text: String, actionTitle: String?, undo: (() -> Void)?) {
        self.undo = undo
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = 14
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        addSubview(effectView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        let bodyFont = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .regular),
            maximumPointSize: 19,
        )
        label.font = bodyFont
        if let title {
            let titleFont = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: .systemFont(ofSize: 15, weight: .semibold),
                maximumPointSize: 19,
            )
            let attributed = NSMutableAttributedString(
                string: title,
                attributes: [.font: titleFont, .foregroundColor: UIColor.white],
            )
            if !text.isEmpty {
                attributed.append(NSAttributedString(
                    string: "\n" + text,
                    attributes: [.font: bodyFont, .foregroundColor: UIColor.white],
                ))
            }
            label.attributedText = attributed
            label.numberOfLines = 0
        } else {
            label.text = text
            label.numberOfLines = 2
        }
        label.adjustsFontForContentSizeCategory = true
        effectView.contentView.addSubview(label)

        undoButton.translatesAutoresizingMaskIntoConstraints = false
        undoButton.setTitle(actionTitle ?? L10n.telegram("Undo.Undo"), for: .normal)
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

    static func show(
        title: String? = nil,
        text: String,
        in host: UIView,
        bottomInset: CGFloat,
        actionTitle: String? = nil,
        undo: (() -> Void)?,
    ) {
        current?.dismiss(animated: false)
        let toast = TelegramUndoToast(title: title, text: text, actionTitle: actionTitle, undo: undo)
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

    /// UndoOverlayController's `.forward(savedMessages: true)` at the top of `host`: Telegram's **marked** text
    /// semibold, Saved Messages in the lighter accent, for three seconds; a tap anywhere opens Saved Messages.
    static func showSavedMessagesForward(
        _ text: String,
        in host: UIView,
        topInset: CGFloat,
        open: @escaping () -> Void,
    ) {
        current?.dismiss(animated: false)
        let toast = TelegramUndoToast(title: nil, text: text.withoutTelegramMarkup, actionTitle: nil, undo: nil)
        toast.label.attributedText = savedMessagesText(text, font: toast.label.font)
        toast.duration = 3
        toast.entersFromTop = true
        toast.tapAction = open
        toast.isAccessibilityElement = true
        toast.accessibilityLabel = text.withoutTelegramMarkup
        toast.accessibilityTraits = .button
        toast.addGestureRecognizer(UITapGestureRecognizer(target: toast, action: #selector(panelTapped)))
        toast.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            toast.trailingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            toast.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor, constant: topInset),
        ])
        current = toast
        toast.present()
    }

    /// The text with each `**…**` part semibold in `itemAccentColor.withMultiplied(hue: 0.933, saturation: 0.61)`.
    private static func savedMessagesText(_ text: String, font: UIFont) -> NSAttributedString {
        let bold = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: font.pointSize, weight: .semibold),
            maximumPointSize: 19,
        )
        var hue = CGFloat.zero
        var saturation = CGFloat.zero
        var brightness = CGFloat.zero
        UIColor.systemBlue
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        let accent = UIColor(hue: hue * 0.933, saturation: saturation * 0.61, brightness: brightness, alpha: 1)
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            let isBold = index % 2 == 1
            result.append(NSAttributedString(string: part, attributes: [
                .font: isBold ? bold : font,
                .foregroundColor: isBold ? accent : UIColor.white,
            ]))
        }
        return result
    }

    @objc private func panelTapped() {
        let action = tapAction
        dismiss(animated: true)
        action?()
    }

    private func present() {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: entersFromTop ? -16 : 16)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
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
            self.transform = CGAffineTransform(translationX: 0, y: self.entersFromTop ? -16 : 16)
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
