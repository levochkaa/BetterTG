// WebAppLauncher.swift

import TDLibKit
import UIKit

// MARK: - WebAppLauncher

/// ChatControllerOpenWebApp's `openWebAppImpl` for a bot's main Web App (`simple` with an empty URL:
/// `requestMainWebView`, WebAppParameters.Source.generic), a bot's menu button (source .menu) and
/// ChatControllerOpenAttachmentMenu's `.app` button (WebAppController with source .attachMenu). Before the page
/// opens, a bot that can be added to the attachment menu
/// but isn't (`isAttachMenuBotInstalled == false`, `.notActivated`) gets webAppTermsAlertController and
/// `addBotToAttachMenu` with the check as its write access; any other main or menu Web App gets
/// webAppLaunchConfirmationController the first time (`getBotGameNotice`) unless the caller skips the terms, as the
/// profile's Open App does.
@MainActor final class WebAppLauncher {
    struct Host {
        let accountID: UUID
        let client: TDLibClient
        let presenter: () -> UIViewController?
        let isCurrent: () -> Bool
        let actions: WebAppViewController.Actions
    }

    #if DEBUG
        /// `-ui-probe-attach-bots` and `-ui-probe-main-web-app`: this page opens in place of every launch and adding
        /// a bot only closes the terms, so no openWebApp, getMainWebApp or toggleBotIsAddedToAttachmentMenu is sent.
        static var probeHTML: String?
    #endif

    private let host: Host
    private var task: Task<Void, Never>?

    init(host: Host) {
        self.host = host
    }

    deinit {
        task?.cancel()
    }

    /// The per-account, per-bot `getBotGameNotice` the inline buttons' Web Apps also keep.
    static func noticeKey(accountID: UUID, botUserID: Int64) -> String {
        "bettertg.webAppNotice.\(accountID.uuidString).\(botUserID)"
    }

