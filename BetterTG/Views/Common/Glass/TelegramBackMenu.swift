// TelegramBackMenu.swift

import UIKit

// MARK: - TelegramBackMenuTitled

/// A screen's name in the back button's history menu, for a screen that draws its title in its own header rather than
/// in its navigation item.
@MainActor protocol TelegramBackMenuTitled: AnyObject {
    var telegramBackMenuTitle: String? { get }
}

// MARK: - UINavigationController + back menu

extension UINavigationController {
    /// UIKit's back button menu (`_backButtonMenu`): the screens under `controller`, nearest first, each by its back
    /// title; choosing one pops back to it, as Back would, past a screen that holds Back for unsaved changes.
    func telegramBackMenuActions(below controller: UIViewController) -> [TelegramContextMenuAction] {
        guard let index = viewControllers.firstIndex(of: controller), index > 0 else { return [] }
        return viewControllers[..<index].reversed().map { target in
            TelegramContextMenuAction(title: Self.backMenuTitle(of: target)) { [
                weak self,
                weak target,
                weak controller,
            ] in
                guard let self, let target, let controller, viewControllers.contains(target) else { return }
                if let handler = controller as? TelegramNavigationAttemptHandling,
                   !handler.attemptNavigation() { return }
                popToViewController(target, animated: true)
            }
        }
    }

    /// Opens the history menu from `controller`'s back button, growing out of its glass `platter`.
    func presentTelegramBackMenu(from platter: UIView, for controller: UIViewController) {
        let actions = telegramBackMenuActions(below: controller)
        guard !actions.isEmpty, transitionCoordinator == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        controller.presentTelegramContextMenu(sourceView: platter, actions: actions, presentationStyle: .sourceMorph)
    }

    private static func backMenuTitle(of controller: UIViewController) -> String {
        let titles = [
            (controller as? TelegramBackMenuTitled)?.telegramBackMenuTitle,
            controller.navigationItem.backButtonTitle,
            controller.navigationItem.title,
            controller.title,
        ]
        return titles.compactMap(\.self).first { !$0.isEmpty } ?? L10n.telegram("Common.Back")
    }
}

// MARK: - UIView + back menu

extension UIView {
    /// Opens the history menu for the screen this bar belongs to, out of its back button's `platter`.
    func presentTelegramBackMenu(from platter: UIView) {
        var controller = nearestViewController
        while let current = controller, !(current.parent is UINavigationController) {
            controller = current.parent
        }
        guard let controller, let navigation = controller.navigationController else { return }
        navigation.presentTelegramBackMenu(from: platter, for: controller)
    }
}

// MARK: - MainViewController + TelegramBackMenuTitled

extension MainViewController: TelegramBackMenuTitled {
    /// The chat list goes by Chats, as Telegram's back buttons name it.
    var telegramBackMenuTitle: String? { L10n.telegram("ChatList.Search.FilterChats") }
}
