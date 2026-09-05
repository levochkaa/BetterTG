// MessageContentPresentation.swift

import Foundation
import TDLibKit

struct MessageContentPresentation {
    struct LocationContent {
        let liveDeadline: Foundation.Date?
        let liveIndefinite: Bool
        let location: Location
        let subtitle: String?
        let title: String
    }

    struct DiceContent {
        let emoji: String
        let sticker: Sticker?
        let value: Int
    }

    struct ServiceContent {
        let detail: String?
        let symbolName: String
        let title: String
    }

    enum Supplement {
        case animatedEmoji(emoji: String, content: AnimatedEmoji)
        case audio(Audio)
        case contact(Contact)
        case dice(DiceContent)
        case document(Document)
        case location(LocationContent)
        case linkPreview(LinkPreview)
        case none
        case poll(MessagePoll)
        case service(ServiceContent)
        case unsupported(ServiceContent)
    }

    static let auditedTDLibCaseCount = 104
    static let auditedTDLibRevision = "1.8.66-022d6020"

    let formattedText: FormattedText?
    let isVisualMedia: Bool
    let summary: String
    let supplement: Supplement

    var isService: Bool {
        if case .service = supplement { return true }
        return false
    }

    static func make(_ message: Message) -> Self {
        guard case .messageLiveLocation(let liveLocation) = message.content else {
            return make(message.content)
        }
        let livePeriod = liveLocation.location.livePeriod
        let isIndefinite = livePeriod >= Int(Int32.max)
        let deadline: Foundation.Date? =
            if isIndefinite {
                nil
            } else if message.date > 0, livePeriod > 0 {
                Foundation.Date(timeIntervalSince1970: TimeInterval(message.date + livePeriod))
            } else {
                Foundation.Date().addingTimeInterval(TimeInterval(max(0, liveLocation.expiresIn)))
            }
        return make(
            message.content,
            liveLocationDeadline: deadline,
            liveLocationIndefinite: isIndefinite,
        )
    }

    static func make(_ content: MessageContent) -> Self {
        make(content, liveLocationDeadline: nil, liveLocationIndefinite: false)
    }

