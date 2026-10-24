// ContextMenuInteraction.swift

import UIKit

// MARK: - ContextMenuSpringBehavior

/// `UIViewSpringAnimationBehavior` setters used by the system context menu (UIKitCore 24A434).
@objc private protocol ContextMenuSpringBehavior: NSObjectProtocol {
    init()
    @objc(setDampingRatio:response:) func setDampingRatio(_ dampingRatio: CGFloat, response: CGFloat)
    @objc(setInertialTargetSmoothing:) func setInertialTargetSmoothing(_ value: CGFloat)
    @objc(setInertialProjectionDeceleration:) func setInertialProjectionDeceleration(_ value: CGFloat)
    @objc(setTrackingDampingRatio:response:dampingRatioSmoothing:responseSmoothing:) func setTracking(
        dampingRatio: CGFloat,
        response: CGFloat,
        dampingRatioSmoothing: CGFloat,
        responseSmoothing: CGFloat,
    )
}

// MARK: - ContextMenuSpringAnimating

@objc private protocol ContextMenuSpringAnimating: NSObjectProtocol {
    @objc(_animateUsingSpringBehavior:tracking:animations:completion:) static func animate(
        behavior: AnyObject,
        tracking: Bool,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)?,
    )
    @objc(_modifyAnimationsWithPreferredFrameRateRange:updateReason:animations:)
    static func modifyAnimations(frameRateRange: CAFrameRateRange, updateReason: UInt32, animations: () -> Void)
}

// MARK: - ContextMenuGlassMaterial

/// `_UIViewGlass` setters the system menu calls in `__UIContextMenuListViewResolvedMaterial` (0x1c482aee0).
@objc private protocol ContextMenuGlassMaterial: NSObjectProtocol {
    @objc(initWithVariant:) init(variant: Int)
    @objc(setAdaptive:) func setAdaptive(_ value: Bool)
    @objc(setFlexible:) func setFlexible(_ value: Bool)
    @objc(_setFlexVariant:) func setFlexVariant(_ value: Int)
    @objc(_setEnabledWithoutSolarium:) func setEnabledWithoutSolarium(_ value: Bool)
    @objc(setAllowsGrouping:) func setAllowsGrouping(_ value: Bool)
}

// MARK: - ContextMenuMaterialHost

@objc private protocol ContextMenuMaterialHost: NSObjectProtocol {
    @objc(_setBackground:) func setMaterialBackground(_ material: AnyObject?)
}

// MARK: - ContextMenuNativeGlass

/// The system menu's glass, ported from CustomContextMenu App/NativeUIKit.swift. The flexible material installs
/// UIKit's `_UIFlexInteraction` (activation 2/0, sources 3, variant 5, pan on the window), so the menu stretches
/// toward a finger dragged across it, as the system menu does. iOS 26 has every call but
/// `_setEnabledWithoutSolarium:`; without the material, the public interactive glass doesn't bend under a touch
/// that begins on the menu's rows, which sit beside it.
@MainActor enum ContextMenuNativeGlass {
    // MARK: Private

    private static let glassClass: AnyClass? = {
        guard let glassClass = NSClassFromString("_UIViewGlass"),
              [
                  "initWithVariant:",
                  "setAdaptive:",
                  "setFlexible:",
                  "_setFlexVariant:",
                  "setAllowsGrouping:",
              ].allSatisfy({ glassClass.instancesRespond(to: NSSelectorFromString($0)) })
        else { return nil }
        return glassClass
    }()

    /// iOS 27 adds `_setEnabledWithoutSolarium:`; iOS 26 glass is always enabled and lacks the selector.
    private static let setsEnabledWithoutSolarium = glassClass?
        .instancesRespond(to: NSSelectorFromString("_setEnabledWithoutSolarium:")) == true

    // MARK: Internal

    /// `_updateGlassBackgroundIfNeeded` (0x1c482b0a8) puts the material on a plain view. Returns false when the
    /// private material is unavailable; the caller then uses interactive `UIGlassEffect`.
    static func applyMenuGlass(to view: UIView) -> Bool {
        guard let glassClass, view.responds(to: NSSelectorFromString("_setBackground:")) else { return false }
        let glass = unsafeBitCast(glassClass, to: ContextMenuGlassMaterial.Type.self).init(variant: 0)
        glass.setAdaptive(false)
        glass.setFlexible(true)
        glass.setFlexVariant(5)
        if setsEnabledWithoutSolarium { glass.setEnabledWithoutSolarium(true) }
        glass.setAllowsGrouping(false)
        unsafeBitCast(view, to: ContextMenuMaterialHost.self).setMaterialBackground(glass)
        return true
    }
}

