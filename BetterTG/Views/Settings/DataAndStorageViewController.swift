// DataAndStorageViewController.swift

import TDLibKit
import UIKit

// MARK: - DataAndStorageViewController

/// Telegram's Data and Storage (DataAndStorageSettingsController): Storage Usage and Network Usage with their
/// totals, Auto-Download Media on cellular and Wi-Fi with Reset, Pause Music While Recording and Raise to Listen, and
/// Connection Type's Proxy with the type of the proxy in use.
final class DataAndStorageViewController: SettingsListViewController {
    private var storageSize: Int64?
    private var networkBytes: Int64?
    /// The enabled proxy's type, "None" without one; nil until TDLib answers.
    private var proxyValue: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ChatSettings.Title")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        let loading = L10n.telegram("Channel.NotificationLoading")
        return [SettingsSection(rows: [
            SettingsRow(
                title: L10n.telegram("ChatSettings.Cache"),
                detail: storageSize.map(SettingsFormatting.byteCount) ?? loading,
                symbol: "internaldrive.fill",
                symbolTint: .systemBlue,
                accessory: .disclosure,
            ) { [weak self] in
                self?.navigationController?.pushViewController(StorageUsageViewController(), animated: true)
            },
            SettingsRow(
                title: L10n.telegram("NetworkUsageSettings.Title"),
                detail: networkBytes.map(SettingsFormatting.byteCount) ?? loading,
                symbol: "chart.bar.fill",
                symbolTint: .systemGreen,
                accessory: .disclosure,
            ) { [weak self] in
                self?.navigationController?.pushViewController(NetworkUsageViewController(), animated: true)
            },
        ]), autoDownloadSection(), SettingsSection(
            header: L10n.telegram("ChatSettings.Other").uppercased(),
            footer: L10n.telegram("Settings.RaiseToListenInfo"),
            rows: [
                SettingsRow(
                    title: L10n.telegram("Settings.PauseMusicOnRecording"),
                    accessory: .toggle(isOn: PauseMusicOnRecordingSettings.isEnabled, onChange: { isOn in
                        PauseMusicOnRecordingSettings.isEnabled = isOn
                    }),
                ),
                SettingsRow(
                    title: L10n.telegram("Settings.RaiseToListen"),
                    accessory: .toggle(isOn: RaiseToListenSettings.isEnabled, onChange: { isOn in
                        RaiseToListenSettings.isEnabled = isOn
                    }),
                ),
            ],
        ), SettingsSection(
            header: L10n.telegram("ChatSettings.ConnectionType.Title").uppercased(),
            rows: [SettingsRow(
                title: L10n.telegram("SocksProxySetup.Title"),
                detail: proxyValue ?? loading,
                accessory: .disclosure,
            ) { [weak self] in
                self?.navigationController?.pushViewController(ProxySettingsViewController(), animated: true)
            }],
        )]
    }

    /// AUTO-DOWNLOAD MEDIA: Using Cellular and Using Wi-Fi with what they download, and Reset Auto-Download Settings
    /// while either differs from Telegram's defaults.
    private func autoDownloadSection() -> SettingsSection {
        let connections: [(MediaAutoDownload.NetworkType, String)] = [
            (.cellular, "ChatSettings.AutoDownloadUsingCellular"),
            (.wifi, "ChatSettings.AutoDownloadUsingWiFi"),
        ]
        var rows = connections.map { networkType, title in
            SettingsRow(
                title: L10n.telegram(title),
                detail: AutoDownloadSummary.connection(networkType),
                style: .subtitle,
                accessory: .disclosure,
            ) { [weak self] in
                self?.navigationController?.pushViewController(
                    AutoDownloadConnectionViewController(networkType: networkType),
                    animated: true,
                )
            }
        }
        rows.append(SettingsRow(
            title: L10n.telegram("ChatSettings.AutoDownloadReset"),
            style: .action(destructive: false),
            isEnabled: !MediaAutoDownload.shared.isDefault,
        ) { [weak self] in self?.confirmAutoDownloadReset() })
        return SettingsSection(header: L10n.telegram("ChatSettings.AutoDownloadTitle"), rows: rows)
    }

    /// resetAutomaticDownload: Telegram's sheet with the note and a destructive Reset.
    private func confirmAutoDownloadReset() {
        let sheet = UIAlertController(
            title: nil,
            message: L10n.telegram("AutoDownloadSettings.ResetHelp"),
            preferredStyle: .actionSheet,
        )
        sheet.addAction(UIAlertAction(title: L10n.telegram("AutoDownloadSettings.Reset"), style: .destructive) { _ in
            MediaAutoDownload.shared.reset()
            self.reload()
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let storage = try? await client.send(TDNativeRequests.getStorageStatisticsFast())
            let network = try? await client.send(TDNativeRequests.getNetworkStatistics(onlyCurrent: false))
            let proxies = try? await client.send(TDNativeRequests.getProxies())
            guard let self, contextIsCurrent else { return }
            proxyValue = proxies.map { list in
                list.proxies.first(where: \.isEnabled).map { ProxyPresentation.typeTitle($0.proxy) }
                    ?? L10n.telegram("GroupInfo.SharedMediaNone")
            }
            storageSize = storage.map { $0.filesSize + $0.databaseSize + $0.languagePackDatabaseSize + $0.logSize }
            networkBytes = network.map { statistics in
                statistics.entries.reduce(Int64(0)) { total, entry in
                    let usage = NetworkUsageEntry(entry)
                    return total + usage.sent + usage.received
                }
            }
            reload()
        }
    }
}
