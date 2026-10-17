// TelegramLinkRouter.swift

import Combine
import TDLibKit
import UIKit

// MARK: - TelegramLinkRouter

/// Telegram's openResolvedUrl for BetterTG. A link on Telegram's hosts or in the tg:// scheme is classified by
/// TDLib's `getInternalLinkType` on the active client and opens in the app; any other link, and a Telegram link
/// TDLib doesn't know or BetterTG can't show, leaves through Safari. A result is dropped when the account or client
/// that resolved it is no longer the active one, or when a newer link replaced it.
@MainActor final class TelegramLinkRouter {
    // MARK: Adding bots

    /// Where a bot's add link puts it: startgroup's group, whose start parameter goes to the bot, or startchannel's
    /// channel.
    enum BotAdditionTarget {
        case group(startParameter: String)
        case channel
    }

    /// A link that waits until the account is ready.
    private struct PendingLink {
        let link: String
        let url: URL
    }

    static let shared = TelegramLinkRouter()

    /// LinkManager::get_link_info keeps these t.me subdomains for its own paths; they aren't usernames.
    private static let reservedSubdomains: Set = [
        "addemoji", "addlist", "addstickers", "addstyle", "addtheme", "auction", "auth", "boost", "call",
        "confirmphone", "contact", "giftcode", "invoice", "joinchat", "login", "m", "nft", "proxy", "setlanguage",
        "share", "socks", "web", "a", "k", "z",
    ]

    private var cancellables = Set<AnyCancellable>()
    private var pendingLink: PendingLink?
    private weak var pendingWindow: UIWindow?
    private var resolveTask: Task<Void, Never>?
    /// OpenUserGeneratedUrl's loading overlay over the link that is resolving.
    private var resolveProgress: LinkResolutionProgressView?
    /// The `startapp` link's launch, through its terms and `getMainWebApp`.
    private var mainWebAppLauncher: WebAppLauncher?
    /// The `startattach` link's terms and `toggleBotIsAddedToAttachmentMenu` for a bot that isn't added.
    private var attachmentMenuBotLauncher: WebAppLauncher?

