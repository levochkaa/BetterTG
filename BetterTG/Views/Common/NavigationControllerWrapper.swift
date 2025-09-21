// NavigationControllerWrapper.swift

import SwiftUI

// MARK: - NavigationControllerWrapper

struct NavigationControllerWrapper<Content: View>: UIViewControllerRepresentable {
    // MARK: Lifecycle

    init(
        navigationController: UINavigationController = UINavigationController(),
        @ViewBuilder root: @escaping () -> Content,
    ) {
        self.navigationController = navigationController
        self.root = root
    }

    // MARK: Internal

    func makeUIViewController(context _: Context) -> UINavigationController {
        if navigationController.viewControllers.isEmpty {
            let rootController = UIHostingController(rootView: AnyView(root()))
            rootController.view.backgroundColor = .clear
            navigationController.setViewControllers([rootController], animated: false)
        }
        return navigationController
    }

    func updateUIViewController(_: UINavigationController, context _: Context) {}

    // MARK: Private

    private let navigationController: UINavigationController
    private let root: () -> Content
}
