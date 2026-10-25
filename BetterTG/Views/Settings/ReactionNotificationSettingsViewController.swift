// ReactionNotificationSettingsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ReactionNotificationSettingsViewController

/// ReactionNotificationSettingsController: Notify Me About... reactions to the user's messages and stories, each a
/// switch with From My Contacts or From Everyone under it, which a tap on the row changes; then, while either is on,
/// Show Sender's Name (setReactionNotificationSettings). Telegram's sound choice is not offered, as for the chat
/// categories.
final class ReactionNotificationSettingsViewController: SettingsListViewController {
    private enum Kind {
        case messages
        case stories
    }

    /// The settings' fields, editable before TDLib's immutable value is made from them.
    private struct Values {
        var messageReactionSource: TDNativeReactionNotificationSource
        var storyReactionSource: TDNativeReactionNotificationSource
        var pollVoteSource: TDNativeReactionNotificationSource
        var soundId: Int64
        var showPreview: Bool

        var settings: TDNativeReactionNotificationSettings {
            TDNativeReactionNotificationSettings(
                messageReactionSource: messageReactionSource,
                storyReactionSource: storyReactionSource,
                pollVoteSource: pollVoteSource,
                soundId: soundId,
                showPreview: showPreview,
            )
        }

        init(_ settings: TDNativeReactionNotificationSettings) {
            self.messageReactionSource = settings.messageReactionSource
            self.storyReactionSource = settings.storyReactionSource
            self.pollVoteSource = settings.pollVoteSource
            self.soundId = settings.soundId
            self.showPreview = settings.showPreview
        }
    }

    private var settings: TDNativeReactionNotificationSettings?
    private var changesCancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Notifications.Reactions.Title")
        settings = ReactionNotificationSettingsStore.shared.settings(for: client)
        changesCancellable = ReactionNotificationSettingsStore.shared
            .changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                settings = ReactionNotificationSettingsStore.shared.settings(for: client)
                reload()
            }
        reload()
    }

    override func makeSections() -> [SettingsSection] {
        guard let settings else { return [] }
        var sections = [SettingsSection(
            header: L10n.telegram("Notifications.Reactions.SettingsHeader"),
            rows: [
                row(.messages, source: settings.messageReactionSource),
                row(.stories, source: settings.storyReactionSource),
            ],
        )]
        if settings.messageReactionSource != .reactionNotificationSourceNone
            || settings.storyReactionSource != .reactionNotificationSourceNone
        {
            sections.append(SettingsSection(
                header: L10n.telegram("Notifications.Options").uppercased(),
                rows: [SettingsRow(
                    title: L10n.telegram("Notifications.Stories.DisplayName"),
                    accessory: .toggle(isOn: settings.showPreview) { [weak self] isOn in
                        self?.update { $0.showPreview = isOn }
                    },
                )],
            ))
        }
        return sections
    }

    // MARK: Private

    private func row(_ kind: Kind, source: TDNativeReactionNotificationSource) -> SettingsRow {
        let detail: String? =
            switch source {
            case .reactionNotificationSourceNone: nil
            case .reactionNotificationSourceContacts: L10n.telegram("Notifications.Reactions.SubtitleContacts")
            case .reactionNotificationSourceAll: L10n.telegram("Notifications.Reactions.SubtitleEveryone")
            }
        return SettingsRow(
            title: L10n.telegram(kind == .messages
                ? "Notifications.Reactions.ItemMessages"
                : "Notifications.Reactions.ItemStories"),
            detail: detail,
            detailColor: .tintColor,
            style: .subtitle,
            // toggleMessages and toggleStories: on means from contacts.
            accessory: .toggle(isOn: source != .reactionNotificationSourceNone) { [weak self] isOn in
                self?.setSource(isOn ? .reactionNotificationSourceContacts : .reactionNotificationSourceNone, for: kind)
            },
            action: { [weak self] in self?.presentSourceMenu(for: kind) },
        )
    }

    /// openCategory: Everyone or My Contacts over the row, the current one checked.
    private func presentSourceMenu(for kind: Kind) {
        guard let settings,
              let cell = tableView.cellForRow(at: IndexPath(row: kind == .messages ? 0 : 1, section: 0))
        else { return }
        let current = kind == .messages ? settings.messageReactionSource : settings.storyReactionSource
        let options: [(TDNativeReactionNotificationSource, String)] = [
            (.reactionNotificationSourceAll, L10n.telegram("Notifications.Reactions.SheetValueEveryone")),
            (.reactionNotificationSourceContacts, L10n.telegram("Notifications.Reactions.SheetValueContacts")),
        ]
        let actions = options.map { source, title in
            TelegramContextMenuAction(
                title: title,
                image: current == source ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] in self?.setSource(source, for: kind) }
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    private func setSource(_ source: TDNativeReactionNotificationSource, for kind: Kind) {
        update { settings in
            switch kind {
            case .messages: settings.messageReactionSource = source
            case .stories: settings.storyReactionSource = source
            }
        }
    }

    private func update(_ change: (inout Values) -> Void) {
        guard let current = settings else { return }
        var values = Values(current)
        change(&values)
        let updated = values.settings
        settings = updated
        reload()
        perform { client in
            _ = try await client.send(TDNativeRequests.setReactionNotificationSettings(notificationSettings: updated))
        } completion: {}
    }
}
