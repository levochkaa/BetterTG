// MessageLinkMenu.swift

import SafariServices
import TDLibKit
import UIKit

// MARK: - MessageTextLink

/// A link, mention or bot command of a message's text under a long press, which opens its own menu.
struct MessageTextLink: Equatable {
    enum Target: Equatable {
        /// `TelegramTextAttributes.URL`: the address, a text link's URL, or `mailto:` and the email address.
        case url(String)
        /// An @username as written.
        case mention(String)
        /// A text mention of a user, with its text.
        case userMention(Int64, text: String)
        case botCommand(String)
        /// A hashtag or cashtag as written, "@chat" included.
        case hashtag(String)
    }

    let target: Target
    /// The entity's line rects in its text view.
    let rects: [CGRect]

    /// What the menu's card shows: an email address without `mailto:`, anything else as written.
    var previewText: String {
        switch target {
        case .url(let url): url.replacing("mailto:", with: "")
        case .botCommand(let text),
             .hashtag(let text),
             .mention(let text): text
        case .userMention(_, let text): text
        }
    }
}

// MARK: - MessageLinkMenu

/// Telegram's menu for a link in a message (ChatControllerOpenLinkContextMenu): Open, Copy Link or Copy Email, and
/// Add to Reading List for anything but an email address. BetterTG opens web links in Safari, so the in-app browser's
/// Open in Browser and Open in App have nothing to switch to.
struct MessageLinkMenu {
    let url: String

    var isEmail: Bool { url.hasPrefix("mailto:") }

    /// The link as the menu's preview shows it.
    var previewText: String { url.replacing("mailto:", with: "") }

    /// parseUrl's display string, which Copy puts on the pasteboard: an email address without `mailto:`, and a link
    /// whose host has non-Latin letters percent-encoded.
    var copiedText: String {
        if isEmail { return String(url.dropFirst("mailto:".count)) }
        let parsed = url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://")
            ? URL(string: url)
            : URL(string: "https://" + url)
        let host = parsed?.host ?? url
        let rawHost = host.removingPercentEncoding ?? host
        let latin = CharacterSet(charactersIn: "A"..."Z")
            .union(CharacterSet(charactersIn: "a"..."z"))
            .union(CharacterSet(charactersIn: "0"..."9"))
        let punctuation = CharacterSet(charactersIn: ".-/+_?=")
        let hasNonLatin = rawHost.unicodeScalars.contains { !latin.contains($0) && !punctuation.contains($0) }
        return hasNonLatin ? url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url : url
    }

    func actions(open: @escaping () -> Void, copied: @escaping (String) -> Void) -> [TelegramContextMenuAction] {
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("Conversation.LinkDialogOpen"),
                image: UIImage(systemName: "globe"),
                handler: open,
            ),
            TelegramContextMenuAction(
                title: L10n
                    .telegram(isEmail ? "Conversation.ContextMenuCopyEmail" : "Conversation.ContextMenuCopyLink"),
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
                handler: { [copiedText, isEmail] in
                    UIPasteboard.general.string = copiedText
                    copied(L10n.telegram(isEmail ? "Conversation.EmailCopied" : "Conversation.LinkCopied"))
                },
            ),
        ]
        if !isEmail {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.AddToReadingList"),
                image: UIImage(systemName: "eyeglasses"),
                handler: { [url] in
                    guard let link = getUrl(from: url) else { return }
                    try? SSReadingList.default()?.addItem(with: link, title: nil, previewText: nil)
                },
            ))
        }
        return actions
    }
}

// MARK: - MessageMentionMenu

/// Telegram's menu for a mention in a message (ChatControllerOpenUsernameContextMenu): Send Message for a user, or
/// Open Group or Open Channel, Copy Username, and under them the peer with View Profile, or that nobody has the name.
struct MessageMentionMenu {
    enum Destination: Equatable {
        case user(Int64)
        case chat(Int64)
    }

    struct Peer {
        enum Kind {
            case user
            case group
            case channel
        }

        let kind: Kind
        let name: String
        let avatar: UIImage?
        let destination: Destination
    }

    /// The mention as written, which Copy puts on the pasteboard.
    let text: String
    let peer: Peer?

    /// The peer a mention names: an @username through searchPublicChat, a text mention's user by its ID, with the
    /// avatar once its small photo is downloaded.
    nonisolated static func peer(for target: MessageTextLink.Target, client: TDLibClient) async -> Peer? {
        switch target {
        case .mention(let text):
            let username = text.hasPrefix("@") ? String(text.dropFirst()) : text
            guard let chat = try? await client.send(TDNativeRequests.searchPublicChat(username: username))
            else { return nil }
            let kind: Peer.Kind
            let destination: Destination
            switch chat.type {
            case .chatTypePrivate(let value):
                (kind, destination) = (.user, .user(value.userId))
            case .chatTypeSecret(let value):
                (kind, destination) = (.user, .user(value.userId))
            case .chatTypeBasicGroup:
                (kind, destination) = (.group, .chat(chat.id))
            case .chatTypeSupergroup(let value):
                (kind, destination) = (value.isChannel ? .channel : .group, .chat(chat.id))
            }
            let avatar = await avatar(chat.photo?.small, client: client)
            return Peer(kind: kind, name: chat.title, avatar: avatar, destination: destination)
        case .userMention(let userID, _):
            guard let user = try? await client.getUser(userId: userID) else { return nil }
            let avatar = await avatar(user.profilePhoto?.small, client: client)
            return Peer(
                kind: .user,
                name: ServiceMessageText.displayTitle(user),
                avatar: avatar,
                destination: .user(userID),
            )
        case .botCommand,
             .hashtag,
             .url:
            return nil
        }
    }

