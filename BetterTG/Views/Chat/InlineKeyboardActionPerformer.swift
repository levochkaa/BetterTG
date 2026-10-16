// InlineKeyboardActionPerformer.swift

import TDLibKit
import UIKit

// MARK: - InlineKeyboardButtonPress

/// A pressed inline keyboard button, under a message or inside a rich message block.
struct InlineKeyboardButtonPress {
    let messageID: Int64
    let type: TDNativeInlineKeyboardButtonType
}

// MARK: - InlineTargetChatTypes

/// `targetChatTypes`: the kinds of chat a switch inline button may continue in.
struct InlineTargetChatTypes: Equatable {
    let users: Bool
    let bots: Bool
    let groups: Bool
    let channels: Bool

    /// No kind set: TDLib's empty `targetChatTypes`, which Telegram's `requestPeerTypes` treats as any chat.
    var isEmpty: Bool { !(users || bots || groups || channels) }

    init(_ types: TDNativeTargetChatTypes) {
        self.users = types.allowUserChats
        self.bots = types.allowBotChats
        self.groups = types.allowGroupChats
        self.channels = types.allowChannelChats
    }

    init(users: Bool, bots: Bool, groups: Bool, channels: Bool) {
        self.users = users
        self.bots = bots
        self.groups = groups
        self.channels = channels
    }
}

// MARK: - InlineKeyboardActionPerformer

/// Telegram's inline keyboard actions (ChatController `requestMessageActionCallback`, `openUrl`,
/// `activateSwitchInline`, `copyText`, `openPeer`). The chat runs them with its own client once the row's action
/// authority accepted the tap, and drops a late answer after the chat or client changed.
@MainActor final class InlineKeyboardActionPerformer {
    struct Host {
        let presenter: () -> UIViewController?
        let isCurrent: () -> Bool
        let showToast: (String) -> Void
        let openUserProfile: (Int64) -> Void
        let insertInlineQuery: (String) -> Void
        /// Picks a chat of the given kinds and puts the text into its composer.
        let chooseInlineChat: (_ text: String, _ types: InlineTargetChatTypes, _ messageID: Int64) -> Void
    }

    // MARK: Private

    /// Telegram's `isConcealedUrlWhitelisted` hosts, which open without the hidden link alert.
    private static let trustedHosts: Set = ["t.me", "telegram.me", "telegra.ph", "telesco.pe", "fragment.com"]

    private let host: Host
    private var tasks = [String: Task<Void, Never>]()

