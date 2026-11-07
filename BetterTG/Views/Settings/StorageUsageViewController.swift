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

        private static let allFileTypes: [TDNativeFileType] = [
            .fileTypeAnimation, .fileTypeAudio, .fileTypeDocument, .fileTypeLivePhotoVideo, .fileTypeNone,
            .fileTypeNotificationSound, .fileTypePhoto, .fileTypePhotoStory, .fileTypeProfilePhoto, .fileTypeSecret,
            .fileTypeSecretThumbnail, .fileTypeSecure, .fileTypeSelfDestructingLivePhotoVideo,
            .fileTypeSelfDestructingPhoto, .fileTypeSelfDestructingVideo, .fileTypeSelfDestructingVideoNote,
            .fileTypeSelfDestructingVoiceNote, .fileTypeSticker, .fileTypeThumbnail, .fileTypeUnknown,
            .fileTypeVideo, .fileTypeVideoNote, .fileTypeVideoStory, .fileTypeVoiceNote, .fileTypeWallpaper,
        ]

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

        /// The TDLib file types the category stands for, which a selective clear passes to optimizeStorage.
        var fileTypes: [TDNativeFileType] {
            Self.allFileTypes.filter { Category($0) == self }
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

    /// Runs after the chat's cache is cleared, so the whole cache's screen reads its statistics again.
    var onCleared: (() -> Void)?

    /// The chat whose cache the screen shows (StorageUsageScreen's `peer`), or nil for the whole cache.
    private let chat: (id: Int64, peer: SettingsPeer)?
    private var fast: TDNativeStorageStatisticsFast?
    /// The whole cache, against which a chat's share is told.
    private var allChatsTotal: Int64 = 0
    private var categorySizes = [Category: Int64]()
    private var chats = [(peer: SettingsPeer, size: Int64)]()
    private var isCalculating = true
    private var isClearing = false
    private var isOtherExpanded = false
    /// The categories a clear takes: all that hold anything at first, as StorageUsageScreen selects them.
    private var selected = Set<Category>()
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

    private var existing: Set<Category> {
        Set(Category.allCases.filter { (categorySizes[$0] ?? 0) > 0 })
    }

    private var isEverythingSelected: Bool {
        isCalculating || existing.isSubset(of: selected)
    }

    private var selectedSize: Int64 {
        selected.reduce(0) { $0 + (categorySizes[$1] ?? 0) }
    }

    /// The chat's name, Saved Messages for the account's own chat.
    private var chatTitle: String? {
        guard let chat else { return nil }
        return chat.id == TDLib.shared.activeAccount?.userID
            ? L10n.telegram("DialogList.SavedMessages")
            : chat.peer.title
    }

    init(chat: (id: Int64, peer: SettingsPeer)? = nil) {
        self.chat = chat
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = chatTitle ?? L10n.telegram("StorageManagement.Title")
        headerView.emptyColor = UIColor(rgb: 0x34C759)
        if let chat {
            // The chat's 72 pt avatar in the ring's hole.
            let avatar = ProfileAvatarView()
            avatar.isUserInteractionEnabled = false
            avatar.configure(
                file: chat.peer.file,
                minithumbnail: chat.peer.minithumbnail,
                placeholder: chat.peer.placeholder,
                accountID: accountID,
                accountUserID: TDLib.shared.activeAccount?.userID,
                client: client,
            )
            headerView.centerView = avatar
        }
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
            // Shares are of the selected categories; one left out shows none.
            let total = max(1, selectedSize)
            // StorageCategoryItemComponent: the check in the category's colour, which a tap turns.
            func row(_ category: Category) -> SettingsRow {
                let size = categorySizes[category] ?? 0
                let isSelected = selected.contains(category)
                return SettingsRow(
                    title: category.title,
                    titleSuffix: UsagePieChartView.fractionText(isSelected ? CGFloat(size) / CGFloat(total) : 0),
                    detail: SettingsFormatting.byteCount(size),
                    symbol: isSelected ? "checkmark.circle.fill" : "circle",
                    symbolTint: isSelected ? category.color : .tertiaryLabel,
                ) { [weak self] in self?.toggleSelection(category) }
            }
            let (shown, other) = listed
            var rows = shown.map(row)
            if !other.isEmpty {
                let size = other.reduce(0) { $0 + (categorySizes[$1] ?? 0) }
                let selectedOtherSize = other.filter(selected.contains).reduce(0) { $0 + (categorySizes[$1] ?? 0) }
                let isSelected = other.allSatisfy(selected.contains)
                let otherColor = isOtherExpanded ? Self.otherColor : Category.misc.color
                var otherRow = SettingsRow(
                    title: L10n.telegram("StorageManagement.SectionOther"),
                    titleSuffix: UsagePieChartView.fractionText(CGFloat(selectedOtherSize) / CGFloat(total)),
                    symbol: isSelected ? "checkmark.circle.fill" : "circle",
                    symbolTint: isSelected ? otherColor : .tertiaryLabel,
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
        // StorageCategoriesComponent's button: Clear Entire Cache with everything selected, Clear Selected otherwise,
        // with the size it frees.
        let selectedSize = selectedSize
        let clearTitle =
            if !isEverythingSelected {
                L10n.telegram("StorageManagement.ClearSelected")
            } else if chat != nil {
                L10n.telegram("StorageManagement.ClearCache")
            } else {
                L10n.telegram("StorageManagement.ClearAll")
            }
        sections.append(SettingsSection(rows: [SettingsRow(
            title: clearTitle,
            detail: isCalculating
                ? fast.map { SettingsFormatting.byteCount($0.filesSize) }
                : selectedSize == 0 ? nil : SettingsFormatting.byteCount(selectedSize),
            style: .action(destructive: false),
            accessory: isClearing ? .activity : .none,
            isEnabled: !isClearing && (isCalculating ? (fast?.filesSize ?? 0) > 0 : selectedSize > 0),
        ) { [weak self] in self?.confirmClear() }]))
        guard chat == nil else { return sections }
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
                        accessory: .disclosure,
                    ) { [weak self] in self?.openChat(item.peer) }
                },
            ))
        }
        return sections
    }

    /// The cache's share of the free disk space with it.
    private static func diskFraction(of size: Int64) -> Double {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 0, size > 0 else { return 0 }
        return Double(size) / Double(free + size)
    }

    /// A share as StorageUsageScreen writes it in its description: tenths, "<0.1" for less.
    private static func shareText(_ fraction: Double) -> String {
        let value = floor(fraction * 1000) / 10
        if value < 0.1 { return "<0.1" }
        return abs(Double(Int(value)) - value) < 0.001 ? "\(Int(value))" : "\(value)"
    }

    /// openPeer: the chat's own Storage Usage, after whose clear this one reads its statistics again.
    private func openChat(_ peer: SettingsPeer) {
        let screen = StorageUsageViewController(chat: (id: peer.id, peer: peer))
        screen.onCleared = { [weak self] in
            guard let self else { return }
            isCalculating = true
            updateHeader(animated: true)
            reload()
            load()
        }
        navigationController?.pushViewController(screen, animated: true)
    }

    /// The chart: the shown categories, then the other ones apart while Other is open and as one Misc-coloured
    /// section otherwise.
    private func updateHeader(animated: Bool) {
        let total = cacheTotal
        let selectedTotal = selectedSize
        let (shown, other) = listed
        // A category left out of the clear leaves the ring, and the rest share it.
        func size(_ category: Category) -> Int64 {
            selected.contains(category) ? categorySizes[category] ?? 0 : 0
        }
        func fraction(_ size: Int64) -> CGFloat {
            selectedTotal == 0 ? 0 : CGFloat(size) / CGFloat(selectedTotal)
        }
        var items = shown.map { category in
            UsagePieChartView.Item(id: category.rawValue, fraction: fraction(size(category)), color: category.color)
        }
        if isOtherExpanded {
            items += other.map { category in
                UsagePieChartView.Item(id: category.rawValue, fraction: fraction(size(category)), color: category.color)
            }
        } else if !other.isEmpty {
            let size = other.reduce(0) { $0 + size($1) }
            items.append(UsagePieChartView.Item(id: Self.otherID, fraction: fraction(size), color: Category.misc.color))
        }
        // The description and the bar under it: a chat's share of the cache, or the cache's of the free space.
        let title: String
        let description: String?
        var progress: CGFloat?
        if isCalculating {
            title = chatTitle ?? L10n.telegram("StorageManagement.Title")
            description = " "
        } else if total == 0 {
            title = L10n.telegram("StorageManagement.TitleCleared")
            description = L10n.telegram("StorageManagement.DescriptionCleared")
        } else if let chatTitle {
            let fraction = allChatsTotal == 0 ? 0 : Double(total) / Double(allChatsTotal)
            title = chatTitle
            description = L10n.telegram("StorageManagement.DescriptionChatUsage", Self.shareText(fraction))
            progress = CGFloat(fraction)
        } else {
            let fraction = Self.diskFraction(of: total)
            title = L10n.telegram("StorageManagement.Title")
            description = L10n.betterTG("StorageManagement.DescriptionAppUsage", Self.shareText(fraction))
            progress = CGFloat(fraction)
        }
        headerView.update(
            items: isCalculating ? [] : items,
            totalText: DataSize.string(selectedTotal, forceDecimal: true),
            title: title,
            description: description,
            progress: progress,
            animated: animated,
        )
        viewIfLoaded?.setNeedsLayout()
    }

    private func toggleSelection(_ category: Category) {
        if selected.contains(category) {
            selected.remove(category)
        } else {
            selected.insert(category)
        }
        updateHeader(animated: true)
        reload()
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
            let chatID = chat?.id
            var allChatsTotal: Int64 = 0
            for byChat in statistics?.byChat ?? [] {
                allChatsTotal += byChat.byFileType.reduce(0) { $0 + $1.size }
                if chatID == nil || byChat.chatId == chatID {
                    for byType in byChat.byFileType {
                        sizes[Category(byType.fileType), default: 0] += byType.size
                    }
                }
                guard chatID == nil, byChat.chatId != 0, byChat.size > 0,
                      let peer = await SettingsPeer.chat(byChat.chatId, client: client) else { continue }
                chats.append((peer: peer, size: byChat.size))
            }
            guard contextIsCurrent else { return }
            categorySizes = sizes
            self.allChatsTotal = allChatsTotal
            self.chats = chats.sorted { $0.size > $1.size }
            isCalculating = false
            selected = existing
            updateHeader(animated: true)
            reload()
        }
    }

    /// requestClear: Clear Cache with Telegram's text and Clear Entire Cache or Clear Selected, then optimizeStorage
    /// over everything or the selected categories' file types, and ClearCache.Success with the size freed.
    private func confirmClear() {
        let everything = isEverythingSelected
        let fileTypes = everything ? [] : selected.flatMap(\.fileTypes)
        let freed = isCalculating ? fast?.filesSize ?? 0 : selectedSize
        let chatIDs = chat.map { [$0.id] } ?? []
        confirm(
            title: L10n.telegram("StorageManagement.ClearConfirmationTitle"),
            message: L10n.telegram("StorageManagement.ClearConfirmationText"),
            actionTitle: L10n.telegram(
                everything && chat == nil ? "StorageManagement.ClearAll" : "StorageManagement.ClearSelected",
            ),
        ) { [weak self] in
            guard let self else { return }
            isClearing = true
            reload()
            perform { client in
                _ = try await client.send(TDNativeRequests.optimizeStorage(
                    size: 0, ttl: 0, count: 0, immunityDelay: 0, fileTypes: fileTypes, chatIds: chatIDs,
                    excludeChatIds: [],
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
                onCleared?()
                showToast(L10n.telegram(
                    "ClearCache.Success", SettingsFormatting.byteCount(freed), UIDevice.current.model,
                )
                .withoutTelegramMarkup)
                load()
            }
        }
    }
}
