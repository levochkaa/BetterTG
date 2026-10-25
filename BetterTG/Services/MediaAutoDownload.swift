// MediaAutoDownload.swift

import Foundation
import Network
import TDLibKit

// MARK: - MediaAutoDownloadCategory

/// MediaAutoDownloadCategory: the chats a kind of media downloads in by itself, and up to what size.
struct MediaAutoDownloadCategory: Codable, Equatable {
    var contacts: Bool
    var otherPrivate: Bool
    var groups: Bool
    var channels: Bool
    var sizeLimit: Int64
    var predownload: Bool

    var isEnabledForAnyPeer: Bool {
        contacts || otherPrivate || groups || channels
    }

    func isEnabled(for peerType: MediaAutoDownload.PeerType) -> Bool {
        switch peerType {
        case .contact: contacts
        case .otherPrivate: otherPrivate
        case .group: groups
        case .channel: channels
        }
    }

    subscript(peerType: MediaAutoDownload.PeerType) -> Bool {
        get { isEnabled(for: peerType) }
        set {
            switch peerType {
            case .contact: contacts = newValue
            case .otherPrivate: otherPrivate = newValue
            case .group: groups = newValue
            case .channel: channels = newValue
            }
        }
    }
}

// MARK: - MediaAutoDownloadCategories

/// MediaAutoDownloadCategories: photos, videos and GIFs, and files and music. BetterTG doesn't preload stories, so
/// the stories category has no counterpart.
struct MediaAutoDownloadCategories: Codable, Equatable {
    var basePreset: MediaAutoDownload.Preset
    var photo: MediaAutoDownloadCategory
    var video: MediaAutoDownloadCategory
    var file: MediaAutoDownloadCategory

    /// MediaAutoDownloadCategories' order: by the video and file sizes they download, for the custom stop's place on
    /// the data usage slider.
    var downloadedSize: Int64 {
        (video.isEnabledForAnyPeer ? video.sizeLimit : 0) + (file.isEnabledForAnyPeer ? file.sizeLimit : 0)
    }

    subscript(category: MediaAutoDownload.Category) -> MediaAutoDownloadCategory {
        get {
            switch category {
            case .photo: photo
            case .video: video
            case .file: file
            }
        }
        set {
            switch category {
            case .photo: photo = newValue
            case .video: video = newValue
            case .file: file = newValue
            }
        }
    }
}

// MARK: - MediaAutoDownloadConnection

struct MediaAutoDownloadConnection: Codable, Equatable {
    var enabled: Bool
    var preset: MediaAutoDownload.Preset
    var custom: MediaAutoDownloadCategories?
}

// MARK: - MediaAutoDownload

/// Telegram's MediaAutoDownloadSettings, kept on the device for every account: whether media downloads by itself on
/// cellular and on Wi-Fi, each at the Low, Medium or High preset (TDLib's getAutoDownloadSettingsPresets, Telegram's
/// own until they load) or a custom one, and shouldDownloadMediaAutomatically's decision for a message's media.
@MainActor final class MediaAutoDownload {
    enum Preset: Int, Codable, CaseIterable {
        case low
        case medium
        case high
        case custom
    }

    enum NetworkType {
        case cellular
        case wifi
    }

    enum PeerType: CaseIterable {
        case contact
        case otherPrivate
        case group
        case channel
    }

    enum Category {
        case photo
        case video
        case file
    }

    private struct Stored: Codable {
        var cellular: MediaAutoDownloadConnection
        var wifi: MediaAutoDownloadConnection
    }

    static let shared = MediaAutoDownload()

    /// Posted when a setting, the presets or the network changes.
    static let didChange = Notification.Name("BetterTG.MediaAutoDownload.didChange")

    static let defaultCellular = MediaAutoDownloadConnection(enabled: true, preset: .medium, custom: nil)
    static let defaultWifi = MediaAutoDownloadConnection(enabled: true, preset: .high, custom: nil)

