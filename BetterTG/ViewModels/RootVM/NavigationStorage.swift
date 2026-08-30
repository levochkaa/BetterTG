// NavigationStorage.swift

import UIKit

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

    @discardableResult func setRoot(_ controller: UIViewController) -> UINavigationController {
        navigationController.setViewControllers([controller], animated: false)
        return navigationController
    }

    func push(_ route: Route, animated: Bool = true) {
        let controller: UIViewController =
            switch route {
            case .customChat(let customChat, let targetMessageID):
                ChatViewController(
                    customChat: customChat,
                    targetMessageID: targetMessageID,
                )
            case .archive(let customFolder):
                ArchiveViewController(folder: customFolder, rootVM: .shared)
            }
        navigationController.pushViewController(controller, animated: animated)
    }

    func pop(animated: Bool = true) {
        navigationController.popViewController(animated: animated)
    }

    func popToRoot(animated: Bool = true) {
        navigationController.popToRootViewController(animated: animated)
    }
}
