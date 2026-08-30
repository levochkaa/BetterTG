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
        nc.publisher(&cancellables, for: .updateMessageSendSucceeded) { update in
            guard case .messageVideoNote = update.message.content else { return }
            Task {
                do {
                    if let resolution = try await VideoNoteFileStore.shared.handleSendSucceeded(
                        chatID: update.message.chatId,
                        temporaryMessageID: update.oldMessageId,
                    ) {
                        nc.post(name: .videoNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Video note success ownership update failed: \(error)")
                }
            }
        }
        nc.publisher(&cancellables, for: .updateMessageSendFailed) { update in
            guard case .messageVideoNote = update.message.content else { return }
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
                        chatID: update.message.chatId,
                        temporaryMessageID: update.oldMessageId,
                        failedSendState: failedSendState,
                    ) {
                        nc.post(name: .videoNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Video note failure ownership update failed: \(error)")
                }
            }
        }
        nc.publisher(&cancellables, for: .updateDeleteMessages) { update in
            guard !update.fromCache, update.isPermanent else { return }
            Task {
                for messageID in update.messageIds {
                    do {
                        if let resolution = try await VideoNoteFileStore.shared.handleMessageDeleted(
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
