// fullScreenBackground.swift

import SwiftUI

extension View {
    func fullScreenBackground(color: Color) -> some View {
        ZStack {
            color.ignoresSafeArea()
            
            self
        }
    }
}
