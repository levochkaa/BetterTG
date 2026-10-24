// VideoNoteHoldProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum VideoNoteHoldProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Clock
    {
        var now: TimeInterval = 100

        private var waiters = [(TimeInterval, CheckedContinuation<Void, Never>)]()

        func sleep(_ duration: TimeInterval) async {
            guard duration > 0 else { return }
            await withCheckedContinuation { waiters.append((now + duration, $0)) }
        }

        func advance(_ time: TimeInterval) {
            now = time
            let ready = waiters.filter { $0.0 <= time }
            waiters.removeAll { $0.0 <= time }
            ready.forEach { $0.1.resume() }
        }

        func finish() { let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.1.resume() }
        }
    }

        @MainActor private final class Fixture
    {
        let source = TdUpdateSource(accountID: UUID(), clientID: 17)
        lazy var currentSource = source
        let center = NotificationCenter()
        let changes = PassthroughSubject<TdUpdateSource, Never>()
            let lifecycle = PassthroughSubject<Foundation.Notification, Never>()
        let clock = Clock()
        let url: URL
        var needsDownload = false
            var secret = true
            var minithumbnail: Minithumbnail?
        var outgoing = false
        var type: MessageSelfDestructType? = .messageSelfDestructTypeTimer(.init(selfDestructTime: 5))
        var postTTL = 4.0
        var opened = false
        var openCalls = 0
        var downloadCalls = 0
        var cancelCalls = 0
        var messageCalls = 0
        var takeovers = 0
        var suspendedMessageCall: Int?
        var suspendDownload = false
        var openReplies = [CheckedContinuation<Void, Swift.Error>?]()
        var messageReply: CheckedContinuation<Void, Never>?
        var downloadReply: CheckedContinuation<Void, Never>?

        var file: File {
            VideoNoteHoldProbe.file(url: url, complete: !needsDownload)
        }

        var value: Message {
            VideoNoteHoldProbe.message(
                file: file,
                secret: secret,
                type: type,
                remaining: opened ? postTTL : 0,
                outgoing: outgoing,
                minithumbnail: minithumbnail,
            )
        }

        var backend: VideoNotePlaybackBackend {
            VideoNotePlaybackBackend(
                source: source, center: center, clientChanges: changes.eraseToAnyPublisher(),
                lifecycle: lifecycle.eraseToAnyPublisher(), isCurrent: { [self] in currentSource == source },
                download: { [self] _, _ in
                    downloadCalls += 1
                    if suspendDownload { await withCheckedContinuation { downloadReply = $0 } }
                    return VideoNoteHoldProbe.file(url: url, complete: true)
                },
                cancelDownload: { [self] _ in cancelCalls += 1 },
                message: { [self] _, _ in
                    messageCalls += 1
                    let captured = value
                    if suspendedMessageCall == messageCalls {
                        await withCheckedContinuation { messageReply = $0 }
                    }
                    return captured
                },
                open: { [self] _, _ in
                    openCalls += 1
                    try await withCheckedThrowingContinuation { openReplies.append($0) }
                    opened = true
                },
                now: { [clock] in clock.now }, sleep: { [clock] in await clock.sleep($0) },
                takePlayback: { [self] in takeovers += 1 },
            )
        }

        init(url: URL) { self.url = url }

        func acknowledge(_ index: Int, failure: Bool = false) {
            guard openReplies.indices.contains(index), let reply = openReplies[index] else { return }
            openReplies[index] = nil
            if failure { reply.resume(throwing: Failure(description: "isolated open failure")) }
            else { reply.resume() }
        }

        func finish() {
            openReplies.indices.forEach { acknowledge($0) }
            messageReply?.resume()
            messageReply = nil
            downloadReply?.resume()
            downloadReply = nil
            clock.finish()
        }

        func makeView(in parent: UIView, captureState: UISceneCaptureState? = nil) -> VideoNotePlaybackView {
            let view = VideoNotePlaybackView(frame: CGRect(x: 10, y: 140, width: 220, height: 220))
            if let captureState { view.traitOverrides.sceneCaptureState = captureState }
            view.configure(message: value, backend: backend)
            parent.addSubview(view)
            view.setPlaybackVisible(true)
            view.layoutIfNeeded()
            return view
        }
    }

    private static var directorylessURL: URL { URL(filePath: "/nonexistent/probe-only.mp4") }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-media-probe-video-note-hold") else { return }
        Task {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("video-note-hold-\(UUID())")
            let result: String
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let url = directory.appendingPathComponent("private.mp4")
                _ = try await VideoNoteAssetWriter.makeDebugSegment(outputURL: url, duration: 1, frameSeed: 291)
                try await verify(window: window, url: url)
                try await verifyCaptureState(window: window, url: url)
                    result = "Video note hold probe passed: actual-UIKit/native-player/private-MP4=true; "
                        + "nil/stale-backend-no-thumbnail=true; "
                    + "unsupported-immediate/unknown/outgoing=no-IO; ack-before-player/pixels=true; "
                    + "release-before-dispatch/no-open; late-ACK/error/new-hold/reuse=fenced; "
                    + "source-collision/client-change/content/edit/delete/offscreen/window/inactive=revoke; "
                    + "fresh-positive-TTL/conservative-clock/no-extension=true; "
                    + "deinit/suspended-download/ordinary-tap=true; real-secret-open/account-writes=0; "
                    + "capture-trait-inheritance/admission/pending-IO/ACK/pixels/rehold/ordinary=true; "
                    + "server-semantics/touch-hardware/recording-hardware/screenshot-prevention=unverified"
            } catch {
                result = "Video note hold probe failed: \(error)"
            }
            log(result)
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("video-note-hold-probe.txt"),
                    options: .atomic,
                )
            }
        }
    }

        private static func verify(window: UIWindow, url: URL) async throws
    {
            let thumbnailImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            guard let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.8) else {
                throw Failure(description: "private thumbnail fixture")
            }
            for stale in [false, true] {
                let f = Fixture(url: url)
                f.secret = false
                f.type = nil
                f.minithumbnail = Minithumbnail(data: thumbnailData, height: 2, width: 2)
                if stale { f.currentSource = TdUpdateSource(accountID: f.source.accountID, clientID: 18) }
                let v = VideoNotePlaybackView(frame: CGRect(x: 10, y: 140, width: 220, height: 220))
                defer { v.prepareForReuse()
                v.removeFromSuperview()
                f.finish()
                }
                v.configure(message: f.value, backend: stale ? f.backend : nil)
                window.addSubview(v)
                v.setPlaybackVisible(true)
                await drain()
                try require(
                    !v.probeSnapshot.thumbnail && !v.probeSnapshot.playerItem
                    && f.downloadCalls == 0 && f.messageCalls == 0,
                    "rejected backend admitted pixels/download",
                )
            }
            for kind in 0..<4
        {
            let f = Fixture(url: url)
            if kind == 0 { f.type = .messageSelfDestructTypeImmediately }
            if kind == 1 { f.type = nil }
            if kind == 2 { f.type = .messageSelfDestructTypeTimer(.init(selfDestructTime: 0)) }
            if kind == 3 { f.outgoing = true }
            let v = f.makeView(in: window)
            defer { v.prepareForReuse()
            v.removeFromSuperview()
            f.finish()
            }
            v.beginHoldForProbe()
            await drain()
            try require(
                f.messageCalls == 0 && f.downloadCalls == 0 && f.openCalls == 0
                && !v.probeSnapshot.playerItem && !v.probeSnapshot.thumbnail,
                "unsupported \(kind) performed IO",
            )
        }
        for oldFails in [false, true] {
            let f = Fixture(url: url)
            let v = f.makeView(in: window)
            defer { v.prepareForReuse()
            v.removeFromSuperview()
            f.finish()
            }
            v.beginHoldForProbe()
            v.releaseHoldForProbe()
            await drain()
            try require(f.messageCalls == 0 && f.openCalls == 0, "released before dispatch")
            v.beginHoldForProbe()
            try await until("first open") { f.openCalls == 1 }
            try require(!v.probeSnapshot.playerItem && !v.probeSnapshot.visiblePixels, "pixels before ACK")
            v.releaseHoldForProbe()
            v.beginHoldForProbe()
            try await until("second open") { f.openCalls == 2 }
            f.acknowledge(0, failure: oldFails)
            await drain()
            try require(v.probeSnapshot.held && !v.probeSnapshot.playerItem, "old failure retired new hold")
            f.acknowledge(1)
            try await until("native reveal") { v.probeSnapshot.visiblePixels }
            try require(
                v.probeSnapshot.acknowledged && v.probeSnapshot.playerItem
                && v.probeSnapshot.deadline == 104,
                "ACK/deadline",
            )
            v.releaseHoldForProbe()
            try require(!v.probeSnapshot.playerItem && !v.probeSnapshot.visiblePixels, "release retained player")
            f.clock.advance(101)
            v.beginHoldForProbe()
            try await until("third open") { f.openCalls == 3 }
            f.acknowledge(2)
            try await until("repeat reveal") { v.probeSnapshot.visiblePixels }
            try require(v.probeSnapshot.deadline == 104, "repeated hold extended deadline")
            f.clock.advance(104)
            try await until("deadline revoke") { !v.probeSnapshot.playerItem && !v.probeSnapshot.held }
        }
        for pending in [true, false] {
            for action in [
                "release",
                "offscreen",
                "window",
                "inactive",
                "scene",
                "source",
                "content",
                "edit",
                "delete",
                "reuse",
                "file",
            ] {
                let f = Fixture(url: url)
                let v = f.makeView(in: window)
                defer { v.prepareForReuse()
                v.removeFromSuperview()
                f.finish()
                }
                v.beginHoldForProbe()
                try await until("\(action) open") { f.openCalls == 1 }
                if !pending {
                    f.acknowledge(0)
                    try await until("\(action) reveal") { v.probeSnapshot.visiblePixels }
                }
                let foreign = TdUpdateSource(accountID: UUID(), clientID: 18)
                f.center.postTdUpdate(
                    name: TdNotification<UpdateDeleteMessages>.updateDeleteMessages.name,
                    object: UpdateDeleteMessages(chatId: 8, fromCache: false, isPermanent: true, messageIds: [9]),
                    source: foreign,
                )
                try require(v.probeSnapshot.held, "foreign numeric IDs revoked hold")
                switch action {
                case "release": v.releaseHoldForProbe()
                case "offscreen": v.setPlaybackVisible(false)
                case "window": v.removeFromSuperview()
                case "inactive": f.lifecycle.send(Notification(name: UIApplication.willResignActiveNotification))
                case "scene": f.lifecycle.send(Notification(name: UIScene.willDeactivateNotification))
                case "source":
                    f.currentSource = TdUpdateSource(accountID: f.source.accountID, clientID: 19)
                    f.changes.send(f.currentSource)
                case "content": f.center.postTdUpdate(
                    name: TdNotification<UpdateMessageContent>.updateMessageContent.name,
                    object: UpdateMessageContent(chatId: 8, messageId: 9, newContent: .messageExpiredVideoNote),
                    source: f.source,
                )
                case "edit": f.center.postTdUpdate(
                    name: TdNotification<UpdateMessageEdited>.updateMessageEdited.name,
                    object: UpdateMessageEdited(chatId: 8, editDate: 2, messageId: 9, replyMarkup: nil),
                    source: f.source,
                )
                case "delete": f.center.postTdUpdate(
                    name: TdNotification<UpdateDeleteMessages>.updateDeleteMessages.name,
                    object: UpdateDeleteMessages(chatId: 8, fromCache: false, isPermanent: true, messageIds: [9]),
                    source: f.source,
                )
                case "reuse":
                    v.prepareForReuse()
                    f.type = .messageSelfDestructTypeImmediately
                    v.configure(message: f.value, backend: f.backend)
                    v.setPlaybackVisible(true)
                case "file":
                    if pending {
                        v.releaseHoldForProbe()
                    } else {
                        f.center.postTdUpdate(
                            name: TdNotification<UpdateFile>.updateFile.name,
                            object: UpdateFile(file: file(url: url, complete: false)),
                            source: f.source,
                        )
                    }
                default: break
                }
                try require(
                    !v.probeSnapshot.visiblePixels && !v.probeSnapshot.playerItem,
                    "\(action) did not revoke synchronously",
                )
                if pending { f.acknowledge(0) }
                await drain()
                try require(!v.probeSnapshot.playerItem && !v.probeSnapshot.held, "\(action) late ACK revealed")
            }
        }
        for remaining in [0.0, Double.nan, Double.infinity] {
            let f = Fixture(url: url)
            let v = f.makeView(in: window)
            defer { v.prepareForReuse()
            v.removeFromSuperview()
            f.finish()
            }
            f.postTTL = remaining
            v.beginHoldForProbe()
            try await until("invalid TTL open") { f.openCalls == 1 }
            f.acknowledge(0)
            try await until("invalid TTL denied") { !v.probeSnapshot.held }
            try require(!v.probeSnapshot.playerItem, "invalid TTL revealed")
        }
        do {
            let f = Fixture(url: url)
            let v = f.makeView(in: window)
            defer { v.prepareForReuse()
            v.removeFromSuperview()
            f.finish()
            }
            f.suspendedMessageCall = 3
            v.beginHoldForProbe()
            try await until("delayed TTL open") { f.openCalls == 1 }
            f.acknowledge(0)
            try await until("delayed TTL requested") { f.messageReply != nil }
            f.clock.advance(105)
            f.messageReply?.resume()
            f.messageReply = nil
            try await until("elapsed TTL rejected") { !v.probeSnapshot.held }
            try require(!v.probeSnapshot.playerItem, "metadata RTT extended TTL")
        }
        do {
            let f = Fixture(url: url)
            f.needsDownload = true
            f.suspendDownload = true
            let v = f.makeView(in: window)
            defer { v.prepareForReuse()
            v.removeFromSuperview()
            f.finish()
            }
            v.beginHoldForProbe()
            try await until("download entered") { f.downloadReply != nil }
            v.releaseHoldForProbe()
            f.downloadReply?.resume()
            f.downloadReply = nil
            await drain()
            try require(
                f.openCalls == 0 && f.cancelCalls == 1 && !v.probeSnapshot.playerItem,
                "released download consumed content",
            )
        }
        do {
            let f = Fixture(url: url)
            defer { f.finish() }
            var v: VideoNotePlaybackView? = f.makeView(in: window)
                weak let weakView = v
            v?.beginHoldForProbe()
            try await until("deinit open") { f.openCalls == 1 }
            v?.removeFromSuperview()
            v = nil
            // UIKit may release detached views after its queued layout/animation work.
            // Keep the open RPC suspended while checking eventual view teardown.
            await drain()
            try await until("pending open released before ACK") { [weak weakView] in weakView == nil }
            f.acknowledge(0)
            await drain()
        }
        do {
            let f = Fixture(url: url)
            f.secret = false
            f.type = nil
            let v = f.makeView(in: window)
            defer { v.prepareForReuse()
            v.removeFromSuperview()
            f.finish()
            }
            try await until("ordinary player") { v.probeSnapshot.playerItem }
            v.tapForProbe()
            try require(v.probeSnapshot.playbackRequested && f.openCalls == 0, "ordinary play changed")
            try await until("ordinary pixels") { v.probeSnapshot.visiblePixels }
            v.tapForProbe()
            try require(!v.probeSnapshot.playbackRequested, "ordinary pause changed")
            f.center.postTdUpdate(
                name: TdNotification<UpdateFile>.updateFile.name,
                object: UpdateFile(file: file(url: directorylessURL, complete: true)),
                source: TdUpdateSource(accountID: UUID(), clientID: 99),
            )
            try require(v.probeSnapshot.path == url.path, "foreign file changed ordinary player")
        }
    }

    private static func verifyCaptureState(window: UIWindow, url: URL) async throws {
        do {
            let container = UIView(frame: window.bounds)
            container.traitOverrides.sceneCaptureState = .active
            window.addSubview(container)
            let f = Fixture(url: url)
            let v = f.makeView(in: container)
            defer {
                v.prepareForReuse()
                container.removeFromSuperview()
                f.finish()
            }
            container.updateTraitsIfNeeded()
            try require(v.traitCollection.sceneCaptureState == .active, "capture trait did not inherit")
            v.beginHoldForProbe()
            await drain()
            try require(f.messageCalls == 0 && !v.probeSnapshot.held, "inherited capture admitted IO")
            setCaptureState(.inactive, on: container)
            try require(v.traitCollection.sceneCaptureState == .inactive, "capture stop did not inherit")
            await drain()
            try require(f.messageCalls == 0 && !v.probeSnapshot.held, "inherited capture stop auto-opened")
            v.beginHoldForProbe()
            try await until("inherited inactive hold") { f.openCalls == 1 }
            f.acknowledge(0)
            try await until("inherited inactive native pixels") { v.probeSnapshot.visiblePixels }
            setCaptureState(.active, on: container)
            try require(
                !v.probeSnapshot.held && !v.probeSnapshot.playerItem && !v.probeSnapshot.visiblePixels,
                "inherited capture did not synchronously revoke",
            )
            setCaptureState(.inactive, on: container)
            await drain()
            try require(
                f.openCalls == 1 && !v.probeSnapshot.held && !v.probeSnapshot.playerItem,
                "inherited capture stop resumed playback",
            )
        }

        for captureState in [UISceneCaptureState.active, .unspecified] {
            let f = Fixture(url: url)
            let v = f.makeView(in: window, captureState: captureState)
            defer {
                v.prepareForReuse()
                v.removeFromSuperview()
                f.finish()
            }
            v.beginHoldForProbe()
            await drain()
            try require(
                f.messageCalls == 0 && f.downloadCalls == 0 && f.openCalls == 0
                && !v.probeSnapshot.held && !v.probeSnapshot.playerItem && !v.probeSnapshot.thumbnail,
                "initial capture state admitted hold or IO",
            )
            setCaptureState(.inactive, on: v)
            await drain()
            try require(f.messageCalls == 0 && !v.probeSnapshot.held, "capture stop resumed old touch")
            v.beginHoldForProbe()
            try await until("new hold after initial capture") { f.openCalls == 1 }
        }

        for stage in ["dispatch", "metadata", "download", "pre-open", "ACK", "post-ACK", "pixels"] {
            let f = Fixture(url: url)
            if stage == "metadata" { f.suspendedMessageCall = 1 }
            if stage == "pre-open" { f.suspendedMessageCall = 2 }
            if stage == "post-ACK" { f.suspendedMessageCall = 3 }
            if stage == "download" {
                f.needsDownload = true
                f.suspendDownload = true
            }
            let v = f.makeView(in: window, captureState: .inactive)
            defer {
                v.prepareForReuse()
                v.removeFromSuperview()
                f.finish()
            }
            v.beginHoldForProbe()
            if stage == "metadata" || stage == "pre-open" {
                try await until("capture \(stage) suspended") { f.messageReply != nil }
            } else if stage == "download" {
                try await until("capture download suspended") { f.downloadReply != nil }
            } else if stage != "dispatch" {
                try await until("capture \(stage) open") { f.openCalls == 1 }
                if stage != "ACK" { f.acknowledge(0) }
                if stage == "post-ACK" {
                    try await until("capture post-ACK suspended") { f.messageReply != nil }
                } else if stage == "pixels" {
                    try await until("capture native pixels") { v.probeSnapshot.visiblePixels }
                }
            }
            let priorDeadline = v.probeSnapshot.deadline
            let priorReads = f.messageCalls
            let priorOpens = f.openCalls
            setCaptureState(.active, on: v)
            try require(
                !v.probeSnapshot.held && !v.probeSnapshot.visiblePixels
                && !v.probeSnapshot.playerItem && !v.probeSnapshot.playbackRequested,
                "capture \(stage) did not synchronously retire hold/player/pixels",
            )
            f.messageReply?.resume()
            f.messageReply = nil
            f.downloadReply?.resume()
            f.downloadReply = nil
            f.acknowledge(0)
            await drain()
            try require(
                f.messageCalls == priorReads && f.openCalls == priorOpens
                && !v.probeSnapshot.held && !v.probeSnapshot.playerItem,
                "capture \(stage) accepted delayed result",
            )
            if stage == "download" { try require(f.cancelCalls == 1, "capture kept owned download") }
            setCaptureState(.inactive, on: v)
            await drain()
            try require(
                f.messageCalls == priorReads && f.openCalls == priorOpens
                && !v.probeSnapshot.playerItem,
                "capture \(stage) stop auto-resumed",
            )
            if stage == "pixels" {
                f.clock.advance(101)
                v.beginHoldForProbe()
                try await until("fresh hold after capture") { f.openCalls == priorOpens + 1 }
                f.acknowledge(priorOpens)
                try await until("fresh native reveal after capture") { v.probeSnapshot.visiblePixels }
                try require(v.probeSnapshot.deadline == priorDeadline, "capture extended expiry")
            }
        }

        do {
            let f = Fixture(url: url)
            let v = f.makeView(in: window)
            defer {
                v.prepareForReuse()
                f.finish()
            }
            v.removeFromSuperview()
            v.setPlaybackVisible(true)
            v.beginHoldForProbe()
            await drain()
            try require(f.messageCalls == 0 && !v.probeSnapshot.held, "detached hold admitted IO")
        }

        let f = Fixture(url: url)
        f.secret = false
        f.type = nil
        let v = f.makeView(in: window, captureState: .active)
        defer {
            v.prepareForReuse()
            v.removeFromSuperview()
            f.finish()
        }
        try await until("ordinary captured player") { v.probeSnapshot.playerItem }
        v.tapForProbe()
        try await until("ordinary captured pixels") { v.probeSnapshot.visiblePixels }
        setCaptureState(.inactive, on: v)
        setCaptureState(.active, on: v)
        try require(
            v.probeSnapshot.playerItem && v.probeSnapshot.playbackRequested
            && v.probeSnapshot.visiblePixels && f.openCalls == 0,
            "secret capture policy altered ordinary note",
        )
    }

    private static func setCaptureState(_ state: UISceneCaptureState, on view: UIView) {
        view.traitOverrides.sceneCaptureState = state
        view.updateTraitsIfNeeded()
    }

    private static func file(url: URL, complete: Bool) -> File {
        File(
            expectedSize: 1,
            id: 5,
            local: .init(
                canBeDeleted: true,
                canBeDownloaded: true,
                downloadOffset: 0,
                downloadedPrefixSize: complete ? 1 : 0,
                downloadedSize: complete ? 1 : 0,
                isDownloadingActive: false,
                isDownloadingCompleted: complete,
                path: complete ? url.path : "",
            ),
            remote: .init(id: "", isUploadingActive: false, isUploadingCompleted: true, uniqueId: "", uploadedSize: 1),
            size: 1,
        )
    }

    private static func message(
        file: File,
        secret: Bool,
        type: MessageSelfDestructType?,
        remaining: Double,
        outgoing: Bool,
        minithumbnail: Minithumbnail?,
    ) -> Message {
        Message(
            id: 9,
            senderId: .messageSenderUser(.init(userId: 1)),
            receiverId: nil,
            chatId: 8,
            sendingState: nil,
            schedulingState: nil,
            isOutgoing: outgoing,
            isPinned: false,
            isFromOffline: false,
            canBeSaved: !secret,
            hasTimestampedMedia: false,
            isChannelPost: false,
            isPaidStarSuggestedPost: false,
            isPaidGramSuggestedPost: false,
            containsUnreadMention: false,
            containsUnreadPollVotes: false,
            date: 1,
            editDate: 0,
            forwardInfo: nil,
            importInfo: nil,
            interactionInfo: nil,
            unreadReactions: [],
            factCheck: nil,
            suggestedPostInfo: nil,
            replyTo: nil,
            topicId: nil,
            selfDestructType: type,
            selfDestructIn: remaining,
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
            content: .messageVideoNote(.init(
                videoNote: .init(
                    duration: 1,
                    waveform: Data(),
                    length: 220,
                    minithumbnail: minithumbnail,
                    thumbnail: nil,
                    speechRecognitionResult: nil,
                    video: file,
                ),
                isViewed: false,
                isSecret: secret,
            )),
            ephemeralContent: nil,
            replyMarkup: nil,
            ephemeralMessageId: 0,
            chatInstance: 0,
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }

    private static func drain() async {
        for _ in 0..<3 {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    private static func until(_ reason: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(description: "timeout: \(reason)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
#endif
