// UIScrollView+SystemEdgeEffects.swift

import ObjectiveC
import UIKit

extension UIScrollView {
    /// `TelegramBarBackgroundView` draws every bar's effect, and `TelegramNavigationController` keeps the system's bar
    /// hidden. On iOS 27 a full-screen scroll view still gets the system's scroll edge effect under the status bar. It
    /// would lie under BetterTG's bar as a second blur and wash, so no scroll view keeps it.
    static func hideSystemEdgeEffects() {
        let original = #selector(UIView.didMoveToWindow)
        let replacement = #selector(UIScrollView.bettertgDidMoveToWindow)
        guard let originalMethod = class_getInstanceMethod(UIScrollView.self, original),
              let replacementMethod = class_getInstanceMethod(UIScrollView.self, replacement)
        else { return }
        // UIScrollView inherits the method, and UIView's own must stay as it is for every other view.
        if class_addMethod(
            UIScrollView.self,
            original,
            method_getImplementation(replacementMethod),
            method_getTypeEncoding(replacementMethod),
        ) {
            class_replaceMethod(
                UIScrollView.self,
                replacement,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod),
            )
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    @objc private func bettertgDidMoveToWindow() {
        bettertgDidMoveToWindow()
        guard window != nil else { return }
        topEdgeEffect.isHidden = true
        bottomEdgeEffect.isHidden = true
    }
}
