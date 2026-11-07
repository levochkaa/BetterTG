// UIBarButtonItem+Icons.swift

import UIKit

/// Done and Edit as icons, as iOS 26's bar shows Done: a checkmark on prominent glass, and Edit as a pencil.
extension UIBarButtonItem {
    static let doneImage = UIImage(systemName: "checkmark")
    static let editImage = UIImage(systemName: "pencil")

    static func telegramDone(target: Any?, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: doneImage, style: .prominent, target: target, action: action)
        item.accessibilityLabel = L10n.telegram("Common.Done")
        return item
    }

    static func telegramEdit(target: Any?, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: editImage, style: .plain, target: target, action: action)
        item.accessibilityLabel = L10n.telegram("Common.Edit")
        return item
    }

    static func telegramEdit(primaryAction: UIAction) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: editImage, primaryAction: primaryAction)
        item.accessibilityLabel = L10n.telegram("Common.Edit")
        return item
    }
}
