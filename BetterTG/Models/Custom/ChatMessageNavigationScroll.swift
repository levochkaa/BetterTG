// ChatMessageNavigationScroll.swift

import UIKit

/// An explicit target owns the viewport until its current geometry has settled.
/// Native animation-end is also emitted by interruption, so it is only a wakeup.
@MainActor final class ChatMessageNavigationScroll {
    struct Target {
        let offset: CGPoint
        let isVisible: Bool
    }

    enum Resolution { case deferred, missing, cancelled, ready(Target) }
    enum Outcome: Equatable { case settled, missing, failed, cancelled }

    /// Estimated neighboring cells may require more than two layout passes.
    /// Continue only while stable residuals converge (one stalled pass may retry),
    /// with an independent command cap and the request's failure-only deadline.
    struct CorrectionBudget {
        static let maximum = 8

        private(set) var count = 0

        private var previousError: CGFloat?
        private var stalledPasses = 0

        mutating func admit(error: CGFloat) -> Bool {
            guard error.isFinite, error > 0.75, count < Self.maximum else { return false }
            if let previousError {
                stalledPasses = error < previousError - 0.75 ? 0 : stalledPasses + 1
            }
            guard stalledPasses < 2 else { return false }
            previousError = error
            count += 1
            return true
        }
    }

    @MainActor private final class FrameObserver: NSObject {
        weak var owner: ChatMessageNavigationScroll?

        @objc func frame() { owner?.verifyFrame() }
    }

    private struct Attempt {
        let id = UUID()
        let animated: Bool
        let resolve: () -> Resolution
        let onCommand: (Target, Bool) -> Void
        let completion: (Outcome) -> Void
        var command: UUID?
        var commandAnimated = false
        var corrections = CorrectionBudget()
    }

    #if DEBUG
        /// Enabled only by the isolated native probe. Retain values, not layout
        /// callbacks: observing this trace must not resolve or lay out a target.
        var debugTracingEnabled = false

        private struct DebugEvent {
            let elapsed: CFTimeInterval
            let event: String
            let resolution: String
            let target: Target?
            let offset: CGPoint?
            let bounds: CGRect?
            let contentSize: CGSize?
            let inset: UIEdgeInsets?
            let receivedEnd: Bool
            let issuing: Bool
            let checking: Bool
            let commandAnimated: Bool?
            let corrections: Int
            let firstOffset: CGPoint?
            let firstTarget: CGPoint?
            let tracking: Bool
            let dragging: Bool
            let decelerating: Bool
        }

        private var debugStartedAt: CFTimeInterval = 0
        private var debugEvents = [DebugEvent]()
        private var debugDroppedEvents = 0
        private var debugLastResolution = "none"
        private var debugLastTarget: Target?
        private var debugFailureReason: String?
        private var debugOutcome: Outcome?
        private var debugCommands = [Bool]()
        private var debugNativeEnds = 0

        var debugReport: String {
            guard debugTracingEnabled else { return "driver-trace=disabled" }
            let summary = "driver outcome=\(String(describing: debugOutcome)) failure=\(debugFailureReason ?? "none")"
                + " commands=\(debugCommands) nativeEnds=\(debugNativeEnds) dropped=\(debugDroppedEvents)"
            return ([summary] + debugEvents.map { event in
                let error = event.offset.flatMap { offset in event.target.map {
                    CGPoint(x: offset.x - $0.offset.x, y: offset.y - $0.offset.y)
                } }
                return "t=\(event.elapsed) event=\(event.event) resolution=\(event.resolution)"
                    + " target=\(String(describing: event.target?.offset)) visible=\(String(describing: event.target?.isVisible))"
                    + " error=\(String(describing: error)) offset=\(String(describing: event.offset))"
                    + " bounds=\(String(describing: event.bounds)) size=\(String(describing: event.contentSize))"
                    + " inset=\(String(describing: event.inset)) end=\(event.receivedEnd) issuing=\(event.issuing)"
                    + " checking=\(event.checking) animated=\(String(describing: event.commandAnimated)) corrections=\(event.corrections)"
                    + " firstOffset=\(String(describing: event.firstOffset)) firstTarget=\(String(describing: event.firstTarget))"
                    + " tracking=\(event.tracking) dragging=\(event.dragging) decelerating=\(event.decelerating)"
            }).joined(separator: "\n")
        }

