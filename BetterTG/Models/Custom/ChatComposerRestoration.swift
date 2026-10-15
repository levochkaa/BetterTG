// ChatComposerRestoration.swift

import TDLibKit
import UIKit

// MARK: - ChatComposerRestorationState

/// In-memory state, not a second file owner. Message values avoid sharing the old
/// VM's mutable CustomMessage instances with the replacement composer.
struct ChatComposerRestorationState: Equatable {
    struct MessageValue: Equatable {
        let message: Message
        let sender: User?
        let properties: MessageProperties
        let formattedText: FormattedText?

        @MainActor init(_ value: CustomMessage) {
            self.message = value.message
            self.sender = value.senderUser
            self.properties = value.properties
            self.formattedText = value.formattedText
        }

        @MainActor func makeMessage() -> CustomMessage {
            CustomMessage(message: message, senderUser: sender, formattedText: formattedText, properties: properties)
        }
    }

    struct Edit: Equatable {
        let target: MessageValue
        let text: AttributedString
    }

    let location: ChatLocation
    let revision: UInt64
    let text: AttributedString
    let edit: Edit?
    let replyMessage: MessageValue?
    let replyTo: InputMessageReplyTo?
    let images: [SelectedImage]
    let documents: [SelectedDocument]
    let sendError: String?
    let draftError: String?
    /// A forward waiting in the composer, which a client renewal keeps (Telegram's interface state keeps it).
    var forward: PendingMessageForward?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.location == rhs.location && lhs.revision == rhs.revision
            && lhs.text == rhs.text && lhs.edit == rhs.edit
            && lhs.replyMessage == rhs.replyMessage && lhs.replyTo == rhs.replyTo
            && lhs.images.map(\.id) == rhs.images.map(\.id) && lhs.images == rhs.images
            && lhs.documents == rhs.documents
            && lhs.sendError == rhs.sendError && lhs.draftError == rhs.draftError
            && lhs.forward == rhs.forward
    }

    func permitsRestoration(to destination: ChatLocation, currentSource: TdUpdateSource?) -> Bool {
        location.accountID != nil
            && location.draftKey == destination.draftKey
            && location.clientID != destination.clientID
            && currentSource?.matches(destination) == true
    }
}

// MARK: - ChatComposerRestorationTransfer

/// Capturing or cancelling a ticket does not change ownership. The old owner
/// validates its live state again and relinquishes ownership synchronously,
/// immediately before the nonthrowing replacement constructor takes over.
@MainActor final class ChatComposerRestorationTransfer {
    let snapshot: ChatComposerRestorationState

    private var retireOwner: (() -> Bool)?
    private var isCommitting = false

    init(snapshot: ChatComposerRestorationState, retireOwner: @escaping () -> Bool) {
        self.snapshot = snapshot
        self.retireOwner = retireOwner
    }

    func cancel() {
        guard !isCommitting else { return }
        retireOwner = nil
    }

    func commit<Recipient>(
        to destination: ChatLocation,
        currentSource: TdUpdateSource?,
        construct: (ChatComposerRestorationState) -> Recipient,
    ) -> Recipient? {
        guard !isCommitting,
              snapshot.permitsRestoration(to: destination, currentSource: currentSource),
              let retireOwner
        else { return nil }
        isCommitting = true
        defer { isCommitting = false }
        guard retireOwner() else { return nil }
        self.retireOwner = nil
        return construct(snapshot)
    }
}

// MARK: - ChatComposerRestorationLifetime

/// Shared by ChatVM's actual deinit and the isolated ownership probe. Once an
/// owner transfers, its later deinit must not delete files or dismiss new media.
@MainActor final class ChatComposerRestorationLifetime {
    private(set) var isRetired = false

    private var didFinish = false

    @discardableResult func retire() -> Bool {
        guard !isRetired, !didFinish else { return false }
        isRetired = true
        return true
    }

    func finish(cleanup: () -> Void) {
        guard !isRetired, !didFinish else { return }
        didFinish = true
        cleanup()
    }
}
