// VideoNoteDraftCoordinator.swift

import Combine
import Foundation

final class VideoNoteDraftCoordinator {
    static let shared = VideoNoteDraftCoordinator()

    func start() {
        guard cancellables.isEmpty else { return }
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

    private var cancellables = Set<AnyCancellable>()
}

extension Notification.Name {
    static let videoNoteDraftResolved = Self("videoNoteDraftResolved")
}