        private func debugRecord(_ event: String, resolution: Resolution? = nil, target: Target? = nil) {
            guard debugTracingEnabled else { return }
            if let resolution {
                switch resolution {
                case .ready(let value): debugLastResolution = "ready"
                debugLastTarget = value
                case .deferred: debugLastResolution = "deferred"
                case .missing: debugLastResolution = "missing"
                case .cancelled: debugLastResolution = "cancelled"
                }
            }
            if let target { debugLastTarget = target }
            if debugEvents.count == 192 {
                debugEvents.removeFirst()
                debugDroppedEvents += 1
            }
            debugEvents.append(.init(
                elapsed: CACurrentMediaTime() - debugStartedAt, event: event,
                resolution: debugLastResolution, target: debugLastTarget,
                offset: scrollView?.contentOffset, bounds: scrollView?.bounds,
                contentSize: scrollView?.contentSize, inset: scrollView?.adjustedContentInset,
                receivedEnd: receivedEnd, issuing: issuingCommand, checking: frameLink != nil,
                commandAnimated: attempt?.command == nil ? nil : attempt?.commandAnimated,
                corrections: attempt?.corrections.count ?? 0, firstOffset: firstOffset, firstTarget: firstTarget,
                tracking: scrollView?.isTracking ?? false, dragging: scrollView?.isDragging ?? false,
                decelerating: scrollView?.isDecelerating ?? false,
            ))
        }
    #endif

    private weak var scrollView: UIScrollView?
    private var attempt: Attempt?
    private var issuingCommand = false
    private var receivedEnd = false
    private var frameObserver: FrameObserver?
    private var frameLink: CADisplayLink?
    private var checkCommand: UUID?
    private var firstOffset: CGPoint?
    private var firstTarget: CGPoint?
    private var generation = UInt64.zero

    var ownsViewport: Bool { attempt != nil }

    isolated deinit { frameLink?.invalidate() }

