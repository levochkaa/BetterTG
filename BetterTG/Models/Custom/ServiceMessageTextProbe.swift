// ServiceMessageTextProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    /// Checks Telegram's service wording for actions whose real messages are rare (calls, video chats, timers,
    /// game scores, proximity alerts, web app data, themes). Launch with `-ui-probe-service-text`.
    @MainActor enum ServiceMessageTextProbe {
        private struct Case {
            let name: String
            let content: MessageContent
            let context: ServiceMessageText.Context
            let check: (String?) -> Bool
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-service-text") else { return }
            var failures = [String]()
            let cases = makeCases()
            for item in cases {
                let text = ServiceMessageText.make(item.content, context: item.context)
                if !item.check(text) { failures.append("\(item.name)=\(text ?? "nil")") }
            }
            let result = failures.isEmpty
                ? "Service text probe passed: \(cases.count) cases"
                : "Service text probe failed: \(failures.joined(separator: "; "))"
            log(result)
        }

        private static func context(
            outgoing: Bool = false,
            channel: Bool = false,
            byUser: Bool = true,
            kind: ServiceMessageText.ChatKind = .unknown,
            names: [Int64: String] = [:],
        ) -> ServiceMessageText.Context {
            ServiceMessageText.Context(
                author: byUser ? "Ada" : "News",
                isOutgoing: outgoing,
                isChannel: channel,
                senderUserID: byUser ? 2 : nil,
                names: names,
                pinned: nil,
                accountUserID: 7,
                chatKind: kind,
                chatTitle: "Ada",
            )
        }

        private static func equals(_ expected: String) -> (String?) -> Bool {
            { $0 == expected.trimmingCharacters(in: .whitespaces) }
        }

        /// Expected wording comes from the selected language pack, so the probe checks key choice and arguments.
        private static func t(_ key: String, _ arguments: CVarArg...) -> String {
            AppLocalization.shared.telegramString(key, arguments: arguments)
        }

        private static func p(_ key: String, _ count: Int) -> String {
            AppLocalization.shared.telegramPluralString(key, count: count)
        }

        private static func makeCases() -> [Case] {
            let day = 24 * 60 * 60
            return [
                Case(
                    name: "missed-call",
                    content: .messageCall(MessageCall(
                        discardReason: .callDiscardReasonMissed, duration: 0, isVideo: false, uniqueId: 1,
                    )),
                    context: context(),
                    check: equals(t("Notification.CallMissed")),
                ),
                Case(
                    name: "outgoing-call",
                    content: .messageCall(MessageCall(
                        discardReason: .callDiscardReasonHungUp, duration: 65, isVideo: false, uniqueId: 2,
                    )),
                    context: context(outgoing: true),
                    check: equals(t("Notification.CallOutgoing")),
                ),
                Case(
                    name: "group-call-declined",
                    content: .messageGroupCall(MessageGroupCall(
                        duration: 0, isActive: false, isVideo: false, otherParticipantIds: [], uniqueId: 3,
                        wasMissed: true,
                    )),
                    context: context(),
                    check: equals(t("Chat.CallMessage.DeclinedGroupCall")),
                ),
                Case(
                    name: "video-chat-ended-user",
                    content: .messageVideoChatEnded(MessageVideoChatEnded(duration: 125)),
                    context: context(kind: .supergroup),
                    check: equals(t("Notification.VoiceChatEndedGroup", "Ada", p("Call.Minutes", 2))),
                ),
                Case(
                    name: "live-stream-ended",
                    content: .messageVideoChatEnded(MessageVideoChatEnded(duration: 3 * 60 * 60)),
                    context: context(channel: true, byUser: false, kind: .channel),
                    check: equals(t("Notification.LiveStreamEnded", p("Call.Hours", 3))),
                ),
                Case(
                    name: "video-chat-scheduled",
                    content: .messageVideoChatScheduled(MessageVideoChatScheduled(
                        groupCallId: 1,
                        startDate: Int(Foundation.Date().timeIntervalSince1970) + 2 * day,
                    )),
                    context: context(kind: .supergroup),
                    check: { text in
                        let date = Foundation
                            .Date(timeIntervalSince1970: Foundation.Date().timeIntervalSince1970 + 2 * 86400)
                        return text == t(
                            "Notification.VoiceChatScheduled",
                            "Ada",
                            date.formatted(date: .abbreviated, time: .shortened),
                        )
                    },
                ),
                Case(
                    name: "invited-you",
                    content: .messageInviteVideoChatParticipants(MessageInviteVideoChatParticipants(
                        groupCallId: 1, userIds: [7],
                    )),
                    context: context(),
                    check: equals(t("Notification.VoiceChatInvitationForYou", "Ada")),
                ),
                Case(
                    name: "invited-others",
                    content: .messageInviteVideoChatParticipants(MessageInviteVideoChatParticipants(
                        groupCallId: 1, userIds: [8, 9],
                    )),
                    context: context(names: [8: "Bob", 9: "Eve"]),
                    check: equals(t("Notification.VoiceChatInvitation", "Ada", "Bob, Eve")),
                ),
                Case(
                    name: "auto-delete-private",
                    content: .messageChatSetMessageAutoDeleteTime(MessageChatSetMessageAutoDeleteTime(
                        fromUserId: 0, messageAutoDeleteTime: day,
                    )),
                    context: context(kind: .privateChat),
                    check: equals(t("Conversation.AutoremoveTimerSetUser", "Ada", p("MessageTimer.Days", 1))),
                ),
                Case(
                    name: "auto-delete-group",
                    content: .messageChatSetMessageAutoDeleteTime(MessageChatSetMessageAutoDeleteTime(
                        fromUserId: 0, messageAutoDeleteTime: 7 * day,
                    )),
                    context: context(kind: .supergroup),
                    check: equals(t("Conversation.AutoremoveTimerSetGroup", p("MessageTimer.Weeks", 1))),
                ),
                Case(
                    name: "auto-delete-off-channel",
                    content: .messageChatSetMessageAutoDeleteTime(MessageChatSetMessageAutoDeleteTime(
                        fromUserId: 0, messageAutoDeleteTime: 0,
                    )),
                    context: context(channel: true, byUser: false, kind: .channel),
                    check: equals(t("Conversation.AutoremoveTimerRemovedChannel")),
                ),
                Case(
                    name: "auto-delete-unknown-chat",
                    content: .messageChatSetMessageAutoDeleteTime(MessageChatSetMessageAutoDeleteTime(
                        fromUserId: 0, messageAutoDeleteTime: day,
                    )),
                    context: context(),
                    check: { $0 == nil },
                ),
                Case(
                    name: "game-score-self",
                    content: .messageGameScore(MessageGameScore(gameId: 1, gameMessageId: 0, score: 42)),
                    context: context(outgoing: true),
                    check: { $0?.contains("42") == true && $0?.contains("{") == false },
                ),
                Case(
                    name: "proximity-you",
                    content: .messageProximityAlertTriggered(MessageProximityAlertTriggered(
                        distance: 150,
                        travelerId: .messageSenderUser(MessageSenderUser(userId: 7)),
                        watcherId: .messageSenderUser(MessageSenderUser(userId: 8)),
                    )),
                    context: context(names: [8: "Bob"]),
                    check: { $0?.contains("Bob") == true && $0 != t("Notification.ProximityReached", "", "", "") },
                ),
                Case(
                    name: "web-app-data",
                    content: .messageWebAppDataSent(MessageWebAppDataSent(buttonText: "Order")),
                    context: context(outgoing: true),
                    check: equals(t("Notification.WebAppSentData", "Order")),
                ),
                Case(
                    name: "theme-changed",
                    content: .messageChatSetTheme(
                        MessageChatSetTheme(theme: .chatThemeEmoji(ChatThemeEmoji(name: "🌸"))),
                    ),
                    context: context(kind: .privateChat),
                    check: equals(t("Notification.ChangedTheme", "Ada", "🌸")),
                ),
                Case(
                    name: "theme-disabled-you",
                    content: .messageChatSetTheme(MessageChatSetTheme(theme: nil)),
                    context: context(outgoing: true, kind: .privateChat),
                    check: equals(t("Notification.YouDisabledTheme")),
                ),
                Case(
                    name: "live-stream-started",
                    content: .messageVideoChatStarted(MessageVideoChatStarted(groupCallId: 1)),
                    context: context(channel: true, byUser: false, kind: .channel),
                    check: equals(t("Notification.LiveStreamStarted")),
                ),
            ]
        }
    }
#endif