    private init() {
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            DispatchQueue.main.async { self?.openPendingLink() }
        }
    }

    // MARK: Classification

    /// The link TDLib classifies, in LinkManager::get_link_info's forms: the tg: scheme (BetterTG's own bettertg:
    /// scheme, the one iOS hands the app, stands for it), and http or https on t.me, telegram.me, telegram.dog or a
    /// username's t.me subdomain, on the default port and without credentials. Nil for every other URL.
    static func internalLink(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        switch scheme {
        case "tg":
            return url.absoluteString
        case "bettertg":
            return "tg:" + url.absoluteString.dropFirst(scheme.count + 1)
        case "http", "https":
            guard components.user == nil, components.password == nil,
                  components.port == nil || components.port == 80 || components.port == 443,
                  let host = components.host?.lowercased() else { return nil }
            if host.hasSuffix(".t.me") {
                let subdomain = String(host.dropLast(5))
                if subdomain != "www" {
                    guard isTelegramUsername(subdomain), !reservedSubdomains.contains(subdomain) else { return nil }
                    return url.absoluteString
                }
            }
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return ["t.me", "telegram.me", "telegram.dog"].contains(domain) ? url.absoluteString : nil
        default:
            return nil
        }
    }

    /// TDLib's is_valid_username: a Latin letter, then letters, digits and single underscores, up to 32 characters,
    /// not ending with an underscore.
    static func isTelegramUsername(_ value: String) -> Bool {
        let characters = Array(value.utf8)
        guard let first = characters.first, characters.count <= 32, characters.last != UInt8(ascii: "_"),
              isLatinLetter(first) else { return false }
        var previous: UInt8 = 0
        for character in characters {
            let isUnderscore = character == UInt8(ascii: "_")
            guard isLatinLetter(character) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(character)
                || isUnderscore else { return false }
            if isUnderscore, previous == UInt8(ascii: "_") { return false }
            previous = character
        }
        return true
    }

    private static func isLatinLetter(_ character: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(character)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(character)
    }

    // MARK: Opening

    /// Opens a Telegram link in the app, and any other link in Safari.
    func open(_ url: URL, from presenter: UIViewController?) {
        guard handle(url, from: presenter) else {
            UIApplication.shared.open(url)
            return
        }
    }

    /// True when the link is Telegram's and the router took it, even if it waits for the account to be ready.
    @discardableResult func handle(_ url: URL, from presenter: UIViewController?) -> Bool {
        guard let link = Self.internalLink(for: url) else { return false }
        guard TDLib.shared.isActiveAccountReady else {
            pendingLink = PendingLink(link: link, url: url)
            pendingWindow = presenter?.viewIfLoaded?.window
            return true
        }
        presenter?.viewIfLoaded?.endEditing(true)
        resolve(link, url: url, from: presenter)
        return true
    }

    /// A text mention of a user (`textEntityTypeMentionName`) opens the user's chat on the active client, as
    /// ChatMessageBubbleItemNode's peerMention tap does.
    func openUser(_ userID: Int64, from presenter: UIViewController?) {
        guard TDLib.shared.isActiveAccountReady else { return }
        presenter?.viewIfLoaded?.endEditing(true)
        resolveTask?.cancel()
        let authority = ChatListActionAuthority()
        resolveTask = Task { [weak self, weak presenter] in
            await self?.openUser(userID, authority: authority, presenter: presenter, profile: false)
        }
    }

    #if DEBUG
        /// `-ui-probe-startattach`: an attachment menu bot link's flow for a made-up bot, from its terms on.
        func probeAttachmentMenuBot(_ bot: TDNativeAttachmentMenuBot, target: TDNativeTargetChat) {
            let presenter = NavigationStorage.shared.navigationController.topViewController
            startAttachmentMenuBot(
                bot,
                target: target,
                url: "probe",
                authority: ChatListActionAuthority(),
                presenter: presenter,
            )
        }
    #endif

    /// A story's message area (StoryItemSetContainerViewSendMessage's openResolved .channelMessage): the message's
    /// chat on the active client, at the message, once the story viewer over it closes.
    func openMessage(chatID: Int64, messageID: Int64, from presenter: UIViewController?) {
        guard TDLib.shared.isActiveAccountReady else { return }
        resolveTask?.cancel()
        let authority = ChatListActionAuthority()
        resolveTask = Task { [weak self, weak presenter] in
            await self?.openChat(chatID, authority: authority, presenter: presenter, messageID: messageID)
        }
    }

    private func openPendingLink() {
        guard TDLib.shared.isActiveAccountReady, let pending = pendingLink else { return }
        pendingLink = nil
        resolve(pending.link, url: pending.url, from: pendingWindow?.rootViewController)
    }

    private func resolve(_ link: String, url: URL, from presenter: UIViewController?) {
        resolveTask?.cancel()
        let authority = ChatListActionAuthority()
        let client = authority.client
        let window = presenter?.viewIfLoaded?.window ?? NavigationStorage.shared.navigationController.viewIfLoaded?
            .window
        let task = Task { [weak self, weak presenter] in
            #if DEBUG
                // `-ui-probe-slow-links`: OpenUserGeneratedUrl's DEBUG delay, so the loading overlay shows.
                if ProcessInfo.processInfo.arguments.contains("-ui-probe-slow-links") {
                    try? await Task.sleep(for: .seconds(2))
                }
            #endif
            let type = try? await client.send(TDNativeRequests.getInternalLinkType(link: link))
            guard let self, !Task.isCancelled, authority.isCurrent else { return }
            guard let type else {
                openExternally(url)
                return
            }
            await route(type, url: url, authority: authority, presenter: presenter)
        }
        resolveTask = task
        showResolveProgress(for: task, in: window)
    }

    /// OpenUserGeneratedUrl's progress: Telegram's loading overlay appears once a link needs the network, and a tap
    /// on it cancels the link. TDLib doesn't say when a request leaves its cache, so the overlay appears when the link
    /// is still resolving after a moment, and leaves when the link has opened what it leads to.
    private func showResolveProgress(for task: Task<Void, Never>, in window: UIWindow?) {
        resolveProgress?.finish()
        guard let window else { return }
        let progress = LinkResolutionProgressView { task.cancel() }
        resolveProgress = progress
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak progress, weak window] in
            guard let progress, let window else { return }
            progress.show(in: window)
        }
        Task { [weak self, weak progress] in
            await task.value
            progress?.finish()
            if self?.resolveProgress === progress { self?.resolveProgress = nil }
        }
    }

    /// OpenResolvedUrl's cases BetterTG has screens for. Sign-in links stay out of the browser; the rest of Telegram's
    /// link types (other web apps, proxies, payments, Premium, gifts, calls) open their t.me page in Safari.
    private func route(
        _ type: TDNativeInternalLinkType,
        url: URL,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        let client = authority.client
        switch type {
        case .internalLinkTypePublicChat(let value):
            guard let chat = await publicChat(value.chatUsername, authority: authority, presenter: presenter)
            else { return }
            await openChat(chat.id, authority: authority, presenter: presenter, profile: value.openProfile)
        case .internalLinkTypeBotStart(let value):
            guard let chat = await publicChat(value.botUsername, authority: authority, presenter: presenter)
            else { return }
            await openChat(chat.id, authority: authority, presenter: presenter, botStartParameter: value.startParameter)
        case .internalLinkTypeBotStartInGroup(let value):
            await addBot(
                value.botUsername,
                to: .group(startParameter: value.startParameter),
                requestedRights: value.administratorRights,
                authority: authority,
                presenter: presenter,
            )
        case .internalLinkTypeBotAddToChannel(let value):
            await addBot(
                value.botUsername,
                to: .channel,
                requestedRights: value.administratorRights,
                authority: authority,
                presenter: presenter,
            )
        case .internalLinkTypeMessageDraft(let value):
            presentChatPicker(.messageDraft, authority: authority, presenter: presenter) { [weak self] chat, topic in
                await self?.openChat(
                    chat.id,
                    authority: authority,
                    presenter: presenter,
                    topic: topic,
                    linkDraft: value.text,
                )
            }
        case .internalLinkTypeGame(let value):
            await shareGame(
                value.gameShortName,
                botUsername: value.botUsername,
                authority: authority,
                presenter: presenter,
            )
        case .internalLinkTypeMainWebApp(let value):
            await openMainWebApp(value, authority: authority, presenter: presenter)
        case .internalLinkTypeAttachmentMenuBot(let value):
            await openAttachmentMenuBot(value, authority: authority, presenter: presenter)
        case .internalLinkTypeMessage(let value):
            await openMessage(value.url, authority: authority, presenter: presenter)
        case .internalLinkTypeChatInvite(let value):
            await openChatInvite(value.inviteLink, authority: authority, presenter: presenter)
        case .internalLinkTypeUserPhoneNumber(let value):
            let user = try? await client.send(TDNativeRequests.searchUserByPhoneNumber(
                phoneNumber: value.phoneNumber,
                onlyLocal: false,
            ))
            await openUser(user?.id, authority: authority, presenter: presenter, profile: value.openProfile)
        case .internalLinkTypeUserToken(let value):
            let user = try? await client.send(TDNativeRequests.searchUserByToken(token: value.token))
            await openUser(user?.id, authority: authority, presenter: presenter, profile: false)
        case .internalLinkTypeSavedMessages:
            let me = try? await client.getMe()
            await openUser(me?.id, authority: authority, presenter: presenter, profile: false)
        case .internalLinkTypeStickerSet(let value):
            await openStickerSet(value.stickerSetName, authority: authority, presenter: presenter)
        case .internalLinkTypeStory(let value):
            await openStory(
                value.storyPosterUsername,
                storyID: value.storyId,
                authority: authority,
                presenter: presenter,
            )
        case .internalLinkTypeChatFolderInvite(let value):
            guard let host = presentationHost(presenter) else { return }
            ChatFolderInviteLinkPreviewViewController.present(inviteLink: value.inviteLink, from: host)
        case .internalLinkTypeLanguagePack(let value):
            presentationHost(presenter)?.present(
                LanguagePackPreviewViewController(identifier: value.languagePackId),
                animated: true,
            )
        case .internalLinkTypeSettings(let value):
            openSettings(value.section)
        case .internalLinkTypeMyProfilePage:
            openSettings(nil)
        case .internalLinkTypeUnknownDeepLink(let value):
            // OpenResolvedUrl's `.unknownDeepLink`: TDLib's text for a link this version doesn't know, if any.
            let info = try? await client.send(TDNativeRequests.getDeepLinkInfo(link: value.link))
            guard !Task.isCancelled, authority.isCurrent, let text = info?.text.text, !text.isEmpty else { return }
            presentAlert(text, presenter: presenter)
        case .internalLinkTypeAuthenticationCode, .internalLinkTypeOauth, .internalLinkTypePassportDataRequest,
             .internalLinkTypePhoneNumberConfirmation, .internalLinkTypeQrCodeAuthentication:
            break
        default:
            openExternally(url)
        }
    }

    // MARK: Destinations

    /// UrlHandling's `.peer(.name)`: `searchPublicChat`, or Telegram's "doesn't seem to exist" alert.
    private func publicChat(
        _ username: String,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async -> Chat? {
        let chat = try? await authority.client.send(TDNativeRequests.searchPublicChat(username: username))
        guard !Task.isCancelled, authority.isCurrent else { return nil }
        if chat == nil { presentAlert(L10n.telegram("Resolve.ErrorNotFound"), presenter: presenter) }
        return chat
    }

    /// A user's private chat, as a phone number, a contact token or Saved Messages resolves to.
    private func openUser(
        _ userID: Int64?,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
        profile: Bool,
    ) async {
        guard !Task.isCancelled, authority.isCurrent else { return }
        guard let userID,
              let chat = try? await authority.client.createPrivateChat(force: false, userId: userID)
        else {
            if authority.isCurrent { presentAlert(L10n.telegram("Resolve.ErrorNotFound"), presenter: presenter) }
            return
        }
        await openChat(chat.id, authority: authority, presenter: presenter, profile: profile)
    }

    /// OpenResolvedUrl's `.peer(bot, .appStart(payload, mode))`: a bot with a main Web App opens it for its own chat
    /// (`openWebApp(… url: "", simple: true, source: .generic, payload:)`, with the terms); any other chat opens.
    private func openMainWebApp(
        _ link: TDNativeInternalLinkTypeMainWebApp,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        guard let chat = await publicChat(link.botUsername, authority: authority, presenter: presenter) else { return }
        var bot: User?
        if case .chatTypePrivate(let type) = chat.type {
            bot = try? await authority.client.getUser(userId: type.userId)
        }
        guard !Task.isCancelled, authority.isCurrent else { return }
        guard let bot, case .userTypeBot(let type) = bot.type, type.hasMainWebApp,
              let accountID = authority.source?.accountID
        else {
            await openChat(chat.id, authority: authority, presenter: presenter)
            return
        }
        let launcher = WebAppLauncher(host: .init(
            accountID: accountID,
            client: authority.client,
            presenter: { [weak self, weak presenter] in self?.presentationHost(presenter) },
            isCurrent: { authority.isCurrent },
            actions: .init(
                openTelegramLink: { [weak self] url in self?.open(url, from: nil) },
                switchInline: { _, _ in },
            ),
        ))
        mainWebAppLauncher = launcher
        launcher.openMainWebApp(
            bot: bot,
            chatID: chat.id,
            startParameter: link.startParameter,
            mode: link.mode,
            skipsTerms: false,
        )
    }

    /// OpenResolvedUrl's `.startAttach`: the link's bot must be one that can join the attachment menu
    /// (`getAttachMenuBot`), or Telegram's unavailable notice shows.
    private func openAttachmentMenuBot(
        _ link: TDNativeInternalLinkTypeAttachmentMenuBot,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        guard let chat = await publicChat(link.botUsername, authority: authority, presenter: presenter) else { return }
        let client = authority.client
        var bot: TDNativeAttachmentMenuBot?
        if case .chatTypePrivate(let type) = chat.type,
           let user = try? await client.getUser(userId: type.userId),
           case .userTypeBot(let info) = user.type, info.canBeAddedToAttachmentMenu
        {
            bot = try? await client.send(TDNativeRequests.getAttachmentMenuBot(botUserId: user.id))
        }
        guard !Task.isCancelled, authority.isCurrent else { return }
        guard let bot else {
            presentToast(L10n.telegram("WebApp.AddToAttachmentUnavailableError"), presenter: presenter)
            return
        }
        startAttachmentMenuBot(bot, target: link.targetChat, url: link.url, authority: authority, presenter: presenter)
    }

    /// The rest of `.startAttach`: a bot that isn't added gets webAppTermsAlertController and
    /// `toggleBotIsAddedToAttachmentMenu` first (the unavailable notice if TDLib refuses), then the link's chat.
    private func startAttachmentMenuBot(
        _ bot: TDNativeAttachmentMenuBot,
        target: TDNativeTargetChat,
        url: String,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) {
        let launch: (Bool) -> Void = { [weak self, weak presenter] justInstalled in
            guard let self, authority.isCurrent else { return }
            let start = AttachmentMenuBotStart(bot: bot, url: url, justInstalled: justInstalled)
            resolveTask?.cancel()
            resolveTask = Task { [weak self, weak presenter] in
                await self?.openAttachmentMenuBotTarget(
                    target,
                    start: start,
                    authority: authority,
                    presenter: presenter,
                )
            }
        }
        guard !bot.isAdded else { return launch(false) }
        guard let accountID = authority.source?.accountID else { return }
        let launcher = WebAppLauncher(host: .init(
            accountID: accountID,
            client: authority.client,
            presenter: { [weak self, weak presenter] in self?.presentationHost(presenter) },
            isCurrent: { authority.isCurrent },
            actions: .init(
                openTelegramLink: { [weak self] url in self?.open(url, from: nil) },
                switchInline: { _, _ in },
            ),
        ))
        attachmentMenuBotLauncher = launcher
        launcher.addAttachmentMenuBot(
            botUserID: bot.botUserId,
            failed: { [weak self, weak presenter] in
                self?.presentToast(L10n.telegram("WebApp.AddToAttachmentUnavailableError"), presenter: presenter)
            },
            added: { launch(true) },
        )
    }

    /// `.startAttach`'s chat: Select Chat among the kinds both the link and the bot allow (`filterChooseTypes`),
    /// the chat the link names, or the chat the link was opened in (`urlContext .chat`), where ChatController's
    /// `attachBotStart` launches the bot. With no chat, an added bot gets Telegram's already-added notice.
    private func openAttachmentMenuBotTarget(
        _ target: TDNativeTargetChat,
        start: AttachmentMenuBotStart,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        let bot = start.bot
        switch target {
        case .targetChatChosen(let chosen):
            let types = InlineTargetChatTypes(
                users: chosen.types.allowUserChats && bot.supportsUserChats,
                bots: chosen.types.allowBotChats && bot.supportsBotChats,
                groups: chosen.types.allowGroupChats && bot.supportsGroupChats,
                channels: chosen.types.allowChannelChats && bot.supportsChannelChats,
            )
            guard types.isEmpty else {
                return presentAttachmentMenuBotPicker(types, start: start, authority: authority, presenter: presenter)
            }
            openAttachmentMenuBotInCurrentChat(start, authority: authority, presenter: presenter)
        case .targetChatCurrent:
            openAttachmentMenuBotInCurrentChat(start, authority: authority, presenter: presenter)
        case .targetChatInternalLink(let value):
            let client = authority.client
            var chatID: Int64?
            switch value.link {
            case .internalLinkTypePublicChat(let link):
                guard let chat = await publicChat(link.chatUsername, authority: authority, presenter: presenter)
                else { return }
                chatID = chat.id
            case .internalLinkTypeUserPhoneNumber(let link):
                if let user = try? await client.send(TDNativeRequests.searchUserByPhoneNumber(
                    phoneNumber: link.phoneNumber,
                    onlyLocal: false,
                )) {
                    chatID = try? await client.createPrivateChat(force: false, userId: user.id).id
                }
            default:
                break
            }
            guard !Task.isCancelled, authority.isCurrent else { return }
            guard let chatID else {
                presentAlert(L10n.telegram("Resolve.ErrorNotFound"), presenter: presenter)
                return
            }
            await openChat(chatID, authority: authority, presenter: presenter, attachmentMenuBotStart: start)
        }
    }

    private func openAttachmentMenuBotInCurrentChat(
        _ start: AttachmentMenuBotStart,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) {
        guard let chat = presenter as? ChatViewController, chat.viewIfLoaded?.window != nil else {
            if !start.justInstalled {
                presentToast(L10n.telegram("WebApp.AddToAttachmentAlreadyAddedError"), presenter: presenter)
            }
            return
        }
        afterDismissingPresentations { [weak chat] in
            guard authority.isCurrent else { return }
            chat?.beginAttachmentMenuBot(start)
        }
    }

    /// PeerSelectionController titled Select Chat with `onlyWriteable` and the allowed kinds; the chosen chat (or
    /// forum topic) opens with the bot.
    private func presentAttachmentMenuBotPicker(
        _ types: InlineTargetChatTypes,
        start: AttachmentMenuBotStart,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) {
        var seen = Set<Int64>()
        let seedChats = RootVM.shared.allFolders.flatMap(\.chats).map(\.chat).filter { seen.insert($0.id).inserted }
        guard let accountID = authority.source?.accountID, let host = presentationHost(presenter),
              let picker = ForwardMessagesViewController(
                  choosingChatFor: .attachmentMenuBot(types),
                  client: authority.client,
                  accountID: accountID,
                  seedChats: seedChats,
              )
        else { return }
        picker.onChosenChat = { [weak self, weak presenter] chat, topic in
            guard let self, authority.isCurrent else { return }
            resolveTask?.cancel()
            resolveTask = Task { [weak self, weak presenter] in
                await self?.openChat(
                    chat.id,
                    authority: authority,
                    presenter: presenter,
                    topic: topic,
                    attachmentMenuBotStart: start,
                )
            }
        }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .fullScreen
        host.present(navigation, animated: true)
    }

    // MARK: Chat pickers

    /// PeerSelectionController for a link's chat: the chosen chat, or forum topic, goes to `chosen` once the
    /// picker has closed.
    private func presentChatPicker(
        _ purpose: ForwardMessagesViewController.Purpose,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
        chosen: @escaping @MainActor (CustomChat, ForumTopic?) async -> Void,
    ) {
        var seen = Set<Int64>()
        let seedChats = RootVM.shared.allFolders.flatMap(\.chats).map(\.chat).filter { seen.insert($0.id).inserted }
        guard let accountID = authority.source?.accountID, let host = presentationHost(presenter),
              let picker = ForwardMessagesViewController(
                  choosingChatFor: purpose,
                  client: authority.client,
                  accountID: accountID,
                  seedChats: seedChats,
              )
        else { return }
        picker.onChosenChat = { [weak self] chat, topic in
            guard let self, authority.isCurrent else { return }
            resolveTask?.cancel()
            resolveTask = Task { await chosen(chat, topic) }
        }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .fullScreen
        host.present(navigation, animated: true)
    }

    /// OpenResolvedUrl's `.gameStart`: a chat to share the bot's game with, Telegram's confirmation, the game sent
    /// there, and the chat or topic opened.
    private func shareGame(
        _ shortName: String,
        botUsername: String,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        guard let botChat = await publicChat(botUsername, authority: authority, presenter: presenter),
              case .chatTypePrivate(let botType) = botChat.type else { return }
        let botUserID = botType.userId
        presentChatPicker(.shareGame, authority: authority, presenter: presenter) { [weak self] chat, topic in
            guard let self, let host = presentationHost(presenter) else { return }
            let key =
                if case .chatTypePrivate = chat.chat.type {
                    "Target.ShareGameConfirmationPrivate"
                } else {
                    "Target.ShareGameConfirmationGroup"
                }
            let alert = UIAlertController(
                title: nil,
                message: L10n.telegram(key, chat.chat.title),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(
                title: L10n.telegram("RequestPeer.SelectionConfirmationSend"),
                style: .default,
            ) { [weak self] _ in
                self?.sendGame(
                    shortName,
                    botUserID: botUserID,
                    to: chat,
                    topic: topic,
                    authority: authority,
                    presenter: presenter,
                )
            })
            host.present(alert, animated: true)
        }
    }

    private func sendGame(
        _ shortName: String,
        botUserID: Int64,
        to chat: CustomChat,
        topic: ForumTopic?,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) {
        guard authority.isCurrent else { return }
        let client = authority.client
        let topicID = topic
            .map { MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId)) }
        resolveTask?.cancel()
        resolveTask = Task { [weak self, weak presenter] in
            do {
                _ = try await client.send(TDNativeRequests.sendMessage(
                    chatId: chat.id,
                    topicId: topicID,
                    replyTo: nil,
                    options: nil,
                    replyMarkup: nil,
                    inputMessageContent: .inputMessageGame(InputMessageGame(
                        botUserId: botUserID,
                        gameShortName: shortName,
                    )),
                ))
                guard let self, !Task.isCancelled, authority.isCurrent else { return }
                await openChat(chat.id, authority: authority, presenter: presenter, topic: topic)
            } catch {
                guard let self, !Task.isCancelled, authority.isCurrent else { return }
                presentAlert(L10n.telegram("Login.UnknownError"), presenter: presenter)
            }
        }
    }

    /// OpenResolvedUrl's `.groupBotStart`: the groups or channels the user manages, then the bot's admin rights
    /// where the user may add admins, or Telegram's Add Bot as Member confirmation elsewhere.
    private func addBot(
        _ username: String,
        to destination: BotAdditionTarget,
        requestedRights: ChatAdministratorRights?,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        let client = authority.client
        guard let botChat = await publicChat(username, authority: authority, presenter: presenter) else { return }
        guard case .chatTypePrivate(let botType) = botChat.type,
              let bot = try? await client.getUser(userId: botType.userId),
              case .userTypeBot(let info) = bot.type
        else {
            guard !Task.isCancelled, authority.isCurrent else { return }
            await openChat(botChat.id, authority: authority, presenter: presenter)
            return
        }
        guard !Task.isCancelled, authority.isCurrent else { return }
        let payload: String
        let isStartGroup: Bool
        switch destination {
        case .group(let startParameter):
            // A bot that can't join groups only has its chat to offer.
            guard info.canJoinGroups else {
                await openChat(botChat.id, authority: authority, presenter: presenter)
                return
            }
            payload = startParameter
            isStartGroup = true
        case .channel:
            payload = ""
            isStartGroup = false
        }
        // An empty set of rights in the link means it asked for none (ResolvedBotAdminRights is nil).
        let requested = requestedRights.map(AdminRightsSet.init).flatMap { rights in
            var withoutManagement = rights
            withoutManagement.canManageChat = false
            return withoutManagement == AdminRightsSet.none ? nil : rights
        }
        let types = InlineTargetChatTypes(users: false, bots: false, groups: isStartGroup, channels: !isStartGroup)
        presentChatPicker(.addBot(types), authority: authority, presenter: presenter) { [weak self] chat, _ in
            await self?.addBot(
                bot,
                to: chat.id,
                payload: payload,
                isStartGroup: isStartGroup,
                requested: requested,
                authority: authority,
                presenter: presenter,
            )
        }
    }

    /// The chosen group or channel: a forced start, a bot that is already an admin, or a chat where the user can't
    /// add admins takes the member confirmation; otherwise the admin rights screen opens with the link's rights or
    /// the bot's defaults.
    private func addBot(
        _ bot: User,
        to chatID: Int64,
        payload: String,
        isStartGroup: Bool,
        requested: AdminRightsSet?,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        let client = authority.client
        guard let target = await ChatManagementTarget.load(chatID: chatID, client: client),
              !Task.isCancelled, authority.isCurrent else { return }
        let forcesStart = isStartGroup && !payload.isEmpty && requested == nil
        let checksExistingAdmin = isStartGroup && !payload.isEmpty && requested != nil
        let botSender = MessageSender.user(bot.id)
        let botStatus = try? await client.send(TDNativeRequests.getChatMember(chatId: chatID, memberId: botSender))
            .status
        guard !Task.isCancelled, authority.isCurrent else { return }
        let botIsAdmin =
            switch botStatus {
            case .chatMemberStatusAdministrator, .chatMemberStatusCreator: true
            default: false
            }
        let opensRights: Bool
        switch target.group {
        case .supergroup:
            let canAddAdmins = target.isCreator || target.rights?.canPromoteMembers == true
            opensRights = !forcesStart && canAddAdmins && !(checksExistingAdmin && !target.isChannel && botIsAdmin)
        case .basic:
            let isMember =
                if case .chatMemberStatusMember = target.status {
                    true
                } else {
                    false
                }
            opensRights = !forcesStart && !isMember && !(checksExistingAdmin && botIsAdmin)
        }
        guard opensRights else {
            confirmBotMember(bot, target: target, payload: payload, authority: authority, presenter: presenter)
            return
        }
        var rights = requested
        if rights == nil, let botInfo = try? await client.getUserFullInfo(userId: bot.id).botInfo {
            rights = (target.isChannel
                ? botInfo.defaultChannelAdministratorRights
                : botInfo.defaultGroupAdministratorRights)
                .map(AdminRightsSet.init)
        }
        guard !Task.isCancelled, authority.isCurrent,
              let peer = await SettingsPeer.resolve(botSender, client: client), authority.isCurrent else { return }
        let member = ChatManagementMember(
            sender: botSender,
            peer: peer,
            status: botStatus ?? .chatMemberStatusLeft,
            tag: "",
        )
        afterDismissingPresentations { [weak self] in
            guard authority.isCurrent else { return }
            let navigation = NavigationStorage.shared.navigationController
            let editor = ChatAdminRightsViewController(
                target: target,
                member: member,
                isNew: true,
                botInvite: .init(requestedRights: rights) { [weak self, weak navigation] in
                    navigation?.popViewController(animated: true)
                    guard checksExistingAdmin else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.confirmBotMember(
                            bot,
                            target: target,
                            payload: payload,
                            authority: authority,
                            presenter: presenter,
                        )
                    }
                },
            )
            navigation.pushViewController(editor, animated: true)
        }
    }

    /// Bot.AddToChat.Add.MemberAlert: the bot joins, or with a start parameter is started in the group, which then
    /// opens.
    private func confirmBotMember(
        _ bot: User,
        target: ChatManagementTarget,
        payload: String,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) {
        guard authority.isCurrent, let host = presentationHost(presenter) else { return }
        let key = target.isChannel
            ? "Bot.AddToChat.Add.MemberAlertTextChannel"
            : "Bot.AddToChat.Add.MemberAlertTextGroup"
        let alert = UIAlertController(
            title: L10n.telegram("Bot.AddToChat.Add.MemberAlertTitle"),
            message: L10n.telegram(key, target.chat.title).withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Bot.AddToChat.Add.MemberAlertAdd"), style: .default) {
            [weak self] _ in
            self?.addBotMember(bot, to: target.chatID, payload: payload, authority: authority, presenter: presenter)
        })
        host.present(alert, animated: true)
    }

    private func addBotMember(
        _ bot: User,
        to chatID: Int64,
        payload: String,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) {
        guard authority.isCurrent else { return }
        let client = authority.client
        resolveTask?.cancel()
        resolveTask = Task { [weak self, weak presenter] in
            do {
                if payload.isEmpty {
                    _ = try await client.send(TDNativeRequests.addChatMember(
                        chatId: chatID,
                        userId: bot.id,
                        forwardLimit: 0,
                    ))
                } else {
                    _ = try await client.send(TDNativeRequests.sendBotStartMessage(
                        botUserId: bot.id,
                        chatId: chatID,
                        parameter: payload,
                    ))
                    guard let self, !Task.isCancelled, authority.isCurrent else { return }
                    await openChat(chatID, authority: authority, presenter: presenter)
                }
            } catch {
                guard let self, !Task.isCancelled, authority.isCurrent else { return }
                presentAlert(ChatManagementRows.failureText(error), presenter: presenter)
            }
        }
    }

    /// OpenResolvedUrl's `.channelMessage` and `.replyThreadMessage`: `getMessageLinkInfo`, then the message in its
    /// chat, forum topic or comment thread. A chat the user can't see gets Telegram's inaccessible-message alert.
    private func openMessage(_ link: String, authority: ChatListActionAuthority, presenter: UIViewController?) async {
        let client = authority.client
        let info = try? await client.send(TDNativeRequests.getMessageLinkInfo(url: link))
        guard !Task.isCancelled, authority.isCurrent else { return }
        guard let info, info.chatId != 0 else {
            presentAlert(L10n.telegram("Conversation.ErrorInaccessibleMessage"), presenter: presenter)
            return
        }
        let messageID = info.message?.id
        switch info.topicId {
        case .messageTopicForum(let forum):
            let topic = try? await client.getForumTopic(chatId: info.chatId, forumTopicId: forum.forumTopicId)
            guard !Task.isCancelled, authority.isCurrent else { return }
            await openChat(info.chatId, authority: authority, presenter: presenter, topic: topic, messageID: messageID)
        case .messageTopicThread(let thread):
            let threadInfo = try? await client.getMessageThread(chatId: info.chatId, messageId: thread.messageThreadId)
            guard !Task.isCancelled, authority.isCurrent else { return }
            if let threadInfo {
                await openChat(
                    threadInfo.chatId,
                    authority: authority,
                    presenter: presenter,
                    messageThread: threadInfo,
                    messageID: messageID,
                )
            } else {
                await openChat(info.chatId, authority: authority, presenter: presenter, messageID: messageID)
            }
        default:
            await openChat(info.chatId, authority: authority, presenter: presenter, messageID: messageID)
        }
    }

    /// OpenResolvedUrl's `.join`: `checkChatInviteLink`; a chat the user can already read opens, any other shows
    /// Telegram's join preview. An invalid link gets Telegram's expired-link toast.
    private func openChatInvite(
        _ inviteLink: String,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        do {
            let info = try await authority.client.send(TDNativeRequests.checkChatInviteLink(inviteLink: inviteLink))
            guard !Task.isCancelled, authority.isCurrent else { return }
            if info.chatId != 0 {
                await openChat(info.chatId, authority: authority, presenter: presenter)
                return
            }
            guard let host = presentationHost(presenter) else { return }
            let preview = ChatInviteLinkPreviewViewController(inviteLink: inviteLink, info: info)
            preview.onJoined = { [weak self] chatID in
                guard let self, authority.isCurrent else { return }
                resolveTask?.cancel()
                resolveTask = Task { await self.openChat(chatID, authority: authority, presenter: nil) }
            }
            host.present(preview, animated: true)
        } catch {
            guard !Task.isCancelled, authority.isCurrent else { return }
            let tdError = error as? TDLibError
            if tdError?.code == 429 || tdError?.message.contains("FLOOD") == true {
                presentAlert(L10n.telegram("TwoStepAuth.FloodError"), presenter: presenter)
            } else if let host = presentationHost(presenter) {
                TelegramUndoToast.show(
                    text: L10n.telegram("InviteLinks.InviteLinkExpired"),
                    in: host.view,
                    bottomInset: 8,
                    undo: nil,
                )
            }
        }
    }

    /// OpenResolvedUrl's `.stickerPack`: the pack sheet, or Telegram's not-found alert.
    private func openStickerSet(
        _ name: String,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        let client = authority.client
        let stickerSet = try? await client.send(TDNativeRequests.searchStickerSet(name: name, ignoreCache: false))
        guard !Task.isCancelled, authority.isCurrent else { return }
        guard let stickerSet else {
            presentAlert(L10n.telegram("StickerPack.ErrorNotFound"), presenter: presenter)
            return
        }
        guard let host = presentationHost(presenter) else { return }
        StickerPackPreviewViewController.present(setID: stickerSet.id, client: client, from: host, onSend: nil)
    }

    /// OpenResolvedUrl's `.story`: the story on its own in the viewer, or Telegram's expired-story toast.
    private func openStory(
        _ username: String,
        storyID: Int,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
    ) async {
        guard let chat = await publicChat(username, authority: authority, presenter: presenter),
              let host = presentationHost(presenter) else { return }
        StoryViewerController.present(
            .story(chatID: chat.id, storyID: storyID),
            client: authority.client,
            from: host,
            sourceView: nil,
        ) { [weak host] in
            guard let host else { return }
            TelegramUndoToast.show(
                text: L10n.telegram("Story.TooltipExpired"),
                in: host.view,
                bottomInset: 8,
                undo: nil,
            )
        }
    }

    /// OpenResolvedUrl's openPeer: the chat on screen takes the link in place (Telegram's openPeer for the current
    /// peer); otherwise the chat, its topic or thread, or the peer's profile is pushed.
    private func openChat(
        _ chatID: Int64,
        authority: ChatListActionAuthority,
        presenter: UIViewController?,
        topic: ForumTopic? = nil,
        messageThread: TDNativeMessageThreadInfo? = nil,
        messageID: Int64? = nil,
        botStartParameter: String? = nil,
        attachmentMenuBotStart: AttachmentMenuBotStart? = nil,
        linkDraft: FormattedText? = nil,
        profile: Bool = false,
    ) async {
        let client = authority.client
        let customChat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
        guard !Task.isCancelled, authority.isCurrent else { return }
        guard let customChat, let accountID = authority.source?.accountID else {
            presentAlert(L10n.telegram("Login.UnknownError"), presenter: presenter)
            return
        }
        let chatLocation = ChatLocation.current(chatID: chatID, client: client)
        let location =
            if let messageThread {
                chatLocation.withMessageThread(chatID: messageThread.chatId, id: messageThread.messageThreadId)
            } else if let topic {
                chatLocation.withForumTopic(id: topic.info.forumTopicId)
            } else {
                chatLocation
            }
        afterDismissingPresentations {
            guard authority.isCurrent else { return }
            let navigation = NavigationStorage.shared.navigationController
            if profile {
                let controller = PeerProfileViewController(
                    customChat: customChat,
                    topic: nil,
                    client: client,
                    accountID: accountID,
                )
                controller.configureOpensChatItself()
                navigation.pushViewController(controller, animated: true)
                return
            }
            if let open = navigation.topViewController as? ChatViewController,
               open.openLinkInPlace(
                   chatID: location.chatID,
                   topic: location.topic,
                   messageID: messageID,
                   botStartParameter: botStartParameter,
                   attachmentMenuBotStart: attachmentMenuBotStart,
                   linkDraft: linkDraft,
               )
            {
                return
            }
            if let botStartParameter {
                let controller = ChatViewController(customChat: customChat, location: location)
                controller.beginBotStart(parameter: botStartParameter)
                navigation.pushViewController(controller, animated: true)
                return
            }
            if let attachmentMenuBotStart {
                let controller = ChatViewController(customChat: customChat, location: location, forumTopic: topic)
                controller.beginAttachmentMenuBot(attachmentMenuBotStart)
                navigation.pushViewController(controller, animated: true)
                return
            }
            if let linkDraft {
                let controller = ChatViewController(customChat: customChat, location: location, forumTopic: topic)
                controller.beginLinkDraft(linkDraft)
                navigation.pushViewController(controller, animated: true)
                return
            }
            NavigationStorage.shared.push(.customChat(
                customChat,
                location: location,
                forumTopic: topic,
                targetMessageID: messageID,
                messageThread: messageThread,
            ))
        }
    }

    /// OpenResolvedUrl's `.settings`: the matching Settings screen, the Settings root for a section BetterTG doesn't
    /// have, and Telegram's FAQ and privacy policy pages in Safari.
    private func openSettings(_ section: TDNativeSettingsSection?) {
        let make: () -> UIViewController
        switch section {
        case .settingsSectionAppearance: make = { AppearanceViewController() }
        case .settingsSectionChatFolders: make = { ChatFoldersViewController(rootVM: .shared) }
        case .settingsSectionDataAndStorage: make = { DataAndStorageViewController() }
        case .settingsSectionDevices: make = { ActiveSessionsViewController() }
        case .settingsSectionEditProfile: make = { EditProfileViewController() }
        case .settingsSectionLanguage: make = { LanguageSelectionViewController() }
        case .settingsSectionNotifications: make = { NotificationSettingsViewController() }
        case .settingsSectionPrivacyAndSecurity: make = { PrivacySettingsViewController() }
        case .settingsSectionFaq:
            if let url = URL(string: L10n.telegram("Settings.FAQ_URL")) { UIApplication.shared.open(url) }
            return
        case .settingsSectionPrivacyPolicy:
            if let url = URL(string: L10n.telegram("Settings.PrivacyPolicy_URL")) { UIApplication.shared.open(url) }
            return
        default: make = { SettingsViewController() }
        }
        let authority = ChatListActionAuthority()
        afterDismissingPresentations {
            guard authority.isCurrent else { return }
            let controller = make()
            let navigation = NavigationStorage.shared.navigationController
            // Telegram replaces a copy of the screen already on top instead of stacking another.
            if let top = navigation.topViewController, type(of: top) == type(of: controller) { return }
            navigation.pushViewController(controller, animated: true)
        }
    }

    // MARK: Presentation

    /// Pushes go on the app's navigation stack, so whatever is presented over it closes first.
    private func afterDismissingPresentations(_ action: @escaping () -> Void) {
        guard let root = NavigationStorage.shared.navigationController.viewIfLoaded?.window?.rootViewController,
              let presented = root.presentedViewController, !presented.isBeingDismissed
        else {
            action()
            return
        }
        root.dismiss(animated: true) { action() }
    }

    /// The controller sheets and alerts present from: the top of the link's window, or of the app's window when the
    /// link's screen has gone.
    private func presentationHost(_ presenter: UIViewController?) -> UIViewController? {
        let window = presenter?.viewIfLoaded?.window
            ?? NavigationStorage.shared.navigationController.viewIfLoaded?.window
        return window?.rootViewController.map(topPresenter)
    }

    private func presentAlert(_ text: String, presenter: UIViewController?) {
        guard let host = presentationHost(presenter) else { return }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        host.present(alert, animated: true)
    }

    /// Telegram's info UndoOverlayController for a link's notice.
    private func presentToast(_ text: String, presenter: UIViewController?) {
        guard let host = presentationHost(presenter) else { return }
        TelegramUndoToast.show(text: text, in: host.view, bottomInset: 8, undo: nil)
    }

    /// A Telegram page BetterTG can't show opens in Safari; a tg:// link has nowhere else to go.
    private func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
        UIApplication.shared.open(url)
    }

    private func topPresenter(_ root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController, !presented.isBeingDismissed { return topPresenter(presented) }
        if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController {
            return topPresenter(visible)
        }
        if let child = root.children.last(where: { $0.viewIfLoaded?.window != nil }) { return topPresenter(child) }
        return root
    }
}

