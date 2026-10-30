// HomeScreenQuickActions.swift

import Combine
import UIKit

// MARK: - HomeScreenQuickActions

/// Telegram's ApplicationShortcutItem on the app's icon: Search, New Message, Saved Messages and, with another
/// signed-in
/// account, Switch Account; none while no account is signed in. As in AppDelegate.handleShortcutItem, an action that
/// shows the account's content waits for the passcode and Switch Account doesn't. Each also waits for the active
/// client,
/// which the app gives up in the background and takes back as it returns.
@MainActor final class HomeScreenQuickActions {
    private enum Action: String {
        case search
        case compose
        case savedMessages
        case account
    }

    static let shared = HomeScreenQuickActions()

    private var pendingAction: Action?
    private var readySource: TdUpdateSource?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        TDLib.shared
            .readyClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                self?.readySource = source
                self?.runPendingAction()
            }
            .store(in: &cancellables)
        AppPasscode.shared
            .$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.runPendingAction() }
            .store(in: &cancellables)
    }

    private static func otherAccount(in accounts: [TelegramAccount], activeAccountID: UUID?) -> TelegramAccount? {
        accounts.first { $0.id != activeAccountID && $0.userID != nil }
    }

    /// applicationShortcutItems. Telegram's App Icon item, shown without another account, has no screen here.
    private static func items(
        accounts: [TelegramAccount],
        activeAccountID: UUID?,
    ) -> [UIApplicationShortcutItem] {
        guard accounts.first(where: { $0.id == activeAccountID })?.userID != nil else { return [] }
        var items = [
            UIApplicationShortcutItem(
                type: Action.search.rawValue,
                localizedTitle: L10n.telegram("Common.Search"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(type: .search),
            ),
            UIApplicationShortcutItem(
                type: Action.compose.rawValue,
                localizedTitle: L10n.telegram("Compose.NewMessage"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(type: .compose),
            ),
            UIApplicationShortcutItem(
                type: Action.savedMessages.rawValue,
                localizedTitle: L10n.telegram("Conversation.SavedMessages"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(templateImageName: "Shortcuts/SavedMessages"),
            ),
        ]
        if let other = otherAccount(in: accounts, activeAccountID: activeAccountID) {
            items.append(UIApplicationShortcutItem(
                type: Action.account.rawValue,
                localizedTitle: L10n.telegram("Shortcut.SwitchAccount"),
                localizedSubtitle: other.localizedTitle,
                icon: UIApplicationShortcutIcon(templateImageName: "Shortcuts/Account"),
            ))
        }
        return items
    }

    /// Set as the app leaves the screen, when the accounts' names and the language are current.
    func updateItems() {
        UIApplication.shared.shortcutItems = Self.items(
            accounts: TDLib.shared.accounts,
            activeAccountID: TDLib.shared.activeAccountID,
        )
    }

    /// False for an item this version doesn't know.
    @discardableResult func perform(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = Action(rawValue: item.type) else { return false }
        pendingAction = action
        runPendingAction()
        return true
    }

    private func runPendingAction() {
        guard let action = pendingAction, let readySource, readySource == TDLib.shared.activeUpdateSource,
              action == .account || !AppPasscode.shared.isLocked
        else { return }
        pendingAction = nil
        dismissActiveTelegramContextMenu()
        let navigation = NavigationStorage.shared.navigationController
        let main = navigation.viewControllers.first as? MainViewController
        switch action {
        case .search:
            // TelegramRootController.openChatsController(activateSearch: true)
            TelegramLinkRouter.shared.afterDismissingPresentations {
                NavigationStorage.shared.popToRoot(animated: false)
                main?.activateSearch()
            }
        case .compose:
            // ChatListController.composePressed
            TelegramLinkRouter.shared.afterDismissingPresentations {
                guard !navigation.viewControllers.contains(where: { $0 is ComposeFlowScreen }) else { return }
                navigation.pushViewController(NewMessageViewController(), animated: true)
            }
        case .savedMessages:
            guard let userID = TDLib.shared.activeAccount?.userID else { return }
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-probe-quick-action-saved") {
                    logSavedMessagesTarget(userID: userID)
                    return
                }
            #endif
            TelegramLinkRouter.shared.openUser(userID, from: navigation.topViewController)
        case .account:
            guard let other = Self.otherAccount(
                in: TDLib.shared.accounts,
                activeAccountID: TDLib.shared.activeAccountID,
            ) else { return }
            do {
                try TDLib.shared.switchToAccount(other.id)
            } catch {
                main?.showAccountError(error)
            }
        }
    }
}

#if DEBUG

    // MARK: - HomeScreenQuickActions + Probes

    extension HomeScreenQuickActions {
        /// `-ui-probe-quick-actions`: which items each state of the accounts gets.
        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-quick-actions") else { return }
            func account(_ name: String, userID: Int64?) -> TelegramAccount {
                TelegramAccount(
                    id: UUID(),
                    displayName: name,
                    phoneNumber: nil,
                    userID: userID,
                    createdAt: Date(),
                    lastActiveAt: Date(),
                )
            }
            func described(_ accounts: [TelegramAccount], active: UUID?) -> String {
                items(accounts: accounts, activeAccountID: active)
                    .lazy
.map { [$0.type, $0.localizedSubtitle].compactMap(\.self).joined(separator: ":") }
                    .joined(separator: ",")
            }
            let first = account("First", userID: 1)
            let second = account("Second", userID: 2)
            let third = account("Third", userID: 3)
            let unfinished = account("Unfinished", userID: nil)
            let base = "search,compose,savedMessages"
            let checks: [(String, String, String)] = [
                ("no account", described([], active: nil), ""),
                ("signing in", described([unfinished], active: unfinished.id), ""),
                ("one account", described([first], active: first.id), base),
                ("other still signing in", described([first, unfinished], active: first.id), base),
                ("two accounts", described([first, second], active: first.id), base + ",account:Second"),
                ("from the second", described([first, second], active: second.id), base + ",account:First"),
                ("three accounts", described([third, first, second], active: first.id), base + ",account:Third"),
            ]
            let failures = checks.filter { $0.1 != $0.2 }.map { "\($0.0): \($0.1)" }
            let result = failures.isEmpty
                ? "Quick actions probe passed: \(checks.count) account states"
                : "Quick actions probe failed: \(failures.joined(separator: "; "))"
            log(result)
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("quick-actions-probe.txt"),
                    options: .atomic,
                )
            }
        }

        /// `-ui-probe-quick-action-saved`: resolves the action's chat without showing it, since an automated check
        /// must not open the account's Saved Messages.
        fileprivate func logSavedMessagesTarget(userID: Int64) {
            let client = TDLib.shared.activeClient
            Task {
                let chat = try? await client.createPrivateChat(force: false, userId: userID)
                let customChat =
 if let chat {
                    await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client)
                } else {
                    CustomChat?.none
                }
                let result = "Quick action Saved Messages probe: resolved=\(customChat != nil), "
                    + "isSavedMessages=\(customChat?.isSavedMessages == true)"
                log(result)
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("quick-action-saved-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }
    }
#endif
