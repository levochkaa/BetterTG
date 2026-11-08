// NetworkUsageViewController.swift

import TDLibKit
import UIKit

// MARK: - NetworkUsageViewController

/// Telegram's DataUsageScreen: the share of each category in PieChartComponent's ring with the total inside, Data
/// Usage and since when, then the categories by size with their shares (a tap shows Incoming and Outgoing), the
/// network's totals sent and received, and Reset Statistics (resetNetworkStatistics) after Telegram's confirmation.
/// All, Mobile and Wi-Fi switch under the header and stay at the bar's row once scrolled there, the header fading as
/// the switch nears it; the bar has no title, as DataUsageScreen's.
final class NetworkUsageViewController: SettingsListViewController {
    /// DataUsageScreen.Category with its colour, Settings icon and title.
    enum Category: String, CaseIterable {
        case photos
        case videos
        case files
        case music
        case messages
        case stickers
        case voiceMessages
        case calls

        var title: String {
            switch self {
            case .photos: L10n.telegram("StorageManagement.SectionPhotos")
            case .videos: L10n.telegram("StorageManagement.SectionVideos")
            case .files: L10n.telegram("StorageManagement.SectionFiles")
            case .music: L10n.telegram("StorageManagement.SectionMusic")
            case .messages: L10n.telegram("StorageManagement.SectionMessages")
            case .stickers: L10n.telegram("StorageManagement.SectionStickers")
            case .voiceMessages: L10n.telegram("StorageManagement.SectionVoiceMessages")
            case .calls: L10n.telegram("StorageManagement.SectionCalls")
            }
        }

        var color: UIColor {
            switch self {
            case .photos: UIColor(rgb: 0x5AC8FA)
            case .videos: UIColor(rgb: 0x0088FF)
            case .files: UIColor(rgb: 0x34C759)
            case .music: UIColor(rgb: 0xFF2D55)
            case .messages: UIColor(rgb: 0x5856D6)
            case .stickers: UIColor(rgb: 0xFF9500)
            case .voiceMessages: UIColor(rgb: 0xAF52DE)
            case .calls: UIColor(rgb: 0xFF9500)
            }
        }

        var symbol: String {
            switch self {
            case .photos: "photo.fill"
            case .videos: "video.fill"
            case .files: "doc.fill"
            case .music: "music.note"
            case .messages: "bubble.left.fill"
            case .stickers: "face.smiling.inverse"
            case .voiceMessages: "mic.fill"
            case .calls: "phone.fill"
            }
        }

        /// isSeparable: calls show no Incoming and Outgoing.
        var isSeparable: Bool { self != .calls }
    }

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

        var totalTitleKey: String {
            switch self {
            case .all: "DataUsage.SectionUsageTotal"
            case .mobile: "DataUsage.SectionUsageMobile"
            case .wifi: "DataUsage.SectionUsageWifi"
            }
        }

