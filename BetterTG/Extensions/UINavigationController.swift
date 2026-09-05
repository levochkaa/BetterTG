// UINavigationController.swift

import UIKit

final class TelegramNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        let panGesture = UIPanGestureRecognizer(
            target: interactivePopGestureRecognizer?.delegate,
            action: Selector(("handleNavigationTransition:")),
        )
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
        interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Keep Telegram's plain bar buttons on iOS 26, including screens which
        // create their Edit/Done items after the navigation transition begins.
        if #available(iOS 26.0, *) {
            for item in navigationBar.items ?? [] {
                for button in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) {
                    if !button.hidesSharedBackground { button.hidesSharedBackground = true }
                }
                if item.backBarButtonItem == nil {
                    item.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
                }
                if item.backBarButtonItem?.hidesSharedBackground == false {
                    item.backBarButtonItem?.hidesSharedBackground = true
                }
            }
        }
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A trim/scrub drag belongs to its editor even when it moves toward Back.
        var touchedView = touch.view
        while let candidate = touchedView, candidate !== view {
            if candidate is VoiceRecordingTrimView || candidate is UISlider { return false }
            touchedView = candidate.superview
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1,
              transitionCoordinator == nil,
              let panGesture = gestureRecognizer as? UIPanGestureRecognizer
        else { return false }

        let velocity = panGesture.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) else { return false }
        return switch view.effectiveUserInterfaceLayoutDirection {
        case .leftToRight:
            velocity.x > 0
        case .rightToLeft:
            velocity.x < 0
        @unknown default:
            velocity.x > 0
        }
    }
}
