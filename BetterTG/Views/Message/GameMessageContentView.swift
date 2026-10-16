// GameMessageContentView.swift

import TDLibKit
import UIKit

/// Telegram's game bubble (ChatMessageGameBubbleContentNode over ChatMessageAttachedContentNode with
/// `preferMediaBeforeText`): the game's media first, then its title and its text, or its description while the bot
/// set no text. Tapping the media plays the game as the message's Play button does: a game callback query whose
/// answer URL opens the game (requestMessageActionCallback with isGame). An animated game plays its animation in place,
/// muted, as ChatMessageInteractiveMediaNode plays a GIF, under Telegram's GAME badge.
final class GameMessageContentView: UIView, MessageSupplementView {
    private struct Media {
        let file: File?
        let placeholder: Data?
        let size: CGSize
    }

    private let messageID: Int64
    private let onAction: (MessageContentAction) -> Void
    private let mediaView = TDImageLoadingView()
    private var animationView: ReusableMediaView?
    private let bodyTextView = MessageTextContentView()

    init(game: Game, messageID: Int64, client: TDLibClient, onAction: @escaping (MessageContentAction) -> Void) {
        self.messageID = messageID
        self.onAction = onAction
        super.init(frame: .zero)
        layer.cornerRadius = 5
        clipsToBounds = true
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)

        let accent = UIView()
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.backgroundColor = .systemBlue
        addSubview(accent)

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 4
        addSubview(content)

        if let media = Self.media(of: game) {
            mediaView.contentMode = .scaleAspectFill
            mediaView.clipsToBounds = true
            mediaView.layer.cornerRadius = 4
            mediaView.backgroundColor = .tertiarySystemFill
            mediaView.isUserInteractionEnabled = true
            if let animation = game.animation {
                installAnimation(animation, client: client)
            } else if let file = media.file {
                mediaView.load(file: file, placeholderData: media.placeholder, maximumPixelSize: 720, client: client)
            }
            mediaView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(play)))
            content.addArrangedSubview(mediaView)
            content.setCustomSpacing(6, after: mediaView)
            let aspect = min(1.3, max(0.5, media.size.height / max(1, media.size.width)))
            mediaView.heightAnchor.constraint(equalTo: mediaView.widthAnchor, multiplier: aspect).isActive = true
            if game.animation != nil { addBadge(to: mediaView) }
        }

        let title = game.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            titleLabel.textColor = .systemBlue
            titleLabel.numberOfLines = 0
            content.addArrangedSubview(titleLabel)
        }

        let body = game.text.text.isEmpty ? FormattedText(entities: [], text: game.description) : game.text
        if !body.text.isEmpty {
            bodyTextView.configure(
                formattedText: body,
                client: client,
                statusText: "",
                statusColor: .secondaryLabel,
                maximumWidth: Utils.maxMessageContentWidth - 24,
            )
            content.addArrangedSubview(bodyTextView)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            accent.topAnchor.constraint(equalTo: topAnchor),
            accent.bottomAnchor.constraint(equalTo: bottomAnchor),
            accent.leadingAnchor.constraint(equalTo: leadingAnchor),
            accent.widthAnchor.constraint(equalToConstant: 3),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        if content.arrangedSubviews.isEmpty {
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        }

        isAccessibilityElement = true
        accessibilityLabel = [L10n.telegram("Message.Game"), title, body.text]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// ChatMessageGameBubbleContentNode.accessibilityActivate plays the game.
    override func accessibilityActivate() -> Bool {
        play()
        return true
    }

    /// ChatMessageGameBubbleContentNode's order: the game's animation, else its photo.
    private static func media(of game: Game) -> Media? {
        if let animation = game.animation {
            return Media(
                file: animation.thumbnail?.file,
                placeholder: animation.minithumbnail?.data,
                size: CGSize(width: animation.width, height: animation.height),
            )
        }
        if let size = game.photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            return Media(
                file: size.photo,
                placeholder: game.photo.minithumbnail?.data,
                size: CGSize(width: size.width, height: size.height),
            )
        }
        return nil
    }

    func prepareForReuse() {
        mediaView.cancel()
        animationView?.prepareForReuse()
        bodyTextView.prepareForReuse()
    }

    func setPlaybackVisible(_ visible: Bool) {
        animationView?.setPlaybackVisible(visible)
        bodyTextView.setCustomEmojiPlaybackVisible(visible)
    }

    /// The animation fills the media frame and leaves taps to it, so a tap still plays the game. MP4 loops through
    /// AVFoundation; other containers go through the FFmpeg decoder, as animation messages do.
    private func installAnimation(_ animation: Animation, client: TDLibClient) {
        let view: ReusableMediaView
        if telegramAnimationUsesFFmpeg(animation) {
            let ffmpegView = FFmpegAnimatedVideoView()
            ffmpegView.configure(
                file: animation.animation,
                client: client,
                thumbnail: animation.thumbnail,
                displaySize: nil,
                onTap: nil,
            )
            view = ffmpegView
        } else {
            let inlineView = InlineAnimationMediaView()
            inlineView.fillsBounds = true
            inlineView.configure(animation: animation, displaySize: nil, client: client)
            view = inlineView
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isAccessibilityElement = false
        view.isUserInteractionEnabled = false
        mediaView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: mediaView.topAnchor),
            view.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
        ])
        animationView = view
    }

    /// ChatMessageInteractiveMediaNode labels a game's animation GAME where a GIF reads GIF.
    private func addBadge(to mediaView: UIView) {
        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = " \(L10n.telegram("Message.Game").uppercased()) "
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        badge.layer.cornerRadius = 6
        badge.clipsToBounds = true
        mediaView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: mediaView.topAnchor, constant: 6),
            badge.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor, constant: 6),
            badge.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @objc private func play() {
        onAction(.pressInlineKeyboardButton(InlineKeyboardButtonPress(
            messageID: messageID,
            type: .inlineKeyboardButtonTypeCallbackGame,
        )))
    }
}
