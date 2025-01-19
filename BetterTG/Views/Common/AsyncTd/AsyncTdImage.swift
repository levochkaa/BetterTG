// AsyncTdImage.swift

import SwiftUI
import TDLibKit

struct AsyncTdImage<Content: View, Placeholder: View>: View {
    let id: Int
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var image: Image?
    
    var body: some View {
        AsyncTdFile(id: id) { file in
            if let image {
                content(image)
            } else {
                placeholder().task {
                    guard let uiImage = await UIImage(contentsOfFile: file.local.path)?.byPreparingForDisplay() else { return }
                    self.image = Image(uiImage: uiImage)
                }
            }
        } placeholder: {
            placeholder()
        }
    }
}