// MARK: - ContextMenuNativeAnimation

/// The private UIKit spring calls of the system context menu, ported from CustomContextMenu
/// App/NativeUIKit.swift (addresses in its Research/Interaction/README.md). Every entry point checks its
/// selectors and otherwise falls back to public UIKit that exists on iOS 26.
@MainActor enum ContextMenuNativeAnimation {
    // MARK: Private

    private static let springClass: AnyClass? = {
        guard let springClass = NSClassFromString("UIViewSpringAnimationBehavior"),
              [
                  "setDampingRatio:response:",
                  "setInertialTargetSmoothing:",
                  "setInertialProjectionDeceleration:",
                  "setTrackingDampingRatio:response:dampingRatioSmoothing:responseSmoothing:",
              ].allSatisfy({ springClass.instancesRespond(to: NSSelectorFromString($0)) })
        else { return nil }
        return springClass
    }()

    private static let animator: ContextMenuSpringAnimating.Type? = {
        let viewClass: AnyClass = UIView.self
        guard viewClass
            .responds(to: NSSelectorFromString("_animateUsingSpringBehavior:tracking:animations:completion:")),
            viewClass.responds(
                to: NSSelectorFromString("_modifyAnimationsWithPreferredFrameRateRange:updateReason:animations:"),
            )
        else { return nil }
        return unsafeBitCast(viewClass, to: ContextMenuSpringAnimating.Type.self)
    }()

    // MARK: Internal

    static var usesNativeSprings: Bool { springClass != nil && animator != nil }

    /// `_createAnimationBehaviorWithCriticalDamping:NO` (0x1c3fc0764), the PreviewPlatterPan spring: inertial
    /// smoothing 0.15, projection deceleration 0.996, release 0.85 / 0.5 s, tracking 0.8 / 0.4 s smoothed by 0.08.
    static func makePanBehavior() -> AnyObject? {
        guard let springClass else { return nil }
        let behavior = unsafeBitCast(springClass, to: ContextMenuSpringBehavior.Type.self).init()
        behavior.setInertialTargetSmoothing(0.15)
        behavior.setInertialProjectionDeceleration(0.996)
        behavior.setDampingRatio(0.85, response: 0.5)
        behavior.setTracking(dampingRatio: 0.8, response: 0.4, dampingRatioSmoothing: 0.08, responseSmoothing: 0.08)
        return behavior
    }

    /// `behaviorWithDampingRatio:response:` of `highlightItemAtIndexPath:` and `unHighlightItemAtIndexPath:`.
    static func makeBehavior(dampingRatio: CGFloat, response: CGFloat) -> AnyObject? {
        guard let springClass else { return nil }
        let behavior = unsafeBitCast(springClass, to: ContextMenuSpringBehavior.Type.self).init()
        behavior.setDampingRatio(dampingRatio, response: response)
        return behavior
    }

    /// `+[UIView _animateUsingSpringBehavior:tracking:…]` inside the native 48–120 Hz frame-rate range with
    /// update reason 0x100026 (0x1c3fc0730–0760, 0x1c482e218–0248).
    static func animate(
        behavior: AnyObject?,
        tracking: Bool,
        fallbackDampingRatio: CGFloat,
        fallbackResponse: CGFloat,
        _ animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        guard let behavior, let animator else {
            UIView.animate(
                springDuration: fallbackResponse,
                bounce: max(0, 1 - fallbackDampingRatio),
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: animations,
                completion: completion,
            )
            return
        }
        animator.animate(behavior: behavior, tracking: tracking, animations: {
            animator.modifyAnimations(
                frameRateRange: CAFrameRateRange(minimum: 48, maximum: 120, preferred: 0),
                updateReason: 0x100026,
                animations: animations,
            )
        }, completion: completion)
    }
}

// MARK: - ContextMenuTouchRecognizer

/// Continuous observer of one touch on the open menu (CustomContextMenu App/MenuTouchRecognizer.swift). It
/// cancels and delays no touches, so the views under it still receive them.
final class ContextMenuTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    // MARK: Internal

    private(set) var point = CGPoint.zero
    /// Timestamp of the latest touch event, in the `CACurrentMediaTime` timebase.
    private(set) var timestamp: TimeInterval = 0

    // MARK: Private

    private var trackedTouch: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
        allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        point = touch.location(in: nil)
        timestamp = touch.timestamp
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        point = touch.location(in: nil)
        timestamp = touch.timestamp
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        point = touch.location(in: nil)
        timestamp = touch.timestamp
        state = .ended
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }

    override func canPrevent(_: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by _: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool { true }
}

