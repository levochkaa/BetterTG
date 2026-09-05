// MessageMetadataDebugProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    @MainActor enum MessageMetadataDebugProbe {
        private final class ProbeViewController: UIViewController {
            let forwardView = ForwardHeaderView()
            let replyView = ReplySnippetView()
            let textView = MessageTextContentView()
            private(set) var expansionCount = 0
            private(set) var navigationCount = 0

            private var replyPresentation: MessageReplyPresentation?

            override func viewDidLoad() {
                super.viewDidLoad()
                title = "Message References Probe"
                view.backgroundColor = .systemBackground

                let stack = UIStackView()
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.axis = .vertical
                stack.spacing = 18
                view.addSubview(stack)
                stack.addArrangedSubview(sectionLabel("Forward source"))
                stack.addArrangedSubview(forwardView)
                stack.addArrangedSubview(sectionLabel("Manual quote"))
                stack.addArrangedSubview(replyView)
                stack.addArrangedSubview(sectionLabel("Destination highlight"))
                stack.addArrangedSubview(textView)
                NSLayoutConstraint.activate([
                    stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
                    stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                ])
                forwardView.accessibilityIdentifier = "metadata-forward"
                replyView.accessibilityIdentifier = "metadata-reply"
                textView.accessibilityIdentifier = "metadata-highlight"
            }

            func configure(
                reply: MessageReplyPresentation,
                forward: MessageForwardPresentation,
                destinationText: FormattedText,
            ) {
                loadViewIfNeeded()
                replyPresentation = reply
                forwardView.configure(presentation: forward, client: nil) { [weak self] in
                    self?.navigationCount += 1
                }
                configureReply(expanded: false)
                textView.configure(
                    formattedText: destinationText,
                    client: td,
                    statusText: "03:45",
                    statusColor: .secondaryLabel,
                    maximumWidth: 320,
                )
                textView.highlightQuote(
                    position: reply.quoteHighlight?.position ?? 0,
                    length: reply.quoteHighlight?.length ?? 1,
                )
            }

            func resetReplyForInteraction() {
                expansionCount = 0
                navigationCount = 0
                configureReply(expanded: false)
            }

            private func configureReply(expanded: Bool) {
                guard let replyPresentation else { return }
                replyView
                    .configure(
                        presentation: replyPresentation,
                        expanded: expanded,
                        client: nil,
                    ) { [weak self] shouldExpand in
                    guard let self else { return }
                    if shouldExpand {
                        expansionCount += 1
                        configureReply(expanded: true)
                    } else {
                        navigationCount += 1
                    }
                }
            }

            private func sectionLabel(_ text: String) -> UILabel {
                let label = UILabel()
                label.text = text
                label.font = .preferredFont(forTextStyle: .caption1)
                label.textColor = .secondaryLabel
                return label
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-message-metadata") else { return }
            Task { @MainActor in
                await run(in: window)
            }
        }

        private static func run(in window: UIWindow) async {
            let quoteText = FormattedText(
                entities: [TextEntity(length: 6, offset: 0, type: .textEntityTypeBold)],
                text: "Quoted line one\nQuoted line two\nQuoted line three\nQuoted line four\nQuoted line five\nQuoted line six\nQuoted line seven",
            )
            let reply = MessageReplyTo.messageReplyToMessage(MessageReplyToMessage(
                chatId: 777,
                checklistTaskId: 0,
                content: .messageText(MessageText(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: "Inline fallback body"),
                )),
                messageId: 0,
                origin: .messageOriginHiddenUser(MessageOriginHiddenUser(senderName: "Inline Author")),
                originSendDate: 1,
                pollOptionId: "",
                quote: TextQuote(isManual: true, position: 7, text: quoteText),
            ))
            let parent = makeMessage(id: 700, chatID: 1, content: .messageText(MessageText(
                linkPreview: nil,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: "Parent"),
            )), replyTo: reply)
            let forwardInfo = MessageForwardInfo(
                date: 1,
                origin: .messageOriginHiddenUser(MessageOriginHiddenUser(senderName: "Original Author")),
                publicServiceAnnouncementType: "",
                source: ForwardSource(
                    chatId: 888,
                    date: 2,
                    isOutgoing: false,
                    messageId: 999,
                    senderId: nil,
                    senderName: "Last Forward Source",
                ),
            )
            let resolver = MessageMetadataResolver(client: TDLib.shared.activeClient)
            guard let replyPresentation = await resolver.replyPresentation(for: parent),
                  let forwardPresentation = await resolver.forwardPresentation(for: forwardInfo)
            else {
                write("Message metadata probe failed: resolver")
                assertionFailure("Message metadata resolver probe failed")
                return
            }
            let unknownChatParent = makeMessage(
                id: 701,
                chatID: 1,
                content: .messageText(MessageText(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: "Unknown parent"),
                )),
                replyTo: .messageReplyToMessage(MessageReplyToMessage(
                    chatId: 0,
                    checklistTaskId: 0,
                    content: .messageText(MessageText(
                        linkPreview: nil,
                        linkPreviewOptions: nil,
                        text: FormattedText(entities: [], text: "Unknown inline"),
                    )),
                    messageId: 0,
                    origin: .messageOriginHiddenUser(MessageOriginHiddenUser(senderName: "Unknown Author")),
                    originSendDate: 1,
                    pollOptionId: "",
                    quote: nil,
                )),
            )
            let unknownChatPresentation = await resolver.replyPresentation(for: unknownChatParent)

            let controller = ProbeViewController()
            controller.configure(
                reply: replyPresentation,
                forward: forwardPresentation,
                destinationText: quoteText,
            )
            let navigation = TelegramNavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            topPresenter(from: window.rootViewController)?.present(navigation, animated: false)
            controller.view.layoutIfNeeded()

            controller.replyView.simulateTapForProbe()
            controller.view.layoutIfNeeded()
            let expandedLineLimit = controller.replyView.debugBodyLineLimit
            controller.replyView.simulateTapForProbe()
            let expansionProof = controller.expansionCount == 1
                && controller.navigationCount == 1
                && expandedLineLimit == 50
            controller.resetReplyForInteraction()
            controller.view.layoutIfNeeded()

            var forwardNavigated = false
            let testForwardView = ForwardHeaderView()
            testForwardView.configure(presentation: forwardPresentation, client: nil) { forwardNavigated = true }
            testForwardView.simulateTapForProbe()

            let originalExternal = InputMessageReplyTo
                .inputMessageReplyToExternalMessage(InputMessageReplyToExternalMessage(
                    chatId: 42,
                    checklistTaskId: 5,
                    messageId: 43,
                    pollOptionId: "option",
                    quote: InputTextQuote(position: 3, text: FormattedText(entities: [], text: "kept")),
                ))
            let externalTarget = makeMessage(
                id: 43,
                chatID: 42,
                content: .messageText(MessageText(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: "External"),
                )),
                replyTo: nil,
            )
            let preservedInput = MessageReplyInputBuilder.make(
                currentChatID: 1,
                target: externalTarget,
                override: originalExternal,
                quote: nil,
            )
            let authoredExternal = MessageReplyInputBuilder.make(
                currentChatID: 1,
                target: externalTarget,
                override: nil,
                quote: nil,
            )
            let unicodeQuote = MessageQuoteBuilder.make(
                from: FormattedText(
                    entities: [
                        TextEntity(length: 1, offset: 0, type: .textEntityTypeBold),
                        TextEntity(length: 1, offset: 3, type: .textEntityTypeUrl),
                    ],
                    text: "A😀BC",
                ),
                maximumLength: 2,
            )

            let inlineFallback = replyPresentation.availability == .inline
                && replyPresentation.title.contains("Inline Author")
                && replyPresentation.body == quoteText
                && replyPresentation.targetMessageID == nil
                && replyPresentation.quoteHighlight == MessageQuoteHighlight(
                    length: quoteText.text.utf16.count,
                    position: 7,
                )
            let unknownChatScope = unknownChatPresentation?.targetChatID == nil
                && unknownChatPresentation?.navigationTarget == nil
            let sourcePriority = forwardPresentation.sourceTitle == "Last Forward Source • Original Author"
                && forwardPresentation.navigationTarget == .message(chatID: 888, messageID: 999, quote: nil)
            let inputProof = preservedInput == originalExternal
                && authoredExternal == .inputMessageReplyToExternalMessage(InputMessageReplyToExternalMessage(
                    chatId: 42,
                    checklistTaskId: 0,
                    messageId: 43,
                    pollOptionId: "",
                    quote: nil,
                ))
            let unicodeProof = unicodeQuote?.text.text == "A"
                && unicodeQuote?.text.entities.count == 1
                && unicodeQuote?.text.entities.first?.type == .textEntityTypeBold
            let highlightProof = controller.textView.debugQuoteHighlightCount > 0
            let proof = "Message metadata probe: inline=\(inlineFallback), unknown-chat=\(unknownChatScope), "
                + "source-priority=\(sourcePriority), "
                + "expand-then-navigate=\(expansionProof), forward-navigate=\(forwardNavigated), "
                + "external-input=\(inputProof), utf16-quote=\(unicodeProof), highlight=\(highlightProof), "
                + "uikit=true, swiftui=false"
            write(proof)
            if !inlineFallback || !unknownChatScope || !sourcePriority || !expansionProof || !forwardNavigated ||
                !inputProof
                || !unicodeProof || !highlightProof
            {
                assertionFailure(proof)
            }
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

        private static func makeMessage(
            id: Int64,
            chatID: Int64,
            content: MessageContent,
            replyTo: MessageReplyTo?,
        ) -> Message {
            Message(
                authorSignature: "",
                autoDeleteIn: 0,
                canBeSaved: true,
                chatId: chatID,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                content: content,
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
                replyTo: replyTo,
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
                topicId: nil,
                unreadReactions: [],
                viaBotUserId: 0,

            ephemeralContent: nil,
                chatInstance: 0,
            )
        }

        private static func write(_ proof: String) {
            log(proof)
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            try? proof.write(
                to: documents.appendingPathComponent("message-metadata-probe.txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }
#endif
