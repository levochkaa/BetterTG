// CustomMessageAlbum.swift

import SwiftUI
@preconcurrency import TDLibKit

struct CustomMessageAlbum: Identifiable {
    var id = UUID()
    var photos: [Message]
    var selection: Int64
}
