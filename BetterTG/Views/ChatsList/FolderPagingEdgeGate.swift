// FolderPagingEdgeGate.swift

import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Reports where a touch starts on the chat list pages and fails at once, so it never takes a touch.
///
/// Telegram's folder pan (ChatListControllerNode, `InteractiveTransitionGestureRecognizer` with
/// `[.leftCenter, .rightCenter]` and an edge width of a sixth of the width within 22...80 pt) fails for a pan that
/// starts in a side edge zone; the row's reveal options then take it. A pan from the middle switches folders.
final class FolderPagingEdgeGate: UIGestureRecognizer {
    // MARK: Internal

    /// Whether the latest touch started in an edge zone.
    private(set) var touchStartedAtEdge = false
    var onTouchBegan: ((Bool) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
        if let view, let point = touches.first?.location(in: view) {
            let edge = Self.edgeWidth(for: view.bounds.width)
            touchStartedAtEdge = point.x < edge || point.x > view.bounds.width - edge
            onTouchBegan?(touchStartedAtEdge)
        }
        state = .failed
    }

    override func canPrevent(_: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by _: UIGestureRecognizer) -> Bool {
        false
    }

    static func edgeWidth(for width: CGFloat) -> CGFloat {
        max(22, min(width / 6, 80))
    }
}
