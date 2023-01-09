// NSRange+Index.swift

import Foundation

extension NSRange {
    func index() -> Int {
        location + length - 1
    }
}
