// BotButtonsProbe.swift

#if DEBUG
    import UIKit

    /// Launch with `-ui-probe-bot-buttons`. Once an account is active it shows the login URL button's Open Link alert
    /// with Telegram's two checks for a sample bot; Open shows which choice it would send. With
    /// `-ui-probe-bot-buttons-quiz` it opens the poll creator as a bot's quiz request instead. With
    /// `-ui-probe-bot-buttons-switch-inline KINDS` (comma separated users, bots, groups, channels) it opens a switch
    /// inline button's chat picker for the first chat; the chosen chat shows in an alert, or with
    /// `-ui-probe-bot-buttons-switch-inline-open` opens with "@probe_bot query" in its composer. Nothing reaches a
    /// bot and nothing is sent.
    @MainActor enum BotButtonsProbe {
        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-ui-probe-bot-buttons") else { return }
            let showsQuiz = arguments.contains("-ui-probe-bot-buttons-quiz")
            let switchInlineKinds = arguments.firstIndex(of: "-ui-probe-bot-buttons-switch-inline")
                .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1].split(separator: ",") : nil }
                .map { Set($0.map(String.init)) }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard TDLib.shared.activeAccountID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                guard let presenter else { return }
                if let switchInlineKinds {
                    return presentSwitchInlinePicker(
                        kinds: switchInlineKinds,
                        opensChat: arguments.contains("-ui-probe-bot-buttons-switch-inline-open"),
                        from: presenter,
                    )
                }
                if showsQuiz {
                    let poll = CreatePollViewController(
                        isChannel: false,
                        client: TDLib.shared.activeClient,
                        forcedQuiz: true,
                        accountID: nil,
                        chatID: 0,
                    ) { _ in }
                    presenter.present(poll.makeNavigationController(), animated: true)
                    return
                }
                let alert = BotLoginUrlAlert.make(
                    url: "https://example.com/login",
                    domain: "example.com",
                    botName: "Example Bot",
                    accountName: "Probe User",
                    requestsWriteAccess: true,
                ) { [weak presenter] authorize, allowWriteAccess in
                    let result = UIAlertController(
                        title: "Probe",
                        message: "authorize=\(authorize) allowWriteAccess=\(allowWriteAccess)",
                        preferredStyle: .alert,
                    )
                    result.addAction(UIAlertAction(title: "OK", style: .default))
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.6))
                        presenter?.present(result, animated: true)
                    }
                }
                presenter.present(alert, animated: true)
            }
        }

        private static func presentSwitchInlinePicker(
            kinds: Set<String>,
            opensChat: Bool,
            from presenter: UIViewController,
        ) {
            var seen = Set<Int64>()
            let seedChats = RootVM.shared.allFolders.flatMap(\.chats).map(\.chat).filter { seen.insert($0.id).inserted }
            let client = TDLib.shared.activeClient
            guard let accountID = TDLib.shared.activeAccountID, let source = seedChats.first,
                  let request = try? MessageForwardRequest(
                      sourceLocation: .current(chatID: source.id, client: client),
                      messageIDs: [source.lastMessage?.id ?? 1],
                  )
            else { return }
            let picker = ForwardMessagesViewController(
                request: request,
                client: client,
                accountID: accountID,
                seedChats: seedChats,
                purpose: .switchInline(InlineTargetChatTypes(
                    users: kinds.contains("users"),
                    bots: kinds.contains("bots"),
                    groups: kinds.contains("groups"),
                    channels: kinds.contains("channels"),
                )),
            )
            picker.onChosenChat = { [weak presenter] chat, topic in
                if opensChat {
                    return ChatViewController.openSwitchInline(
                        "@probe_bot query",
                        in: chat,
                        topic: topic,
                        destination: .current(
                            chatID: chat.id,
                            topic: topic.map {
                                .messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId))
                            },
                            client: client,
                        ),
                        navigationController: firstNavigation(in: presenter),
                    )
                }
                let result = UIAlertController(
                    title: "Probe",
                    message: "chat=\(chat.displayTitle) topic=\(topic?.info.name ?? "none")",
                    preferredStyle: .alert,
                )
                result.addAction(UIAlertAction(title: "OK", style: .default))
                presenter?.present(result, animated: true)
            }
            let navigation = TelegramNavigationController(rootViewController: picker)
            navigation.modalPresentationStyle = .fullScreen
            presenter.present(navigation, animated: true)
        }

        private static func firstNavigation(in controller: UIViewController?) -> UINavigationController? {
            guard let controller else { return nil }
            if let navigation = controller as? UINavigationController { return navigation }
            return controller.children.lazy.compactMap { firstNavigation(in: $0) }.first
        }
    }
#endif
