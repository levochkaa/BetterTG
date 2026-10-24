// ChatListChatRemoval.swift

import TDLibKit
import UIKit

// MARK: - ChatListChatRemoval

/// Telegram's chat-list Delete flow (ChatListController: deletePeerChat, maybeAskForPeerChatRemoval and
/// schedulePeerChatRemoval) on TDLib. A private chat is deleted with deleteChatHistory, a group or channel is left, and
/// its owner may delete it for everyone with deleteChat. Every request runs on the row's own client and is dropped once
/// that account, client or page is no longer current.
@MainActor final class ChatListChatRemoval {
    // MARK: Private

    private enum Peer {
        case savedMessages
        case user(User)
        case bot(User)
        case basicGroup(BasicGroup)
        case supergroup(Supergroup)
    }

    private let chat: CustomChat
    private let client: TDLibClient
    private let scope: ChatListActionScope
    private weak var host: UIViewController?
    private let showStatus: (String) -> Void
    /// The chat list's Undo toast; without it (the profile) a confirmed request runs at once.
    private let showUndo: ((String, @escaping () -> Void) -> Void)?
    private let peer: Peer

    private var title: String {
        chat.displayTitle
    }

    /// Telegram's compact display title: a person's first name, otherwise the chat title.
    private var compactTitle: String {
        if let firstName = chat.user?.firstName.trimmingCharacters(in: .whitespacesAndNewlines), !firstName.isEmpty {
            return firstName
        }
        return title
    }

    /// The last message says the user just joined Telegram; Telegram then offers a single Delete.
    private var isJoinNotice: Bool {
        if case .messageContactRegistered? = chat.lastMessage?.content { return true }
        return false
    }

    private var isDeletedAccount: Bool {
        chat.user?.isDeletedAccount == true
    }

    private var isChannel: Bool {
        if case .supergroup(let group) = peer { return group.isChannel }
        return false
    }

    private var isCreator: Bool {
        switch peer {
        case .basicGroup(let group): group.status.isCreator
        case .supergroup(let group): group.status.isCreator
        case .bot,
             .savedMessages,
             .user: false
        }
    }

    init(
        chat: CustomChat,
        client: TDLibClient,
        scope: ChatListActionScope,
        host: UIViewController,
        showUndo: ((String, @escaping () -> Void) -> Void)? = nil,
        showStatus: @escaping (String) -> Void,
    ) {
        self.chat = chat
        self.client = client
        self.scope = scope
        self.host = host
        self.showUndo = showUndo
        self.showStatus = showStatus
        self.peer =
            switch chat.type {
            case .user(let user): chat.isSavedMessages ? .savedMessages : .user(user)
            case .bot(let user): .bot(user)
            case .group(let group): .basicGroup(group)
            case .supergroup(let group): .supergroup(group)
            }
    }

    // MARK: Internal

    func start() {
        guard scope.isCurrent else { return }
        // Telegram asks right away about a person whose chat it can delete for both sides.
        if case .user(let user) = peer, chat.chat.canBeDeletedForAllUsers || user.isDeletedAccount {
            askPrivateChatRemoval()
        } else {
            presentDeleteSheet()
        }
    }

    // MARK: Sheets

