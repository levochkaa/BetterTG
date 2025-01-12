// TextEntity.swift

import SwiftUI
@preconcurrency import TDLibKit

extension TextEntity {
    init(_ type: TextEntityType, range: NSRange) {
        self.init(length: range.length, offset: range.location, type: type)
    }
}
