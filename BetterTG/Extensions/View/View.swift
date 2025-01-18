// View.swift

import SwiftUI

extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
    
    @ViewBuilder func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        _ transform: (Self) -> TrueContent,
        else elseTransform: ((Self) -> FalseContent)? = nil
    ) -> some View {
        if condition {
            transform(self)
        } else {
            if let elseTransform {
                elseTransform(self)
            } else {
                self
            }
        }
    }
    
    @ViewBuilder func `if`<Content: View>(
        _ condition: Bool,
        _ transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder func modify<Content: View>(@ViewBuilder _ transform: (Self) -> Content?) -> some View {
        if let view = transform(self), !(view is EmptyView) {
            view
        } else {
            self
        }
    }
    
    @ViewBuilder func frame(size: CGSize?, alignment: Alignment = .center) -> some View {
        frame(width: size?.width, height: size?.height, alignment: alignment)
    }
    
    func flipped() -> some View {
        self
            .rotationEffect(.init(radians: .pi))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}
