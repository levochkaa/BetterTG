// ChatVM+Checklist.swift

import Foundation
import TDLibKit

extension ChatVM {
    /// Telegram's notice that marking tasks needs Telegram Premium, without its inline link markup.
    static var checklistPremiumRequiredText: String {
        L10n.telegram("Chat.Todo.PremiumRequired")
            .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
    }

    /// Telegram's requestToggleTodoMessageItem: the task already shows its new state, and this chat's client marks
    /// it. Marking needs Telegram Premium, which Telegram checks before it sends (ChatMessageTodoItemNode
    /// .buttonPressed). A failed or refused request restores the task; an error is reported.
    func toggleChecklistTask(
        _ toggle: MessagePollInteractionStore.ChecklistToggle,
        onPremiumRequired: @escaping () -> Void,
    ) {
        let store = pollInteractionStore
        guard store.isCurrent(toggle) else { return }
        guard !isReadOnlyTopic, locationContextIsCurrent,
              messages.contains(where: { message in
                  message.id == toggle.messageID || message.album.contains(where: { $0.id == toggle.messageID })
              })
        else {
            store.failChecklistToggle(toggle)
            return
        }
        let client = client
        let chatID = chatID
        Task { [weak self] in
            do {
                let isPremium = try await client.getMe().isPremium
                guard store.isCurrent(toggle) else { return }
                guard let self, locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else {
                    store.failChecklistToggle(toggle)
                    return
                }
                guard isPremium else {
                    store.failChecklistToggle(toggle)
                    onPremiumRequired()
                    return
                }
                _ = try await client.markChecklistTasksAsDone(
                    chatId: chatID,
                    markedAsDoneTaskIds: toggle.isDone ? [toggle.taskID] : [],
                    markedAsNotDoneTaskIds: toggle.isDone ? [] : [toggle.taskID],
                    messageId: toggle.messageID,
                )
            } catch {
                // A toggle that already timed out or was replaced stays silent.
                guard store.failChecklistToggle(toggle) else { return }
                log(
                    "Couldn't mark checklist task \(toggle.taskID) of \(toggle.messageID): \(error.localizedDescription)",
                )
                guard let self, locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else { return }
                messageActionErrorMessage = (error as? TDLibError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Whether this chat's account has Telegram Premium; nil once the chat's client is no longer active.
    func accountHasPremium() async -> Bool? {
        let client = client
        guard let me = try? await client.getMe(), TDLib.shared.activeClient.id == client.id else { return nil }
        return me.isPremium
    }

    /// Telegram's Add a Task (ChatInterfaceStateContextMenus) for a published checklist where TDLib's `canAddTasks`
    /// allows it.
    func canAddChecklistTask(_ message: CustomMessage) -> Bool {
        guard !isReadOnlyTopic, locationContextIsCurrent, location.matches(message: message.message),
              message.message.sendingState == nil, message.message.schedulingState == nil,
              case .messageChecklist(let content) = message.message.content
        else { return false }
        return content.list.canAddTasks
    }

    /// Appends one task after the checklist's highest task ID; the longer list arrives through updateMessageContent.
    func addChecklistTask(_ message: CustomMessage, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canAddChecklistTask(message), messages.contains(where: { $0 === message }),
              case .messageChecklist(let content) = message.message.content
        else { return }
        let client = client
        let chatID = message.message.chatId
        let messageID = message.id
        let task = InputChecklistTask(
            id: (content.list.tasks.map(\.id).max() ?? 0) + 1,
            text: FormattedText(entities: [], text: text),
        )
        Task { [weak self] in
            do {
                _ = try await client.addChecklistTasks(chatId: chatID, messageId: messageID, tasks: [task])
            } catch {
                guard let self, locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else { return }
                messageActionErrorMessage = (error as? TDLibError)?.message ?? error.localizedDescription
            }
        }
    }
}
