// PasskeysViewController.swift

import TDLibKit
import UIKit

// MARK: - PasskeysViewController

/// PasskeysScreen's list: the account's login passkeys (getLoginPasskeys), each with its name (Passkey when unnamed)
/// and when it was created and last used, under Your passkeys are stored securely in your password manager. A swipe
/// or a hold deletes one after Delete Passkey? (removeLoginPasskey). BetterTG can't create one: a passkey belongs to
/// the app's associated web domain, which BetterTG has none of.
final class PasskeysViewController: SettingsListViewController {
    private var passkeys: [TDNativePasskey]?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Passkeys.Title")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let passkeys else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        return [SettingsSection(
            header: L10n.telegram("Passkeys.Subtitle"),
            footer: L10n.telegram("Passkeys.ListFooter"),
            rows: passkeys.map { passkey in
                SettingsRow(
                    title: passkey.name.isEmpty ? L10n.telegram("Passkeys.EmptyName") : passkey.name,
                    detail: Self.dates(passkey),
                    style: .subtitle,
                    symbol: "person.badge.key.fill",
                    symbolTint: .systemGreen,
                    swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in self?.confirmDelete(passkey) }),
                )
            },
        )]
    }

    override func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let passkey = passkeys?[safe: indexPath.row] else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [UIAction(
                title: L10n.telegram("Common.Delete"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { _ in self?.confirmDelete(passkey) }])
        })
    }

    /// PasskeysScreenListComponent's subtitle: created …, or created … • used ….
    private static func dates(_ passkey: TDNativePasskey) -> String {
        let format: (Int) -> String = { date in
            Date(timeIntervalSince1970: TimeInterval(date)).formatted(date: .abbreviated, time: .omitted)
        }
        guard passkey.lastUsageDate > 0 else {
            return L10n.telegram("Passkeys.PasskeyCreatedPattern", format(passkey.additionDate))
        }
        return L10n.telegram(
            "Passkeys.PasskeyCreatedAndUsedPattern",
            format(passkey.additionDate),
            format(passkey.lastUsageDate),
        )
    }

    private func load() {
        let client = client
        Task { [weak self] in
            let passkeys = await (try? client.send(TDNativeRequests.getLoginPasskeys()))?.passkeys ?? []
            guard let self, contextIsCurrent else { return }
            self.passkeys = passkeys
            reload()
        }
    }

    /// Delete Passkey? with its reminder to remove it from the password manager.
    private func confirmDelete(_ passkey: TDNativePasskey) {
        let alert = UIAlertController(
            title: L10n.telegram("Passkeys.DeleteAlert.Title"),
            message: L10n.telegram("Passkeys.DeleteAlert.Text"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Passkeys.DeleteAlert.Action"), style: .destructive) {
            [weak self] _ in
            self?.passkeys?.removeAll { $0.id == passkey.id }
            self?.reload()
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.removeLoginPasskey(passkeyId: passkey.id))
            } completion: {}
        })
        present(alert, animated: true)
    }
}
