// NavigationStorage.swift

import Combine
import TDLibKit
import UIKit

@MainActor final class NavigationStorage: NSObject {
    // MARK: Internal

    static let shared = NavigationStorage()

    let navigationController = TelegramNavigationController()
    private(set) lazy var splitController = TelegramSplitViewController(master: navigationController)
    /// The chat the detail pane shows while the window is split, for the lists to highlight.
    let splitSelectedChatID = CurrentValueSubject<Int64?, Never>(nil)

    private var clientRestoration: NavigationClientRestoration?

    var viewControllers: [UIViewController] {
        splitController.logicalStack
    }

    /// The stack new screens go on: the detail pane's while the window is split.
    var activeNavigationController: TelegramNavigationController {
        splitController.activeNavigation
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
                guard let self else { return false }
                let split = splitController
                return [split.master, split.detail].allSatisfy { $0.transitionCoordinator == nil }
                    && navigationController.presentedViewController == nil
                    && !viewControllers.contains { $0.presentedViewController != nil }
            },
            replace: { [weak self] controllers in
                self?.splitController.setLogicalStack(controllers, animated: false)
            },
        )
        splitController.onDetailChange = { [weak self] in self?.updateSplitSelection() }
    }

    func retryClientRestoration() {
        clientRestoration?.retry()
    }

    @discardableResult func setRoot(_ controller: UIViewController) -> UIViewController {
        navigationController.setViewControllers([controller], animated: false)
        return splitController
    }

    /// `fromList`: a list row opens the route. In a split window it takes the detail pane instead of stacking there,
    /// and the chat already shown stays.
    func push(_ route: Route, animated: Bool = true, fromList: Bool = false) {
        if fromList, splitController.isSplit, isShownInDetail(route) { return }
        guard let controller = controller(for: route) else { return }
        if fromList, splitController.isSplit, !(controller is TelegramMasterPaneScreen) {
            splitController.replaceDetail(with: controller)
            return
        }
        navigationController.pushViewController(controller, animated: animated)
    }

    /// Telegram's compose flow gives way to what it opens (replaceTopController, replaceAllButRootController): the
    /// screens marked `ComposeFlowScreen` and everything above them leave the stack.
    func replaceComposeFlow(with route: Route) {
        guard let controller = controller(for: route) else { return }
        replaceComposeFlow(with: controller)
    }

    func replaceComposeFlow(with controller: UIViewController) {
        let navigation = activeNavigationController
        let kept = navigation.viewControllers.prefix { !($0 is ComposeFlowScreen) }
        navigation.setViewControllers(Array(kept) + [controller], animated: true)
    }

    func pop(animated: Bool = true) {
        activeNavigationController.popViewController(animated: animated)
    }

    func popToRoot(animated: Bool = true) {
        splitController.popToRoots(animated: animated)
    }

    private func updateSplitSelection() {
        let split = splitController
        let chat = split.isSplit ? split.detail.viewControllers.dropFirst().first as? ChatViewController : nil
        let chatID = chat?.location.chatID
        if splitSelectedChatID.value != chatID { splitSelectedChatID.send(chatID) }
    }

    /// Whether the detail pane's top already shows the route's chat as it is, with no message to go to.
    private func isShownInDetail(_ route: Route) -> Bool {
        guard case .customChat(let customChat, _, let forumTopic, let targetMessageID, _, let messageThread) = route,
              forumTopic == nil, targetMessageID == nil, messageThread == nil,
              let shown = splitController.detail.viewControllers.last as? ChatViewController
        else { return false }
        return splitController.detail.viewControllers.count == 2 && shown.location.chatID == customChat.id
            && shown.location.topic == nil
    }

    private func controller(for route: Route) -> UIViewController? {
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
            else { return nil }
            // A forum opens as its topic list; a topic or a reply thread opens as its own chat.
            if resolvedLocation.topic == nil,
               customChat.chat.viewAsTopics
            {
                return ForumTopicsViewController(
                    customChat: customChat,
                    location: resolvedLocation,
                    client: client,
                    targetMessageID: targetMessageID,
                    targetQuote: targetQuote,
                )
            }
            return ChatViewController(
                customChat: customChat,
                location: resolvedLocation,
                forumTopic: forumTopic,
                targetMessageID: targetMessageID,
                targetQuote: targetQuote,
                messageThread: messageThread,
            )
        case .archive(let customFolder):
            return ArchiveViewController(folder: customFolder, rootVM: .shared)
        }
    }
}
