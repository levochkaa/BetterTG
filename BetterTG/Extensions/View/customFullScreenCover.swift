// customFullScreenCover.swift

import SwiftUI

extension View {
    @ViewBuilder func customFullScreenCover<Content: View>(
        show: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(HelperHeroView(show: show, overlay: content()))
    }
}

private struct HelperHeroView<Overlay: View>: ViewModifier {
    
    @Binding var show: Bool
    var overlay: Overlay
    
    @State private var hostView: CustomHostingView<Overlay>?
    @State private var parentController: UIViewController?
    
    func body(content: Content) -> some View {
        content
            .background {
                ExtractSwiftUIParentController(content: overlay, hostView: $hostView) { viewController in
                    parentController = viewController
                }
            }
            .onAppear {
                hostView = CustomHostingView(show: $show, rootView: overlay)
            }
            .onChange(of: show) { newValue in
                if newValue {
                    if let hostView {
                        hostView.modalPresentationStyle = .overCurrentContext
                        hostView.modalTransitionStyle = .crossDissolve
                        hostView.view.backgroundColor = .clear
                        parentController?.present(hostView, animated: false)
                    }
                } else {
                    hostView?.dismiss(animated: false)
                }
            }
    }
}

private struct ExtractSwiftUIParentController<Content: View>: UIViewRepresentable {
    
    var content: Content
    @Binding var hostView: CustomHostingView<Content>?
    var parentController: (UIViewController?) -> Void
    
    func makeUIView(context: Context) -> UIView {
        return UIView()
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        hostView?.rootView = content
        DispatchQueue.main.async {
            parentController(uiView.superview?.superview?.parentController)
        }
    }
}

private class CustomHostingView<Content: View>: UIHostingController<Content> {
    
    @Binding var show: Bool
    
    init(show: Binding<Bool>, rootView: Content) {
        self._show = show
        super.init(rootView: rootView)
    }
    
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(false)
        show = false
    }
}

fileprivate extension UIView {
    var parentController: UIViewController? {
        var responder = self.next
        while responder != nil {
            if let viewController = responder as? UIViewController {
                return viewController
            }
            responder = responder?.next
        }
        return nil
    }
}
