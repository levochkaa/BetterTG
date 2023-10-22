// AttributedString.swift

import SwiftUI

extension AttributedString {
    var string: String {
        NSAttributedString(self).string
    }
}
