// StorageUsageViewController.swift

import TDLibKit
import UIKit

// MARK: - StorageUsageViewController

/// Telegram's Storage Usage (StorageUsageScreen) on TDLib's statistics: PieChartComponent's ring of the cache by
/// category with the total inside, Storage Usage and the share of the free disk space, the categories by size with
/// their shares (past four, the smaller ones gather in Other, which opens), Clear Entire Cache with Telegram's
/// confirmation (optimizeStorage with no limits), TDLib's service files and the cache by chat. Keep Media and the
/// maximum cache size need a periodic cleanup BetterTG doesn't run, so they are not offered.
final class StorageUsageViewController: SettingsListViewController {
    /// StorageUsageScreen.Category with its colour and title.
    enum Category: String, CaseIterable {
        case photos
        case videos
        case files
        case music
        case stickers
        case avatars
        case misc
        case stories

        var title: String {
            switch self {
            case .photos: L10n.telegram("StorageManagement.SectionPhotos")
            case .videos: L10n.telegram("StorageManagement.SectionVideos")
            case .files: L10n.telegram("StorageManagement.SectionFiles")
            case .music: L10n.telegram("StorageManagement.SectionMusic")
            case .stickers: L10n.telegram("StorageManagement.SectionStickers")
            case .avatars: L10n.telegram("StorageManagement.SectionAvatars")
            case .misc: L10n.telegram("StorageManagement.SectionMiscellaneous")
            case .stories: L10n.telegram("StorageManagement.SectionStories")
            }
        }

        var color: UIColor {
            switch self {
            case .photos: UIColor(rgb: 0x5AC8FA)
            case .videos: UIColor(rgb: 0x3478F6)
            case .files: UIColor(rgb: 0x34C759)
            case .music: UIColor(rgb: 0xFF2D55)
            case .stickers: UIColor(rgb: 0x5856D6)
            case .avatars: UIColor(rgb: 0xAF52DE)
            case .misc: UIColor(rgb: 0xFF9500)
            case .stories: UIColor(rgb: 0xFF2D55)
            }
        }

        var symbol: String {
            switch self {
            case .photos: "photo.fill"
            case .videos: "video.fill"
            case .files: "doc.fill"
            case .music: "music.note"
            case .stickers: "face.smiling.inverse"
            case .avatars: "person.crop.circle.fill"
            case .misc: "ellipsis.circle.fill"
            case .stories: "circle.dashed"
            }
        }

        /// TDLib's file types in Telegram's categories; voice notes, thumbnails and the rest are Misc.
        init(_ type: TDNativeFileType) {
            self =
                switch type {
                case .fileTypePhoto,
                     .fileTypeSelfDestructingPhoto: .photos
                case .fileTypeAnimation,
                     .fileTypeLivePhotoVideo,
                     .fileTypeSelfDestructingLivePhotoVideo,
                     .fileTypeSelfDestructingVideo,
                     .fileTypeSelfDestructingVideoNote,
                     .fileTypeVideo,
                     .fileTypeVideoNote:
                    .videos
                case .fileTypePhotoStory,
                     .fileTypeVideoStory: .stories
                case .fileTypeDocument: .files
                case .fileTypeAudio: .music
                case .fileTypeSticker: .stickers
                case .fileTypeProfilePhoto: .avatars
                case .fileTypeNone,
                     .fileTypeNotificationSound,
                     .fileTypeSecret,
                     .fileTypeSecretThumbnail,
                     .fileTypeSecure,
                     .fileTypeSelfDestructingVoiceNote,
                     .fileTypeThumbnail,
                     .fileTypeUnknown,
                     .fileTypeVoiceNote,
                     .fileTypeWallpaper:
                    .misc
                }
        }
    }

    private static let otherID = "other"
    private static let otherColor = UIColor(rgb: 0xC4C4C6)

