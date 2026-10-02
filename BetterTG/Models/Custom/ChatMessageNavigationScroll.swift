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
        var corrections = 0
    }

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
        let requestID = attempt?.id
        // Missing UIKit/layout wakeups must not leave a permanent barrier.
        // A deadline reports failure, never successful arrival.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, attempt?.id == requestID else { return }
            finish(.failed)
        }
        layoutDidSettle()
    }

    func cancel() {
        let wasActive = attempt != nil
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
        switch resolution {
        case .missing: finish(.missing)
        case .cancelled: finish(.cancelled)
        case .ready(let target): if isAtTarget(target) { beginChecking() }
        case .deferred: break
        }
    }

    func animationEnded() {
        guard attempt?.command != nil, !issuingCommand else { return }
        receivedEnd = true
        beginChecking()
    }

    private func issue(_ target: Target, animated: Bool) {
        guard let current = attempt, let scrollView else { return }
        stopChecking()
        attempt?.command = UUID()
        receivedEnd = !animated
        issuingCommand = true
        current.onCommand(target, animated)
        guard attempt?.id == current.id else { issuingCommand = false
            return
        }
        scrollView.setContentOffset(target.offset, animated: animated)
        issuingCommand = false
        guard attempt?.id == current.id else { return }
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
        switch resolution {
        case .missing: finish(.missing)
        case .cancelled: finish(.cancelled)
        case .deferred: stopChecking()
        case .ready(let target):
            guard attempt?.id == current.id, attempt?.command == current.command else { return }
            guard let previous = firstOffset, let previousTarget = firstTarget else {
                firstOffset = scrollView.contentOffset
                firstTarget = target.offset
                return
            }
            guard close(previous, scrollView.contentOffset) else {
                // An old end signal must not interrupt a newer moving animation.
                stopChecking()
                receivedEnd = false
                return
            }
            guard close(previousTarget, target.offset) else {
                firstOffset = scrollView.contentOffset
                firstTarget = target.offset
                return
            }
            stopChecking()
            if isAtTarget(target) { finish(.settled) }
            else if receivedEnd {
                guard current.corrections < 2 else { finish(.failed)
                    return
                }
                attempt?.corrections += 1
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
        frameLink?.invalidate()
        frameLink = nil
        frameObserver = nil
        checkCommand = nil
        firstOffset = nil
        firstTarget = nil
    }

    private func finish(_ outcome: Outcome) {
        guard let current = attempt else { return }
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
