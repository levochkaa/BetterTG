// LiquidLens.swift

import UIKit

// MARK: - LiquidLens

/// UIKit's liquid lens: the glass selection that `UISegmentedControl` and the system tab bar lift, carry and
/// stretch, as Telegram 13.2's `LiquidLensView` drives it. UIKit keeps the lens private, so it is reached by name, and
/// `init` fails on a system that lacks the class or one of the selectors used here; the caller then draws a selection
/// of its own.
///
/// The lens goes between two copies of the content, which share one superview: `liftedContent` below it, shown
/// inside the lens, and `punchout` above it, cut away under the lens. While lifted, the lens is drawn in
/// `liftedContainer`, an ancestor that does not clip, so it can grow past the control's capsule. The lens puts its
/// resting selection at the back of `liftedContent`, where it shows in the lens's shape while the lens rests.
///
/// UIKit animates only the lens's material into and out of the lifted state. Everything else is the lens's own:
/// - the hang time (a lens lifts for at least `hangTime`) and the lift's size spring;
/// - the position and the flex (squash, stretch and drift, `LiquidLensFlex`), worked out ahead every 1/120 s
///   (`LiquidLensMotionPlan`) and played as keyframe animations. A move that starts while the lens moves keeps its
///   velocity, and one that starts after the lens followed the finger keeps the finger's. The keyframes start when
///   their transaction commits, as view animations do;
/// - the punch-out, which takes the lens's bounds and keyframes, so the cut follows the glass through size changes.
@MainActor final class LiquidLens {
    /// How far a lifted lens grows past its frame on each side.
    static let liftedOutset: CGFloat = 6

    // MARK: Private

    private static let className = "_UILiquidLensView"
    private static let initializer = "initWithRestingBackground:"
    private static let setters = [
        "setLiftedContainerView:",
        "setLiftedContentView:",
        "setOverridePunchoutView:",
        "setLiftedContentMode:",
        "setStyle:",
        "setWarpsContentBelow:",
        "setLifted:animated:alongsideAnimations:completion:",
    ]

    /// `_UILiquidLensViewLargeVariantSpec` (the lens's style 1): how long a lens stays lifted at least, and the
    /// response of its lift and unlift springs (damping ratio 1).
    private static let hangTime: TimeInterval = 0.22
    private static let liftSpringResponse: TimeInterval = 0.25
    /// The finger's velocity is its displacement over the immediate updates of this long before the move starts; a
    /// longer window than one touch event, because events arrive in bursts after the main thread stalls.
    private static let immediateVelocityWindow = 0.1
    private static let minImmediateVelocityInterval = 0.03
    private static let maxCarriedSpeed: CGFloat = 3000
    /// The resting selection fades this fast as the lens lifts and lowers.
    private static let restingFadeDuration: TimeInterval = 0.2

    // MARK: Internal

    let view: UIView

    // MARK: Private

    /// Cuts `punchout` where the lens is, so that what lies under the glass shows only as the lens's lifted content.
    /// UIKit's own punch-out follows the lens layer's rect through a match-move animation, not the glass UIKit lays
    /// out inside the lens; this one gets the lens's own bounds and animations, so it stays on the glass however it
    /// moves.
    private let punchoutView = UIView()
    /// UIKit puts its punch-out next to the lens's `overridePunchoutView`: this view, in a hidden container, where it
    /// cuts nothing.
    private let uikitPunchoutTargetView = UIView()
    private let uikitPunchoutSinkView = UIView()
    private let restingBackgroundView: LiquidLensRestingBackgroundView

    /// What the caller asked for: the lens's frame, nil while hidden, and whether it is lifted.
    private var frame: CGRect?
    private var isLifted = false

    /// Whether UIKit's lens is lifted: after an unlift is asked for, it stays lifted for the rest of its hang time.
    private var isLensLifted = false
    private var liftTimestamp: CFTimeInterval = 0
    private var unliftTimer: Timer?
    private var pendingUnliftCurve: LiquidLensCurve?

