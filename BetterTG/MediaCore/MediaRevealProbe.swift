// MediaRevealProbe.swift

#if DEBUG
import Combine
import Foundation
import TDLibKit
import UIKit

@MainActor enum MediaRevealProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }
    private final class Identity {
        var source = TdUpdateSource(accountID: UUID(), clientID: 41)
    }

    private struct Fixture {
        let context: MediaGalleryPlaybackContext
        let session: MediaRevealSession
        let identity: Identity
        let backend: TDLibVODProbeBackend
        let file: File
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-media-probe-media-reveal") else { return }
        Task {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-reveal-\(UUID())")
            let result: String
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                let url = root.appendingPathComponent("source.mp4")
                _ = try await VideoNoteAssetWriter.makeDebugSegment(outputURL: url, duration: 1, frameSeed: 2081)
                try await verifyPolicy(url: url, window: window)
                try await verifyGallery(url: url)
                try await verifyPendingRevocation(url: url)
                result = "Media reveal probe passed: timeline-first-reveal/second-open=true; "
                    + "photo/video/animation/secret-gates=true; member-isolation=true; selected-gallery-only=true; "
                    + "concealed-cell-no-raw-factory=true; pre-reveal-downloads=0; native-after-reveal=true; "
                    + "same-ID-revision-reconceals=true; stale-snapshot-denied=true; "
                    + "PiP-snapshot-session-identity=true; revision-cancels-pending-download=true; "
                    + "source/file/progress-revision-checks=true; actual-TDLib/timeline-UI/system-PiP/profile=unverified"
            } catch {
                result = "Media reveal probe failed: \(error)"
            }
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("media-reveal-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func fixture(url: URL, autoFulfill: Bool = true) async throws -> Fixture {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw Failure(description: "fixture size")
        }
        let backend = TDLibVODProbeBackend(
            fileURL: url,
            fileSize: size.int64Value,
            network: TDLibVODProbeNetwork(available: true),
        )
        await backend.setAutoFulfill(autoFulfill)
        let identity = Identity()
        let source = identity.source
        let context = MediaGalleryPlaybackContext(
            probeLocation: ChatLocation(accountID: source.accountID, chatID: 0, clientID: source.clientID, topic: nil),
            vodRanges: TDLibVODRangeCoordinator(accountID: source.accountID.uuidString, client: backend.client),
            currentClientMatches: { identity.source == source },
        )
        return await Fixture(
            context: context,
            session: MediaRevealSession(context: context),
            identity: identity,
            backend: backend,
            file: backend.file(expectedSize: size.int64Value),
        )
    }

    private static func verifyPolicy(url: URL, window: UIWindow) async throws {
        let f = try await fixture(url: url)
        let animation = message(file: f.file)
        let other = message(file: f.file, id: 9002)
        f.session.reconcile([animation, other])
        let permit = f.session.permit(for: animation)
        try require(permit?.allowsPixels == false, "initial concealment")
        try require(GalleryPlayableMessage(message: animation, revealPermit: permit) == nil, "eager descriptor")
        try require(GalleryVideoPlaybackOwner(
            message: animation,
            tdlib: .shared,
            playbackContext: f.context,
            revealPermit: permit,
        ) == nil, "eager owner")
        let coverCell = MediaGalleryCell()
        coverCell.configure(
            message: animation,
            playbackContext: f.context,
            revealPermit: permit,
            requiresRevealPermit: true,
        )
        try require(
            coverCell.contentView.subviews.count == 1 && coverCell.contentView.subviews.first is MediaConcealmentView,
            "concealed cell created raw factory",
        )
        try await require(f.backend.downloadCalls.isEmpty, "pre-reveal download")
        try require(f.session.timelineTap(captured: animation, current: animation) == .revealed, "first tap opened")
        try require(f.session.timelineTap(captured: animation, current: animation) == .open, "second tap did not open")
        try require(f.session.permit(for: other)?.allowsPixels == false, "album member leaked")

        // The actual transition object must reject both delayed use and capture before validation.
        let sourceView = MediaConcealmentView(message: other)
        sourceView.frame = CGRect(x: 10, y: 10, width: 80, height: 80)
        sourceView.isHidden = true
        window.addSubview(sourceView)
        defer { sourceView.removeFromSuperview() }
        var captures = 0
        let target = MediaGalleryTransitionTarget(
            messageID: animation.id,
            sourceView: sourceView,
            snapshotFactory: { captures += 1
            return UIView(frame: sourceView.bounds)
            },
            validation: { permit?.isCurrent == true },
        )
        try require(target?.snapshotView != nil && captures == 1, "valid transition capture")
        let edited = message(file: f.file, revision: 1)
        f.session.reconcile([edited])
        try require(permit?.allowsPixels == false && target?.snapshotView == nil, "stale snapshot")
        let rejected = MediaGalleryTransitionTarget(
            messageID: animation.id,
            sourceView: sourceView,
            snapshotFactory: { captures += 1
            return UIView()
            },
            validation: { permit?.isCurrent == true },
        )
        try require(rejected == nil && captures == 1, "invalid snapshot factory ran")
        try require(f.session.timelineTap(captured: animation, current: edited) == .rejected, "stale tap")
        try require(f.session.reveal(edited), "current revision could not reveal")
        f.session.reconcile([animation], replacingExisting: false)
        try require(
            f.session.permit(for: animation) == nil && f.session.permit(for: edited)?.allowsPixels == true,
            "restoration rolled revision backward",
        )

        for kind in [MediaRevealSession.Key.Kind.photo, .video, .animation] {
            let concealed = message(file: f.file, id: 9010, kind: kind)
            let secret = message(file: f.file, id: 9011, secret: true, kind: kind)
            f.session.reconcile([concealed, secret])
            try require(!MediaRevealPermit.allows(concealed, permit: f.session.permit(for: concealed)), "kind leaked")
            try require(
                f.session.reveal(concealed) && f.session.permit(for: concealed)?.allowsPixels == true,
                "kind reveal",
            )
            try require(
                !f.session.reveal(secret) && f.session.timelineTap(captured: secret, current: secret) == .rejected,
                "secret reveal",
            )
        }
        let changedFile = File(
            expectedSize: f.file.expectedSize,
            id: f.file.id + 1,
            local: f.file.local,
            remote: f.file.remote,
            size: f.file.size,
        )
        let replacement = message(file: changedFile, revision: 1)
        f.session.reconcile([replacement])
        try require(
            f.session.permit(for: edited) == nil && f.session.permit(for: replacement)?.allowsPixels == false,
            "same revision different file",
        )
        _ = f.session.reveal(replacement)
        let currentPermit = f.session.permit(for: replacement)
        let cachedFile = File(
            expectedSize: changedFile.expectedSize,
            id: changedFile.id,
            local: .init(
                canBeDeleted: true,
                canBeDownloaded: true,
                downloadOffset: 0,
                downloadedPrefixSize: changedFile.size,
                downloadedSize: changedFile.size,
                isDownloadingActive: false,
                isDownloadingCompleted: true,
                path: url.path,
            ),
            remote: changedFile.remote,
            size: changedFile.size,
        )
        f.session.reconcile([message(file: cachedFile, revision: 1)])
        try require(currentPermit?.allowsPixels == true, "download progress reset grant")
        f.identity.source = TdUpdateSource(accountID: UUID(), clientID: f.identity.source.clientID + 1)
        try require(currentPermit?.allowsPixels == false && !f.session.reveal(replacement), "account/client reuse")
        let foreign = try await fixture(url: url)
        foreign.session.reconcile([replacement])
        try require(foreign.session.permit(for: replacement)?.allowsPixels == false, "grant crossed route")
        try require(
            !MediaRevealPermit.allows(message(file: f.file, spoiler: false), permit: nil, requiresPermit: true),
            "missing required source capability",
        )
    }

    private static func verifyGallery(url: URL) async throws {
        let f = try await fixture(url: url)
        let first = message(file: f.file)
        let second = message(file: f.file, id: 9002)
        var accepted = [first, second].map { CustomMessage(message: $0, properties: .default) }
        let acceptedChanges = PassthroughSubject<Void, Never>()
        let observation = f.session.observeAcceptedMessages(
            changes: acceptedChanges.eraseToAnyPublisher(),
            current: { accepted },
        )
        defer { observation.cancel() }
        let gallery = MediaGalleryViewController(
            messages: [first, second],
            selection: first.id,
            playbackContext: f.context,
            mediaRevealSession: f.session,
        )
        defer { gallery.debugRevealOwner(id: first.id)?.invalidate()
        gallery.debugRevealOwner(id: second.id)?.invalidate()
        }
        try require(
            f.session.permit(for: first)?.allowsPixels == true
                    && f.session.permit(for: second)?.allowsPixels == false,
            "gallery granted neighbors",
        )
        let neighbor = gallery.debugRevealCell(at: 1)
        try require(
            neighbor.contentView.subviews.first is MediaConcealmentView
                    && gallery.debugRevealOwner(id: second.id) == nil,
            "adjacent raw owner",
        )
        try await require(f.backend.downloadCalls.isEmpty, "adjacent eager download")
        gallery.loadViewIfNeeded()
        let central = gallery.debugRevealCell(at: 0)
        defer { central.prepareForReuse()
        neighbor.prepareForReuse()
        }
        guard let owner = gallery.debugRevealOwner(id: first.id) else { throw Failure(description: "central owner") }
        try await wait { owner.debugAnimationTime > 0.1 }
        try require(owner.debugAnimationItem != nil && owner.debugAnimationMuted, "revealed native playback")
        let retainedSession = gallery.debugRevealRestorationSession
        try require(retainedSession === f.session, "PiP snapshot lost session")
        let restored = MediaGalleryViewController(
            messages: [first, second],
            selection: first.id,
            playbackContext: f.context,
            mediaRevealSession: retainedSession,
            transferredPlaybackOwner: owner,
        )
        try require(
            restored.debugRevealOwner(id: first.id) === owner
                    && f.session.permit(for: second)?.allowsPixels == false,
            "restoration granted neighbor/replaced owner",
        )
        gallery.debugRevealSelection(at: 1)
        try require(f.session.permit(for: second)?.allowsPixels == true, "central paging did not reveal")
        let revised = message(file: f.file, id: 9002, revision: 1)
        gallery.updateMessages([first, revised])
        let replacementCell = gallery.debugRevealCell(at: 1)
        defer { replacementCell.prepareForReuse() }
        try require(
            replacementCell.contentView.subviews.first is MediaConcealmentView
                    && gallery.debugRevealOwner(id: second.id) == nil,
            "same-ID revision stayed visible",
        )
        let editedFirst = message(file: f.file, revision: 1)
        let latestSecond = message(file: f.file, id: 9002, revision: 2)
        var revisionEvents = 0
        let events = f.session.revisionsChanged.sink { _ in revisionEvents += 1 }
        defer { events.cancel() }
        accepted = [editedFirst, latestSecond].map { CustomMessage(message: $0, properties: .default) }
        acceptedChanges.send()
        try require(
            owner.debugAnimationInvalidated && !owner.matches(message: first)
                    && owner.makeTransitionSnapshot(contentMode: .scaleAspectFill) == nil,
            "old owner survived revision",
        )
        try require(
            revisionEvents == 1 && gallery.debugRevealMessage(at: 1) == latestSecond,
            "accepted gallery revision loop/stale payload",
        )
        let latestCell = gallery.debugRevealCell(at: 1)
        defer { latestCell.prepareForReuse() }
        guard let cover = latestCell.contentView.subviews.first as? MediaConcealmentView else {
            throw Failure(description: "accepted revision not covered")
        }
        try require(
            cover.accessibilityActivate() && f.session.permit(for: latestSecond)?.allowsPixels == true,
            "accepted current revision cannot reveal",
        )
    }

    private static func verifyPendingRevocation(url: URL) async throws {
        let f = try await fixture(url: url, autoFulfill: false)
        let initial = message(file: f.file)
        f.session.reconcile([initial])
        _ = f.session.reveal(initial)
        guard let owner = GalleryVideoPlaybackOwner(
            message: initial,
            tdlib: .shared,
            playbackContext: f.context,
            revealPermit: f.session.permit(for: initial),
        ) else {
            throw Failure(description: "pending owner")
        }
        defer { owner.invalidate() }
        let container = UIView()
        guard let token = owner.attach(to: container, context: .inline)
            else { throw Failure(description: "pending attach") }
        owner.setPlaybackVisible(true, attachment: token)
        try await wait { await !f.backend.downloadCalls.isEmpty }
        f.session.reconcile([message(file: f.file, revision: 2)])
        try require(owner.debugAnimationInvalidated, "pending owner not invalidated")
        try await wait { await f.backend.cancelCount > 0 }
    }

    private static func message(
        file: File,
        id: Int64 = 9001,
        revision: Int = 0,
        secret: Bool = false,
        spoiler: Bool = true,
        kind: MediaRevealSession.Key.Kind = .animation,
    ) -> Message {
        let caption = FormattedText(entities: [], text: "")
        let content: MessageContent =
 switch kind {
        case .photo:
            .messagePhoto(.init(
                photo: .init(hasStickers: false, minithumbnail: nil, sizes: []),
                video: nil,
                caption: caption,
                showCaptionAboveMedia: false,
                hasSpoiler: spoiler,
                isSecret: secret,
            ))
        case .video:
            .messageVideo(.init(
                video: .init(
                    duration: 1,
                    width: 240,
                    height: 240,
                    fileName: "source.mp4",
                    mimeType: "video/mp4",
                    hasStickers: false,
                    supportsStreaming: false,
                    minithumbnail: nil,
                    thumbnail: nil,
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
            .messageAnimation(.init(
                animation: .init(
                    duration: 1,
                    width: 240,
                    height: 240,
                    fileName: "source.mp4",
                    mimeType: "video/mp4",
                    hasStickers: false,
                    minithumbnail: nil,
                    thumbnail: nil,
                    animation: file,
                ),
                caption: caption,
                showCaptionAboveMedia: false,
                hasSpoiler: spoiler,
                isSecret: secret,
            ))
        case .voiceNote:
            .messageVoiceNote(.init(
                voiceNote: .init(
                    duration: 1,
                    waveform: Data(),
                    mimeType: "audio/ogg",
                    speechRecognitionResult: nil,
                    voice: file,
                ),
                caption: caption,
                isListened: false,
            ))
        }
        return Message(
            id: id,
            senderId: .messageSenderUser(.init(userId: 1)),
            receiverId: nil,
            chatId: 0,
            sendingState: nil,
            schedulingState: nil,
            isOutgoing: true,
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
            editDate: revision,
            forwardInfo: nil,
            importInfo: nil,
            interactionInfo: nil,
            unreadReactions: [],
            factCheck: nil,
            suggestedPostInfo: nil,
            replyTo: nil,
            topicId: nil,
            selfDestructType: nil,
            selfDestructIn: 0,
            autoDeleteIn: 0,
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

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }

    private static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while await !condition() {
            try require(ContinuousClock.now < deadline, "native playback/cancellation timeout")
            try await Task<Never, Never>.sleep(for: .milliseconds(20))
        }
    }
}
#endif
