// ChatReactionsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatReactionsViewController

/// peerAllowedReactionListController. A group: All Reactions, Some Reactions or No Reactions with the note for the
/// choice, then, for Some, AVAILABLE REACTIONS, each active emoji with its title and a switch (switching to Some starts
/// from 👍 and 👎). A channel: Allow Reactions, then the reactions. What changed is saved as the screen goes
/// (setChatAvailableReactions), the reaction limit kept. Telegram's channel screen (PeerAllowedReactionsScreen, with
/// custom emoji, the reaction limit and paid reactions) isn't ported; channels use the list.
final class ChatReactionsViewController: SettingsListViewController {
    private enum Mode {
        case all
        case some
        case none
    }

    var onChange: ((TDNativeChatAvailableReactions) -> Void)?

    private let chatID: Int64
    private let isChannel: Bool
    private let initial: TDNativeChatAvailableReactions
    private var mode: Mode
    private var allowed: Set<String>
    private var reactions = [(emoji: String, title: String)]()

    private var maxReactionCount: Int {
        switch initial {
        case .chatAvailableReactionsAll(let all): all.maxReactionCount
        case .chatAvailableReactionsSome(let some): some.maxReactionCount
        }
    }

    init(chatID: Int64, isChannel: Bool, available: TDNativeChatAvailableReactions) {
        self.chatID = chatID
        self.isChannel = isChannel
        self.initial = available
        switch available {
        case .chatAvailableReactionsAll:
            self.mode = .all
            self.allowed = []
        case .chatAvailableReactionsSome(let some):
            let emojis = some.reactions.compactMap { reaction -> String? in
                if case .reactionTypeEmoji(let emoji) = reaction { return emoji.emoji }
                return nil
            }
            self.mode = emojis.isEmpty ? .none : .some
            self.allowed = Set(emojis)
        }
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PeerInfo.AllowedReactions.Title")
        let client = client
        let emojis = DefaultReactionType.shared.activeEmojis(for: client)
        Task { [weak self] in
            var loaded = [(emoji: String, title: String)]()
            for emoji in emojis {
                let reaction = try? await client.send(TDNativeRequests.getEmojiReaction(emoji: emoji))
                loaded.append((emoji, reaction?.title ?? emoji))
            }
            guard let self, contextIsCurrent else { return }
            reactions = loaded
            if case .all = mode { allowed = Set(loaded.map(\.emoji)) }
            reload()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        save()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection]()
        if isChannel {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("PeerInfo.AllowedReactions.AllowAllText"),
                accessory: .toggle(isOn: mode != .none) { [weak self] isOn in
                    self?.setMode(isOn ? .all : .none)
                },
            )]))
        } else {
            let choices: [(Mode, String)] = [
                (.all, "PeerInfo.AllowedReactions.OptionAllReactions"),
                (.some, "PeerInfo.AllowedReactions.OptionSomeReactions"),
                (.none, "PeerInfo.AllowedReactions.OptionNoReactions"),
            ]
            let footer =
                switch mode {
                case .all: "PeerInfo.AllowedReactions.GroupOptionAllInfo"
                case .some: "PeerInfo.AllowedReactions.GroupOptionSomeInfo"
                case .none: "PeerInfo.AllowedReactions.GroupOptionNoInfo"
                }
            sections.append(SettingsSection(
                header: L10n.telegram("PeerInfo.AllowedReactions.ReactionListHeader"),
                footer: L10n.telegram(footer),
                rows: choices.map { choice, key in
                    SettingsRow(
                        title: L10n.telegram(key),
                        accessory: mode == choice ? .checkmark : .none,
                    ) { [weak self] in self?.setMode(choice) }
                },
            ))
        }
        let showsList = isChannel ? mode != .none : mode == .some
        if showsList, !reactions.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("PeerInfo.AllowedReactions.ReactionListHeader"),
                rows: reactions.map { reaction in
                    SettingsRow(
                        title: "\(reaction.emoji)  \(reaction.title)",
                        accessory: .toggle(isOn: allowed.contains(reaction.emoji)) { [weak self] isOn in
                            self?.toggle(reaction.emoji, isOn: isOn)
                        },
                    )
                },
            ))
        }
        return sections
    }

    /// The row's value in the chat's settings: All Reactions, Disabled, or how many are allowed.
    static func summary(_ available: TDNativeChatAvailableReactions) -> String {
        switch available {
        case .chatAvailableReactionsAll:
            L10n.telegram("PeerInfo.LabelAllReactions")
        case .chatAvailableReactionsSome(let some):
            some.reactions.isEmpty
                ? L10n.telegram("PeerInfo.ReactionsDisabled")
                : some.reactions.count.formatted(.number)
        }
    }

    private static func emojis(_ available: TDNativeChatAvailableReactions) -> Set<String> {
        guard case .chatAvailableReactionsSome(let some) = available else { return ["*"] }
        return Set(some.reactions.compactMap { reaction in
            if case .reactionTypeEmoji(let emoji) = reaction { return emoji.emoji }
            return nil
        })
    }

    /// setMode: Some starts from 👍 and 👎, All takes every reaction, No takes none.
    private func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        allowed =
            switch newMode {
            case .all: Set(reactions.map(\.emoji))
            case .some: Set(["👍", "👎"].filter { emoji in reactions.contains { $0.emoji == emoji } })
            case .none: []
            }
        reload()
    }

    /// A channel turned down to none goes back to all once one is on again.
    private func toggle(_ emoji: String, isOn: Bool) {
        if isOn { allowed.insert(emoji) } else { allowed.remove(emoji) }
        if isChannel { mode = allowed.isEmpty ? .none : allowed.count == reactions.count ? .all : .some }
    }

    private func save() {
        let updated: TDNativeChatAvailableReactions =
            switch mode {
            case .all:
                .chatAvailableReactionsAll(TDNativeChatAvailableReactionsAll(maxReactionCount: maxReactionCount))
            case .some:
                .chatAvailableReactionsSome(TDNativeChatAvailableReactionsSome(
                    // In the list's order; without the list yet, as they were.
                    reactions: (reactions.isEmpty ? allowed.sorted() : reactions.map(\.emoji).filter(allowed.contains))
                        .map { .reactionTypeEmoji(.init(emoji: $0)) },
                    maxReactionCount: maxReactionCount,
                ))
            case .none:
                .chatAvailableReactionsSome(TDNativeChatAvailableReactionsSome(
                    reactions: [], maxReactionCount: maxReactionCount,
                ))
            }
        guard Self.summary(updated) != Self.summary(initial) || Self.emojis(updated) != Self.emojis(initial)
        else { return }
        onChange?(updated)
        let client = client
        let chatID = chatID
        Task {
            _ = try? await client.send(TDNativeRequests.setChatAvailableReactions(
                chatId: chatID, availableReactions: updated,
            ))
        }
    }
}