    /// The lens flexes from its lift until its unlift completes, and then settles back.
    private var isFlexActive = false
    /// Whether UIKit's flex is switched off, so this lens flexes itself. Where UIKit's lens has no flex to switch off,
    /// its own flex stays, and a second one on top would bend the glass twice.
    private var flexesItself = false
    private var segment: LiquidLensPositionSegment?
    private var plan: LiquidLensMotionPlan?
    /// The lens's recent immediate positions (the finger's), newest last.
    private var immediatePositions = [(time: Double, position: CGPoint)]()
    /// The plans' time (`lensTime`) is media time less this, so that a plan starts when Core Animation starts playing
    /// it: at the commit of its transaction, which main thread work after a move delays (a folder switch's, 90 ms on
    /// the iPhone Duo simulator). Telegram's keyframes begin at the moment they are planned, and skipped that much of
    /// the move's fast start.
    private var timeOffset: CFTimeInterval = 0
    /// Counts the plans, so that only the current plan's start moves the time.
    private var planID = 0

    /// The lens's centre as it is on screen now, in its superview's coordinates.
    var presentationCenter: CGPoint? {
        guard frame != nil else { return nil }
        return (view.layer.presentation() ?? view.layer).position
    }

    private var lensCenter: CGPoint {
        guard let frame else { return view.center }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: UIKit's lens

    /// `-[_UILiquidLensView _lifted]`, or this lens's own state where UIKit has no such method.
    private var isUIKitLensLifted: Bool {
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let selector = NSSelectorFromString("_lifted")
        guard view.responds(to: selector) else { return isLensLifted }
        return unsafeBitCast(view.method(for: selector), to: Getter.self)(view, selector)
    }

    // MARK: Internal

    /// `isDark` fixes the resting selection's appearance; nil follows the content's trait collection.
    init?(liftedContainer: UIView, liftedContent: UIView, punchout: UIView, isDark: Bool? = nil) {
        guard let container = liftedContent.superview,
              punchout.superview === container,
              let lensClass = NSClassFromString(Self.className) as? UIView.Type,
              (Self.setters + [Self.initializer])
                .allSatisfy({ lensClass.instancesRespond(to: NSSelectorFromString($0)) }),
              let view = Self.make(lensClass)
        else { return nil }
        self.view = view
        self.restingBackgroundView = LiquidLensRestingBackgroundView(isDark: isDark)

        view.isUserInteractionEnabled = false
        // Drawn after the punch-out, which would otherwise cut the lens itself.
        view.layer.zPosition = 10
        container.insertSubview(view, aboveSubview: liftedContent)

        punchoutView.isUserInteractionEnabled = false
        punchoutView.backgroundColor = .black
        punchoutView.layer.compositingFilter = "destOut"
        punchoutView.layer.cornerCurve = .circular
        container.insertSubview(punchoutView, aboveSubview: punchout)
        uikitPunchoutSinkView.isHidden = true
        uikitPunchoutSinkView.isUserInteractionEnabled = false
        uikitPunchoutSinkView.addSubview(uikitPunchoutTargetView)
        container.insertSubview(uikitPunchoutSinkView, aboveSubview: punchoutView)

        restingBackgroundView.frame = liftedContent.bounds
        restingBackgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        liftedContent.insertSubview(restingBackgroundView, at: 0)

        send("setLiftedContainerView:", liftedContainer)
        send("setLiftedContentView:", liftedContent)
        send("setOverridePunchoutView:", uikitPunchoutTargetView)
        send("setLiftedContentMode:", 1)
        send("setStyle:", 1)
        send("setWarpsContentBelow:", true)
        // The lens's flex is `LiquidLensFlex`, planned with its position. UIKit's, which guesses the lens's motion by
        // sampling it, stays attached (the lens activates and deactivates it as it lifts) with nothing to flex from.
        if view.responds(to: NSSelectorFromString("flexInteraction")),
           let flexInteraction = view.value(forKey: "flexInteraction") as? NSObject,
           flexInteraction.responds(to: NSSelectorFromString("setPreferredFlexSources:"))
        {
            flexInteraction.setValue(0 as NSNumber, forKey: "preferredFlexSources")
            self.flexesItself = true
        }
        view.alpha = 0
        punchoutView.alpha = 0
    }

    /// `alloc` hands over an object that `init` consumes, and `init` returns one that is ours.
    private static func make(_ lensClass: UIView.Type) -> UIView? {
        typealias Initialize = @convention(c) (AnyObject, Selector, UIView) -> Unmanaged<UIView>?
        guard let allocated = (lensClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        else { return nil }
        let selector = NSSelectorFromString(initializer)
        let initialize = unsafeBitCast(lensClass.instanceMethod(for: selector), to: Initialize.self)
        return initialize(allocated, selector, UIView())?.takeRetainedValue()
    }

    /// Keyframes a frame apart, played from when their transaction commits.
    private static func keyframeAnimation(
        keyPath: String,
        values: [Any],
        times: [Double],
        duration: Double,
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: min(1, max(0, $0 / duration))) }
        animation.calculationMode = .linear
        animation.duration = duration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = true
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        return animation
    }

