// OpenedItems.swift

import SwiftUI
import TDLibKit

struct OpenedItems {
    var id: any Hashable
    var image: Image
    var message: Message?
    var photos: [SelectedImage]?
}
