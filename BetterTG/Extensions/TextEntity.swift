// TextEntity.swift

import SwiftUI
import TDLibKit

extension TextEntity {
    init(_ type: TextEntityType, range: NSRange) {
        self.init(length: range.length, offset: range.location, type: type)
    }
}