    /// Puts the lens over `frame`, or hides it for nil. With a `curve` the lens moves there from where it is on
    /// screen, with its velocity; without one it goes there at once, as a finger carries it. Lowering keeps the lens
    /// lifted until its hang time has passed.
    func place(_ frame: CGRect?, isLifted: Bool, curve: LiquidLensCurve?) {
        guard let frame else {
            guard self.frame != nil else { return }
            self.frame = nil
            self.isLifted = false
            cancelPendingUnlift()
            let hide = {
                self.view.alpha = 0
                self.punchoutView.alpha = 0
            }
            if let curve {
                UIView.animate(
                    withDuration: curve.duration,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: hide,
                )
            } else {
                hide()
            }
            if isLensLifted { setLensLifted(false, curve: nil) }
            return
        }
        let wasHidden = self.frame == nil
        guard wasHidden || isLifted != self.isLifted || frame != self.frame else { return }
        let isRelifted = isLifted && !self.isLifted
        self.frame = frame
        self.isLifted = isLifted
        if isRelifted, isLensLifted {
            // A tap while the last one's hang time runs carries the lens across again, so its hang time starts over;
            // else the lens would lower mid-move. Consecutive lifted updates (a drag) keep it.
            liftTimestamp = CACurrentMediaTime()
        }
        guard !wasHidden else {
            // A hidden lens appears where it is placed.
            let center = CGPoint(x: frame.midX, y: frame.midY)
            segment = .resting(at: center, time: lensTime())
            immediatePositions.removeAll()
            UIView.performWithoutAnimation {
                self.setLensBounds(self.lensBounds(isLifted: self.isLensLifted))
                self.view.center = center
                self.punchoutView.center = center
            }
            updateLens(curve: nil)
            let show = {
                self.view.alpha = 1
                self.punchoutView.alpha = 1
            }
            if let curve {
                UIView.animate(
                    withDuration: curve.duration,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: show,
                )
            } else {
                show()
            }
            return
        }
        updateLens(curve: curve)
    }

    /// Core Animation started playing a plan: from now on its start is when it started.
    fileprivate func planDidStart(_ id: Int, planTime: Double, mediaTime: CFTimeInterval) {
        guard id == planID else { return }
        timeOffset = mediaTime - planTime
    }

    // MARK: Private

    private func updateLens(curve: LiquidLensCurve?) {
        if isLifted {
            cancelPendingUnlift()
            if !isLensLifted {
                setLensLifted(true, curve: curve)
                return
            }
        } else if isLensLifted {
            // UIKit keeps a lens lifted for at least its hang time, so that a tap shows the lift. It is timed here
            // instead of by UIKit's own unlift timer, which would also hold back the lens's frame until it fires.
            let remainingHangTime = liftTimestamp + Self.hangTime - CACurrentMediaTime()
            if curve != nil, remainingHangTime > 0 {
                scheduleUnlift(after: remainingHangTime, curve: curve)
            } else {
                cancelPendingUnlift()
                setLensLifted(false, curve: curve)
                return
            }
        }
        moveLens(curve: curve)
    }