    private static func make(
        _ content: MessageContent,
        liveLocationDeadline: Foundation.Date?,
        liveLocationIndefinite: Bool,
    ) -> Self {
        switch content {
        case .messageText(let message):
            return Self(
                formattedText: message.text,
                isVisualMedia: false,
                summary: message.text.text,
                supplement: message.linkPreview.map { .linkPreview($0) } ?? .none,
            )
        case .messageRichMessage:
            return unsupported(
                title: "Rich message",
                detail: "This rich message layout isn't supported yet.",
            )
        case .messageAnimation(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(label: "Animation", caption: message.caption),
                isVisualMedia: true,
            )
        case .messageAudio(let message):
            let title = firstNonEmpty(message.audio.title, message.audio.fileName, "Audio")
            let performer = message.audio.performer.trimmingCharacters(in: .whitespacesAndNewlines)
            let attachmentSummary = performer.isEmpty ? title : "\(performer) — \(title)"
            let summary = message.caption.text.isEmpty
                ? attachmentSummary
                : "\(attachmentSummary): \(message.caption.text)"
            return Self(
                formattedText: nonEmpty(message.caption),
                isVisualMedia: false,
                summary: summary,
                supplement: .audio(message.audio),
            )
        case .messageDocument(let message):
            let title = firstNonEmpty(message.document.fileName, "Document")
            let summary = message.caption.text.isEmpty ? title : "\(title): \(message.caption.text)"
            return Self(
                formattedText: nonEmpty(message.caption),
                isVisualMedia: false,
                summary: summary,
                supplement: .document(message.document),
            )
        case .messagePaidMedia:
            return excludedPaidContent(title: "Paid media")
        case .messagePhoto(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(label: "Photo", caption: message.caption),
                isVisualMedia: true,
            )
        case .messageSticker(let message):
            let emoji = message.sticker.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            return presentation(
                summary: emoji.isEmpty ? "Sticker" : "Sticker \(emoji)",
                isVisualMedia: true,
            )
        case .messageVideo(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(label: "Video", caption: message.caption),
                isVisualMedia: true,
            )
        case .messageVideoNote:
            return presentation(summary: "Video message", isVisualMedia: true)
        case .messageVoiceNote(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(label: "Voice message", caption: message.caption),
            )
        case .messageExpiredPhoto:
            return service(title: "Photo expired", symbolName: "photo.badge.exclamationmark")
        case .messageExpiredVideo:
            return service(title: "Video expired", symbolName: "video.badge.ellipsis")
        case .messageExpiredVideoNote:
            return service(title: "Video message expired", symbolName: "video.circle")
        case .messageExpiredVoiceNote:
            return service(title: "Voice message expired", symbolName: "waveform.badge.exclamationmark")
        case .messageLiveLocation(let message):
            let isIndefinite = liveLocationIndefinite || message.expiresIn >= Int(Int32.max)
            let deadline = liveLocationDeadline ?? (isIndefinite
                ? nil
                : Foundation.Date().addingTimeInterval(TimeInterval(max(0, message.expiresIn))))
            return Self(
                formattedText: nil,
                isVisualMedia: false,
                summary: "Live location",
                supplement: .location(LocationContent(
                    liveDeadline: deadline,
                    liveIndefinite: isIndefinite,
                    location: message.location.location,
                    subtitle: nil,
                    title: "Live location",
                )),
            )
        case .messageLocation(let message):
            return Self(
                formattedText: nil,
                isVisualMedia: false,
                summary: "Location",
                supplement: .location(LocationContent(
                    liveDeadline: nil,
                    liveIndefinite: false,
                    location: message.location,
                    subtitle: nil,
                    title: "Location",
                )),
            )
        case .messageVenue(let message):
            let title = firstNonEmpty(message.venue.title, "Venue")
            return Self(
                formattedText: nil,
                isVisualMedia: false,
                summary: title,
                supplement: .location(LocationContent(
                    liveDeadline: nil,
                    liveIndefinite: false,
                    location: message.venue.location,
                    subtitle: nonEmptyString(message.venue.address) ?? coordinateString(message.venue.location),
                    title: title,
                )),
            )
        case .messageContact(let message):
            let name = contactName(message.contact)
            return Self(
                formattedText: nil,
                isVisualMedia: false,
                summary: "Contact: \(name)",
                supplement: .contact(message.contact),
            )
        case .messageAnimatedEmoji(let message):
            return Self(
                formattedText: nil,
                isVisualMedia: true,
                summary: message.emoji,
                supplement: .animatedEmoji(emoji: message.emoji, content: message.animatedEmoji),
            )
        case .messageDice(let message):
            return Self(
                formattedText: nil,
                isVisualMedia: true,
                summary: message.value > 0 ? "\(message.emoji) \(message.value)" : message.emoji,
                supplement: .dice(DiceContent(
                    emoji: message.emoji,
                    sticker: message.value == 0 ? regularDiceSticker(message.initialState) : nil,
                    value: message.value,
                )),
            )
        case .messageGame:
            return unsupported(title: "Game", detail: "Game messages aren't supported yet.")
        case .messagePoll(let message):
            return Self(
                formattedText: nonEmpty(message.description),
                isVisualMedia: false,
                summary: "Poll: \(message.poll.question.text)",
                supplement: .poll(message),
            )
        case .messageStakeDice:
            return excludedPaidContent(title: "Stake dice")
        case .messageStory:
            return unsupported(title: "Story", detail: "Forwarded stories aren't supported yet.")
        case .messageChecklist:
            return unsupported(title: "Checklist", detail: "Checklist messages aren't supported yet.")
        case .messageInvoice:
            return unsupported(title: "Invoice", detail: "Payments aren't supported in BetterTG.")
        case .messageCall:
            return service(title: "Call", symbolName: "phone")
        case .messageGroupCall:
            return service(title: "Group call", symbolName: "person.3")
        case .messageVideoChatScheduled:
            return service(title: "Video chat scheduled", symbolName: "calendar.badge.clock")
        case .messageVideoChatStarted:
            return service(title: "Video chat started", symbolName: "video")
        case .messageVideoChatEnded:
            return service(title: "Video chat ended", symbolName: "video.slash")
        case .messageInviteVideoChatParticipants:
            return service(title: "Participants invited to video chat", symbolName: "person.badge.plus")
        case .messagePollOptionAdded:
            return service(title: "A poll option was added", symbolName: "chart.bar.doc.horizontal")
        case .messagePollOptionDeleted:
            return service(title: "A poll option was removed", symbolName: "chart.bar.doc.horizontal")
        case .messageBasicGroupChatCreate:
            return service(title: "Group created", symbolName: "person.2")
        case .messageSupergroupChatCreate:
            return service(title: "Channel or supergroup created", symbolName: "person.3")
        case .messageChatChangeTitle(let message):
            return service(
                title: "Chat title changed",
                detail: nonEmptyString(message.title),
                symbolName: "pencil",
            )
        case .messageChatChangePhoto:
            return service(title: "Chat photo changed", symbolName: "photo")
        case .messageChatDeletePhoto:
            return service(title: "Chat photo removed", symbolName: "photo.badge.minus")
        case .messageChatOwnerLeft:
            return service(title: "Chat owner left", symbolName: "person.crop.circle.badge.minus")
        case .messageChatOwnerChanged:
            return service(title: "Chat owner changed", symbolName: "person.crop.circle.badge.checkmark")
        case .messageChatHasProtectedContentToggled:
            return service(title: "Content protection changed", symbolName: "lock.shield")
        case .messageChatHasProtectedContentDisableRequested:
            return service(title: "Content protection disable requested", symbolName: "lock.open")
        case .messageChatAddMembers(let message):
            let count = message.memberUserIds.count
            return service(
                title: count == 1 ? "A member joined" : "\(count) members joined",
                symbolName: "person.badge.plus",
            )
        case .messageChatJoinFromCommunity:
            return service(title: "Joined from a community", symbolName: "person.crop.circle.badge.plus")
        case .messageChatJoinByLink:
            return service(title: "Joined via invite link", symbolName: "link")
        case .messageChatJoinByRequest:
            return service(title: "Join request approved", symbolName: "person.crop.circle.badge.checkmark")
        case .messageChatDeleteMember:
            return service(title: "A member left", symbolName: "person.badge.minus")
        case .messageChatAddedToCommunity:
            return service(title: "Chat added to a community", symbolName: "person.3.sequence")
        case .messageChatRemovedFromCommunity:
            return service(title: "Chat removed from a community", symbolName: "person.3.sequence")
        case .messageChatUpgradeTo:
            return service(title: "Group upgraded", symbolName: "arrow.up.circle")
        case .messageChatUpgradeFrom:
            return service(title: "Supergroup created", symbolName: "arrow.up.circle")
        case .messagePinMessage:
            return service(title: "A message was pinned", symbolName: "pin")
        case .messageScreenshotTaken:
            return service(title: "Screenshot taken", symbolName: "camera.viewfinder")
        case .messageChatSetBackground:
            return service(title: "Chat background changed", symbolName: "photo.on.rectangle")
        case .messageChatSetTheme:
            return service(title: "Chat theme changed", symbolName: "paintpalette")
        case .messageChatSetMessageAutoDeleteTime:
            return service(title: "Auto-delete timer changed", symbolName: "timer")
        case .messageChatBoost:
            return excludedPaidContent(title: "Chat boost")
        case .messageForumTopicCreated:
            return service(title: "Topic created", symbolName: "bubble.left.and.bubble.right")
        case .messageForumTopicEdited:
            return service(title: "Topic edited", symbolName: "bubble.left.and.pencil")
        case .messageForumTopicIsClosedToggled:
            return service(title: "Topic state changed", symbolName: "bubble.left.and.exclamationmark.bubble.right")
        case .messageForumTopicIsHiddenToggled:
            return service(title: "General topic visibility changed", symbolName: "eye.slash")
        case .messageSuggestProfilePhoto:
            return service(title: "Profile photo suggested", symbolName: "person.crop.circle.badge.plus")
        case .messageSuggestBirthdate:
            return service(title: "Birthdate suggested", symbolName: "birthday.cake")
        case .messageCustomServiceAction(let message):
            return service(
                title: firstNonEmpty(message.text, "Service message"),
                symbolName: "info.circle",
            )
        case .messageGameScore:
            return service(title: "New game score", symbolName: "trophy")
        case .messageManagedBotCreated:
            return service(title: "Managed bot created", symbolName: "cpu")
        case .messagePaymentRefunded, .messagePaymentSuccessful, .messagePaymentSuccessfulBot:
            return excludedPaidContent(title: "Payment message")
        case .messageGiftedPremium, .messagePremiumGiftCode:
            return excludedPaidContent(title: "Premium gift")
        case .messageGiveaway, .messageGiveawayCompleted, .messageGiveawayCreated, .messageGiveawayWinners:
            return excludedPaidContent(title: "Giveaway")
        case .messageGiftedGrams, .messageGiftedStars, .messageGiveawayPrizeStars:
            return excludedPaidContent(title: "Currency gift")
        case .messageGift, .messageRefundedUpgradedGift, .messageUpgradedGift:
            return excludedPaidContent(title: "Gift")
        case .messageUpgradedGiftPurchaseOffer, .messageUpgradedGiftPurchaseOfferRejected:
            return excludedPaidContent(title: "Gift purchase offer")
        case .messageDirectMessagePriceChanged, .messagePaidMessagePriceChanged, .messagePaidMessagesRefunded:
            return excludedPaidContent(title: "Paid message update")
        case .messageChecklistTasksDone:
            return service(title: "Checklist tasks updated", symbolName: "checklist")
        case .messageChecklistTasksAdded:
            return service(title: "Checklist tasks added", symbolName: "checklist")
        case .messageSuggestedPostApprovalFailed:
            return service(title: "Suggested post approval failed", symbolName: "exclamationmark.circle")
        case .messageSuggestedPostApproved:
            return service(title: "Suggested post approved", symbolName: "checkmark.circle")
        case .messageSuggestedPostDeclined:
            return service(title: "Suggested post declined", symbolName: "xmark.circle")
        case .messageSuggestedPostPaid, .messageSuggestedPostRefunded:
            return excludedPaidContent(title: "Suggested post payment")
        case .messageContactRegistered:
            return service(title: "A contact joined Telegram", symbolName: "person.crop.circle.badge.plus")
        case .messageUsersShared:
            return service(title: "Users shared with a bot", symbolName: "person.2")
        case .messageChatShared:
            return service(title: "Chat shared with a bot", symbolName: "bubble.left.and.bubble.right")
        case .messageBotWriteAccessAllowed:
            return service(title: "Bot messaging allowed", symbolName: "checkmark.shield")
        case .messageWebAppDataSent:
            return service(title: "Web app data sent", symbolName: "app.badge.checkmark")
        case .messageWebAppDataReceived:
            return service(title: "Web app data received", symbolName: "app.badge")
        case .messagePassportDataSent:
            return service(title: "Passport data sent", symbolName: "person.text.rectangle")
        case .messagePassportDataReceived:
            return service(title: "Passport data received", symbolName: "person.text.rectangle")
        case .messageProximityAlertTriggered:
            return service(title: "Proximity alert", symbolName: "location.circle")
        case .messageUnsupported:
            return unsupported(
                title: "Unsupported message",
                detail: "This message isn't supported by the current TDLib version.",
            )
        }
    }

