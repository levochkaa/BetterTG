// RichNotificationMediaPrewarmer.swift

import Combine
import Foundation
import TDLibKitDynamic

/// Owns only active app prewarming attempts, not a history/cache eligibility
/// registry. Durable entries and NSE fallback require a separate evidence gate.
@MainActor final class RichNotificationMediaPrewarmer {
    struct Operations {
        let isCurrent: () -> Bool
        let peer: (Int64) async -> RichNotificationPeerReference?
        let download: (File) async -> File
        let read: (String) -> Data?
        let cache: (Data, RichNotificationMessageReference, Int64) -> Void
    }

    private struct Key: Hashable {
        let chatID: Int64
        let messageID: Int64
    }

    private struct Candidate {
        let file: File
        let placeholder: Data?
    }

    private var source: RichNotificationCacheSource?
    private let center: NotificationCenter
    private var active = [Key: UUID]()
    private var subscriptions = Set<AnyCancellable>()

    init(center: NotificationCenter = nc) {
        self.center = center
        // Accepted TDLib updates are posted on main. Do not queue revocation
        // behind a suspended download's continuation on that same main actor.
        center.publisher(for: TdNotification<UpdateMessageContent>.updateMessageContent.name)
            .compactMap { TdScopedUpdate<UpdateMessageContent>(notification: $0) }
            .sink { [weak self] update in
                guard let self, source?.updateSource == update.source else { return }
                active.removeValue(forKey: Key(chatID: update.value.chatId, messageID: update.value.messageId))
            }
            .store(in: &subscriptions)
        center.publisher(for: TdNotification<UpdateDeleteMessages>.updateDeleteMessages.name)
            .compactMap { TdScopedUpdate<UpdateDeleteMessages>(notification: $0) }
            .sink { [weak self] update in
                guard let self, source?.updateSource == update.source else { return }
                for id in update.value.messageIds {
                    active.removeValue(forKey: Key(chatID: update.value.chatId, messageID: id))
                }
            }
            .store(in: &subscriptions)
    }

    func observeNewMessages(_ admit: @escaping (TdScopedUpdate<UpdateNewMessage>) -> Void) {
        center.publisher(for: TdNotification<UpdateNewMessage>.updateNewMessage.name)
            .compactMap { TdScopedUpdate<UpdateNewMessage>(notification: $0) }
            .sink(receiveValue: admit)
            .store(in: &subscriptions)
    }

    func bind(_ source: RichNotificationCacheSource?) {
        guard self.source != source else { return }
        self.source = source
        active.removeAll()
    }

    @discardableResult func start(
        message: Message, source: RichNotificationCacheSource, operations: Operations,
    ) -> Task<Void, Never>? {
        guard self.source == source, operations.isCurrent() else { return nil }
        let key = Key(chatID: message.chatId, messageID: message.id)
        active.removeValue(forKey: key)
        guard !message.isOutgoing, message.id > 0, RichNotificationMediaEligibility.allows(message),
              let candidate = candidate(for: message.content) else { return nil }
        let token = UUID()
        active[key] = token
        return Task { [weak self] in
            guard let self else { return }
            defer { if active[key] == token { active.removeValue(forKey: key) } }
            @MainActor func current() -> Bool {
                !Task.isCancelled && self.source == source && self.active[key] == token && operations.isCurrent()
            }
            guard current(), let peer = await operations.peer(message.chatId), current() else { return }
            let reference = RichNotificationMessageReference(peer: peer, serverMessageID: message.id >> 20)
            if let placeholder = candidate.placeholder { operations.cache(placeholder, reference, source.userID) }
            guard current() else { return }
            let file = await operations.download(candidate.file)
            guard current(), file.local.isDownloadingCompleted, !file.local.path.isEmpty,
                  let data = operations.read(file.local.path), current() else { return }
            operations.cache(data, reference, source.userID)
        }
    }

    private func candidate(for content: MessageContent) -> Candidate? {
        // Preserve the app's existing supported families; this is not a media
        // feature expansion. Call only after full-message eligibility succeeds.
        switch content {
        case .messagePhoto(let value):
            guard let size = value.photo.sizes.min(by: { lhs, rhs in
                abs(max(lhs.width, lhs.height) - 1280) < abs(max(rhs.width, rhs.height) - 1280)
            }) else { return nil }
            return Candidate(file: size.photo, placeholder: value.photo.minithumbnail?.data)
        case .messageVideo(let value):
            guard let thumbnail = value.video.thumbnail else { return nil }
            return Candidate(file: thumbnail.file, placeholder: value.video.minithumbnail?.data)
        case .messageAnimation(let value):
            guard let thumbnail = value.animation.thumbnail else { return nil }
            return Candidate(file: thumbnail.file, placeholder: value.animation.minithumbnail?.data)
        case .messageSticker(let value):
            guard let thumbnail = value.sticker.thumbnail else { return nil }
            return Candidate(file: thumbnail.file, placeholder: nil)
        default: return nil
        }
    }
}
