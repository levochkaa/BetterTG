// SavedMediaDebugProbe.swift

#if DEBUG
import Foundation
import TDLibKit

@MainActor enum SavedMediaDebugProbe {
    private static var didRun = false

    static func runIfRequested(chat: CustomChat) {
        guard !didRun, chat.isSavedMessages,
              ProcessInfo.processInfo.arguments.contains("-saved-media-probe") else { return }
        didRun = true
        let client = TDLib.shared.activeClient
        let chatID = chat.id
        Task {
            var lines = [String]()
            for filter in [
                SearchMessagesFilter.searchMessagesFilterVideoNote,
                .searchMessagesFilterVoiceNote,
                .searchMessagesFilterPhoto,
            ] {
                do {
                    let result = try await client.searchChatMessages(
                        chatId: chatID,
                        filter: filter,
                        fromMessageId: 0,
                        limit: 5,
                        offset: 0,
                        query: "",
                        senderId: nil,
                        topicId: nil,
                    )
                    for message in result.messages {
                        let kind: String
                        let file: File
                        switch message.content {
                        case .messageVideoNote(let video): kind = "video"
                        file = video.videoNote.video
                        case .messageVoiceNote(let voice): kind = "voice"
                        file = voice.voiceNote.voice
                        case .messagePhoto(let photo):
                            guard let motion = photo.video else { continue }
                            kind = "livePhoto"
                            file = motion.video
                        default: continue
                        }
                        let topic =
 switch message.topicId {
                        case .messageTopicSavedMessages: "savedMessages"
                        case .messageTopicForum: "forum"
                        case nil: "nil"
                        default: "other"
                        }
                        lines
                            .append(
                                "kind=\(kind) id=\(message.id) date=\(message.date) topic=\(topic) sent=\(message.sendingState == nil) downloaded=\(file.local.isDownloadingCompleted) fileExtension=\(URL(filePath: file.local.path).pathExtension)",
                            )
                    }
                } catch { lines.append("read failed: \(error)") }
            }
            let proof = lines.joined(separator: "\n")
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? proof.write(
                    to: documents.appendingPathComponent("saved-media-probe.txt"),
                    atomically: true,
                    encoding: .utf8,
                )
            }
        }
    }
}
#endif