    init(host: Host) {
        self.host = host
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    // MARK: Internal

    static func isTrusted(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "tg" { return true }
        guard var hostName = url.host?.lowercased() else { return false }
        if hostName.hasPrefix("www.") { hostName.removeFirst(4) }
        if trustedHosts.contains(hostName) { return true }
        return hostName == "telegram.org" && (url.path.hasPrefix("/blog/") || url.path.hasPrefix("/tour/"))
    }

    private static func displayName(of user: User?) -> String {
        guard let user else { return "" }
        return [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func perform(_ press: InlineKeyboardButtonPress, in message: Message, client: TDLibClient) {
        guard host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
        switch press.type {
        case .inlineKeyboardButtonTypeUrl(let value):
            openURL(value.url, confirming: true)
        case .inlineKeyboardButtonTypeLoginUrl(let value):
            requestLoginURL(value, message: message, client: client)
        case .inlineKeyboardButtonTypeWebApp(let value):
            // A Web App screen with launch parameters (`openWebApp`) is not built yet; the page opens as a link.
            openURL(value.url, confirming: true)
        case .inlineKeyboardButtonTypeCallback(let value):
            requestAnswer(
                .callbackQueryPayloadData(.init(data: value.data)),
                key: "\(message.id):\(value.data.base64EncodedString())",
                message: message,
                client: client,
            )
        case .inlineKeyboardButtonTypeCallbackGame:
            guard case .messageGame(let game) = message.content else { return showUnsupported() }
            requestAnswer(
                .callbackQueryPayloadGame(.init(gameShortName: game.game.shortName)),
                key: "\(message.id):game",
                message: message,
                client: client,
            )
        case .inlineKeyboardButtonTypeSwitchInline(let value):
            switchInline(query: value.query, target: value.targetChat, message: message, client: client)
        case .inlineKeyboardButtonTypeUser(let value):
            host.openUserProfile(value.userId)
        case .inlineKeyboardButtonTypeCopyText(let value):
            UIPasteboard.setPlainText(value.text)
            host.showToast(L10n.telegram("Conversation.TextCopied"))
        case .inlineKeyboardButtonTypeCallbackWithPassword(let value):
            checkPasswordCallback(data: value.data, message: message, client: client)
        case .inlineKeyboardButtonTypeBuy:
            showUnsupported()
        case .inlineKeyboardButtonTypeDisabled:
            break
        }
    }

    /// The bot's answer is an alert when it asks for one, a short toast otherwise, and its URL opens without the
    /// hidden link alert (`openUrl(url, concealed: false)`). Telegram ignores failed callbacks.
    private func requestAnswer(
        _ payload: TDNativeCallbackQueryPayload,
        key: String,
        message: Message,
        client: TDLibClient,
    ) {
        guard tasks[key] == nil else { return }
        let chatID = message.chatId
        let messageID = message.id
        tasks[key] = Task { [weak self] in
            let answer = try? await client.getCallbackQueryAnswer(
                chatId: chatID,
                messageId: messageID,
                payload: payload,
            )
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id,
                  let answer else { return }
            show(answer)
        }
    }

    private func show(_ answer: TDNativeCallbackQueryAnswer) {
        if !answer.text.isEmpty {
            if answer.showAlert {
                showAlert(answer.text)
            } else {
                host.showToast(answer.text)
            }
        }
        if !answer.url.isEmpty { openURL(answer.url, confirming: false) }
    }

    // MARK: Login URLs

    /// ChatController's `requestMessageActionUrlAuth`: TDLib says whether the link opens as it is or asks to log in
    /// first. A failed check opens the button's own link as Telegram's `.default` result does.
    private func requestLoginURL(
        _ button: TDNativeInlineKeyboardButtonTypeLoginUrl,
        message: Message,
        client: TDLibClient,
    ) {
        let key = "\(message.id):login:\(button.id)"
        guard tasks[key] == nil else { return }
        let chatID = message.chatId
        let messageID = message.id
        let buttonID = button.id
        let defaultURL = button.url
        tasks[key] = Task { [weak self] in
            let info = try? await client.getLoginUrlInfo(chatId: chatID, messageId: messageID, buttonId: buttonID)
            var names: (bot: String, account: String)?
            if case .loginUrlInfoRequestConfirmation(let request) = info {
                async let bot = try? client.getUser(userId: request.botUserId)
                let account = try? await client.getMe()
                names = await (Self.displayName(of: bot), Self.displayName(of: account))
            }
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
            switch info {
            case .loginUrlInfoOpen(let open):
                openURL(open.url, confirming: !open.skipConfirmation)
            case .loginUrlInfoRequestConfirmation(let request):
                guard let presenter = host.presenter(), presenter.presentedViewController == nil else { return }
                let alert = BotLoginUrlAlert.make(
                    url: request.url,
                    domain: request.domain,
                    botName: names?.bot ?? "",
                    accountName: names?.account ?? "",
                    requestsWriteAccess: request.requestWriteAccess,
                ) { [weak self] authorize, allowWriteAccess in
                    guard let self else { return }
                    if authorize {
                        acceptLogin(
                            defaultURL: request.url,
                            allowWriteAccess: allowWriteAccess,
                            chatID: chatID,
                            messageID: messageID,
                            buttonID: buttonID,
                            client: client,
                        )
                    } else {
                        openURL(request.url, confirming: false)
                    }
                }
                presenter.present(alert, animated: true)
            case nil:
                openURL(defaultURL, confirming: false)
            }
        }
    }

    /// `acceptMessageActionUrlAuth`: the authorized link, else the plain one.
    private func acceptLogin(
        defaultURL: String,
        allowWriteAccess: Bool,
        chatID: Int64,
        messageID: Int64,
        buttonID: Int64,
        client: TDLibClient,
    ) {
        let key = "\(messageID):login:\(buttonID)"
        guard tasks[key] == nil, host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
        tasks[key] = Task { [weak self] in
            let authorized = try? await client.getLoginUrl(
                chatId: chatID,
                messageId: messageID,
                buttonId: buttonID,
                allowWriteAccess: allowWriteAccess,
            )
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
            openURL(authorized?.url ?? defaultURL, confirming: false)
        }
    }

    // MARK: Password callbacks

    /// ChatController's `requestMessageActionCallback` with `requiresPassword`: the session check
    /// (`requestMessageActionCallbackPasswordCheck`, which TDLib answers as canTransferOwnership) explains why the
    /// password can't be used yet (ownershipTransferController); otherwise the password prompt sends the callback.
    private func checkPasswordCallback(data: Data, message: Message, client: TDLibClient) {
        let key = "\(message.id):password:\(data.base64EncodedString())"
        guard tasks[key] == nil else { return }
        tasks[key] = Task { [weak self] in
            let result = try? await client.canTransferOwnership()
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
            switch result {
            case .canTransferOwnershipResultOk:
                presentPasswordPrompt(data: data, message: message, client: client, isRetry: false)
            case .canTransferOwnershipResultPasswordNeeded:
                // Telegram offers Enable 2-Step Verification here; BetterTG has no password setup screen.
                showSecurityCheck(comeBackLater: false)
            case .canTransferOwnershipResultPasswordTooFresh, .canTransferOwnershipResultSessionTooFresh:
                showSecurityCheck(comeBackLater: true)
            case nil:
                showAlert(L10n.telegram("Login.UnknownError"))
            }
        }
    }

    /// ownershipTransferController's security requirements, with "come back later" while the password or the
    /// session is too fresh.
    private func showSecurityCheck(comeBackLater: Bool) {
        var text = L10n.telegram("OwnershipTransfer.SecurityRequirements")
        if comeBackLater { text += L10n.telegram("OwnershipTransfer.ComeBackLater") }
        showAlert(
            text.replacingOccurrences(of: "**", with: ""),
            title: L10n.telegram("OwnershipTransfer.SecurityCheck"),
        )
    }

    /// commitOwnershipTransferController: the 2-Step Verification password, whose Transfer stays off while the field
    /// is empty. A wrong password asks again (Telegram shakes the field).
    private func presentPasswordPrompt(data: Data, message: Message, client: TDLibClient, isRetry: Bool) {
        guard let presenter = host.presenter(), presenter.presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.telegram("OwnershipTransfer.EnterPassword"),
            message: L10n
                .telegram(isRetry ? "TwoStepAuth.EnterPasswordInvalid" : "OwnershipTransfer.EnterPasswordText"),
            preferredStyle: .alert,
        )
        let transfer = UIAlertAction(
            title: L10n.telegram("OwnershipTransfer.Transfer"),
            style: .default,
        ) { [weak self, weak alert] _ in
            let password = alert?.textFields?.first?.text ?? ""
            self?.sendPasswordCallback(password: password, data: data, message: message, client: client)
        }
        transfer.isEnabled = false
        alert.addTextField { [weak transfer] field in
            field.isSecureTextEntry = true
            field.textContentType = .password
            field.placeholder = L10n.telegram("Channel.OwnershipTransfer.PasswordPlaceholder")
            field.addAction(UIAction { [weak field] _ in
                transfer?.isEnabled = field?.text?.isEmpty == false
            }, for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(transfer)
        alert.preferredAction = transfer
        presenter.present(alert, animated: true)
    }

    /// requestMessageActionCallback with the password, and its errors as commitOwnershipTransferController shows them.
    private func sendPasswordCallback(password: String, data: Data, message: Message, client: TDLibClient) {
        let key = "\(message.id):password:\(data.base64EncodedString())"
        guard tasks[key] == nil, host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
        let chatID = message.chatId
        let messageID = message.id
        tasks[key] = Task { [weak self] in
            let result: Result<TDNativeCallbackQueryAnswer, Error>
            do {
                result = try await .success(client.getCallbackQueryAnswer(
                    chatId: chatID,
                    messageId: messageID,
                    payload: .callbackQueryPayloadDataWithPassword(.init(password: password, data: data)),
                ))
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
            switch result {
            case .success(let answer):
                show(answer)
            case .failure(let error):
                let tdError = error as? TDLibError
                let description = tdError?.message ?? ""
                if description == "PASSWORD_HASH_INVALID" {
                    presentPasswordPrompt(data: data, message: message, client: client, isRetry: true)
                } else if tdError?.code == 429 || description.hasPrefix("FLOOD_WAIT") {
                    showAlert(L10n.telegram("TwoStepAuth.FloodError"))
                } else if description == "PASSWORD_MISSING" {
                    showSecurityCheck(comeBackLater: false)
                } else if description.hasPrefix("PASSWORD_TOO_FRESH_") || description.hasPrefix("SESSION_TOO_FRESH_") {
                    showSecurityCheck(comeBackLater: true)
                } else if description == "USER_PRIVACY_RESTRICTED" || description == "USER_BLOCKED" {
                    showAlert(L10n.telegram("Group.OwnershipTransfer.ErrorPrivacyRestricted"))
                } else {
                    showAlert(L10n.telegram("Login.UnknownError"))
                }
            }
        }
    }

    /// Telegram's switch inline button (`activateSwitchInline`): "@bot query" goes into this chat's composer, or a
    /// chosen chat's of the allowed kinds; an internal link target opens that link.
    private func switchInline(query: String, target: TDNativeTargetChat, message: Message, client: TDLibClient) {
        if case .targetChatInternalLink(let link) = target {
            openInternalLink(link.link, key: "\(message.id):inline-link", client: client)
            return
        }
        let botUserID: Int64? =
            if message.viaBotUserId != 0 {
                message.viaBotUserId
            } else if case .messageSenderUser(let sender) = message.senderId {
                sender.userId
            } else {
                nil
            }
        guard let botUserID else { return }
        let key = "\(message.id):inline"
        guard tasks[key] == nil else { return }
        let messageID = message.id
        tasks[key] = Task { [weak self] in
            let user = try? await client.getUser(userId: botUserID)
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id,
                  let username = user?.usernames?.activeUsernames.first, !username.isEmpty else { return }
            let text = "@\(username) \(query)"
            if case .targetChatChosen(let chosen) = target {
                host.chooseInlineChat(text, InlineTargetChatTypes(chosen.types), messageID)
            } else {
                host.insertInlineQuery(text)
            }
        }
    }

    /// TDLib's internal link as a tg:// URL, opened by the link router.
    private func openInternalLink(_ link: TDNativeInternalLinkType, key: String, client: TDLibClient) {
        guard tasks[key] == nil else { return }
        tasks[key] = Task { [weak self] in
            let url = try? await client.getInternalLink(type: link, isHttp: false)
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
            guard let url else { return showAlert(L10n.telegram("Login.UnknownError")) }
            openURL(url.url, confirming: false)
        }
    }

    /// Telegram's hidden link alert for button links outside its own hosts (`Generic.OpenHiddenLinkAlert`).
    private func openURL(_ string: String, confirming: Bool) {
        guard let url = getUrl(from: string) else { return }
        let open = { [weak self] in
            guard let self, host.isCurrent() else { return }
            TelegramLinkRouter.shared.open(url, from: host.presenter())
        }
        guard confirming, !Self.isTrusted(url) else { return open() }
        guard let presenter = host.presenter() else { return }
        let displayURL = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Generic.OpenHiddenLinkAlert", displayURL),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.No"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Yes"), style: .default) { _ in open() })
        presenter.present(alert, animated: true)
    }

    private func showAlert(_ text: String, title: String? = nil) {
        guard let presenter = host.presenter(), presenter.presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        presenter.present(alert, animated: true)
    }

    private func showUnsupported() {
        showAlert(L10n.betterTG("Chat.UnsupportedButtonBetterTG"))
    }
}
