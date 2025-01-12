// SelectedImage.swift

import SwiftUI
import TDLibKit

struct SelectedImage: Identifiable {
    let id = UUID()
    var image: Image
    var url: URL
}

extension SelectedImage: Equatable {
    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url
    }
}
