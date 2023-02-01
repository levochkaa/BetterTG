// flippedUpsideDown.swift

import SwiftUI

extension View {
    func flippedUpsideDown() -> some View {
        self
            .rotationEffect(.init(radians: .pi))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}
