// RichNotificationCacheCoordinator.swift

import Combine
import Foundation
import TDLibKitDynamic

@MainActor final class RichNotificationCacheCoordinator {
    // MARK: Private

    private struct MediaCandidate {
        let file: File
        let placeholder: Data?
    }

    // MARK: Internal

    static let shared = RichNotificationCacheCoordinator()

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var avatarReferencesByFileID = [Int: Set<RichNotificationPeerReference>]()

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        nc.publisher(&cancellables, for: .updateUser) { [weak self] update in
            self?.cache(user: update.user)
        }
        nc.publisher(&cancellables, for: .updateNewChat) { [weak self] update in
            self?.cache(chat: update.chat)
        }
        nc.publisher(&cancellables, for: .updateChatPhoto) { [weak self] update in
            self?.refresh(chatID: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateNewMessage) { [weak self] update in
            self?.cacheMedia(for: update.message)
        }
        nc.publisher(&cancellables, for: .updateFile) { [weak self] update in
            self?.cacheCompleted(file: update.file)
        }
        nc.publisher(&cancellables, for: .activeTelegramAccountChanged) { [weak self] _ in
            self?.avatarReferencesByFileID.removeAll()
        }
    }

    private func cache(user: User) {
        let reference = RichNotificationPeerReference(kind: .privateChat, id: user.id)
        cacheAvatar(
            reference: reference,
            files: [user.profilePhoto?.small, user.profilePhoto?.big].compactMap(\.self),
            placeholder: user.profilePhoto?.minithumbnail?.data,
        )
    }

    private func cache(chat: Chat) {
        guard let reference = peerReference(for: chat) else { return }
        cacheAvatar(
            reference: reference,
            files: [chat.photo?.small, chat.photo?.big].compactMap(\.self),
            placeholder: chat.photo?.minithumbnail?.data,
        )
    }

    private func refresh(chatID: Int64) {
        Task { [weak self] in
            guard let self, let chat = try? await td.getChat(chatId: chatID) else { return }
            cache(chat: chat)
        }
    }

    private func cacheAvatar(reference: RichNotificationPeerReference, files: [File], placeholder: Data?) {
        if let placeholder {
            RichNotificationCache.cacheAvatar(placeholder, for: reference)
        }
        for file in files {
            avatarReferencesByFileID[file.id, default: []].insert(reference)
            cacheCompleted(file: file)
        }
    }

    private func cacheCompleted(file: File) {
        guard file.local.isDownloadingCompleted,
              !file.local.path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: file.local.path)),
              let references = avatarReferencesByFileID[file.id]
        else { return }
        for reference in references {
            RichNotificationCache.cacheAvatar(data, for: reference)
        }
    }

    private func cacheMedia(for message: Message) {
        guard !message.isOutgoing, let candidate = mediaCandidate(for: message.content) else { return }
        Task {
            guard let chat = try? await td.getChat(chatId: message.chatId),
                  let peer = peerReference(for: chat),
                  message.id > 0
            else { return }
            let reference = RichNotificationMessageReference(
                peer: peer,
                serverMessageID: message.id >> 20,
            )
            if let placeholder = candidate.placeholder {
                RichNotificationCache.cacheMedia(placeholder, for: reference)
            }
            let file = await (try? td.downloadFile(
                fileId: candidate.file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: true,
            )) ?? candidate.file
            guard file.local.isDownloadingCompleted,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: file.local.path))
            else { return }
            RichNotificationCache.cacheMedia(data, for: reference)
        }
    }

    private func mediaCandidate(for content: MessageContent) -> MediaCandidate? {
        switch content {
        case .messagePhoto(let value):
            guard let size = value.photo.sizes.min(by: { lhs, rhs in
                abs(max(lhs.width, lhs.height) - 1280) < abs(max(rhs.width, rhs.height) - 1280)
            }) else { return nil }
            return MediaCandidate(file: size.photo, placeholder: value.photo.minithumbnail?.data)
        case .messageVideo(let value):
            guard let thumbnail = value.video.thumbnail else { return nil }
            return MediaCandidate(file: thumbnail.file, placeholder: value.video.minithumbnail?.data)
        case .messageAnimation(let value):
            guard let thumbnail = value.animation.thumbnail else { return nil }
            return MediaCandidate(file: thumbnail.file, placeholder: value.animation.minithumbnail?.data)
        case .messageSticker(let value):
            guard let thumbnail = value.sticker.thumbnail else { return nil }
            return MediaCandidate(file: thumbnail.file, placeholder: nil)
        default:
            return nil
        }
    }

    private func peerReference(for chat: Chat) -> RichNotificationPeerReference? {
        switch chat.type {
        case .chatTypePrivate(let value):
            RichNotificationPeerReference(kind: .privateChat, id: value.userId)
        case .chatTypeBasicGroup(let value):
            RichNotificationPeerReference(kind: .basicGroup, id: value.basicGroupId)
        case .chatTypeSupergroup(let value):
            RichNotificationPeerReference(kind: .supergroup, id: value.supergroupId)
        default:
            nil
        }
    }
}