// MARK: - ContextMenuPressGestureRecognizer

/// The hold that opens a context menu, after the system menu's `_UITouchDurationObservingGestureRecognizer`
/// and `_UIGravityWellEffect` (CustomContextMenu App/CustomMenu.swift, pressing phase). Progress starts after
/// 0.15 s, the pressed view grows by up to 8 pt with a shadow on a 0.6 / 0.4 s spring, moving 20 pt cancels the
/// press, and the gesture begins at the hold duration. It then keeps reporting the same finger, which the menu
/// uses for scrubbing, and `presentTelegramContextMenu` takes the grown view over. Competing gestures that are
/// still possible fail through UIKit's normal exclusivity when it begins; resetting them by toggling
/// `isEnabled` breaks UIKit's own state machines, such as the table's swipe actions.
final class ContextMenuPressGestureRecognizer: UIGestureRecognizer {
    // MARK: Internal

    /// The view that grows under the finger. Defaults to the gesture's view; `nil` fails the gesture at once.
    var pressedViewProvider: ((ContextMenuPressGestureRecognizer) -> UIView?)?
    /// Sources without an opaque shape of their own, such as text-only buttons, skip the shadow.
    var castsShadow = true
    /// The press ended without a menu taking the pressed view over.
    var onPressCancelled: (() -> Void)?

    /// Timestamp of the latest touch event, in the `CACurrentMediaTime` timebase.
    private(set) var timestamp: TimeInterval = 0

    // MARK: Private

    private var trackedTouch: UITouch?
    private var startPoint = CGPoint.zero
    private var press: ContextMenuPressEffect?
    private var activated = false

    var isPressing: Bool { press != nil }

