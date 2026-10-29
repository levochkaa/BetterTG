// NetworkUsageViewController.swift

import TDLibKit
import UIKit

// MARK: - NetworkUsageViewController

/// Telegram's DataUsageScreen modes over BetterTG's grouped rows: all, mobile or Wi-Fi bytes for messages, photos,
/// videos, audio, documents and calls, the totals, and Reset Statistics (resetNetworkStatistics) after Telegram's
/// confirmation.
final class NetworkUsageViewController: SettingsListViewController {
    private enum Network: Int {
        case all
        case mobile
        case wifi

        var sinceKey: String {
            switch self {
            case .all: "DataUsage.InfoTotalUsageSinceTime"
            case .mobile: "DataUsage.InfoMobileUsageSinceTime"
            case .wifi: "DataUsage.InfoWifiUsageSinceTime"
            }
        }

        func includes(wifi: Bool) -> Bool { self == .all || (self == .wifi) == wifi }
    }

    private enum Category: CaseIterable {
        case messages
        case photos
        case videos
        case audio
        case documents
        case calls

        var header: String {
            switch self {
            case .messages: L10n.telegram("NetworkUsageSettings.GeneralDataSection")
            case .photos: L10n.telegram("NetworkUsageSettings.MediaImageDataSection")
            case .videos: L10n.telegram("NetworkUsageSettings.MediaVideoDataSection")
            case .audio: L10n.telegram("NetworkUsageSettings.MediaAudioDataSection")
            case .documents: L10n.telegram("NetworkUsageSettings.MediaDocumentDataSection")
            case .calls: L10n.telegram("NetworkUsageSettings.CallDataSection")
            }
        }
    }

    private var statistics: TDNativeNetworkStatistics?
    private var network = Network.all
    private let segmentedControl = TelegramSegmentedControl(items: [
        L10n.telegram("DataUsage.TopSectionAll"),
        L10n.telegram("DataUsage.TopSectionMobile"),
        L10n.telegram("DataUsage.TopSectionWifi"),
    ])

    #if DEBUG
        private var isProbe = false

        convenience init(probeStatistics: TDNativeNetworkStatistics) {
            self.init()
            self.statistics = probeStatistics
            self.isProbe = true
        }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("NetworkUsageSettings.Title")
        segmentedControl.onSelection = { [weak self] index in
            guard let self, let network = Network(rawValue: index) else { return }
            self.network = network
            reload()
        }
        navigationItem.titleView = segmentedControl
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let statistics else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        var sent = [Category: Int64]()
        var received = [Category: Int64]()
        for entry in statistics.entries {
            let usage = NetworkUsageEntry(entry)
            guard let isWifi = usage.isWifi, network.includes(wifi: isWifi) else { continue }
            let category = Self.category(usage)
            sent[category, default: 0] += usage.sent
            received[category, default: 0] += usage.received
        }
        var sections = Category.allCases.map { category in
            SettingsSection(header: category.header, rows: Self.byteRows(
                sent: sent[category] ?? 0, received: received[category] ?? 0,
            ))
        }
        sections.append(SettingsSection(
            header: L10n.telegram("NetworkUsageSettings.TotalSection"),
            rows: Self.byteRows(sent: sent.values.reduce(0, +), received: received.values.reduce(0, +)),
        ))
        let since = Date(timeIntervalSince1970: TimeInterval(statistics.sinceDate))
            .formatted(date: .abbreviated, time: .shortened)
        sections.append(SettingsSection(
            footer: L10n.telegram(
                network.sinceKey,
                since,
            ),
            rows: [SettingsRow(
                title: L10n.telegram("NetworkUsageSettings.ResetStats"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmReset() }],
        ))
        return sections
    }

    private static func byteRows(sent: Int64, received: Int64) -> [SettingsRow] {
        [
            SettingsRow(
                title: L10n.telegram("NetworkUsageSettings.BytesSent"),
                detail: SettingsFormatting.byteCount(sent),
            ),
            SettingsRow(
                title: L10n.telegram("NetworkUsageSettings.BytesReceived"),
                detail: SettingsFormatting.byteCount(received),
            ),
        ]
    }

    private static func category(_ usage: NetworkUsageEntry) -> Category {
        guard !usage.isCall else { return .calls }
        switch usage.fileType {
        case nil:
            return .messages
        case .fileTypePhoto,
             .fileTypePhotoStory,
             .fileTypeProfilePhoto,
             .fileTypeSecretThumbnail,
             .fileTypeSelfDestructingPhoto,
             .fileTypeThumbnail,
             .fileTypeWallpaper:
            return .photos
        case .fileTypeAnimation,
             .fileTypeLivePhotoVideo,
             .fileTypeSelfDestructingLivePhotoVideo,
             .fileTypeSelfDestructingVideo,
             .fileTypeSelfDestructingVideoNote,
             .fileTypeVideo,
             .fileTypeVideoNote,
             .fileTypeVideoStory:
            return .videos
        case .fileTypeAudio,
             .fileTypeNotificationSound,
             .fileTypeSelfDestructingVoiceNote,
             .fileTypeVoiceNote:
            return .audio
        case .fileTypeDocument,
             .fileTypeNone,
             .fileTypeSecret,
             .fileTypeSecure,
             .fileTypeSticker,
             .fileTypeUnknown:
            return .documents
        }
    }

    private func load() {
        #if DEBUG
            if isProbe { return }
        #endif
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let statistics = try? await client.send(TDNativeRequests.getNetworkStatistics(onlyCurrent: false))
            guard let self, contextIsCurrent, let statistics else { return }
            self.statistics = statistics
            reload()
        }
    }

    private func confirmReset() {
        confirm(
            message: L10n.telegram("NetworkUsageSettings.ResetStatsConfirmation"),
            actionTitle: L10n.telegram("NetworkUsageSettings.ResetStats"),
        ) { [weak self] in
            #if DEBUG
                if self?.isProbe == true { return }
            #endif
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.resetNetworkStatistics())
            } completion: { [weak self] in
                self?.load()
            }
        }
    }
}

// MARK: - NetworkUsageEntry

/// One TDLib network statistics entry: its network, file type and bytes. Roaming counts as cellular and other
/// networks as Wi-Fi, as Telegram splits usage in two.
struct NetworkUsageEntry {
    let isWifi: Bool?
    let isCall: Bool
    let fileType: TDNativeFileType?
    let sent: Int64
    let received: Int64

    init(_ entry: TDNativeNetworkStatisticsEntry) {
        let networkType: TDNativeNetworkType
        switch entry {
        case .networkStatisticsEntryFile(let file):
            networkType = file.networkType
            self.isCall = false
            self.fileType = file.fileType
            self.sent = file.sentBytes
            self.received = file.receivedBytes
        case .networkStatisticsEntryCall(let call):
            networkType = call.networkType
            self.isCall = true
            self.fileType = nil
            self.sent = call.sentBytes
            self.received = call.receivedBytes
        }
        self.isWifi =
            switch networkType {
            case .networkTypeMobile,
                 .networkTypeMobileRoaming: false
            case .networkTypeOther,
                 .networkTypeWiFi: true
            case .networkTypeNone: nil
            }
    }
}
