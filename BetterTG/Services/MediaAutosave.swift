// MediaAutosave.swift

import Combine
import Foundation
import Photos
import TDLibKit

// MARK: - MediaAutosave

/// StoreDownloadedMedia over TDLib's autosave settings: an incoming photo, or an incoming video no larger than the
/// setting's size, is saved to the photo library once its file has downloaded, by whatever path, when the chat's kind
/// (or its exception) saves that kind of media. A secret chat never saves. Each file is saved once; the photo
/// library is asked for add-only access, so the media lands in the library without Telegram's album.
@MainActor final class MediaAutosave {
    private struct Key: Hashable {
        let accountID: UUID
        let clientID: Int32
        let fileID: Int

        var source: TdUpdateSource {
            TdUpdateSource(accountID: accountID, clientID: clientID)
        }

        init(source: TdUpdateSource, fileID: Int) {
            self.accountID = source.accountID
            self.clientID = source.clientID
            self.fileID = fileID
        }
    }

    private struct Candidate {
        let chatID: Int64
        let scope: AutosaveScope?
        let isVideo: Bool
        let size: Int64
        let date: Int
        let uniqueID: String
    }

    static let shared = MediaAutosave()

    private static let savedKey = "MediaAutosaveSavedFiles"
    private static let savedLimit = 2000

    private var candidates = [Key: Candidate]()
    private var registeredMessages = Set<String>()
    private var settings = [UUID: TDNativeAutosaveSettings]()
    private var saved: [String]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.saved = UserDefaults.standard.stringArray(forKey: Self.savedKey) ?? []
    }

    /// The file into the photo library, dated when the message was sent, under Telegram's file name.
    private nonisolated static func store(path: String, isVideo: Bool, date: Int, uniqueID: String) {
        PhotoLibrarySaver.save(
            fileURL: URL(fileURLWithPath: path),
            isVideo: isVideo,
            name: "telegram-\(isVideo ? "video" : "photo")-\(uniqueID).\(isVideo ? "mov" : "jpg")",
            date: Date(timeIntervalSince1970: TimeInterval(date)),
        )
    }

    func start() {
        guard cancellables.isEmpty else { return }
        nc.scopedPublisher(&cancellables, for: .updateFile) { [weak self] event in
            self?.fileUpdated(event.value.file, source: event.source)
        }
        nc.scopedPublisher(&cancellables, for: .updateAutosaveSettings) { [weak self] event in
            self?.settings[event.source.accountID] = nil
        }
    }

    /// A chat's loaded messages: its incoming photos and videos wait for their files.
    func register(_ messages: [Message], chatType: TDNativeChatType, source: TdUpdateSource) {
        let scope: AutosaveScope? =
            if case .chatTypeSecret = chatType {
                nil
            } else {
                AutosaveScope(chatType: chatType)
            }
        guard scope != nil else { return }
        for message in messages where !message.isOutgoing {
            let messageKey = "\(source.accountID):\(message.chatId):\(message.id)"
            guard !registeredMessages.contains(messageKey) else { continue }
            let file: File?
            let isVideo: Bool
            switch message.content {
            case .messagePhoto(let content):
                file = content.photo.sizes.max { $0.width * $0.height < $1.width * $1.height }?.photo
                isVideo = false
            case .messageVideo(let content):
                file = content.video.video
                isVideo = true
            default:
                continue
            }
            if registeredMessages.count > 50000 { registeredMessages.removeAll() }
            registeredMessages.insert(messageKey)
            guard let file, !file.remote.uniqueId.isEmpty, !saved.contains(file.remote.uniqueId) else { continue }
            let candidate = Candidate(
                chatID: message.chatId,
                scope: scope,
                isVideo: isVideo,
                size: file.size == 0 ? file.expectedSize : file.size,
                date: message.date,
                uniqueID: file.remote.uniqueId,
            )
            let key = Key(source: source, fileID: file.id)
            candidates[key] = candidate
            if file.local.isDownloadingCompleted {
                consider(candidate, path: file.local.path, key: key)
            }
        }
    }

    private func fileUpdated(_ file: File, source: TdUpdateSource) {
        let key = Key(source: source, fileID: file.id)
        guard file.local.isDownloadingCompleted, let candidate = candidates[key] else { return }
        consider(candidate, path: file.local.path, key: key)
    }

    /// The chat's exception, or its kind's settings, decide; then the file is saved once.
    private func consider(_ candidate: Candidate, path: String, key: Key) {
        candidates[key] = nil
        guard let scope = candidate.scope, !saved.contains(candidate.uniqueID),
              TDLib.shared.activeUpdateSource == key.source else { return }
        let client = TDLib.shared.activeClient
        Task { [weak self] in
            guard let self else { return }
            let all: TDNativeAutosaveSettings
            if let cached = settings[key.source.accountID] {
                all = cached
            } else {
                guard let loaded = try? await client.send(TDNativeRequests.getAutosaveSettings()) else { return }
                settings[key.source.accountID] = loaded
                all = loaded
            }
            var configuration = all.exceptions.first { $0.chatId == candidate.chatID }?.settings
                ?? scope.settings(in: all)
            #if DEBUG
                // `-ui-probe-autosave-photos` saves photos from every kind of chat without touching the account's
                // settings.
                if ProcessInfo.processInfo.arguments.contains("-ui-probe-autosave-photos") {
                    configuration = TDNativeScopeAutosaveSettings(
                        autosavePhotos: true, autosaveVideos: false, maxVideoFileSize: 0,
                    )
                }
            #endif
            let saves = candidate.isVideo
                ? configuration.autosaveVideos && candidate.size <= configuration.maxVideoFileSize
                : configuration.autosavePhotos
            guard saves else { return }
            markSaved(candidate.uniqueID)
            Self.store(path: path, isVideo: candidate.isVideo, date: candidate.date, uniqueID: candidate.uniqueID)
        }
    }

    private func markSaved(_ uniqueID: String) {
        saved.append(uniqueID)
        if saved.count > Self.savedLimit { saved.removeFirst(saved.count - Self.savedLimit) }
        UserDefaults.standard.set(saved, forKey: Self.savedKey)
    }
}

// MARK: - PhotoLibrarySaver

/// Adds a copy of a file to the photo library with add-only access, as Telegram's StoreDownloadedMedia and its edited
/// photos do.
enum PhotoLibrarySaver {
    static func save(fileURL: URL, isVideo: Bool, name: String, date: Date) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
            guard (try? FileManager.default.copyItem(at: fileURL, to: copy)) != nil else { return }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = name
                options.shouldMoveFile = true
                request.addResource(with: isVideo ? .video : .photo, fileURL: copy, options: options)
                request.creationDate = date
            } completionHandler: { _, _ in
                try? FileManager.default.removeItem(at: copy)
            }
        }
    }
}

// MARK: - SaveEditedPhotosSettings

/// GeneratedMediaStoreSettings' storeEditedPhotos: a photo edited before it is sent goes to the library too; on by
/// default.
enum SaveEditedPhotosSettings {
    private static let key = "BetterTG.saveEditedPhotos"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