    private static func presentation(
        formattedText: FormattedText? = nil,
        summary: String,
        isVisualMedia: Bool = false,
    ) -> Self {
        Self(
            formattedText: formattedText,
            isVisualMedia: isVisualMedia,
            summary: summary,
            supplement: .none,
        )
    }

    private static func service(
        title: String,
        detail: String? = nil,
        symbolName: String,
    ) -> Self {
        Self(
            formattedText: nil,
            isVisualMedia: false,
            summary: title,
            supplement: .service(ServiceContent(
                detail: detail,
                symbolName: symbolName,
                title: title,
            )),
        )
    }

    private static func unsupported(title: String, detail: String) -> Self {
        Self(
            formattedText: nil,
            isVisualMedia: false,
            summary: title,
            supplement: .unsupported(ServiceContent(
                detail: detail,
                symbolName: "questionmark.square.dashed",
                title: title,
            )),
        )
    }

    private static func excludedPaidContent(title: String) -> Self {
        unsupported(
            title: title,
            detail: "Paid, Premium, Stars, TON, gift, boost, and collectible flows aren't supported in BetterTG.",
        )
    }

    private static func nonEmpty(_ text: FormattedText) -> FormattedText? {
        text.text.isEmpty ? nil : text
    }

    private static func nonEmptyString(_ string: String) -> String? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func firstNonEmpty(_ strings: String...) -> String {
        strings.lazy.compactMap(nonEmptyString).first ?? "Message"
    }

    private static func captionSummary(label: String, caption: FormattedText) -> String {
        caption.text.isEmpty ? label : "\(label): \(caption.text)"
    }

    private static func contactName(_ contact: Contact) -> String {
        firstNonEmpty("\(contact.firstName) \(contact.lastName)", contact.phoneNumber, "Contact")
    }

    private static func coordinateString(_ location: Location) -> String {
        String(format: "%.5f, %.5f", location.latitude, location.longitude)
    }

    private static func regularDiceSticker(_ dice: DiceStickers?) -> Sticker? {
        guard let dice else { return nil }
        if case .diceStickersRegular(let regular) = dice {
            return regular.sticker
        }
        return nil
    }
}
