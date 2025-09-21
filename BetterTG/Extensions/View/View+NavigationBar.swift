// View+NavigationBar.swift

import SwiftUI

extension View {
    func navigationBarHeight(_ height: Binding<CGFloat>) -> some View {
        background {
            NavigationBarAccessor { navigationBar in
                height.wrappedValue = navigationBar.bounds.height
            }
        }
    }
}

// MARK: - NavigationBarAccessor

struct NavigationBarAccessor: UIViewControllerRepresentable {
    // MARK: Internal

    var callback: (UINavigationBar) -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        let proxyViewController = ProxyViewController()
        proxyViewController.callback = callback
        proxyViewController.startObservingNavigationBarIfNeeded()
        return proxyViewController
    }
    
    func updateUIViewController(_: UIViewController, context _: Context) {}
    
    // MARK: Private

    private final class ProxyViewController: UIViewController {
        // MARK: Lifecycle

        deinit {
            stopObservingNavigationBar()
        }
        
        // MARK: Internal

        var callback: ((UINavigationBar) -> Void)?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            startObservingNavigationBarIfNeeded()
            refreshNavigationBarHeight()
        }
        
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            startObservingNavigationBarIfNeeded()
            refreshNavigationBarHeight()
        }
        
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refreshNavigationBarHeight()
        }
        
        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            if parent == nil {
                stopObservingNavigationBar()
            }
        }
        
        func startObservingNavigationBarIfNeeded() {
            guard let navigationBar = navigationController?.navigationBar else { return }
            guard observedNavigationBar !== navigationBar else { return }
            stopObservingNavigationBar()
            observedNavigationBar = navigationBar
            
            boundsObservation = navigationBar.observe(\.bounds, options: [
                .initial,
                .new,
            ]) { [weak self] navigationBar, _ in
                self?.reportHeightIfNeeded(for: navigationBar)
            }
        }
        
        func refreshNavigationBarHeight() {
            guard let navigationBar = navigationController?.navigationBar else { return }
            reportHeightIfNeeded(for: navigationBar)
        }
        
        // MARK: Private

        private weak var observedNavigationBar: UINavigationBar?
        private var boundsObservation: NSKeyValueObservation?
        private var lastReportedHeight = CGFloat.zero
        
        private func stopObservingNavigationBar() {
            boundsObservation?.invalidate()
            boundsObservation = nil
            observedNavigationBar = nil
        }
        
        private func reportHeightIfNeeded(for navigationBar: UINavigationBar) {
            let height = navigationBar.bounds.height
            guard height.isFinite else { return }
            guard abs(height - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = height
            callback?(navigationBar)
        }
    }
}
