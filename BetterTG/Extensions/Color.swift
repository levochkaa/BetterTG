// Color.swift

import UIKit

extension UIColor {
    static let messageHighlight = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.45)
            : UIColor.black.withAlphaComponent(0.12)
    }

    static let contextMenuSelectionHighlight = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.08)
    }
}
