// AsyncTdImage.swift

import SwiftUI
@preconcurrency import TDLibKit

struct AsyncTdImage<Content: View, Placeholder: View>: View {
    
    let id: Int
    let image: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    var body: some View {
        AsyncTdFile(id: id) { file in
            image(Image(file: file))
        } placeholder: {
            placeholder()
        }
        .equatable(by: id)
    }
}
