// StoryMessageContentView.swift

import TDLibKit
import UIKit

// MARK: - StoryPreviewCache

/// Stories that shared-story and mention messages show, loaded once per client with `getStory`. A story TDLib can't
/// return has expired or isn't visible to the account.
@MainActor enum StoryPreviewCache {
    enum State {
        case available(Story)
        case unavailable
    }

    private struct Key: Hashable {
        let clientID: Int32
        let posterChatID: Int64
        let storyID: Int
    }

    private static let capacity = 256
    private static var states = [Key: State]()
    private static var waiters = [Key: [(State) -> Void]]()

    /// The story's state once TDLib answered on this client; until then `completion` waits for it.
    static func state(
        posterChatID: Int64,
        storyID: Int,
        client: TDLibClient,
        completion: @escaping (State) -> Void,
    ) -> State? {
        guard posterChatID != 0, storyID != 0 else { return .unavailable }
        let key = Key(clientID: client.id, posterChatID: posterChatID, storyID: storyID)
        if let state = states[key] { return state }
        let isFirstWaiter = waiters[key] == nil
        waiters[key, default: []].append(completion)
        guard isFirstWaiter else { return nil }
        Task {
            let state: State
            let isFinal: Bool
            do {
                let story = try await client.getStory(
                    onlyLocal: false,
                    storyId: storyID,
                    storyPosterChatId: posterChatID,
                )
                state = .available(story)
                isFinal = true
            } catch {
                state = .unavailable
                // A missing or hidden story stays so; a flood wait or a server error is asked again next time.
                let code = (error as? TDLibError)?.code ?? 0
                isFinal = code == 400 || code == 403 || code == 404
            }
            let completions = waiters.removeValue(forKey: key) ?? []
            guard TDLib.shared.activeClient.id == client.id else { return }
            if isFinal {
                if states.count >= capacity { states.removeAll() }
                states[key] = state
            }
            completions.forEach { $0(state) }
        }
        return nil
    }
}

// MARK: - StoryMessageContentView

/// Telegram's shared story and story mention (TelegramMediaStory). A shared story reads as a forwarded message with
/// the story's photo or video cover (ChatMessageForwardInfoNode's story header over ChatMessageMediaBubbleContentNode)
/// and becomes "Expired story from" once TDLib can't return it. A mention is a centered card with the story in a ring
/// and Telegram's View Story button (ChatMessageStoryMentionContentNode), or Telegram's expired-mention text. Tapping
/// the cover, the card or the button opens the story in the story viewer.
final class StoryMessageContentView: UIView, MessageSupplementView {
    private static let defaultStoryPixelSize = CGSize(width: 720, height: 1280)

    private let content: MessageContentPresentation.SharedStoryContent
    private let chatID: Int64
    private let client: TDLibClient
    private let onAction: (MessageContentAction) -> Void
    private let stack = UIStackView()
    private let headerView = ForwardHeaderView()
    private let mediaView = TDImageLoadingView()
    private let playIconView = UIImageView()
    private let captionLabel = UILabel()
    private let mentionTextLabel = UILabel()
    private let ringView = UIView()
    private let viewStoryButton = UIButton(type: .system)
    private var mediaWidth: NSLayoutConstraint?
    private var mediaHeight: NSLayoutConstraint?
    /// A mention's card and, once the story expired, its service row (ChatMessageActionBubbleContentNode).
    private var mentionCardConstraints = [NSLayoutConstraint]()
    private var expiredMentionConstraints = [NSLayoutConstraint]()
    private var state: StoryPreviewCache.State?
    private var posterChat: Chat?
    private var peerName: String?
    private var hasLoadedMedia = false
    private var isActive = true