    func start(
        scrollView: UIScrollView,
        animated: Bool,
        resolve: @escaping () -> Resolution,
        onCommand: @escaping (Target, Bool) -> Void = { _, _ in },
        completion: @escaping (Outcome) -> Void,
    ) {
        cancel()
        self.scrollView = scrollView
        attempt = Attempt(animated: animated, resolve: resolve, onCommand: onCommand, completion: completion)
        #if DEBUG
            if debugTracingEnabled {
                debugStartedAt = CACurrentMediaTime()
                debugEvents.removeAll(keepingCapacity: true)
                debugDroppedEvents = 0
                debugLastResolution = "none"
                debugLastTarget = nil
                debugFailureReason = nil
                debugOutcome = nil
                debugCommands.removeAll(keepingCapacity: true)
                debugNativeEnds = 0
                debugRecord("start")
            }
        #endif
        let requestID = attempt?.id
        // Missing UIKit/layout wakeups must not leave a permanent barrier.
        // A deadline reports failure, never successful arrival.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, attempt?.id == requestID else { return }
            #if DEBUG
                if debugTracingEnabled { debugFailureReason = "deadline"
                debugRecord("deadline")
                }
            #endif
            finish(.failed)
        }
        layoutDidSettle()
    }

    func cancel() {
        let wasActive = attempt != nil
        #if DEBUG
            if wasActive { debugOutcome = .cancelled
            debugRecord("cancel")
            }
        #endif
        generation &+= 1
        attempt = nil
        stopChecking()
        receivedEnd = false
        // Retire first: stopping a native animation may synchronously emit end.
        if wasActive, let scrollView {
            scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        }
    }

    func layoutDidSettle() {
        guard let current = attempt, !issuingCommand else { return }
        let resolution = current.resolve()
        guard attempt?.id == current.id else { return }
        #if DEBUG
            debugRecord("layout", resolution: resolution)
        #endif
        switch resolution {
        case .missing: finish(.missing)
        case .cancelled: finish(.cancelled)
        case .deferred: break
        case .ready(let target):
            guard attempt?.id == current.id else { return }
            if current.command == nil { issue(target, animated: current.animated) }
            else if receivedEnd || isAtTarget(target) { beginChecking() }
        }
    }

    func didScroll() {
        guard !issuingCommand, let current = attempt, current.command != nil else { return }
        let resolution = current.resolve()
        guard attempt?.id == current.id else { return }
        #if DEBUG
            debugRecord("scroll", resolution: resolution)
        #endif
        switch resolution {
        case .missing: finish(.missing)
        case .cancelled: finish(.cancelled)
        case .ready(let target): if isAtTarget(target) { beginChecking() }
        case .deferred: break
        }
    }

    func animationEnded() {
        #if DEBUG
            if debugTracingEnabled { debugNativeEnds += 1
            debugRecord("native-end")
            }
        #endif
        guard attempt?.command != nil, !issuingCommand else { return }
        receivedEnd = true
        #if DEBUG
            debugRecord("native-end-accepted")
        #endif
        beginChecking()
    }

    private func issue(_ target: Target, animated: Bool) {
        guard let current = attempt, let scrollView else { return }
        stopChecking()
        attempt?.command = UUID()
        attempt?.commandAnimated = animated
        receivedEnd = !animated
        issuingCommand = true
        #if DEBUG
            if debugTracingEnabled { debugCommands.append(animated)
            debugRecord("command", target: target)
            }
        #endif
        current.onCommand(target, animated)
        guard attempt?.id == current.id else { issuingCommand = false
            return
        }
        scrollView.setContentOffset(target.offset, animated: animated)
        issuingCommand = false
        guard attempt?.id == current.id else { return }
        #if DEBUG
            debugRecord("command-returned")
        #endif
        if receivedEnd || isAtTarget(target) { beginChecking() }
    }

    private func beginChecking() {
        guard frameLink == nil, let command = attempt?.command else { return }
        checkCommand = command
        firstOffset = nil
        firstTarget = nil
        let observer = FrameObserver()
        observer.owner = self
        let link = CADisplayLink(target: observer, selector: #selector(FrameObserver.frame))
        frameObserver = observer
        frameLink = link
        link.add(to: .main, forMode: .common)
        #if DEBUG
            debugRecord("checking-began")
        #endif
    }

    private func verifyFrame() {
        guard let current = attempt, current.command == checkCommand, let scrollView else {
            stopChecking()
            return
        }
        guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else {
            finish(.cancelled)
            return
        }
        let resolution = current.resolve()
        guard attempt?.id == current.id, attempt?.command == current.command else { return }
        #if DEBUG
            debugRecord("frame", resolution: resolution)
        #endif
        switch resolution {
        case .missing: finish(.missing)
        case .cancelled: finish(.cancelled)
        case .deferred: stopChecking()
        case .ready(let target):
            guard attempt?.id == current.id, attempt?.command == current.command else { return }
            guard let previous = firstOffset, let previousTarget = firstTarget else {
                firstOffset = scrollView.contentOffset
                firstTarget = target.offset
                #if DEBUG
                    debugRecord("first-frame")
                #endif
                return
            }
            guard close(previous, scrollView.contentOffset) else {
                if !current.commandAnimated {
                    // Self-sizing can adjust contentOffset after a synchronous
                    // correction. This is not a newer native animation/end pair.
                    firstOffset = scrollView.contentOffset
                    firstTarget = target.offset
                    #if DEBUG
                        debugRecord("synchronous-offset-moved")
                    #endif
                    return
                }
                // An old end signal must not interrupt a newer moving animation.
                stopChecking()
                receivedEnd = false
                #if DEBUG
                    debugRecord("animated-offset-moved-reset-end")
                #endif
                return
            }
            guard close(previousTarget, target.offset) else {
                firstOffset = scrollView.contentOffset
                firstTarget = target.offset
                #if DEBUG
                    debugRecord("target-moved")
                #endif
                return
            }
            stopChecking()
            if isAtTarget(target) { finish(.settled) }
            else if receivedEnd {
                let error = max(
                    abs(scrollView.contentOffset.x - target.offset.x),
                    abs(scrollView.contentOffset.y - target.offset.y),
                )
                guard attempt?.corrections.admit(error: error) == true else {
                    #if DEBUG
                        if debugTracingEnabled {
                            debugFailureReason = "correction-budget"
                            debugRecord("correction-rejected")
                        }
                    #endif
                    finish(.failed)
                    return
                }
                #if DEBUG
                    debugRecord("correction-admitted")
                #endif
                issue(target, animated: false)
            }
        }
    }

    private func isAtTarget(_ target: Target) -> Bool {
        guard let scrollView else { return false }
        return target.isVisible && close(scrollView.contentOffset, target.offset)
    }

    private func close(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 0.75 && abs(lhs.y - rhs.y) <= 0.75
    }

    private func stopChecking() {
        #if DEBUG
            if frameLink != nil { debugRecord("checking-stopped") }
        #endif
        frameLink?.invalidate()
        frameLink = nil
        frameObserver = nil
        checkCommand = nil
        firstOffset = nil
        firstTarget = nil
    }

    private func finish(_ outcome: Outcome) {
        guard let current = attempt else { return }
        #if DEBUG
            if debugTracingEnabled { debugOutcome = outcome
            debugRecord("finish")
            }
        #endif
        // The consumer retires its raw target before native stop can reenter it.
        attempt = nil
        generation &+= 1
        let retiredGeneration = generation
        stopChecking()
        receivedEnd = false
        current.completion(outcome)
        guard generation == retiredGeneration, attempt == nil, let scrollView else { return }
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }
}
