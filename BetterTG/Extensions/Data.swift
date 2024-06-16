// Data.swift

import Foundation

extension Data {
    var string: String { String(decoding: self, as: UTF8.self) }
}
