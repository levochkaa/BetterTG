// View+OnVisible.swift

import SwiftUI

private struct OnVisible: ViewModifier {
    
    @State var action: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: VisibleKey.self,
                            value: UIScreen.main.bounds.intersects(proxy.frame(in: .global))
                        )
                        .onPreferenceChange(VisibleKey.self) { isVisible in
                            guard isVisible else { return }
                            action?()
                        }
                }
            }
    }
}

extension View {
    func onVisible(_ action: @escaping () -> Void) -> some View {
        modifier(OnVisible(action: action))
    }
}
