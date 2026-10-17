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

    /// ChatControllerOpenTodoContextMenu's `canMark`, which TDLib reports as `canMarkTasksAsDone`, for a published
    /// checklist.
    func canMarkChecklistTasks(_ message: CustomMessage) -> Bool {
        guard !isReadOnlyTopic, locationContextIsCurrent, location.matches(message: message.message),
              message.message.sendingState == nil, message.message.schedulingState == nil,
              case .messageChecklist(let content) = message.message.content
        else { return false }
        return content.list.canMarkTasksAsDone
    }

    /// Telegram's Edit Item and Delete Item, where TDLib lets the checklist be edited.
    func canEditChecklist(_ message: CustomMessage) -> Bool {
        guard !isReadOnlyTopic, locationContextIsCurrent, location.matches(message: message.message),
              message.message.sendingState == nil, message.properties.canBeEdited,
              case .messageChecklist = message.message.content
        else { return false }
        return true
    }

    /// The checklist task the composer's reply is to, for the reply panel's "Reply to Checklist Item".
    var replyChecklistTask: ChecklistTask? {
        guard case .inputMessageReplyToMessage(let reply)? = replyInputOverride, reply.checklistTaskId != 0,
              let message = replyMessage, case .messageChecklist(let content) = message.message.content
        else { return nil }
        return content.list.tasks.first { $0.id == reply.checklistTaskId }
    }

    /// Delete Item: the checklist goes back without the task, as long as another task remains.
    func deleteChecklistTask(_ message: CustomMessage, taskID: Int) {
        editChecklist(message) { tasks in
            tasks.count > 1 ? tasks.filter { $0.id != taskID } : tasks
        }
    }

    /// requestEditMessage with the updated TelegramMediaTodo: editMessageChecklist with the checklist's title and
    /// settings and the changed tasks.
    private func editChecklist(
        _ message: CustomMessage,
        transform: ([InputChecklistTask]) -> [InputChecklistTask],
    ) {
        guard case .messageChecklist(let content) = message.message.content
        else { return }
        let list = content.list
        let tasks = list.tasks.map { InputChecklistTask(id: $0.id, text: $0.text) }
        let updated = transform(tasks)
        guard updated != tasks, !updated.isEmpty else { return }
        replaceChecklist(of: message, with: TDNativeInputChecklist(
            title: list.title,
            tasks: updated,
            othersCanAddTasks: list.othersCanAddTasks,
            othersCanMarkTasksAsDone: list.othersCanMarkTasksAsDone,
        ))
    }

    /// openTodoEditing's completion: an edited checklist replaces the published one, and added tasks are appended
    /// where TDLib lets this account add tasks, or go as an edit where only that is allowed.
    func applyChecklistEditor(_ outcome: ChecklistEditorOutcome, to message: CustomMessage) {
        switch outcome {
        case .checklist(let checklist):
            replaceChecklist(of: message, with: checklist)
        case .addedTasks(let tasks, let checklist):
            if canAddChecklistTask(message) {
                addChecklistTasks(tasks, to: message)
            } else {
                replaceChecklist(of: message, with: checklist)
            }
        }
    }

    /// requestEditMessage with the checklist: editMessageChecklist, whose edited list arrives through
    /// updateMessageContent.
    private func replaceChecklist(of message: CustomMessage, with checklist: TDNativeInputChecklist) {
        guard canEditChecklist(message), messages.contains(where: { $0 === message }) else { return }
        let client = client
        let chatID = message.message.chatId
        let messageID = message.id
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.editMessageChecklist(
                    chatId: chatID,
                    messageId: messageID,
                    replyMarkup: nil,
                    checklist: checklist,
                ))
            } catch {
                guard let self, locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else { return }
                messageActionErrorMessage = (error as? TDLibError)?.message ?? error.localizedDescription
            }
        }
    }

    /// appendTodoMessageItems: the tasks, numbered after the checklist's highest task ID, go after its tasks; the
    /// longer list arrives through updateMessageContent.
    private func addChecklistTasks(_ tasks: [InputChecklistTask], to message: CustomMessage) {
        guard !tasks.isEmpty, canAddChecklistTask(message), messages.contains(where: { $0 === message }) else { return }
        let client = client
        let chatID = message.message.chatId
        let messageID = message.id
        Task { [weak self] in
            do {
                _ = try await client.addChecklistTasks(chatId: chatID, messageId: messageID, tasks: tasks)
            } catch {
                guard let self, locationContextIsCurrent, TDLib.shared.activeClient.id == client.id else { return }
                messageActionErrorMessage = (error as? TDLibError)?.message ?? error.localizedDescription
            }
        }
    }
}
