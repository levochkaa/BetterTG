// View+Animation.swift

import SwiftUI

extension View {
    @ViewBuilder func animation<T: Equatable>(value: T) -> some View {
        animation(.default, value: value)
    }
}
