// TdUpdateSourceProbe.swift

#if DEBUG
    import Combine
    import Foundation
    import TDLibKitDynamic

    /// Exercises the generated dispatcher and production transport with isolated sinks.
    /// It never switches the real account, opens TDLib, or touches a draft/file store.
    @MainActor enum TdUpdateSourceProbe {
        private enum ProbeFailure: Swift.Error {
            case check(String)
        }

        private enum Kind: Hashable {
            case success
            case failure
            case deletion
        }

        private final class ProbeState {
            var location: ChatLocation
            var ownedIDs: [UUID: Set<Int64>]
            var durableActions = 0
            var legacy = [Kind: Int]()
            var scoped = [Kind: Int]()
            var ui = [Kind: Int]()
            var rawPayloadsPreserved = true

            init(location: ChatLocation, accountIDs: [UUID]) {
                self.location = location
                self.ownedIDs = Dictionary(uniqueKeysWithValues: accountIDs.map { ($0, Set([-11, -12, -13])) })
            }

            func consume(
                _ kind: Kind,
                source: TdUpdateSource,
                chatID: Int64,
                removedIDs: [Int64],
                replacementID: Int64? = nil,
                permitted: Bool = true,
            ) {
                scoped[kind, default: 0] += 1
                guard permitted, chatID == location.chatID else { return }
                durableActions += 1
                ownedIDs[source.accountID]?.subtract(removedIDs)
                if let replacementID {
                    ownedIDs[source.accountID]?.insert(replacementID)
                }
                if source.matches(location) {
                    ui[kind, default: 0] += 1
                }
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-update-source") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "TD update source probe: generated-dispatch=true, delayed-a-to-b=true, "
                        + "colliding-ids-isolated=true, old-client-ui-rejected=true, "
                        + "old-client-durable-account-preserved=true, unscoped-rejected=true, "
                        + "legacy-raw-exactly-once=true, permanent-delete-guards=true, user-stores-untouched=true"
                } catch {
                    result = "TD update source probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("update-source-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func verify() async throws {
            let center = NotificationCenter()
            var subscriptions = Set<AnyCancellable>()
            defer { subscriptions.removeAll() }
            let sourceA = TdUpdateSource(accountID: UUID(), clientID: 11)
            let sourceB = TdUpdateSource(accountID: UUID(), clientID: 22)
            let oldSourceB = TdUpdateSource(accountID: sourceB.accountID, clientID: 21)
            let chatID = Int64.min + 101
            let locationA = ChatLocation(accountID: sourceA.accountID, chatID: chatID, clientID: 11, topic: nil)
            let locationB = ChatLocation(accountID: sourceB.accountID, chatID: chatID, clientID: 22, topic: nil)
            let state = ProbeState(location: locationA, accountIDs: [sourceA.accountID, sourceB.accountID])
            let message = makeMessage(chatID: chatID)
            let success = UpdateMessageSendSucceeded(message: message, oldMessageId: -11)
            let failure = UpdateMessageSendFailed(
                error: .init(code: 400, message: "probe"),
                message: message,
                oldMessageId: -12,
            )
            let deletion = UpdateDeleteMessages(chatId: chatID, fromCache: false, isPermanent: true, messageIds: [-13])

            center.publisher(&subscriptions, for: .updateMessageSendSucceeded) { value in
                state.legacy[.success, default: 0] += 1
                state.rawPayloadsPreserved = state.rawPayloadsPreserved && value == success
            }
            center.publisher(&subscriptions, for: .updateMessageSendFailed) { value in
                state.legacy[.failure, default: 0] += 1
                state.rawPayloadsPreserved = state.rawPayloadsPreserved && value == failure
            }
            center.publisher(&subscriptions, for: .updateDeleteMessages) { value in
                state.legacy[.deletion, default: 0] += 1
                state.rawPayloadsPreserved = state.rawPayloadsPreserved
                    && value.chatId == chatID && value.messageIds == [-13]
            }
            center.scopedPublisher(&subscriptions, for: .updateMessageSendSucceeded) { event in
                state.consume(
                    .success,
                    source: event.source,
                    chatID: event.value.message.chatId,
                    removedIDs: [event.value.oldMessageId],
                )
            }
            center.scopedPublisher(&subscriptions, for: .updateMessageSendFailed) { event in
                state.consume(
                    .failure,
                    source: event.source,
                    chatID: event.value.message.chatId,
                    removedIDs: [event.value.oldMessageId],
                    replacementID: event.value.message.id,
                )
            }
            center.scopedPublisher(&subscriptions, for: .updateDeleteMessages) { event in
                state.consume(
                    .deletion,
                    source: event.source,
                    chatID: event.value.chatId,
                    removedIDs: event.value.messageIds,
                    permitted: !event.value.fromCache && event.value.isPermanent,
                )
            }

            func postOutcomes(source: TdUpdateSource?) {
                update(.updateMessageSendSucceeded(success), source: source, notificationCenter: center)
                update(.updateMessageSendFailed(failure), source: source, notificationCenter: center)
                update(.updateDeleteMessages(deletion), source: source, notificationCenter: center)
            }

            postOutcomes(source: sourceA)
            for flags in [(true, true), (false, false)] {
                update(
                    .updateDeleteMessages(.init(
                        chatId: chatID,
                        fromCache: flags.0,
                        isPermanent: flags.1,
                        messageIds: [-13],
                    )),
                    source: sourceA,
                    notificationCenter: center,
                )
            }
            guard state.scoped.isEmpty, state.legacy.isEmpty else {
                throw ProbeFailure.check("subscriber delivery was not delayed")
            }
            state.location = locationB
            await drainMainQueue()
            guard state.ownedIDs[sourceA.accountID] == [-32],
                  state.ownedIDs[sourceB.accountID] == [-11, -12, -13],
                  state.ui.isEmpty,
                  state.durableActions == 3,
                  state.scoped == [.success: 1, .failure: 1, .deletion: 3]
            else { throw ProbeFailure.check("delayed A outcome mutated B or ignored delete guards") }

            // Old and current clients share the account but only the current one owns its UI.
            postOutcomes(source: oldSourceB)
            postOutcomes(source: sourceB)
            postOutcomes(source: nil)
            await drainMainQueue()
            guard state.ownedIDs[sourceA.accountID] == [-32],
                  state.ownedIDs[sourceB.accountID] == [-32],
                  state.ui == [.success: 1, .failure: 1, .deletion: 1],
                  state.durableActions == 9,
                  state.scoped == [.success: 3, .failure: 3, .deletion: 5],
                  state.legacy == [.success: 4, .failure: 4, .deletion: 6],
                  state.rawPayloadsPreserved
            else { throw ProbeFailure.check("client/unscoped/legacy delivery contract") }
        }

        private static func drainMainQueue() async {
            // Every receive(on:) delivery above was enqueued before this FIFO barrier.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }

        private static func makeMessage(chatID: Int64) -> Message {
            Message(
                authorSignature: "",
                autoDeleteIn: 0,
                canBeSaved: true,
                chatId: chatID,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                content: .messageText(.init(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: .init(entities: [], text: "isolated transport probe"),
                )),
                date: 0,
                editDate: 0,
                effectId: 0,
                ephemeralMessageId: 0,
                factCheck: nil,
                forwardInfo: nil,
                guestBotCallerId: nil,
                hasTimestampedMedia: false,
                id: -32,
                importInfo: nil,
                interactionInfo: nil,
                isChannelPost: false,
                isFromOffline: false,
                isOutgoing: true,
                isPaidGramSuggestedPost: false,
                isPaidStarSuggestedPost: false,
                isPinned: false,
                mediaAlbumId: 0,
                paidMessageStarCount: 0,
                receiverId: nil,
                replyMarkup: nil,
                replyTo: nil,
                restrictionInfo: nil,
                schedulingState: nil,
                selfDestructIn: 0,
                selfDestructType: nil,
                senderBoostCount: 0,
                senderBusinessBotUserId: 0,
                senderId: .messageSenderUser(.init(userId: 1)),
                senderTag: "",
                sendingState: nil,
                suggestedPostInfo: nil,
                summaryLanguageCode: "",
                topicId: nil,
                unreadReactions: [],
                viaBotUserId: 0,
            )
        }
    }
#endif
