// ZoomableScrollView.swift

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    
    private var content: Content
    
    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostedView.frame = scrollView.bounds
        hostedView.backgroundColor = .clear
        scrollView.addSubview(hostedView)
        
        return scrollView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content))
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>
        
        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }
    }
}
