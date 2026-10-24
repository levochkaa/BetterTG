// ChatListRowIconsProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks a chat row's lead-in offline: which messageTypeIcon and media thumbnail ChatListItem gives a last
    /// message, the text that goes with them, and rows laid out with each, rendered to Documents/row-icons.png.
    /// Launch with `-ui-probe-row-icons`; the result goes to the log and to Documents/row-icons-probe.txt.
    @MainActor enum ChatListRowIconsProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private static let file = File(
            expectedSize: 0,
            id: 9100,
            local: LocalFile(
                canBeDeleted: false,
                canBeDownloaded: false,
                downloadOffset: 0,
                downloadedPrefixSize: 0,
                downloadedSize: 0,
                isDownloadingActive: false,
                isDownloadingCompleted: false,
                path: "",
            ),
            remote: RemoteFile(
                id: "row-icons",
                isUploadingActive: false,
                isUploadingCompleted: true,
                uniqueId: "row-icons",
                uploadedSize: 0,
            ),
            size: 0,
        )

        private static let location = MessageContent.messageLocation(.init(
            location: Location(latitude: 41.7, longitude: 44.8, horizontalAccuracy: 0),
        ))

        private static let forwardInfo = MessageForwardInfo(
            date: 1,
            origin: .messageOriginHiddenUser(MessageOriginHiddenUser(senderName: "Author")),
            publicServiceAnnouncementType: "",
            source: nil,
        )

        private static var minithumbnail: Minithumbnail {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
            }
            return Minithumbnail(data: image.jpegData(compressionQuality: 0.9) ?? Data(), height: 8, width: 8)
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-row-icons") else { return }
            Task {
                let result: String
                do {
                    try await ProbeFixtures.waitForActiveAccount()
                    try verifyIcons()
                    try verifyPreviews()
                    try render()
                    result = "Row icons probe passed: forward/story/voice/location/caption-text/assets=true; "
                        + "photo-caption/video-play/round/spoiler-mini/secret-none=true; rendered=true"
                } catch {
                    result = "Row icons probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("row-icons-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func message(
            _ id: Int64,
            _ content: MessageContent?,
            forward: MessageForwardInfo? = nil,
            replyTo: MessageReplyTo? = nil,
        ) -> Message {
            MessageDeliveryProbe.fixture(
                id: id,
                outgoing: false,
                content: content,
                forwardInfo: forward,
                replyTo: replyTo,
            )
        }

        private static func caption(_ text: String) -> FormattedText {
            FormattedText(entities: [], text: text)
        }

        private static func voice(_ text: String) -> MessageContent {
            .messageVoiceNote(.init(
                voiceNote: .init(
                    duration: 1,
                    waveform: Data(),
                    mimeType: "audio/ogg",
                    speechRecognitionResult: nil,
                    voice: file,
                ),
                caption: caption(text),
                isListened: false,
            ))
        }

        private static func photo(_ text: String, spoiler: Bool = false) -> MessageContent {
            .messagePhoto(.init(
                photo: Photo(
                    hasStickers: false,
                    minithumbnail: minithumbnail,
                    sizes: [PhotoSize(type: "s", photo: file, width: 100, height: 100, progressiveSizes: [])],
                ),
                video: nil,
                caption: caption(text),
                showCaptionAboveMedia: false,
                hasSpoiler: spoiler,
                isSecret: false,
            ))
        }

        private static func video(_ text: String) -> MessageContent {
            .messageVideo(.init(
                video: Video(
                    duration: 1,
                    width: 100,
                    height: 100,
                    fileName: "",
                    mimeType: "video/mp4",
                    hasStickers: false,
                    supportsStreaming: true,
                    minithumbnail: minithumbnail,
                    thumbnail: nil,
                    video: file,
                ),
                alternativeVideos: [],
                storyboards: [],
                cover: nil,
                startTimestamp: 0,
                caption: caption(text),
                showCaptionAboveMedia: false,
                hasSpoiler: false,
                isSecret: false,
            ))
        }

        private static func videoNote() -> MessageContent {
            .messageVideoNote(.init(
                videoNote: VideoNote(
                    duration: 1,
                    waveform: Data(),
                    length: 100,
                    minithumbnail: minithumbnail,
                    thumbnail: nil,
                    speechRecognitionResult: nil,
                    video: file,
                ),
                isViewed: false,
                isSecret: false,
            ))
        }

        private static func verifyIcons() throws {
            try require(
                ChatListMessageTypeIcon.make(for: message(1, voice(""), forward: forwardInfo))
                    == .forward,
                "forward",
            )
            try require(
                ChatListMessageTypeIcon.make(for: message(
                    2,
                    nil,
                    replyTo: .messageReplyToStory(.init(storyPosterChatId: 1, storyId: 1)),
                )) == .story,
                "story",
            )
            let voiceMessage = message(3, voice("hello"))
            try require(ChatListMessageTypeIcon.make(for: voiceMessage) == .voiceMessage, "voice")
            try require(ChatListMessageTypeIcon.text(for: voiceMessage) == "hello", "voice caption")
            try require(
                ChatListMessageTypeIcon.text(for: message(3, voice("")))
                    == nil,
                "voice without caption",
            )
            try require(
                ChatListMessageTypeIcon.make(for: message(4, location))
                    == .location,
                "location",
            )
            try require(
                [
                    .forward,
                    .story,
                    .voiceMessage,
                    .audio,
                    .poll,
                    .todo,
                    .game,
                    .location,
                    ChatListMessageTypeIcon.call(video: true, incoming: true),
                    .call(video: false, incoming: false),
                ]
                    .allSatisfy { $0.image != nil },
                "assets",
            )
        }

        private static func verifyPreviews() throws {
            let captioned = ChatListMediaPreview.make(
                for: message(5, photo("sunset")),
                inSecretChat: false,
            )
            try require(captioned?.text == "sunset" && captioned?.file != nil && captioned?.showsPlay == false, "photo")
            let bare = ChatListMediaPreview.make(
                for: message(5, photo("")),
                inSecretChat: false,
            )
            try require(bare?.text == L10n.telegram("Message.Photo"), "photo label")
            let video = ChatListMediaPreview.make(
                for: message(6, video("")),
                inSecretChat: false,
            )
            try require(video?.showsPlay == true && video?.isRound == false, "video")
            let round = ChatListMediaPreview.make(
                for: message(7, videoNote()),
                inSecretChat: false,
            )
            try require(round?.isRound == true && round?.showsPlay == false, "round")
            let spoiler = ChatListMediaPreview.make(
                for: message(8, photo("", spoiler: true)),
                inSecretChat: false,
            )
            try require(spoiler?.file == nil && spoiler?.minithumbnail != nil, "spoiler")
            try require(
                ChatListMediaPreview.make(
                    for: message(9, photo("")),
                    inSecretChat: true,
                ) == nil,
                "secret",
            )
        }

        private static func render() throws {
            let position = ChatPosition(isPinned: false, list: .chatListMain, order: 1, source: nil)
            let rows: [(String, Message)] = [
                ("Forwarded photo", message(10, photo("A forwarded caption"), forward: forwardInfo)),
                ("Voice", message(11, voice(""))),
                ("Location", message(12, location)),
                ("Video", message(13, video("Clip caption"))),
                ("Round", message(14, videoNote())),
            ]
            let width = CGFloat(402)
            let height = ChatListCell.cardRowHeight
            let canvas = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height * CGFloat(rows.count)))
            canvas.backgroundColor = .systemBackground
            canvas.overrideUserInterfaceStyle = .dark
            for (index, row) in rows.enumerated() {
                let cell = ChatListCell(style: .default, reuseIdentifier: ChatListCell.reuseIdentifier)
                cell.frame = CGRect(x: 0, y: height * CGFloat(index), width: width, height: height)
                cell.configure(
                    chat: ProbeFixtures.chat(position, title: row.0, id: 9000 + Int64(index), last: row.1),
                    isMuted: false,
                    client: TDLib.shared.activeClient,
                )
                canvas.addSubview(cell)
                cell.layoutIfNeeded()
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
            }
            let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
                canvas.layer.render(in: context.cgContext)
            }
            guard let data = image.pngData(),
                  let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { throw Failure(description: "render") }
            try data.write(to: directory.appendingPathComponent("row-icons.png"), options: .atomic)
        }
    }
#endif
