// DataAndStorageViewController.swift

import TDLibKit
import UIKit

// MARK: - DataAndStorageViewController

/// Telegram's Data and Storage (DataAndStorageSettingsController): Storage Usage and Network Usage with their
/// totals, Auto-Download Media on cellular and Wi-Fi with Reset, Save to Camera Roll for each kind of chat, Pause Music
/// While Recording and Raise to Listen, and
/// Connection Type's Proxy with the type of the proxy in use.
final class DataAndStorageViewController: SettingsListViewController {
    private var storageSize: Int64?
    private var networkBytes: Int64?
    /// The enabled proxy's type, "None" without one; nil until TDLib answers.
    private var proxyValue: String?
    /// TDLib's autosave settings and each exception's kind of chat, for Save to Camera Roll.
    private var autosave: TDNativeAutosaveSettings?
    private var autosaveExceptionScopes = [AutosaveScope]()

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
        ]), autoDownloadSection()] + autosaveSections() + [SettingsSection(
            header: L10n.telegram("ChatSettings.Other").uppercased(),
            footer: L10n.telegram("Settings.RaiseToListenInfo"),
            rows: [
                SettingsRow(
                    title: L10n.telegram("Settings.SaveEditedPhotos"),
                    accessory: .toggle(isOn: SaveEditedPhotosSettings.isEnabled, onChange: { isOn in
                        SaveEditedPhotosSettings.isEnabled = isOn
                    }),
                ),
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
        )] + sensitiveContentSections() + [SettingsSection(
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

    /// Show 18+ Content (`ignore_sensitive_content_restrictions`) while the account may turn it on.
    private func sensitiveContentSections() -> [SettingsSection] {
        let clientID = client.id
        guard SensitiveContentStore.canIgnore(clientID: clientID) else { return [] }
        return [SettingsSection(
            footer: L10n.telegram("Settings.SensitiveContentInfo"),
            rows: [SettingsRow(
                title: L10n.telegram("Settings.SensitiveContent"),
                accessory: .toggle(isOn: SensitiveContentStore.ignores(clientID: clientID)) { [weak self] isOn in
                    self?.setShowsSensitiveContent(isOn)
                },
            )],
        )]
    }

    /// toggleSensitiveContent: turning it on asks to confirm the age first.
    private func setShowsSensitiveContent(_ isOn: Bool) {
        let apply = { [weak self] in
            self?.perform { client in
                _ = try await client.setOption(
                    name: SensitiveContentStore.ignoreOptionName,
                    value: .optionValueBoolean(TDNativeOptionValueBoolean(value: isOn)),
                )
            } completion: {}
        }
        guard isOn else {
            apply()
            return
        }
        let alert = UIAlertController(
            title: L10n.telegram("SensitiveContent.Enable.Title"),
            message: L10n.telegram("SensitiveContent.Enable.Text"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("SensitiveContent.Enable.Confirm"), style: .default) { _ in
            apply()
        })
        present(alert, animated: true)
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

    /// DataAndStorageSettingsController's SAVE TO CAMERA ROLL: Private Chats, Groups and Channels with On or Off, what
    /// they save and their exceptions under the title, each opening its settings.
    private func autosaveSections() -> [SettingsSection] {
        guard let autosave else { return [] }
        return [SettingsSection(
            header: L10n.telegram("Settings.SaveToCameraRollSection"),
            footer: L10n.telegram("Settings.SaveToCameraRollInfo"),
            rows: AutosaveScope.allCases.map { scope in
                let settings = scope.settings(in: autosave)
                let exceptions = autosaveExceptionScopes.count { $0 == scope }
                let label = AutosaveScope.label(for: settings, exceptions: exceptions)
                let value = L10n.telegram(
                    settings.autosavePhotos || settings.autosaveVideos
                        ? "Settings.AutosaveMediaOn"
                        : "Settings.AutosaveMediaOff",
                )
                var row = SettingsRow(
                    title: scope.title,
                    detail: label.isEmpty ? nil : label,
                    style: label.isEmpty ? .value : .subtitle,
                    symbol: scope.symbol,
                    symbolTint: scope.tint,
                    accessory: .disclosure,
                ) { [weak self] in
                    self?.navigationController?.pushViewController(
                        AutosaveSettingsViewController(target: .scope(scope)), animated: true,
                    )
                }
                row.trailingView = SettingsTrailingView {
                    let valueLabel = UILabel()
                    valueLabel.text = value
                    valueLabel.textColor = .secondaryLabel
                    valueLabel.font = .preferredFont(forTextStyle: .body)
                    valueLabel.sizeToFit()
                    return valueLabel
                }
                return row
            },
        )]
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let storage = try? await client.send(TDNativeRequests.getStorageStatisticsFast())
            let network = try? await client.send(TDNativeRequests.getNetworkStatistics(onlyCurrent: false))
            let proxies = try? await client.send(TDNativeRequests.getProxies())
            let autosave = try? await client.send(TDNativeRequests.getAutosaveSettings())
            var exceptionScopes = [AutosaveScope]()
            for exception in autosave?.exceptions ?? [] {
                guard let chat = try? await client.getChat(chatId: exception.chatId) else { continue }
                exceptionScopes.append(AutosaveScope(chatType: chat.type))
            }
            guard let self, contextIsCurrent else { return }
            self.autosave = autosave
            autosaveExceptionScopes = exceptionScopes
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
