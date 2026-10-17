// PollMediaGalleryProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    /// Launch with `-ui-probe-poll-gallery` to open a quiz's media gallery as tapping its second answer's photo would:
    /// the first two answers carry photos, the third a place and the fourth nothing, and the poll's own media and the
    /// explanation carry photos too. The probe checks the pages, their captions and how share and save find a page's
    /// photo again in a fresh copy of the poll, writes the result to `poll-gallery-probe.txt` in Documents, and leaves
    /// the gallery open with share and save for the active account. Nothing reaches a chat: the poll is made up, so
    /// share and save end in "message unavailable".
    @MainActor enum PollMediaGalleryProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-poll-gallery") else { return }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                try? await Task.sleep(for: .seconds(2))
                let result: String
                do {
                    result = try run(in: window)
                } catch {
                    result = "Poll gallery probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("poll-gallery-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func run(in window: UIWindow) throws -> String {
            guard let accountID = TDLib.shared.activeAccountID else { throw Failure(description: "no account") }
            let client = TDLib.shared.activeClient
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("poll-gallery-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let first = try photo(id: 9101, label: "1", hue: 0.0, at: root)
            let second = try photo(id: 9102, label: "2", hue: 0.33, at: root)
            let own = try photo(id: 9103, label: "P", hue: 0.6, at: root)
            let explanation = try photo(id: 9104, label: "E", hue: 0.12, at: root)
            let replacement = try photo(id: 9105, label: "1'", hue: 0.8, at: root)
            let place = TDNativePollMedia.pollMediaLocation(TDNativePollMediaLocation(location: Location(
                horizontalAccuracy: 0,
                latitude: 41.6938,
                longitude: 44.8015,
            )))
            let poll = message(options: [first, second, place, nil], own: own, explanation: explanation)

            // An answer's photo pages through the answers' photos only, with the answers as captions.
            guard let answers = PollMediaGallery(media: second, in: poll) else { throw Failure(description: "answers") }
            try require(answers.pages.count == 2, "answer pages \(answers.pages.count)")
            try require(answers.pages.map(caption) == ["First answer", "Second answer"], "answer captions")
            try require(answers.pages.first { $0.id == answers.selection }.map(caption) == "Second answer", "selection")
            try require(Set(answers.pages.map(\.id)).count == 2 && answers.pages.allSatisfy { $0.id < 0 }, "page ids")
            // The poll's own media and the explanation's open alone under the description or the explanation.
            let description = PollMediaGallery(media: own, in: poll)
            try require(description?.pages.map(caption) == ["Poll caption"], "description page")
            let solution = PollMediaGallery(media: explanation, in: poll)
            try require(solution?.pages.map(caption) == ["Because it is first."], "solution page")
            try require(PollMediaGallery(media: place, in: poll) == nil, "a place opened the gallery")

            // Share and save read the page's photo from the poll TDLib returns.
            let source = answers.embeddedSource(accountID: accountID, clientID: client.id)
            let firstPage = answers.pages[0].id
            let secondPage = answers.pages[1].id
            let replaced = message(options: [replacement, second, place, nil], own: own, explanation: explanation)
            try require(fileID(source.resolvePage(firstPage, replaced)) == 9105, "replaced answer photo")
            try require(fileID(source.resolvePage(secondPage, replaced)) == 9102, "kept answer photo")
            let removed = message(options: [first, nil, place, nil], own: own, explanation: explanation)
            try require(source.resolvePage(secondPage, removed) == nil, "removed answer photo")
            try require(source.containerMessageID == poll.id && source.chatID == poll.chatId, "container")

            guard let location = Optional(ChatLocation(
                accountID: accountID,
                chatID: poll.chatId,
                clientID: client.id,
                topic: nil,
            )),
                let context = MediaGalleryPlaybackContext(client: client, location: location, tdlib: .shared),
                let presenter = topController(in: window)
            else { throw Failure(description: "no playback context") }
            let gallery = MediaGalleryViewController(
                messages: answers.pages,
                selection: answers.selection,
                actionClient: client,
                playbackContext: context,
                embeddedMediaSource: source,
            )
            presenter.present(gallery, animated: true)
            return "Poll gallery probe passed: answer-pages=2 (place and empty answers skipped); "
                + "captions=answer/description/explanation; selection=second answer; page-ids=negative and distinct; "
                + "resolve=fresh poll (replaced 9105, kept 9102, removed nil); gallery presented with share/save"
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func caption(_ message: Message) -> String? {
            switch message.content {
            case .messagePhoto(let photo): photo.caption.text
            case .messageVideo(let video): video.caption.text
            case .messageAnimation(let animation): animation.caption.text
            default: nil
            }
        }

        private static func fileID(_ message: Message?) -> Int? {
            guard case .messagePhoto(let photo) = message?.content else { return nil }
            return photo.photo.sizes.last?.photo.id
        }

        private static func photo(id: Int, label: String, hue: CGFloat, at root: URL) throws -> TDNativePollMedia {
            let size = CGSize(width: 900, height: 600)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(hue: hue, saturation: 0.7, brightness: 0.85, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let text = NSAttributedString(string: label, attributes: [
                    .font: UIFont.systemFont(ofSize: 260, weight: .bold),
                    .foregroundColor: UIColor.white,
                ])
                let textSize = text.size()
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
            }
            let url = root.appendingPathComponent("photo-\(id).jpg")
            try image.jpegData(compressionQuality: 0.9)?.write(to: url)
            let byteCount = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
                .int64Value ?? 1
            let file = File(
                expectedSize: byteCount,
                id: id,
                local: .init(
                    canBeDeleted: true,
                    canBeDownloaded: true,
                    downloadOffset: 0,
                    downloadedPrefixSize: byteCount,
                    downloadedSize: byteCount,
                    isDownloadingActive: false,
                    isDownloadingCompleted: true,
                    path: url.path,
                ),
                remote: .init(
                    id: "",
                    isUploadingActive: false,
                    isUploadingCompleted: true,
                    uniqueId: "poll-gallery-\(id)",
                    uploadedSize: byteCount,
                ),
                size: byteCount,
            )
            return .pollMediaPhoto(TDNativePollMediaPhoto(
                photo: Photo(
                    hasStickers: false,
                    minithumbnail: nil,
                    sizes: [PhotoSize(height: 600, photo: file, progressiveSizes: [], type: "y", width: 900)],
                ),
                video: nil,
            ))
        }

        private static func message(
            options media: [TDNativePollMedia?],
            own: TDNativePollMedia,
            explanation: TDNativePollMedia,
        ) -> Message {
            let titles = ["First answer", "Second answer", "Third answer", "Fourth answer"]
            let options = media.enumerated().map { index, media in
                PollOption(
                    additionDate: 0,
                    author: nil,
                    id: "option-\(index)",
                    isBeingChosen: false,
                    isChosen: false,
                    media: media,
                    recentVoterIds: [],
                    text: FormattedText(entities: [], text: titles[index]),
                    votePercentage: 25,
                    voterCount: 1,
                )
            }
            let poll = MessagePoll(
                canAddOption: false,
                description: FormattedText(entities: [], text: "Poll caption"),
                media: own,
                poll: Poll(
                    allowsMultipleAnswers: false,
                    allowsRevoting: true,
                    canGetVoters: false,
                    canSeeResults: true,
                    closeDate: 0,
                    countryCodes: [],
                    id: 701,
                    isAnonymous: true,
                    isClosed: false,
                    membersOnly: false,
                    openPeriod: 0,
                    optionOrder: [],
                    options: options,
                    question: FormattedText(entities: [], text: "Which photo?"),
                    recentVoterIds: [],
                    totalVoterCount: 4,
                    type: .pollTypeQuiz(PollTypeQuiz(
                        correctOptionIds: [0],
                        explanation: FormattedText(entities: [], text: "Because it is first."),
                        explanationMedia: explanation,
                    )),
                    voteRestrictionReason: nil,
                ),
            )
            return Message(
                id: 700,
                senderId: .messageSenderUser(MessageSenderUser(userId: 777_000)),
                receiverId: nil,
                chatId: -1,
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
                date: Int(Date().timeIntervalSince1970),
                editDate: 0,
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
                content: .messagePoll(poll),
                ephemeralContent: nil,
                replyMarkup: nil,
                ephemeralMessageId: 0,
                chatInstance: 0,
            )
        }

        private static func topController(in window: UIWindow) -> UIViewController? {
            var presenter = window.rootViewController
            while let presented = presenter?.presentedViewController {
                presenter = presented
            }
            return presenter
        }
    }
#endif