// MARK: - LanguagePackPreviewViewController

/// UIKit adaptation of Telegram's LanguageLinkPreviewController: preview first, apply on the user's action.
@MainActor private final class LanguagePackPreviewViewController: UIViewController {
    private let identifier: String
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let applyButton = TelegramSheetActionButton()
    private let cancelButton = TelegramSheetActionButton()
    private let dimmer = UIControl()
    private let sheetStack = UIStackView()
    private let textStack = UIStackView()
    private var textHeight: NSLayoutConstraint!
    private var sheetWidth: NSLayoutConstraint!
    private var language: AppLanguage?
    private var task: Task<Void, Never>?
    private var didAnimateIn = false
    private var isApplying = false

    init(identifier: String) {
        self.identifier = identifier
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(dimmer)
        sheetStack.translatesAutoresizingMaskIntoConstraints = false
        sheetStack.axis = .vertical
        sheetStack.spacing = 8
        view.addSubview(sheetStack)
        sheetWidth = sheetStack.widthAnchor.constraint(equalToConstant: 382)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: view.topAnchor),
            dimmer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sheetStack.centerXAnchor.constraint(equalTo: view.centerXAnchor), sheetWidth,
            sheetStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        sheetStack.addArrangedSubview(card)
        sheetStack.addArrangedSubview(cancelButton)
        cancelButton.backgroundColor = .secondarySystemBackground
        cancelButton.layer.cornerRadius = 16
        cancelButton.clipsToBounds = true
        for button in [applyButton, cancelButton] {
            button.heightAnchor.constraint(equalToConstant: 57).isActive = true
        }
        applyButton.setTitle(L10n.telegram("ApplyLanguage.ChangeLanguageAction"), for: .normal)
        applyButton.accessibilityIdentifier = "language-pack-apply"
        applyButton.isEnabled = false
        applyButton.addTarget(self, action: #selector(applyLanguage), for: .touchUpInside)
        cancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = L10n.telegram("Settings.AppLanguage")
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.text = identifier
        bodyLabel.accessibilityIdentifier = "language-pack-preview"
        textStack.axis = .vertical
        textStack.spacing = 12
        textStack.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, bodyLabel, spinner].forEach(textStack.addArrangedSubview)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        card.addSubview(scroll)
        scroll.addSubview(textStack)
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(applyButton)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(separator)
        textHeight = scroll.heightAnchor.constraint(equalToConstant: 120)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor), textHeight,
            textStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            textStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            textStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -20),
            applyButton.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            applyButton.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            applyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            applyButton.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            separator.topAnchor.constraint(equalTo: applyButton.topAnchor),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
        spinner.startAnimating()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let language = try await AppLocalization.shared.languagePack(id: identifier)
                try Task.checkCancellation()
                self.language = language
                spinner.stopAnimating()
                titleLabel.text = L10n.telegram("ApplyLanguage.ChangeLanguageTitle")
                bodyLabel.text = L10n.betterTG(
                    "Localization.Preview",
                    language.nativeName,
                    min(100, Int(language.translationProgress * 100)),
                )
                applyButton.isEnabled = language.totalStringCount > 0
                if language.id == AppLocalization.shared.selectedLanguagePackID {
                    bodyLabel.text = L10n.telegram("ApplyLanguage.ChangeLanguageAlreadyActive", language.nativeName)
                    applyButton.isEnabled = false
                    cancelButton.setTitle(L10n.telegram("Common.OK"), for: .normal)
                }
            } catch is CancellationError { dismiss(animated: true) }
            catch {
                spinner.stopAnimating()
                bodyLabel.text = L10n.telegram("ApplyLanguage.LanguageNotSupportedError")
            }
            view.setNeedsLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width, view.bounds.height) - 20
        if abs(sheetWidth.constant - width) > 0.5 { sheetWidth.constant = width }
        let fitting = textStack.systemLayoutSizeFitting(
            CGSize(width: max(1, width - 20), height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        let available = max(60, view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 142)
        let height = min(available, ceil(fitting.height + 24))
        if abs(textHeight.constant - height) > 0.5 { textHeight.constant = height }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        sheetStack.transform = CGAffineTransform(translationX: 0, y: sheetStack.bounds.height + 40)
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction],
        ) { self.sheetStack.transform = .identity }
    }

    @objc private func applyLanguage() {
        guard let language, applyButton.isEnabled else { return }
        isApplying = true
        applyButton.isEnabled = false
        spinner.startAnimating()
        cancelButton.isEnabled = false
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await AppLocalization.shared.apply(language)
                dismiss(animated: true)
            } catch {
                spinner.stopAnimating()
                bodyLabel.text = L10n.betterTG("Localization.DownloadError")
                applyButton.isEnabled = true
                cancelButton.isEnabled = true
                isApplying = false
                view.setNeedsLayout()
            }
        }
    }

    @objc private func cancel() {
        guard !isApplying else { return }
        task?.cancel()
        dismiss(animated: true)
    }
}

