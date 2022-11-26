// Chat+Hashable.swift

import Foundation
import TDLibKit

extension Chat: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
