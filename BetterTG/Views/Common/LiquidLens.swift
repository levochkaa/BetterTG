// LiquidLens.swift

import UIKit

// MARK: - LiquidLens

/// UIKit's liquid lens: the glass selection that `UISegmentedControl` and the system tab bar lift, carry and
/// stretch. UIKit keeps it private, so it is reached by name, the way Telegram's `LiquidLensView`
/// reaches it, and `init` fails on a system that lacks the class or one of the selectors used here; the caller
/// then draws a selection of its own.
///
/// The lens goes between two copies of the content, which share one superview: `liftedContent` below it,
/// shown inside the lens, and `punchout` above it, cut away under the lens. While lifted, the lens is drawn
/// in `liftedContainer`, an ancestor that does not clip, so it can grow past the control's capsule.
/// The lens draws no background of its own at rest: the selected segment's background belongs in
/// `liftedContent`, where the lens shows it in its shape.
@MainActor final class LiquidLens {
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

    /// How far a lifted lens grows past its frame on each side.
    private static let liftedOutset: CGFloat = 6

    // MARK: Internal

    let view: UIView

    // MARK: Private

    private var frame: CGRect?
    private var isLifted = false
    private var displayLink: CADisplayLink?

    // MARK: Internal

    init?(liftedContainer: UIView, liftedContent: UIView, punchout: UIView) {
        guard let container = liftedContent.superview,
              punchout.superview === container,
              let lensClass = NSClassFromString(Self.className) as? UIView.Type,
              (Self.setters + [Self.initializer])
                .allSatisfy({ lensClass.instancesRespond(to: NSSelectorFromString($0)) }),
              let view = Self.make(lensClass)
        else { return nil }
        self.view = view
        view.isUserInteractionEnabled = false
        view.layer.zPosition = 10
        container.insertSubview(view, aboveSubview: liftedContent)
        send("setLiftedContainerView:", liftedContainer)
        send("setLiftedContentView:", liftedContent)
        send("setOverridePunchoutView:", punchout)
        send("setLiftedContentMode:", 1)
        send("setStyle:", 1)
        send("setWarpsContentBelow:", true)
        view.alpha = 0
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

    /// Puts the lens over `frame`, or hides it for `nil`. With a `springDuration` the lens springs there from
    /// where it is on screen; without one it jumps.
    func place(_ frame: CGRect?, isLifted: Bool, springDuration: TimeInterval?) {
        guard let frame else {
            guard self.frame != nil else { return }
            self.frame = nil
            animate(springDuration) { self.view.alpha = 0 }
            updateDisplayLink()
            return
        }
        let wasHidden = self.frame == nil
        let isLiftChanged = isLifted != self.isLifted
        guard wasHidden || isLiftChanged || frame != self.frame else { return }
        self.frame = frame
        self.isLifted = isLifted
        if wasHidden {
            view.layer.removeAllAnimations()
            applyBounds()
            applyCenter()
            animate(springDuration) { self.view.alpha = 1 }
        }
        // UIKit resizes the lens alongside its lift; until it does, the lens takes its size here.
        let isResizedByLift = isLiftChanged && setLifted(isLifted, animated: springDuration != nil && !wasHidden)
        let move = {
            if !isResizedByLift { self.applyBounds() }
            self.applyCenter()
        }
        if let springDuration {
            animate(springDuration, move)
        } else {
            view.layer.removeAllAnimations()
            move()
        }
        updateDisplayLink()
    }

    fileprivate func step() {
        guard let frame else { return }
        view.center = CGPoint(x: frame.midX, y: frame.midY)
    }

    private func applyBounds() {
        guard let frame else { return }
        let outset = isLifted ? Self.liftedOutset : 0
        view.bounds = CGRect(origin: .zero, size: frame.insetBy(dx: -outset, dy: -outset).size)
    }

    private func applyCenter() {
        guard let frame else { return }
        view.center = CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Lifts or lowers the lens and reports whether UIKit has already resized it alongside.
    private func setLifted(_ isLifted: Bool, animated: Bool) -> Bool {
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
        var isResized = false
        setLifted(view, selector, isLifted, animated, { [weak self] in
            isResized = true
            self?.applyBounds()
        }, nil)
        return isResized
    }

    private func animate(_ springDuration: TimeInterval?, _ changes: @escaping () -> Void) {
        guard let springDuration else {
            changes()
            return
        }
        UIView.animate(
            springDuration: springDuration,
            bounce: 0.15,
            initialSpringVelocity: 0,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes,
        )
    }

    /// A lifted lens wobbles only while it is being moved, so it is moved to where it already is on every frame.
    private func updateDisplayLink() {
        if isLifted, frame != nil {
            guard displayLink == nil else { return }
            let link = CADisplayLink(
                target: LiquidLensDisplayLinkTarget(lens: self),
                selector: #selector(LiquidLensDisplayLinkTarget.step(_:)),
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
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

// MARK: - LiquidLensDisplayLinkTarget

/// Holds the lens weakly: a display link keeps its target alive until it is invalidated.
@MainActor private final class LiquidLensDisplayLinkTarget: NSObject {
    private weak var lens: LiquidLens?

    init(lens: LiquidLens) {
        self.lens = lens
    }

    @objc func step(_ link: CADisplayLink) {
        guard let lens else {
            link.invalidate()
            return
        }
        lens.step()
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