    /// The delete sheet for everything Telegram does not delete straight from the alert: bots, Saved Messages, groups,
    /// channels and people whose chat can be deleted only for this account.
    private func presentDeleteSheet() {
        var canClear = true
        var canStop = false
        var canRemoveGlobally = false
        var deleteTitle = L10n.telegram("Common.Delete")
        switch peer {
        case .supergroup(let group):
            if group.isDirectMessagesGroup {
                canClear = false
            } else {
                let isPublic = group.usernames?.activeUsernames.isEmpty == false
                if group.isChannel {
                    canClear = false
                    deleteTitle = L10n.telegram("Channel.LeaveChannel")
                } else {
                    deleteTitle = L10n.telegram("Group.DeleteGroup")
                }
                // Telegram (canDeletePeerGloballyAsCreator) deletes only a private group or channel for everyone.
                canRemoveGlobally = group.status.isCreator && !isPublic && chat.chat.canBeDeletedForAllUsers
                // TDLib clears supergroup history only for a member of a private group without topics.
                canClear = canClear && !isPublic && chat.chat.canBeDeletedOnlyForSelf
            }
        case .basicGroup:
            canRemoveGlobally = chat.chat.canBeDeletedForAllUsers
        case .bot(let user):
            canStop = !user.isSupport
            deleteTitle = L10n.telegram("ChatList.DeleteChat")
        case .savedMessages,
             .user:
            break
        }

        switch peer {
        case .basicGroup,
             .supergroup:
            guard canRemoveGlobally else { break }
            let sheet = makeSheet(L10n.telegram("ChatList.DeleteAndLeaveGroupConfirmation", title))
            sheet.addAction(destructive(L10n.telegram("ChatList.DeleteForCurrentUser")) { $0.leave() })
            let deleteForAll = isChannel ? "ChatList.DeleteForAllSubscribers" : "ChatList.DeleteForAllMembers"
            sheet.addAction(destructive(L10n.telegram(deleteForAll)) { flow in
                let text = flow.isChannel
                    ? "ChannelInfo.DeleteChannelConfirmation"
                    : "ChannelInfo.DeleteGroupConfirmation"
                flow.confirmWarning(text: L10n.telegram(text)) { $0.deleteForEveryone() }
            })
            present(sheet)
            return
        case .bot,
             .savedMessages,
             .user:
            break
        }

        let message =
            switch peer {
            case .savedMessages: L10n.telegram("ChatList.DeleteSavedMessagesConfirmation")
            case .basicGroup,
                 .supergroup: L10n.telegram("ChatList.LeaveGroupConfirmation", title)
            case .bot,
                 .user: L10n.telegram("ChatList.DeleteChatConfirmation", title)
            }
        let sheet = makeSheet(message)
        if canStop, case .bot(let bot) = peer {
            let botID = bot.id
            sheet.addAction(destructive(L10n.telegram("DialogList.DeleteBotConversationConfirmation")) {
                $0.deletePrivateChat(revoke: false, blockingBotID: botID)
            })
        }
        if canClear {
            let clearTitle = canStop ? "DialogList.DeleteBotClearHistory" : "DialogList.ClearHistoryConfirmation"
            sheet.addAction(action(L10n.telegram(clearTitle), style: .default) { $0.askClearHistory() })
        }
        if !canStop {
            sheet.addAction(destructive(deleteTitle) { $0.deleteForSelf() })
        }
        present(sheet)
    }

