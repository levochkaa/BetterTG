// TextEntity.swift

import Foundation
import TDLibKit

extension TextEntity {
    init(_ type: TextEntityType, range: NSRange) {
        self.init(offset: range.location, length: range.length, type: type)
    }
}
