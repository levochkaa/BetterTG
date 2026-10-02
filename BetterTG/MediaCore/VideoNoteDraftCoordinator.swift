// VideoNoteDraftCoordinator.swift

import Combine
import Foundation

// MARK: - VideoNoteDraftCoordinator

final class VideoNoteDraftCoordinator {
    static let shared = VideoNoteDraftCoordinator()

    private var cancellables = Set<AnyCancellable>()

    func start() {
        guard cancellables.isEmpty else { return }
        Task {
            await reconcileRecordingDraftOrigins()
        }
        nc.scopedPublisher(&cancellables, for: .updateMessageSendSucceeded) { event in
            let update = event.value
            guard case .messageVideoNote = update.message.content else { return }
            let destination = ChatDraftKey(
                accountID: event.source.accountID,
                chatID: update.message.chatId,
                topic: update.message.topicId,
            )
            let migrateLegacy = ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: destination)
            Task {
                do {
                    if let resolution = try await VideoNoteFileStore.shared.handleSendSucceeded(
                        destination: destination,
                        temporaryMessageID: update.oldMessageId,
                        migrateLegacy: migrateLegacy,
                    ) {
                        nc.post(name: .videoNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Video note success ownership update failed: \(error)")
                }
            }
        }
        nc.scopedPublisher(&cancellables, for: .updateMessageSendFailed) { event in
            let update = event.value
            guard case .messageVideoNote = update.message.content else { return }
            let destination = ChatDraftKey(
                accountID: event.source.accountID,
                chatID: update.message.chatId,
                topic: update.message.topicId,
            )
            let migrateLegacy = ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: destination)
            let failedSendState: VideoNoteFailedSendState? =
                if case .messageSendingStateFailed(let state) = update.message.sendingState {
                    VideoNoteFailedSendState(
                        canRetry: state.canRetry,
                        messageID: update.message.id,
                        needAnotherReplyQuote: state.needAnotherReplyQuote,
                        needAnotherSender: state.needAnotherSender,
                        requiredPaidMessageStarCount: state.requiredPaidMessageStarCount,
                        retryAvailableAt: Foundation.Date().addingTimeInterval(max(0, state.retryAfter)),
                    )
                } else {
                    nil
                }
            Task {
                do {
                    if let resolution = try await VideoNoteFileStore.shared.handleSendFailed(
                        destination: destination,
                        temporaryMessageID: update.oldMessageId,
                        failedSendState: failedSendState,
                        migrateLegacy: migrateLegacy,
                    ) {
                        nc.post(name: .videoNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Video note failure ownership update failed: \(error)")
                }
            }
        }
        nc.scopedPublisher(&cancellables, for: .updateDeleteMessages) { event in
            let update = event.value
            guard !update.fromCache, update.isPermanent else { return }
            let accountID = event.source.accountID
            Task {
                for messageID in update.messageIds {
                    do {
                        if let resolution = try await VideoNoteFileStore.shared.handleMessageDeleted(
                            accountID: accountID,
                            chatID: update.chatId,
                            temporaryMessageID: messageID,
                        ) {
                            nc.post(name: .videoNoteDraftResolved, object: resolution)
                        }
                    } catch {
                        log("Video note delete ownership update failed: \(error)")
                    }
                }
            }
        }
    }

    func reconcileRecordingDraftOrigins() async {
        for attempt in 0..<3 {
            do {
                guard try await VideoNoteFileStore.shared.reconcileRemovalTombstones() else {
                    throw VideoNoteDraftCoordinatorError.sendCleanupFailed
                }
                let recordingDraftIDs = try await VideoNoteFileStore.shared.recordingDraftOrigins()
                for id in recordingDraftIDs {
                    guard await VideoNoteRecordingDraftStore.shared.discard(id: id) else {
                        throw VideoNoteDraftCoordinatorError.recordingCleanupFailed
                    }
                }
                return
            } catch {
                guard attempt < 2 else {
                    log("Video note origin reconciliation failed: \(error)")
                    return
                }
                try? await Task<Never, Never>.sleep(for: .milliseconds(500))
            }
        }
    }
}

// MARK: - VideoNoteDraftCoordinatorError

private enum VideoNoteDraftCoordinatorError: Swift.Error {
    case recordingCleanupFailed
    case sendCleanupFailed
}

extension Notification.Name {
    static let videoNoteDraftResolved = Self("videoNoteDraftResolved")
}