    /// UIKit animates the lens's material into and out of the lifted state; its size and position are animated
    /// here, with UIKit's lift spring for the size. UIKit's `alongsideAnimations` would run them inside its own
    /// spring, or, for an unlift within the hang time, only once its timer fires.
    private func setLensLifted(_ isLifted: Bool, curve: LiquidLensCurve?) {
        let animated = curve != nil
        isLensLifted = isLifted
        var resetsMotion = false
        if isLifted {
            liftTimestamp = CACurrentMediaTime()
            if flexesItself, !isFlexActive {
                isFlexActive = true
                resetsMotion = true
            }
        }
        let completion: @convention(block) () -> Void = { [weak self] in
            // UIKit deactivates the lens's flex when the unlift completes.
            guard let self, !isLensLifted else { return }
            setFlexActive(false)
        }
        if isUIKitLensLifted != isLifted {
            setUIKitLensLifted(isLifted, animated: animated, completion: completion)
        } else {
            // Already in that state (UIKit lowers a lens that leaves its window); UIKit would not call the completion.
            completion()
        }

        let bounds = lensBounds(isLifted: isLifted)
        if animated {
            // Inside a view animation the lens lays its glass out along with its bounds.
            UIView.animate(
                springDuration: Self.liftSpringResponse,
                bounce: 0,
                initialSpringVelocity: 0,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: { self.setLensBounds(bounds) },
            )
        } else {
            setLensBounds(bounds)
        }
        let resetsFlex = !animated && !isLifted
        if resetsFlex { isFlexActive = false }
        // The flex depends on the lens's size, so it is planned again also when the lens stays where it is.
        setLensPosition(
            lensCenter,
            curve: curve,
            replans: true,
            resetsMotion: resetsMotion,
            resetsFlex: resetsFlex,
        )
        updateRestingBackground(animated: animated)
    }

