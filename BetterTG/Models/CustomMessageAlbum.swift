// CustomMessageAlbum.swift

import SwiftUI
import TDLibKit

struct CustomMessageAlbum: Identifiable {
    var id = UUID()
    var photos: [Message]
    var selection: Int64
}
