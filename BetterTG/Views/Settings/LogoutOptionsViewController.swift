// LogoutOptionsViewController.swift

import UIKit

// MARK: - LogoutOptionsViewController

/// Telegram's LogoutOptionsController: ALTERNATIVE OPTIONS to logging out (Add another account, Set a Passcode while
/// none is set, Clear Cache and Contact Support), then Log Out with "Remember, logging out kills all your Secret
/// Chats." under it, in a modal over Settings. An alternative closes the modal and opens its screen there. Change
/// Phone Number is left out: BetterTG has no such flow. Log Out asks with Settings.LogoutConfirmationText first.
final class LogoutOptionsViewController: SettingsListViewController {
    /// The navigation the modal came from, where the alternatives open.
    private weak var origin: UINavigationController?
    private let logOut: () -> Void

    init(origin: UINavigationController?, logOut: @escaping () -> Void) {
        self.origin = origin
        self.logOut = logOut
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("LogoutOptions.Title")
        let close = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        close.accessibilityLabel = L10n.telegram("Common.Close")
        navigationItem.leftBarButtonItem = close
    }

    override func makeSections() -> [SettingsSection] {
        var rows = [option("AddAccount", symbol: "person.crop.circle.badge.plus", tint: .systemBlue) { [weak self] in
            self?.leave { _ in try? TDLib.shared.addAccount() }
        }]
        if !AppPasscode.shared.isSet {
            rows.append(option("SetPasscode", symbol: "lock.fill", tint: .systemGray) { [weak self] in
                self?.leave { $0.pushViewController(PasscodeOptionsViewController(), animated: true) }
            })
        }
        rows.append(option("ClearCache", symbol: "externaldrive.fill", tint: .systemGreen) { [weak self] in
            self?.leave { $0.pushViewController(StorageUsageViewController(), animated: true) }
        })
        rows.append(option(
            "ContactSupport", symbol: "bubble.left.and.text.bubble.right.fill", tint: .systemOrange,
        ) { [weak self] in self?.contactSupport() })
        return [
            SettingsSection(header: L10n.telegram("LogoutOptions.AlternativeOptionsSection"), rows: rows),
            SettingsSection(footer: L10n.telegram("LogoutOptions.LogOutInfo"), rows: [SettingsRow(
                title: L10n.telegram("LogoutOptions.LogOut"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmLogOut() }]),
        ]
    }

    /// Telegram pushes the options with `.modal` presentation: a sheet with a close button.
    static func present(from controller: UIViewController, logOut: @escaping () -> Void) {
        let options = LogoutOptionsViewController(origin: controller.navigationController, logOut: logOut)
        controller.present(TelegramNavigationController(rootViewController: options), animated: true)
    }

    /// LogoutOptions.<name>Title over its Text, as ItemListDisclosureItem's multiline detail shows them.
    private func option(
        _ name: String,
        symbol: String,
        tint: UIColor,
        action: @escaping () -> Void,
    ) -> SettingsRow {
        SettingsRow(
            title: L10n.telegram("LogoutOptions.\(name)Title"),
            detail: L10n.telegram("LogoutOptions.\(name)Text"),
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

    /// The logout confirmation: Settings.LogoutConfirmationTitle with its text, Cancel and OK, which logs out and
    /// closes
    /// the options.
    private func confirmLogOut() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.telegram("Settings.LogoutConfirmationTitle"),
            message: L10n.telegram("Settings.LogoutConfirmationText")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        let ok = UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self] _ in
            guard let self else { return }
            let logOut = logOut
            dismiss(animated: true) { logOut() }
        }
        alert.addAction(ok)
        alert.preferredAction = ok
        present(alert, animated: true)
    }
}