    private func scheduleUnlift(after delay: TimeInterval, curve: LiquidLensCurve?) {
        pendingUnliftCurve = curve
        guard unliftTimer == nil else { return }
        // A frame later than the hang time, so that UIKit, which measures it from its own lift, lowers at once.
        let timer = Timer(timeInterval: delay + 1.0 / 120.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.unliftTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        unliftTimer = timer
    }

    private func unliftTimerFired() {
        unliftTimer = nil
        let curve = pendingUnliftCurve ?? .default
        pendingUnliftCurve = nil
        guard frame != nil, !isLifted, isLensLifted else { return }
        setLensLifted(false, curve: curve)
    }

    private func cancelPendingUnlift() {
        unliftTimer?.invalidate()
        unliftTimer = nil
        pendingUnliftCurve = nil
    }

    private func lensBounds(isLifted: Bool) -> CGRect {
        guard let frame else { return view.bounds }
        let outset = isLifted ? Self.liftedOutset : 0
        return CGRect(origin: .zero, size: frame.insetBy(dx: -outset, dy: -outset).size)
    }

    /// The lens's size, and the punch-out's with it: inside a view animation, both animate along with the glass
    /// that UIKit lays out inside the lens.
    private func setLensBounds(_ bounds: CGRect) {
        view.bounds = bounds
        punchoutView.bounds = bounds
        punchoutView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func moveLens(curve: LiquidLensCurve?) {
        let bounds = lensBounds(isLifted: isLensLifted)
        let previousBounds = view.bounds
        if previousBounds != bounds {
            // The lens lays its glass out inside this animation, so the lens, its glass and the punch-out change size
            // together, centred on the lens's path.
            animate(curve) { self.setLensBounds(bounds) }
        }
        setLensPosition(lensCenter, curve: curve, replans: previousBounds != bounds)
    }

    /// Runs `changes` as a view animation along `curve`, or at once without one.
    private func animate(_ curve: LiquidLensCurve?, _ changes: @escaping () -> Void) {
        switch curve {
        case nil:
            changes()
        case .bezier(let duration, let x1, let y1, let x2, let y2):
            let animator = UIViewPropertyAnimator(
                duration: duration,
                controlPoint1: CGPoint(x: x1, y: y1),
                controlPoint2: CGPoint(x: x2, y: y2),
                animations: changes,
            )
            animator.isUserInteractionEnabled = true
            animator.startAnimation()
        case .spring(let duration, let bounce):
            UIView.animate(
                springDuration: duration,
                bounce: bounce,
                initialSpringVelocity: 0,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes,
            )
        }
    }

    /// Moves the lens's glass to `center` from where it is now, along `curve`, so that it stays in step with content
    /// animated along the same curve, and plans the flex of that move. An interrupted move continues from its current
    /// position with its current velocity, and the flex from its current state.
    private func setLensPosition(
        _ center: CGPoint,
        curve: LiquidLensCurve?,
        replans: Bool,
        resetsMotion: Bool = false,
        resetsFlex: Bool = false,
    ) {
        let now = lensTime()
        var movesLens = false
        if segment?.to != center {
            let current = segment?.position(at: now) ?? view.center
            let segment: LiquidLensPositionSegment
            if let curve, current != center {
                segment = LiquidLensPositionSegment(
                    from: current,
                    to: center,
                    startTime: now,
                    duration: curve.duration,
                    progress: curve.makeProgress(),
                    initialVelocity: lensVelocity(at: now),
                )
                immediatePositions.removeAll()
            } else {
                segment = .resting(at: center, time: now)
                immediatePositions.append((now, center))
                immediatePositions.removeAll { now - $0.time > Self.immediateVelocityWindow }
            }
            self.segment = segment
            UIView.performWithoutAnimation {
                self.view.center = center
                self.punchoutView.center = center
            }
            movesLens = true
        }
        if movesLens || replans {
            replanLens(now: now, resetsMotion: resetsMotion, resetsFlex: resetsFlex)
        }
    }

    /// How fast the lens moves at `time`: along its current move, or, right after it followed the finger, as fast
    /// as the finger moved it. A new move starts with this velocity.
    private func lensVelocity(at time: Double) -> CGPoint {
        var velocity = CGPoint.zero
        if let segment, time < segment.endTime {
            velocity = segment.velocity(at: time)
        } else {
            let recent = immediatePositions.filter { time - $0.time <= Self.immediateVelocityWindow }
            if let first = recent.first, let last = recent.last, recent.count > 1,
               time - last.time <= Self.immediateVelocityWindow / 2
            {
                // Over at least a few frames, so that a lone jump (a relayout) or a burst of events is not a speed.
                let interval = CGFloat(max(last.time - first.time, Self.minImmediateVelocityInterval))
                velocity = CGPoint(
                    x: (last.position.x - first.position.x) / interval,
                    y: (last.position.y - first.position.y) / interval,
                )
            }
        }
        let speed = hypot(velocity.x, velocity.y)
        if speed > Self.maxCarriedSpeed {
            velocity = CGPoint(
                x: velocity.x * Self.maxCarriedSpeed / speed,
                y: velocity.y * Self.maxCarriedSpeed / speed,
            )
        }
        return velocity
    }

    private func setFlexActive(_ isActive: Bool) {
        guard isFlexActive != isActive else { return }
        isFlexActive = isActive
        replanLens(now: lensTime(), resetsMotion: isActive)
    }

    /// Plans the lens from where the current plan has it and hands the plan to Core Animation, for the lens and its
    /// punch-out alike.
    private func replanLens(now: Double, resetsMotion: Bool = false, resetsFlex: Bool = false) {
        let segment = segment ?? .resting(at: view.center, time: now)
        var start = plan?.state(at: now) ?? LiquidLensMotionState(time: now)
        start.time = now
        if resetsMotion { start.motion = LiquidLensMotion() }
        if resetsFlex { start.animator.reset() }
        let plan = LiquidLensMotionPlan(
            start: start,
            segment: segment,
            isFlexActive: isFlexActive,
            size: view.bounds.size,
        )
        self.plan = plan

        let positionKeyframes = plan.positionKeyframes
        planID += 1
        let startObserver = LiquidLensPlanStartObserver(lens: self, planID: planID, planTime: plan.startTime)
        for layer in [view.layer, punchoutView.layer] {
            if positionKeyframes.count > 1, let duration = positionKeyframes.last?.time, duration > 0 {
                let animation = Self.keyframeAnimation(
                    keyPath: "position",
                    values: positionKeyframes.map { NSValue(cgPoint: $0.position) },
                    times: positionKeyframes.map(\.time),
                    duration: duration,
                )
                if layer === view.layer { animation.delegate = startObserver }
                layer.add(animation, forKey: "liquidLensPosition")
            } else {
                layer.removeAnimation(forKey: "liquidLensPosition")
            }
            if plan.hasFlex, plan.endTime > plan.startTime {
                let animation = Self.keyframeAnimation(
                    keyPath: "transform",
                    values: plan.states.map { NSValue(caTransform3D: $0.animator.flex.transform) },
                    times: plan.states.map { $0.time - plan.startTime },
                    duration: plan.endTime - plan.startTime,
                )
                if layer === view.layer { animation.delegate = startObserver }
                layer.add(animation, forKey: "liquidLensFlex")
            } else {
                layer.removeAnimation(forKey: "liquidLensFlex")
            }
        }
    }

    /// The time the plans are made in.
    private func lensTime() -> Double {
        CACurrentMediaTime() - timeOffset
    }

    /// The resting selection shows while the lens rests: hidden while it is lifted, which lasts until the lens
    /// really lowers, after its hang time.
    private func updateRestingBackground(animated: Bool) {
        let alpha: CGFloat = isLensLifted ? 0 : 1
        guard restingBackgroundView.alpha != alpha else { return }
        guard animated else {
            restingBackgroundView.alpha = alpha
            return
        }
        UIView.animate(
            withDuration: Self.restingFadeDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
        ) {
            self.restingBackgroundView.alpha = alpha
        }
    }

    private func setUIKitLensLifted(
        _ isLifted: Bool,
        animated: Bool,
        completion: @escaping @convention(block) () -> Void,
    ) {
        typealias SetLifted = @convention(c) (
            AnyObject,
            Selector,
            Bool,
            Bool,
            @escaping @convention(block) () -> Void,
            (@convention(block) () -> Void)?,
        ) -> Void
        let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
        let setLifted = unsafeBitCast(view.method(for: selector), to: SetLifted.self)
        // The size and position are animated here, but UIKit gets a block, as UIKit's own callers pass: whether every
        // version accepts none is not known.
        setLifted(view, selector, isLifted, animated, {}, completion)
    }

    private func send(_ name: String, _ object: AnyObject) {
        typealias Set = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let selector = NSSelectorFromString(name)
        unsafeBitCast(view.method(for: selector), to: Set.self)(view, selector, object)
    }

    private func send(_ name: String, _ value: Int) {
        typealias Set = @convention(c) (AnyObject, Selector, Int) -> Void
        let selector = NSSelectorFromString(name)
        unsafeBitCast(view.method(for: selector), to: Set.self)(view, selector, value)
    }

    private func send(_ name: String, _ value: Bool) {
        typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Void
        let selector = NSSelectorFromString(name)
        unsafeBitCast(view.method(for: selector), to: Set.self)(view, selector, value)
    }
}

// MARK: - LiquidLensPlanStartObserver

/// Tells the lens when Core Animation starts playing a plan. An animation keeps its delegate alive, so this holds the
/// lens weakly.
@MainActor private final class LiquidLensPlanStartObserver: NSObject, @MainActor CAAnimationDelegate {
    private weak var lens: LiquidLens?
    private let planID: Int
    private let planTime: Double
    private var hasStarted = false

    init(lens: LiquidLens, planID: Int, planTime: Double) {
        self.lens = lens
        self.planID = planID
        self.planTime = planTime
    }

    func animationDidStart(_ animation: CAAnimation) {
        // The position and the flex start together; the first to report stands for both.
        guard !hasStarted else { return }
        hasStarted = true
        let mediaTime = animation.beginTime > 0 ? lens?.view.layer.convertTime(animation.beginTime, to: nil) : nil
        lens?.planDidStart(planID, planTime: planTime, mediaTime: mediaTime ?? CACurrentMediaTime())
    }
}

// MARK: - LiquidLensRestingBackgroundView

/// The lens's resting selection, as UIKit's `_UITabSelectionView` draws it on iOS 27 (its `updateBackground` when the
/// platform metrics give no selection colour, as the glass tab bar's do): the backdrop captured at a quarter of the
/// resolution, in a backdrop group of its own, blurred by 2 with normalized edges, then through a colour matrix.
/// Ported from Telegram 13.2's `RestingBackgroundView`.
private final class LiquidLensRestingBackgroundView: UIVisualEffectView {
    // MARK: Private

    private let fixedIsDark: Bool?
    private var appliedIsDark: Bool?

    private var groupName: String {
        "LiquidLensRestingBackground-\(UInt(bitPattern: ObjectIdentifier(self)))"
    }

    // MARK: Internal

    init(isDark: Bool?) {
        self.fixedIsDark = isDark
        super.init(effect: UIBlurEffect(style: .light))
        for subview in subviews where subview.description.contains("VisualEffectSubview") {
            subview.isHidden = true
        }
        isUserInteractionEnabled = false
        clipsToBounds = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _: UITraitCollection) in
            view.applyFilters()
        }
        applyFilters()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyFilters()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFilters()
    }

