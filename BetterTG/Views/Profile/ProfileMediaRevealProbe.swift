// ProfileMediaRevealProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum ProfileMediaRevealProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }
    private final class Identity {
        var source = TdUpdateSource(accountID: UUID(), clientID: 311)
        let changes = PassthroughSubject<TdUpdateSource, Never>()
    }

    private struct Fixture {
        let identity: Identity
        let context: MediaGalleryPlaybackContext
        let session: MediaRevealSession
        let backend: TDLibVODProbeBackend
        let file: File
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-media-reveal") else { return }
        Task {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-media-reveal-\(UUID())")
            let result: String
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                guard let png = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
                    .image(actions: { renderer in
                    UIColor.systemRed.setFill()
                    renderer.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
                })
.pngData() else { throw Failure(description: "PNG fixture") }
                let url = root.appendingPathComponent("private.png")
                try png.write(to: url)
                try await verifyCells(window: window, url: url, png: png)
                result = "Profile media reveal probe passed: actual-grid/photo/video/secret=true; "
                    + "pre-reveal-loads=0; covered-AX=true; cover-only-snapshot=true; first-tap-gallery=true; "
                    + "selected-and-paged-grants-only=true; return-refresh=true; accepted-revision-reconceals=true; "
                    + "stale-snapshot/reuse/source-denied=true; ordinary-caption-spoiler-AX=true; "
                    + "thumbnail-transport=private-PNG-injection; actual-TDLib/profile-navigation/VoiceOver=unverified"
            } catch {
                result = "Profile media reveal probe failed: \(error)"
            }
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("profile-media-reveal-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func fixture(url: URL, accountID: UUID? = nil, clientID: Int32 = 311) async throws -> Fixture {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        else { throw Failure(description: "fixture size") }
        let backend = TDLibVODProbeBackend(
            fileURL: url, fileSize: size.int64Value, network: TDLibVODProbeNetwork(available: false),
        )
        let identity = Identity()
        identity.source = TdUpdateSource(accountID: accountID ?? UUID(), clientID: clientID)
        let source = identity.source
        let context = MediaGalleryPlaybackContext(
            probeLocation: ChatLocation(accountID: source.accountID, chatID: 0, clientID: source.clientID, topic: nil),
            vodRanges: TDLibVODRangeCoordinator(accountID: source.accountID.uuidString, client: backend.client),
            clientChanges: identity.changes.eraseToAnyPublisher(),
            currentClientMatches: { identity.source == source },
        )
        return await Fixture(
            identity: identity,
            context: context,
            session: MediaRevealSession(context: context),
            backend: backend,
            file: backend.file(expectedSize: size.int64Value),
        )
    }

    private static func verifyCells(window: UIWindow, url: URL, png: Data) async throws {
        let f = try await fixture(url: url)
        let messages = (1...3).map { message(file: f.file, id: Int64($0), png: png) }
        f.session.reconcile(messages)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 150))
        host.isHidden = true
        window.addSubview(host)
        defer { host.removeFromSuperview() }
        var imageOrigin = thumbnailOrigin(for: f)
        var loads = [Int64]()
        let cells = messages.enumerated().map { index, message in
            let cell = SharedMediaGridCell(frame: CGRect(x: index * 120, y: 0, width: 110, height: 110))
            cell.debugThumbnailLoader = { loaded, imageView in
                loads.append(loaded.id)
                imageView.loadPlaceholder(data: png, origin: imageOrigin)
            }
            host.addSubview(cell)
            cell.configure(message: message, context: f.context, permit: f.session.permit(for: message))
            cell.layoutIfNeeded()
            return cell
        }
        for cell in cells {
            cell.pauseLoading()
            cell.resumeLoading()
            try require(
                cell.debugHasCover && !cell.debugHasRawImage && cell.accessibilityLabel == "Media spoiler",
                "raw concealed cell/AX",
            )
            try require(cell.contentView.subviews.compactMap { $0 as? MediaConcealmentView }.allSatisfy {
                !$0.isUserInteractionEnabled && !$0.isAccessibilityElement
            }, "cover intercepts first tap or duplicates AX")
        }
        try require(loads.isEmpty, "concealed cell loaded thumbnail/minithumbnail")
        host.layoutIfNeeded()
        let coveredSnapshot = cells[1].transitionTarget(for: 2, validation: { true })
        guard coveredSnapshot?.validatedSourceView is MediaConcealmentView,
              let coveredImage = (coveredSnapshot?.snapshotView as? UIImageView)?.image
        else { throw Failure(description: "covered source or rasterized snapshot absent") }
        try require(loads.isEmpty && !isFixtureRed(coveredImage), "source pixels entered covered transition")

        // Use the actual gallery initializer/selection, never a synthetic reveal policy.
        let gallery = MediaGalleryViewController(
            messages: messages, selection: 2, sourceLocation: f.context.location,
            playbackContext: f.context, mediaRevealSession: f.session,
        )
        gallery.loadViewIfNeeded()
        for cell in cells {
            cell.refreshRevealState()
        }
        try require(
            loads == [2] && cells[1].debugHasRawImage && cells[0].debugHasCover && cells[2].debugHasCover,
            "first gallery tap did not grant only selected member",
        )
        try require(coveredSnapshot?.snapshotView == nil, "old cover snapshot survived render replacement")
        let rawSnapshot = cells[1].transitionTarget(for: 2, validation: { true })
        guard rawSnapshot?.validatedSourceView is TDImageLoadingView,
              let revealedImage = (rawSnapshot?.snapshotView as? UIImageView)?.image
        else { throw Failure(description: "revealed source or rasterized snapshot absent") }
        try require(isFixtureRed(revealedImage), "revealed transition lost private fixture pixels")
        try require(
            cells[1].accessibilityLabel?.contains("hidden-caption") == false,
            "text spoiler caption leaked after media reveal",
        )
        gallery.debugRevealSelection(at: 2)
        for cell in cells {
            cell.refreshRevealState()
        }
        try require(
            loads == [2, 3] && cells[0].debugHasCover && cells[2].debugHasRawImage,
            "gallery paging/return overgranted",
        )

        let replacement = message(file: f.file, id: 2, revision: 1, png: png)
        f.session.reconcile([replacement])
        try require(
            cells[1].debugHasCover && !cells[1].debugHasRawImage && rawSnapshot?.snapshotView == nil,
            "accepted revision did not synchronously revoke grid/snapshot",
        )
        try require(gallery.debugRevealMessage(at: 1).editDate == 1, "gallery kept stale profile payload")
        cells[1].configure(message: replacement, context: f.context, permit: f.session.permit(for: replacement))
        cells[1].pauseLoading()
        cells[1].resumeLoading()
        try require(loads == [2, 3], "replacement loaded before a fresh grant")
        gallery.debugRevealSelection(at: 1)
        cells[1].refreshRevealState()
        try require(loads == [2, 3, 2] && cells[1].debugHasRawImage, "fresh accepted revision cannot reveal")
        let reusedSnapshot = cells[1].transitionTarget(for: 2, validation: { true })
        cells[1].prepareForReuse()
        cells[1].configure(message: messages[0], context: f.context, permit: f.session.permit(for: messages[0]))
        try require(
            reusedSnapshot?.snapshotView == nil && !cells[1].debugHasRawImage && cells[1].debugHasCover,
            "reuse retained grant or source pixels",
        )
        f.session.reconcile([message(file: f.file, id: 2, revision: 2, png: png)])
        try require(loads == [2, 3, 2] && cells[1].debugHasCover, "late old member callback affected reuse")

        let currentSnapshot = cells[2].transitionTarget(for: 3, validation: { true })
        f.identity.source = TdUpdateSource(accountID: UUID(), clientID: 312)
        f.identity.changes.send(f.identity.source)
        try require(currentSnapshot?.snapshotView == nil, "source switch left valid snapshot")
        try await wait { cells[2].debugHasCover }
        cells[2].pauseLoading()
        cells[2].resumeLoading()
        try require(!cells[2].debugHasRawImage && loads == [2, 3, 2], "old client cell resumed download")

        let other = try await fixture(url: url)
        imageOrigin = thumbnailOrigin(for: other)
        other.session.reconcile(messages)
        cells[2].configure(message: messages[2], context: other.context, permit: f.session.permit(for: messages[2]))
        try require(cells[2].debugHasCover && loads == [2, 3, 2], "foreign session capability admitted")
        cells[2].configure(message: messages[2], context: other.context, permit: other.session.permit(for: messages[2]))
        try require(cells[2].debugHasCover, "colliding account/message inherited reveal")

        // Same account, replacement client: grants cannot cross an epoch either.
        other.session.reveal(messages[2])
        cells[2].refreshRevealState()
        let epochPermit = other.session.permit(for: messages[2])
        cells[2].configure(message: messages[2], context: f.context, permit: epochPermit)
        try require(cells[2].debugHasCover && !cells[2].debugHasRawImage, "current foreign permit admitted")
        let epoch = try await fixture(url: url, accountID: other.identity.source.accountID, clientID: 313)
        imageOrigin = thumbnailOrigin(for: epoch)
        epoch.session.reconcile(messages)
        cells[2].configure(message: messages[2], context: epoch.context, permit: epochPermit)
        try require(cells[2].debugHasCover && !cells[2].debugHasRawImage, "replacement-client capability admitted")

        for video in [false, true] {
            let covered = message(file: epoch.file, id: video ? 11 : 10, video: video, png: png)
            let secret = message(file: epoch.file, id: video ? 13 : 12, video: video, secret: true, png: png)
            epoch.session.reconcile([covered, secret])
            let count = loads.count
            for message in [covered, secret] {
                cells[0].configure(message: message, context: epoch.context, permit: epoch.session.permit(for: message))
                cells[0].pauseLoading()
                cells[0].resumeLoading()
                try require(
                    cells[0].debugHasCover && !cells[0].debugHasRawImage && loads.count == count,
                    "photo/video minithumbnail bypassed cover",
                )
            }
            try require(
                !epoch.session.reveal(secret) && cells[0].accessibilityLabel == "Protected media",
                "secret admitted",
            )
        }
        let ordinary = message(file: epoch.file, id: 20, spoiler: false, png: png)
        epoch.session.reconcile([ordinary])
        cells[0].configure(message: ordinary, context: epoch.context, permit: epoch.session.permit(for: ordinary))
        try require(cells[0].debugHasRawImage && !cells[0].debugHasCover, "ordinary media regressed")
        try require(cells[0].accessibilityLabel?.contains("hidden-caption") == false, "ordinary text spoiler AX leaked")
        let firstDownloads = await f.backend.downloadCalls
        let otherDownloads = await other.backend.downloadCalls
        let epochDownloads = await epoch.backend.downloadCalls
        try require(
            firstDownloads.isEmpty && otherDownloads.isEmpty && epochDownloads.isEmpty,
            "probe unexpectedly started VOD transport",
        )
    }

    private static func thumbnailOrigin(for fixture: Fixture) -> TDImageOrigin {
        TDImageOrigin(
            source: fixture.identity.source, backend: .init(download: { _ in nil }, cancel: { _ in }),
            demand: AnimatedFileDemand(center: NotificationCenter()), currentSource: { fixture.identity.source },
            changes: fixture.identity.changes.eraseToAnyPublisher(),
        )
    }

    private static func message(
        file: File,
        id: Int64,
        revision: Int = 0,
        video: Bool = false,
        secret: Bool = false,
        spoiler: Bool = true,
        png: Data,
    ) -> Message {
        let caption = FormattedText(
            entities: [.init(length: 14, offset: 0, type: .textEntityTypeSpoiler)],
            text: "hidden-caption",
        )
        let mini = Minithumbnail(data: png, height: 24, width: 24)
        let content: MessageContent = video
            ? .messageVideo(.init(
                video: .init(
                    duration: 1,
                    width: 24,
                    height: 24,
                    fileName: "private.mp4",
                    mimeType: "video/mp4",
                    hasStickers: false,
                    supportsStreaming: false,
                    minithumbnail: mini,
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
            : .messagePhoto(.init(
                photo: .init(
                    hasStickers: false, minithumbnail: mini,
                    sizes: [.init(height: 24, photo: file, progressiveSizes: [], type: "y", width: 24)],
                ),
                video: nil,
                caption: caption,
                showCaptionAboveMedia: false,
                hasSpoiler: spoiler,
                isSecret: secret,
            ))
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

    /// The private source is solid red; a gray spoiler cover must not rasterize that source.
    private static func isFixtureRed(_ image: UIImage) throws -> Bool {
        guard let source = image.cgImage else { throw Failure(description: "snapshot has no CGImage") }
        var pixel = [UInt8](repeating: 0, count: 4)
        let sampled = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        try require(sampled, "snapshot pixel sampling failed")
        let red = Int(pixel[0])
        return red > 150 && red - Int(pixel[1]) > 60 && red - Int(pixel[2]) > 60
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            try require(ContinuousClock.now < deadline, "client-change delivery timeout")
            try await Task<Never, Never>.sleep(for: .milliseconds(10))
        }
    }
}
#endif
