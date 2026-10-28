// TelegramGlassInPlaceMorph.swift

import UIKit

// MARK: - TelegramGlassInPlaceMorph

/// Telegram 13's in-place bar change (NavigationBarInPlaceCapsule) for glass that becomes other glass within one bar,
/// such as a chat's title and avatar turning into its search field and close button. Each shape springs from its old
/// frame to its new one while the old items shrink away where they were and the new ones grow in where they will be;
/// a shape with only one end materializes or dematerializes in place. The morph draws the glass above the bar:
/// `handOver` hides the owner's own glass as the morph's takes its place, and `completion` hands it back.
@MainActor enum TelegramGlassInPlaceMorph {
    struct Shape {
        var from: CGRect?
        var fromItems: UIImage?
        var to: CGRect?
        var toItems: UIImage?
    }

    /// NavigationBarGlassAnimation's spring and matched item scale, as the push and pop morph uses.
    private static let duration: TimeInterval = 0.416
    private static let bounce: CGFloat = 0.25
    private static let itemScale = CGAffineTransform(scaleX: 0.2, y: 0.2)

    /// Runs the shapes, given in `host`'s coordinates, above `host`'s content.
    static func run(
        in host: UIView,
        shapes: [Shape],
        handOver: @escaping () -> Void,
        completion: @escaping () -> Void,
    ) {
        let overlay = UIView(frame: host.bounds)
        overlay.isUserInteractionEnabled = false
        // Each shape is glass of its own, as the bar's pills are: a shared glass container draws its members
        // differently, and the bar's glass would flash at the hand-over.
        let glassLayer = UIView(frame: overlay.bounds)
        overlay.addSubview(glassLayer)
        host.addSubview(overlay)
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
            glassLayer.addSubview(glass)
            let leaving = shape.from.flatMap { frame in shape.fromItems.map { itemsView($0, frame: frame) } }
            let arriving = shape.to.flatMap { frame in shape.toItems.map { itemsView($0, frame: frame) } }
            arriving?.alpha = 0
            arriving?.transform = itemScale
            for items in [leaving, arriving].compactMap(\.self) {
                overlay.addSubview(items)
            }
            changes.append {
                if let target = shape.to {
                    glass.transform = .identity
                    glass.frame = target
                    glass.effect = UIGlassEffect(style: .regular)
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
            completion()
            // The owner's glass draws from the next frame; the overlay stays until then.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { overlay.removeFromSuperview() }
        }
    }

    private static func itemsView(_ image: UIImage, frame: CGRect) -> UIImageView {
        let view = UIImageView(image: image)
        view.frame = frame
        return view
    }

    /// UIKit's materialize scale for a shape `size` large: 16 pt beyond it per axis, at most 1.2.
    private static func materializeScale(for size: CGSize) -> CGAffineTransform {
        let x = size.width > 0 ? min(1.2, (size.width + 16) / size.width) : 1.2
        let y = size.height > 0 ? min(1.2, (size.height + 16) / size.height) : 1.2
        return CGAffineTransform(scaleX: x, y: y)
    }
}
