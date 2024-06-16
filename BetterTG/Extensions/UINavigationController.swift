// UINavigationController.swift

import SwiftUI

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        let panGesture = UIPanGestureRecognizer(
            target: interactivePopGestureRecognizer?.delegate,
            action: Selector(("handleNavigationTransition:"))
        )
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
        interactivePopGestureRecognizer?.isEnabled = false
    }
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
