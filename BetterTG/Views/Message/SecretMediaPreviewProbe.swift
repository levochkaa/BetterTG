// SecretMediaPreviewProbe.swift

#if DEBUG
    import Combine
    import TDLibKit
    import UIKit

    /// Launch with `-ui-probe-secret-media`. Over stubbed TDLib calls it shows a timed and a view-once
    /// self-destructing photo bubble, opens the timed photo and waits for it to close at its deadline, opens a sent
    /// photo nobody has opened yet, and finally leaves a view-once photo open whose file the stub deletes on
    /// openMessageContent, as TDLib does. Each stage is saved as `secret-media-N.png` in Documents, and the result as
    /// `secret-media-probe.txt`.
    @MainActor enum SecretMediaPreviewProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Stub {
            let center = NotificationCenter()
            let source = TdUpdateSource(accountID: UUID(), clientID: 77)
            var messages = [Int64: Message]()
            var deletesFileOnOpen = Set<Int64>()
            var calls = [String]()
            var ttlAfterOpen = 6.0

            var backend: VideoNotePlaybackBackend {
                VideoNotePlaybackBackend(
                    source: source, center: center,
                    clientChanges: Empty(completeImmediately: false).eraseToAnyPublisher(),
                    lifecycle: Empty(completeImmediately: false).eraseToAnyPublisher(),
                    isCurrent: { true },
                    download: { [self] id, _ in
                        calls.append("download")
                        guard let file = messages.values
.compactMap({ SecretMediaPreviewProbe.file(of: $0) })
                            .first(where: { $0.id == id }) else { throw Failure(description: "no file") }
                        return file
                    },
                    cancelDownload: { _ in },
                    message: { [self] _, id in
                        calls.append("message")
                        guard let message = messages[id] else { throw Failure(description: "no message") }
                        return message
                    },
                    open: { [self] _, id in
                        calls.append("open")
                        guard let message = messages[id] else { return }
                        if deletesFileOnOpen.contains(id),
                           let path = SecretMediaPreviewProbe.file(of: message)?.local.path
                        {
                            try? FileManager.default.removeItem(atPath: path)
                        }
                        messages[id] = SecretMediaPreviewProbe.message(
                            id: id, file: SecretMediaPreviewProbe.file(of: message)!,
                            type: message.selfDestructType, outgoing: message.isOutgoing,
                            remaining: message.selfDestructType == .messageSelfDestructTypeImmediately
                                ? 0
                                : ttlAfterOpen,
                        )
                    },
                    now: { ProcessInfo.processInfo.systemUptime },
                    sleep: { try await Task.sleep(for: .seconds(max(0, $0))) },
                    takePlayback: {},
                )
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-secret-media") else { return }
            Task { @MainActor in
                let result: String
                do {
                    result = try await run(in: window)
                } catch {
                    result = "Secret media probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("secret-media-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        fileprivate static func file(of message: Message) -> File? {
            guard case .messagePhoto(let value) = message.content else { return nil }
            return value.photo.sizes.first?.photo
        }

        fileprivate static func message(
            id: Int64,
            file: File,
            type: MessageSelfDestructType?,
            outgoing: Bool,
            remaining: Double = 0,
        ) -> Message {
            let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).jpegData(
                withCompressionQuality: 0.6,
            ) { context in
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }
            return Message(
                id: id,
                senderId: .messageSenderUser(.init(userId: 1)),
                receiverId: nil,
                chatId: 0,
                sendingState: nil,
                schedulingState: nil,
                isOutgoing: outgoing,
                isPinned: false,
                isFromOffline: false,
                canBeSaved: false,
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
                content: .messagePhoto(.init(
                    photo: .init(
                        hasStickers: false,
                        minithumbnail: .init(width: 40, height: 30, data: thumbnail),
                        sizes: [.init(type: "y", photo: file, width: 800, height: 600, progressiveSizes: [])],
                    ),
                    video: nil,
                    caption: .init(entities: [], text: ""),
                    showCaptionAboveMedia: false,
                    hasSpoiler: false,
                    isSecret: true,
                )),
                ephemeralContent: nil,
                replyMarkup: nil,
                ephemeralMessageId: 0,
                chatInstance: 0,
            )
        }

        private static func run(in window: UIWindow) async throws -> String {
            try? await Task.sleep(for: .seconds(2))
            UserDefaults.standard.removeObject(forKey: "SecretMedia.ViewOnceTooltipCount")
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("secret-media-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let stub = Stub()
            let timed = try message(
                id: 1, file: photoFile(id: 11, at: root, hue: 0.08),
                type: .messageSelfDestructTypeTimer(.init(selfDestructTime: 6)), outgoing: false,
            )
            let once = try message(
                id: 2, file: photoFile(id: 12, at: root, hue: 0.6),
                type: .messageSelfDestructTypeImmediately, outgoing: false,
            )
            let sent = try message(
                id: 3, file: photoFile(id: 13, at: root, hue: 0.35),
                type: .messageSelfDestructTypeTimer(.init(selfDestructTime: 10)), outgoing: true,
            )
            for message in [timed, once, sent] {
                stub.messages[message.id] = message
            }
            stub.deletesFileOnOpen = [once.id]

            let context = try playbackContext(url: URL(fileURLWithPath: file(of: timed)!.local.path), stub: stub)
            let session = MediaRevealSession(context: context)
            session.reconcile([timed, once, sent])

            // Bubbles.
            let host = UIViewController()
            host.view.backgroundColor = .systemBackground
            host.modalPresentationStyle = .fullScreen
            let clientID = stub.source.clientID
            let timedBubble = MediaConcealmentView(message: timed, clientID: clientID)
            let onceBubble = MediaConcealmentView(message: once, clientID: clientID)
            for (index, bubble) in [timedBubble, onceBubble].enumerated() {
                bubble.frame = CGRect(x: 20 + CGFloat(index) * 180, y: 140, width: 160, height: 120)
                bubble.layer.cornerRadius = 14
                host.view.addSubview(bubble)
            }
            window.rootViewController?.chatListTopPresenter.present(host, animated: false)
            try await settle()
            try require(labels(in: timedBubble).contains("6s"), "timed badge \(labels(in: timedBubble))")
            try require(labels(in: onceBubble).contains("1"), "view-once badge \(labels(in: onceBubble))")
            snapshot(window, 1)

            // A timed photo: read before it is opened, counted down, closed at its deadline.
            let timedPreview = try preview(timed, session: session, stub: stub)
            host.present(timedPreview, animated: true)
            try await until("timed photo shown") { shownImage(in: timedPreview) != nil }
            try require(stub.calls == ["message", "message", "open", "message"], "timed calls \(stub.calls)")
            try require(
                SelfDestructDeadlines.deadline(clientID: clientID, message: timed) != nil,
                "deadline not recorded",
            )
            try require(labels(in: timedPreview.view).contains(L10n.telegram("SecretImage.Title")), "timed title")
            try await Task.sleep(for: .seconds(1.5))
            snapshot(window, 2)
            let bubbleCountdown = labels(in: timedBubble).contains { $0 == "5s" || $0 == "4s" || $0 == "6s" }
            try await until("timed photo closed at its deadline", timeout: 9) { host.presentedViewController == nil }
            snapshot(window, 3)

            // A sent photo nobody opened: not consumed, with Telegram's footer.
            stub.calls.removeAll()
            let sentPreview = try preview(sent, session: session, stub: stub)
            host.present(sentPreview, animated: true)
            try await until("sent photo shown") { shownImage(in: sentPreview) != nil }
            try require(!stub.calls.contains("open"), "sent photo was opened: \(stub.calls)")
            let footer = L10n.telegram("SecretImage.NotViewedYet", "Ada")
            try require(labels(in: sentPreview.view).contains(footer), "sent footer \(labels(in: sentPreview.view))")
            snapshot(window, 4)
            try tapBack(in: sentPreview)
            try await until("sent photo closed") { host.presentedViewController == nil }

            // A view-once photo whose file TDLib deletes on opening stays on screen until it is closed.
            stub.calls.removeAll()
            let oncePreview = try preview(once, session: session, stub: stub)
            host.present(oncePreview, animated: true)
            try await until("view-once photo shown") { shownImage(in: oncePreview) != nil }
            let deleted = file(of: once).map { !FileManager.default.fileExists(atPath: $0.local.path) } ?? false
            try require(deleted && stub.calls.contains("open"), "view-once file kept or not opened: \(stub.calls)")
            try require(
                labels(in: oncePreview.view).contains(L10n.telegram("Gallery.ViewOncePhotoTooltip")),
                "view-once tooltip",
            )
            try await Task.sleep(for: .seconds(1))
            snapshot(window, 5)
            return "Secret media probe passed: bubble-badges=6s/1; timed=read-then-open, deadline-recorded, "
                + "bubble-countdown=\(bubbleCountdown), closed-at-deadline; sent=not-opened, footer; "
                + "view-once=file-deleted-on-open, still-shown, tooltip; view-once preview left open"
        }

        private static func preview(
            _ message: Message,
            session: MediaRevealSession,
            stub: Stub,
        ) throws -> SecretMediaPreviewViewController {
            guard let permit = session.permit(for: message), session.timelineTap(captured: message, current: message)
                == .openSecret,
                let preview = SecretMediaPreviewViewController(
                    message: message,
                    backend: stub.backend,
                    permit: permit,
                    peerTitle: "Ada",
                )
            else { throw Failure(description: "no preview for \(message.id)") }
            return preview
        }

        private static func playbackContext(url: URL, stub _: Stub) throws -> MediaGalleryPlaybackContext {
            let size = try (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 1
            let backend = TDLibVODProbeBackend(
                fileURL: url,
                fileSize: size,
                network: TDLibVODProbeNetwork(available: true),
            )
            let accountID = UUID()
            return MediaGalleryPlaybackContext(
                probeLocation: ChatLocation(accountID: accountID, chatID: 0, clientID: 77, topic: nil),
                vodRanges: TDLibVODRangeCoordinator(accountID: accountID.uuidString, client: backend.client),
                currentClientMatches: { true },
            )
        }

        private static func photoFile(id: Int, at root: URL, hue: CGFloat) throws -> File {
            let size = CGSize(width: 800, height: 600)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 250, y: 150, width: 300, height: 300))
            }
            let url = root.appendingPathComponent("photo-\(id).jpg")
            try image.jpegData(compressionQuality: 0.9)?.write(to: url)
            return File(
                expectedSize: 1,
                id: id,
                local: .init(
                    canBeDeleted: true,
                    canBeDownloaded: true,
                    downloadOffset: 0,
                    downloadedPrefixSize: 1,
                    downloadedSize: 1,
                    isDownloadingActive: false,
                    isDownloadingCompleted: true,
                    path: url.path,
                ),
                remote: .init(
                    id: "",
                    isUploadingActive: false,
                    isUploadingCompleted: true,
                    uniqueId: "",
                    uploadedSize: 1,
                ),
                size: 1,
            )
        }

        private static func shownImage(in controller: UIViewController) -> UIImage? {
            controller.viewIfLoaded.flatMap { view in
                subviews(of: view).compactMap { ($0 as? UIImageView)?.image }.first { $0.size.width >= 400 }
            }
        }

        private static func labels(in view: UIView) -> [String] {
            subviews(of: view).compactMap { ($0 as? UILabel).flatMap { $0.isHidden ? nil : $0.text } }
        }

        private static func subviews(of view: UIView) -> [UIView] {
            view.subviews + view.subviews.flatMap { subviews(of: $0) }
        }

        private static func tapBack(in controller: UIViewController) throws {
            guard let back = subviews(of: controller.view)
.compactMap({ $0 as? UIButton })
                .first(where: { $0.accessibilityLabel == L10n.telegram("Common.Back") })
            else { throw Failure(description: "no back button") }
            back.sendActions(for: .touchUpInside)
        }

        private static func snapshot(_ window: UIWindow, _ index: Int) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            try? image.pngData()?.write(to: documents.appendingPathComponent("secret-media-\(index).png"))
        }

        private static func settle() async throws {
            try await Task.sleep(for: .milliseconds(600))
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func until(
            _ reason: String,
            timeout: Double = 8,
            _ condition: () -> Bool,
        ) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
            while !condition() {
                guard ContinuousClock.now < deadline else { throw Failure(description: "timeout: \(reason)") }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }
#endif
