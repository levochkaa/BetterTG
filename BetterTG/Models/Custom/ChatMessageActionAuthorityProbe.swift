// ChatMessageActionAuthorityProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum ChatMessageActionAuthorityProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Rows {
        let collection: UICollectionView
        let client = TDLib.shared.activeClient
        let polls = MessagePollInteractionStore()
        let source: TdUpdateSource
        let location: ChatLocation
        var currentSource: TdUpdateSource?
        var current: CustomMessage?
        var ownerIsCurrent = true
        var isFull = true
        var isSelecting = true
        var isSelected = false
        var isReadOnly = false
        var canAddReactions = true
        var calls = 0
        var completed = 0
        var authority: ChatMessageActionAuthority?
        var contentAction: ((MessageContentAction) -> Void)?
        var acceptedPoll: MessagePollInteractionStore.Submission?
        var data: UICollectionViewDiffableDataSource<Int, DisplayedMessageID>!

        init() {
            self.source = TdUpdateSource(accountID: UUID(), clientID: client.id)
            self.currentSource = source
            self.location = .init(accountID: source.accountID, chatID: 100, clientID: client.id, topic: nil)
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: 350, height: 170)
            self.collection = UICollectionView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 550),
                collectionViewLayout: layout,
            )
            collection.register(MessageCell.self, forCellWithReuseIdentifier: "action")
            self
                .data = UICollectionViewDiffableDataSource<
                    Int,
                    DisplayedMessageID,
                >(collectionView: collection) { [weak self] list, path, _ in
                ChatTimelineCellProvider.dequeue(
                    MessageCell.self, from: list, at: path, reuseIdentifier: "action",
                    configure: { [weak self] cell in
                        guard let self, let current else { return false }
                        configure(cell, message: current)
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
            }
        }

        func configure(_ cell: MessageCell, message: CustomMessage, renderValue: ChatMessageRenderValue? = nil) {
            let authority = ChatMessageActionAuthority(
                message: message, cell: cell, source: source, location: location, selected: isSelected,
                renderValue: renderValue,
            )
            self.authority = authority
            let action: (MessageContentAction) -> Void = { [weak self, weak polls] action in
                guard let self, invoke(authority, .content(action)) else {
                    action.rejectPollSubmission(in: polls)
                    return
                }
                if case .submitPollAnswer(_, _, let submission) = action { acceptedPoll = submission }
            }
            contentAction = action
            cell.configure(
                message: renderValue?.makeRenderOnlyMessage() ?? message,
                chat: RootChatInsertionProbe.chat(
                    .init(isPinned: false, list: .chatListMain, order: 1, source: nil),
                    id: 100,
                ),
                highlighted: false, client: client, pollInteractionStore: polls,
                canAddReactions: canAddReactions, selectionActive: isSelecting, selected: isSelected,
                onSwipeToReply: { [weak self] in _ = self?.invoke(authority, .reply) },
                onSelectionToggle: { [weak self] in _ = self?.invoke(authority, .selection) },
                onReactionTap: { [weak self] in _ = self?.invoke(authority, .reaction($0)) },
                onMetadataNavigate: { [weak self] in _ = self?.invoke(authority, .metadata($0)) },
                onReplyQuoteExpand: { [weak self] in _ = self?.invoke(authority, .quote) },
                onContentAction: action,
                onMediaTap: { [weak self] _, _ in _ = self?.invoke(authority, .media) },
                actionBindingID: authority.bindingID,
            )
        }

        @discardableResult func invoke(
            _ authority: ChatMessageActionAuthority,
            _ intent: ChatMessageActionAuthority.Intent,
        ) -> Bool {
            let resolved = authority.resolve(
                intent, current: current, source: currentSource, location: location,
                ownerIsCurrent: ownerIsCurrent,
                rowIsCurrent: data.snapshot().itemIdentifiers.contains(authority.displayedID),
                state: .init(
                    isFull: isFull,
                    isSelecting: isSelecting,
                    isReadOnly: isReadOnly,
                    canAddReactions: canAddReactions,
                    isSelected: isSelected,
                ),
            )
            if resolved != nil { calls += 1 }
            return resolved != nil
        }

        func apply(reconfigure: Bool = false) {
            var snapshot = data.snapshot()
            if reconfigure { snapshot.reconfigureItems(snapshot.itemIdentifiers) }
            else {
                snapshot.appendSections([0])
                snapshot.appendItems(current.map { [$0.displayedID] } ?? [])
            }
            data.apply(snapshot, animatingDifferences: false) { [weak self] in self?.completed += 1 }
        }
    }

    static func verify() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw Failure(description: "action fixture has no scene")
        }
        let rows = Rows()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(rows.collection)
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil
        }
        let message = makeMessage()
        rows.current = message
        rows.apply()
        try await until { rows.completed == 1 }
        rows.collection.layoutIfNeeded()
        guard let cell = rows.collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? MessageCell,
              let first = rows.authority,
              let oldSelect = selectionAction(cell), let oldMedia = cell.probeMediaAction
        else {
            throw Failure(description: "action fixture was not armed")
        }
        func select(_ action: UIAccessibilityCustomAction = oldSelect) { _ = action.actionHandler?(action) }
        select()
        try require(rows.calls == 1, "current selection action failed")
        rows.isSelected = true
        select()
        try require(rows.calls == 1, "stale select label became deselect")
        rows.isSelected = false
        rows.isFull = false
        select()
        rows.isFull = true
        rows.ownerIsCurrent = false
        select()
        rows.ownerIsCurrent = true
        rows.currentSource = .init(accountID: UUID(), clientID: rows.source.clientID)
        select()
        rows.currentSource = .init(accountID: rows.source.accountID, clientID: rows.source.clientID + 1)
        select()
        rows.currentSource = rows.source
        rows.isSelecting = false
        select()
        rows.isSelecting = true
        rows.current = nil
        select()
        rows.current = makeMessage()
        select()
        rows.current = message
        message.message = MessageDeliveryProbe.fixture(id: 70, content: .messageText(.init(
            linkPreview: nil, linkPreviewOptions: nil, text: .init(entities: [], text: "changed payload"),
        )))
        select()
        message.message = MessageDeliveryProbe.fixture(id: 70)
        message.album = [message.message, MessageDeliveryProbe.fixture(id: 71)]
        select()
        message.album = []
        message.formattedText = .init(entities: [], text: "derived edit")
        select()
        message.formattedText = nil
        message.replyPresentation = reply(target: 99)
        select()
        message.replyPresentation = nil
        message.forwardPresentation = forward(target: 99)
        select()
        message.forwardPresentation = nil
        message.isReplyQuoteExpanded = true
        select()
        message.isReplyQuoteExpanded = false
        try require(rows.calls == 1, "stale source/route/owner/payload action escaped")
        select()
        try require(rows.calls == 2, "equal current payload did not recover")
        rows.apply(reconfigure: true)
        try await until { rows.completed == 2 }
        try require(
            rows.collection.cellForItem(at: IndexPath(item: 0, section: 0)) === cell,
            "binding test replaced native cell",
        )
        guard let second = rows.authority, let newSelect = selectionAction(cell),
              let newMedia = cell.probeMediaAction
        else {
            throw Failure(description: "rebound action fixture missing")
        }
        select()
        try require(!rows.invoke(first, .selection) && rows.calls == 2, "old same-ID binding revived")
        select(newSelect)
        try require(rows.calls == 3, "new same-ID action failed")
        rows.isSelecting = false
        oldMedia(message.sourceMessages, 70)
        try require(rows.calls == 3, "old media bridge invoked new callback")
        newMedia(message.sourceMessages, 70)
        try require(rows.calls == 4, "current media bridge failed")
        try require(!rows.invoke(second, .reply), "reply ignored current message permission")
        message.properties = replyProperties()
        try require(rows.invoke(second, .reply), "current reply permission failed")
        rows.isReadOnly = true
        try require(!rows.invoke(second, .reply), "read-only reply admitted")
        rows.isReadOnly = false
        try verifyReaction(rows, cell: cell, message: message)
        try verifyMetadata(rows, cell: cell, message: message)
        try verifyPollRejection(rows, cell: cell, message: message)
        let latest = rows.authority!
        let calls = rows.calls
        cell.resetUnavailableContent()
        try require(!rows.invoke(latest, .media), "unavailable cell kept binding")
        newMedia(message.sourceMessages, 70)
        try require(rows.calls == calls, "reset cell retained media bridge authority")
        try await verifyRenderValues(rows)
    }

    private static func verifyRenderValues(_ rows: Rows) async throws {
        let type = ReactionType.reactionTypeEmoji(.init(emoji: "👍"))
        let rawReactions = MessageReactions(areTags: false, canGetAddedReactions: false, paidReactors: [], reactions: [
            .init(isChosen: true, recentSenderIds: [], totalCount: 1, type: type, usedSenderId: nil),
        ])
        let unread = UnreadReaction(isBig: true, senderId: .messageSenderUser(.init(userId: 2)), type: type)
        // Native TDLibKit 2 views are immutable and not Codable; build the variant directly.
        let raw = MessageDeliveryProbe.fixture(
            id: 70,
            album: 77,
            interactionInfo: MessageInteractionInfo(
                forwardCount: 0, reactions: rawReactions, replyInfo: nil, viewCount: 0,
            ),
            unreadReactions: [unread],
        )
        let older = MessageDeliveryProbe.fixture(id: 69, album: 77)
        let canonical = CustomMessage(
            message: raw, senderUser: sender(), replyPresentation: reply(target: 99),
            forwardPresentation: forward(target: 200), album: [raw, older], sendFailed: true,
            formattedText: .init(entities: [], text: "frozen caption"), properties: replyProperties(),
            unreadReactions: [], isPinned: true,
        )
        canonical.reactions = nil
        canonical.reactionMutationInFlight = true
        canonical.isReplyQuoteExpanded = true
        canonical.updateDeliveryState(permitsFinalStatus: true, readOutbox: 70)
        let frozen = ChatMessageRenderValue(canonical)
        try require(
            frozen.message.interactionInfo?.reactions == rawReactions && frozen.reactions == nil
                && frozen.message.unreadReactions == [unread] && frozen.unreadReactions.isEmpty
                && frozen.deliveryState == .read && frozen.reactionMutationInFlight,
            "render value explicit nil/derived-state fixture was not armed",
        )
        canonical.message = older
        canonical.album = [older]
        canonical.senderUser = nil
        canonical.replyPresentation = nil
        canonical.forwardPresentation = nil
        canonical.formattedText = nil
        canonical.sendFailed = false
        canonical.properties = .default
        canonical.reactions = rawReactions
        canonical.unreadReactions = [unread]
        canonical.isPinned = false
        canonical.isReplyQuoteExpanded = false
        canonical.reactionMutationInFlight = false
        canonical.updateDeliveryState(permitsFinalStatus: true, readOutbox: 0)
        let copy = frozen.makeRenderOnlyMessage()
        try require(
            copy !== canonical && frozen.displayedID == .album(77) && copy.displayedID == frozen.displayedID
                && frozen.message == raw && frozen.album == [raw, older]
                && frozen.sourceMessages == [raw, older] && frozen.senderUser == sender()
                && sameReply(frozen.replyPresentation, reply(target: 99))
                && sameForward(frozen.forwardPresentation, forward(target: 200))
                && frozen.formattedText == .init(entities: [], text: "frozen caption")
                && copy.message == frozen.message && copy.album == frozen.album && copy.senderUser == frozen.senderUser
                && sameReply(copy.replyPresentation, frozen.replyPresentation)
                && sameForward(copy.forwardPresentation, frozen.forwardPresentation)
                && copy.formattedText == frozen.formattedText && copy.sendFailed && frozen.sendFailed
                && copy.properties == frozen.properties && copy.properties.canBeReplied
                && copy.reactions == nil && copy.unreadReactions.isEmpty
                && copy.isPinned && frozen.isPinned && copy.isReplyQuoteExpanded && frozen.isReplyQuoteExpanded
                && copy.deliveryState == .read && frozen.deliveryState == .read
                && copy.reactionMutationInFlight && frozen.reactionMutationInFlight,
            "canonical promotion or materialization changed immutable complete rendering state",
        )
        copy.album.removeAll()
        copy.message = MessageDeliveryProbe.fixture(id: 123)
        copy.reactions = rawReactions
        copy.isReplyQuoteExpanded = false
        copy.reactionMutationInFlight = false
        copy.updateDeliveryState(permitsFinalStatus: false, readOutbox: nil)
        try require(
            canonical.message == older && canonical.album == [older] && canonical.deliveryState == .delivered
                && frozen.message == raw && frozen.album == [raw, older] && frozen.reactions == nil
                && frozen.isReplyQuoteExpanded && frozen.reactionMutationInFlight && frozen.deliveryState == .read,
            "render clone mutation escaped into canonical or frozen state",
        )
        rows.current = canonical
        var snapshot = NSDiffableDataSourceSnapshot<Int, DisplayedMessageID>()
        snapshot.appendSections([0])
        snapshot.appendItems([canonical.displayedID])
        var completed = false
        rows.data.apply(snapshot, animatingDifferences: false) { completed = true }
        try await until { completed }
        rows.collection.layoutIfNeeded()
        guard let cell = rows.collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? MessageCell else {
            throw Failure(description: "render-value native album cell missing")
        }
        rows.configure(cell, message: canonical, renderValue: frozen)
        try require(!rows.invoke(rows.authority!, .media), "old render baseline was recaptured from current canonical")
        let current = ChatMessageRenderValue(canonical)
        let currentCopy = current.makeRenderOnlyMessage()
        try require(
            currentCopy.reactions == rawReactions && currentCopy.unreadReactions == [unread]
                    && currentCopy.deliveryState == .delivered && !currentCopy.reactionMutationInFlight,
            "fresh materialization lost reactions/unread/delivery or mutation state",
        )
        rows.configure(cell, message: canonical, renderValue: current)
        try require(rows.invoke(rows.authority!, .media), "fresh render baseline rejected same canonical")
        rows.current = current.makeRenderOnlyMessage()
        try require(!rows.invoke(rows.authority!, .media), "render-only clone acquired canonical action authority")
        rows.current = canonical
        try require(rows.invoke(rows.authority!, .media), "canonical identity did not recover with fresh baseline")
    }

    private static func sameReply(_ lhs: MessageReplyPresentation?, _ rhs: MessageReplyPresentation?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.availability == rhs.availability && lhs.body == rhs.body && lhs.navigationTarget == rhs
            .navigationTarget
            && lhs.quote == rhs.quote && lhs.referencedChatID == rhs.referencedChatID
            && lhs.referencedUserID == rhs.referencedUserID && lhs.targetChatID == rhs.targetChatID
            && lhs.targetMessageID == rhs.targetMessageID && lhs.title == rhs.title
            && lhs.thumbnail?.file == rhs.thumbnail?.file && lhs.thumbnail?.isRound == rhs.thumbnail?.isRound
            && lhs.thumbnail?.minithumbnailData == rhs.thumbnail?.minithumbnailData
    }

    private static func sameForward(_ lhs: MessageForwardPresentation?, _ rhs: MessageForwardPresentation?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.avatar?.file == rhs.avatar?.file && lhs.avatar?.initials == rhs.avatar?.initials
            && lhs.avatar?.minithumbnailData == rhs.avatar?.minithumbnailData && lhs.headline == rhs.headline
            && lhs.navigationTarget == rhs.navigationTarget && lhs.originalSourceTitle == rhs.originalSourceTitle
            && lhs.publicServiceAnnouncementType == rhs.publicServiceAnnouncementType
            && lhs.referencedChatIDs == rhs.referencedChatIDs && lhs.referencedUserIDs == rhs.referencedUserIDs
            && lhs.sourceTitle == rhs.sourceTitle && lhs.targetChatID == rhs.targetChatID
            && lhs.targetMessageID == rhs.targetMessageID
    }

    private static func sender() -> User {
        .init(
            accentColorId: 1,
            activeStoryState: nil,
            addedToAttachmentMenu: false,
            backgroundCustomEmojiId: 0,
            emojiStatus: nil,
            firstName: "Render sender",
            haveAccess: true,
            id: 1,
            isCloseFriend: false,
            isContact: false,
            isMutualContact: false,
            isPremium: false,
            isSupport: false,
            languageCode: "",
            lastName: "",
            paidMessageStarCount: 0,
            phoneNumber: "",
            profileAccentColorId: -1,
            profileBackgroundCustomEmojiId: 0,
            profilePhoto: nil,
            restrictionInfo: nil,
            restrictsNewChats: false,
            status: .userStatusEmpty,
            type: .userTypeRegular,
            upgradedGiftColors: nil,
            usernames: nil,
            verificationStatus: nil,
        )
    }

    private static func verifyReaction(_ rows: Rows, cell: MessageCell, message: CustomMessage) throws {
        let type = ReactionType.reactionTypeEmoji(.init(emoji: "👍"))
        func reactions(_ chosen: Bool) -> MessageReactions {
            .init(areTags: false, canGetAddedReactions: false, paidReactors: [], reactions: [
                .init(isChosen: chosen, recentSenderIds: [], totalCount: 1, type: type, usedSenderId: nil),
            ])
        }
        message.reactions = reactions(true)
        rows.configure(cell, message: message)
        guard let action = cell.accessibilityCustomActions?.first(where: { $0.name.hasPrefix("Remove ") }) else {
            throw Failure(description: "chosen reaction AX action missing")
        }
        rows.canAddReactions = false
        let calls = rows.calls
        _ = action.actionHandler?(action)
        try require(rows.calls == calls + 1, "chosen removal incorrectly needs add permission")
        message.reactions = reactions(false)
        _ = action.actionHandler?(action)
        try require(rows.calls == calls + 1, "stale remove reaction became add")
        rows.configure(cell, message: message)
        try require(!rows.invoke(rows.authority!, .reaction(type)), "reaction add ignored permission")
        rows.canAddReactions = true
        try require(rows.invoke(rows.authority!, .reaction(type)), "fresh reaction add rejected")
        message.reactionMutationInFlight = true
        try require(!rows.invoke(rows.authority!, .reaction(type)), "in-flight reaction admitted")
        message.reactionMutationInFlight = false
    }

    private static func verifyMetadata(_ rows: Rows, cell: MessageCell, message: CustomMessage) throws {
        message.replyPresentation = reply(target: 99)
        rows.configure(cell, message: message)
        guard let action = cell.accessibilityCustomActions?.first(where: { $0.name == "Open replied message" }) else {
            throw Failure(description: "metadata AX action missing")
        }
        let calls = rows.calls
        _ = action.actionHandler?(action)
        try require(rows.calls == calls + 1 && rows.invoke(rows.authority!, .quote), "current metadata/quote rejected")
        message.replyPresentation = reply(target: 100)
        _ = action.actionHandler?(action)
        try require(rows.calls == calls + 2, "old derived metadata navigated")
        message.replyPresentation = nil
    }

    private static func verifyPollRejection(_ rows: Rows, cell: MessageCell, message: CustomMessage) throws {
        message.message = MessageDeliveryProbe.fixture(id: 70, content: .messagePoll(poll(closed: false)))
        rows.configure(cell, message: message)
        let store = rows.polls
        guard let option = controls(cell).first(where: { $0.accessibilityLabel == "Action option" }),
              option.isEnabled
        else {
            throw Failure(description: "enabled native poll option missing")
        }
        let calls = rows.calls
        option.sendActions(for: .touchUpInside)
        guard let first = rows.acceptedPoll else { throw Failure(description: "native poll option did not submit") }
        try require(
            rows.calls == calls + 1 && store.currentSubmission(messageID: 70) == first,
            "native poll did not carry its exact accepted Submission",
        )
        let old = MessageContentAction.submitPollAnswer(messageID: 70, optionIDs: [0], submission: first)
        rows.ownerIsCurrent = false
        rows.contentAction?(old)
        try require(store.currentSubmission(messageID: 70) == nil, "rejected action left poll busy")
        let second = store.beginSubmission(messageID: 70, sourceSelection: [])!
        rows.contentAction?(old)
        try require(store.currentSubmission(messageID: 70) == second, "old rejection canceled new retry")
        store.failSubmission(second)
        var replacement: MessagePollInteractionStore.Submission?
        var reentered = false
        let subscription = store.changes.sink { _ in
            guard !reentered, let pending = store.currentSubmission(messageID: 70) else { return }
            reentered = true
            store.failSubmission(pending)
            replacement = store.beginSubmission(messageID: 70, sourceSelection: [])
        }
        let returned = store.beginSubmission(messageID: 70, sourceSelection: [])!
        try require(
            reentered && returned != replacement && replacement == store.currentSubmission(messageID: 70),
            "reentrant notification replaced returned Submission identity",
        )
        MessageContentAction.submitPollAnswer(messageID: 70, optionIDs: [1], submission: returned)
            .rejectPollSubmission(in: store)
        try require(store.currentSubmission(messageID: 70) == replacement, "exact reentrant rejection canceled retry")
        subscription.cancel()
        if let replacement { store.failSubmission(replacement) }
        rows.ownerIsCurrent = true
        message.message = MessageDeliveryProbe.fixture(id: 70, content: .messagePoll(poll(closed: true)))
        rows.configure(cell, message: message)
        try require(
            controls(cell).first(where: { $0.accessibilityLabel == "Action option" })?.isEnabled == false,
            "closed poll option remained enabled",
        )
        let closed = store.beginSubmission(messageID: 70, sourceSelection: [])!
        rows.contentAction?(.submitPollAnswer(messageID: 70, optionIDs: [0], submission: closed))
        try require(
            rows.calls == calls + 1 && store.currentSubmission(messageID: 70) == nil,
            "closed poll admitted vote or retained rejected submission",
        )
    }

    private static func controls(_ view: UIView) -> [UIControl] {
        ((view as? UIControl).map { [$0] } ?? []) + view.subviews.flatMap(controls)
    }

    private static func poll(closed: Bool) -> MessagePoll {
        .init(canAddOption: false, description: .init(entities: [], text: ""), media: nil, poll: .init(
            allowsMultipleAnswers: false, allowsRevoting: true, canGetVoters: false, canSeeResults: false,
            closeDate: 0, countryCodes: [], id: 700, isAnonymous: true, isClosed: closed, membersOnly: false,
            openPeriod: 0, optionOrder: [0], options: [
                .init(
                    additionDate: 0,
                    author: nil,
                    id: "first",
                    isBeingChosen: false,
                    isChosen: false,
                    media: nil,
                    recentVoterIds: [],
                    text: .init(entities: [], text: "Action option"),
                    votePercentage: 0,
                    voterCount: 0,
                ),
            ], question: .init(entities: [], text: "Action poll"), recentVoterIds: [], totalVoterCount: 0,
            type: .pollTypeRegular, voteRestrictionReason: nil,
        ))
    }

    private static func selectionAction(_ cell: MessageCell) -> UIAccessibilityCustomAction? {
        cell.accessibilityCustomActions?.first { $0.name == "Select Message" }
    }

    private static func makeMessage() -> CustomMessage {
        .init(message: MessageDeliveryProbe.fixture(id: 70), properties: .default)
    }

    private static func reply(target: Int64) -> MessageReplyPresentation {
        .init(
            availability: .resolved,
            body: .init(entities: [], text: "quote"),
            navigationTarget: .message(chatID: 100, messageID: target, quote: nil),
            quote: .init(isManual: true, position: 0, text: .init(entities: [], text: "quote")),
            referencedChatID: 100,
            referencedUserID: nil,
            targetChatID: 100,
            targetMessageID: target,
            thumbnail: nil,
            title: "Reply",
        )
    }

    private static func forward(target: Int64) -> MessageForwardPresentation {
        .init(
            avatar: nil,
            headline: "Forwarded",
            navigationTarget: .chat(chatID: target),
            originalSourceTitle: "Source",
            publicServiceAnnouncementType: nil,
            referencedChatIDs: [target],
            referencedUserIDs: [],
            sourceTitle: "Source",
            targetChatID: target,
            targetMessageID: nil,
        )
    }

    private static func replyProperties() -> MessageProperties {
        MessageProperties(
            canAddOffer: false,
            canAddTasks: false,
            canBeApproved: false,
            canBeCopied: false,
            canBeCopiedToSecretChat: false,
            canBeDeclined: false,
            canBeDeletedForAllUsers: false,
            canBeDeletedOnlyForSelf: false,
            canBeEdited: false,
            canBeForwarded: false,
            canBePaid: false,
            canBePinned: false,
            canBeReplied: true,
            canBeRepliedInAnotherChat: false,
            canBeSaved: false,
            canBeSharedInStory: false,
            canDeleteReactions: false,
            canEditMedia: false,
            canEditSchedulingState: false,
            canEditSuggestedPostInfo: false,
            canGetAuthor: false,
            canGetEmbeddingCode: false,
            canGetLink: false,
            canGetMediaTimestampLinks: false,
            canGetMessageThread: false,
            canGetPollVoteStatistics: false,
            canGetReadDate: false,
            canGetStatistics: false,
            canGetVideoAdvertisements: false,
            canGetViewers: false,
            canMarkTasksAsDone: false,
            canRecognizeSpeech: false,
            canReportChat: false,
            canReportReactions: false,
            canReportSupergroupSpam: false,
            canSetFactCheck: false,
            hasProtectedContentByCurrentUser: false,
            hasProtectedContentByOtherUser: false,
            needShowStatistics: false,
        )
    }

    private static func require(_ value: Bool, _ text: String) throws {
        if !value { throw Failure(description: text) }
    }

    private static func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure(description: "native action snapshot completion timed out")
    }
}
#endif
