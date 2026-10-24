// RichNotificationMediaPrewarmerProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    @MainActor enum RichNotificationMediaPrewarmerProbe {
        enum Kind { case photo, video, animation, videoNote, document, sticker }

        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Gate {
            private var pending: (File, CheckedContinuation<File, Never>)?
            private var observer: CheckedContinuation<Bool, Never>?
            private var entered = false
            private var opened = false

            func hold(_ file: File) async -> File {
                guard !opened else { return file }
                return await withCheckedContinuation { continuation in
                    pending = (file, continuation)
                    entered = true
                    observer?.resume(returning: true)
                    observer = nil
                }
            }

            func wait() async -> Bool {
                if entered { return true }
                return await withCheckedContinuation { continuation in
                    observer = continuation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.observer?.resume(returning: false)
                        self?.observer = nil
                    }
                }
            }

            func open() {
                opened = true
                if let (file, continuation) = pending { pending = nil
                continuation.resume(returning: file)
                }
            }
        }

        @MainActor private final class Fixture {
            static var file: File {
                .init(
                    expectedSize: 3,
                    id: 7,
                    local: .init(
                        canBeDeleted: true,
                        canBeDownloaded: true,
                        downloadOffset: 0,
                        downloadedPrefixSize: 3,
                        downloadedSize: 3,
                        isDownloadingActive: false,
                        isDownloadingCompleted: true,
                        path: "/probe/injected-media",
                    ),
                    remote: .init(
                        id: "probe",
                        isUploadingActive: false,
                        isUploadingCompleted: true,
                        uniqueId: "probe",
                        uploadedSize: 3,
                    ),
                    size: 3,
                )
            }

            let center = NotificationCenter()
            let source = RichNotificationCacheSource(updateSource: .init(accountID: UUID(), clientID: 11), userID: 101)
            lazy var warmer = RichNotificationMediaPrewarmer(center: center)
            var current = true
            var peerCalls = 0
            var downloadCalls = 0
            var reads = 0
            var writes = [(RichNotificationMessageReference, Int64, Data)]()
            var tasks = [Task<Void, Never>]()
            var gates = [Gate]()
            var gate: Gate?
            var peerGate: Gate?

            var operations: RichNotificationMediaPrewarmer.Operations {
                .init(isCurrent: { [self] in current }, peer: { [self] _ in
                    peerCalls += 1
                    if let peerGate { _ = await peerGate.hold(Self.file) }
                    return .init(kind: .privateChat, id: 77)
                }, download: { [self] file in
                    downloadCalls += 1
                    if let gate { return await gate.hold(file) }
                    return file
                }, read: { [self] _ in
                    reads += 1
                    return Data([7, 8, 9])
                }, cache: { [self] data, reference, account in writes.append((reference, account, data)) })
            }

            func start(_ message: Message) -> Task<Void, Never>? {
                let task = warmer.start(message: message, source: source, operations: operations)
                if let task { tasks.append(task) }
                return task
            }

            func prepare() {
                warmer.bind(source)
                warmer.observeNewMessages { [weak self] update in
                    guard let self, update.source == source.updateSource else { return }
                    _ = start(update.value.message)
                }
            }

            func edit(_ message: Message, source: TdUpdateSource? = nil) {
                center.postTdUpdate(name: .updateMessageContent, object: UpdateMessageContent(
                    chatId: message.chatId, messageId: message.id, newContent: message.content,
                ), source: source ?? self.source.updateSource)
            }

            func delete(_ message: Message) {
                center.postTdUpdate(name: .updateDeleteMessages, object: UpdateDeleteMessages(
                    chatId: message.chatId, fromCache: false, isPermanent: true, messageIds: [message.id],
                ), source: source.updateSource)
            }

            func finish() async {
                warmer.bind(nil)
                gates.forEach { $0.open() }
                for task in tasks {
                    await task.value
                }
            }
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-media-admission") else { return }
            Task {
                let result: String
                let f = Fixture()
                f.prepare()
                do {
                    try await verify(f)
                    result = "PASS: full-message concealment/self-destruct gate before injected peer/download/cache; ordinary positives; "
                        + "exact ordinary cloud IDs before IO; local/scheduled/overflow aliases refused; "
                        + "exact production publishers and async leases; held edit/delete/source/replacement refusal; own-token cleanup; "
                        + "real TDLib/NSE/durable cache revocation=unverified; verified cache-only media restoration=pending; RPC/disk-media=0"
                } catch {
                    result = "FAIL: \(error)"
                }
                await f.finish()
                log(result)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("notification-media-admission-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }

        static func content(
            _ kind: Kind,
            secret: Bool = false,
            spoiler: Bool = false,
            placeholder: Bool = false,
        ) -> MessageContent {
            let file = Fixture.file
            let thumbnail = Thumbnail(file: file, format: .thumbnailFormatJpeg, height: 16, width: 16)
            let mini: Minithumbnail? = placeholder ? .init(data: Data([1, 2]), height: 2, width: 2) : nil
            let caption = FormattedText(entities: [], text: "")
            switch kind {
            case .photo:
                return .messagePhoto(.init(
                    photo: .init(
                        hasStickers: false,
                        minithumbnail: mini,
                        sizes: [.init(height: 16, photo: file, progressiveSizes: [], type: "x", width: 16)],
                    ),
                    video: nil,
                    caption: caption,
                    showCaptionAboveMedia: false,
                    hasSpoiler: spoiler,
                    isSecret: secret,
                ))
            case .video:
                return .messageVideo(.init(
                    video: .init(
                        duration: 1,
                        width: 16,
                        height: 16,
                        fileName: "probe",
                        mimeType: "video/mp4",
                        hasStickers: false,
                        supportsStreaming: false,
                        minithumbnail: mini,
                        thumbnail: thumbnail,
                        video: file,
                    ),
                    alternativeVideos: [],
                    storyboards: [],
                    cover: nil,
                    startTimestamp: 0,
                    caption: caption,
                    showCaptionAboveMedia: false,
                    hasSpoiler: spoiler,
                    isSecret: secret,
                ))
            case .animation:
                return .messageAnimation(.init(
                    animation: .init(
                        duration: 1,
                        width: 16,
                        height: 16,
                        fileName: "probe",
                        mimeType: "video/mp4",
                        hasStickers: false,
                        minithumbnail: mini,
                        thumbnail: thumbnail,
                        animation: file,
                    ),
                    caption: caption,
                    showCaptionAboveMedia: false,
                    hasSpoiler: spoiler,
                    isSecret: secret,
                ))
            case .videoNote:
                return .messageVideoNote(.init(
                    videoNote: .init(
                        duration: 1,
                        waveform: Data(),
                        length: 16,
                        minithumbnail: mini,
                        thumbnail: thumbnail,
                        speechRecognitionResult: nil,
                        video: file,
                    ),
                    isViewed: false,
                    isSecret: secret,
                ))
            case .document:
                return .messageDocument(.init(caption: caption, document: .init(
                    document: file,
                    fileName: "probe",
                    mimeType: "application/pdf",
                    minithumbnail: mini,
                    thumbnail: thumbnail,
                )))
            case .sticker:
                return .messageSticker(.init(
                    sticker: .init(
                        id: 1,
                        setId: 0,
                        width: 16,
                        height: 16,
                        emoji: "",
                        format: .stickerFormatWebp,
                        fullType: .stickerFullTypeRegular(.init(premiumAnimation: nil)),
                        thumbnail: thumbnail,
                        sticker: file,
                    ),
                    isPremium: false,
                ))
            }
        }

        static func message(
            _ content: MessageContent,
            chatID: Int64 = 7,
            id: Int64 = 88 << 20,
            destruction: MessageSelfDestructType? = nil,
            destructionIn: Double = 0,
            autoDeleteIn: Double = 0,
        ) -> Message {
            .init(
                id: id,
                senderId: .messageSenderUser(.init(userId: 1)),
                receiverId: nil,
                chatId: chatID,
                sendingState: nil,
                schedulingState: nil,
                isOutgoing: false,
                isPinned: false,
                isFromOffline: false,
                canBeSaved: true,
                hasTimestampedMedia: false,
                isChannelPost: false,
                isPaidStarSuggestedPost: false,
                isPaidGramSuggestedPost: false,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                date: 0,
                editDate: 0,
                forwardInfo: nil,
                importInfo: nil,
                interactionInfo: nil,
                unreadReactions: [],
                factCheck: nil,
                suggestedPostInfo: nil,
                replyTo: nil,
                topicId: nil,
                selfDestructType: destruction,
                selfDestructIn: destructionIn,
                autoDeleteIn: autoDeleteIn,
                viaBotUserId: 0,
                guestBotCallerId: nil,
                senderBusinessBotUserId: 0,
                senderBoostCount: 0,
                senderTag: "",
                paidMessageStarCount: 0,
                authorSignature: "",
                mediaAlbumId: 0,
                effectId: 0,
                restrictionInfo: nil,
                summaryLanguageCode: "",
                content: content,
                ephemeralContent: nil,
                replyMarkup: nil,
                ephemeralMessageId: 0,
                chatInstance: 0,
            )
        }

        private static func verify(_ f: Fixture) async throws {
            for id: Int64 in [0, -1, 1, (88 << 20) + 1, (88 << 20) + 4, (Int64(Int32.max) + 1) << 20, Int64.max] {
                try require(f.start(message(content(.photo), id: id)) == nil, "noncloud ID acquired a prewarming task")
            }
            for kind in [Kind.photo, .video, .animation] {
                for flags in [(true, false), (false, true), (true, true)] {
                    let denied = message(content(kind, secret: flags.0, spoiler: flags.1, placeholder: true))
                    try require(
                        !RichNotificationMediaEligibility.allows(denied) && f.start(denied) == nil,
                        "concealed media acquired a prewarming task",
                    )
                }
            }
            for denied in [
                message(content(.videoNote, secret: true)),
                message(content(.photo), destruction: .messageSelfDestructTypeImmediately),
                message(
                    content(.photo),
                    destruction: .messageSelfDestructTypeTimer(.init(selfDestructTime: 30)),
                ),
                message(content(.photo), destructionIn: 1),
            ] {
                try require(
                    !RichNotificationMediaEligibility.allows(denied) && f.start(denied) == nil,
                    "secret/self-destruct envelope acquired prewarming",
                )
            }
            try require(
                f.peerCalls == 0 && f.downloadCalls == 0 && f.reads == 0 && f.writes.isEmpty,
                "negative admission touched injected IO",
            )
            for kind in [Kind.photo, .video, .animation, .sticker] {
                let value = message(content(kind), autoDeleteIn: 3600)
                try require(RichNotificationMediaEligibility.allows(value), "ordinary media/auto-delete was denied")
                guard let task = f.start(value) else { throw Failure(description: "positive media task absent") }
                await task.value
            }
            for kind in [Kind.videoNote, .document] {
                try require(
                    RichNotificationMediaEligibility.allows(message(content(kind))),
                    "ordinary shared-policy family denied",
                )
            }
            try require(
                f.peerCalls == 4 && f.downloadCalls == 4 && f.reads == 4 && f.writes.count == 4
                && f.writes.allSatisfy { $0.0.serverMessageID == 88 && $0.1 == 101 && $0.2 == Data([7, 8, 9]) },
                "ordinary app families did not follow the original positive path",
            )
            let beforeMaximum = f.writes.count
            guard let maximumTask = f.start(message(content(.photo), id: Int64(Int32.max) << 20)) else {
                throw Failure(description: "maximum valid cloud ID was denied")
            }
            await maximumTask.value
            try require(
                f.writes.count == beforeMaximum + 1 && f.writes.last?.0.serverMessageID == Int64(Int32.max),
                "maximum valid cloud ID cache key was not preserved",
            )
            let beforePlaceholder = f.writes.count
            guard let placeholderTask = f.start(message(content(.photo, placeholder: true))) else {
                throw Failure(description: "ordinary placeholder task absent")
            }
            await placeholderTask.value
            try require(
                f.writes.count == beforePlaceholder + 2
                && f.writes[beforePlaceholder].2 == Data([1, 2])
                && f.writes[beforePlaceholder + 1].2 == Data([7, 8, 9])
                && f.writes.suffix(2).allSatisfy { $0.0.peer == .init(kind: .privateChat, id: 77)
                    && $0.0.serverMessageID == 88 && $0.1 == 101
                },
                "ordinary placeholder/full preview order or exact destination changed",
            )

            let baseline = (f.peerCalls, f.downloadCalls, f.writes.count)
            let priorTasks = f.tasks.count
            let ordinary = message(content(.photo))
            let hidden = message(content(.photo, spoiler: true))
            f.center.postTdUpdate(
                name: .updateNewMessage,
                object: UpdateNewMessage(message: ordinary),
                source: f.source.updateSource,
            )
            try require(f.tasks.count == priorTasks + 1, "new-message publisher did not synchronously admit a task")
            let admitted = f.tasks[priorTasks]
            f.edit(hidden) // Same accepted burst, before the admitted Task runs.
            await admitted.value
            try require(
                f.peerCalls == baseline.0 && f.downloadCalls == baseline.1 && f.writes.count == baseline.2,
                "new-message publisher hop admitted work after its synchronous edit",
            )

            for reason in 0..<5 {
                f.warmer.bind(f.source)
                let gate = Gate()
                f.gates.append(gate)
                f.gate = gate
                guard let task = f.start(ordinary) else { throw Failure(description: "held positive task absent") }
                try await require(gate.wait(), "download hold was not reached")
                let before = (f.reads, f.writes.count)
                switch reason {
                case 0: f.edit(hidden)
                case 1: f.delete(ordinary)
                case 2: f.warmer.bind(nil)
                f.warmer.bind(f.source)
                case 3:
                    f.warmer.bind(.init(
                        updateSource: .init(accountID: f.source.updateSource.accountID, clientID: 12),
                        userID: 101,
                    ))
                default: f.current = false
                }
                gate.open()
                await task.value
                try require(
                    f.reads == before.0 && f.writes.count == before.1,
                    "revoked held download read or wrote old media",
                )
                f.current = true
            }
            f.warmer.bind(f.source)
            f.gate = nil
            let peerGate = Gate()
            f.gates.append(peerGate)
            f.peerGate = peerGate
            guard let peerTask = f.start(ordinary) else { throw Failure(description: "peer lookup task absent") }
            try await require(peerGate.wait(), "peer lookup hold was not reached")
            let downloads = f.downloadCalls
            f.delete(ordinary)
            peerGate.open()
            await peerTask.value
            f.peerGate = nil
            try require(f.downloadCalls == downloads, "deleted peer lookup result started a download")

            // Old completion must not retire a replacement for the identical raw ID.
            let oldGate = Gate()
            f.gates.append(oldGate)
            f.gate = oldGate
            guard let old = f.start(ordinary) else { throw Failure(description: "old replacement task absent") }
            try await require(oldGate.wait(), "old replacement download not held")
            let newGate = Gate()
            f.gates.append(newGate)
            f.gate = newGate
            guard let fresh = f.start(ordinary) else { throw Failure(description: "fresh replacement task absent") }
            try await require(newGate.wait(), "fresh replacement download not held")
            let before = f.writes.count
            oldGate.open()
            await old.value
            try require(f.writes.count == before, "old replacement task wrote")
            // A different chat/raw ID/source must not revoke the fresh lease.
            f.edit(message(content(.photo, spoiler: true), chatID: 8))
            f.edit(message(content(.photo, spoiler: true), id: ordinary.id + 1))
            f.edit(hidden, source: .init(accountID: UUID(), clientID: 11))
            newGate.open()
            await fresh.value
            try require(f.writes.count == before + 1, "old cleanup or nonmatching update revoked replacement")
            f.gate = nil
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            if !condition { throw Failure(description: detail) }
        }
    }
#endif
