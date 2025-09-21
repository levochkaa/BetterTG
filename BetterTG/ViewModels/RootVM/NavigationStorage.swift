// NavigationStorage.swift

import SwiftUI

@MainActor final class NavigationStorage {
    // MARK: Lifecycle

    private init() {
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.isTranslucent = true
    }

    // MARK: Internal

    static let shared = NavigationStorage()

    let navigationController = UINavigationController()

    var viewControllers: [UIViewController] {
        navigationController.viewControllers
    }

    func setDestinationBuilder(@ViewBuilder _ builder: @escaping (Route) -> some View) {
        destinationBuilder = { AnyView(builder($0)) }
    }

    func push(_ route: Route, animated: Bool = true) {
        guard let destinationBuilder else { return }
        let controller = UIHostingController(rootView: destinationBuilder(route))
        controller.view.backgroundColor = .clear
        navigationController.pushViewController(controller, animated: animated)
    }

    func pop(animated: Bool = true) {
        navigationController.popViewController(animated: animated)
    }

    func popToRoot(animated: Bool = true) {
        navigationController.popToRootViewController(animated: animated)
    }

    // MARK: Private

    private var destinationBuilder: ((Route) -> AnyView)?
}
