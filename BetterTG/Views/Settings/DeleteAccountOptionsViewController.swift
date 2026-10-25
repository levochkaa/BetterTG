// DeleteAccountOptionsViewController.swift

import UIKit

// MARK: - DeleteAccountOptionsViewController

/// Telegram's DeleteAccountOptionsController: the alternatives to deleting the account, then Delete My Account,
/// in a modal over Privacy and Security. An alternative closes the modal and opens its screen there. Change Phone
/// Number and Enable Two-Step Verification are left out: BetterTG has neither flow.
final class DeleteAccountOptionsViewController: SettingsListViewController {
    private static let deleteMessagesFaq = "https://telegram.org/faq#q-can-i-delete-my-messages"

    private let hasPassword: Bool
    /// The navigation the modal came from, where the alternatives open.
    private weak var origin: UINavigationController?

    init(hasPassword: Bool, origin: UINavigationController?) {
        self.hasPassword = hasPassword
        self.origin = origin
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("DeleteAccount.AlternativeOptionsTitle")
        // ItemListNavigationButton's `.icon(.close)`; the classic bar draws an item's own image, not a system item.
        let close = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        close.accessibilityLabel = L10n.telegram("Common.Close")
        navigationItem.leftBarButtonItem = close
    }

    override func makeSections() -> [SettingsSection] {
        let add = SettingsSection(rows: [option(
            "AddAccount",
            symbol: "person.crop.circle.badge.plus",
            tint: .systemBlue,
        ) { [weak self] in
            self?.leave { _ in try? TDLib.shared.addAccount() }
        }])
        var privacyRows = [option("ChangePrivacy", symbol: "lock.fill", tint: .systemGray) { [weak self] in
            // Privacy and Security is under the modal already.
            self?.dismiss(animated: true)
        }]
        if !AppPasscode.shared.isSet {
            privacyRows.append(option("SetPasscode", symbol: "faceid", tint: .systemGreen) { [weak self] in
                self?.leave { $0.pushViewController(PasscodeOptionsViewController(), animated: true) }
            })
        }
        let remove = SettingsSection(rows: [
            option("ClearCache", symbol: "externaldrive.fill", tint: .systemGreen) { [weak self] in
                self?.leave { $0.pushViewController(StorageUsageViewController(), animated: true) }
            },
            option("ClearSyncedContacts", symbol: "person.crop.circle.badge.xmark", tint: .systemOrange) {
                [weak self] in
                self?.leave { $0.pushViewController(DataPrivacySettingsViewController(), animated: true) }
            },
            option("DeleteChats", symbol: "bubble.left.and.bubble.right.fill", tint: .systemRed) { [weak self] in
                self?.leave { origin in
                    let link = L10n.telegram("DeleteAccount.DeleteMessagesURL")
                    let url = URL(string: link.hasPrefix("http") ? link : Self.deleteMessagesFaq)
                    if let url, let top = origin.topViewController { WebBrowser.open(url, from: top) }
                }
            },
        ])
        let support = SettingsSection(rows: [option(
            "ContactSupport",
            symbol: "bubble.left.and.text.bubble.right.fill",
            tint: .systemOrange,
        ) { [weak self] in self?.contactSupport() }])
        let delete = SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("DeleteAccount.DeleteMyAccount"),
            style: .action(destructive: true),
        ) { [weak self] in self?.deleteAccount() }])
        return [add, SettingsSection(rows: privacyRows), remove, support, delete]
    }

    /// Telegram pushes the options with `.modal` presentation: a sheet with a close button.
    static func present(hasPassword: Bool, from controller: UIViewController) {
        let options = DeleteAccountOptionsViewController(
            hasPassword: hasPassword,
            origin: controller.navigationController,
        )
        controller.present(TelegramNavigationController(rootViewController: options), animated: true)
    }

    /// DeleteAccount.Options.<name>Title over its Text, as ItemListDisclosureItem's multiline detail shows them.
    private func option(
        _ name: String,
        symbol: String,
        tint: UIColor,
        action: @escaping () -> Void,
    ) -> SettingsRow {
        SettingsRow(
            title: L10n.telegram("DeleteAccount.Options.\(name)Title"),
            detail: L10n.telegram("DeleteAccount.Options.\(name)Text"),
            style: .subtitle,
            symbol: symbol,
            symbolTint: tint,
            accessory: .disclosure,
            action: action,
        )
    }

    /// Closes the modal, then opens an alternative in the navigation it came from.
    private func leave(then open: @escaping @MainActor (UINavigationController) -> Void) {
        let origin = origin
        dismiss(animated: true) {
            if let origin { open(origin) }
        }
    }

    /// Telegram's support note over the options; FAQ or OK closes them and opens the FAQ or the support chat.
    private func contactSupport() {
        present(TelegramSupport.alert(
            openFaq: { [weak self] in
                self?.leave { origin in origin.topViewController.map(TelegramSupport.openFaq) }
            },
            openChat: { [weak self] in
                self?.leave { origin in origin.topViewController.map(TelegramSupport.openChat) }
            },
        ), animated: true)
    }

    /// Delete My Account replaces the options with the first step, so Back doesn't return to them.
    private func deleteAccount() {
        navigationController?.setViewControllers(
            [DeleteAccountDataViewController(step: .cloud, hasPassword: hasPassword)],
            animated: true,
        )
    }
}
