// StickerPeekGestureRecognizer.swift

import TDLibKit
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - StickerPeekContent

/// What StickerPreviewPeekContent shows for the sticker under the finger: the sticker, the cell it grows out of and
/// returns to, and its menu.
struct StickerPeekContent {
    let sticker: Sticker
    let client: TDLibClient
    let sourceView: UIView
    let actions: [TelegramContextMenuAction]

    /// StickerPreviewPeekContent.isEqual: the same sticker file.
    func showsSameSticker(as other: StickerPeekContent) -> Bool {
        sticker.sticker.id == other.sticker.sticker.id
    }
}

// MARK: - StickerPeekGestureRecognizer

/// PeekControllerGestureRecognizer with StickerPreviewPeekContent's `.press` menu activation. Holding a sticker for
/// 0.4 s opens its preview; holding on for a second, with every move past 3 points restarting the wait, opens its
/// menu. Until then the finger slides over other stickers to preview them instead, and once the menu is open it
/// picks an item. Lifting the finger before the menu opens puts the sticker back.
final class StickerPeekGestureRecognizer: UIGestureRecognizer {
    // MARK: Private

    /// PeekControllerGestureRecognizer's tolerance before the preview opens, and between its menu waits.
    private static let moveTolerance: CGFloat = 3
    /// The pressure that opens the menu at once on a 3D Touch screen.
    private static let menuForce: CGFloat = 2.5

    // MARK: Internal

    /// The sticker under a point in the recognizer's view; nil where there is none.
    var contentAtPoint: ((CGPoint) -> StickerPeekContent?)?

    private var trackedTouch: UITouch?
    private var tapLocation: CGPoint?
    private var longTapTask: Task<Void, Never>?
    private var pressTask: Task<Void, Never>?
    private var candidate: StickerPeekContent?
    /// `menuActivation == .press`: the preview is open and its menu still waits for the held second.
    private var awaitsMenu = false
    private weak var peekView: StickerPeekView?

    override func reset() {
        super.reset()
        stopTimers()
        trackedTouch = nil
        tapLocation = nil
        candidate = nil
        awaitsMenu = false
        peekView = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard trackedTouch == nil else {
            // The preview follows the finger that opened it.
            if peekView == nil {
                state = .failed
            } else {
                for touch in touches {
                    ignore(touch, for: event)
                }
            }
            return
        }
        guard let view, touches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }
        let location = touch.location(in: view)
        // A touch that stops a scrolling list doesn't preview.
        guard !Self.hasDeceleratingScrollView(view, at: location) else {
            state = .failed
            return
        }
        trackedTouch = touch
        tapLocation = location
        startLongTapTimer()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let view, let touch = trackedTouch, touches.contains(touch), let initialLocation = tapLocation
        else { return }
        let location = touch.location(in: view)
        let movedAway = hypot(location.x - initialLocation.x, location.y - initialLocation.y) > Self.moveTolerance
        guard let peekView else {
            if movedAway {
                stopTimers()
                tapLocation = nil
                state = .failed
            }
            return
        }
        if awaitsMenu {
            if touch.force >= Self.menuForce {
                // Pressed through: the menu opens and stays open after the finger lifts.
                peekView.activateMenu(immediately: false)
                stopTimers()
                awaitsMenu = false
                self.peekView = nil
                candidate = nil
                state = .ended
                return
            }
            if pressTask != nil, movedAway {
                startPressTimer()
            }
            checkCandidateContent(at: location)
        } else {
            peekView.applyDraggingOffset(touch.location(in: peekView))
        }
        if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        stopTimers()
        if let peekView {
            peekView.endDragging(at: touch.location(in: peekView))
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        stopTimers()
        if let peekView {
            peekView.dismiss()
            state = .cancelled
        } else {
            state = .failed
        }
    }

    /// PeekControllerGestureRecognizer's traceDeceleratingScrollView.
    private static func hasDeceleratingScrollView(_ view: UIView, at point: CGPoint) -> Bool {
        if view.bounds.contains(point), let scrollView = view as? UIScrollView, scrollView.isDecelerating {
            return true
        }
        return view.subviews.contains { hasDeceleratingScrollView($0, at: view.convert(point, to: $0)) }
    }

    private func startLongTapTimer() {
        longTapTask?.cancel()
        longTapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.longTapTimerFired()
        }
    }

    private func startPressTimer() {
        pressTask?.cancel()
        pressTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.pressTimerFired()
        }
    }

    private func stopTimers() {
        longTapTask?.cancel()
        longTapTask = nil
        pressTask?.cancel()
        pressTask = nil
    }

    private func longTapTimerFired() {
        longTapTask = nil
        guard state == .possible, let tapLocation else { return }
        checkCandidateContent(at: tapLocation)
    }

    private func pressTimerFired() {
        pressTask = nil
        guard awaitsMenu, tapLocation != nil, let peekView else { return }
        peekView.activateMenu(immediately: false)
        awaitsMenu = false
    }

    /// PeekControllerGestureRecognizer.checkCandidateContent: the first sticker opens the preview; another one the
    /// finger reaches replaces its content.
    private func checkCandidateContent(at location: CGPoint) {
        guard let content = contentAtPoint?(location) else {
            if peekView == nil, state == .possible {
                stopTimers()
                state = .failed
            }
            return
        }
        if let candidate {
            guard !candidate.showsSameSticker(as: content) else { return }
            tapLocation = location
            self.candidate = content
            awaitsMenu = true
            peekView?.updateContent(content)
            return
        }
        guard state == .possible, let peekView = StickerPeekView.present(content) else {
            if state == .possible {
                stopTimers()
                state = .failed
            }
            return
        }
        candidate = content
        awaitsMenu = true
        self.peekView = peekView
        state = .began
        if peekView.traitCollection.forceTouchCapability != .available {
            startPressTimer()
        }
    }
}
