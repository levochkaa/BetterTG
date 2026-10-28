// TelegramLottieIconView.swift

import Lottie
import UIKit

// MARK: - TelegramLottieIconView

/// One of Telegram's input panel icons drawn from its Lottie animation, as LottieComponent with a monochromatic
/// effect draws it: in the view's tint colour, resting on the animation's last frame, and played once when it
/// changes to show a transition, such as `input_anim_keyToSmile`.
@MainActor final class TelegramLottieIconView: UIView {
    // MARK: Private

    private static var cache = [String: LottieAnimation]()

    // MARK: Internal

    override var intrinsicContentSize: CGSize { CGSize(width: side, height: side) }

    private let side: CGFloat
    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic,
        decodingStrategy: .legacyCodable,
    ))
    private var currentName: String?

    init(side: CGFloat) {
        self.side = side
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        isUserInteractionEnabled = false
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .forceFinish
        addSubview(animationView)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.applyTint() }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyTint()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        animationView.frame = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side,
        )
    }

    private static func animation(named name: String) -> LottieAnimation? {
        if let cached = cache[name] { return cached }
        guard let path = Bundle.main.path(forResource: name, ofType: "json"),
              let animation = LottieAnimation.filepath(path)
        else { return nil }
        cache[name] = animation
        return animation
    }

    /// Shows the bundled animation `name`, played from its start when `animated`, else on its last frame.
    func show(_ name: String, animated: Bool) {
        if name != currentName {
            currentName = name
            animationView.animation = Self.animation(named: name)
            applyTint()
        }
        if animated {
            animationView.currentProgress = 0
            animationView.play()
        } else {
            animationView.stop()
            animationView.currentProgress = 1
        }
    }

    private func applyTint() {
        let color = tintColor.resolvedColor(with: traitCollection)
        animationView.setValueProvider(
            ColorValueProvider(color.lottieColorValue),
            keypath: AnimationKeypath(keypath: "**.Color"),
        )
        animationView.alpha = color.cgColor.alpha
    }
}
