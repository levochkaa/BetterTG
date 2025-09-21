// View.swift

import SwiftUI

extension View {
    func readOffset(in coordinateSpace: NamedCoordinateSpace, onChange: @escaping (CGRect) -> Void) -> some View {
        overlay {
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: geometryProxy.frame(in: coordinateSpace))
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: onChange)
            }
        }
    }
    
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
                    .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
            }
        }
    }
    
    @ViewBuilder func `if`(
        _ condition: Bool,
        _ transform: (Self) -> some View,
        else elseTransform: ((Self) -> some View)? = nil,
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
    
    @ViewBuilder func `if`(
        _ condition: Bool,
        _ transform: (Self) -> some View,
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder func modify(@ViewBuilder _ transform: (Self) -> (some View)?) -> some View {
        if let view = transform(self), !(view is EmptyView) {
            view
        } else {
            self
        }
    }
    
    func frame(size: CGSize?, alignment: Alignment = .center) -> some View {
        frame(width: size?.width, height: size?.height, alignment: alignment)
    }
    
    func flipped() -> some View {
        rotationEffect(.init(radians: .pi))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}
