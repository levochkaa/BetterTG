// ComposerSendIconView.swift

import UIKit

// MARK: - ComposerSendIconView

/// Telegram's send button (ChatTextInputActionButtonsNode's `sendContainerNode`): a circle in the accent color with its
/// arrow. It comes and goes as `updateActionButtons` has it on the chat's 0.4 s spring: the circle grows from nothing
/// beside its place while it fades in out of a blur, and the arrow swims in from below and before it.
@MainActor final class ComposerSendIconView: UIView {
    static let side: CGFloat = 28

    /// `transition.animatePositionAdditive(layer: imageNode.layer, offset: CGPoint(x: -22.0, y: 18.0))`.
    private static let arrowOffset = CGPoint(x: -22, y: 18)
    /// Where the layout keeps the hidden button: `(width - 3.0 * 2.0) * 0.5 - 3.0` of its 40 pt to the side.
    private static let hiddenOffset = CGPoint(x: 14, y: 0)
    private static let hiddenScale: CGFloat = 0.001
    /// `sendButtonBlurOut`.
    private static let hiddenBlur: CGFloat = 4
    private static let blurKeyPath = "filters.gaussianBlur.inputRadius"
    private static let fadeDuration: CFTimeInterval = 0.2
    private static let blurDuration: CFTimeInterval = 0.18
    private static let highlightedOpacity: Float = 0.4

    private let circle = CALayer()
    private let arrow = UIImageView(image: UIImage(
        systemName: "arrow.up",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold),
    ))
    private var isShown = false
    private var transitionID = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        // A layer of its own: glass moves a view's background and corner radius out to an effect layer of its own,
        // which
        // doesn't follow what is animated on the view's layer.
        circle.cornerRadius = Self.side / 2
        circle.cornerCurve = .circular
        circle.backgroundColor = tintColor.cgColor
        layer.addSublayer(circle)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.circle.backgroundColor = self.tintColor.resolvedColor(with: self.traitCollection).cgColor
        }
        arrow.tintColor = .white
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)
        NSLayoutConstraint.activate([
            arrow.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circle.frame = bounds
        CATransaction.commit()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        circle.backgroundColor = tintColor.resolvedColor(with: traitCollection).cgColor
    }

    private static func makeBlurFilter() -> NSObject? {
        guard let filterClass = NSClassFromString(["CA", "Filter"].joined()) as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return nil }
        return filterClass.perform(selector, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
    }

    func setShown(_ shown: Bool, animated: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        transitionID += 1
        guard animated else {
            layer.removeAllAnimations()
            arrow.layer.removeAllAnimations()
            layer.filters = nil
            layer.opacity = 1
            isHidden = !shown
            return
        }
        let presentation = layer.presentation()
        let opacity = isHidden ? 0 : presentation?.opacity ?? layer.opacity
        let scale = isHidden ? Self.hiddenScale : presentation?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1
        isHidden = false
        layer.opacity = shown ? 1 : 0
        layer.addTelegramAnimation(
            keyPath: "opacity",
            from: opacity,
            to: layer.opacity,
            duration: Self.fadeDuration,
            isRemovedOnCompletion: true,
        )
        animateBlur(to: shown ? 0 : Self.hiddenBlur)
        let id = transitionID
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, id == transitionID else { return }
            layer.filters = nil
            if !shown { isHidden = true }
            layer.opacity = 1
        }
        layer.addTelegramSpring(keyPath: "transform.scale", from: scale, to: shown ? 1 : Self.hiddenScale)
        layer.addTelegramSpring(
            keyPath: "position",
            from: NSValue(cgPoint: shown ? Self.hiddenOffset : .zero),
            to: NSValue(cgPoint: shown ? .zero : Self.hiddenOffset),
            isAdditive: true,
        )
        if shown {
            arrow.layer.addTelegramSpring(
                keyPath: "position",
                from: NSValue(cgPoint: Self.arrowOffset),
                to: NSValue(cgPoint: .zero),
                isAdditive: true,
            )
        }
        CATransaction.commit()
    }

    /// `sendButton.highligthedChanged`: it dims under the finger and brightens again.
    func setHighlighted(_ highlighted: Bool) {
        guard isShown else { return }
        layer.removeAnimation(forKey: "opacity")
        layer.opacity = highlighted ? Self.highlightedOpacity : 1
        guard !highlighted else { return }
        layer.addTelegramAnimation(
            keyPath: "opacity",
            from: Self.highlightedOpacity,
            to: Float(1),
            duration: Self.fadeDuration,
            isRemovedOnCompletion: true,
        )
    }

    /// ComponentTransition's `setBlur`: the filter stays only while it blurs.
    private func animateBlur(to radius: CGFloat) {
        let current = layer.presentation()?.value(forKeyPath: Self.blurKeyPath) as? CGFloat
        let from = current ?? (radius == 0 ? Self.hiddenBlur : 0)
        if layer.filters?.isEmpty != false {
            guard let filter = Self.makeBlurFilter() else { return }
            layer.filters = [filter]
        }
        layer.setValue(radius, forKeyPath: Self.blurKeyPath)
        layer.addTelegramAnimation(
            keyPath: Self.blurKeyPath,
            from: from,
            to: radius,
            duration: Self.blurDuration,
            isRemovedOnCompletion: true,
        )
    }
}
