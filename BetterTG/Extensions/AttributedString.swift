// AttributedString.swift

import Foundation

extension AttributedString {
    var string: String {
        NSAttributedString(self).string
    }
}
