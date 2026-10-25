// PasscodeOptionsViewController.swift

import Combine
import LocalAuthentication
import UIKit

// MARK: - PasscodeOptionsViewController

/// PasscodeOptionsController: Turn Passcode On while there is none; otherwise Turn Passcode Off, Change Passcode,
/// Telegram's note on the lock icon, then Lock Telegram's Auto-Lock and Unlock with Face ID.
final class PasscodeOptionsViewController: SettingsListViewController {
    private var cancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PasscodeSettings.Title")
        cancellable = AppPasscode.shared
            .$isSet
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    override func makeSections() -> [SettingsSection] {
        let passcode = AppPasscode.shared
        guard passcode.isSet else {
            return [SettingsSection(footer: L10n.telegram("PasscodeSettings.Help"), rows: [SettingsRow(
                title: L10n.telegram("PasscodeSettings.TurnPasscodeOn"),
                style: .action(destructive: false),
                action: { [weak self] in self?.turnOn() },
            )])]
        }
        var lockRows = [SettingsRow(
            title: L10n.telegram("PasscodeSettings.AutoLock"),
            detail: Self.autoLockText(passcode.autoLockTimeout),
            accessory: .disclosure,
            action: { [weak self] in self?.presentAutoLockMenu() },
        )]
        let biometry = passcode.biometryType
        if biometry == .faceID || biometry == .touchID {
            lockRows.append(SettingsRow(
                title: L10n.telegram(biometry == .faceID
                    ? "PasscodeSettings.UnlockWithFaceId"
                    : "PasscodeSettings.UnlockWithTouchId"),
                accessory: .toggle(isOn: passcode.usesBiometrics) { isOn in AppPasscode.shared.usesBiometrics = isOn },
            ))
        }
        return [
            SettingsSection(footer: L10n.telegram("PasscodeSettings.Help"), rows: [
                SettingsRow(
                    title: L10n.telegram("PasscodeSettings.TurnPasscodeOff"),
                    style: .action(destructive: false),
                    action: { [weak self] in self?.confirmTurnOff() },
                ),
                SettingsRow(
                    title: L10n.telegram("PasscodeSettings.ChangePasscode"),
                    style: .action(destructive: false),
                    action: { [weak self] in self?.change() },
                ),
            ]),
            SettingsSection(header: L10n.telegram("PasscodeSettings.LockTelegram").uppercased(), rows: lockRows),
        ]
    }

    // MARK: Private

    static func autoLockText(_ timeout: Int?) -> String {
        switch timeout {
        case 60: L10n.telegram("PasscodeSettings.AutoLock.IfAwayFor_1minute")
        case 5 * 60: L10n.telegram("PasscodeSettings.AutoLock.IfAwayFor_5minutes")
        case 60 * 60: L10n.telegram("PasscodeSettings.AutoLock.IfAwayFor_1hour")
        case 5 * 60 * 60: L10n.telegram("PasscodeSettings.AutoLock.IfAwayFor_5hours")
        default: L10n.telegram("PasscodeSettings.AutoLock.Disabled")
        }
    }

    private func turnOn() {
        let setup = PasscodeSetupViewController(mode: .create) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(setup, animated: true)
    }

    private func change() {
        let setup = PasscodeSetupViewController(mode: .change) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(setup, animated: true)
    }

    private func confirmTurnOff() {
        confirm(
            message: L10n.telegram("PasscodeSettings.TurnPasscodeOff"),
            actionTitle: L10n.telegram("PasscodeSettings.TurnPasscodeOff"),
        ) {
            AppPasscode.shared.removePasscode()
        }
    }

    /// Auto-Lock's choices, the current one checked.
    private func presentAutoLockMenu() {
        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) else { return }
        let current = AppPasscode.shared.autoLockTimeout
        let actions = AppPasscode.autoLockTimeouts.map { timeout in
            TelegramContextMenuAction(
                title: Self.autoLockText(timeout),
                image: timeout == current ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] in
                AppPasscode.shared.autoLockTimeout = timeout
                self?.reload()
            }
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }
}
