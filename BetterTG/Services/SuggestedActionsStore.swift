// SuggestedActionsStore.swift

import Combine
import Foundation
import TDLibKit

// MARK: - SuggestedActionsStore

/// Telegram's server-provided suggestions (`ServerProvidedSuggestion`) as TDLib lists them in `updateSuggestedActions`,
/// kept per account for the client that sent them. Settings shows the phone number, password and password setup
/// reminders from them.
@MainActor final class SuggestedActionsStore {
    /// The Settings reminder a suggestion asks for, in PeerInfoSettingsItems' order of precedence.
    enum Reminder: Equatable {
        case checkPhoneNumber
        case checkPassword
        case setPassword
    }

    private struct List {
        let source: TdUpdateSource
        var actions: [TDNativeSuggestedAction]
    }

    static let shared = SuggestedActionsStore()

    /// Any change to an account's suggestions; Settings reloads.
    let changes = PassthroughSubject<Void, Never>()

    private var lists = [UUID: List]()
    private var cancellables = Set<AnyCancellable>()

    private static func rank(_ notice: ChatListNotice) -> Int {
        switch notice {
        case .accountFrozen: -1
        case .reviewLogin: 0
        case .setupPassword: 1
        case .setupPhoto: 2
        case .setupBirthday: 3
        case .link: 4
        }
    }

    func start() {
        guard cancellables.isEmpty else { return }
        nc.scopedPublisher(&cancellables, for: .updateSuggestedActions) { [weak self] update in
            self?.apply(added: update.value.addedActions, removed: update.value.removedActions, source: update.source)
        }
    }

    /// The reminder Settings shows for the account: a phone number check first, then a password check, then a
    /// password to set up.
    func reminder(for source: TdUpdateSource?) -> Reminder? {
        #if DEBUG
            // `-ui-probe-settings-suggestion check-phone|check-password|set-password` shows one on any account.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-ui-probe-settings-suggestion") {
                switch arguments[safe: index + 1] {
                case "check-password": return .checkPassword
                case "set-password": return .setPassword
                default: return .checkPhoneNumber
                }
            }
        #endif
        guard let source, let list = lists[source.accountID], list.source == source else { return nil }
        let actions = list.actions
        if actions.contains(where: {
            if case .suggestedActionCheckPhoneNumber = $0 {
                true
            } else {
                false
            }
        }) {
            return .checkPhoneNumber
        }
        if actions.contains(where: {
            if case .suggestedActionCheckPassword = $0 {
                true
            } else {
                false
            }
        }) {
            return .checkPassword
        }
        if actions.contains(where: {
            if case .suggestedActionSetPassword = $0 {
                true
            } else {
                false
            }
        }) {
            return .setPassword
        }
        return nil
    }

    /// GlobalControlPanelsContext's suggested chat list notice for the account: a password to set up, then a photo, a
    /// birthday, then the server's own suggestion. The caller drops the photo and birthday ones the account already
    /// has.
    func chatListNotices(for source: TdUpdateSource?) -> [ChatListNotice] {
        #if DEBUG
            // `-ui-probe-chat-list-notice password|photo|birthday|link` shows one on any account.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-ui-probe-chat-list-notice") {
                switch arguments[safe: index + 1] {
                case "password": return [.setupPassword]
                case "photo": return [.setupPhoto]
                case "birthday": return [.setupBirthday]
                default: return [.link(
                    name: "probe", title: "Telegram Tips", text: "Learn what's new in Telegram.",
                    url: "https://telegram.org/blog",
                )]
                }
            }
        #endif
        guard let source, let list = lists[source.accountID], list.source == source else { return [] }
        var notices = [ChatListNotice]()
        for action in list.actions {
            switch action {
            case .suggestedActionSetPassword: notices.append(.setupPassword)
            case .suggestedActionSetProfilePhoto: notices.append(.setupPhoto)
            case .suggestedActionSetBirthdate: notices.append(.setupBirthday)
            default: break
            }
        }
        notices.sort { Self.rank($0) < Self.rank($1) }
        for action in list.actions {
            if case .suggestedActionCustom(let custom) = action {
                notices.append(.link(
                    name: custom.name, title: custom.title.text, text: custom.description.text, url: custom.url,
                ))
            }
        }
        return notices
    }

    /// dismissChatListNotice: the notice's suggestion is hidden on the server and leaves at once.
    func dismiss(_ notice: ChatListNotice, client: TDLibClient, source: TdUpdateSource) {
        let action: TDNativeSuggestedAction? = lists[source.accountID]?.actions.first { action in
            switch (notice, action) {
            case (.setupBirthday, .suggestedActionSetBirthdate),
                 (.setupPassword, .suggestedActionSetPassword),
                 (.setupPhoto, .suggestedActionSetProfilePhoto): true
            case (.link(let name, _, _, _), .suggestedActionCustom(let custom)): custom.name == name
            default: false
            }
        }
        guard let action else { return }
        apply(added: [], removed: [action], source: source)
        Task { _ = try? await client.send(TDNativeRequests.hideSuggestedAction(action: action)) }
    }

    /// dismissServerProvidedSuggestion: hideSuggestedAction, and the reminder leaves at once.
    func dismiss(_ reminder: Reminder, client: TDLibClient, source: TdUpdateSource) {
        let action: TDNativeSuggestedAction? = lists[source.accountID]?.actions.first { action in
            switch (reminder, action) {
            case (.checkPassword, .suggestedActionCheckPassword),
                 (.checkPhoneNumber, .suggestedActionCheckPhoneNumber),
                 (.setPassword, .suggestedActionSetPassword): true
            default: false
            }
        }
        guard let action else { return }
        apply(added: [], removed: [action], source: source)
        Task { _ = try? await client.send(TDNativeRequests.hideSuggestedAction(action: action)) }
    }

    private func apply(added: [TDNativeSuggestedAction], removed: [TDNativeSuggestedAction], source: TdUpdateSource) {
        var list = lists[source.accountID].flatMap { $0.source == source ? $0 : nil }
            ?? List(source: source, actions: [])
        let removedKinds = Set(removed.map(\.typeID))
        list.actions.removeAll { removedKinds.contains($0.typeID) }
        let present = Set(list.actions.map(\.typeID))
        list.actions += added.filter { !present.contains($0.typeID) }
        lists[source.accountID] = list
        changes.send()
    }
}