// MARK: - TelegramSheetActionButton

/// An action button of Telegram's action-sheet previews (language pack, chat invite link).
final class TelegramSheetActionButton: UIControl {
    override var isEnabled: Bool { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { updateAppearance() } }

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        updateAppearance()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String?, for _: UIControl.State) {
        label.text = title
        accessibilityLabel = title
    }

    private func updateAppearance() {
        backgroundColor = isHighlighted ? .tertiarySystemBackground : .secondarySystemBackground
        label.textColor = isEnabled ? .systemBlue : .tertiaryLabel
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    }
}

// MARK: - LinkResolutionProgressView

/// TGProgressWindow, OverlayStatusController's `.loading`: a 100-point blurred square with a spinner in the middle of
/// the window, which takes every touch while it shows and cancels the link on a tap.
private final class LinkResolutionProgressView: UIView {
    private let cancel: () -> Void
    private let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let spinner = UIActivityIndicatorView(style: .large)
    private var isFinished = false

    init(cancel: @escaping () -> Void) {
        self.cancel = cancel
        super.init(frame: .zero)
        backgroundColor = .clear
        container.layer.cornerRadius = 20
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        addSubview(container)
        container.contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 100),
            container.heightAnchor.constraint(equalToConstant: 100),
            spinner.centerXAnchor.constraint(equalTo: container.contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.contentView.centerYAnchor),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityLabel = L10n.telegram("Common.Cancel")
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// TGProgressWindow's appearance: the square grows from 0.6 with a spring while it fades in over 0.3 seconds.
    func show(in window: UIWindow) {
        guard !isFinished, superview == nil else { return }
        frame = window.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(self)
        container.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(springDuration: 0.3, bounce: 0) {
            self.container.transform = .identity
        }
        UIView.animate(withDuration: 0.3) {
            self.container.alpha = 1
        }
    }

    /// TGProgressWindow's dismissal: a 0.3-second fade, or nothing when the link resolved before the overlay showed.
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        isUserInteractionEnabled = false
        guard superview != nil else { return }
        UIView.animate(withDuration: 0.3, delay: 0, options: .beginFromCurrentState) {
            self.container.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    @objc private func tapped() {
        cancel()
        finish()
    }
}
