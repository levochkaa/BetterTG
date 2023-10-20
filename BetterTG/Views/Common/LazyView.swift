// LazyView.swift

struct LazyView<Content: View>: View {
    private let build: () -> Content
    
    init(_ build: @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}
