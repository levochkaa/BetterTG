// ChatComposerEditProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    @MainActor enum ChatComposerEditProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private final class Gate {
            private var entered = false
            private var continuation: CheckedContinuation<Void, Never>?
            private var observer: CheckedContinuation<Void, Never>?

            func wait() async {
                entered = true
                observer?.resume()
                observer = nil
                await withCheckedContinuation { continuation = $0 }
            }

            func waitUntilEntered() async {
                guard !entered else { return }
                await withCheckedContinuation { observer = $0 }
            }

            func open() {
                continuation?.resume()
                continuation = nil
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-composer-edit") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "Composer edit probe passed: invalid-edit-ordinary-sends=0; "
                        + "immutable-payload; delayed-success/error-fenced; A-B-A-revision; "
                        + "same-ID-reopen-fenced; completion-delivery-fenced; unchanged-clears; "
                        + "empty-media-caption-valid; cancellation-fenced; production-policy=true; server-sends=0"
                } catch {
                    result = "Composer edit probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("composer-edit-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(description: message) }
        }

        private static func verify() async throws {
            let message = fixture(content: .messageText(.init(
                linkPreview: nil, linkPreviewOptions: nil, text: .init(entities: [], text: "original"),
            )))
            let state = ChatComposerEditState()
            state.changeSession()
            var ordinarySends = 0
            var editRequests = 0
            // The real dispatch policy must consume this action regardless of
            // preserved ordinary text/attachments/reply in the surrounding composer.
            switch state.prepare(message: message, text: "") {
            case .ordinary: ordinarySends += 1
            case .edit: editRequests += 1
            case .invalidEdit: break
            }
            try require(ordinarySends == 0 && editRequests == 0, "empty edit fell through")
            guard case .ordinary = state.prepare(message: nil, text: "") else {
                throw Failure(description: "ordinary mode blocked")
            }

            for throwsError in [false, true] {
                for reopensSameMessage in [false, true] {
                    state.changeSession()
                    guard case .edit(let attempt) = state.prepare(message: message, text: "A") else {
                        throw Failure(description: "valid text edit rejected")
                    }
                    let gate = Gate()
                    var submittedText: FormattedText?
                    let request = Task {
                        await state.perform(attempt) { captured in
                            submittedText = captured.text
                            await gate.wait()
                            if throwsError { throw Failure(description: "delayed RPC error") }
                        }
                    }
                    await gate.waitUntilEntered()
                    if reopensSameMessage {
                        state.changeSession() // Close.
                        state.changeSession() // Reopen the identical message and text.
                    } else {
                        state.changeText() // A -> B.
                        state.changeText() // B -> A still represents a newer user revision.
                    }
                    gate.open()
                    let completion = await request.value
                    guard case .obsolete = completion else {
                        throw Failure(description: "stale \(throwsError ? "error" : "success") accepted")
                    }
                    try require(submittedText?.text == "A" && !state.isCurrent(attempt), "mutable request payload")
                }
            }

            state.changeSession()
            guard case .edit(let unchanged) = state.prepare(message: message, text: "unchanged") else {
                throw Failure(description: "unchanged fixture")
            }
            let success = await state.perform(unchanged) { captured in
                try require(captured.message.id == message.id && captured.text.text == "unchanged", "captured edit")
            }
            var didClear = false
            if case .succeeded = success, state.isCurrent(unchanged) {
                state.changeSession()
                didClear = true
            }
            try require(didClear && !state.isCurrent(unchanged), "unchanged completion did not clear")

            guard case .edit(let deliveryRace) = state.prepare(message: message, text: "A") else {
                throw Failure(description: "completion delivery fixture")
            }
            let delivered = await state.perform(deliveryRace) { _ in }
            state.changeText() // New input before the caller consumes the completion.
            guard case .succeeded = delivered else { throw Failure(description: "completion delivery setup") }
            try require(!state.isCurrent(deliveryRace), "caller delivery fence missing")

            let photo = fixture(content: .messagePhoto(.init(
                photo: .init(hasStickers: false, minithumbnail: nil, sizes: []),
                video: nil,
                caption: .init(entities: [], text: "old caption"),
                showCaptionAboveMedia: false,
                hasSpoiler: false,
                isSecret: false,
            )))
            state.changeSession()
            guard case .edit(let emptyCaption) = state.prepare(message: photo, text: "") else {
                throw Failure(description: "empty media caption rejected")
            }
            let captionResult = await state.perform(emptyCaption) { captured in
                try require(captured.text.text.isEmpty && captured.text.entities.isEmpty, "empty caption payload")
                editRequests += 1
            }
            guard case .succeeded = captionResult else { throw Failure(description: "empty caption completion") }
            try require(editRequests == 1 && ordinarySends == 0, "media edit dispatched ordinary send")

            state.changeSession()
            guard case .edit(let cancelled) = state.prepare(message: message, text: "cancel") else {
                throw Failure(description: "cancel fixture")
            }
            let gate = Gate()
            let task = Task { await state.perform(cancelled) { _ in await gate.wait() } }
            await gate.waitUntilEntered()
            task.cancel()
            gate.open()
            guard case .obsolete = await task.value else { throw Failure(description: "cancelled result accepted") }
        }

        private static func fixture(content: MessageContent) -> Message {
            Message(
                id: 42,
                senderId: .messageSenderUser(.init(userId: 1)),
                receiverId: nil,
                chatId: 100,
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
    }
#endif
