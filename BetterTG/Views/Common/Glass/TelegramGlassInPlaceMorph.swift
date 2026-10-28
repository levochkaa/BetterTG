// TelegramGlassInPlaceMorph.swift

import UIKit

// MARK: - TelegramGlassInPlaceMorph

/// Telegram 13's in-place bar change (NavigationBarInPlaceCapsule) for glass that becomes other glass within one bar,
/// such as a chat's title and avatar turning into its search field and close button. Each shape springs from its old
/// frame to its new one while the old items shrink away where they were and the new ones grow in where they will be;
/// a shape with only one end materializes or dematerializes in place. The morph draws the glass above the bar, in one
/// container as the bar's glass is, with the items lent live inside it, where glass draws its content as the owner's
/// does; they move against the glass, so that they stay where they are. `handOver` hides the owner's own glass as the
/// morph's takes its place, and `completion` shows it again, as the items go back into it.
@MainActor enum TelegramGlassInPlaceMorph {
    struct Shape {
        var from: CGRect?
        var fromItems: TelegramGlassLoan?
        var to: CGRect?
        var toItems: TelegramGlassLoan?
    }

    /// NavigationBarGlassAnimation's spring and matched item scale, as the push and pop morph uses.
    private static let duration: TimeInterval = 0.416
    private static let bounce: CGFloat = 0.25
    private static let itemScale = CGAffineTransform(scaleX: 0.2, y: 0.2)

    /// Runs the shapes, given in `host`'s coordinates, above `host`'s content. `spacing` is the glass container's, as
    /// the owner's glass is grouped.
    static func run(
        in host: UIView,
        shapes: [Shape],
        spacing: CGFloat,
        handOver: @escaping () -> Void,
        completion: @escaping () -> Void,
    ) {
        let overlay = UIView(frame: host.bounds)
        overlay.isUserInteractionEnabled = false
        let container = UIVisualEffectView(effect: {
            let effect = UIGlassContainerEffect()
            effect.spacing = spacing
            return effect
        }())
        container.frame = overlay.bounds
        overlay.addSubview(container)
        host.addSubview(overlay)
        var loans = [TelegramGlassLoan]()
        var changes = [() -> Void]()
        for shape in shapes {
            guard let start = shape.from ?? shape.to else { continue }
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.cornerConfiguration = .capsule()
            glass.frame = start
            if shape.from == nil {
                // Glass materializes from no effect; animating a glass view's opacity breaks its rendering.
                glass.effect = nil
                glass.transform = materializeScale(for: start.size)
            }
            container.contentView.addSubview(glass)
            glass.clipsToBounds = false
            glass.contentView.clipsToBounds = false
            // Where items at `frame` stand inside glass whose frame is `glassFrame`.
            func center(of frame: CGRect, in glassFrame: CGRect) -> CGPoint {
                CGPoint(x: frame.midX - glassFrame.minX, y: frame.midY - glassFrame.minY)
            }
            func lend(_ loan: TelegramGlassLoan?, at frame: CGRect?) -> UIView? {
                guard let loan, let frame else { return nil }
                loan.host.bounds = CGRect(origin: .zero, size: frame.size)
                loan.host.center = center(of: frame, in: start)
                glass.contentView.addSubview(loan.host)
                loan.lend()
                loans.append(loan)
                return loan.host
            }
            let leaving = lend(shape.fromItems, at: shape.from)
            let arriving = lend(shape.toItems, at: shape.to)
            arriving?.alpha = 0
            arriving?.transform = itemScale
            changes.append {
                if let target = shape.to {
                    glass.transform = .identity
                    glass.frame = target
                    glass.effect = UIGlassEffect(style: .regular)
                    // On the glass's spring, against it: the items keep their place on screen.
                    if let from = shape.from { leaving?.center = center(of: from, in: target) }
                    arriving?.center = center(of: target, in: target)
                } else {
                    glass.transform = materializeScale(for: glass.bounds.size)
                    glass.effect = nil
                }
                leaving?.alpha = 0
                leaving?.transform = itemScale
                arriving?.alpha = 1
                arriving?.transform = .identity
            }
        }
        // Each shape is plain glass, which draws in the same frame: the owner's glass gives way at once, as two
        // shapes on one spot would show both while they part.
        handOver()
        UIView.animate(
            springDuration: duration,
            bounce: bounce,
            initialSpringVelocity: 0,
            delay: 0,
            options: [.beginFromCurrentState],
        ) {
            for change in changes {
                change()
            }
        } completion: { _ in
            // The owner's glass and its items come back in one frame, as the overlay leaves.
            completion()
            for loan in loans {
                loan.giveBack()
            }
            overlay.removeFromSuperview()
        }
    }

    /// UIKit's materialize scale for a shape `size` large: 16 pt beyond it per axis, at most 1.2.
    private static func materializeScale(for size: CGSize) -> CGAffineTransform {
        let x = size.width > 0 ? min(1.2, (size.width + 16) / size.width) : 1.2
        let y = size.height > 0 ? min(1.2, (size.height + 16) / size.height) : 1.2
        return CGAffineTransform(scaleX: x, y: y)
    }
}
