// FormattedText.swift

import Foundation
import TDLibKit

extension FormattedText {
    var withDate: NSMutableAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.append(NSMutableAttributedString.dateString)
        return attributedString
    }
}
