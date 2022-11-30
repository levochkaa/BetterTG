// AsyncTdImage.swift

import SwiftUI
import TDLibKit

struct AsyncTdImage<Content: View, Placeholder: View>: View {
    let id: Int
    let image: (Image) -> Content
    let placeholder: () -> Placeholder
    
    var body: some View {
        AsyncTdFile(id: id) { file in
            image(Image(file: file))
                .transition(.opacity)
                .animation(.easeInOut, value: file)
        } placeholder: {
            placeholder()
        }
    }
}
