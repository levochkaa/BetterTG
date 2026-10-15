// StorageUsageViewController.swift

import TDLibKit
import UIKit

// MARK: - StorageUsageViewController

/// Telegram's Storage Usage (StorageUsageScreen) on TDLib's statistics: Clear Entire Cache with Telegram's
/// confirmation (optimizeStorage with no limits), the cache by media type and by chat. Keep Media and the maximum
/// cache size need a periodic cleanup BetterTG doesn't run, so they are not offered.
final class StorageUsageViewController: SettingsListViewController {
    private enum Category: CaseIterable {
        case photos
        case videos
        case files
        case music
        case voice
        case stickers
        case avatars
        case other

        var title: String {
            switch self {
            case .photos: L10n.telegram("StorageManagement.SectionPhotos")
            case .videos: L10n.telegram("StorageManagement.SectionVideos")
            case .files: L10n.telegram("StorageManagement.SectionFiles")
            case .music: L10n.telegram("StorageManagement.SectionMusic")
            case .voice: L10n.telegram("StorageManagement.SectionVoiceMessages")
            case .stickers: L10n.telegram("StorageManagement.SectionStickers")
            case .avatars: L10n.telegram("StorageManagement.SectionAvatars")
            case .other: L10n.telegram("StorageManagement.SectionOther")
            }
        }

        init(_ type: TDNativeFileType) {
            self =
                switch type {
                case .fileTypePhoto, .fileTypePhotoStory, .fileTypeSelfDestructingPhoto: .photos
                case .fileTypeAnimation, .fileTypeLivePhotoVideo, .fileTypeSelfDestructingLivePhotoVideo,
                     .fileTypeSelfDestructingVideo, .fileTypeSelfDestructingVideoNote, .fileTypeVideo,
                     .fileTypeVideoNote,
                     .fileTypeVideoStory:
                    .videos
                case .fileTypeDocument: .files
                case .fileTypeAudio: .music
                case .fileTypeSelfDestructingVoiceNote, .fileTypeVoiceNote: .voice
                case .fileTypeSticker: .stickers
                case .fileTypeProfilePhoto: .avatars
                case .fileTypeNone, .fileTypeNotificationSound, .fileTypeSecret, .fileTypeSecretThumbnail,
                     .fileTypeSecure,
                     .fileTypeThumbnail, .fileTypeUnknown, .fileTypeWallpaper:
                    .other
                }
        }
    }

    private var fast: TDNativeStorageStatisticsFast?
    private var categorySizes = [Category: Int64]()
    private var chats = [(peer: SettingsPeer, size: Int64)]()
    private var isCalculating = true
    private var isClearing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("StorageManagement.Title")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        let loading = L10n.telegram("Channel.NotificationLoading")
        let total = fast.map { $0.filesSize + $0.databaseSize + $0.languagePackDatabaseSize + $0.logSize }
        var sections = [SettingsSection(
            footer: L10n.telegram("StorageManagement.SectionsDescription"),
            rows: [SettingsRow(
                title: L10n.telegram("StorageManagement.ClearAll"),
                detail: fast.map { SettingsFormatting.byteCount($0.filesSize) },
                style: .action(destructive: false),
                accessory: isClearing ? .activity : .none,
                isEnabled: !isClearing && (fast?.filesSize ?? 0) > 0,
            ) { [weak self] in self?.confirmClear() }],
        )]
        var usageRows = [SettingsRow(
            title: L10n.telegram("ChatSettings.Cache"),
            detail: total.map(SettingsFormatting.byteCount) ?? loading,
        )]
        if isCalculating {
            usageRows.append(SettingsRow(title: loading, style: .status(.secondaryLabel), accessory: .activity))
        } else {
            for category in Category.allCases {
                guard let size = categorySizes[category], size > 0 else { continue }
                usageRows.append(SettingsRow(title: category.title, detail: SettingsFormatting.byteCount(size)))
            }
        }
        if let fast {
            let serviceSize = fast.databaseSize + fast.languagePackDatabaseSize + fast.logSize
            usageRows.append(SettingsRow(
                title: L10n.telegram("Cache.ServiceFiles"),
                detail: SettingsFormatting.byteCount(serviceSize),
            ))
        }
        sections.append(SettingsSection(rows: usageRows))
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
                showToast(L10n.telegram("StorageManagement.TitleCleared"))
                load()
            }
        }
    }
}
