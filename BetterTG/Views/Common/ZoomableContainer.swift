// ZoomableContainer.swift

import SwiftUI

private let maxAllowedScale = 3.0

// MARK: - ZoomableContainer

struct ZoomableContainer<Content: View>: View {
    // MARK: Internal

    @ViewBuilder let content: Content
    
    var body: some View {
        ZoomableScrollView(scale: $currentScale, tapLocation: $tapLocation) {
            content
        }
        .onTapGesture(count: 2, perform: doubleTapAction)
    }

    func doubleTapAction(location: CGPoint) {
        tapLocation = location
        currentScale = currentScale == 1.0 ? maxAllowedScale : 1.0
    }
    
    // MARK: Private

    @State private var currentScale: CGFloat = 1.0
    @State private var tapLocation = CGPoint.zero
}

// MARK: - ZoomableScrollView

private struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    // MARK: Lifecycle

    init(scale: Binding<CGFloat>, tapLocation: Binding<CGPoint>, @ViewBuilder content: () -> Content) {
        _currentScale = scale
        _tapLocation = tapLocation
        self.content = content()
    }
    
    // MARK: Internal

    final class Coordinator: NSObject, UIScrollViewDelegate {
        // MARK: Lifecycle

        init(hostingController: UIHostingController<Content>, scale: Binding<CGFloat>) {
            self.hostingController = hostingController
            _currentScale = scale
        }
        
        // MARK: Internal

        @Binding var currentScale: CGFloat
        
        var hostingController: UIHostingController<Content>

        func viewForZooming(in _: UIScrollView) -> UIView? {
            hostingController.view
        }
        
        func scrollViewDidEndZooming(_: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            currentScale = scale
        }
    }

    func makeUIView(context: Context) -> UIScrollView {
        // Setup the UIScrollView
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator // for viewForZooming(in:)
        scrollView.maximumZoomScale = maxAllowedScale
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.clipsToBounds = false
        
        // Create a UIHostingController to hold our SwiftUI content
        let hostedView = context.coordinator.hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostedView.frame = scrollView.bounds
        scrollView.addSubview(hostedView)
        
        return scrollView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content), scale: $currentScale)
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Update the hosting controller's SwiftUI content
        context.coordinator.hostingController.rootView = content
        
        if uiView.zoomScale > uiView.minimumZoomScale { // Scale out
            uiView.setZoomScale(currentScale, animated: true)
        } else if tapLocation != .zero { // Scale in to a specific point
            uiView.zoom(to: zoomRect(for: uiView, scale: uiView.maximumZoomScale, center: tapLocation), animated: true)
            // Reset the location to prevent scaling to it in case of a negative scale (manual pinch)
            // Use the main thread to prevent unexpected behavior
            Task.main { tapLocation = .zero }
        }
        
        assert(context.coordinator.hostingController.view.superview == uiView)
    }
    
    func zoomRect(for scrollView: UIScrollView, scale: CGFloat, center: CGPoint) -> CGRect {
        let scrollViewSize = scrollView.bounds.size
        
        let width = scrollViewSize.width / scale
        let height = scrollViewSize.height / scale
        let x = center.x - (width / 2.0)
        let y = center.y - (height / 2.0)
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: Private

    @Binding private var currentScale: CGFloat
    @Binding private var tapLocation: CGPoint
    
    private var content: Content
}
