// String.swift

import SwiftUI

extension String {
    var data: Data { Data(utf8) }
    
    var attributedString: AttributedString {
        let mutable = NSMutableAttributedString(string: self)
        mutable.addAttributes([
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.white
        ], range: NSRange(location: 0, length: count))
        return AttributedString(mutable)
    }
}

extension AttributedString {
    var string: String {
        NSAttributedString(self).string
    }
}

extension NSMutableAttributedString {
    static var dateString: NSMutableAttributedString {
        NSMutableAttributedString(
            string: " 00.00",
            attributes: [
                .font: UIFont.caption,
                .foregroundColor: UIColor.clear,
            ]
        )
    }
}