    private static let storageKey = "BetterTG.mediaAutoDownload"
    private static let megabyte: Int64 = 1024 * 1024

    /// MediaAutoDownloadSettings.defaultSettings' presets.
    private static var defaultPresets: (
        MediaAutoDownloadCategories,
        MediaAutoDownloadCategories,
        MediaAutoDownloadCategories,
    ) {
        func category(_ enabled: Bool, _ size: Int64, predownload: Bool = false) -> MediaAutoDownloadCategory {
            MediaAutoDownloadCategory(
                contacts: enabled, otherPrivate: enabled, groups: enabled, channels: enabled,
                sizeLimit: size, predownload: predownload,
            )
        }
        return (
            MediaAutoDownloadCategories(
                basePreset: .low,
                photo: category(true, megabyte),
                video: category(false, megabyte),
                file: category(false, megabyte),
            ),
            MediaAutoDownloadCategories(
                basePreset: .medium,
                photo: category(true, megabyte),
                video: category(true, megabyte * 5 / 2),
                file: category(true, megabyte),
            ),
            MediaAutoDownloadCategories(
                basePreset: .high,
                photo: category(true, megabyte),
                video: category(true, 10 * megabyte, predownload: true),
                file: category(true, 3 * megabyte),
            ),
        )
    }

    private(set) var cellular: MediaAutoDownloadConnection
    private(set) var wifi: MediaAutoDownloadConnection
    private(set) var low: MediaAutoDownloadCategories
    private(set) var medium: MediaAutoDownloadCategories
    private(set) var high: MediaAutoDownloadCategories
    /// The network the decisions follow now; anything but Wi-Fi counts as cellular.
    private(set) var networkType = NetworkType.cellular

    private let pathMonitor = NWPathMonitor()

    var isDefault: Bool {
        cellular == Self.defaultCellular && wifi == Self.defaultWifi
    }

    private init() {
        let stored = UserDefaults.standard
            .data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        self.cellular = stored?.cellular ?? Self.defaultCellular
        self.wifi = stored?.wifi ?? Self.defaultWifi
        (self.low, self.medium, self.high) = Self.defaultPresets
        pathMonitor.pathUpdateHandler = { path in
            let type: NetworkType = path.usesInterfaceType(.wifi) ? .wifi : .cellular
            Task { @MainActor in MediaAutoDownload.shared.updateNetworkType(type) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "BetterTG.MediaAutoDownload.path"))
    }

