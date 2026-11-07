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
