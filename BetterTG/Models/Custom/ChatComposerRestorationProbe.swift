// ChatComposerRestorationProbe.swift

#if DEBUG
    import TDLibKitDynamic
    import UIKit

    @MainActor enum ChatComposerRestorationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private final class Counters {
            var destructions = 0
            var fileCleanups = 0
            var mediaDismissals = 0
        }

        /// No TDLib client, shared draft store, or actual Media singleton. The
        /// real lifetime helper controls deinit against isolated temporary files.
        @MainActor private final class Owner {
            var snapshot: ChatComposerRestorationState
            var quiescent = true
            let lifetime = ChatComposerRestorationLifetime()
            let counters: Counters

            init(_ snapshot: ChatComposerRestorationState, counters: Counters) {
                self.snapshot = snapshot
                self.counters = counters
            }

            deinit {
                MainActor.assumeIsolated {
                    counters.destructions += 1
                    lifetime.finish {
                        for document in snapshot.documents {
                            try? FileManager.default.removeItem(at: document.url)
                            counters.fileCleanups += 1
                        }
                        counters.mediaDismissals += 1
                    }
                }
            }

            func transfer() -> ChatComposerRestorationTransfer {
                let captured = snapshot
                return ChatComposerRestorationTransfer(snapshot: captured) { [self] in
                    quiescent && snapshot == captured && lifetime.retire()
                }
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-composer-restoration") else { return }
            let result: String
            do {
                try verify()
                result = "Composer restoration foundation probe passed: production-value/transfer/lifetime=true; "
                    + "account/chat/topic/new-client-fences=true; nil-topic-distinct=true; "
                    + "attributed-compose/edit/reply-quote/attachment-IDs=true; mutable-message-detached=true; "
                    + "busy/changed/cancelled/repeated/reentrant-transfer-fenced=true; "
                    + "old-deinit-file/media-cleanup=0; new-owner-cleanup-once=true; "
                    + "ChatVM-seed-before-server-draft=source-reviewed; Chat-navigation-not-enabled; server-sends=0"
            } catch {
                result = "Composer restoration foundation probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("composer-restoration-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verify() throws {
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let root = temporaryDirectory
                .appendingPathComponent("ComposerRestorationProbe-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let account = UUID()
            let topic = MessageTopic.messageTopicForum(.init(forumTopicId: 99))
            let old = ChatLocation(accountID: account, chatID: 100, clientID: 11, topic: topic)
            let next = ChatLocation(accountID: account, chatID: 100, clientID: 12, topic: topic)
            let source = TdUpdateSource(accountID: account, clientID: 12)
            let message = CustomMessage(message: messageFixture(), properties: .default)
            let state = try snapshot(root: root, location: old, message: message)
            let frozenMessage = state.edit?.target.message
            message.message = messageFixture(text: "changed after capture")
            try require(state.edit?.target.message == frozenMessage, "snapshot retained mutable message")
            let restoredMessage = state.edit?.target.makeMessage()
            try require(
                restoredMessage !== message && restoredMessage?.message == frozenMessage,
                "new composer reused old CustomMessage",
            )
            let editPolicy = ChatComposerEditState()
            guard case .invalidEdit = editPolicy.prepare(message: state.edit?.target.message, text: state.edit!.text)
                else {
                throw Failure(description: "preserved empty edit became an ordinary send")
            }
            try require(
                !state.text.characters.isEmpty && state.images.count == 1 && state.documents.count == 1,
                "ordinary draft lost while edit is active",
            )
            let counters = Counters()
            var owner: Owner? = Owner(state, counters: counters)
            let transfer = owner!.transfer()
            let rejected = [
                ChatLocation(accountID: UUID(), chatID: 100, clientID: 12, topic: topic),
                ChatLocation(accountID: account, chatID: 101, clientID: 12, topic: topic),
                ChatLocation(accountID: account, chatID: 100, clientID: 12, topic: nil),
                ChatLocation(
                    accountID: account,
                    chatID: 100,
                    clientID: 12,
                    topic: .messageTopicForum(.init(forumTopicId: 1)),
                ),
                old,
            ]
            for location in rejected {
                let result = transfer.commit(to: location, currentSource: source) { _ in true }
                try require(result == nil && !owner!.lifetime.isRetired, "mismatched scope moved ownership")
            }
            try require(
                transfer.commit(to: next, currentSource: nil, construct: { _ in true }) == nil,
                "missing source accepted",
            )
            try require(
                transfer
                    .commit(
                        to: next,
                        currentSource: .init(accountID: account, clientID: 13),
                        construct: { _ in true },
                    ) ==
                    nil,
                "newer client accepted stale destination",
            )
            owner!.quiescent = false
            try require(
                transfer.commit(to: next, currentSource: source, construct: { _ in true }) == nil,
                "busy owner retired",
            )
            try require(
                !owner!.lifetime.isRetired && counters.fileCleanups == 0
                    && FileManager.default.fileExists(atPath: state.documents[0].url.path),
                "failed retirement changed file ownership",
            )
            owner!.quiescent = true
            owner = nil // The uncommitted ticket still retains its owning VM.
            try require(counters.destructions == 0, "pending transfer released file owner")
            let recipientCounters = Counters()
            var recipient: Owner? = transfer.commit(to: next, currentSource: source) { captured in
                Owner(captured, counters: recipientCounters)
            }
            try require(
                recipient?.snapshot == state && recipient?.snapshot.images[0].id == state.images[0].id,
                "payload or attachment identity changed",
            )
            try require(
                counters.destructions == 1 && counters.fileCleanups == 0 && counters.mediaDismissals == 0,
                "old deinit deleted transferred files or dismissed media",
            )
            try require(
                FileManager.default.fileExists(atPath: state.documents[0].url.path),
                "transferred file disappeared",
            )
            try require(
                transfer.commit(to: next, currentSource: source, construct: { _ in true }) == nil,
                "ticket transferred twice",
            )
            recipient = nil
            try require(
                recipientCounters.fileCleanups == 1 && recipientCounters.mediaDismissals == 1,
                "new owner did not clean up exactly once",
            )
            try require(
                !FileManager.default.fileExists(atPath: state.documents[0].url.path),
                "new owner leaked its file",
            )

            let cancelledState = try snapshot(root: root, location: old, message: message)
            let cancelledOwner = Owner(cancelledState, counters: Counters())
            let cancelled = cancelledOwner.transfer()
            cancelled.cancel()
            try require(
                cancelled.commit(to: next, currentSource: source, construct: { _ in true }) == nil
                && !cancelledOwner.lifetime.isRetired
                && FileManager.default.fileExists(atPath: cancelledState.documents[0].url.path),
                "cancel changed file ownership",
            )
            let changed = cancelledOwner.transfer()
            cancelledOwner.snapshot = try snapshot(root: root, location: old, message: message)
            try require(
                changed.commit(to: next, currentSource: source, construct: { _ in true }) == nil,
                "changed attachment state accepted old ticket",
            )
            let nilTopic = ChatLocation(accountID: account, chatID: 100, clientID: 11, topic: nil)
            let nilState = try snapshot(root: root, location: nilTopic, message: message)
            try require(
                !nilState.permitsRestoration(to: next, currentSource: source),
                "all-messages became a topic route",
            )
            try require(nilState.permitsRestoration(
                to: .init(accountID: account, chatID: 100, clientID: 12, topic: nil), currentSource: source,
            ), "nil-topic identity rejected")
            var recursive: ChatComposerRestorationTransfer!
            var recursiveAccepted = false
            recursive = ChatComposerRestorationTransfer(snapshot: state) {
                recursive.cancel()
                recursiveAccepted = recursive.commit(to: next, currentSource: source, construct: { _ in true }) != nil
                return true
            }
            try require(
                recursive.commit(to: next, currentSource: source, construct: { _ in true }) == true
                && !recursiveAccepted,
                "reentrant cancel interrupted atomic transfer or commit accepted twice",
            )
            try require(
                recursive.commit(to: next, currentSource: source, construct: { _ in true }) == nil,
                "reentrant cancel restored a consumed transfer",
            )
        }

        private static func snapshot(
            root: URL,
            location: ChatLocation,
            message: CustomMessage,
        ) throws -> ChatComposerRestorationState {
            let file = root.appendingPathComponent("\(UUID().uuidString)-document.txt")
            try Data("isolated selected attachment".utf8).write(to: file)
            let formatted = FormattedText(entities: [
                .init(length: 4, offset: 0, type: .textEntityTypeBold),
                .init(length: 6, offset: 5, type: .textEntityTypeSpoiler),
            ], text: "bold secret")
            return ChatComposerRestorationState(
                location: location, revision: 7, text: getAttributedString(from: formatted),
                edit: .init(target: .init(message), text: ""),
                replyMessage: .init(message),
                replyTo: .inputMessageReplyToExternalMessage(.init(
                    chatId: 200, checklistTaskId: 0, messageId: 42, pollOptionId: "",
                    quote: .init(position: 3, text: formatted),
                )),
                images: [.init(image: UIImage(), url: root.appendingPathComponent("selected.jpg"))],
                documents: [.init(id: UUID(), name: "document.txt", size: 27, url: file)],
                sendError: "Check the chat before retrying.", draftError: "Preserved draft error",
            )
        }

        private static func messageFixture(text: String = "edit target") -> Message {
            Message(
                authorSignature: "", autoDeleteIn: 0, canBeSaved: true, chatId: 100,
                containsUnreadMention: false, containsUnreadPollVotes: false,
                content: .messageText(.init(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: .init(entities: [], text: text),
                )),
                date: 1, editDate: 0, effectId: 0, ephemeralMessageId: 0, factCheck: nil,
                forwardInfo: nil, guestBotCallerId: nil, hasTimestampedMedia: false, id: 42,
                importInfo: nil, interactionInfo: nil, isChannelPost: false, isFromOffline: false,
                isOutgoing: true, isPaidGramSuggestedPost: false, isPaidStarSuggestedPost: false,
                isPinned: false, mediaAlbumId: 0, paidMessageStarCount: 0, receiverId: nil,
                replyMarkup: nil, replyTo: nil, restrictionInfo: nil, schedulingState: nil,
                selfDestructIn: 0, selfDestructType: nil, senderBoostCount: 0, senderBusinessBotUserId: 0,
                senderId: .messageSenderUser(.init(userId: 1)), senderTag: "", sendingState: nil,
                suggestedPostInfo: nil, summaryLanguageCode: "", topicId: nil, unreadReactions: [], viaBotUserId: 0,
            )
        }
    }
#endif