    override func location(in view: UIView?) -> CGPoint {
        trackedTouch?.location(in: view) ?? super.location(in: view)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard trackedTouch == nil else {
            // A second finger before the menu opens is not a press; afterwards the menu ignores it.
            if !activated { failPress() }
            return
        }
        guard touches.count == 1, let touch = touches.first else {
            failPress()
            return
        }
        trackedTouch = touch
        startPoint = touch.location(in: nil)
        timestamp = touch.timestamp
        guard let pressedView = pressedViewProvider.map({ $0(self) }) ?? view else {
            failPress()
            return
        }
        press = ContextMenuPressEffect(
            view: pressedView,
            owner: self,
            castsShadow: castsShadow,
            startTimestamp: touch.timestamp,
            holdDuration: ContextMenuMotion.holdDuration(
                isPad: pressedView.traitCollection.userInterfaceIdiom == .pad,
            ),
        )
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        timestamp = touch.timestamp
        if activated {
            state = .changed
            return
        }
        let point = touch.location(in: nil)
        if hypot(point.x - startPoint.x, point.y - startPoint.y) > ContextMenuMotion.allowableMovement {
            failPress()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        timestamp = touch.timestamp
        if activated { state = .ended } else { failPress() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if activated { state = .cancelled } else { failPress() }
    }

    override func reset() {
        super.reset()
        releasePress()
        trackedTouch = nil
        activated = false
    }

    /// Stops the press effect and leaves the grown transform for the menu, which restores the returned base
    /// transform when it closes. Returns `nil` when `view` is not the pressed view.
    func handOffPress(of view: UIView) -> CGAffineTransform? {
        guard let press, press.view === view else { return nil }
        self.press = nil
        return press.handOff()
    }

    /// The pressed view's transform before the press, for a menu that leaves the view in place.
    func pressBaseTransform(of view: UIView) -> CGAffineTransform? {
        guard let press, press.view === view else { return nil }
        return press.baseTransform
    }

    /// Springs the pressed view back to rest.
    func releasePress() {
        guard let press else { return }
        self.press = nil
        press.release()
        onPressCancelled?()
    }

    // MARK: Fileprivate

    fileprivate func pressDidReachHold() {
        guard state == .possible, !activated else { return }
        activated = true
        press?.hold()
        state = .began
    }

    private func failPress() {
        releasePress()
        if state == .possible { state = .failed }
    }
}

// MARK: - ContextMenuPressEffect

/// `_UIGravityWellEffect` on the pressed view, driven by one display link at up to 120 Hz.
@MainActor private final class ContextMenuPressEffect {
    // MARK: Private

    private enum Phase {
        case pressing
        case held
        case releasing
    }

    private struct SavedShadow {
        let color: CGColor?
        let radius: CGFloat
        let offset: CGSize
        let opacity: Float
    }

    // MARK: Internal

    private(set) weak var view: UIView?
    let baseTransform: CGAffineTransform

    private weak var owner: ContextMenuPressGestureRecognizer?
    private let castsShadow: Bool
    private let startTimestamp: TimeInterval
    private let holdDuration: TimeInterval
    private let savedShadow: SavedShadow
    private var phase = Phase.pressing
    private var scale = ContextMenuSpring(1)
    private var shadow = ContextMenuSpring(0)
    private var lastTime: TimeInterval
    private var displayLink: CADisplayLink?

    init(
        view: UIView,
        owner: ContextMenuPressGestureRecognizer,
        castsShadow: Bool,
        startTimestamp: TimeInterval,
        holdDuration: TimeInterval,
    ) {
        self.view = view
        self.owner = owner
        self.castsShadow = castsShadow
        self.startTimestamp = startTimestamp
        self.holdDuration = holdDuration
        self.baseTransform = view.transform
        let layer = view.layer
        self.savedShadow = SavedShadow(
            color: layer.shadowColor,
            radius: layer.shadowRadius,
            offset: layer.shadowOffset,
            opacity: layer.shadowOpacity,
        )
        self.lastTime = CACurrentMediaTime()
        if castsShadow {
            // _UIShadowProperties of the platter: black, radius 20, zero offset, opacity 0.3 at full progress.
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowRadius = 20
            layer.shadowOffset = .zero
            layer.shadowOpacity = 0
        }
        let target = ContextMenuDisplayLinkTarget()
        target.effect = self
        let link = CADisplayLink(target: target, selector: #selector(ContextMenuDisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 48, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    /// The menu opened: the press holds full progress until the menu takes the view over.
    func hold() {
        guard phase == .pressing else { return }
        phase = .held
        retarget(progress: 1)
    }

    func release() {
        guard phase != .releasing else { return }
        phase = .releasing
        scale.target = 1
        shadow.target = 0
    }

    func handOff() -> CGAffineTransform {
        stop()
        restoreShadow()
        return baseTransform
    }

    func tick() {
        guard let view, view.window != nil else {
            finish()
            return
        }
        if owner == nil { release() }
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        if phase == .pressing {
            let elapsed = now - startTimestamp
            retarget(progress: ContextMenuMotion.pressProgress(elapsed: elapsed, duration: holdDuration))
            if elapsed >= holdDuration { owner?.pressDidReachHold() }
        }
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        let releasing = phase == .releasing
        let response = reducedMotion ? 0.4 : (releasing ? 0.35 : ContextMenuMotion.pressSpringResponse)
        let damping = reducedMotion ? 1.0 : (releasing ? 0.85 : ContextMenuMotion.pressSpringDamping)
        scale.step(dt, response: response, damping: damping)
        shadow.step(dt, response: response, damping: damping)
        view.transform = baseTransform.scaledBy(x: scale.value, y: scale.value)
        if castsShadow { view.layer.shadowOpacity = Float(max(0, min(1, shadow.value))) * 0.3 }
        if releasing, scale.isSettled, shadow.isSettled { finish() }
    }

    private func retarget(progress: CGFloat) {
        let size = view?.bounds.size ?? .zero
        scale.target = UIAccessibility.isReduceMotionEnabled
            ? 1
            : ContextMenuMotion.pressScale(size: size, progress: progress)
        shadow.target = progress
    }

    private func finish() {
        stop()
        view?.transform = baseTransform
        restoreShadow()
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func restoreShadow() {
        guard castsShadow, let layer = view?.layer else { return }
        layer.shadowColor = savedShadow.color
        layer.shadowRadius = savedShadow.radius
        layer.shadowOffset = savedShadow.offset
        layer.shadowOpacity = savedShadow.opacity
    }
}

// MARK: - ContextMenuDisplayLinkTarget

/// Keeps a releasing press alive until its spring settles; invalidating the link releases it.
@MainActor private final class ContextMenuDisplayLinkTarget: NSObject {
    var effect: ContextMenuPressEffect?

    @objc func tick(_: CADisplayLink) {
        effect?.tick()
    }
}
