// flippedUpsideDown.swift

import SwiftUI

extension View {
    func flippedUpsideDown() -> some View {
        self
            .rotationEffect(.pi)
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}
