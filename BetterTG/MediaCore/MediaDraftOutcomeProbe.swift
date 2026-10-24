// MediaDraftOutcomeProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    enum MediaDraftOutcomeProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-draft-outcomes") else { return }
            Task {
                let root = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("draft-outcomes-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: root) }
                    try await verify(VoiceNoteDraftStore.self, root: root.appendingPathComponent("voice"))
                    try await verify(VideoNoteFileStore.self, root: root.appendingPathComponent("video"))
                    try await verifyAccountPurge(root: root.appendingPathComponent("purge"))
                    result = "Media draft outcome probe passed: voice+video; ordinary/explicit/all-messages "
                        + "early+late success/failure; original-route; wrong-account/chat/topic/tempID; "
                        + "route+delivery-gates; ambiguous-persisted-enqueues/IDs; exact-ID-relaunch; "
                        + "pre-registration-crash-retained; legacy-base-route; unrelated-draft/file-preserved; "
                        + "isolated-stores=true; logout-purges-only-its-account=true"
                } catch {
                    result = "Media draft outcome probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("draft-outcomes-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ label: String) throws {
            guard condition else { throw Failure(description: label) }
        }

        /// Logging out one account removes its voice drafts and leaves another account's.
        private static func verifyAccountPurge(root: URL) async throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = VoiceNoteDraftStore(
                directoryURL: root.appendingPathComponent("drafts"),
                legacyBindingAllowed: { _ in false },
            )
            let loggedOut = ChatDraftKey(accountID: UUID(), chatID: 100, topic: nil)
            let remaining = ChatDraftKey(accountID: UUID(), chatID: 100, topic: nil)
            _ = try await store.probeAdopt(route: loggedOut, sendTopic: nil, root: root)
            _ = try await store.probeAdopt(route: remaining, sendTopic: nil, root: root)
            guard let loggedOutAccount = loggedOut.accountID else { throw Failure(description: "purge setup") }
            await store.discardAccount(loggedOutAccount)
            try await require(store.drafts(for: loggedOut, migrateLegacy: false).isEmpty, "purge removed")
            try await require(store.drafts(for: remaining, migrateLegacy: false).count == 1, "purge kept other")
        }

        private static func verify<Store: MediaDraftProbeStore>(_ type: Store.Type, root: URL) async throws {
            var stage = "setup"
            do {
                try await verifyCases(type, root: root) { stage = $0 }
            } catch {
                throw Failure(description: "\(Store.self) \(stage): \(error)")
            }
        }

        private static func verifyCases<Store: MediaDraftProbeStore>(
            _ type: Store.Type, root: URL, markStage: (String) -> Void,
        ) async throws {
            let accountID = UUID()
            let chatID = Int64(100)
            let topic = MessageTopic.messageTopicForum(.init(forumTopicId: 42))
            let otherTopic = MessageTopic.messageTopicForum(.init(forumTopicId: 43))
            let base = ChatDraftKey(accountID: accountID, chatID: chatID, topic: nil)
            let topicRoute = ChatDraftKey(accountID: accountID, chatID: chatID, topic: topic)
            let routes: [(String, ChatDraftKey, MessageTopic?, MessageTopic?)] = [
                ("ordinary", base, nil, nil),
                ("explicit", topicRoute, nil, topic),
                ("all-messages", base, topic, topic),
            ]
            let sentinel = root.appendingPathComponent("unrelated.keep")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data([9, 8, 7]).write(to: sentinel)

            for (name, route, sendTopic, deliveredTopic) in routes {
                for early in [false, true] {
                    for succeeds in [false, true] {
                        let label = "\(Store.self) \(name) early=\(early) success=\(succeeds)"
                        markStage("\(label) adopt-primary")
                        let directory = root.appendingPathComponent(UUID().uuidString)
                        let store = type.init(directoryURL: directory, legacyBindingAllowed: { _ in false })
                        let adopted = try await store.probeAdopt(route: route, sendTopic: sendTopic, root: root)
                        markStage("\(label) adopt-unrelated")
                        let unrelatedRoute = ChatDraftKey(accountID: UUID(), chatID: chatID, topic: deliveredTopic)
                        let unrelated = try await store.probeAdopt(route: unrelatedRoute, sendTopic: nil, root: root)
                        markStage("\(label) begin-enqueue")
                        let draft = try await store.beginEnqueue(adopted)
                        let delivery = ChatDraftDeliveryKey(accountID: accountID, chatID: chatID, topic: deliveredTopic)
                        try require(draft.deliveryKey == delivery, "\(label): delivery key")
                        if early {
                            markStage("\(label) early-outcome")
                            let resolution = try await store.probeOutcome(delivery, id: -101, succeeds: succeeds)
                            try require(resolution == nil, "\(label): early outcome consumed before registration")
                        }
                        markStage("\(label) register")
                        let registration = try await store.probeRegister(draft, id: -101)
                        let resolved: Store.Draft?
                        if early {
                            try require(registration.outcome == succeeds, "\(label): exact early outcome")
                            resolved = registration.draft
                        } else {
                            markStage("\(label) late-outcome")
                            try require(registration.outcome == nil, "\(label): unexpected registration outcome")
                            resolved = try await store.probeOutcome(delivery, id: -101, succeeds: succeeds)
                        }
                        try require(resolved?.destination == route, "\(label): original UI route changed")
                        try require(resolved?.id == draft.id, "\(label): wrong draft")
                        try require(
                            FileManager.default
                                .fileExists(atPath: draft.fileURL.path) == (!succeeds || Store.keepsSentFile),
                            "\(label): file ownership",
                        )
                        if !succeeds {
                            try require(
                                resolved?.probeFailureID == 901 && resolved?.temporaryMessageID == nil,
                                "\(label): retry state",
                            )
                        }
                        markStage("\(label) relaunch")
                        let relaunched = type.init(directoryURL: directory, legacyBindingAllowed: { _ in false })
                        let restored = await relaunched.drafts(for: route, migrateLegacy: false)
                        try require(restored.count == (succeeds ? 0 : 1), "\(label): relaunch")
                        let other = await relaunched.drafts(for: unrelatedRoute, migrateLegacy: false)
                        try require(
                            other.map(\.id) == [unrelated.id]
                            && FileManager.default.fileExists(atPath: unrelated.fileURL.path),
                            "\(label): unrelated draft removed",
                        )
                    }
                }
            }

            let delivery = ChatDraftDeliveryKey(accountID: accountID, chatID: chatID, topic: topic)
            let invalidDeliveries = [
                ChatDraftDeliveryKey(accountID: UUID(), chatID: chatID, topic: topic),
                ChatDraftDeliveryKey(accountID: accountID, chatID: chatID + 1, topic: topic),
                ChatDraftDeliveryKey(accountID: accountID, chatID: chatID, topic: otherTopic),
                ChatDraftDeliveryKey(accountID: accountID, chatID: chatID, topic: nil),
            ]
            for early in [false, true] {
                markStage("invalid-delivery early=\(early)")
                let directory = root.appendingPathComponent(UUID().uuidString)
                let store = type.init(directoryURL: directory, legacyBindingAllowed: { _ in false })
                let adopted = try await store.probeAdopt(route: base, sendTopic: topic, root: root)
                let draft = try await store.beginEnqueue(adopted)
                if !early { _ = try await store.probeRegister(draft, id: -201) }
                for succeeds in [false, true] {
                    for invalid in invalidDeliveries {
                        let resolution = try await store.probeOutcome(invalid, id: -201, succeeds: succeeds)
                        try require(resolution == nil, "\(Store.self): wrong delivery accepted")
                    }
                    let wrongID = try await store.probeOutcome(delivery, id: -299, succeeds: succeeds)
                    try require(wrongID == nil, "\(Store.self): wrong temporary ID resolved")
                }
                if early {
                    let registration = try await store.probeRegister(draft, id: -201)
                    try require(registration.outcome == nil, "\(Store.self): arbitrary other-ID fallback")
                }
                let relaunched = type.init(directoryURL: directory, legacyBindingAllowed: { _ in false })
                let drafts = await relaunched.drafts(for: base, migrateLegacy: false)
                try require(
                    drafts.count == 1 && drafts[0].temporaryMessageID == -201
                    && drafts[0].probeFailureID == nil && FileManager.default.fileExists(atPath: draft.fileURL.path),
                    "\(Store.self): invalid outcome mutated registered draft",
                )
            }

            markStage("route/delivery enqueue gates")
            let gateDirectory = root.appendingPathComponent(UUID().uuidString)
            let gateStore = type.init(directoryURL: gateDirectory, legacyBindingAllowed: { _ in false })
            let first = try await gateStore.probeAdopt(route: base, sendTopic: topic, root: root)
            _ = try await gateStore.beginEnqueue(first)
            for (route, sendTopic) in [(topicRoute, MessageTopic?.none), (base, Optional(otherTopic))] {
                let conflicting = try await gateStore.probeAdopt(route: route, sendTopic: sendTopic, root: root)
                var rejected = false
                do {
                    _ = try await gateStore.beginEnqueue(conflicting)
                } catch {
                    rejected = true
                }
                try require(rejected, "\(Store.self): route or delivery enqueue gate missing")
            }
            let otherAccount = ChatDraftKey(accountID: UUID(), chatID: chatID, topic: topic)
            let independent = try await gateStore.probeAdopt(route: otherAccount, sendTopic: nil, root: root)
            _ = try await gateStore.beginEnqueue(independent)

            // Write old-version manifests directly: current beginEnqueue deliberately rejects this state.
            for duplicateID in [false, true] {
                markStage("ambiguous persisted candidates duplicateID=\(duplicateID)")
                let directory = root.appendingPathComponent(UUID().uuidString)
                let store = type.init(directoryURL: directory, legacyBindingAllowed: { _ in false })
                var first = try await store.probeAdopt(route: base, sendTopic: topic, root: root)
                var second = try await store.probeAdopt(route: topicRoute, sendTopic: nil, root: root)
                first.enqueueStartedAt = duplicateID ? nil : Foundation.Date()
                second.enqueueStartedAt = first.enqueueStartedAt
                first.temporaryMessageID = duplicateID ? -301 : nil
                second.temporaryMessageID = first.temporaryMessageID
                try writeManifest(first, in: directory)
                try writeManifest(second, in: directory)
                for succeeds in [false, true] {
                    let resolution = try await store.probeOutcome(delivery, id: -301, succeeds: succeeds)
                    try require(resolution == nil, "\(Store.self): ambiguous persisted candidates resolved")
                }
                let outcomeFiles = try FileManager.default
.contentsOfDirectory(atPath: directory.path)
                    .filter { $0.hasPrefix("outcome_") }
                try require(
                    outcomeFiles.isEmpty && FileManager.default.fileExists(atPath: first.fileURL.path)
                    && FileManager.default.fileExists(atPath: second.fileURL.path),
                    "\(Store.self): ambiguous candidates produced evidence or cleanup",
                )
            }

            for succeeds in [false, true] {
                for matchesID in [false, true] {
                    for persistedRegistration in [false, true] {
                        let label = "\(Store.self) crash success=\(succeeds) exact=\(matchesID) registered=\(persistedRegistration)"
                        markStage(label)
                        let directory = root.appendingPathComponent(UUID().uuidString)
                        let store = type.init(directoryURL: directory, legacyBindingAllowed: { _ in false })
                        let adopted = try await store.probeAdopt(route: base, sendTopic: topic, root: root)
                        var draft = try await store.beginEnqueue(adopted)
                        _ = try await store.probeOutcome(delivery, id: -401, succeeds: succeeds)
                        let actualID = Int64(matchesID ? -401 : -402)
                        if persistedRegistration {
                            // Simulate a crash after the actual ID save but before outcome cleanup.
                            draft.enqueueStartedAt = nil
                            draft.temporaryMessageID = actualID
                            try writeManifest(draft, in: directory)
                        }
                        let relaunched = type.init(directoryURL: directory, legacyBindingAllowed: { _ in false })
                        let restored = await relaunched.drafts(for: base, migrateLegacy: false)
                        if persistedRegistration, matchesID {
                            try require(restored.count == (succeeds ? 0 : 1), "\(label): exact crash recovery")
                            try require(
                                FileManager.default
                                    .fileExists(atPath: draft.fileURL.path) == (!succeeds || Store.keepsSentFile),
                                "\(label): exact recovery file ownership",
                            )
                            if !succeeds {
                                try require(restored.first?.probeFailureID == 901, "\(label): failure recovery")
                            }
                        } else {
                            try require(
                                restored.count == 1 && restored[0].probeFailureID == nil
                                && FileManager.default.fileExists(atPath: draft.fileURL.path),
                                "\(label): unresolved crash lost draft or file",
                            )
                            if !persistedRegistration {
                                try require(
                                    restored[0].enqueueStartedAt != nil && restored[0].temporaryMessageID == nil,
                                    "\(label): unregistered enqueue guessed an outcome",
                                )
                                let registration = try await relaunched.probeRegister(restored[0], id: actualID)
                                try require(
                                    registration.outcome == (matchesID ? succeeds : nil),
                                    "\(label): exact registration after relaunch",
                                )
                            }
                        }
                    }
                }
            }

            markStage("legacy account binding")
            let legacyDirectory = root.appendingPathComponent(UUID().uuidString)
            let legacyStore = type.init(directoryURL: legacyDirectory, legacyBindingAllowed: { $0 == base })
            let legacy = try await legacyStore.probeAdopt(route: nil, sendTopic: topic, root: root)
            let legacyEnqueue = try await legacyStore.beginEnqueue(legacy)
            _ = try await legacyStore.probeRegister(legacyEnqueue, id: -501)
            let migrated = try await legacyStore.probeOutcome(delivery, id: -501, succeeds: false, migrateLegacy: true)
            try require(
                migrated?.destination == base && migrated?.probeFailureID == 901,
                "\(Store.self): legacy delivery topic became UI route",
            )
            try require(Data(contentsOf: sentinel) == Data([9, 8, 7]), "\(Store.self): unrelated file removed")
        }

        private static func writeManifest(_ draft: some MediaDraftProbeValue, in directory: URL) throws {
            try JSONEncoder().encode(draft).write(
                to: directory.appendingPathComponent(draft.id.uuidString).appendingPathExtension("json"),
                options: .atomic,
            )
        }
    }

    private protocol MediaDraftProbeValue: ChatDraftSendScoped, Codable {
        var id: UUID { get }
        var fileURL: URL { get }
        var enqueueStartedAt: Foundation.Date? { get set }
        var temporaryMessageID: Int64? { get set }
        var probeFailureID: Int64? { get }
    }

    extension VoiceNoteSendDraft: MediaDraftProbeValue {
        fileprivate var probeFailureID: Int64? { failedSendState?.messageID }
    }

    extension VideoNoteSendDraft: MediaDraftProbeValue {
        fileprivate var probeFailureID: Int64? { failedSendState?.messageID }
    }

    private protocol MediaDraftProbeStore: Actor {
        associatedtype Draft: MediaDraftProbeValue
        init(directoryURL: URL?, legacyBindingAllowed: @escaping @Sendable (ChatDraftKey) -> Bool)
        func probeAdopt(route: ChatDraftKey?, sendTopic: MessageTopic?, root: URL) throws -> Draft
        func beginEnqueue(_ draft: Draft) throws -> Draft
        func probeRegister(_ draft: Draft, id: Int64) async throws -> (draft: Draft, outcome: Bool?)
        func probeOutcome(
            _ delivery: ChatDraftDeliveryKey,
            id: Int64,
            succeeds: Bool,
            migrateLegacy: Bool,
        ) async throws -> Draft?
        func drafts(for route: ChatDraftKey, migrateLegacy: Bool) async -> [Draft]
        /// A sent voice note keeps its uploaded file for the abandoned-file sweep, since the message points at it.
        static var keepsSentFile: Bool { get }
    }

    private extension MediaDraftProbeStore {
        func probeOutcome(_ delivery: ChatDraftDeliveryKey, id: Int64, succeeds: Bool) async throws -> Draft? {
            try await probeOutcome(delivery, id: id, succeeds: succeeds, migrateLegacy: false)
        }

        func probeInput(root: URL, fileExtension: String) throws -> URL {
            let source = root.appendingPathComponent("input-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            try Data([0, 1, 2, 3]).write(to: source, options: .atomic)
            return source
        }
    }

    extension VoiceNoteDraftStore: MediaDraftProbeStore {
        static var keepsSentFile: Bool { true }

        fileprivate func probeAdopt(
            route: ChatDraftKey?,
            sendTopic: MessageTopic?,
            root: URL,
        ) throws -> VoiceNoteSendDraft {
            try adopt(VoiceNoteSendDraft(
                id: UUID(), chatID: route?.chatID ?? 100, caption: .init(entities: [], text: ""),
                createdAt: Foundation.Date(), duration: 1, enqueueStartedAt: nil, failedSendState: nil,
                // Opaque lifecycle bytes still need the production encoded-file
                // extension; an extensionless input is adopted as raw ID.wav.
                fileURL: probeInput(root: root, fileExtension: "ogg"), isEncoded: true,
                replyMessageID: nil, replyTo: nil,
                sendTopic: sendTopic, temporaryMessageID: nil, waveform: Data(), destination: route,
            ))
        }

        fileprivate func probeRegister(
            _ draft: VoiceNoteSendDraft,
            id: Int64,
        ) throws -> (draft: VoiceNoteSendDraft, outcome: Bool?) {
            let result = try registerEnqueued(draft, temporaryMessageID: id)
            return (result.draft, result.outcome.map { $0 == .succeeded })
        }

        fileprivate func probeOutcome(
            _ delivery: ChatDraftDeliveryKey,
            id: Int64,
            succeeds: Bool,
            migrateLegacy: Bool,
        ) throws -> VoiceNoteSendDraft? {
            if succeeds {
                return try handleSendSucceeded(
                    delivery: delivery,
                    temporaryMessageID: id,
                    migrateLegacy: migrateLegacy,
                )?.draft
            }
            return try handleSendFailed(
                delivery: delivery, temporaryMessageID: id,
                failedSendState: .init(
                    canRetry: true,
                    messageID: 901,
                    needAnotherReplyQuote: false,
                    needAnotherSender: false,
                    requiredPaidMessageStarCount: 0,
                    retryAvailableAt: Foundation.Date(),
                ),
                migrateLegacy: migrateLegacy,
            )?.draft
        }
    }

    extension VideoNoteFileStore: MediaDraftProbeStore {
        static var keepsSentFile: Bool { false }

        fileprivate func probeAdopt(
            route: ChatDraftKey?,
            sendTopic: MessageTopic?,
            root: URL,
        ) throws -> VideoNoteSendDraft {
            try adopt(
                .init(duration: 1, length: 400, url: probeInput(root: root, fileExtension: "mp4")),
                chatID: route?.chatID ?? 100, draftKey: route,
                replyMessageID: nil, replyTo: nil, sendTopic: sendTopic,
            )
        }

        fileprivate func probeRegister(
            _ draft: VideoNoteSendDraft,
            id: Int64,
        ) async throws -> (draft: VideoNoteSendDraft, outcome: Bool?) {
            let result = try await registerEnqueued(draft, temporaryMessageID: id)
            return (result.draft, result.outcome.map { $0 == .succeeded })
        }

        fileprivate func probeOutcome(
            _ delivery: ChatDraftDeliveryKey,
            id: Int64,
            succeeds: Bool,
            migrateLegacy: Bool,
        ) async throws -> VideoNoteSendDraft? {
            if succeeds {
                return try await handleSendSucceeded(
                    delivery: delivery,
                    temporaryMessageID: id,
                    migrateLegacy: migrateLegacy,
                )?.draft
            }
            return try handleSendFailed(
                delivery: delivery, temporaryMessageID: id,
                failedSendState: .init(
                    canRetry: true,
                    messageID: 901,
                    needAnotherReplyQuote: false,
                    needAnotherSender: false,
                    requiredPaidMessageStarCount: 0,
                    retryAvailableAt: Foundation.Date(),
                ),
                migrateLegacy: migrateLegacy,
            )?.draft
        }
    }
#endif
