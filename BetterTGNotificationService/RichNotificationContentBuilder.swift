// RichNotificationContentBuilder.swift

import Intents
import UIKit
import UserNotifications

enum RichNotificationContentBuilder {
    // MARK: Internal

    /// `pushText` replaces the relay's alert, Telegram Web's text, with Telegram for iOS's.
    static func content(
        from original: UNNotificationContent,
        metadata: RelayNotificationMetadata,
        resolved: ResolvedTelegramNotification,
        pushText: TelegramPushText?,
    ) -> UNNotificationContent {
        guard let mutable = original.mutableCopy() as? UNMutableNotificationContent else { return original }

        if let pushText, !pushText.body.isEmpty {
            if let title = pushText.title, !title.isEmpty {
                mutable.title = title
            }
            mutable.body = pushText.body
        }
        if let body = resolved.preview.bodyOverride(resolved.body), !body.isEmpty {
            mutable.body = body
        }

        mutable.attachments = []
        if let mediaData = resolved.preview.attachmentData,
           let url = RichNotificationCache.writeTemporaryAttachment(mediaData),
           let attachment = try? UNNotificationAttachment(identifier: "telegram-media", url: url)
        {
            mutable.attachments = [attachment]
        }

        let senderAvatar = resolved.senderAvatarData
            ?? RichNotificationCache.avatarData(for: metadata.sender, accountID: metadata.accountID)
            ?? generatedAvatar(name: resolved.senderName, id: metadata.sender.id)
        let sender = INPerson(
            personHandle: INPersonHandle(value: metadata.sender.cacheKey, type: .unknown),
            nameComponents: nil,
            displayName: resolved.senderName,
            image: senderAvatar.map(INImage.init(imageData:)),
            contactIdentifier: nil,
            customIdentifier: metadata.sender.cacheKey,
            isMe: false,
            suggestionType: .none,
        )

        let isGroup = metadata.peer != metadata.sender || metadata.peer.kind != .privateChat
        let groupName = isGroup
            ? (resolved.conversationTitle ?? metadata.conversationTitle).flatMap {
                $0.isEmpty ? nil : INSpeakableString(spokenPhrase: $0)
            }
            : nil
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: mutable.body,
            speakableGroupName: groupName,
            conversationIdentifier: metadata.peer.cacheKey,
            serviceName: "BetterTG",
            sender: sender,
            attachments: nil,
        )
        if let senderAvatar {
            intent.setImage(INImage(imageData: senderAvatar), forParameterNamed: \.sender)
        }
        if groupName != nil,
           let groupAvatar = resolved.conversationAvatarData
           ?? RichNotificationCache.avatarData(for: metadata.peer, accountID: metadata.accountID)
        {
            intent.setImage(INImage(imageData: groupAvatar), forParameterNamed: \.speakableGroupName)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        let updated = (try? mutable.updating(from: intent)) ?? mutable
        guard let finalContent = updated.mutableCopy() as? UNMutableNotificationContent else {
            return updated
        }
        finalContent.categoryIdentifier = resolved.canQuickReply
            ? QuickReplyNotification.categoryIdentifier
            : QuickReplyNotification.messageCategoryIdentifier
        return finalContent
    }

    static func fallback(
        metadata: RelayNotificationMetadata,
        canQuickReply: Bool,
    ) -> ResolvedTelegramNotification {
        ResolvedTelegramNotification(
            senderName: metadata.senderName?.isEmpty == false ? metadata.senderName! : "Telegram",
            conversationTitle: metadata.conversationTitle,
            senderAvatarData: RichNotificationCache.avatarData(for: metadata.sender, accountID: metadata.accountID),
            conversationAvatarData: RichNotificationCache.avatarData(for: metadata.peer, accountID: metadata.accountID),
            preview: .unresolved,
            body: nil,
            canQuickReply: canQuickReply,
        )
    }

    // MARK: Private

    private static func generatedAvatar(name: String, id: Int64) -> Data? {
        let size = CGSize(width: 128, height: 128)
        let hue = CGFloat(UInt64(bitPattern: id) % 360) / 360
        let background = UIColor(hue: hue, saturation: 0.58, brightness: 0.78, alpha: 1)
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return UIGraphicsImageRenderer(size: size).pngData { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .medium),
                .foregroundColor: UIColor.white,
            ]
            let text = initials.isEmpty ? "T" : initials
            let textSize = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes,
            )
        }
    }
}
