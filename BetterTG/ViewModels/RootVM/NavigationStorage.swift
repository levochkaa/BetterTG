// NavigationStorage.swift

import TDLibKit
import UIKit

@MainActor final class NavigationStorage: NSObject {
    // MARK: Internal

    static let shared = NavigationStorage()

    let navigationController = TelegramNavigationController()

    private var clientRestoration: NavigationClientRestoration?

    var viewControllers: [UIViewController] {
        navigationController.viewControllers
    }

    override private init() {
        super.init()
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.isTranslucent = true
        // TelegramNavigationController stays its own delegate for classic chrome and reports each shown screen.
        navigationController.onDidShow = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.retryClientRestoration() }
        }
        self.clientRestoration = NavigationClientRestoration(
            readiness: TDLib.shared.readyClientChanges,
            currentSource: { TDLib.shared.activeUpdateSource },
            stack: { [weak self] in self?.viewControllers ?? [] },
            canReplace: { [weak self] in
                guard let navigation = self?.navigationController else { return false }
                return navigation.transitionCoordinator == nil
                    && navigation.presentedViewController == nil
                    && !navigation.viewControllers.contains { $0.presentedViewController != nil }
            },
            replace: { [weak self] controllers in
                self?.navigationController.setViewControllers(controllers, animated: false)
            },
        )
    }

    func retryClientRestoration() {
        clientRestoration?.retry()
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
            let messageThread,
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
            // A forum opens as its topic list; a topic or a reply thread opens as its own chat.
            if resolvedLocation.topic == nil,
               customChat.chat.viewAsTopics
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
                    messageThread: messageThread,
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
