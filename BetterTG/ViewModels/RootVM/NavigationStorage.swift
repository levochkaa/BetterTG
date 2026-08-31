// NavigationStorage.swift

import TDLibKitDynamic
import UIKit

@MainActor final class NavigationStorage {
    // MARK: Internal

    static let shared = NavigationStorage()

    let navigationController = UINavigationController()

    var viewControllers: [UIViewController] {
        navigationController.viewControllers
    }

    private init() {
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.isTranslucent = true
    }

    @discardableResult func setRoot(_ controller: UIViewController) -> UINavigationController {
        navigationController.setViewControllers([controller], animated: false)
        return navigationController
    }

    func push(_ route: Route, animated: Bool = true) {
        let controller: UIViewController
        switch route {
        case .customChat(
            let customChat,
            let location,
            let forumTopic,
            let targetMessageID,
            let targetQuote,
        ):
            let client = TDLib.shared.activeClient
            let resolvedLocation = location ?? ChatLocation.current(
                chatID: customChat.id,
                client: client,
            )
            guard resolvedLocation.accountID == TDLib.shared.activeAccountID,
                  resolvedLocation.clientID == client.id,
                  resolvedLocation.chatID == customChat.id
            else { return }
            if resolvedLocation.forumTopicID == nil,
               customChat.chat.viewAsTopics || customChat.supergroup?.isForum == true
            {
                controller = ForumTopicsViewController(
                    customChat: customChat,
                    location: resolvedLocation,
                    client: client,
                    targetMessageID: targetMessageID,
                    targetQuote: targetQuote,
                )
            } else {
                controller = ChatViewController(
                    customChat: customChat,
                    location: resolvedLocation,
                    forumTopic: forumTopic,
                    targetMessageID: targetMessageID,
                    targetQuote: targetQuote,
                )
            }
        case .archive(let customFolder):
            controller = ArchiveViewController(folder: customFolder, rootVM: .shared)
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
