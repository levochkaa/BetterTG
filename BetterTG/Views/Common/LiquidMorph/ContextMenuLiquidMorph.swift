// ContextMenuLiquidMorph.swift

import UIKit

// MARK: - ContextMenuLiquidMorph

/// UIKit's liquid morph between a button and the custom menu, ported from Telegram iOS 7c2cfd6a1f
/// (submodules/TelegramUI/Components/LensTransition/Sources/LiquidMorphTransition.swift, commits 58ce7d6688,
/// 11a469d1f8 and 7c2cfd6a1f). `BTLiquidMorphDriver` runs UIKit's own coordinator; this wrapper validates the
/// previews, adds the 10 × 10 pivot at the attachment point, pins 120 Hz while the morph moves and hands views back
/// after UIKit's cleanup.
@MainActor final class ContextMenuLiquidMorph {
    static var isSupported: Bool { BTLiquidMorphDriver.isSupported() }

    // MARK: Internal

    private(set) var isAnimating = false

    // MARK: Private

    private var driver: BTLiquidMorphDriver?
    private var generation = 0

    /// Hides `view` while the returned object is retained, without touching its model alpha or hidden state.
    static func sourceVisibilityAssertion(for view: UIView) -> AnyObject? {
        BTLiquidMorphDriver.visibilityAssertion(for: view) as AnyObject?
    }

    /// UIKit centers the preview on `visiblePath` and keeps the view transform. A closing preview uses the
    /// presentation transform, as UIKit's dismissal preview does.
    static func sourcePreview(
        for view: UIView,
        parameters: UIPreviewParameters,
        usePresentationTransform: Bool = false,
    ) -> UITargetedPreview? {
        guard view.superview != nil, view.window != nil else { return nil }
        let preview = UITargetedPreview(view: view, parameters: parameters)
        guard usePresentationTransform else { return preview }
        let transform = view.layer.presentation()?.affineTransform() ?? view.transform
        let target = UIPreviewTarget(
            container: preview.target.container,
            center: preview.target.center,
            transform: transform,
        )
        return preview.retargetedPreview(with: target)
    }

    /// A second transition is rejected while one runs unless `interruptingCurrent` is set: then it starts at once
    /// and UIKit hands it the running morph. The interrupted completion still fires, but only the newest transition
    /// clears `isAnimating`.
    @discardableResult func animate(
        from: UITargetedPreview,
        to: UITargetedPreview,
        attachment: CGPoint,
        in container: UIView,
        sourceIdentity: UIView? = nil,
        interruptingCurrent: Bool = false,
        alongsideAnimations: (() -> Void)? = nil,
        completion: @escaping () -> Void,
    ) -> Bool {
        guard !isAnimating || interruptingCurrent, Self.isSupported, container.window != nil,
              from.target.container.window != nil, to.target.container.window != nil,
              from.view.window != nil, to.view.window != nil,
              from.size.width > 0, from.size.height > 0, to.size.width > 0, to.size.height > 0,
              from.size.width.isFinite, from.size.height.isFinite, to.size.width.isFinite, to.size.height.isFinite,
              attachment.x.isFinite, attachment.y.isFinite
        else { return false }
        let pivot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        pivot.layer.cornerRadius = 5
        pivot.overrideUserInterfaceStyle = container.traitCollection.userInterfaceStyle
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        let through = UITargetedPreview(
            view: pivot,
            parameters: parameters,
            target: UIPreviewTarget(container: container, center: attachment),
        )
        guard let driver = BTLiquidMorphDriver(
            source: from,
            destination: to,
            pivot: through,
            container: container,
            sourceIdentity: sourceIdentity,
            alongside: alongsideAnimations,
        ) else { return false }
        isAnimating = true
        self.driver = driver
        generation += 1
        let transitionGeneration = generation
        let frameRateClaim = ContextMenuLiquidMorphFrameRate.shared.claim(screen: container.window?.windowScene?.screen)
        driver.start { [self] in
            MainActor.assumeIsolated {
                frameRateClaim.end()
                // UIKit calls this before its own cleanup. Hand views back only after that cleanup, keeping the
                // coordinator alive through the callback.
                DispatchQueue.main.async { [self, driver] in
                    withExtendedLifetime(driver) {
                        if generation == transitionGeneration {
                            self.driver = nil
                            isAnimating = false
                        }
                        completion()
                    }
                }
            }
        }
        return true
    }
}

// MARK: - ContextMenuLiquidMorphFrameRate

/// Holds the display at 120 Hz while any morph moves, on screens that support it. UIKit ticks the morph from its
/// in-process animation manager with a 48–120 Hz range, which visibly ran slower than 120 Hz on device (Telegram
/// 7c2cfd6a1f). Each claim ends at its morph's completion or after one second, whichever comes first, so a missing
/// completion cannot keep the display at 120 Hz.
@MainActor private final class ContextMenuLiquidMorphFrameRate {
    // MARK: Internal

    @MainActor final class Claim {
        // MARK: Private

        private var isEnded = false

        fileprivate init() {}

        // MARK: Internal

        func end() {
            guard !isEnded else { return }
            isEnded = true
            ContextMenuLiquidMorphFrameRate.shared.release()
        }
    }

    // MARK: Private

    private final class Target: NSObject {
        @objc func tick() {}
    }

    static let shared = ContextMenuLiquidMorphFrameRate()

    /// UIKit reports completion once every spring settles, about 1.3 s after an opening and 1.6 s after a close;
    /// the visible motion ends at about 0.75 s and 0.7 s.
    private static let maximumDuration: TimeInterval = 1

    private var displayLink: CADisplayLink?
    private var count = 0

    func claim(screen: UIScreen?) -> Claim {
        count += 1
        if displayLink == nil, let screen, screen.maximumFramesPerSecond >= 120 {
            let link = CADisplayLink(target: Target(), selector: #selector(Target.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        let claim = Claim()
        // Holds the claim strongly, so the deadline fires even if the morph is torn down without completing.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumDuration) {
            claim.end()
        }
        return claim
    }

    private func release() {
        count -= 1
        if count == 0, let link = displayLink {
            displayLink = nil
            link.invalidate()
        }
    }
}
