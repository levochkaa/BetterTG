// View+Width.swift

import SwiftUI

extension View {
    func width(_ width: Binding<Int>) -> some View {
        background {
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: WidthPreferenceKey.self, value: Int(geometryProxy.size.width))
            }
        }
        .onPreferenceChange(WidthPreferenceKey.self) { newWidth in
            width.wrappedValue = newWidth
        }
    }
}
