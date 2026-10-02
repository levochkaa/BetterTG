// InlineAnimationPlaybackProbe.swift

#if DEBUG
import Combine
import Foundation
import TDLibKitDynamic
import UIKit

@MainActor enum InlineAnimationPlaybackProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }
    private final class Identity {
        var source = TdUpdateSource(accountID: UUID(), clientID: 31)
    }

    private struct Fixture {
        let owner: GalleryVideoPlaybackOwner
        let message: Message
        let backend: TDLibVODProbeBackend
        let context: MediaGalleryPlaybackContext
        let identity: Identity
        let changes: PassthroughSubject<TdUpdateSource, Never>
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-media-probe-inline-animation") else { return }
        Task {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("inline-animation-\(UUID())")
            let result: String
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                let url = root.appendingPathComponent("loop.mp4")
                _ = try await VideoNoteAssetWriter.makeDebugSegment(outputURL: url, duration: 1, frameSeed: 981)
                try await verifyHandoff(url: url)
                try await verifyCancellation(url: url)
                try await verifyRevocation(url: url)
                result = "Inline animation probe passed: native-loop=true; silent=true; same-item/layer=true; "
                    + "stale-attachment-rejected=true; hidden-pause/resume=true; full-download-cancel/retry=true; "
                    + "background-pause=true; source-revoked=true; file/revision-admission=true; "
                    + "secret/spoiler-rejected=true; all-visible-animations=true; ordinary-video-policy-preserved=true; "
                    + "actual-TDLib/UI/hardware=unverified"
            } catch {
                result = "Inline animation probe failed: \(error)"
            }
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("inline-animation-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func fixture(url: URL, autoFulfill: Bool) async throws -> Fixture {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size else { throw Failure(description: "fixture size") }
        let backend = TDLibVODProbeBackend(
            fileURL: url,
            fileSize: size.int64Value,
            network: TDLibVODProbeNetwork(available: true),
        )
        await backend.setAutoFulfill(autoFulfill)
        let identity = Identity()
        let source = identity.source
        let changes = PassthroughSubject<TdUpdateSource, Never>()
        let context = MediaGalleryPlaybackContext(
            probeLocation: ChatLocation(accountID: source.accountID, chatID: 0, clientID: source.clientID, topic: nil),
            vodRanges: TDLibVODRangeCoordinator(accountID: source.accountID.uuidString, client: backend.client),
            clientChanges: changes.eraseToAnyPublisher(),
            currentClientMatches: { identity.source == source },
        )
        let message = await makeMessage(file: backend.file(expectedSize: size.int64Value))
        guard let owner = GalleryVideoPlaybackOwner(message: message, tdlib: .shared, playbackContext: context) else {
            throw Failure(description: "production animation owner rejected")
        }
        return Fixture(
            owner: owner,
            message: message,
            backend: backend,
            context: context,
            identity: identity,
            changes: changes,
        )
    }

    private static func verifyHandoff(url: URL) async throws {
        let f = try await fixture(url: url, autoFulfill: true)
        defer { f.owner.invalidate() }
        let initialCalls = await f.backend.downloadCalls.count
        try require(initialCalls == 0 && f.owner.debugAnimationItem == nil, "eager hidden download")
        let inline = UIView()
        guard let inlineToken = f.owner.attach(to: inline, context: .inline)
            else { throw Failure(description: "inline attachment") }
        var loops = 0
        let observation = f.owner.debugAnimationLoopPublisher.sink { loops += 1 }
        defer { observation.cancel() }
        f.owner.setPlaybackVisible(true, attachment: inlineToken)
        try await wait { f.owner.debugAnimationTime > 0.15 }
        let item = f.owner.debugAnimationItem
        let layer = f.owner.debugAnimationLayer
        try require(item != nil && f.owner.debugAnimationMuted, "native item/silent playback")
        let cell = MediaGalleryCell()
        cell.configure(message: f.message, playbackContext: f.context, videoPlaybackOwner: f.owner)
        f.owner.detach(attachment: inlineToken)
        f.owner.setPlaybackVisible(false, attachment: inlineToken)
        cell.setPlaybackVisible(true)
        try require(
            f.owner.debugAnimationItem == item && f.owner.debugAnimationLayer == layer
                    && f.owner.debugAnimationMuted,
            "handoff replaced item/layer or unmuted",
        )
        try await wait { loops >= 2 }
        guard let returned = f.owner.attach(to: inline, context: .inline)
            else { throw Failure(description: "return attachment") }
        cell.prepareForReuse()
        f.owner.setPlaybackVisible(true, attachment: returned)
        try require(f.owner.debugAnimationItem == item && f.owner.debugAnimationLayer == layer, "stale cell teardown")
        f.owner.setPlaybackVisible(false, attachment: returned)
        try await wait { f.owner.debugAnimationState == .paused }
        let pausedTime = f.owner.debugAnimationTime
        try await Task<Never, Never>.sleep(for: .milliseconds(150))
        try require(abs(f.owner.debugAnimationTime - pausedTime) < 0.1, "offscreen time advanced")
        f.owner.setPlaybackVisible(true, attachment: returned)
        try await wait { f.owner.debugAnimationState == .playing }
        f.owner.debugAnimationApplicationVisible(false)
        try await wait { f.owner.debugAnimationState == .paused }
        f.owner.debugAnimationApplicationVisible(true)
        try await wait { f.owner.debugAnimationState == .playing }
        try require(f.owner.debugAnimationItem == item, "visibility replaced native item")
        let calls = await f.backend.downloadCalls
        try require(!calls.isEmpty && calls.allSatisfy(\.isFullDownload), "invented streaming capability")
        try verifyPolicy(message: f.message, owner: f.owner)
    }

    private static func verifyCancellation(url: URL) async throws {
        let f = try await fixture(url: url, autoFulfill: false)
        defer { f.owner.invalidate() }
        let container = UIView()
        guard let token = f.owner.attach(to: container, context: .inline)
            else { throw Failure(description: "cancel attachment") }
        f.owner.setPlaybackVisible(true, attachment: token)
        try await wait { await !f.backend.downloadCalls.isEmpty }
        f.owner.setPlaybackVisible(false, attachment: token)
        try await wait { await f.backend.completedCancelCount > 0 }
        try require(f.owner.debugAnimationItem == nil, "hidden pending download installed item")
        await f.backend.setAutoFulfill(true)
        f.owner.setPlaybackVisible(true, attachment: token)
        try await wait { f.owner.debugAnimationTime > 0.1 }
        let calls = await f.backend.downloadCalls
        try require(calls.count >= 2 && calls.allSatisfy(\.isFullDownload), "visible retry/full-download routing")
    }

    private static func verifyRevocation(url: URL) async throws {
        for sameAccount in [false, true] {
            let f = try await fixture(url: url, autoFulfill: false)
            defer { f.owner.invalidate() }
            let container = UIView()
            guard let token = f.owner.attach(to: container, context: .inline)
                else { throw Failure(description: "revoke attachment") }
            f.owner.setPlaybackVisible(true, attachment: token)
            try await wait { await !f.backend.downloadCalls.isEmpty }
            f.identity.source = TdUpdateSource(
                accountID: sameAccount ? f.identity.source.accountID : UUID(),
                clientID: 32,
            )
            f.changes.send(f.identity.source)
            try await wait { f.owner.debugAnimationInvalidated }
            try await wait { await f.backend.completedCancelCount > 0 }
            let count = await f.backend.downloadCalls.count
            try require(
                !f.owner.matches(message: f.message)
                        && f.owner.attach(to: UIView(), context: .inline) == nil,
                "revoked owner admitted",
            )
            f.owner.setPlaybackVisible(true)
            await f.backend.setAutoFulfill(true)
            try await Task<Never, Never>.sleep(for: .milliseconds(50))
            let after = await f.backend.downloadCalls.count
            try require(after == count && f.owner.debugAnimationItem == nil, "revoked owner restarted")
        }
    }

    private static func verifyPolicy(message: Message, owner: GalleryVideoPlaybackOwner) throws {
        guard case .messageAnimation(let animation) = message.content
            else { throw Failure(description: "fixture kind") }
        let file = animation.animation.animation
        let replacementFile = File(
            expectedSize: file.expectedSize,
            id: file.id + 1,
            local: file.local,
            remote: file.remote,
            size: file.size,
        )
        try require(
            !owner.matches(message: makeMessage(file: replacementFile))
                    && !owner.matches(message: makeMessage(file: file, revision: 1))
                    && !owner.matches(message: makeMessage(file: file, isVideo: true)),
            "stale media identity admitted",
        )
        for (secret, spoiler) in [(true, false), (false, true)] {
            try require(
                GalleryPlayableMessage(message: makeMessage(file: file, secret: secret, spoiler: spoiler)) == nil,
                "secret/spoiler autoplay admitted",
            )
        }
        let active = InlineMediaPlaybackPolicy.visibleMessageIDs([
            .init(messageID: 1, visibleArea: 10, isAnimation: true),
            .init(messageID: 2, visibleArea: 20, isAnimation: true),
            .init(messageID: 3, visibleArea: 0, isAnimation: true),
            .init(messageID: 4, visibleArea: 5, isAnimation: false),
            .init(messageID: 5, visibleArea: 30, isAnimation: false),
        ])
        try require(active == [1, 2, 5], "inline visibility arbitration")
    }

    private static func makeMessage(
        file: File,
        revision: Int = 0,
        secret: Bool = false,
        spoiler: Bool = false,
        isVideo: Bool = false,
    ) -> Message {
        let content: MessageContent = isVideo
            ? .messageVideo(.init(
                alternativeVideos: [],
                caption: .init(entities: [], text: ""),
                cover: nil,
                hasSpoiler: spoiler,
                isSecret: secret,
                showCaptionAboveMedia: false,
                startTimestamp: 0,
                storyboards: [],
                video: .init(
                    duration: 1,
                    fileName: "probe.mp4",
                    hasStickers: false,
                    height: 240,
                    mimeType: "video/mp4",
                    minithumbnail: nil,
                    supportsStreaming: false,
                    thumbnail: nil,
                    video: file,
                    width: 240,
                ),
            ))
            : .messageAnimation(.init(
                animation: .init(
                    animation: file,
                    duration: 1,
                    fileName: "probe.mp4",
                    hasStickers: false,
                    height: 240,
                    mimeType: "video/mp4",
                    minithumbnail: nil,
                    thumbnail: nil,
                    width: 240,
                ),
                caption: .init(entities: [], text: ""),
                hasSpoiler: spoiler,
                isSecret: secret,
                showCaptionAboveMedia: false,
            ))
        return Message(
            authorSignature: "", autoDeleteIn: 0, canBeSaved: true, chatId: 0,
            containsUnreadMention: false, containsUnreadPollVotes: false, content: content,
            date: 0, editDate: revision, effectId: 0, ephemeralMessageId: 0, factCheck: nil, forwardInfo: nil,
            guestBotCallerId: nil, hasTimestampedMedia: false, id: 9001, importInfo: nil, interactionInfo: nil,
            isChannelPost: false, isFromOffline: false, isOutgoing: true, isPaidGramSuggestedPost: false,
            isPaidStarSuggestedPost: false, isPinned: false, mediaAlbumId: 0, paidMessageStarCount: 0,
            receiverId: nil, replyMarkup: nil, replyTo: nil, restrictionInfo: nil, schedulingState: nil,
            selfDestructIn: 0, selfDestructType: nil, senderBoostCount: 0, senderBusinessBotUserId: 0,
            senderId: .messageSenderUser(.init(userId: 1)), senderTag: "", sendingState: nil,
            suggestedPostInfo: nil, summaryLanguageCode: "", topicId: nil, unreadReactions: [], viaBotUserId: 0,
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }

    private static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while await !condition() {
            try require(ContinuousClock.now < deadline, "native playback/gate timeout")
            try await Task<Never, Never>.sleep(for: .milliseconds(20))
        }
    }
}
#endif