    private var fast: TDNativeStorageStatisticsFast?
    private var categorySizes = [Category: Int64]()
    private var chats = [(peer: SettingsPeer, size: Int64)]()
    private var isCalculating = true
    private var isClearing = false
    private var isOtherExpanded = false
    private let headerView = UsageChartHeaderView()

    /// The used categories by size: up to five shown, otherwise four and the rest under Other.
    private var listed: (shown: [Category], other: [Category]) {
        let used = Category.allCases
            .filter { (categorySizes[$0] ?? 0) > 0 }
            .sorted { (categorySizes[$0] ?? 0) > (categorySizes[$1] ?? 0) }
        guard used.count > 5 else { return (used, []) }
        return (Array(used.prefix(4)), Array(used.dropFirst(4)))
    }

    private var cacheTotal: Int64 {
        categorySizes.values.reduce(0, +)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("StorageManagement.Title")
        headerView.emptyColor = UIColor(rgb: 0x34C759)
        updateHeader(animated: false)
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        let height = headerView.height(for: width)
        if headerView.frame.size != CGSize(width: width, height: height) {
            headerView.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = headerView
        }
    }

    override func makeSections() -> [SettingsSection] {
        let loading = L10n.telegram("Channel.NotificationLoading")
        var sections = [SettingsSection]()
        if isCalculating {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: loading, style: .status(.secondaryLabel), accessory: .activity,
            )]))
        } else if cacheTotal > 0 {
            let total = cacheTotal
            func row(_ category: Category) -> SettingsRow {
                let size = categorySizes[category] ?? 0
                return SettingsRow(
                    title: category.title,
                    titleSuffix: UsagePieChartView.fractionText(CGFloat(size) / CGFloat(total)),
                    detail: SettingsFormatting.byteCount(size),
                    symbol: category.symbol,
                    symbolTint: category.color,
                )
            }
            let (shown, other) = listed
            var rows = shown.map(row)
            if !other.isEmpty {
                let size = other.reduce(0) { $0 + (categorySizes[$1] ?? 0) }
                var otherRow = SettingsRow(
                    title: L10n.telegram("StorageManagement.SectionOther"),
                    titleSuffix: UsagePieChartView.fractionText(CGFloat(size) / CGFloat(total)),
                    symbol: "square.stack.fill",
                    symbolTint: isOtherExpanded ? Self.otherColor : Category.misc.color,
                )
                let expanded = isOtherExpanded
                let sizeText = SettingsFormatting.byteCount(size)
                otherRow.trailingView = SettingsTrailingView {
                    NetworkUsageSizeView(text: sizeText, isExpanded: expanded)
                }
                otherRow.action = { [weak self] in self?.toggleOther() }
                rows.append(otherRow)
                if isOtherExpanded {
                    rows += other.map(row)
                }
            }
            sections.append(SettingsSection(footer: L10n.telegram("StorageManagement.SectionsDescription"), rows: rows))
        }
        sections.append(SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("StorageManagement.ClearAll"),
            detail: fast.map { SettingsFormatting.byteCount($0.filesSize) },
            style: .action(destructive: false),
            accessory: isClearing ? .activity : .none,
            isEnabled: !isClearing && (fast?.filesSize ?? 0) > 0,
        ) { [weak self] in self?.confirmClear() }]))
        if let fast {
            let serviceSize = fast.databaseSize + fast.languagePackDatabaseSize + fast.logSize
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Cache.ServiceFiles"),
                detail: SettingsFormatting.byteCount(serviceSize),
            )]))
        }
        if !chats.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("Cache.ByPeerHeader"),
                rows: chats.map { item in
                    SettingsRow(
                        title: item.peer.title,
                        detail: SettingsFormatting.byteCount(item.size),
                        style: .peer(item.peer),
                    )
                },
            ))
        }
        return sections
    }

    /// The cache's share of the free disk space with it, as StorageUsageScreen writes it.
    private static func diskShare(of size: Int64) -> String {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 0, size > 0 else { return "0" }
        let value = floor(Double(size) / Double(free + size) * 1000) / 10
        if value < 0.1 { return "<0.1" }
        return abs(Double(Int(value)) - value) < 0.001 ? "\(Int(value))" : "\(value)"
    }

    /// The chart: the shown categories, then the other ones apart while Other is open and as one Misc-coloured
    /// section otherwise.
    private func updateHeader(animated: Bool) {
        let total = cacheTotal
        let (shown, other) = listed
        func fraction(_ size: Int64) -> CGFloat {
            total == 0 ? 0 : CGFloat(size) / CGFloat(total)
        }
        var items = shown.map { category in
            UsagePieChartView.Item(
                id: category.rawValue, fraction: fraction(categorySizes[category] ?? 0), color: category.color,
            )
        }
        if isOtherExpanded {
            items += other.map { category in
                UsagePieChartView.Item(
                    id: category.rawValue, fraction: fraction(categorySizes[category] ?? 0), color: category.color,
                )
            }
        } else if !other.isEmpty {
            let size = other.reduce(0) { $0 + (categorySizes[$1] ?? 0) }
            items.append(UsagePieChartView.Item(id: Self.otherID, fraction: fraction(size), color: Category.misc.color))
        }
        let title: String
        let description: String?
        if isCalculating {
            title = L10n.telegram("StorageManagement.Title")
            description = " "
        } else if total == 0 {
            title = L10n.telegram("StorageManagement.TitleCleared")
            description = L10n.telegram("StorageManagement.DescriptionCleared")
        } else {
            title = L10n.telegram("StorageManagement.Title")
            description = L10n.betterTG("StorageManagement.DescriptionAppUsage", Self.diskShare(of: total))
        }
        headerView.update(
            items: isCalculating ? [] : items,
            totalText: SettingsFormatting.byteCount(total),
            title: title,
            description: description,
            animated: animated,
        )
        viewIfLoaded?.setNeedsLayout()
    }

    private func toggleOther() {
        isOtherExpanded.toggle()
        updateHeader(animated: true)
        reload()
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let fast = try? await client.send(TDNativeRequests.getStorageStatisticsFast())
            guard let self, contextIsCurrent else { return }
            self.fast = fast
            reload()
            // The full statistics scan the files and can take a while.
            let statistics = try? await client.send(TDNativeRequests.getStorageStatistics(chatLimit: 100))
            var sizes = [Category: Int64]()
            var chats = [(peer: SettingsPeer, size: Int64)]()
            for byChat in statistics?.byChat ?? [] {
                for byType in byChat.byFileType {
                    sizes[Category(byType.fileType), default: 0] += byType.size
                }
                guard byChat.chatId != 0, byChat.size > 0,
                      let peer = await SettingsPeer.chat(byChat.chatId, client: client) else { continue }
                chats.append((peer: peer, size: byChat.size))
            }
            guard contextIsCurrent else { return }
            categorySizes = sizes
            self.chats = chats.sorted { $0.size > $1.size }
            isCalculating = false
            updateHeader(animated: true)
            reload()
        }
    }

    /// Telegram's Clear Entire Cache. Downloaded media stays in the cloud.
    private func confirmClear() {
        confirm(
            message: L10n.telegram("StorageManagement.ClearConfirmationText"),
            actionTitle: L10n.telegram("StorageManagement.ClearCache"),
        ) { [weak self] in
            guard let self else { return }
            isClearing = true
            reload()
            perform { client in
                _ = try await client.send(TDNativeRequests.optimizeStorage(
                    size: 0, ttl: 0, count: 0, immunityDelay: 0, fileTypes: [], chatIds: [], excludeChatIds: [],
                    returnDeletedFileStatistics: false, chatLimit: 0,
                ))
            } completion: { [weak self] in
                guard let self else { return }
                isClearing = false
                isCalculating = true
                chats = []
                categorySizes = [:]
                isOtherExpanded = false
                updateHeader(animated: true)
                showToast(L10n.telegram("StorageManagement.TitleCleared"))
                load()
            }
        }
    }
}
