// GameViewController.swift

import TDLibKit
import UIKit
import WebKit

// MARK: - GameViewController

/// GameController: a bot's HTML5 game pushed over its chat, titled with the game over "@bot"
/// (GameControllerTitleView), in a web view below the bar that plays media inline and without a tap. The page reaches
/// the app through `TelegramWebviewProxy.postEvent` (GameControllerNode): `share_game` and the bar's Share send the
/// game's link, and `share_score` sends the game message with the player's score (`forwardGameWithScore`, an in-game
/// share) to a chosen chat.
@MainActor final class GameViewController: UIViewController {
    struct Game {
        let url: URL
        let title: String
        let shortName: String
        let botUsername: String?
        let chatID: Int64
        let messageID: Int64
    }

    /// WeakGameScriptMessageHandler: the content controller keeps its handler, which must not keep the screen.
    private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
        weak var target: GameViewController?

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated { target?.handleScriptMessage(message) }
        }
    }

    private static let proxyScript = """
    var TelegramWebviewProxyProto = function() {}; \
    TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) { \
    window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData}); \
    }; \
    var TelegramWebviewProxy = new TelegramWebviewProxyProto();
    """

    private let game: Game
    private let client: TDLibClient
    private let accountID: UUID
    private let scriptProxy = ScriptMessageProxy()
    private var webView: WKWebView?
    private var shareTask: Task<Void, Never>?

    /// The game's `https://t.me/<bot>?game=<name>` link, when the bot has a username.
    private var shareURL: String? {
        guard let username = game.botUsername, !username.isEmpty, !game.shortName.isEmpty else { return nil }
        return "https://t.me/\(username)?game=\(game.shortName)"
    }

    init(game: Game, client: TDLibClient, accountID: UUID) {
        self.game = game
        self.client = client
        self.accountID = accountID
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        navigationItem.titleView = makeTitleView()
        let share = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(sharePressed),
        )
        share.accessibilityLabel = L10n.telegram("Gallery.VoiceOver.Share")
        navigationItem.rightBarButtonItem = share
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        shareTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        scriptProxy.target = self

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Self.proxyScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
        ))
        contentController.add(scriptProxy, name: "performAction")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.webView = webView
        webView.load(URLRequest(url: game.url))
    }

    /// GameControllerTitleView: the game's title in 17 pt semibold over the bot's username in 13 pt.
    private func makeTitleView() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = game.title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        let subtitleLabel = UILabel()
        subtitleLabel.text = "@\(game.botUsername ?? "")"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        for label in [titleLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
        }
        stack.isAccessibilityElement = true
        stack.accessibilityTraits = .header
        stack.accessibilityLabel = "\(game.title), \(subtitleLabel.text ?? "")"
        return stack
    }

    // MARK: Sharing

    @objc private func sharePressed() {
        shareWithoutScore()
    }

    /// GameControllerNode's `handleScriptMessage`: only the share events, and only for a bot with a username.
    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let eventName = body["eventName"] as? String,
              eventName == "share_game" || eventName == "share_score", shareURL != nil else { return }
        if eventName == "share_score" {
            chooseChat { [weak self] chat, topic in self?.sendScore(to: chat, topic: topic) }
        } else {
            shareWithoutScore()
        }
    }

    /// `shareWithoutScore`: the game's link to a chosen chat.
    private func shareWithoutScore() {
        guard let shareURL else { return }
        chooseChat { [weak self] chat, topic in
            self?.send(.inputMessageText(InputMessageText(
                clearDraft: false,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: shareURL),
            )), to: chat, topic: topic, tooltip: L10n.telegram("Conversation.ShareLinkTooltip.Chat.One", chat.title))
        }
    }

    /// `forwardGameWithScore`: the game message as an in-game share, which carries the player's score.
    private func sendScore(to chat: Chat, topic: ForumTopic?) {
        send(.inputMessageForwarded(TDNativeInputMessageForwarded(
            fromChatId: game.chatID,
            messageId: game.messageID,
            inGameShare: true,
            replaceVideoStartTimestamp: false,
            newVideoStartTimestamp: 0,
            copyOptions: nil,
        )), to: chat, topic: topic, tooltip: nil)
    }

    /// ShareController's chats: the Forward picker's chats the user can write to outside secret chats.
    private func chooseChat(_ chosen: @escaping (Chat, ForumTopic?) -> Void) {
        let client = client
        let accountID = accountID
        guard presentedViewController == nil, TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id else { return }
        var seen = Set<Int64>()
        let seedChats = RootVM.shared.allFolders.flatMap(\.chats).map(\.chat).filter { seen.insert($0.id).inserted }
        guard let picker = ForwardMessagesViewController(
            choosingChatFor: .shareGame,
            client: client,
            accountID: accountID,
            seedChats: seedChats,
        ) else { return }
        picker.onChosenChat = { chat, topic in
            guard TDLib.shared.activeAccountID == accountID, TDLib.shared.activeClient.id == client.id else { return }
            chosen(chat.chat, topic)
        }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func send(_ content: InputMessageContent, to chat: Chat, topic: ForumTopic?, tooltip: String?) {
        let client = client
        let chatID = chat.id
        let topicID = topic
            .map { MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId)) }
        shareTask?.cancel()
        shareTask = Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.sendMessage(
                    chatId: chatID,
                    topicId: topicID,
                    replyTo: nil,
                    options: nil,
                    replyMarkup: nil,
                    inputMessageContent: content,
                ))
                guard let self, !Task.isCancelled, let tooltip else { return }
                TelegramUndoToast.show(text: tooltip.withoutTelegramMarkup, in: view, bottomInset: 12, undo: nil)
            } catch {
                guard let self, !Task.isCancelled else { return }
                TelegramUndoToast.show(
                    text: L10n.telegram("Login.UnknownError"),
                    in: view,
                    bottomInset: 12,
                    undo: nil,
                )
            }
        }
    }
}
