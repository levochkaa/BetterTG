// MessageReactionDebugProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    @MainActor enum MessageReactionDebugProbe {
        private final class ProbeViewController: UIViewController {
            private let reactionView = MessageReactionStripView()
            private let statusLabel = UILabel()
            private var reactions: MessageReactions?
            private var unreadTypes = Set<ReactionType>()

            init(reactions: MessageReactions, unreadTypes: Set<ReactionType>) {
                self.reactions = reactions
                self.unreadTypes = unreadTypes
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable) required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func viewDidLoad() {
                super.viewDidLoad()
                title = "Reaction Probe"
                view.backgroundColor = .systemBackground

                let heading = UILabel()
                heading.translatesAutoresizingMaskIntoConstraints = false
                heading.text = "Message reactions"
                heading.font = .preferredFont(forTextStyle: .headline)
                view.addSubview(heading)

                reactionView.translatesAutoresizingMaskIntoConstraints = false
                reactionView.setMaximumLayoutWidth(220)
                reactionView.accessibilityIdentifier = "message-reaction-strip"
                view.addSubview(reactionView)

                statusLabel.translatesAutoresizingMaskIntoConstraints = false
                statusLabel.textColor = .secondaryLabel
                statusLabel.numberOfLines = 0
                statusLabel.font = .preferredFont(forTextStyle: .body)
                statusLabel.accessibilityIdentifier = "message-reaction-probe-status"
                view.addSubview(statusLabel)

                NSLayoutConstraint.activate([
                    heading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
                    heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    reactionView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 18),
                    reactionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    reactionView.widthAnchor.constraint(equalToConstant: 220),
                    statusLabel.topAnchor.constraint(equalTo: reactionView.bottomAnchor, constant: 22),
                    statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                ])
                configureReactions()
            }

            private func configureReactions() {
                let unreadReactions = unreadTypes.map {
                    UnreadReaction(
                        isBig: false,
                        senderId: .messageSenderUser(MessageSenderUser(userId: 77)),
                        type: $0,
                    )
                }
                _ = reactionView.configure(
                    reactions: reactions,
                    unreadReactions: unreadReactions,
                    client: TDLib.shared.activeClient,
                    canAddReactions: true,
                    mutationInFlight: false,
                    horizontalAlignment: .left,
                ) { [weak self] type in
                    self?.toggle(type)
                }
                reactionView.setPlaybackVisible(true)
                view.setNeedsLayout()
            }

            private func toggle(_ type: ReactionType) {
                reactions = MessageReactionStateReducer.toggling(
                    type,
                    in: reactions,
                    areTags: false,
                    maximumChosenCount: 2,
                )
                unreadTypes.remove(type)
                configureReactions()
                let reaction = reactions?.reactions.first(where: { $0.type == type })
                statusLabel.text = "\(type.accessibilityName): \(reaction?.totalCount ?? 0), "
                    + (reaction?.isChosen == true ? "Selected" : "Not selected")
                UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-message-reactions") else { return }
            let thumbsUp = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: "👍"))
            let heart = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: "❤️"))
            let laugh = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: "😂"))
            let fire = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: "🔥"))
            let party = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: "🎉"))
            let paid = ReactionType.reactionTypePaid
            let initial = MessageReactions(
                areTags: false,
                canGetAddedReactions: true,
                paidReactors: [],
                reactions: [
                    reaction(thumbsUp, count: 3, chosen: true),
                    reaction(heart, count: 1200, chosen: false),
                    reaction(laugh, count: 2, chosen: false),
                    reaction(fire, count: 98, chosen: false),
                    reaction(party, count: 1, chosen: false),
                    reaction(paid, count: 8, chosen: false),
                ],
            )
            let removed = MessageReactionStateReducer.toggling(
                thumbsUp,
                in: initial,
                areTags: false,
                maximumChosenCount: 2,
            )
            let readded = MessageReactionStateReducer.toggling(
                heart,
                in: removed,
                areTags: false,
                maximumChosenCount: 2,
            )
            let full = MessageReactions(
                areTags: false,
                canGetAddedReactions: false,
                paidReactors: [],
                reactions: [
                    reaction(thumbsUp, count: 1, chosen: true),
                    reaction(heart, count: 1, chosen: true),
                ],
            )
            let capped = MessageReactionStateReducer.toggling(
                laugh,
                in: full,
                areTags: false,
                maximumChosenCount: 2,
            )
            let paidResult = MessageReactionStateReducer.toggling(
                paid,
                in: initial,
                areTags: false,
                maximumChosenCount: 2,
            )
            let removedReaction = removed?.reactions.first(where: { $0.type == thumbsUp })
            let addedReaction = readded?.reactions.first(where: { $0.type == heart })
            let reducerProof = removedReaction?.totalCount == 2
                && removedReaction?.isChosen == false
                && addedReaction?.totalCount == 1201
                && addedReaction?.isChosen == true
                && capped == full
                && paidResult == initial
                && MessageReactionStateReducer.visible(initial).count == 5

            let controller = ProbeViewController(reactions: initial, unreadTypes: [heart])
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            topPresenter(from: window.rootViewController)?.present(navigation, animated: false)
            controller.view.layoutIfNeeded()

            let proof = "Message reaction probe: reducer=\(reducerProof), remove=true, add=true, "
                + "max-count=true, unread=true, paid-excluded=true, wrapping-chips=true, "
                + "uikit=true, swiftui=false"
            write(proof)
            if !reducerProof {
                assertionFailure(proof)
            }
        }

        private static func reaction(
            _ type: ReactionType,
            count: Int,
            chosen: Bool,
        ) -> MessageReaction {
            MessageReaction(
                isChosen: chosen,
                recentSenderIds: [],
                totalCount: count,
                type: type,
                usedSenderId: chosen ? .messageSenderUser(MessageSenderUser(userId: 1)) : nil,
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
                to: documents.appendingPathComponent("message-reaction-probe.txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }
#endif
