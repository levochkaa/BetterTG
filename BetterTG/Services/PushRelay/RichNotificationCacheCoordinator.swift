// RichNotificationCacheCoordinator.swift

import Combine
import Foundation
import TDLibKitDynamic

// MARK: - RichNotificationCacheSource

struct RichNotificationCacheSource: Equatable {
    let updateSource: TdUpdateSource
    let userID: Int64

    func isCurrent(source: TdUpdateSource?, account: TelegramAccount?, clientID: Int32?) -> Bool {
        userID > 0 && source == updateSource && account?.id == updateSource.accountID
            && account?.userID == userID && clientID == updateSource.clientID
    }
}

// MARK: - RichNotificationAvatarReferences

struct RichNotificationAvatarReferences {
    private var source: RichNotificationCacheSource?
    private var references = [Int: Set<RichNotificationPeerReference>]()

    mutating func bind(_ source: RichNotificationCacheSource?) {
        guard self.source != source else { return }
        self.source = source
        references.removeAll()
    }

    mutating func insert(_ reference: RichNotificationPeerReference, fileID: Int, source: RichNotificationCacheSource) {
        guard self.source == source else { return }
        references[fileID, default: []].insert(reference)
    }

    func references(for fileID: Int, source: RichNotificationCacheSource) -> Set<RichNotificationPeerReference>? {
        guard self.source == source else { return nil }
        return references[fileID]
    }
}

// MARK: - RichNotificationCacheCoordinator

@MainActor final class RichNotificationCacheCoordinator {
    // MARK: Private

    private struct Context {
        let source: RichNotificationCacheSource
        let client: TDLibClient
    }

    private struct Context {
        let source: RichNotificationCacheSource
        let client: TDLibClient
    }

    // MARK: Internal

    static let shared = RichNotificationCacheCoordinator()

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private let tdlib = TDLib.shared
    private var avatarReferences = RichNotificationAvatarReferences()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
            RichNotificationCacheProbe.runIfRequested()
        #endif

        nc.scopedPublisher(&cancellables, for: .updateUser) { [weak self] update in
            guard let self, let context = context(for: update.source) else { return }
            cache(user: update.value.user, context: context)
        }
        nc.scopedPublisher(&cancellables, for: .updateNewChat) { [weak self] update in
            guard let self, let context = context(for: update.source) else { return }
            cache(chat: update.value.chat, context: context)
        }
        nc.scopedPublisher(&cancellables, for: .updateChatPhoto) { [weak self] update in
            guard let self, let context = context(for: update.source) else { return }
            refresh(chatID: update.value.chatId, context: context)
        }
        nc.scopedPublisher(&cancellables, for: .updateNewMessage) { [weak self] update in
            guard let self, let context = context(for: update.source) else { return }
            cacheMedia(for: update.value.message, context: context)
        }
        nc.scopedPublisher(&cancellables, for: .updateFile) { [weak self] update in
            guard let self, let context = context(for: update.source) else { return }
            cacheCompleted(file: update.value.file, context: context)
        }
        tdlib.activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, source == tdlib.activeUpdateSource else { return }
                // A queued source change must not clear a newer admitted map.
                if context(for: source) == nil { avatarReferences.bind(nil) }
            }
            .store(in: &cancellables)
    }

    private func context(for source: TdUpdateSource) -> Context? {
        guard source == tdlib.activeUpdateSource, let account = tdlib.activeAccount,
              let userID = account.userID, let client = tdlib.authorizationClient(for: source)
        else { return nil }
        let bound = RichNotificationCacheSource(updateSource: source, userID: userID)
        guard bound.isCurrent(source: tdlib.activeUpdateSource, account: account, clientID: client.id)
        else { return nil }
        avatarReferences.bind(bound)
        return Context(source: bound, client: client)
    }

    private func isCurrent(_ context: Context) -> Bool {
        !Task.isCancelled && context.source.isCurrent(
            source: tdlib.activeUpdateSource, account: tdlib.activeAccount,
            clientID: tdlib.authorizationClient(for: context.source.updateSource)?.id,
        )
    }

    private func cache(user: User, context: Context) {
        let reference = RichNotificationPeerReference(kind: .privateChat, id: user.id)
        cacheAvatar(
            reference: reference,
            files: [user.profilePhoto?.small, user.profilePhoto?.big].compactMap(\.self),
            placeholder: user.profilePhoto?.minithumbnail?.data,
            context: context,
        )
    }

    private func cache(chat: Chat, context: Context) {
        guard let reference = peerReference(for: chat) else { return }
        cacheAvatar(
            reference: reference,
            files: [chat.photo?.small, chat.photo?.big].compactMap(\.self),
            placeholder: chat.photo?.minithumbnail?.data,
            context: context,
        )
    }

    private func refresh(chatID: Int64, context: Context) {
        Task { [weak self] in
            guard let self, isCurrent(context),
                  let chat = try? await context.client.getChat(chatId: chatID), isCurrent(context) else { return }
            cache(chat: chat, context: context)
        }
    }

    private func cacheAvatar(
        reference: RichNotificationPeerReference,
        files: [File],
        placeholder: Data?,
        context: Context,
    ) {
        guard isCurrent(context) else { return }
        if let placeholder {
            RichNotificationCache.cacheAvatar(placeholder, for: reference, accountID: context.source.userID)
        }
        for file in files {
            avatarReferences.insert(reference, fileID: file.id, source: context.source)
            cacheCompleted(file: file, context: context)
        }
    }

    private func cacheCompleted(file: File, context: Context) {
        guard isCurrent(context),
              let references = avatarReferences.references(for: file.id, source: context.source), !references.isEmpty,
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: file.local.path))
        else { return }
        for reference in references {
            RichNotificationCache.cacheAvatar(data, for: reference, accountID: context.source.userID)
        }
    }

    private func cacheMedia(for message: Message, context: Context) {
        guard !message.isOutgoing, let candidate = mediaCandidate(for: message.content) else { return }
        Task { [weak self] in
            guard let self, isCurrent(context),
                  let chat = try? await context.client.getChat(chatId: message.chatId), isCurrent(context),
                  let peer = peerReference(for: chat),
                  message.id > 0
            else { return }
            let reference = RichNotificationMessageReference(
                peer: peer,
                serverMessageID: message.id >> 20,
            )
            if let placeholder = candidate.placeholder {
                RichNotificationCache.cacheMedia(placeholder, for: reference, accountID: context.source.userID)
            }
            let file = await (try? context.client.downloadFile(
                fileId: candidate.file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: true,
            )) ?? candidate.file
            guard isCurrent(context), file.local.isDownloadingCompleted,
                  !file.local.path.isEmpty,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: file.local.path))
            else { return }
            RichNotificationCache.cacheMedia(data, for: reference, accountID: context.source.userID)
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
