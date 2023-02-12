// OpenedItems.swift

import SwiftUI
import TDLibKit

struct OpenedItems {
    var images: [IdentifiableImage]
    var index: Int
}

struct IdentifiableImage: Identifiable {
    var id = UUID().uuidString
    var image: Image
}
