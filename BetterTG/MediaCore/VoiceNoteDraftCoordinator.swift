// VoiceNoteDraftCoordinator.swift

import Combine
import Foundation

// MARK: - VoiceNoteDraftCoordinator

final class VoiceNoteDraftCoordinator {
    // MARK: Internal

    static let shared = VoiceNoteDraftCoordinator()

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()

    func start() {
        guard cancellables.isEmpty else { return }
        nc.scopedPublisher(&cancellables, for: .updateMessageSendSucceeded) { event in
            let update = event.value
            guard case .messageVoiceNote = update.message.content else { return }
            let delivery = ChatDraftDeliveryKey(
                accountID: event.source.accountID,
                chatID: update.message.chatId,
                topic: update.message.topicId,
            )
            let migrateLegacy = ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: delivery.legacyBaseRoute)
            Task {
                do {
                    if let resolution = try await VoiceNoteDraftStore.shared.handleSendSucceeded(
                        delivery: delivery,
                        temporaryMessageID: update.oldMessageId,
                        migrateLegacy: migrateLegacy,
                    ) {
                        nc.post(name: .voiceNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Voice note success ownership update failed: \(error)")
                }
            }
        }
        nc.scopedPublisher(&cancellables, for: .updateMessageSendFailed) { event in
            let update = event.value
            guard case .messageVoiceNote = update.message.content else { return }
            let delivery = ChatDraftDeliveryKey(
                accountID: event.source.accountID,
                chatID: update.message.chatId,
                topic: update.message.topicId,
            )
            let migrateLegacy = ChatDraftLegacyMigrationPolicy.canBindLegacyDrafts(to: delivery.legacyBaseRoute)
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
                        delivery: delivery,
                        temporaryMessageID: update.oldMessageId,
                        failedSendState: failedSendState,
                        migrateLegacy: migrateLegacy,
                    ) {
                        nc.post(name: .voiceNoteDraftResolved, object: resolution)
                    }
                } catch {
                    log("Voice note failure ownership update failed: \(error)")
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
                        if let resolution = try await VoiceNoteDraftStore.shared.handleMessageDeleted(
                            accountID: accountID,
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
}

extension Notification.Name {
    static let voiceNoteDraftResolved = Self("voiceNoteDraftResolved")
    /// A voice recording is about to take the audio session; inline playback such as a video note pauses.
    static let voiceRecordingWillStart = Self("voiceRecordingWillStart")
}
