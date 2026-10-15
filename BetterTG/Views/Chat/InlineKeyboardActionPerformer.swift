// InlineKeyboardActionPerformer.swift

import TDLibKit
import UIKit

// MARK: - InlineKeyboardButtonPress

/// A pressed inline keyboard button, under a message or inside a rich message block.
struct InlineKeyboardButtonPress {
    let messageID: Int64
    let type: TDNativeInlineKeyboardButtonType
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

    func perform(_ press: InlineKeyboardButtonPress, in message: Message, client: TDLibClient) {
        guard host.isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
        switch press.type {
        case .inlineKeyboardButtonTypeUrl(let value):
            openURL(value.url, confirming: true)
        case .inlineKeyboardButtonTypeLoginUrl(let value):
            // Telegram first asks the server to authorize the login (`requestMessageActionUrlAuth`); BetterTG opens
            // the link as an ordinary button link.
            openURL(value.url, confirming: true)
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
        case .inlineKeyboardButtonTypeBuy, .inlineKeyboardButtonTypeCallbackWithPassword:
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
            if !answer.text.isEmpty {
                if answer.showAlert {
                    showAlert(answer.text)
                } else {
                    host.showToast(answer.text)
                }
            }
            if !answer.url.isEmpty { openURL(answer.url, confirming: false) }
        }
    }

    /// Telegram's switch inline button for the current chat: the composer gets "@bot query". Choosing another chat
    /// needs a chat picker.
    private func switchInline(query: String, target: TDNativeTargetChat, message: Message, client: TDLibClient) {
        guard case .targetChatCurrent = target else { return showUnsupported() }
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
        tasks[key] = Task { [weak self] in
            let user = try? await client.getUser(userId: botUserID)
            guard let self else { return }
            tasks[key] = nil
            guard !Task.isCancelled, host.isCurrent(), TDLib.shared.activeClient.id == client.id,
                  let username = user?.usernames?.activeUsernames.first, !username.isEmpty else { return }
            host.insertInlineQuery("@\(username) \(query)")
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

    private func showAlert(_ text: String) {
        guard let presenter = host.presenter(), presenter.presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        presenter.present(alert, animated: true)
    }

    private func showUnsupported() {
        showAlert(L10n.betterTG("Chat.UnsupportedButtonBetterTG"))
    }
}
