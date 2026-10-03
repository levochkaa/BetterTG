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
    struct Registration {
        let peer: RichNotificationPeerReference
        let revision: RichNotificationAvatarRevision
        let rank: Int
    }

    private struct Photo {
        let fileIDs: [Int]
        let revision: RichNotificationAvatarRevision
        let sequence: UInt64
    }

    private(set) var sequence: UInt64 = 0

    private var source: RichNotificationCacheSource?
    private var references = [Int: Set<RichNotificationPeerReference>]()
    /// Current-source, metadata-only registrations; their total peer count is not
    /// the worker's bounded pending-payload or successful-candidate cache.
    private var photos = [RichNotificationPeerReference: Photo]()

    func wasReplaced(_ peer: RichNotificationPeerReference, after sequence: UInt64) -> Bool {
        (photos[peer]?.sequence ?? 0) > sequence
    }

    mutating func bind(_ source: RichNotificationCacheSource?) {
        guard self.source != source else { return }
        for photo in photos.values {
            photo.revision.invalidate()
        }
        self.source = source
        references.removeAll()
        photos.removeAll()
    }

    mutating func replace(
        _ reference: RichNotificationPeerReference, fileIDs: [Int], source: RichNotificationCacheSource,
    ) -> RichNotificationAvatarRevision? {
        guard self.source == source else { return nil }
        if let photo = photos[reference], photo.fileIDs == fileIDs { return photo.revision }
        if let previous = photos.removeValue(forKey: reference) {
            previous.revision.invalidate()
            for fileID in previous.fileIDs {
                references[fileID]?.remove(reference)
                if references[fileID]?.isEmpty == true { references.removeValue(forKey: fileID) }
            }
        }
        let revision = RichNotificationAvatarRevision()
        sequence &+= 1
        photos[reference] = Photo(fileIDs: fileIDs, revision: revision, sequence: sequence)
        for fileID in fileIDs {
            references[fileID, default: []].insert(reference)
        }
        return revision
    }

    func references(for fileID: Int, source: RichNotificationCacheSource) -> Set<RichNotificationPeerReference>? {
        guard self.source == source else { return nil }
        return references[fileID]
    }

    func registrations(for fileID: Int, source: RichNotificationCacheSource) -> [Registration] {
        guard self.source == source else { return [] }
        return (references[fileID] ?? []).compactMap { peer in
            guard let photo = photos[peer], let index = photo.fileIDs.lastIndex(of: fileID) else { return nil }
            return Registration(peer: peer, revision: photo.revision, rank: index + 1)
        }
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
    private let avatarWorker = RichNotificationAvatarWorker()
    private var refreshRequests = [Int64: UUID]()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
            RichNotificationCacheProbe.runIfRequested()
            RichNotificationAvatarWorkerProbe.runIfRequested()
        #endif

        // TDLib publishes this synchronously on its main-queue admission path.
        // In particular handoff emits nil without an activeClientChanges event.
        tdlib.authorizationUpdates
            .sink { [weak self] snapshot in
                guard let self else { return }
                if let source = snapshot?.source, context(for: source) != nil { return }
                avatarReferences.bind(nil)
                avatarWorker.bind(nil)
                refreshRequests.removeAll()
            }
            .store(in: &cancellables)

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
                if context(for: source) == nil {
                    avatarReferences.bind(nil)
                    avatarWorker.bind(nil)
                    refreshRequests.removeAll()
                }
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
        avatarWorker.bind(bound)
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
        refreshRequests.removeValue(forKey: chat.id)
        guard let reference = peerReference(for: chat) else { return }
        cacheAvatar(
            reference: reference,
            files: [chat.photo?.small, chat.photo?.big].compactMap(\.self),
            placeholder: chat.photo?.minithumbnail?.data,
            context: context,
        )
    }

    private func refresh(chatID: Int64, context: Context) {
        let request = UUID()
        let photoSequence = avatarReferences.sequence
        refreshRequests[chatID] = request
        Task { [weak self] in
            guard let self else { return }
            defer { if refreshRequests[chatID] == request { refreshRequests.removeValue(forKey: chatID) } }
            guard isCurrent(context), refreshRequests[chatID] == request,
                  let chat = try? await context.client.getChat(chatId: chatID), isCurrent(context),
                  refreshRequests[chatID] == request,
                  let peer = peerReference(for: chat), !avatarReferences.wasReplaced(peer, after: photoSequence)
            else { return }
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
        guard let revision = avatarReferences.replace(
            reference,
            fileIDs: files.map(\.id),
            source: context.source,
        ) else { return }
        if let placeholder {
            avatarWorker.offer(.init(
                peer: reference,
                source: context.source,
                revision: revision,
                rank: 0,
                input: .data(placeholder),
            ))
        }
        for file in files {
            cacheCompleted(file: file, context: context)
        }
    }

    private func cacheCompleted(file: File, context: Context) {
        guard isCurrent(context),
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty
        else { return }
        for registration in avatarReferences.registrations(for: file.id, source: context.source) {
            avatarWorker.offer(.init(
                peer: registration.peer,
                source: context.source,
                revision: registration.revision,
                rank: registration.rank,
                input: .path(file.local.path),
            ))
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
