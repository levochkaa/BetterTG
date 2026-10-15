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
        /// The roll's animation layers: one sticker, or the slot machine's background, three reels and lever in
        /// Telegram's SlotMachineAnimationNode order. Rolling dice carry the initial state, rolled dice the final one.
        let stickers: [Sticker]
        let value: Int
        /// Unix time of the message, or 0 when the presentation was built from content alone.
        let messageDate: Int
    }

    struct ServiceContent {
        let detail: String?
        let symbolName: String
        let title: String
        /// The message a tap opens (ChatController's action taps: a pinned message, the game, the earlier same
        /// wallpaper, the checklist or the poll).
        var targetMessageID: Int64?
        /// The new chat photo Telegram shows in the row; a tap opens it in the avatar gallery.
        var photo: ChatPhoto?
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
        case richMessage(TDNativeRichMessage)
        case service(ServiceContent)
        case unsupported(ServiceContent)
    }

    static let auditedTDLibCaseCount = 107
    static let auditedTDLibRevision = "1.8.68-c15d3f5a"

    let formattedText: FormattedText?
    let isVisualMedia: Bool
    let summary: String
    let supplement: Supplement

    var isService: Bool {
        if case .service = supplement { return true }
        return false
    }

    static func make(_ message: Message) -> Self {
        if case .messageDice = message.content {
            return make(message.content).dated(message.date)
        }
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

    static func diceStickers(_ dice: DiceStickers?) -> [Sticker] {
        switch dice {
        case .diceStickersRegular(let regular):
            [regular.sticker]
        case .diceStickersSlotMachine(let slot):
            [slot.background, slot.leftReel, slot.centerReel, slot.rightReel, slot.lever]
        case nil:
            []
        }
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
        case .messageRichMessage(let message):
            return Self(
                formattedText: nil,
                isVisualMedia: false,
                summary: RichMessageText.summary(message.message),
                supplement: .richMessage(message.message),
            )
        case .messageAnimation(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(label: L10n.telegram("Message.Animation"), caption: message.caption),
                isVisualMedia: true,
            )
        case .messageAudio(let message):
            // Telegram mediaContentKind: "title — performer", either alone, then the file name or File.
            let title = message.audio.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let performer = message.audio.performer.trimmingCharacters(in: .whitespacesAndNewlines)
            let attachmentSummary =
                switch (title.isEmpty, performer.isEmpty) {
                case (false, false): "\(title) — \(performer)"
                case (false, true): title
                case (true, false): performer
                case (true, true): firstNonEmpty(message.audio.fileName, L10n.telegram("Message.File"))
                }
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
            let title = firstNonEmpty(message.document.fileName, L10n.telegram("Message.File"))
            let summary = message.caption.text.isEmpty ? title : "\(title): \(message.caption.text)"
            return Self(
                formattedText: nonEmpty(message.caption),
                isVisualMedia: false,
                summary: summary,
                supplement: .document(message.document),
            )
        case .messagePaidMedia:
            return excludedPaidContent(title: L10n.betterTG("Message.PaidMedia"))
        case .messagePhoto(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(
                    label: L10n.telegram(message.video == nil ? "Message.Photo" : "Message.LivePhoto"),
                    caption: message.caption,
                ),
                isVisualMedia: true,
            )
        case .messageSticker(let message):
            let emoji = message.sticker.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            return presentation(
                summary: emoji.isEmpty ? L10n.telegram("Message.Sticker") : L10n.telegram("Message.StickerText", emoji),
                isVisualMedia: true,
            )
        case .messageVideo(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(label: L10n.telegram("Message.Video"), caption: message.caption),
                isVisualMedia: true,
            )
        case .messageVideoNote:
            return presentation(summary: L10n.telegram("Message.VideoMessage"), isVisualMedia: true)
        case .messageVoiceNote(let message):
            return presentation(
                formattedText: nonEmpty(message.caption),
                summary: captionSummary(label: L10n.telegram("Message.Audio"), caption: message.caption),
            )
        case .messageExpiredPhoto:
            return service(title: L10n.telegram("Message.ImageExpired"), symbolName: "photo.badge.exclamationmark")
        case .messageExpiredVideo:
            return service(title: L10n.telegram("Message.VideoExpired"), symbolName: "video.badge.ellipsis")
        case .messageExpiredVideoNote:
            return service(title: L10n.telegram("Message.VideoMessageExpired"), symbolName: "video.circle")
        case .messageExpiredVoiceNote:
            return service(
                title: L10n.telegram("Message.VoiceMessageExpired"),
                symbolName: "waveform.badge.exclamationmark",
            )
        case .messageLiveLocation(let message):
            let isIndefinite = liveLocationIndefinite || message.expiresIn >= Int(Int32.max)
            let deadline = liveLocationDeadline ?? (isIndefinite
                ? nil
                : Foundation.Date().addingTimeInterval(TimeInterval(max(0, message.expiresIn))))
            return Self(
                formattedText: nil,
                isVisualMedia: false,
                summary: L10n.telegram("Message.LiveLocation"),
                supplement: .location(LocationContent(
                    liveDeadline: deadline,
                    liveIndefinite: isIndefinite,
                    location: message.location.location,
                    subtitle: nil,
                    title: L10n.telegram("Message.LiveLocation"),
                )),
            )
        case .messageLocation(let message):
            return Self(
                formattedText: nil,
                isVisualMedia: false,
                summary: L10n.telegram("Message.Location"),
                supplement: .location(LocationContent(
                    liveDeadline: nil,
                    liveIndefinite: false,
                    location: message.location,
                    subtitle: nil,
                    title: L10n.telegram("Message.Location"),
                )),
            )
        case .messageVenue(let message):
            let title = firstNonEmpty(message.venue.title, L10n.telegram("Message.Location"))
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
                summary: "\(L10n.telegram("Message.Contact")): \(name)",
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
            let state = message.value == 0 ? message.initialState : message.finalState
            return Self(
                formattedText: nil,
                isVisualMedia: true,
                summary: message.value > 0 ? "\(message.emoji) \(message.value)" : message.emoji,
                supplement: .dice(DiceContent(
                    emoji: message.emoji,
                    stickers: diceStickers(state),
                    value: message.value,
                    messageDate: 0,
                )),
            )
        case .messageGame:
            return unsupported(title: L10n.telegram("Message.Game"), detail: L10n.betterTG("Message.Unsupported.Game"))
        case .messagePoll(let message):
            return Self(
                formattedText: nonEmpty(message.description),
                isVisualMedia: false,
                summary: "📊 \(message.poll.question.text)",
                supplement: .poll(message),
            )
        case .messageStakeDice:
            return excludedPaidContent(title: L10n.betterTG("Message.StakeDice"))
        case .messageStory:
            return unsupported(
                title: L10n.telegram("Message.Story"),
                detail: L10n.betterTG("Message.Unsupported.Story"),
            )
        case .messageChecklist:
            return unsupported(
                title: L10n.betterTG("Message.Checklist"),
                detail: L10n.betterTG("Message.Unsupported.Checklist"),
            )
        case .messageInvoice:
            return unsupported(
                title: L10n.betterTG("Message.Invoice"),
                detail: L10n.betterTG("Message.Unsupported.Invoice"),
            )
        case .messageCall:
            return service(title: L10n.betterTG("Service.Call"), symbolName: "phone")
        case .messageGroupCall:
            return service(title: L10n.betterTG("Service.GroupCall"), symbolName: "person.3")
        case .messageVideoChatScheduled:
            return service(title: L10n.betterTG("Service.VideoChatScheduled"), symbolName: "calendar.badge.clock")
        case .messageVideoChatStarted:
            return service(title: L10n.telegram("Notification.VoiceChatStartedChannel"), symbolName: "video")
        case .messageVideoChatEnded:
            return service(title: L10n.betterTG("Service.VideoChatEnded"), symbolName: "video.slash")
        case .messageInviteVideoChatParticipants:
            return service(title: L10n.betterTG("Service.VideoChatInvited"), symbolName: "person.badge.plus")
        case .messagePollOptionAdded(let message):
            return service(
                title: L10n.betterTG("Service.PollOptionAdded"),
                symbolName: "chart.bar.doc.horizontal",
                targetMessageID: message.pollMessageId,
            )
        case .messagePollOptionDeleted(let message):
            return service(
                title: L10n.betterTG("Service.PollOptionRemoved"),
                symbolName: "chart.bar.doc.horizontal",
                targetMessageID: message.pollMessageId,
            )
        case .messageBasicGroupChatCreate:
            return service(title: L10n.telegram("Notification.CreatedGroup"), symbolName: "person.2")
        case .messageSupergroupChatCreate:
            return service(title: L10n.betterTG("Service.SupergroupCreated"), symbolName: "person.3")
        case .messageChatChangeTitle(let message):
            return service(
                title: L10n.betterTG("Service.TitleChanged"),
                detail: nonEmptyString(message.title),
                symbolName: "pencil",
            )
        case .messageChatChangePhoto(let message):
            return service(title: L10n.betterTG("Service.PhotoChanged"), symbolName: "photo", photo: message.photo)
        case .messageChatDeletePhoto:
            return service(title: L10n.betterTG("Service.PhotoRemoved"), symbolName: "photo.badge.minus")
        case .messageChatOwnerLeft:
            return service(title: L10n.betterTG("Service.OwnerLeft"), symbolName: "person.crop.circle.badge.minus")
        case .messageChatOwnerChanged:
            return service(
                title: L10n.betterTG("Service.OwnerChanged"),
                symbolName: "person.crop.circle.badge.checkmark",
            )
        case .messageChatHasProtectedContentToggled:
            return service(title: L10n.betterTG("Service.ProtectionChanged"), symbolName: "lock.shield")
        case .messageChatHasProtectedContentDisableRequested:
            return service(title: L10n.betterTG("Service.ProtectionDisableRequested"), symbolName: "lock.open")
        case .messageChatAddMembers(let message):
            let count = message.memberUserIds.count
            return service(
                title: count == 1
                    ? L10n.betterTG("Service.MemberJoined")
                    : L10n.betterTG("Service.MembersJoined", count),
                symbolName: "person.badge.plus",
            )
        case .messageChatJoinFromCommunity:
            return service(
                title: L10n.betterTG("Service.JoinedFromCommunity"),
                symbolName: "person.crop.circle.badge.plus",
            )
        case .messageChatJoinByLink:
            return service(title: L10n.betterTG("Service.JoinedByLink"), symbolName: "link")
        case .messageChatJoinByRequest:
            return service(
                title: L10n.betterTG("Service.JoinRequestApproved"),
                symbolName: "person.crop.circle.badge.checkmark",
            )
        case .messageChatDeleteMember:
            return service(title: L10n.betterTG("Service.MemberLeft"), symbolName: "person.badge.minus")
        case .messageChatAddedToCommunity:
            return service(title: L10n.betterTG("Service.AddedToCommunity"), symbolName: "person.3.sequence")
        case .messageChatRemovedFromCommunity:
            return service(title: L10n.betterTG("Service.RemovedFromCommunity"), symbolName: "person.3.sequence")
        case .messageChatUpgradeTo:
            return service(title: L10n.betterTG("Service.GroupUpgraded"), symbolName: "arrow.up.circle")
        case .messageChatUpgradeFrom:
            return service(title: L10n.betterTG("Service.UpgradedFromGroup"), symbolName: "arrow.up.circle")
        case .messagePinMessage(let message):
            return service(
                title: L10n.betterTG("Service.MessagePinned"),
                symbolName: "pin",
                targetMessageID: message.messageId,
            )
        case .messageScreenshotTaken:
            return service(title: L10n.betterTG("Service.Screenshot"), symbolName: "camera.viewfinder")
        case .messageChatSetBackground(let message):
            return service(
                title: L10n.betterTG("Service.BackgroundChanged"),
                symbolName: "photo.on.rectangle",
                targetMessageID: message.oldBackgroundMessageId,
            )
        case .messageChatSetTheme:
            return service(title: L10n.betterTG("Service.ThemeChanged"), symbolName: "paintpalette")
        case .messageChatSetMessageAutoDeleteTime:
            return service(title: L10n.betterTG("Service.AutoDeleteChanged"), symbolName: "timer")
        case .messageChatBoost:
            return excludedPaidContent(title: L10n.betterTG("Message.ChatBoost"))
        case .messageForumTopicCreated:
            return service(
                title: L10n.telegram("Notification.ForumTopicCreated"),
                symbolName: "bubble.left.and.bubble.right",
            )
        case .messageForumTopicEdited:
            return service(title: L10n.betterTG("Service.TopicEdited"), symbolName: "bubble.left.and.pencil")
        case .messageForumTopicIsClosedToggled:
            return service(
                title: L10n.betterTG("Service.TopicStateChanged"),
                symbolName: "bubble.left.and.exclamationmark.bubble.right",
            )
        case .messageForumTopicIsHiddenToggled:
            return service(title: L10n.betterTG("Service.GeneralTopicVisibility"), symbolName: "eye.slash")
        case .messageSuggestProfilePhoto:
            return service(
                title: L10n.betterTG("Service.ProfilePhotoSuggested"),
                symbolName: "person.crop.circle.badge.plus",
            )
        case .messageSuggestBirthdate:
            return service(title: L10n.betterTG("Service.BirthdateSuggested"), symbolName: "birthday.cake")
        case .messageCustomServiceAction(let message):
            return service(
                title: firstNonEmpty(message.text, L10n.betterTG("Service.Generic")),
                symbolName: "info.circle",
            )
        case .messageGameScore(let message):
            return service(
                title: L10n.betterTG("Service.GameScore"),
                symbolName: "trophy",
                targetMessageID: message.gameMessageId,
            )
        case .messageManagedBotCreated:
            return service(title: L10n.betterTG("Service.ManagedBotCreated"), symbolName: "cpu")
        case .messagePaymentRefunded, .messagePaymentSuccessful, .messagePaymentSuccessfulBot,
             .messageTonConnectRequest, .messageTonWalletTransfer:
            return excludedPaidContent(title: L10n.betterTG("Message.Payment"))
        case .messageGiftedPremium, .messagePremiumGiftCode:
            return excludedPaidContent(title: L10n.betterTG("Message.PremiumGift"))
        case .messageGiveaway, .messageGiveawayCompleted, .messageGiveawayCreated, .messageGiveawayWinners:
            return excludedPaidContent(title: L10n.telegram("Message.Giveaway"))
        case .messageGiftedGrams, .messageGiftedStars, .messageGiveawayPrizeStars:
            return excludedPaidContent(title: L10n.betterTG("Message.CurrencyGift"))
        case .messageGift, .messageRefundedUpgradedGift, .messageUpgradedGift:
            return excludedPaidContent(title: L10n.betterTG("Message.Gift"))
        case .messageUpgradedGiftPurchaseOffer, .messageUpgradedGiftPurchaseOfferRejected:
            return excludedPaidContent(title: L10n.betterTG("Message.GiftOffer"))
        case .messageDirectMessagePriceChanged, .messagePaidMessagePriceChanged, .messagePaidMessagesRefunded:
            return excludedPaidContent(title: L10n.betterTG("Message.PaidMessages"))
        case .messageChecklistTasksDone(let message):
            return service(
                title: L10n.betterTG("Service.ChecklistDone"),
                symbolName: "checklist",
                targetMessageID: message.checklistMessageId,
            )
        case .messageChecklistTasksAdded(let message):
            return service(
                title: L10n.betterTG("Service.ChecklistAdded"),
                symbolName: "checklist",
                targetMessageID: message.checklistMessageId,
            )
        case .messageSuggestedPostApprovalFailed:
            return service(title: L10n.betterTG("Service.SuggestedPostFailed"), symbolName: "exclamationmark.circle")
        case .messageSuggestedPostApproved:
            return service(title: L10n.betterTG("Service.SuggestedPostApproved"), symbolName: "checkmark.circle")
        case .messageSuggestedPostDeclined:
            return service(title: L10n.betterTG("Service.SuggestedPostDeclined"), symbolName: "xmark.circle")
        case .messageSuggestedPostPaid, .messageSuggestedPostRefunded:
            return excludedPaidContent(title: L10n.betterTG("Message.SuggestedPostPayment"))
        case .messageContactRegistered:
            return service(title: L10n.betterTG("Service.ContactJoined"), symbolName: "person.crop.circle.badge.plus")
        case .messageUsersShared:
            return service(title: L10n.betterTG("Service.UsersShared"), symbolName: "person.2")
        case .messageChatShared:
            return service(title: L10n.betterTG("Service.ChatShared"), symbolName: "bubble.left.and.bubble.right")
        case .messageBotWriteAccessAllowed:
            return service(title: L10n.betterTG("Service.BotAllowed"), symbolName: "checkmark.shield")
        case .messageWebAppDataSent:
            return service(title: L10n.betterTG("Service.WebAppSent"), symbolName: "app.badge.checkmark")
        case .messageWebAppDataReceived:
            return service(title: L10n.betterTG("Service.WebAppReceived"), symbolName: "app.badge")
        case .messagePassportDataSent:
            return service(title: L10n.betterTG("Service.PassportSent"), symbolName: "person.text.rectangle")
        case .messagePassportDataReceived:
            return service(title: L10n.betterTG("Service.PassportReceived"), symbolName: "person.text.rectangle")
        case .messageProximityAlertTriggered:
            return service(title: L10n.betterTG("Service.ProximityAlert"), symbolName: "location.circle")
        case .messageUnsupported:
            return unsupported(
                title: L10n.betterTG("Message.Unsupported"),
                detail: L10n.betterTG("Message.Unsupported.TDLib"),
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
        targetMessageID: Int64? = nil,
        photo: ChatPhoto? = nil,
    ) -> Self {
        Self(
            formattedText: nil,
            isVisualMedia: false,
            summary: title,
            supplement: .service(ServiceContent(
                detail: detail,
                symbolName: symbolName,
                title: title,
                targetMessageID: targetMessageID.flatMap { $0 == 0 ? nil : $0 },
                photo: photo,
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
            detail: L10n.betterTG("Message.Unsupported.Paid"),
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
        strings.lazy.compactMap(nonEmptyString).first ?? L10n.betterTG("Message.Generic")
    }

    private static func captionSummary(label: String, caption: FormattedText) -> String {
        caption.text.isEmpty ? label : "\(label): \(caption.text)"
    }

    private static func contactName(_ contact: Contact) -> String {
        firstNonEmpty("\(contact.firstName) \(contact.lastName)", contact.phoneNumber, L10n.telegram("Message.Contact"))
    }

    private static func coordinateString(_ location: Location) -> String {
        String(format: "%.5f, %.5f", location.latitude, location.longitude)
    }

    /// Telegram's actor wording for a service action, once its names are resolved. The wording already names the
    /// changed value, so the generic detail line is dropped.
    func replacingServiceTitle(_ title: String?) -> Self {
        guard let title, case .service(let content) = supplement else { return self }
        return Self(
            formattedText: formattedText,
            isVisualMedia: isVisualMedia,
            summary: title,
            supplement: .service(ServiceContent(
                detail: nil,
                symbolName: content.symbolName,
                title: title,
                targetMessageID: content.targetMessageID,
                photo: content.photo,
            )),
        )
    }

    private func dated(_ date: Int) -> Self {
        guard case .dice(let dice) = supplement else { return self }
        return Self(
            formattedText: formattedText,
            isVisualMedia: isVisualMedia,
            summary: summary,
            supplement: .dice(DiceContent(
                emoji: dice.emoji,
                stickers: dice.stickers,
                value: dice.value,
                messageDate: date,
            )),
        )
    }
}
