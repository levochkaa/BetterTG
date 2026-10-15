// GlobalAutoDeleteViewController.swift

import TDLibKit
import UIKit

// MARK: - GlobalAutoDeleteViewController

/// Telegram's GlobalAutoremoveScreen: Off, 1 day, 1 week or 1 month for new chats the account starts
/// (setDefaultMessageAutoDeleteTime). Turning it on asks first, as Telegram does. Custom times and applying the timer
/// to existing chats are not offered.
final class GlobalAutoDeleteViewController: SettingsListViewController {
    var onChange: ((Int) -> Void)?

    private var currentTime: Int

    init(currentTime: Int) {
        self.currentTime = currentTime
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("GlobalAutodeleteSettings.Title")
    }

    override func makeSections() -> [SettingsSection] {
        let day = 24 * 60 * 60
        var values = [0, day, 7 * day, 31 * day]
        if !values.contains(currentTime) { values.append(currentTime) }
        values.sort()
        return [SettingsSection(
            header: L10n.telegram("GlobalAutodeleteSettings.OptionsHeader"),
            footer: L10n
                .telegram(currentTime == 0 ? "GlobalAutodeleteSettings.InfoDisabled" : "Settings.AutoDeleteInfo"),
            rows: values.map { value in
                SettingsRow(
                    title: value == 0
                        ? L10n.telegram("Autoremove.OptionOff")
                        : L10n.telegram(
                            "GlobalAutodeleteSettings.OptionTitle",
                            SettingsFormatting.timeInterval(seconds: value),
                        ),
                    accessory: value == currentTime ? .checkmark : .none,
                ) { [weak self] in self?.select(value) }
            },
        )]
    }

    private func select(_ value: Int) {
        guard value != currentTime else { return }
        guard value != 0 else {
            save(value)
            return
        }
        let interval = SettingsFormatting.timeInterval(seconds: value)
        confirm(
            title: L10n.telegram("GlobalAutodeleteSettings.SetConfirmTitle"),
            message: L10n.telegram("GlobalAutodeleteSettings.SetConfirmText", interval),
            actionTitle: L10n.telegram("GlobalAutodeleteSettings.SetConfirmAction"),
            isDestructive: false,
        ) { [weak self] in self?.save(value) }
    }

    private func save(_ value: Int) {
        perform { client in
            _ = try await client.send(TDNativeRequests.setDefaultMessageAutoDeleteTime(
                messageAutoDeleteTime: TDNativeMessageAutoDeleteTime(time: value),
            ))
        } completion: { [weak self] in
            guard let self else { return }
            currentTime = value
            onChange?(value)
            reload()
            showToast(value == 0
                ? L10n.telegram("GlobalAutodeleteSettings.SetConfirmToastDisabled")
                : L10n.telegram(
                    "GlobalAutodeleteSettings.SetConfirmToastEnabled",
                    SettingsFormatting.timeInterval(seconds: value),
                ))
        }
    }
}