    init(
        content: MessageContentPresentation.SharedStoryContent,
        chatID: Int64,
        client: TDLibClient,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.content = content
        self.chatID = chatID
        self.client = client
        self.onAction = onAction
        super.init(frame: .zero)
        if content.viaMention {
            configureMention()
        } else {
            configureSharedStory()
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openStory(_:))))
        resolve()
        render()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        guard case .available = state else { return false }
        openStory(nil)
        return true
    }

    private static func pixelSize(of story: Story) -> CGSize {
        switch story.content {
        case .storyContentPhoto(let photo):
            let largest = photo.photo.sizes.max { $0.width * $0.height < $1.width * $1.height }
            guard let largest, largest.width > 0, largest.height > 0 else { return defaultStoryPixelSize }
            return CGSize(width: largest.width, height: largest.height)
        case .storyContentVideo(let video):
            guard video.video.width > 0, video.video.height > 0 else { return defaultStoryPixelSize }
            return CGSize(width: video.video.width, height: video.video.height)
        case .storyContentLive,
             .storyContentUnsupported:
            return defaultStoryPixelSize
        }
    }

    private static func initials(_ title: String) -> String {
        let initials = title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return initials.isEmpty ? "•" : initials
    }

    func prepareForReuse() {
        isActive = false
        mediaView.cancel()
        headerView.prepareForReuse()
    }

    /// The cover of a shared story, or anywhere on a mention's card, opens the story while TDLib can return it.
    @objc private func openStory(_ gesture: UITapGestureRecognizer?) {
        guard isActive, case .available = state else { return }
        if let gesture, !content.viaMention,
           !mediaView.bounds.contains(gesture.location(in: mediaView)) { return }
        onAction(.openStory(
            posterChatID: content.posterChatID,
            storyID: content.storyID,
            sourceView: mediaView,
            sourceIsRound: content.viaMention,
        ))
    }

    @objc private func viewStoryPressed() {
        openStory(nil)
    }

    // MARK: Layout

    private func configureSharedStory() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        addSubview(stack)

        headerView.isUserInteractionEnabled = false
        stack.addArrangedSubview(headerView)

        configureMediaView(cornerRadius: 10)
        let size = displaySize(pixelSize: Self.defaultStoryPixelSize)
        let width = mediaView.widthAnchor.constraint(equalToConstant: size.width)
        let height = mediaView.heightAnchor.constraint(equalToConstant: size.height)
        mediaWidth = width
        mediaHeight = height
        stack.addArrangedSubview(mediaView)

        captionLabel.numberOfLines = 0
        captionLabel.isHidden = true
        stack.addArrangedSubview(captionLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            headerView.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor),
            captionLabel.widthAnchor.constraint(lessThanOrEqualTo: mediaView.widthAnchor),
            width,
            height,
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    /// ChatMessageStoryMentionContentNode: a 180-point card, the story cut into a circle inside its ring, the
    /// mention text and the View Story pill under it.
    private func configureMention() {
        layer.cornerCurve = .continuous

        ringView.translatesAutoresizingMaskIntoConstraints = false
        ringView.layer.cornerRadius = 50
        ringView.layer.borderWidth = 2.5
        ringView.layer.borderColor = UIColor.systemBlue.cgColor
        addSubview(ringView)

        configureMediaView(cornerRadius: 44)
        addSubview(mediaView)

        mentionTextLabel.translatesAutoresizingMaskIntoConstraints = false
        mentionTextLabel.numberOfLines = 0
        mentionTextLabel.textAlignment = .center
        addSubview(mentionTextLabel)

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.attributedTitle = AttributedString(
            L10n.telegram("Chat.StoryMentionAction"),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]),
        )
        buttonConfiguration.baseForegroundColor = .label
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 19, bottom: 8, trailing: 19)
        buttonConfiguration.background.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        buttonConfiguration.cornerStyle = .capsule
        viewStoryButton.configuration = buttonConfiguration
        viewStoryButton.translatesAutoresizingMaskIntoConstraints = false
        viewStoryButton.addTarget(self, action: #selector(viewStoryPressed), for: .touchUpInside)
        addSubview(viewStoryButton)

        mentionCardConstraints = [
            mentionTextLabel.topAnchor.constraint(equalTo: ringView.bottomAnchor, constant: 13),
            mentionTextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mentionTextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            viewStoryButton.topAnchor.constraint(equalTo: mentionTextLabel.bottomAnchor, constant: 11),
            viewStoryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            viewStoryButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            widthAnchor.constraint(equalToConstant: 180),
        ]
        expiredMentionConstraints = [
            mentionTextLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            mentionTextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            mentionTextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            mentionTextLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ]
        NSLayoutConstraint.activate([
            ringView.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            ringView.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringView.widthAnchor.constraint(equalToConstant: 100),
            ringView.heightAnchor.constraint(equalToConstant: 100),
            mediaView.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
            mediaView.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),
            mediaView.widthAnchor.constraint(equalToConstant: 88),
            mediaView.heightAnchor.constraint(equalToConstant: 88),
        ])
    }

    private func configureMediaView(cornerRadius: CGFloat) {
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = cornerRadius
        mediaView.layer.cornerCurve = .continuous
        mediaView.backgroundColor = .tertiarySystemFill

        playIconView.translatesAutoresizingMaskIntoConstraints = false
        playIconView.image = UIImage(
            systemName: "play.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 34),
        )
        playIconView.tintColor = UIColor.white.withAlphaComponent(0.9)
        playIconView.isHidden = true
        mediaView.addSubview(playIconView)
        NSLayoutConstraint.activate([
            playIconView.centerXAnchor.constraint(equalTo: mediaView.centerXAnchor),
            playIconView.centerYAnchor.constraint(equalTo: mediaView.centerYAnchor),
        ])
    }

    // MARK: Loading

    /// The story from TDLib; for a shared story its poster, and for a mention the chat's other side, whose name the
    /// mention text carries.
    private func resolve() {
        state = StoryPreviewCache.state(
            posterChatID: content.posterChatID,
            storyID: content.storyID,
            client: client,
        ) { [weak self] state in
            guard let self, isActive else { return }
            self.state = state
            render(notifyingLayout: true)
        }
        if content.viaMention {
            guard chatID != 0 else { return }
            peerName = MessagePeerNames.compactName(ofChat: chatID, client: client) { [weak self] name in
                guard let self, isActive else { return }
                peerName = name
                render(notifyingLayout: true)
            }
        } else if content.posterChatID != 0 {
            posterChat = MessagePeerNames.chat(content.posterChatID, client: client) { [weak self] chat in
                guard let self, isActive else { return }
                posterChat = chat
                render(notifyingLayout: true)
            }
        }
    }

    // MARK: Rendering

    private func render(notifyingLayout: Bool = false) {
        let previousSize = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if content.viaMention {
            renderMention()
        } else {
            renderSharedStory()
        }
        guard notifyingLayout else { return }
        if systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) != previousSize {
            onAction(.richContentLayoutChanged)
        }
    }

    private func renderSharedStory() {
        let story: Story? =
            if case .available(let story) = state {
                story
            } else {
                nil
            }
        let isExpired =
            if case .unavailable = state {
                true
            } else {
                false
            }
        let posterTitle = posterChat?.title ?? ""
        headerView.configure(
            presentation: MessageForwardPresentation(
                avatar: posterChat.map { chat in
                    MessageMetadataAvatar(
                        file: chat.photo?.small,
                        initials: Self.initials(chat.title),
                        minithumbnailData: chat.photo?.minithumbnail?.data,
                    )
                },
                headline: L10n.telegram(isExpired
                    ? "Chat.MessageForwardInfo.ExpiredStoryHeader"
                    : "Chat.MessageForwardInfo.StoryHeader"),
                navigationTarget: nil,
                originalSourceTitle: posterTitle,
                publicServiceAnnouncementType: nil,
                referencedChatIDs: [],
                referencedUserIDs: [],
                // A blank title keeps the header's height until the poster's name arrives.
                sourceTitle: posterTitle.isEmpty ? " " : posterTitle,
                targetChatID: nil,
                targetMessageID: nil,
            ),
            client: client,
            onTap: nil,
        )

        mediaView.isHidden = isExpired
        if let story {
            let size = displaySize(pixelSize: Self.pixelSize(of: story))
            mediaWidth?.constant = size.width
            mediaHeight?.constant = size.height
            loadMediaOnce(of: story)
            let caption = story.caption
            captionLabel.isHidden = caption.text.isEmpty
            captionLabel.attributedText = caption.text.isEmpty
                ? nil
                : NSAttributedString(getAttributedString(from: caption))
        } else {
            captionLabel.isHidden = true
        }
        isAccessibilityElement = true
        accessibilityLabel = [
            L10n.telegram(isExpired
                ? "Chat.MessageForwardInfo.ExpiredStoryHeader"
                : "Chat.MessageForwardInfo.StoryHeader"),
            posterTitle,
            story?.caption.text ?? "",
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        accessibilityTraits = story == nil ? .staticText : [.image, .button]
    }

    private func renderMention() {
        let isExpired =
            if case .unavailable = state {
                true
            } else {
                false
            }
        let name = peerName ?? ""
        let text: String
        let font: UIFont
        if isExpired {
            // Telegram turns an expired mention into a service message (plainServiceMessageString).
            text = content.isOutgoing
                ? L10n.telegram("Conversation.StoryExpiredMentionTextOutgoing", name)
                : L10n.telegram("Conversation.StoryExpiredMentionTextIncoming")
            font = .preferredFont(forTextStyle: .caption1).withSemiboldWeight
        } else {
            text = content.isOutgoing
                ? L10n.telegram("Conversation.StoryMentionTextOutgoing", name)
                : L10n.telegram("Conversation.StoryMentionTextIncoming", name)
            font = .systemFont(ofSize: 13)
        }
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: isExpired ? UIColor.secondaryLabel : UIColor.label],
        )
        if !name.isEmpty {
            let range = (text as NSString).range(of: name)
            if range.location != NSNotFound {
                attributed.addAttribute(
                    .font,
                    value: UIFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                    range: range,
                )
            }
        }
        mentionTextLabel.attributedText = attributed

        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        layer.cornerRadius = isExpired ? 11 : 15
        ringView.isHidden = isExpired
        mediaView.isHidden = isExpired
        viewStoryButton.isHidden = isExpired
        if isExpired {
            NSLayoutConstraint.deactivate(mentionCardConstraints)
            NSLayoutConstraint.activate(expiredMentionConstraints)
            mediaView.cancel()
        } else {
            NSLayoutConstraint.deactivate(expiredMentionConstraints)
            NSLayoutConstraint.activate(mentionCardConstraints)
        }
        if case .available(let story) = state { loadMediaOnce(of: story) }
        isAccessibilityElement = true
        accessibilityLabel = text.replacing("\n", with: " ")
        accessibilityTraits =
            if case .available = state {
                .button
            } else {
                .staticText
            }
    }

    /// Names arriving later render the view again; the cover loads once.
    private func loadMediaOnce(of story: Story) {
        guard !hasLoadedMedia else { return }
        hasLoadedMedia = true
        switch story.content {
        case .storyContentPhoto(let photo):
            playIconView.isHidden = true
            mediaView.load(photo: photo.photo, preferredSize: .xBox, maximumPixelSize: 720, client: client)
        case .storyContentVideo(let video):
            playIconView.isHidden = content.viaMention
            if let thumbnail = video.video.thumbnail {
                mediaView.load(
                    file: thumbnail.file,
                    placeholderData: video.video.minithumbnail?.data,
                    maximumPixelSize: 720,
                    client: client,
                )
            } else {
                mediaView.loadPlaceholder(data: video.video.minithumbnail?.data, client: client)
            }
        case .storyContentLive,
             .storyContentUnsupported:
            playIconView.isHidden = true
            mediaView.cancel()
        }
    }

    /// A story's media in a bubble, sized as Telegram sizes a photo (720×1280 until TDLib returns the story).
    private func displaySize(pixelSize: CGSize) -> CGSize {
        TelegramMediaLayout.displaySize(pixelSize: pixelSize, kind: .image, maximumWidth: Utils.maxMessageContentWidth)
    }
}

private extension UIFont {
    var withSemiboldWeight: UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: .semibold)
    }
}