    /// Telegram's alert for a person: delete just for me, or for both sides after a second warning.
    private func askPrivateChatRemoval() {
        let alert = UIAlertController(
            title: L10n.telegram("ChatList.DeleteChat"),
            message: L10n.telegram("ChatList.DeleteChatConfirmation", title).withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        if isJoinNotice || isDeletedAccount {
            let revoke = chat.chat.canBeDeletedForAllUsers
            alert.addAction(destructive(L10n.telegram("Common.Delete")) { $0.deletePrivateChat(revoke: revoke) })
        } else {
            alert.addAction(destructive(L10n.telegram("ChatList.DeleteForCurrentUser")) {
                $0.deletePrivateChat(revoke: false)
            })
            alert.addAction(destructive(L10n.telegram("ChatList.DeleteForEveryone", compactTitle)) { flow in
                flow.confirmWarning(text: L10n.telegram("ChatList.DeleteForEveryoneConfirmationText")) {
                    $0.deletePrivateChat(revoke: true)
                }
            })
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(alert)
    }

    /// Telegram's Clear History: a for-me or for-both choice where TDLib can revoke, otherwise one warning.
    private func askClearHistory() {
        let isPrivate =
            switch peer {
            case .bot,
                 .user: true
            case .basicGroup,
                 .savedMessages,
                 .supergroup: false
            }
        guard isPrivate, chat.chat.canBeDeletedForAllUsers else {
            confirmSavedMessagesWarning { $0.clearHistory(revoke: false) }
            return
        }
        let sheet = makeSheet(L10n.telegram("ChatList.ClearChatConfirmation", title))
        if isJoinNotice || isDeletedAccount {
            sheet.addAction(destructive(L10n.telegram("Common.Delete")) { $0.clearHistory(revoke: true) })
        } else {
            sheet.addAction(destructive(L10n.telegram("ChatList.DeleteForCurrentUser")) {
                $0.clearHistory(revoke: false)
            })
            sheet.addAction(destructive(L10n.telegram("ChatList.DeleteForEveryone", compactTitle)) {
                $0.clearHistory(revoke: true)
            })
        }
        present(sheet)
    }

    /// The sheet's own Delete or Leave item, which never deletes for everyone.
    private func deleteForSelf() {
        switch peer {
        case .savedMessages:
            confirmSavedMessagesWarning { $0.deletePrivateChat(revoke: false) }
        case .bot,
             .user:
            deletePrivateChat(revoke: false)
        case .basicGroup,
             .supergroup:
            leave()
        }
    }

    /// Telegram warns an owner who leaves which member takes the chat over.
    private func leave() {
        guard scope.isCurrent else { return }
        guard isCreator else {
            commitLeave()
            return
        }
        let client = client
        let scope = scope
        let chatID = chat.id
        Task {
            let nextOwner: User?
            do {
                nextOwner = try await scope.perform {
                    try await client.send(TDNativeRequests.getChatOwnerAfterLeaving(chatId: chatID))
                }
            } catch is CancellationError {
                return
            } catch {
                // Telegram leaves without the warning when there is no next owner.
                nextOwner = nil
            }
            guard scope.isCurrent else { return }
            if let nextOwner {
                confirmLeave(nextOwner: nextOwner)
            } else {
                commitLeave()
            }
        }
    }

    private func confirmLeave(nextOwner: User) {
        let ownerName = [nextOwner.firstName, nextOwner.lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let text =
            if case .basicGroup = peer {
                L10n.telegram("LeaveGroup.LegacyGroupText", ownerName, title)
            } else {
                L10n.telegram("LeaveGroup.Text", ownerName, title)
            }
        let alert = UIAlertController(
            title: L10n.telegram("LeaveGroup.Title", title),
            message: text.withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(destructive(L10n.telegram("LeaveGroup.Proceed")) { $0.commitLeave() })
        present(alert)
    }

    /// Telegram's "Warning!" alert before an irreversible deletion.
    private func confirmWarning(
        title: String = L10n.telegram("ChatList.DeleteForEveryoneConfirmationTitle"),
        text: String,
        actionTitle: String = L10n.telegram("ChatList.DeleteForEveryoneConfirmationAction"),
        perform: @escaping (ChatListChatRemoval) -> Void,
    ) {
        let alert = UIAlertController(
            title: title,
            message: text.withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(destructive(actionTitle, perform))
        present(alert)
    }

    /// Telegram's warning before deleting all messages without a for-everyone choice.
    private func confirmSavedMessagesWarning(perform: @escaping (ChatListChatRemoval) -> Void) {
        confirmWarning(
            title: L10n.telegram("ChatList.DeleteSavedMessagesConfirmationTitle"),
            text: L10n.telegram("ChatList.DeleteSavedMessagesConfirmationText"),
            actionTitle: L10n.telegram("ChatList.DeleteSavedMessagesConfirmationAction"),
            perform: perform,
        )
    }

    // MARK: Requests

    private func deletePrivateChat(revoke: Bool, blockingBotID: Int64? = nil) {
        let chatID = chat.id
        execute(
            status: L10n.telegram(revoke ? "Undo.ChatDeletedForBothSides" : "Undo.ChatDeleted"),
            hidesRow: true,
        ) { client, scope in
            _ = try await scope.perform {
                try await client.deleteChatHistory(chatId: chatID, removeFromChatList: true, revoke: revoke)
            }
            guard let blockingBotID else { return }
            _ = try await scope.perform {
                try await client.send(TDNativeRequests.setMessageSenderBlockList(
                    senderId: .messageSenderUser(MessageSenderUser(userId: blockingBotID)),
                    blockList: .blockListMain,
                ))
            }
        }
    }

    /// Leaves a group or channel. A left basic group stays listed until its history is deleted, which Telegram's
    /// removePeerChat also does.
    private func commitLeave() {
        let chatID = chat.id
        let peer = peer
        execute(status: L10n.telegram(isChannel ? "Undo.LeftChannel" : "Undo.LeftGroup"), hidesRow: true) {
            client, scope in
            switch peer {
            case .basicGroup(let group):
                if group.isActive, group.status.isMember {
                    _ = try await scope.perform { try await client.send(TDNativeRequests.leaveChat(chatId: chatID)) }
                }
                _ = try await scope.perform {
                    try await client.deleteChatHistory(chatId: chatID, removeFromChatList: true, revoke: false)
                }
            case .supergroup:
                _ = try await scope.perform { try await client.send(TDNativeRequests.leaveChat(chatId: chatID)) }
            case .bot,
                 .savedMessages,
                 .user:
                return
            }
        }
    }

    private func deleteForEveryone() {
        let chatID = chat.id
        execute(status: L10n.telegram(isChannel ? "Undo.DeletedChannel" : "Undo.DeletedGroup"), hidesRow: true) {
            client, scope in
            _ = try await scope.perform { try await client.send(TDNativeRequests.deleteChat(chatId: chatID)) }
        }
    }

    private func clearHistory(revoke: Bool) {
        let chatID = chat.id
        execute(status: L10n.telegram("Undo.ChatCleared"), hidesRow: false) { client, scope in
            _ = try await scope.perform {
                try await client.deleteChatHistory(chatId: chatID, removeFromChatList: false, revoke: revoke)
            }
        }
    }

    /// Runs the confirmed request, then shows Telegram's status toast or its generic error. In the chat list it is
    /// scheduled behind the Undo toast instead, with the row hidden for a removal, as Telegram does.
    private func execute(
        status: String,
        hidesRow: Bool,
        _ operation: @escaping @MainActor (TDLibClient, ChatListActionScope) async throws -> Void,
    ) {
        guard scope.isCurrent else { return }
        let client = client
        let scope = scope
        let showStatus = showStatus
        let host = host
        if let showUndo {
            let cancel = PendingChatRemovals.shared.schedule(
                PendingChatRemovals.Key(clientID: client.id, chatID: chat.id),
                hides: hidesRow,
            ) { [weak host] in
                guard scope.isCurrent else { return }
                do {
                    try await operation(client, scope)
                } catch {
                    guard scope.isCurrent, let host else { return }
                    host.presentChatListActionFailure()
                }
            }
            showUndo(status, cancel)
            return
        }
        Task { [weak host] in
            do {
                try await operation(client, scope)
                try scope.check()
                showStatus(status)
            } catch {
                guard scope.isCurrent, let host else { return }
                host.presentChatListActionFailure()
            }
        }
    }

    // MARK: Presentation

    private func makeSheet(_ message: String) -> UIAlertController {
        UIAlertController(title: nil, message: message.withoutTelegramMarkup, preferredStyle: .actionSheet)
    }

    private func destructive(
        _ title: String,
        _ perform: @escaping (ChatListChatRemoval) -> Void,
    ) -> UIAlertAction {
        action(title, style: .destructive, perform)
    }

    /// Each step re-checks the row's account, client and page before it acts.
    private func action(
        _ title: String,
        style: UIAlertAction.Style,
        _ perform: @escaping (ChatListChatRemoval) -> Void,
    ) -> UIAlertAction {
        UIAlertAction(title: title, style: style) { _ in
            guard self.scope.isCurrent else { return }
            perform(self)
        }
    }

    private func present(_ alert: UIAlertController) {
        guard scope.isCurrent, let host else { return }
        if alert.preferredStyle == .actionSheet {
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            alert.popoverPresentationController?.sourceView = host.view
            alert.popoverPresentationController?.sourceRect = CGRect(
                x: host.view.bounds.midX,
                y: host.view.bounds.midY,
                width: 0,
                height: 0,
            )
        }
        host.chatListTopPresenter.present(alert, animated: true)
    }
}

// MARK: - Helpers

extension UIViewController {
    /// Telegram reports a failed chat-list action with its generic error alert.
    func presentChatListActionFailure() {
        let alert = UIAlertController(title: nil, message: L10n.telegram("Login.UnknownError"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        chatListTopPresenter.present(alert, animated: true)
    }

    /// The controller that can present now: this one, or whatever it or its ancestors already present.
    var chatListTopPresenter: UIViewController {
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }
}

extension String {
    /// Telegram strings mark bold text with a double asterisk, which a plain UIKit alert would show literally.
    var withoutTelegramMarkup: String {
        replacingOccurrences(of: "**", with: "")
    }
}

private extension User {
    var isDeletedAccount: Bool {
        if case .userTypeDeleted = type { return true }
        return false
    }
}

private extension ChatMemberStatus {
    var isCreator: Bool {
        if case .chatMemberStatusCreator = self { return true }
        return false
    }

    var isMember: Bool {
        switch self {
        case .chatMemberStatusAdministrator,
             .chatMemberStatusMember: true
        case .chatMemberStatusCreator(let creator): creator.isMember
        case .chatMemberStatusRestricted(let restricted): restricted.isMember
        case .chatMemberStatusBanned,
             .chatMemberStatusLeft: false
        }
    }
}