    private nonisolated static func avatar(_ file: TDNativeFile?, client: TDLibClient) async -> UIImage? {
        guard let file else { return nil }
        if file.local.isDownloadingCompleted { return PollOptionMenu.avatar(path: file.local.path) }
        guard let downloaded = try? await client.downloadFile(
            fileId: file.id,
            priority: 1,
            offset: 0,
            limit: 0,
            synchronous: true,
        ), downloaded.local.isDownloadingCompleted else { return nil }
        return PollOptionMenu.avatar(path: downloaded.local.path)
    }

    func actions(
        open: @escaping (Destination) -> Void,
        openProfile: @escaping (Destination) -> Void,
        copied: @escaping (String) -> Void,
    ) -> [TelegramContextMenuAction] {
        var actions = [TelegramContextMenuAction]()
        if let peer {
            let (title, image) =
                switch peer.kind {
                case .user: ("Chat.Context.Username.SendMessage", "bubble.left")
                case .group: ("Chat.Context.Username.OpenGroup", "person.2")
                case .channel: ("Chat.Context.Username.OpenChannel", "megaphone")
                }
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(title),
                image: UIImage(systemName: image),
                handler: { open(peer.destination) },
            ))
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("Chat.Context.Username.Copy"),
            image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            handler: { [text] in
                UIPasteboard.general.string = text
                copied(L10n.telegram("Conversation.UsernameCopied"))
            },
        ))
        if let peer {
            var row = TelegramContextMenuAction(
                title: peer.name,
                image: peer.avatar ?? UIImage(systemName: "person.crop.circle"),
                startsNewSection: true,
                handler: { openProfile(peer.destination) },
            )
            row.secondLine = (L10n.telegram("Chat.Context.Phone.ViewProfile"), true)
            actions.append(row)
        } else {
            var row = TelegramContextMenuAction(
                title: L10n.telegram("Chat.Context.Username.NotOnTelegram"),
                startsNewSection: true,
            )
            row.isInformational = true
            actions.append(row)
        }
        return actions
    }
}

// MARK: - MessageCommandMenu

/// Telegram's menu for a bot command in a message (ChatControllerOpenCommandContextMenu): Copy Command.
enum MessageCommandMenu {
    static func actions(command: String, copied: @escaping (String) -> Void) -> [TelegramContextMenuAction] {
        [TelegramContextMenuAction(
            title: L10n.telegram("Chat.Context.Command.Copy"),
            image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
            handler: {
                UIPasteboard.general.string = command
                copied(L10n.telegram("Conversation.TextCopied"))
            },
        )]
    }
}

// MARK: - MessageHashtagMenu

/// Telegram's menu for a hashtag in a message (ChatControllerOpenHashtagContextMenu): Search and Copy Hashtag.
enum MessageHashtagMenu {
    static func actions(
        hashtag: String,
        search: @escaping () -> Void,
        copied: @escaping (String) -> Void,
    ) -> [TelegramContextMenuAction] {
        [
            TelegramContextMenuAction(
                title: L10n.telegram("Chat.Context.Hashtag.Search"),
                image: UIImage(systemName: "magnifyingglass"),
                handler: search,
            ),
            TelegramContextMenuAction(
                title: L10n.telegram("Chat.Context.Hashtag.Copy"),
                image: UIImage(systemName: "rectangle.portrait.on.rectangle.portrait"),
                handler: {
                    UIPasteboard.general.string = hashtag
                    copied(L10n.telegram("Conversation.HashtagCopied"))
                },
            ),
        ]
    }
}

// MARK: - MessageLinkContextChipView

/// ChatMessageBubbleItemNode.contextContentNodeForLink: the link on a bubble-colored card with 10 pt corners, at
/// most two lines, that the menu lifts in place of the message.
final class MessageLinkContextChipView: TelegramContextMenuExtractableView {
    init(text: String, maximumTextWidth: CGFloat) {
        super.init(frame: .zero)
        let label = UILabel()
        label.text = text
        label.font = .body
        label.textColor = .systemBlue
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        let fitting = label.sizeThatFits(CGSize(width: maximumTextWidth, height: .greatestFiniteMagnitude))
        let textSize = CGSize(width: ceil(min(fitting.width, maximumTextWidth)), height: ceil(fitting.height))
        let insets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        bounds.size = CGSize(
            width: textSize.width + insets.left + insets.right,
            height: textSize.height + insets.top + insets.bottom,
        )
        extractedContentView.backgroundColor = .secondarySystemBackground
        extractedContentView.layer.cornerRadius = 10
        extractedContentView.clipsToBounds = true
        label.frame = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: textSize)
        extractedContentView.addSubview(label)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MessageLinkHighlightView

/// LinkHighlightingNode: the link's rects grown by 2 pt with 4 pt corners.
final class MessageLinkHighlightView: UIView {
    init(rects: [CGRect], color: UIColor) {
        let grown = rects.map { $0.insetBy(dx: -2, dy: -2) }
        let bounds = grown.dropFirst().reduce(grown.first ?? .zero) { $0.union($1) }
        super.init(frame: bounds)
        isUserInteractionEnabled = false
        let path = UIBezierPath()
        for rect in grown {
            path.append(UIBezierPath(
                roundedRect: rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
                cornerRadius: 4,
            ))
        }
        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.fillColor = color.cgColor
        layer.addSublayer(shape)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