    static func displayName(of user: User) -> String {
        [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The named Web App a menu button links to: its bot, `searchWebApp`, then `getWebAppLinkUrl` for the menu
    /// bot's chat with write access (`requestAppWebView(allowWrite: true)`), titled with the app's name.
    private static func namedWebAppLaunch(
        _ link: TDNativeInternalLinkTypeWebApp,
        chatID: Int64,
        theme: TDNativeThemeParameters,
        client: TDLibClient,
        accountID: UUID,
    ) async -> WebAppLaunch? {
        guard let chat = try? await client.send(TDNativeRequests.searchPublicChat(username: link.botUsername)),
              case .chatTypePrivate(let type) = chat.type,
              let bot = try? await client.getUser(userId: type.userId), case .userTypeBot = bot.type,
              let found = try? await client.send(TDNativeRequests.searchWebApp(
                  botUserId: bot.id,
                  webAppShortName: link.webAppShortName,
              )),
              let result = try? await client.send(TDNativeRequests.getWebAppLinkUrl(
                  chatId: chatID,
                  botUserId: bot.id,
                  webAppShortName: link.webAppShortName,
                  startParameter: link.startParameter,
                  allowWriteAccess: true,
                  parameters: TDNativeWebAppOpenParameters(theme: theme, applicationName: "BetterTG", mode: link.mode),
              )),
              let url = URL(string: result.url)
        else { return nil }
        return WebAppLaunch(
            source: .menu(launchID: nil),
            url: url,
            requiresSameOrigin: result.requireSameOrigin,
            botUserID: bot.id,
            botName: found.webApp.title.isEmpty ? displayName(of: bot) : found.webApp.title,
            botUsername: bot.usernames?.activeUsernames.first,
            accountID: accountID,
            client: client,
            presentation: WebAppLaunch.Presentation(link.mode),
        )
    }

    /// The profile's Open App (PeerInfoProfileItems: `openWebApp(botPeer:chatPeer: nil, url: "", simple: true,
    /// source: .generic, skipTermsOfService: true)`) and a `startapp` link (OpenResolvedUrl's `.appStart`, with the
    /// terms). The page opens for the bot's own chat, Telegram's `chatPeer?.id ?? botId`, and in the mode the bot
    /// asks for.
    func openMainWebApp(
        bot: User,
        chatID: Int64,
        startParameter: String = "",
        mode: TDNativeWebAppOpenMode? = nil,
        skipsTerms: Bool,
    ) {
        guard case .userTypeBot(let type) = bot.type, type.hasMainWebApp else { return }
        prepare(bot: bot, skipsTerms: skipsTerms) { [weak self] in
            self?.requestMainWebApp(bot: bot, chatID: chatID, startParameter: startParameter, mode: mode)
        }
    }

    /// ChatTextInputPanelNode's menu button for a bot's `.webView` menu (ChatControllerOpenWebApp's
    /// `openWebApp(buttonText:url:simple: false, source: .menu)`, never skipping the terms): the main Web App's
    /// checks, then the button's page for the bot's chat and topic at half height (`fullSize: false`).
    func openMenuWebApp(bot: User, chatID: Int64, url: String, topic: MessageTopic?) {
        prepare(bot: bot, skipsTerms: false) { [weak self] in
            self?.requestMenuWebApp(bot: bot, chatID: chatID, url: url, topic: topic)
        }
    }

    /// webAppTermsAlertController, then `toggleBotIsAddedToAttachmentMenu` with the check as the write access
    /// (`addBotToAttachMenu(botId:allowWrite:)`); the launch follows once TDLib added the bot.
    func addAttachmentMenuBot(botUserID: Int64, cancelled: @escaping () -> Void = {}, added: @escaping () -> Void) {
        guard let presenter = host.presenter() else { return }
        let client = host.client
        let noticeKey = Self.noticeKey(accountID: host.accountID, botUserID: botUserID)
        let alert = WebAppTermsAlert.make(cancel: cancelled) { [weak self] allowWriteAccess in
            guard let self, task == nil else { return }
            #if DEBUG
                if Self.probeHTML != nil { return added() }
            #endif
            UserDefaults.standard.set(true, forKey: noticeKey)
            task = Task { [weak self] in
                let result = try? await client.send(TDNativeRequests.toggleBotIsAddedToAttachmentMenu(
                    botUserId: botUserID,
                    isAdded: true,
                    allowWriteAccess: allowWriteAccess,
                ))
                guard let self else { return }
                task = nil
                guard !Task.isCancelled, host.isCurrent() else { return }
                guard result != nil else { return showError() }
                added()
            }
        }
        presenter.present(alert, animated: true)
    }

    /// ChatControllerOpenAttachmentMenu's `.app` button: the terms for a bot that isn't added, then `openWebApp`
    /// without a URL in the chat, its topic and the composer's reply. The sheet opens at half height, as Telegram's
    /// attachment container does (`fullSize: false`).
    func openAttachmentMenuBot(
        botUserID: Int64,
        name: String,
        isAdded: Bool,
        chatID: Int64,
        topic: MessageTopic?,
        replyTo: InputMessageReplyTo?,
    ) {
        guard task == nil else { return }
        let open: () -> Void = { [weak self] in
            self?.requestAttachmentMenuWebApp(
                botUserID: botUserID,
                name: name,
                chatID: chatID,
                topic: topic,
                replyTo: replyTo,
            )
        }
        guard isAdded else { return addAttachmentMenuBot(botUserID: botUserID, added: open) }
        open()
    }

    #if DEBUG
        /// `-ui-probe-main-web-app`: Open App as for a bot that can join the attachment menu but hasn't, so the
        /// terms come first and then the probe page at full size.
        func openProbeMainWebApp(name: String) {
            addAttachmentMenuBot(botUserID: 0, added: { [weak self] in
                guard let self, let html = Self.probeHTML else { return }
                presentProbe(html: html, botUserID: 0, name: name, presentation: .fullSize)
            })
        }

        /// `-ui-probe-bot-menu-button`: the menu button as for a bot seen for the first time, so the launch
        /// confirmation comes first and then the probe page at half height. The made-up bot's notice is cleared on
        /// each run.
        func openProbeMenuWebApp(name: String) {
            let botUserID: Int64 = -1
            UserDefaults.standard.removeObject(forKey: Self.noticeKey(accountID: host.accountID, botUserID: botUserID))
            confirm(botUserID: botUserID, botName: name, attachmentMenuBot: nil, skipsTerms: false) { [weak self] in
                guard let self, let html = Self.probeHTML else { return }
                presentProbe(html: html, botUserID: botUserID, name: name, presentation: .compact)
            }
        }

        private func presentProbe(
            html: String,
            botUserID: Int64,
            name: String,
            presentation: WebAppLaunch.Presentation,
        ) {
            guard let url = URL(string: "https://bettertg.probe/") else { return }
            present(WebAppLaunch(
                source: .probe(html: html),
                url: url,
                requiresSameOrigin: false,
                botUserID: botUserID,
                botName: name,
                botUsername: nil,
                accountID: host.accountID,
                client: host.client,
                presentation: presentation,
            ))
        }
    #endif

    /// openWebAppImpl's `getAttachMenuBot(cached: true)` for a bot that can join the attachment menu, then the checks.
    private func prepare(bot: User, skipsTerms: Bool, open: @escaping () -> Void) {
        guard task == nil, case .userTypeBot(let type) = bot.type else { return }
        let client = host.client
        let canBeAdded = type.canBeAddedToAttachmentMenu
        task = Task { [weak self] in
            var attachmentMenuBot: TDNativeAttachmentMenuBot?
            if canBeAdded {
                attachmentMenuBot = try? await client.send(TDNativeRequests.getAttachmentMenuBot(botUserId: bot.id))
            }
            guard let self else { return }
            task = nil
            guard !Task.isCancelled, host.isCurrent() else { return }
            confirm(
                botUserID: bot.id,
                botName: Self.displayName(of: bot),
                attachmentMenuBot: attachmentMenuBot,
                skipsTerms: skipsTerms,
                open: open,
            )
        }
    }

    /// The checks before the page opens, in ChatControllerOpenWebApp's order.
    private func confirm(
        botUserID: Int64,
        botName: String,
        attachmentMenuBot: TDNativeAttachmentMenuBot?,
        skipsTerms: Bool,
        open: @escaping () -> Void,
    ) {
        if let attachmentMenuBot {
            guard attachmentMenuBot.isAdded else { return addAttachmentMenuBot(botUserID: botUserID, added: open) }
            return open()
        }
        let noticeKey = Self.noticeKey(accountID: host.accountID, botUserID: botUserID)
        guard !skipsTerms, !UserDefaults.standard.bool(forKey: noticeKey) else { return open() }
        guard let presenter = host.presenter() else { return }
        let terms = L10n.telegram("WebApp.LaunchTermsConfirmation")
            .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        let alert = UIAlertController(title: botName, message: terms, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("WebApp.LaunchOpenApp"), style: .default) { _ in
            UserDefaults.standard.set(true, forKey: noticeKey)
            open()
        })
        presenter.present(alert, animated: true)
    }

    /// `getMainWebApp`, then the sheet in the returned mode: compact at half height, full size expanded,
    /// fullscreen over the screen.
    private func requestMainWebApp(bot: User, chatID: Int64, startParameter: String, mode: TDNativeWebAppOpenMode?) {
        guard task == nil, let presenter = host.presenter() else { return }
        #if DEBUG
            if let html = Self.probeHTML {
                return presentProbe(
                    html: html,
                    botUserID: bot.id,
                    name: Self.displayName(of: bot),
                    presentation: .fullSize,
                )
            }
        #endif
        let client = host.client
        let accountID = host.accountID
        let parameters = TDNativeWebAppOpenParameters(
            theme: WebAppViewController.themeParameters(for: presenter.traitCollection),
            applicationName: "BetterTG",
            mode: mode,
        )
        task = Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.getMainWebApp(
                chatId: chatID,
                botUserId: bot.id,
                startParameter: startParameter,
                parameters: parameters,
            ))
            guard let self else { return }
            task = nil
            guard !Task.isCancelled, host.isCurrent() else { return }
            guard let result, let url = URL(string: result.url.url) else { return showError() }
            present(WebAppLaunch(
                source: .main,
                url: url,
                requiresSameOrigin: result.url.requireSameOrigin,
                botUserID: bot.id,
                botName: Self.displayName(of: bot),
                botUsername: bot.usernames?.activeUsernames.first,
                accountID: accountID,
                client: client,
                presentation: WebAppLaunch.Presentation(result.mode),
            ))
        }
    }

    private func requestAttachmentMenuWebApp(
        botUserID: Int64,
        name: String,
        chatID: Int64,
        topic: MessageTopic?,
        replyTo: InputMessageReplyTo?,
    ) {
        guard task == nil, let presenter = host.presenter() else { return }
        #if DEBUG
            if let html = Self.probeHTML {
                return presentProbe(html: html, botUserID: botUserID, name: name, presentation: .compact)
            }
        #endif
        let client = host.client
        let accountID = host.accountID
        let parameters = TDNativeWebAppOpenParameters(
            theme: WebAppViewController.themeParameters(for: presenter.traitCollection),
            applicationName: "BetterTG",
            mode: nil,
        )
        task = Task { [weak self] in
            let bot = try? await client.getUser(userId: botUserID)
            let info = try? await client.openWebApp(
                chatId: chatID,
                botUserId: botUserID,
                url: "",
                topicId: topic,
                replyTo: replyTo,
                parameters: parameters,
            )
            guard let self else {
                if let info { _ = try? await client.closeWebApp(webAppLaunchId: info.launchId) }
                return
            }
            task = nil
            guard !Task.isCancelled, host.isCurrent() else {
                if let info { _ = try? await client.closeWebApp(webAppLaunchId: info.launchId) }
                return
            }
            guard let info, let url = URL(string: info.url.url) else { return showError() }
            present(WebAppLaunch(
                source: .attachMenu(launchID: info.launchId),
                url: url,
                requiresSameOrigin: info.url.requireSameOrigin,
                botUserID: botUserID,
                botName: name,
                botUsername: bot?.usernames?.activeUsernames.first,
                accountID: accountID,
                client: client,
                presentation: .compact,
            ))
        }
    }

    /// WebAppController.setupWebView for `.menu`: `openWebApp` with the button's URL (`requestWebView(fromMenu:
    /// true)`) and no reply. A button linking to a named Web App on t.me (the `.peer(_, .appStart)` branch, TDLib's
    /// internalLinkTypeWebApp) opens that app instead, in the mode its link asks for.
    private func requestMenuWebApp(bot: User, chatID: Int64, url: String, topic: MessageTopic?) {
        guard task == nil, let presenter = host.presenter() else { return }
        let botName = Self.displayName(of: bot)
        #if DEBUG
            if let html = Self.probeHTML {
                return presentProbe(html: html, botUserID: bot.id, name: botName, presentation: .compact)
            }
        #endif
        let client = host.client
        let accountID = host.accountID
        let theme = WebAppViewController.themeParameters(for: presenter.traitCollection)
        let link = URL(string: url).flatMap { TelegramLinkRouter.internalLink(for: $0) }
        task = Task { [weak self] in
            var linkType: TDNativeInternalLinkType?
            if let link { linkType = try? await client.send(TDNativeRequests.getInternalLinkType(link: link)) }
            var launch: WebAppLaunch?
            if case .internalLinkTypeWebApp(let app) = linkType {
                launch = await Self.namedWebAppLaunch(
                    app,
                    chatID: chatID,
                    theme: theme,
                    client: client,
                    accountID: accountID,
                )
            } else if let info = try? await client.openWebApp(
                chatId: chatID,
                botUserId: bot.id,
                url: url,
                topicId: topic,
                replyTo: nil,
                parameters: TDNativeWebAppOpenParameters(theme: theme, applicationName: "BetterTG", mode: nil),
            ) {
                if let pageURL = URL(string: info.url.url) {
                    launch = WebAppLaunch(
                        source: .menu(launchID: info.launchId),
                        url: pageURL,
                        requiresSameOrigin: info.url.requireSameOrigin,
                        botUserID: bot.id,
                        botName: botName,
                        botUsername: bot.usernames?.activeUsernames.first,
                        accountID: accountID,
                        client: client,
                        presentation: .compact,
                    )
                } else {
                    _ = try? await client.closeWebApp(webAppLaunchId: info.launchId)
                }
            }
            guard let self else {
                if let launchID = launch?.launchID { _ = try? await client.closeWebApp(webAppLaunchId: launchID) }
                return
            }
            task = nil
            guard !Task.isCancelled, host.isCurrent() else {
                if let launchID = launch?.launchID { _ = try? await client.closeWebApp(webAppLaunchId: launchID) }
                return
            }
            guard let launch else { return showError() }
            present(launch)
        }
    }

    private func present(_ launch: WebAppLaunch) {
        guard let presenter = host.presenter() else {
            if let launchID = launch.launchID {
                let client = launch.client
                Task { _ = try? await client.closeWebApp(webAppLaunchId: launchID) }
            }
            return
        }
        presenter.present(WebAppViewController(launch: launch, actions: host.actions), animated: true)
    }

    private func showError() {
        guard let presenter = host.presenter(), presenter.presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: L10n.telegram("Login.UnknownError"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        presenter.present(alert, animated: true)
    }
}