        func includes(wifi: Bool) -> Bool { self == .all || (self == .wifi) == wifi }
    }

    private struct Usage {
        var sent: Int64 = 0
        var received: Int64 = 0

        var total: Int64 { sent + received }
    }

    private static let segmentedHeight: CGFloat = 36

    private var statistics: TDNativeNetworkStatistics?
    private var network = Network.all
    private var expanded = Set<Category>()
    private let headerView = UsageChartHeaderView()
    private let headerContainer = UIView()
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
            updateHeader(animated: true)
            reload()
        }
        headerContainer.addSubview(headerView)
        tableView.addSubview(segmentedControl)
        updateHeader(animated: false)
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        // DataUsageScreen: the switch 20 pt under the description and the categories 26 pt under it; the first
        // section's own top spacing takes part of that.
        let height = headerView.height(for: width) + Self.segmentedHeight + 24
        if tableView.tableHeaderView !== headerContainer || headerContainer.frame.size != CGSize(
            width: width,
            height: height,
        ) {
            headerContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            headerView.frame = CGRect(x: 0, y: 0, width: width, height: headerView.height(for: width))
            tableView.tableHeaderView = headerContainer
        }
        updateSegmentedControl()
    }

    override func scrollViewDidScroll(_: UIScrollView) {
        updateSegmentedControl()
    }

    override func makeSections() -> [SettingsSection] {
        guard statistics != nil else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        let usage = usage()
        let total = usage.values.reduce(0) { $0 + $1.total }
        var rows = [SettingsRow]()
        for category in sortedCategories(usage) {
            let value = usage[category] ?? Usage()
            let isExpandable = category.isSeparable && value.total != 0
            let isExpanded = isExpandable && expanded.contains(category)
            var row = SettingsRow(
                title: category.title,
                titleSuffix: total == 0 ? nil : UsagePieChartView.fractionText(CGFloat(value.total) / CGFloat(total)),
                symbol: category.symbol,
                symbolTint: category.color,
            )
            let size = SettingsFormatting.byteCount(value.total)
            if isExpandable {
                row.trailingView = SettingsTrailingView {
                    NetworkUsageSizeView(text: size, isExpanded: isExpanded)
                }
                row.action = { [weak self] in self?.toggle(category) }
            } else {
                row.detail = size
            }
            rows.append(row)
            if isExpanded {
                rows.append(SettingsRow(
                    title: L10n.telegram("DataUsage.MediaDirectionIncoming"),
                    detail: SettingsFormatting.byteCount(value.received),
                    symbol: "arrow.down",
                    symbolTint: .label,
                ))
                rows.append(SettingsRow(
                    title: L10n.telegram("DataUsage.MediaDirectionOutgoing"),
                    detail: SettingsFormatting.byteCount(value.sent),
                    symbol: "arrow.up",
                    symbolTint: .label,
                ))
            }
        }
        let sent = usage.values.reduce(0) { $0 + $1.sent }
        let received = usage.values.reduce(0) { $0 + $1.received }
        return [
            SettingsSection(footer: L10n.telegram("DataUsage.SectionsInfo"), rows: rows),
            SettingsSection(header: L10n.telegram(network.totalTitleKey), rows: [
                SettingsRow(
                    title: L10n.telegram("DataUsage.SectionTotalOutgoing"),
                    detail: SettingsFormatting.byteCount(sent),
                    symbol: "arrow.up.circle.fill",
                    symbolTint: UIColor(rgb: 0xFF9500),
                ),
                SettingsRow(
                    title: L10n.telegram("DataUsage.SectionTotalIncoming"),
                    detail: SettingsFormatting.byteCount(received),
                    symbol: "arrow.down.circle.fill",
                    symbolTint: UIColor(rgb: 0xFF9500),
                ),
            ]),
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("DataUsage.Reset"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmReset() }]),
        ]
    }

    /// DataUsageScreen's categories from TDLib's file types: the rest of the traffic counts as messages.
    private static func category(_ usage: NetworkUsageEntry) -> Category {
        guard !usage.isCall else { return .calls }
        switch usage.fileType {
        case .fileTypeNone,
             nil:
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
             .fileTypeNotificationSound:
            return .music
        case .fileTypeSelfDestructingVoiceNote,
             .fileTypeVoiceNote:
            return .voiceMessages
        case .fileTypeSticker:
            return .stickers
        case .fileTypeDocument,
             .fileTypeSecret,
             .fileTypeSecure,
             .fileTypeUnknown:
            return .files
        }
    }

    /// DataUsageScreen.updateScrolling: the switch keeps its place under the header until it reaches the middle of
    /// the bar's row, then stays there over the bar; the header's contents fade over the last 60 pt before it does.
    private func updateSegmentedControl() {
        let chrome = tableView.subviews.lazy.compactMap { $0 as? TelegramClassicNavigationChrome }.first
        chrome?.titleAlpha = 0
        // Centred in the band between the side insets, 36 pt from them at most.
        let insets = tableView.safeAreaInsets
        let band = tableView.bounds.width - insets.left - insets.right
        let width = min(band - 36 * 2, segmentedControl.intrinsicContentSize.width)
        let naturalY = headerContainer.frame.minY + headerView.frame.maxY
        var y = naturalY
        if let chrome {
            let rowCenter = chrome.frame.maxY - TelegramGlassPlatter.barBottomInset - 22
            let dockedY = rowCenter - Self.segmentedHeight / 2
            y = max(naturalY, dockedY)
            headerView.alpha = min(1, max(0, (naturalY - dockedY) / 60))
            // overNavigationContainer: over the bar's background, as the bar stays over the list by zPosition.
            segmentedControl.layer.zPosition = chrome.layer.zPosition + 1
            tableView.bringSubviewToFront(segmentedControl)
        }
        segmentedControl.frame = CGRect(
            x: (insets.left + (band - width) / 2).rounded(),
            y: y,
            width: width,
            height: Self.segmentedHeight,
        )
    }

    /// The network's usage by category.
    private func usage() -> [Category: Usage] {
        var result = [Category: Usage]()
        for entry in statistics?.entries ?? [] {
            let usage = NetworkUsageEntry(entry)
            guard let isWifi = usage.isWifi, network.includes(wifi: isWifi) else { continue }
            let category = Self.category(usage)
            result[category, default: Usage()].sent += usage.sent
            result[category, default: Usage()].received += usage.received
        }
        return result
    }

    /// The categories by size, largest first, then by title.
    private func sortedCategories(_ usage: [Category: Usage]) -> [Category] {
        Category.allCases.sorted { lhs, rhs in
            let left = usage[lhs]?.total ?? 0
            let right = usage[rhs]?.total ?? 0
            return left != right ? left > right : lhs.title < rhs.title
        }
    }

    private func updateHeader(animated: Bool) {
        let usage = usage()
        let total = usage.values.reduce(0) { $0 + $1.total }
        let items = sortedCategories(usage).map { category in
            UsagePieChartView.Item(
                id: category.rawValue,
                fraction: total == 0 ? 0 : CGFloat(usage[category]?.total ?? 0) / CGFloat(total),
                color: category.color,
            )
        }
        var since: String?
        if let statistics, statistics.sinceDate != 0 {
            let date = ChatVM.fullDateString(Date(timeIntervalSince1970: TimeInterval(statistics.sinceDate)))
            since = L10n.telegram(network.sinceKey, date)
        }
        headerView.update(
            items: statistics == nil ? [] : items,
            totalText: DataSize.string(total, forceDecimal: true),
            title: L10n.telegram(total == 0 ? "DataUsage.HeaderNoDataUsed" : "DataUsage.Header"),
            description: since,
            animated: animated,
        )
        viewIfLoaded?.setNeedsLayout()
    }

    private func toggle(_ category: Category) {
        if expanded.contains(category) {
            expanded.remove(category)
        } else {
            expanded.insert(category)
        }
        reload()
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
            updateHeader(animated: true)
            reload()
        }
    }

    private func confirmReset() {
        confirm(
            message: L10n.telegram("NetworkUsageSettings.ResetStatsConfirmation"),
            actionTitle: L10n.telegram("DataUsage.Reset"),
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

// MARK: - NetworkUsageSizeView

/// DataCategoryItemComponent's size and the arrow that turns up while the category is open.
final class NetworkUsageSizeView: UIView {
    override var intrinsicContentSize: CGSize {
        frame.size
    }

    private let label = UILabel()
    private let arrow = UIImageView()

    init(text: String, isExpanded: Bool) {
        super.init(frame: .zero)
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        addSubview(label)
        arrow.image = UIImage(
            systemName: isExpanded ? "chevron.up" : "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
        )
        arrow.tintColor = .tertiaryLabel
        arrow.contentMode = .center
        addSubview(arrow)
        let labelSize = label.sizeThatFits(CGSize(width: 200, height: 40))
        frame.size = CGSize(width: labelSize.width + 6 + 16, height: max(labelSize.height, 22))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_: CGSize) -> CGSize {
        frame.size
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelSize = label.sizeThatFits(CGSize(width: 200, height: 40))
        label.frame = CGRect(
            x: 0, y: (bounds.height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height,
        )
        arrow.frame = CGRect(x: bounds.width - 16, y: 0, width: 16, height: bounds.height)
    }
}
