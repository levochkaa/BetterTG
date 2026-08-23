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

    convenience init(userID: Int64) {
        let colors: [UIColor] = [
            .systemRed,
            .systemGreen,
            .systemYellow,
            .systemBlue,
            .systemPurple,
            .systemPink,
            .systemBlue,
        ]
        let normalized = abs(Int(String(userID).replacingOccurrences(of: "-100", with: "")) ?? 0)
        self.init(cgColor: colors[[0, 6, 4, 1, 5, 3, 2][normalized % 7]].cgColor)
    }
}
