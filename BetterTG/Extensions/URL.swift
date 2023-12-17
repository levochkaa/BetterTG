// URL.swift

import SwiftUI

extension URL: Identifiable {
    public var id: String { absoluteString }
}
