// SendDraftRelocationProbe.swift

#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import TDLibKit
    import UniformTypeIdentifiers

    enum SendDraftRelocationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private actor OriginRemovals {
            var ids = [UUID]()

            func remove(_ id: UUID) -> Bool {
                ids.append(id)
                return true
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-draft-relocation") else { return }
            Task {
                let root = FileManager.default
.temporaryDirectory
                    .appendingPathComponent("draft-relocation-\(UUID().uuidString)", isDirectory: true)
                let result: String
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: root) }
                    for legacy in [false, true] {
                        for copy in [false, true] {
                            try await verifyRelocation(root: root, legacy: legacy, copy: copy)
                        }
                    }
                    try await verifyRejectedReferences(root: root)
                    try await verifyFailedMigration(root: root)
                    try await verifyMissingTombstone(root: root)
                    result = "Send draft relocation probe passed: legacy+relative/move+copy; voice-raw+encoded+token; "
                        + "canonical-before-list/stale-adopt; route/caption/reply/topic/waveform; "
                        + "enqueue/failed/tempID/provisional+registered-outcomes; video-thumbnail/origin/tombstone+missing-media; "
                        + "idempotent; missing/malformed/mismatched/external/traversal/symlink-rejected; "
                        + "retained-manifest-protects-aged-files; migration-write-failure-retained; isolated-stores=true"
                } catch {
                    result = "Send draft relocation probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("draft-relocation-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ label: String) throws {
            guard condition else { throw Failure(description: label) }
        }

        private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        private static func container(in root: URL) throws -> URL {
            let url = root.appendingPathComponent("Containers/Data/Application/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private static func directory(_ name: String, container: URL) -> URL {
            container.appendingPathComponent("Library/Application Support/\(name)", isDirectory: true)
        }

        private static func manifest(_ id: UUID, directory: URL) -> URL {
            directory.appendingPathComponent("\(id.uuidString).json")
        }

        private static func metadata(_ value: some Encodable) throws -> Data {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
            object.removeValue(forKey: "fileURL")
            object.removeValue(forKey: "thumbnailFileURL")
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }

        private static func writeLegacy(_ draft: some Encodable, id: UUID, directory: URL) throws {
            try JSONEncoder().encode(draft).write(to: manifest(id, directory: directory), options: .atomic)
        }

        private static func verifyRelativeManifest(_ id: UUID, directory: URL) throws {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest(id, directory: directory)))
                as! [String: Any]
            for key in ["fileURL", "thumbnailFileURL"] {
                if let reference = object[key] as? String {
                    try require(!reference.contains("/") && !reference.contains(":"), "absolute persisted \(key)")
                }
            }
        }

        private static func source(root: URL, ext: String) throws -> URL {
            let url = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try Data([0, 1, 2, 3, 4]).write(to: url)
            return url
        }

        private static func voice(root: URL, route: ChatDraftKey, encoded: Bool) throws -> VoiceNoteSendDraft {
            try VoiceNoteSendDraft(
                id: UUID(), chatID: route.chatID,
                caption: .init(
                    entities: [.init(length: 4, offset: 0, type: .textEntityTypeBold)],
                    text: "keep caption",
                ),
                createdAt: Foundation.Date(timeIntervalSince1970: 100), duration: 3,
                enqueueStartedAt: nil, failedSendState: nil,
                fileURL: source(root: root, ext: encoded ? "ogg" : "wav"), isEncoded: encoded,
                replyMessageID: 42,
                replyTo: .inputMessageReplyToMessage(.init(
                    checklistTaskId: 0,
                    messageId: 42,
                    pollOptionId: "",
                    quote: nil,
                )),
                sendTopic: .messageTopicForum(.init(forumTopicId: 99)), temporaryMessageID: nil,
                waveform: Data([1, 2, 3]), destination: route,
            )
        }

        private static func video(
            store: VideoNoteFileStore, root: URL, route: ChatDraftKey, origin: UUID? = nil,
        ) async throws -> VideoNoteSendDraft {
            let thumbnail = root.appendingPathComponent("\(UUID().uuidString).jpg")
            try writeThumbnail(to: thumbnail)
            return try await store.adopt(
                .init(duration: 3, length: 400, url: source(root: root, ext: "mp4")),
                thumbnail: .init(height: 16, url: thumbnail, width: 16),
                chatID: route.chatID, draftKey: route, originRecordingDraftID: origin,
                replyMessageID: 42,
                replyTo: .inputMessageReplyToMessage(.init(
                    checklistTaskId: 0,
                    messageId: 42,
                    pollOptionId: "",
                    quote: nil,
                )),
                sendTopic: .messageTopicForum(.init(forumTopicId: 99)),
            )
        }

        private static func verifyRelocation(root: URL, legacy: Bool, copy: Bool) async throws {
            let fixtureRoot = root.appendingPathComponent(UUID().uuidString)
            let oldContainer = try container(in: fixtureRoot)
            let newContainer = oldContainer.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            let oldVoice = directory("VoiceNoteDrafts", container: oldContainer)
            let oldVideo = directory("VideoNoteDrafts", container: oldContainer)
            let voiceStore = VoiceNoteDraftStore(directoryURL: oldVoice, legacyBindingAllowed: { _ in false })
            let videoStore = VideoNoteFileStore(
                directoryURL: oldVideo, legacyBindingAllowed: { _ in false }, discardRecordingDraft: { _ in false },
            )
            let route = ChatDraftKey(accountID: UUID(), chatID: 100, topic: nil)
            let raw = try await voiceStore.adopt(voice(root: root, route: route, encoded: false))
            let claim = try await voiceStore.claimFinalization(voice(root: root, route: route, encoded: false))
            let encoded = try await voiceStore.replaceFile(
                in: claim.draft, with: source(root: root, ext: "ogg"), finalization: claim.lease,
            )
            await voiceStore.finishFinalization(claim.lease)
            let failedVoice = try await voiceStore.markPending(encoded, failedSendState: .init(
                canRetry: false, messageID: -8, needAnotherReplyQuote: true, needAnotherSender: true,
                requiredPaidMessageStarCount: 7, retryAvailableAt: Foundation.Date(timeIntervalSince1970: 999),
            ))
            let registeredVoice = try await voiceStore.registerEnqueued(
                voiceStore.beginEnqueue(voiceStore.adopt(voice(root: root, route: route, encoded: true))),
                temporaryMessageID: -11,
            )
.draft
            let waitingVoice = try await voiceStore.beginEnqueue(
                voiceStore.adopt(voice(root: root, route: route, encoded: true)),
            )
            _ = try await voiceStore.handleSendSucceeded(delivery: waitingVoice.deliveryKey, temporaryMessageID: -12)
            let voices = [raw, failedVoice, registeredVoice, waitingVoice]

            let videoOrigin = UUID()
            let pendingVideo = try await video(store: videoStore, root: root, route: route, origin: videoOrigin)
            let failedVideo = try await videoStore.markPending(pendingVideo, failedSendState: .init(
                canRetry: true, messageID: -21, needAnotherReplyQuote: false, needAnotherSender: false,
                requiredPaidMessageStarCount: 0, retryAvailableAt: Foundation.Date(timeIntervalSince1970: 999),
            ))
            let registeredVideo = try await videoStore.registerEnqueued(
                videoStore.beginEnqueue(video(store: videoStore, root: root, route: route)), temporaryMessageID: -22,
            )
.draft
            let waitingVideo = try await videoStore.beginEnqueue(video(store: videoStore, root: root, route: route))
            _ = try await videoStore.handleSendSucceeded(delivery: waitingVideo.deliveryKey, temporaryMessageID: -23)
            let tombstoneOrigin = UUID()
            var tombstone = try await video(store: videoStore, root: root, route: route, origin: tombstoneOrigin)
            try await require(!videoStore.remove(tombstone), "tombstone fixture removed")
            tombstone = try JSONDecoder().decode(
                VideoNoteSendDraft.self, from: Data(contentsOf: manifest(tombstone.id, directory: oldVideo)),
            )
            tombstone.fileURL = oldVideo.appendingPathComponent(tombstone.fileURL.lastPathComponent)
            tombstone.thumbnailFileURL = tombstone.thumbnailFileURL
                .map { oldVideo.appendingPathComponent($0.lastPathComponent) }
            let videos = [failedVideo, registeredVideo, waitingVideo, tombstone]
            for draft in voices {
                try verifyRelativeManifest(draft.id, directory: oldVoice)
                if legacy { try writeLegacy(draft, id: draft.id, directory: oldVoice) }
            }
            for draft in videos {
                try verifyRelativeManifest(draft.id, directory: oldVideo)
                if legacy { try writeLegacy(draft, id: draft.id, directory: oldVideo) }
            }
            if copy {
                try FileManager.default.copyItem(at: oldContainer, to: newContainer)
            } else {
                try FileManager.default.moveItem(at: oldContainer, to: newContainer)
            }
            let newVoice = directory("VoiceNoteDrafts", container: newContainer)
            let newVideo = directory("VideoNoteDrafts", container: newContainer)
            let restoredVoice = VoiceNoteDraftStore(directoryURL: newVoice, legacyBindingAllowed: { _ in false })
            let removals = OriginRemovals()
            let restoredVideo = VideoNoteFileStore(
                directoryURL: newVideo, legacyBindingAllowed: { _ in false },
                discardRecordingDraft: { await removals.remove($0) },
            )
            // The A14 single-ID/canonical route must work before enumeration has migrated anything.
            let status = await restoredVoice.status(id: failedVoice.id, destination: route)
            try require(status.draft?.fileURL.deletingLastPathComponent() == newVoice, "canonical single load")
            let adopted = try await restoredVoice.adopt(failedVoice)
            try require(adopted.fileURL == status.draft?.fileURL, "stale UI adoption after relocation")
            let restoredVoices = await restoredVoice.drafts(for: route)
            try require(restoredVoices.count == voices.count, "voice count legacy=\(legacy) copy=\(copy)")
            for old in voices {
                guard let draft = restoredVoices.first(where: { $0.id == old.id })
                    else { throw Failure(description: "voice ID") }
                try require(metadata(draft) == metadata(old), "voice metadata")
                try require(draft.fileURL.deletingLastPathComponent() == newVoice, "voice destination root")
                try require(Data(contentsOf: draft.fileURL) == Data([0, 1, 2, 3, 4]), "voice bytes")
                try verifyRelativeManifest(draft.id, directory: newVoice)
            }
            let origins = try await restoredVideo.recordingDraftOrigins()
            try require(origins == [videoOrigin, tombstoneOrigin], "consumed recording origins")
            let restoredVideos = await restoredVideo.drafts(for: route)
            try require(restoredVideos.count == videos.count - 1, "video count")
            try await require(removals.ids == [tombstoneOrigin], "tombstone origin cleanup")
            try require(
                !exists(newVideo.appendingPathComponent(tombstone.fileURL.lastPathComponent)),
                "tombstone file cleanup",
            )
            try require(!exists(manifest(tombstone.id, directory: newVideo)), "tombstone manifest cleanup")
            for old in videos where old.id != tombstone.id {
                guard let draft = restoredVideos.first(where: { $0.id == old.id })
                    else { throw Failure(description: "video ID") }
                try require(metadata(draft) == metadata(old), "video metadata")
                try require(draft.fileURL.deletingLastPathComponent() == newVideo, "video destination root")
                try require(draft.thumbnailFileURL?.deletingLastPathComponent() == newVideo, "thumbnail root")
                try await require(restoredVideo.inputThumbnail(for: draft) != nil, "thumbnail validation")
                try verifyRelativeManifest(draft.id, directory: newVideo)
            }
            let beforeVoice = try Data(contentsOf: manifest(raw.id, directory: newVoice))
            let beforeVideo = try Data(contentsOf: manifest(failedVideo.id, directory: newVideo))
            _ = await restoredVoice.drafts(for: route)
            _ = await restoredVideo.drafts(for: route)
            try require(Data(contentsOf: manifest(raw.id, directory: newVoice)) == beforeVoice, "voice idempotence")
            try require(
                Data(contentsOf: manifest(failedVideo.id, directory: newVideo)) == beforeVideo,
                "video idempotence",
            )
            guard let currentVoice = restoredVoices.first(where: { $0.id == waitingVoice.id }),
                  let currentVideo = restoredVideos.first(where: { $0.id == waitingVideo.id })
            else { throw Failure(description: "provisional enqueue missing") }
            try await require(
                restoredVoice.registerEnqueued(currentVoice, temporaryMessageID: -12).outcome == .succeeded,
                "voice outcome after move",
            )
            try await require(
                restoredVideo.registerEnqueued(currentVideo, temporaryMessageID: -23).outcome == .succeeded,
                "video outcome after move",
            )
            // A sent voice note keeps its uploaded file for the abandoned-file sweep; a video note's file goes.
            try require(exists(currentVoice.fileURL) && !exists(currentVideo.fileURL), "resolved local file ownership")
            if copy {
                try require(
                    exists(waitingVoice.fileURL) && exists(waitingVideo.fileURL) && exists(tombstone.fileURL),
                    "unrelated old copy modified",
                )
            }
            // Exact registered outcomes on the next launch must use rebased files too.
            let failure = VoiceNoteFailedSendState(
                canRetry: true, messageID: -11, needAnotherReplyQuote: false, needAnotherSender: false,
                requiredPaidMessageStarCount: 0, retryAvailableAt: Foundation.Date(timeIntervalSince1970: 12),
            )
            try writeOutcome(
                id: registeredVoice.id,
                temporaryID: -11,
                outcome: "failed",
                failure: failure,
                directory: newVoice,
            )
            try writeOutcome(
                id: registeredVideo.id,
                temporaryID: -22,
                outcome: "succeeded",
                failure: VideoNoteFailedSendState?.none,
                directory: newVideo,
            )
            let nextVoices = await restoredVoice.drafts(for: route)
            let nextVideos = await restoredVideo.drafts(for: route)
            try require(
                nextVoices.first(where: { $0.id == registeredVoice.id })?.failedSendState?.messageID == -11,
                "registered voice outcome",
            )
            try require(!nextVideos.contains(where: { $0.id == registeredVideo.id }), "registered video outcome")
        }

        private static func writeOutcome(
            id: UUID, temporaryID: Int64, outcome: String, failure: (some Encodable)?, directory: URL,
        ) throws {
            var object: [String: Any] = ["draftID": id.uuidString, "outcome": outcome]
            if let failure {
                object["failedSendState"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(failure))
            }
            try JSONSerialization.data(withJSONObject: object).write(
                to: directory.appendingPathComponent("outcome_\(id.uuidString)_\(temporaryID).json"), options: .atomic,
            )
        }

        private static func verifyFailedMigration(root: URL) async throws {
            let fixture = root.appendingPathComponent(UUID().uuidString)
            let oldContainer = try container(in: fixture)
            let newContainer = oldContainer.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            let oldVoice = directory("VoiceNoteDrafts", container: oldContainer)
            let oldVideo = directory("VideoNoteDrafts", container: oldContainer)
            let route = ChatDraftKey(accountID: UUID(), chatID: 100, topic: nil)
            let voiceStore = VoiceNoteDraftStore(directoryURL: oldVoice, legacyBindingAllowed: { _ in false })
            let videoStore = VideoNoteFileStore(directoryURL: oldVideo, legacyBindingAllowed: { _ in false })
            let raw = try await voiceStore.adopt(voice(root: root, route: route, encoded: false))
            let clip = try await video(store: videoStore, root: root, route: route)
            try writeLegacy(raw, id: raw.id, directory: oldVoice)
            try writeLegacy(clip, id: clip.id, directory: oldVideo)
            try FileManager.default.moveItem(at: oldContainer, to: newContainer)
            let newVoice = directory("VoiceNoteDrafts", container: newContainer)
            let newVideo = directory("VideoNoteDrafts", container: newContainer)
            let voiceJSON = try Data(contentsOf: manifest(raw.id, directory: newVoice))
            let videoJSON = try Data(contentsOf: manifest(clip.id, directory: newVideo))
            let deniedVoice = VoiceNoteDraftStore(
                directoryURL: newVoice, legacyBindingAllowed: { _ in false },
                writeManifest: { _, _ in throw CocoaError(.fileWriteNoPermission) },
            )
            let deniedVideo = VideoNoteFileStore(
                directoryURL: newVideo, legacyBindingAllowed: { _ in false },
                writeManifest: { _, _ in throw CocoaError(.fileWriteNoPermission) },
                discardRecordingDraft: nil,
            )
            try await require(
                deniedVoice.status(id: raw.id, destination: route).draft != nil,
                "migration failure blocked canonical load",
            )
            try await require(deniedVoice.drafts(for: route).map(\.id) == [raw.id], "migration failure hid voice")
            try await require(deniedVideo.drafts(for: route).map(\.id) == [clip.id], "migration failure hid video")
            try require(
                Data(contentsOf: manifest(raw.id, directory: newVoice)) == voiceJSON,
                "failed voice migration replaced JSON",
            )
            try require(
                Data(contentsOf: manifest(clip.id, directory: newVideo)) == videoJSON,
                "failed video migration replaced JSON",
            )
        }

        private static func verifyRejectedReferences(root: URL) async throws {
            let fixture = try container(in: root.appendingPathComponent(UUID().uuidString))
            let route = ChatDraftKey(accountID: UUID(), chatID: 100, topic: nil)
            let voiceDirectory = directory("VoiceNoteDrafts", container: fixture)
            let videoDirectory = directory("VideoNoteDrafts", container: fixture)
            let voiceStore = VoiceNoteDraftStore(directoryURL: voiceDirectory, legacyBindingAllowed: { _ in false })
            let videoStore = VideoNoteFileStore(directoryURL: videoDirectory, legacyBindingAllowed: { _ in false })
            let externalDirectory = root.appendingPathComponent("external-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
            var retained = [URL: Data]()
            for mode in [
                "external",
                "traversal",
                "wrong-id",
                "manifest-id",
                "malformed",
                "missing",
                "symlink",
                "wrong-container",
                "symlink-manifest",
            ] {
                var raw = try await voiceStore.adopt(voice(root: root, route: route, encoded: false))
                var clip = try await video(store: videoStore, root: root, route: route)
                let rawFile = raw.fileURL
                let clipFile = clip.fileURL
                let thumbnailFile = clip.thumbnailFileURL!
                let voiceJSON = manifest(raw.id, directory: voiceDirectory)
                let videoJSON = manifest(clip.id, directory: videoDirectory)
                for file in [rawFile, clipFile, clip.thumbnailFileURL!] {
                    try FileManager.default.setAttributes(
                        [.modificationDate: Foundation.Date(timeIntervalSince1970: 1)],
                        ofItemAtPath: file.path,
                    )
                }
                switch mode {
                case "external":
                    raw.fileURL = externalDirectory.appendingPathComponent(rawFile.lastPathComponent)
                    clip.fileURL = externalDirectory.appendingPathComponent(clipFile.lastPathComponent)
                case "traversal":
                    raw.fileURL = URL(string: "../\(rawFile.lastPathComponent)")!
                    clip.thumbnailFileURL = URL(string: "../\(clip.thumbnailFileURL!.lastPathComponent)")!
                case "wrong-id":
                    raw.fileURL = voiceDirectory.appendingPathComponent("\(UUID().uuidString).wav")
                    clip.fileURL = videoDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                case "missing":
                    try FileManager.default.removeItem(at: rawFile)
                    try FileManager.default.removeItem(at: clipFile)
                    raw.fileURL = URL(string: rawFile.lastPathComponent)!
                    clip.fileURL = URL(string: clipFile.lastPathComponent)!
                    clip.thumbnailFileURL = URL(string: thumbnailFile.lastPathComponent)!
                case "symlink":
                    for file in [rawFile, clipFile] {
                        let target = externalDirectory.appendingPathComponent(file.lastPathComponent)
                        try FileManager.default.moveItem(at: file, to: target)
                        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
                        retained[target] = try Data(contentsOf: target)
                    }
                case "wrong-container":
                    let wrong = fixture.deletingLastPathComponent().appendingPathComponent("not-an-app-container")
                    raw.fileURL = directory("VoiceNoteDrafts", container: wrong)
                        .appendingPathComponent(rawFile.lastPathComponent)
                    clip.fileURL = directory("VideoNoteDrafts", container: wrong)
                        .appendingPathComponent(clipFile.lastPathComponent)
                default: break
                }
                if mode == "malformed" {
                    try Data("{bad".utf8).write(to: voiceJSON)
                    try Data("{bad".utf8).write(to: videoJSON)
                } else {
                    try writeLegacy(raw, id: raw.id, directory: voiceDirectory)
                    try writeLegacy(clip, id: clip.id, directory: videoDirectory)
                }
                if mode == "manifest-id" {
                    for file in [voiceJSON, videoJSON] {
                        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
                        object["id"] = UUID().uuidString
                        try JSONSerialization.data(withJSONObject: object).write(to: file)
                    }
                }
                if mode == "symlink-manifest" {
                    for file in [voiceJSON, videoJSON] {
                        let target = externalDirectory.appendingPathComponent(file.lastPathComponent)
                        try FileManager.default.moveItem(at: file, to: target)
                        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
                        retained[target] = try Data(contentsOf: target)
                    }
                }
                for file in [voiceJSON, videoJSON, rawFile, clipFile, thumbnailFile] where exists(file) {
                    retained[file] = try Data(contentsOf: file)
                }
                try await require(
                    voiceStore.status(id: raw.id, destination: route).draft == nil,
                    "accepted voice \(mode)",
                )
            }
            try await require(voiceStore.drafts(for: route).isEmpty, "invalid voice list")
            try await require(videoStore.drafts(for: route).isEmpty, "invalid video list")
            for (file, data) in retained {
                try require(exists(file), "rejected manifest or aged media removed: \(file.lastPathComponent)")
                try require(Data(contentsOf: file) == data, "rejected data mutated: \(file.lastPathComponent)")
            }
        }

        private static func verifyMissingTombstone(root: URL) async throws {
            let fixture = root.appendingPathComponent(UUID().uuidString)
            let oldContainer = try container(in: fixture)
            let newContainer = oldContainer.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            let oldDirectory = directory("VideoNoteDrafts", container: oldContainer)
            let route = ChatDraftKey(accountID: UUID(), chatID: 100, topic: nil)
            let origin = UUID()
            let store = VideoNoteFileStore(
                directoryURL: oldDirectory, legacyBindingAllowed: { _ in false }, discardRecordingDraft: { _ in false },
            )
            let draft = try await video(store: store, root: root, route: route, origin: origin)
            try await require(!store.remove(draft), "missing tombstone setup")
            var legacy = draft
            legacy.removalRequestedAt = Foundation.Date(timeIntervalSince1970: 100)
            try writeLegacy(legacy, id: draft.id, directory: oldDirectory)
            try FileManager.default.removeItem(at: draft.fileURL)
            try FileManager.default.removeItem(at: draft.thumbnailFileURL!)
            try FileManager.default.moveItem(at: oldContainer, to: newContainer)
            let newDirectory = directory("VideoNoteDrafts", container: newContainer)
            let removals = OriginRemovals()
            let restored = VideoNoteFileStore(
                directoryURL: newDirectory, legacyBindingAllowed: { _ in false },
                discardRecordingDraft: { await removals.remove($0) },
            )
            try await require(restored.recordingDraftOrigins() == [origin], "missing media lost origin tombstone")
            try await require(restored.reconcileRemovalTombstones(), "missing media tombstone reconciliation")
            try await require(removals.ids == [origin], "missing media origin not discarded")
            try require(!exists(manifest(draft.id, directory: newDirectory)), "missing media tombstone retained")
        }

        private static func writeThumbnail(to url: URL) throws {
            guard let context = CGContext(
                data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ), let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(
                    url as CFURL,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil,
                )
            else { throw Failure(description: "thumbnail fixture") }
            CGImageDestinationAddImage(destination, image, nil)
            try require(CGImageDestinationFinalize(destination), "thumbnail write")
        }
    }
#endif
