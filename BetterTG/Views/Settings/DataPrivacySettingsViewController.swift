// DataPrivacySettingsViewController.swift

import TDLibKit
import UIKit

// MARK: - DataPrivacySettingsViewController

/// Telegram's Data Settings (DataPrivacySettingsController): Delete Synced Contacts behind its warning, Suggest
/// Frequent Contacts (`disable_top_chats`, turned off behind its warning) and Delete All Cloud Drafts behind its
/// sheet, each confirmed with Telegram's toast, and SECRET CHATS' Link Previews. BetterTG doesn't sync device
/// contacts and leaves payments out, so Sync Contacts and Clear Payment Info aren't offered.
final class DataPrivacySettingsViewController: SettingsListViewController {
    /// Whether TDLib suggests frequent contacts; nil until read.
    private var suggestsFrequentContacts: Bool?
    private var isDeletingContacts = false
    private var isDeletingDrafts = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PrivacySettings.DataSettings")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        var contactRows = [SettingsRow(
            title: L10n.telegram("Privacy.ContactsReset"),
            style: .action(destructive: false),
            isEnabled: !isDeletingContacts,
        ) { [weak self] in self?.confirmDeleteContacts() }]
        var contactsFooter: String?
        if let suggestsFrequentContacts {
            contactRows.append(SettingsRow(
                title: L10n.telegram("Privacy.TopPeers"),
                accessory: .toggle(isOn: suggestsFrequentContacts) { [weak self] isOn in
                    self?.setSuggestsFrequentContacts(isOn)
                },
            ))
            contactsFooter = L10n.telegram("Privacy.TopPeersHelp")
        }
        return [
            SettingsSection(header: L10n.telegram("Privacy.ContactsTitle"), footer: contactsFooter, rows: contactRows),
            SettingsSection(header: L10n.telegram("Privacy.ChatsTitle"), rows: [SettingsRow(
                title: L10n.telegram("Privacy.DeleteDrafts"),
                style: .action(destructive: false),
                isEnabled: !isDeletingDrafts,
            ) { [weak self] in self?.confirmDeleteDrafts() }]),
            // secretChatLinkPreviews: on until the user says otherwise.
            SettingsSection(
                header: L10n.telegram("Privacy.SecretChatsTitle"),
                footer: L10n.telegram("Privacy.SecretChatsLinkPreviewsHelp"),
                rows: [SettingsRow(
                    title: L10n.telegram("Privacy.SecretChatsLinkPreviews"),
                    accessory: .toggle(isOn: SecretChatLinkPreviews.isEnabled ?? true) { isOn in
                        SecretChatLinkPreviews.isEnabled = isOn
                    },
                )],
            ),
        ]
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let disabled =
                if case .optionValueBoolean(let value) = try? await client.getOption(name: "disable_top_chats") {
                    value.value
                } else {
                    false
                }
            guard let self, contextIsCurrent else { return }
            suggestsFrequentContacts = !disabled
            reload()
        }
    }

    /// deleteContacts: Telegram's warning, then every contact and the imported ones removed (`deleteAllContacts`:
    /// contacts.deleteContacts and contacts.resetSaved).
    private func confirmDeleteContacts() {
        confirm(
            message: L10n.telegram("Privacy.ContactsResetConfirmation"),
            actionTitle: L10n.telegram("Common.Delete"),
        ) { [weak self] in
            guard let self else { return }
            isDeletingContacts = true
            reload()
            perform(failureText: { [weak self] _ in
                self?.isDeletingContacts = false
                self?.reload()
                return nil
            }) { client in
                let contacts = try await client.send(TDNativeRequests.getContacts())
                if !contacts.userIds.isEmpty {
                    _ = try await client.send(TDNativeRequests.removeContacts(userIds: contacts.userIds))
                }
                _ = try await client.send(TDNativeRequests.clearImportedContacts())
            } completion: { [weak self] in
                guard let self else { return }
                isDeletingContacts = false
                reload()
                showToast(L10n.telegram("Privacy.ContactsReset.ContactsDeleted"))
            }
        }
    }

    /// updateSuggestFrequentContacts: turning it off warns that the data goes first.
    private func setSuggestsFrequentContacts(_ isOn: Bool) {
        let apply = { [weak self] in
            guard let self else { return }
            suggestsFrequentContacts = isOn
            reload()
            perform { client in
                _ = try await client.setOption(
                    name: "disable_top_chats",
                    value: .optionValueBoolean(TDNativeOptionValueBoolean(value: !isOn)),
                )
            } completion: {}
        }
        guard !isOn else {
            apply()
            return
        }
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Privacy.TopPeersWarning"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Privacy.TopPeersDelete"), style: .destructive) { _ in
            apply()
        })
        present(alert, animated: true)
    }

    /// deleteCloudDrafts: Telegram's sheet with the destructive action, then `clearAllDraftMessages`.
    private func confirmDeleteDrafts() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.telegram("Privacy.DeleteDrafts"), style: .destructive) {
            [weak self] _ in
            guard let self else { return }
            isDeletingDrafts = true
            reload()
            perform(failureText: { [weak self] _ in
                self?.isDeletingDrafts = false
                self?.reload()
                return nil
            }) { client in
                _ = try await client.send(TDNativeRequests.clearAllDraftMessages(excludeSecretChats: true))
            } completion: { [weak self] in
                guard let self else { return }
                isDeletingDrafts = false
                reload()
                showToast(L10n.telegram("Privacy.DeleteDrafts.DraftsDeleted"))
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(sheet, animated: true)
    }
}

// MARK: - SecretChatLinkPreviews

/// ApplicationSpecificSharedDataKeys' secretChatLinkPreviews: whether a secret chat's composer previews links; nil
/// until the user answered the first link's question or switched it in Data Settings.
enum SecretChatLinkPreviews {
    private static let key = "BetterTG.secretChatLinkPreviews"

    static var isEnabled: Bool? {
        get { UserDefaults.standard.object(forKey: key) as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