    /// AutodownloadMediaCategoryController's sizes: "1.5 MB", "10 MB", "1.5 GB".
    static func sizeString(_ size: Int64, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> String {
        let gigabyte = 1024 * megabyte
        func string(_ unit: Int64, name: String, keepsFraction: Bool) -> String {
            // A tenth as Telegram counts it: 102 of the unit's 1,024 parts.
            var remainder = (size % unit) / (unit / 1024 * 102)
            if remainder == 10 { remainder = 9 }
            while remainder != 0, remainder % 10 == 0 {
                remainder /= 10
            }
            if remainder != 0, keepsFraction {
                return "\(size / unit)\(decimalSeparator)\(remainder) \(name)"
            }
            return "\(size / unit) \(name)"
        }
        if size >= gigabyte {
            return string(gigabyte, name: "GB", keepsFraction: true)
        } else if size >= megabyte {
            return string(megabyte, name: "MB", keepsFraction: size < 10 * megabyte)
        } else if size >= 1024 {
            return "\(size / 1024) KB"
        }
        return "\(size) B"
    }

    // MARK: Settings

    func connection(for networkType: NetworkType) -> MediaAutoDownloadConnection {
        switch networkType {
        case .cellular: cellular
        case .wifi: wifi
        }
    }

    func updateConnection(_ networkType: NetworkType, _ change: (inout MediaAutoDownloadConnection) -> Void) {
        switch networkType {
        case .cellular: change(&cellular)
        case .wifi: change(&wifi)
        }
        save()
    }

    /// effectiveAutodownloadCategories: the connection's preset, or its custom categories.
    func categories(for networkType: NetworkType) -> MediaAutoDownloadCategories {
        let connection = connection(for: networkType)
        switch connection.preset {
        case .low: return low
        case .medium: return medium
        case .high: return high
        case .custom: return connection.custom ?? medium
        }
    }

    /// An edit of a type of media turns the connection's preset into a custom one.
    func updateCategories(_ networkType: NetworkType, _ change: (inout MediaAutoDownloadCategories) -> Void) {
        var categories = categories(for: networkType)
        change(&categories)
        updateConnection(networkType) {
            $0.preset = .custom
            $0.custom = categories
        }
    }

    func preset(_ preset: Preset) -> MediaAutoDownloadCategories? {
        switch preset {
        case .low: low
        case .medium: medium
        case .high: high
        case .custom: nil
        }
    }

    func reset() {
        cellular = Self.defaultCellular
        wifi = Self.defaultWifi
        save()
    }

    /// presetsWithAutodownloadSettings: the server's sizes in place of the defaults.
    func loadPresets(client: TDLibClient) {
        Task { [weak self] in
            guard let presets = try? await client.send(TDNativeRequests.getAutoDownloadSettingsPresets())
            else { return }
            self?.applyPresets(low: presets.low, medium: presets.medium, high: presets.high)
        }
    }

    // MARK: Decisions

    /// shouldDownloadMediaAutomatically on the current network: a voice message up to at least 2 MB anywhere, else
    /// the category's size limit where it is on for the chat's kind. `size` nil (a photo) only asks the chat.
    func shouldDownload(_ category: Category, size: Int64?, peerType: PeerType, isVoice: Bool = false) -> Bool {
        guard connection(for: networkType).enabled else { return false }
        let settings = categories(for: networkType)[category]
        guard let size else { return settings.isEnabled(for: peerType) }
        if isVoice {
            return size <= max(2 * Self.megabyte, settings.sizeLimit)
        }
        return settings.isEnabled(for: peerType) && size <= settings.sizeLimit
    }

    private func applyPresets(
        low: TDNativeAutoDownloadSettings,
        medium: TDNativeAutoDownloadSettings,
        high: TDNativeAutoDownloadSettings,
    ) {
        func categories(_ settings: TDNativeAutoDownloadSettings, preset: Preset) -> MediaAutoDownloadCategories {
            let videoEnabled = settings.maxVideoFileSize > 0
            let fileEnabled = settings.maxOtherFileSize > 0
            return MediaAutoDownloadCategories(
                basePreset: preset,
                photo: MediaAutoDownloadCategory(
                    contacts: true, otherPrivate: true, groups: true, channels: true,
                    sizeLimit: Int64(settings.maxPhotoFileSize), predownload: false,
                ),
                video: MediaAutoDownloadCategory(
                    contacts: videoEnabled, otherPrivate: videoEnabled, groups: videoEnabled, channels: videoEnabled,
                    sizeLimit: videoEnabled ? settings.maxVideoFileSize : Self.megabyte,
                    predownload: settings.preloadLargeVideos,
                ),
                file: MediaAutoDownloadCategory(
                    contacts: fileEnabled, otherPrivate: fileEnabled, groups: fileEnabled, channels: fileEnabled,
                    sizeLimit: fileEnabled ? settings.maxOtherFileSize : Self.megabyte, predownload: false,
                ),
            )
        }
        self.low = categories(low, preset: .low)
        self.medium = categories(medium, preset: .medium)
        self.high = categories(high, preset: .high)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Stored(cellular: cellular, wifi: wifi)) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private func updateNetworkType(_ type: NetworkType) {
        guard type != networkType else { return }
        networkType = type
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
