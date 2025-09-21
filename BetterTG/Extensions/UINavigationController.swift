// UINavigationController.swift

import SwiftUI

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()

        let panGesture = UIPanGestureRecognizer(
            target: interactivePopGestureRecognizer?.delegate,
            action: Selector(("handleNavigationTransition:")),
        )
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
        interactivePopGestureRecognizer?.isEnabled = false
    }

    public func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
