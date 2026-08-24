// VoiceNoteDraftCoordinator.swift

import Combine
import Foundation

// MARK: - VoiceNoteDraftCoordinator

final class VoiceNoteDraftCoordinator {
    // MARK: Internal

    static let shared = VoiceNoteDraftCoordinator()

    func start() {
        guard cancellables.isEmpty else { return }
        nc.publisher(&cancellables, for: .updateMessageSendSucceeded) { update in
            guard case .messageVoiceNote = update.message.content else { return }
            Task {
                do {
                    if let resolution = try await VoiceNoteDraftStore.shared.handleSendSucceeded(
                        chatID: update.message.chatId,
                        temporaryMessageID: update.oldMessageId,
                    ) {
                        nc.post(name: .voiceNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Voice note success ownership update failed: \(error)")
                }
            }
        }
        nc.publisher(&cancellables, for: .updateMessageSendFailed) { update in
            guard case .messageVoiceNote = update.message.content else { return }
            let failedSendState: VoiceNoteFailedSendState? =
                if case .messageSendingStateFailed(let state) = update
                        .message
                        .sendingState
                {
                    VoiceNoteFailedSendState(
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
                    if let resolution = try await VoiceNoteDraftStore.shared.handleSendFailed(
                        chatID: update.message.chatId,
                        temporaryMessageID: update.oldMessageId,
                        failedSendState: failedSendState,
                    ) {
                        nc.post(name: .voiceNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Voice note failure ownership update failed: \(error)")
                }
            }
        }
        nc.publisher(&cancellables, for: .updateDeleteMessages) { update in
            guard !update.fromCache, update.isPermanent else { return }
            Task {
                for messageID in update.messageIds {
                    do {
                        if let resolution = try await VoiceNoteDraftStore.shared.handleMessageDeleted(
                            chatID: update.chatId,
                            temporaryMessageID: messageID,
                        ) {
                            nc.post(name: .voiceNoteDraftResolved, object: resolution)
                        }
                    } catch {
                        log("Voice note delete ownership update failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
}

extension Notification.Name {
    static let voiceNoteDraftResolved = Self("voiceNoteDraftResolved")
}
