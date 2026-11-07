// WebBrowserSettingsViewController.swift

import UIKit

// MARK: - WebBrowserSettingsViewController

/// Telegram's Web Browser (WebBrowserSettingsController): OPEN LINKS IN with Telegram's in-app browser, Safari and
/// the browsers installed on the device, and the note; then the websites that open the other way: DON'T OPEN IN-APP
/// while the in-app browser is chosen, OPEN IN-APP while another is, with Add Website, a swipe to delete one and
/// Delete All Exceptions. They're kept on the device, as TDLib doesn't sync Telegram's browser settings. The in-app
/// browser is Safari's, whose cookies the app can't clear, so Clear Cookies has no counterpart.
final class WebBrowserSettingsViewController: SettingsListViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("WebBrowser.Title")
    }

    override func makeSections() -> [SettingsSection] {
        let current = WebBrowser.current
        var sections = [SettingsSection(
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
        let inApp = current == .telegram
        let exceptions = WebBrowser.exceptions
        var rows = [SettingsRow(
            title: L10n.telegram("WebBrowser.Exceptions.AddException"),
            style: .action(destructive: false),
            symbol: "plus",
        ) { [weak self] in self?.addException() }]
        // The newest first, as Telegram lists them.
        for domain in exceptions.reversed() {
            var row = SettingsRow(title: domain, symbol: "globe", symbolTint: .secondaryLabel)
            row.swipeAction = (L10n.telegram("Common.Delete"), { [weak self] in
                WebBrowser.exceptions.removeAll { $0 == domain }
                self?.reload()
            })
            rows.append(row)
        }
        sections.append(SettingsSection(
            header: L10n.telegram(inApp ? "WebBrowser.Exceptions.DontOpenInApp" : "WebBrowser.Exceptions.OpenInApp"),
            footer: L10n.telegram(inApp ? "WebBrowser.Exceptions.Info" : "WebBrowser.Exceptions.InAppInfo"),
            rows: rows,
        ))
        if !exceptions.isEmpty {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("WebBrowser.Exceptions.DeleteAll"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmDeleteAll() }]))
        }
        return sections
    }

    /// webBrowserDomainController: Add Website with the domain to type; Done takes a link or a bare domain.
    private func addException() {
        let inApp = WebBrowser.current == .telegram
        let alert = UIAlertController(
            title: L10n.telegram("WebBrowser.Exceptions.Create.Title"),
            message: L10n.telegram(inApp
                ? "WebBrowser.Exceptions.Create.Text"
                : "WebBrowser.Exceptions.Create.ExternalText"),
            preferredStyle: .alert,
        )
        alert.addTextField { field in
            field.placeholder = L10n.telegram("WebBrowser.Exceptions.Create.Placeholder")
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        let done = UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [weak self, weak alert] _ in
            guard let domain = WebBrowser.exceptionDomain(alert?.textFields?.first?.text ?? "") else { return }
            var exceptions = WebBrowser.exceptions.filter { $0 != domain }
            exceptions.append(domain)
            WebBrowser.exceptions = exceptions
            self?.reload()
        }
        alert.addAction(done)
        alert.preferredAction = done
        present(alert, animated: true)
    }

    private func confirmDeleteAll() {
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("WebBrowser.Exceptions.ClearConfirmation.Text"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: L10n.telegram("WebBrowser.Exceptions.ClearConfirmation.Clear"),
            style: .destructive,
        ) { [weak self] _ in
            WebBrowser.exceptions = []
            self?.reload()
        })
        present(alert, animated: true)
    }
}
