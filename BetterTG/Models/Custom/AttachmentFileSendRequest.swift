// AttachmentFileSendRequest.swift

import Foundation
import TDLibKit

// MARK: - AttachmentRecentFile

/// A recent attachment is a source message, not a file ID: two messages can contain the same file.
struct AttachmentRecentFile {
    struct ID: Hashable {
        let chatID: Int64
        let messageID: Int64
    }

    let id: ID
    let date: Int
    let document: Document

    init(id: ID, date: Int, document: Document) {
        self.id = id
        self.date = date
        self.document = document
    }

    init?(_ message: Message) {
        guard case .messageDocument(let value) = message.content else { return nil }
        self.init(id: ID(chatID: message.chatId, messageID: message.id), date: message.date, document: value.document)
    }
}

// MARK: - AttachmentFileSendRequest

struct AttachmentFileSendRequest {
    let files: [AttachmentRecentFile]
    let caption: AttributedString
    let options: TDNativeMessageSendOptions?

    /// ChatControllerOpenAttachmentMenu puts a File caption on the last selected document, unlike Gallery.
    static func contents(files: [AttachmentRecentFile], caption: FormattedText?) -> [InputMessageContent] {
        files.enumerated().map { index, file in
            .inputMessageDocument(TDNativeInputMessageDocument(
                document: TDNativeInputDocument(
                    document: .inputFileId(TDNativeInputFileId(id: file.document.document.id)),
                    thumbnail: nil,
                    disableContentTypeDetection: true,
                ),
                caption: index == files.count - 1 ? caption : nil,
            ))
        }
    }

    /// A partial album can omit a middle item. Match receipts rather than dropping a presumed accepted prefix.
    static func acceptedIDs(
        files: [AttachmentRecentFile], contents: [InputMessageContent], messages: [Message],
    ) -> Set<AttachmentRecentFile.ID>? {
        guard messages.count <= files.count, contents.count == files.count else { return nil }
        if messages.count == files.count { return Set(files.map(\.id)) }
        var accepted = Set<AttachmentRecentFile.ID>()
        for message in messages {
            guard case .messageDocument(let sent) = message.content,
                  let index = files.indices.first(where: { index in
                      let file = files[index]
                      guard !accepted.contains(file.id),
                            case .inputMessageDocument(let input) = contents[index] else { return false }
                      let sameFile = file.document.document.id == sent.document.document.id
                          || (!file.document.document.remote.uniqueId.isEmpty
                              && file.document.document.remote.uniqueId == sent.document.document.remote.uniqueId)
                      return sameFile && (input.caption?.text ?? "") == sent.caption.text
                  })
            else { return nil }
            accepted.insert(files[index].id)
        }
        return accepted
    }
}

// MARK: - AttachmentFileSendResult

struct AttachmentFileSendResult {
    var acceptedIDs = Set<AttachmentRecentFile.ID>()
    var error: String?
    /// An unidentifiable receipt must not silently resend a document that TDLib may already have accepted.
    var canRetry = true
}

// MARK: - AttachmentFileSendSession

/// A partial send clears the main composer's reply. Its retry must still use the original reply and forum topic.
@MainActor final class AttachmentFileSendSession {
    struct Snapshot {
        let context: ResolvedSendContext
        let reply: CustomMessage?
        let defaultOptions: TDNativeMessageSendOptions?
    }

    private var snapshot: Snapshot?

    /// Only the client changes. An All Messages reply may target a forum topic different from the route's nil topic.
    func replacingClient(from old: ChatLocation, with new: ChatLocation) -> AttachmentFileSendSession? {
        guard old.accountID != nil, old.accountID == new.accountID, old.chatID == new.chatID,
              old.topic == new.topic, old.clientID != new.clientID else { return nil }
        let replacement = AttachmentFileSendSession()
        if let snapshot {
            let context = snapshot.context
            guard context.accountID == old.accountID, context.clientID == old.clientID,
                  context.chatID == old.chatID, context.draftTopic == old.topic else { return nil }
            replacement.snapshot = Snapshot(
                context: ResolvedSendContext(
                    accountID: context.accountID, chatID: context.chatID, clientID: new.clientID,
                    destinationTopic: context.destinationTopic, draftTopic: context.draftTopic,
                    replyTo: context.replyTo, allowsSavedMessagesTopic: context.allowsSavedMessagesTopic,
                ),
                reply: snapshot.reply, defaultOptions: snapshot.defaultOptions,
            )
        }
        return replacement
    }

    func capture(_ make: () throws -> Snapshot) rethrows -> Snapshot {
        if let snapshot { return snapshot }
        let value = try make()
        snapshot = value
        return value
    }
}