    // MARK: Private

    /// `_ColorMatrix.YCC(black:white:saturation:hue:).colorMatrix` (DesignLibrary), as `currentColorMatrixValue`
    /// builds it: light YCC(-0.2, 0.93, 1.2, 0), dark YCC(-0.07, 0.8, 1.2, 0), computed by calling DesignLibrary in
    /// the iOS 27 simulator.
    private static func colorMatrix(isDark: Bool) -> [Float32] {
        if isDark {
            [
                1.1298, -0.2361, -0.0237, 0, -0.07,
                -0.0701, 0.964, -0.0238, 0, -0.07,
                -0.0702, -0.236, 1.1762, 0, -0.07,
                0, 0, 0, 1, 0,
            ]
        } else {
            [
                1.1851, -0.0502, -0.005, 0, -0.2,
                -0.0149, 1.1499, -0.0051, 0, -0.2,
                -0.0149, -0.05, 1.1949, 0, -0.2,
                0, 0, 0, 1, 0,
            ]
        }
    }

    private static func filter(named name: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol else { return nil }
        let selector = NSSelectorFromString("filterWithName:")
        guard filterClass.responds(to: selector) else { return nil }
        return filterClass.perform(selector, with: name)?.takeUnretainedValue() as? NSObject
    }

    /// Puts the filters on the backdrop layer again whenever the appearance changes or UIKit has reset them.
    private func applyFilters() {
        let isDark = fixedIsDark ?? (traitCollection.userInterfaceStyle == .dark)
        guard let backdrop = layer.sublayers?.first, backdrop.filters != nil else { return }
        let groupName = groupName
        if appliedIsDark == isDark, backdrop.value(forKey: "groupName") as? String == groupName { return }
        guard let blur = Self.filter(named: "gaussianBlur"), let colorMatrix = Self.filter(named: "colorMatrix")
        else { return }
        appliedIsDark = isDark
        backdrop.backgroundColor = nil
        backdrop.isOpaque = false
        blur.setValue(2.0 as NSNumber, forKey: "inputRadius")
        blur.setValue(true as NSNumber, forKey: "inputNormalizeEdges")
        var matrix = Self.colorMatrix(isDark: isDark)
        colorMatrix.setValue(
            NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"),
            forKey: "inputColorMatrix",
        )
        backdrop.filters = [blur, colorMatrix]
        backdrop.setValue(0.25 as NSNumber, forKey: "scale")
        backdrop.setValue(groupName, forKey: "groupName")
    }
}

// MARK: - LiquidLensTabRecognizer

/// Telegram's TabSelectionRecognizer: begins as soon as a finger touches a lens's tabs, so the lens lifts and comes
/// to the finger before it moves, where a long press would wait out its duration and a pan would wait for movement.
/// Beginning, it cancels the tabs' own touches, so a tap selects through it too.
final class LiquidLensTabRecognizer: UIGestureRecognizer {
    /// Where the finger touched down, in the window.
    private var initialLocation: CGPoint?

    /// How far the finger has moved since it touched down.
    var translation: CGPoint {
        guard let initialLocation else { return .zero }
        let location = location(in: nil)
        return CGPoint(x: location.x - initialLocation.x, y: location.y - initialLocation.y)
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func reset() {
        super.reset()
        initialLocation = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if initialLocation == nil { initialLocation = touches.first?.location(in: nil) }
        state = state == .possible ? .began : .changed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }
}
