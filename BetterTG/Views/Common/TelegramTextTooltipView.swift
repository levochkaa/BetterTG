// TelegramTextTooltipView.swift

import UIKit

// MARK: - TelegramTooltipShape

/// ContextMenuContainerNode's bubble: 10 pt corners and an 18 by 9 pt arrow towards the source.
enum TelegramTooltipShape {
    static let cornerRadius = CGFloat(10)
    static let arrowWidth = CGFloat(18)
    static let verticalInset = CGFloat(9)

    /// ContextMenuContainerNode's mask: a rounded rectangle 9 pt in from the top and bottom, with the arrow in the
    /// inset on the source's side, kept clear of the corners.
    static func path(size: CGSize, arrowPosition: CGFloat, arrowOnBottom: Bool) -> UIBezierPath {
        let radius = cornerRadius
        let inset = verticalInset
        let arrow = max(radius + arrowWidth / 2, min(size.width - radius - arrowWidth / 2, arrowPosition))
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: inset + radius))
        path.addArc(
            withCenter: CGPoint(x: radius, y: inset + radius),
            radius: radius,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: true,
        )
        if !arrowOnBottom {
            path.addLine(to: CGPoint(x: arrow - arrowWidth / 2, y: inset))
            path.addLine(to: CGPoint(x: arrow, y: 0))
            path.addLine(to: CGPoint(x: arrow + arrowWidth / 2, y: inset))
        }
        path.addLine(to: CGPoint(x: size.width - radius, y: inset))
        path.addArc(
            withCenter: CGPoint(x: size.width - radius, y: inset + radius),
            radius: radius,
            startAngle: 3 * .pi / 2,
            endAngle: 0,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: size.width, y: size.height - radius - inset))
        path.addArc(
            withCenter: CGPoint(x: size.width - radius, y: size.height - radius - inset),
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true,
        )
        if arrowOnBottom {
            path.addLine(to: CGPoint(x: arrow + arrowWidth / 2, y: size.height - inset))
            path.addLine(to: CGPoint(x: arrow, y: size.height))
            path.addLine(to: CGPoint(x: arrow - arrowWidth / 2, y: size.height - inset))
        }
        path.addLine(to: CGPoint(x: radius, y: size.height - inset))
        path.addArc(
            withCenter: CGPoint(x: radius, y: size.height - radius - inset),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true,
        )
        path.close()
        return path
    }
}

// MARK: - TelegramTextTooltipView

/// Telegram's TooltipController with text: white 14 pt text in the context menu bubble, above the source when there
/// are 54 pt over it, else below. The bubble is the blurred dark one (`isBlurred`) in the material of BetterTG's
/// toasts, as black at 0.8 vanishes on BetterTG's black chat. It fades in over 0.25 s and out over 0.3 s after two
/// seconds;
/// showing it again for the same source changes the text in place and restarts the timer. Touches go through.
@MainActor final class TelegramTextTooltipView: UIView {
    private weak static var current: TelegramTextTooltipView?

    private let bubble = UIView()
    private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let shape = CAShapeLayer()
    private let label = UILabel()
    private var source = CGRect.zero
    private var dismissWork: DispatchWorkItem?

    private var topInset = CGFloat.zero
    private var padding = CGFloat(8)

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        overrideUserInterfaceStyle = .dark
        effectView.layer.mask = shape
        bubble.addSubview(effectView)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        bubble.addSubview(label)
        addSubview(bubble)
    }

    /// `source` is in `host`'s coordinates; `topInset` keeps the tooltip under the status bar, and `padding` is how
    /// near the screen's edges it may come (TooltipController's 8 pt, or 2 pt for the record button's).
    static func show(_ text: String, source: CGRect, in host: UIView, topInset: CGFloat, padding: CGFloat = 8) {
        if let current, current.superview === host, current.source == source {
            current.update(text, animated: true)
            current.restartTimer()
            return
        }
        current?.dismiss(animated: false)
        let tooltip = TelegramTextTooltipView()
        tooltip.frame = host.bounds
        tooltip.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tooltip.source = source
        tooltip.padding = padding
        host.addSubview(tooltip)
        current = tooltip
        tooltip.update(text, animated: false, topInset: topInset)
        tooltip.bubble.alpha = 0
        UIView.animate(withDuration: 0.25) { tooltip.bubble.alpha = 1 }
        UIAccessibility.post(notification: .announcement, argument: text)
        tooltip.restartTimer()
    }

    private func update(_ text: String, animated: Bool, topInset: CGFloat? = nil) {
        if let topInset { self.topInset = topInset }
        if animated, let snapshot = label.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = label.frame
            bubble.addSubview(snapshot)
            UIView.animate(withDuration: 0.12, animations: { snapshot.alpha = 0 }, completion: { _ in
                snapshot.removeFromSuperview()
            })
            label.alpha = 0
            UIView.animate(withDuration: 0.12) { self.label.alpha = 1 }
        }
        label.text = text
        // TooltipControllerNode: the text fits the screen less 20 pt and the 8 pt padding on each side, rounded up
        // to even points; the bubble is 12 pt wider and 34 pt taller, with the text at (6, 17).
        let maxWidth = bounds.width - 20 - padding * 2
        let fitting = label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let textSize = CGSize(
            width: ceil(min(fitting.width, maxWidth) / 2) * 2,
            height: ceil(fitting.height / 2) * 2,
        )
        let size = CGSize(width: textSize.width + 12, height: textSize.height + 34)
        let arrowOnBottom = source.minY - 54 > self.topInset
        let y = arrowOnBottom ? source.minY - size.height : source.maxY
        let x = floor(min(max(padding, source.midX - size.width / 2), bounds.width - size.width - padding))
        bubble.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        label.frame = CGRect(origin: CGPoint(x: 6, y: 17), size: textSize)
        effectView.frame = bubble.bounds
        shape.path = TelegramTooltipShape.path(
            size: size,
            arrowPosition: source.midX - x,
            arrowOnBottom: arrowOnBottom,
        )
        .cgPath
    }

    private func restartTimer() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func dismiss(animated: Bool) {
        dismissWork?.cancel()
        dismissWork = nil
        if Self.current === self { Self.current = nil }
        guard animated else {
            removeFromSuperview()
            return
        }
        UIView.animate(withDuration: 0.3, animations: { self.bubble.alpha = 0 }, completion: { _ in
            self.removeFromSuperview()
        })
    }
}
