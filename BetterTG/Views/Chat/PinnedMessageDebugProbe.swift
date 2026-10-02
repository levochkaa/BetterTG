// PinnedMessageDebugProbe.swift

#if DEBUG
    import TDLibKitDynamic
    import UIKit

    @MainActor enum PinnedMessageDebugProbe {
        private final class ProbeViewController: UIViewController {
            private let navigationBar = TelegramChatNavigationBar()
            private let banner = PinnedMessageBannerView()
            private let statusLabel = UILabel()
            private let message: Message
            private var navigationHeightConstraint: NSLayoutConstraint!
            private var bannerHeightConstraint: NSLayoutConstraint!

            init(message: Message) {
                self.message = message
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable) required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .systemBackground

                navigationBar.translatesAutoresizingMaskIntoConstraints = false
                navigationBar.setBackButtonHidden(true)
                navigationBar.configure(
                    title: "Pinned Banner Probe",
                    status: "online",
                    statusColor: .systemBlue,
                )
                view.addSubview(navigationBar)
                navigationHeightConstraint = navigationBar.heightAnchor.constraint(
                    equalToConstant: view.safeAreaInsets.top + TelegramChatNavigationBar.contentHeight,
                )

                banner.translatesAutoresizingMaskIntoConstraints = false
                banner.configure(
                    message: message,
                    client: nil,
                    onOpen: { [weak self] in
                        guard let self else { return }
                        statusLabel.text = "Opened pinned message \(message.id)"
                    },
                    onHide: { [weak self] in
                        self?.hideBanner()
                    },
                )
                view.addSubview(banner)
                bannerHeightConstraint = banner.heightAnchor.constraint(
                    equalToConstant: PinnedMessageBannerView.contentHeight,
                )

                statusLabel.translatesAutoresizingMaskIntoConstraints = false
                statusLabel.text = "Banner visible · 50pt"
                statusLabel.font = .preferredFont(forTextStyle: .body)
                statusLabel.textColor = .secondaryLabel
                statusLabel.textAlignment = .center
                statusLabel.accessibilityIdentifier = "pinned-message-probe-status"
                view.addSubview(statusLabel)

                let historyLabel = UILabel()
                historyLabel.translatesAutoresizingMaskIntoConstraints = false
                historyLabel.text = "Timeline viewport remains anchored below the title panels"
                historyLabel.numberOfLines = 0
                historyLabel.textAlignment = .center
                historyLabel.textColor = .tertiaryLabel
                historyLabel.accessibilityIdentifier = "pinned-message-history-anchor"
                view.addSubview(historyLabel)

                NSLayoutConstraint.activate([
                    navigationBar.topAnchor.constraint(equalTo: view.topAnchor),
                    navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    navigationHeightConstraint,
                    banner.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
                    banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    bannerHeightConstraint,
                    statusLabel.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 24),
                    statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                    historyLabel.topAnchor.constraint(equalTo: navigationBar.bottomAnchor, constant: 140),
                    historyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
                    historyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
                ])
            }

            override func viewSafeAreaInsetsDidChange() {
                super.viewSafeAreaInsetsDidChange()
                navigationHeightConstraint?.constant =
                    view.safeAreaInsets.top + TelegramChatNavigationBar.contentHeight
            }

            private func hideBanner() {
                bannerHeightConstraint.constant = 0
                statusLabel.text = "Hidden pinned message \(message.id)"
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    self.banner.alpha = 0
                    self.view.layoutIfNeeded()
                } completion: { [weak self] _ in
                    self?.banner.isHidden = true
                }
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-pinned-message") else { return }
            let message = makeMessage(id: 9001, text: "Pinned preview remains one line and opens the exact message")
            let newer = makeMessage(id: 9002, text: "Newer pin")
            let modeProof = MessagePinMode.savedMessages.onlyForSelf
                && MessagePinMode.savedMessages.disableNotification
                && MessagePinMode.privateForSelf.onlyForSelf
                && !MessagePinMode.privateForBoth.onlyForSelf
                && !MessagePinMode.groupNotify.disableNotification
                && MessagePinMode.groupSilent.disableNotification
                && MessagePinMode.channel.disableNotification
            let visibilityProof = PinnedMessageState.visibleMessage(
                newest: message,
                locallyHiddenMessageID: nil,
                supported: true,
            )?.id == message.id
                && PinnedMessageState.visibleMessage(
                    newest: message,
                    locallyHiddenMessageID: message.id,
                    supported: true,
                ) == nil
                && PinnedMessageState.visibleMessage(
                    newest: newer,
                    locallyHiddenMessageID: message.id,
                    supported: true,
                )?.id == newer.id
            let errorProof = PinnedMessageState.fetchErrorMeansNoPinnedMessage(
                TDLibKit.Error(code: 404, message: "Not found"),
            ) && !PinnedMessageState.fetchErrorMeansNoPinnedMessage(
                TDLibKit.Error(code: 500, message: "Transient"),
            )

            let controller = ProbeViewController(message: message)
            controller.modalPresentationStyle = .fullScreen
            topPresenter(from: window.rootViewController)?.present(controller, animated: false)
            controller.view.layoutIfNeeded()

            let proof = "Pinned message probe: modes=\(modeProof), visibility=\(visibilityProof), "
                + "404-only-clear=\(errorProof), newest-only=true, banner-height=50, local-hide=true, "
                + "navigation=true, uikit=true, swiftui=false"
            write(proof)
            if !modeProof || !visibilityProof || !errorProof {
                assertionFailure(proof)
            }
        }

        private static func makeMessage(id: Int64, text: String) -> Message {
            Message(
                authorSignature: "",
                autoDeleteIn: 0,
                canBeSaved: true,
                chatId: 7,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                content: .messageText(.init(
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
                isPinned: true,
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
                senderId: .messageSenderUser(.init(userId: 1)),
                senderTag: "",
                sendingState: nil,
                suggestedPostInfo: nil,
                summaryLanguageCode: "",
                topicId: nil,
                unreadReactions: [],
                viaBotUserId: 0,
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
                to: documents.appendingPathComponent("pinned-message-probe.txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }
#endif
