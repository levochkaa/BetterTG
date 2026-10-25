// WebBrowserSettingsViewController.swift

import UIKit

// MARK: - WebBrowserSettingsViewController

/// Telegram's Web Browser (WebBrowserSettingsController): OPEN LINKS IN with Telegram's in-app browser, Safari and
/// the browsers installed on the device, and the note. BetterTG's in-app browser keeps no cookies or exceptions of
/// its own, so Clear Cookies and the website exceptions have no counterpart.
final class WebBrowserSettingsViewController: SettingsListViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("WebBrowser.Title")
    }

    override func makeSections() -> [SettingsSection] {
        let current = WebBrowser.current
        return [SettingsSection(
            header: L10n.telegram("WebBrowser.OpenLinksIn.Title"),
            footer: L10n.telegram("WebBrowser.OpenLinksInfo"),
            rows: WebBrowser.available.map { browser in
                SettingsRow(
                    title: browser.title,
                    accessory: browser == current ? .checkmark : .none,
                ) { [weak self] in
                    WebBrowser.current = browser
                    self?.reload()
                }
            },
        )]
    }
}
