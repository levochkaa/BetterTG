// BotButtonsProbe.swift

#if DEBUG
    import UIKit

    /// Launch with `-ui-probe-bot-buttons`. Once an account is active it shows the login URL button's Open Link alert
    /// with Telegram's two checks for a sample bot; Open shows which choice it would send. With
    /// `-ui-probe-bot-buttons-quiz` it opens the poll creator as a bot's quiz request instead. Nothing reaches a bot
    /// and nothing is sent.
    @MainActor enum BotButtonsProbe {
        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-ui-probe-bot-buttons") else { return }
            let showsQuiz = arguments.contains("-ui-probe-bot-buttons-quiz")
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
                if showsQuiz {
                    let poll = CreatePollViewController(
                        isChannel: false,
                        client: TDLib.shared.activeClient,
                        forcedQuiz: true,
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
    }
#endif
