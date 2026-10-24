// ChatVM+ReplyKeyboard.swift

import Combine
import Foundation
import TDLibKit

extension ChatVM {
    /// Follows the chat's reply keyboard: its changes refresh the composer, and each new keyboard message gets the
    /// reply Telegram sets up for it.
    func bindReplyKeyboard() {
        replyKeyboard.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        replyKeyboard.$revision
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setUpReplyKeyboardReplyIfNeeded() }
            .store(in: &cancellables)
        replyKeyboard.load()
    }

    /// Telegram replies to a force reply's message, and in a group to a keyboard's message so that the bot receives
    /// the answer, once per message and only when the composer has no reply yet (`processedSetupReplyMessageId`).
    private func setUpReplyKeyboardReplyIfNeeded() {
        guard supportsReplyKeyboard, locationContextIsCurrent, canWriteBasicMessages,
              editCustomMessage == nil, pendingForward == nil, replyMessage == nil,
              replyInputOverride == nil, replyFallbackPresentation == nil,
              let message = replyKeyboard.replySetupCandidate(isGroup: isGroupChat)
        else { return }
        replyKeyboard.markReplySetUp(messageID: message.id)
        Task { [weak self] in
            guard let self else { return }
            let customMessage = await getCustomMessage(from: message)
            guard locationContextIsCurrent, replyKeyboard.message?.id == message.id,
                  editCustomMessage == nil, pendingForward == nil, replyMessage == nil
            else { return }
            beginReply(to: customMessage)
        }
    }

    private var isGroupChat: Bool {
        switch customChat.type {
        case .group: true
        case .supergroup(let supergroup): !supergroup.isChannel
        case .bot,
             .user: false
        }
    }
}
