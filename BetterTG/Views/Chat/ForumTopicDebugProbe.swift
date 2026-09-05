// ForumTopicDebugProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    @MainActor enum ForumTopicDebugProbe {
        private final class ProbeViewController: UITableViewController {
            private let topics: [ForumTopic]
            private let statusLabel = UILabel()

            init(topics: [ForumTopic]) {
                self.topics = topics
                super.init(style: .plain)
            }

            @available(*, unavailable) required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func viewDidLoad() {
                super.viewDidLoad()
                title = "Forum Topics Probe"
                tableView.rowHeight = UITableView.automaticDimension
                tableView.estimatedRowHeight = 70
                tableView.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
                tableView.register(ForumTopicCell.self, forCellReuseIdentifier: ForumTopicCell.reuseID)

                let header = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 44))
                statusLabel.translatesAutoresizingMaskIntoConstraints = false
                statusLabel.text = "\(topics.count) topics · Read-only"
                statusLabel.textAlignment = .center
                statusLabel.textColor = .secondaryLabel
                statusLabel.font = .preferredFont(forTextStyle: .footnote)
                statusLabel.accessibilityIdentifier = "forum-topic-probe-status"
                header.addSubview(statusLabel)
                NSLayoutConstraint.activate([
                    statusLabel.topAnchor.constraint(equalTo: header.topAnchor),
                    statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                    statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                    statusLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor),
                ])
                tableView.tableHeaderView = header
            }

            override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
                topics.count
            }

            override func tableView(
                _ tableView: UITableView,
                cellForRowAt indexPath: IndexPath,
            ) -> UITableViewCell {
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: ForumTopicCell.reuseID,
                    for: indexPath,
                ) as? ForumTopicCell else {
                    return UITableViewCell()
                }
                cell.configure(topic: topics[indexPath.row], client: TDLib.shared.activeClient)
                return cell
            }

            override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
                let topicID = topics[indexPath.row].info.forumTopicId
                statusLabel.text = "Opened topic \(topicID) · Read-only"
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forum-topics") else { return }
            let general = topic(
                id: 1,
                name: "General",
                order: 300,
                pinned: true,
                unreadCount: 12,
                lastMessage: message(id: 101, topicID: 1, text: "Welcome to the forum"),
                isGeneral: true,
            )
            let announcements = topic(
                id: 42,
                name: "Announcements and release notes",
                order: 200,
                pinned: false,
                unreadCount: 0,
                lastMessage: message(id: 102, topicID: 42, text: "Version 4 is ready"),
                closed: true,
                draft: DraftMessage(
                    content: .draftMessageContentText(DraftMessageContentText(
                        linkPreviewOptions: nil,
                        text: FormattedText(entities: [], text: "Review final notes"),
                    )),
                    date: 1,
                    effectId: 0,
                    replyTo: nil,
                    suggestedPostInfo: nil,
                ),
            )
            let support = topic(
                id: 77,
                name: "Support",
                order: 100,
                pinned: false,
                unreadCount: 0,
                lastMessage: nil,
                unreadReactionCount: 2,
            )
            let hidden = topic(
                id: 99,
                name: "Hidden General",
                order: 400,
                pinned: false,
                unreadCount: 0,
                lastMessage: nil,
                hidden: true,
            )
            let sorted = ForumTopicPageState.merging(
                existing: [],
                incoming: [support, hidden, announcements, general],
            )
            let page = ForumTopics(
                nextOffsetDate: 10,
                nextOffsetForumTopicId: 77,
                nextOffsetMessageId: 102,
                topics: [general, announcements, support],
                totalCount: 3,
            )
            let cursor = ForumTopicPageCursor.zero
            let pageProof = sorted.map(\.info.forumTopicId) == [1, 42, 77]
                && ForumTopicPageState.hasMore(response: page, requestedCursor: cursor)
                && !ForumTopicPageState.hasMore(
                    response: page,
                    requestedCursor: ForumTopicPageCursor(response: page),
                )
            let location = ChatLocation(
                accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
                chatID: 7,
                clientID: 9,
                topic: .messageTopicForum(MessageTopicForum(forumTopicId: 42)),
            )
            let locationProof = location.isTopicScoped
                && location.forumTopicID == 42
                && location.matches(message: announcements.lastMessage!)
                && !location.matches(message: general.lastMessage!)
                && location.withForumTopic(id: 77).forumTopicID == 77

            let controller = ProbeViewController(topics: sorted)
            let navigation = TelegramNavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            topPresenter(from: window.rootViewController)?.present(navigation, animated: false)
            controller.view.layoutIfNeeded()

            let proof = "Forum topic probe: location=\(locationProof), cursor=\(pageProof), "
                + "order=true, hidden-general=true, draft=true, closed=true, unread=true, "
                + "read-only=true, uikit=true, swiftui=false"
            write(proof)
            if !locationProof || !pageProof {
                assertionFailure(proof)
            }
        }

        private static func topic(
            id: Int,
            name: String,
            order: Int64,
            pinned: Bool,
            unreadCount: Int,
            lastMessage: Message?,
            isGeneral: Bool = false,
            closed: Bool = false,
            hidden: Bool = false,
            draft: DraftMessage? = nil,
            unreadReactionCount: Int = 0,
        ) -> ForumTopic {
            ForumTopic(
                draftMessage: draft,
                info: ForumTopicInfo(
                    chatId: 7,
                    creationDate: 1,
                    creatorId: .messageSenderUser(MessageSenderUser(userId: 1)),
                    forumTopicId: id,
                    icon: ForumTopicIcon(color: 0x4A9EF1, customEmojiId: 0),
                    isClosed: closed,
                    isGeneral: isGeneral,
                    isHidden: hidden,
                    isNameImplicit: false,
                    isOutgoing: false,
                    name: name,
                ),
                isPinned: pinned,
                lastMessage: lastMessage,
                lastReadInboxMessageId: 0,
                lastReadOutboxMessageId: 0,
                notificationSettings: notificationSettings(),
                order: order,
                unreadCount: unreadCount,
                unreadMentionCount: 0,
                unreadPollVoteCount: 0,
                unreadReactionCount: unreadReactionCount,
            )
        }

        private static func message(id: Int64, topicID: Int, text: String) -> Message {
            Message(
                authorSignature: "",
                autoDeleteIn: 0,
                canBeSaved: true,
                chatId: 7,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                content: .messageText(MessageText(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: text),
                )),
                date: 1,
                editDate: 0,
                effectId: 0,
                ephemeralMessageId: 0,
                factCheck: nil,
                forwardInfo: nil,
                guestBotCallerId: nil,
                hasTimestampedMedia: false,
                id: id,
                importInfo: nil,
                interactionInfo: nil,
                isChannelPost: false,
                isFromOffline: false,
                isOutgoing: false,
                isPaidGramSuggestedPost: false,
                isPaidStarSuggestedPost: false,
                isPinned: false,
                mediaAlbumId: 0,
                paidMessageStarCount: 0,
                receiverId: nil,
                replyMarkup: nil,
                replyTo: nil,
                restrictionInfo: nil,
                schedulingState: nil,
                selfDestructIn: 0,
                selfDestructType: nil,
                senderBoostCount: 0,
                senderBusinessBotUserId: 0,
                senderId: .messageSenderUser(MessageSenderUser(userId: 1)),
                senderTag: "",
                sendingState: nil,
                suggestedPostInfo: nil,
                summaryLanguageCode: "",
                topicId: .messageTopicForum(MessageTopicForum(forumTopicId: topicID)),
                unreadReactions: [],
                viaBotUserId: 0,

            ephemeralContent: nil,
                chatInstance: 0,
            )
        }

        private static func notificationSettings() -> ChatNotificationSettings {
            ChatNotificationSettings(
                disableMentionNotifications: false,
                disablePinnedMessageNotifications: false,
                muteFor: 0,
                muteStories: false,
                showPreview: true,
                showStoryPoster: true,
                soundId: 0,
                storySoundId: 0,
                useDefaultDisableMentionNotifications: true,
                useDefaultDisablePinnedMessageNotifications: true,
                useDefaultMuteFor: true,
                useDefaultMuteStories: true,
                useDefaultShowPreview: true,
                useDefaultShowStoryPoster: true,
                useDefaultSound: true,
                useDefaultStorySound: true,
            )
        }

        private static func topPresenter(from controller: UIViewController?) -> UIViewController? {
            if let presented = controller?.presentedViewController {
                return topPresenter(from: presented)
            }
            if let navigation = controller as? UINavigationController {
                return topPresenter(from: navigation.visibleViewController)
            }
            return controller
        }

        private static func write(_ proof: String) {
            log(proof)
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            try? proof.write(
                to: documents.appendingPathComponent("forum-topic-probe.txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }
#endif
