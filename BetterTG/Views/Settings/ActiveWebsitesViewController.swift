// ActiveWebsitesViewController.swift

import TDLibKit
import UIKit

// MARK: - ActiveWebsitesViewController

/// RecentSessionsController in its websites mode: Disconnect All Websites with Telegram's note, then Connected
/// Websites, newest first, each as ItemListWebsiteItem's bot, its domain, browser and platform, and its location with
/// the last activity, with a Disconnect swipe (disconnectWebsite).
final class ActiveWebsitesViewController: SettingsListViewController {
    /// Called with the count after a change, so Privacy and Security can update its row.
    var onChange: ((Int) -> Void)?

    private var websites: [(website: TDNativeConnectedWebsite, bot: SettingsPeer?)]?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PrivacySettings.WebSessions")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let websites, !websites.isEmpty else { return [] }
        return [
            SettingsSection(footer: L10n.telegram("AuthSessions.LogOutApplicationsHelp"), rows: [SettingsRow(
                title: L10n.telegram("AuthSessions.LogOutApplications"),
                style: .action(destructive: true),
                action: { [weak self] in self?.confirmDisconnectAll() },
            )]),
            SettingsSection(
                header: L10n.telegram("AuthSessions.LoggedInWithTelegram"),
                rows: websites.map { item in
                    let website = item.website
                    let peer = item.bot ?? SettingsPeer(
                        id: website.botUserId,
                        title: website.domainName,
                        file: nil,
                        minithumbnail: nil,
                        placeholder: TelegramAvatarPlaceholder(
                            peerID: website.botUserId,
                            accentColorID: 0,
                            upgradedGiftColors: nil,
                            letters: website.domainName.telegramAvatarFirstLetter.map { [$0] } ?? [],
                            isDeleted: false,
                        ),
                    )
                    return SettingsRow(
                        title: peer.title,
                        detail: Self.detail(website),
                        style: .peer(peer),
                        swipeAction: (
                            title: L10n.telegram("AuthSessions.LogOut"),
                            handler: { [weak self] in self?.disconnect(website.id) },
                        ),
                    )
                },
            ),
        ]
    }

    // MARK: Private

    /// The domain, browser and platform, then the location and the last activity.
    private static func detail(_ website: TDNativeConnectedWebsite) -> String {
        let app = [website.domainName, website.browser, website.platform].filter { !$0.isEmpty }.joined(separator: ", ")
        let location = [website.location.isEmpty ? website.ipAddress : website.location]
            .filter { !$0.isEmpty } + [SettingsFormatting.activityDate(website.lastActiveDate)]
        return app + "\n" + location.joined(separator: " • ")
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let list = await (try? client.send(TDNativeRequests.getConnectedWebsites()))?.websites ?? []
            var loaded = [(website: TDNativeConnectedWebsite, bot: SettingsPeer?)]()
            for website in list.sorted(by: { $0.lastActiveDate > $1.lastActiveDate }) {
                await loaded.append((website, SettingsPeer.user(website.botUserId, client: client)))
            }
            guard let self, contextIsCurrent else { return }
            websites = loaded
            reload()
        }
    }

    private func disconnect(_ id: Int64) {
        perform { client in
            _ = try await client.send(TDNativeRequests.disconnectWebsite(websiteId: id))
        } completion: { [weak self] in
            guard let self else { return }
            websites?.removeAll { $0.website.id == id }
            reload()
            onChange?(websites?.count ?? 0)
        }
    }

    private func confirmDisconnectAll() {
        confirm(
            message: L10n.telegram("AuthSessions.LogOutApplications"),
            actionTitle: L10n.telegram("AuthSessions.LogOut"),
        ) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.disconnectAllWebsites())
            } completion: { [weak self] in
                self?.websites = []
                self?.reload()
                self?.onChange?(0)
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }
}
