// View+OnVisible.swift

import SwiftUI

extension View {
    func onVisible(perform action: @escaping () -> Void) -> some View {
        modifier(OnVisibleViewModifier(action: action))
    }
}

private struct OnVisibleViewModifier: ViewModifier {
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
                            guard isVisible, let action else { return }
                            action()
                            self.action = nil
                        }
                }
            }
    }
    
    struct VisibleKey: PreferenceKey {
        static var defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) { }
    }
}
