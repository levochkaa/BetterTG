// ChatComposerEditState.swift

import Foundation
import TDLibKitDynamic

@MainActor final class ChatComposerEditState {
    enum Submission {
        case ordinary
        case invalidEdit
        case edit(Attempt)
    }

    struct Attempt {
        let message: Message
        let text: FormattedText

        fileprivate let session: UInt64
        fileprivate let revision: UInt64
    }

    enum Completion {
        case obsolete
        case succeeded
        case failed(Swift.Error)
    }

    private var session = UInt64.zero
    private var revision = UInt64.zero

    static func allowsSubmission(message: Message, text: AttributedString) -> Bool {
        switch message.content {
        case .messageAnimation, .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
            true
        case .messageText:
            !text.characters.isEmpty
        default:
            false
        }
    }

    func changeSession() {
        session &+= 1
    }

    func changeText() {
        revision &+= 1
    }

    func prepare(message: Message?, text: AttributedString) -> Submission {
        guard let message else { return .ordinary }
        guard Self.allowsSubmission(message: message, text: text) else { return .invalidEdit }
        return .edit(Attempt(
            message: message,
            text: FormattedText(entities: getEntities(from: text), text: text.string),
            session: session,
            revision: revision,
        ))
    }

    func perform(
        _ attempt: Attempt,
        operation: (Attempt) async throws -> Void,
    ) async -> Completion {
        guard isCurrent(attempt), !Task.isCancelled else { return .obsolete }
        do {
            try await operation(attempt)
            return isCurrent(attempt) && !Task.isCancelled ? .succeeded : .obsolete
        } catch {
            return isCurrent(attempt) && !Task.isCancelled ? .failed(error) : .obsolete
        }
    }

    func isCurrent(_ attempt: Attempt) -> Bool {
        attempt.session == session && attempt.revision == revision
    }
}
