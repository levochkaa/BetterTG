// View+Center.swift

import SwiftUI

enum CustomAxis {
    case horizontally, vertically, both
}

extension View {
    @ViewBuilder func center(_ axis: CustomAxis) -> some View {
        switch axis {
            case .vertically:
                VStack {
                    Spacer()
                    self
                    Spacer()
                }
            case .horizontally:
                HStack {
                    Spacer()
                    self
                    Spacer()
                }
            case .both:
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        self
                        Spacer()
                    }
                    Spacer()
                }
        }
    }
}
