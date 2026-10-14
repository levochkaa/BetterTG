// UIView+StackHiding.swift

import UIKit

extension UIView {
    /// UIStackView counts every `isHidden = true` on an arranged subview made inside an animation block, so a
    /// reused view configured that way several times needed as many `false` assignments to show again: a text
    /// message reusing a photo cell kept its text row hidden and collapsed to the bubble insets. Assign only changes.
    func setHiddenIfChanged(_ hidden: Bool) {
        guard isHidden != hidden else { return }
        isHidden = hidden
    }
}
