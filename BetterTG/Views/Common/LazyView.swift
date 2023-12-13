// LazyView.swift

import SwiftUI

struct LazyView<Content: View>: View {
    let build: () -> Content
    
    var body: Content {
        build()
    }
}
