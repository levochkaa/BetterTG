// View+FullScreenBackground.swift

extension View {
    func fullScreenBackground(color: Color) -> some View {
        ZStack {
            color
                .ignoresSafeArea()
            
            self
        }
    }
}
