// Data.swift

import Foundation

extension Data {
    var string: String { String(data: self, encoding: .utf8) ?? "" }
}
