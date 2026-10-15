// DataAndStorageViewController.swift

import TDLibKit
import UIKit

// MARK: - DataAndStorageViewController

/// Telegram's Data and Storage (DataAndStorageSettingsController): Storage Usage and Network Usage with their
/// totals. BetterTG loads media as it shows it and has no automatic download policy, so Telegram's auto-download
/// presets are not offered.
final class DataAndStorageViewController: SettingsListViewController {
    private var storageSize: Int64?
    private var networkBytes: Int64?

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
        ])]
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let storage = try? await client.send(TDNativeRequests.getStorageStatisticsFast())
            let network = try? await client.send(TDNativeRequests.getNetworkStatistics(onlyCurrent: false))
            guard let self, contextIsCurrent else { return }
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
