// MessageLinkPreviewView.swift

import TDLibKit
import UIKit

final class MessageLinkPreviewView: UIView, MessageSupplementView, UIGestureRecognizerDelegate {
    /// The still a link preview shows, which a poll's link media draws too.
    struct Thumbnail {
        let file: File
        let placeholder: Data?
        let size: CGSize
    }

    private let preview: LinkPreview
    private let client: TDLibClient
    private let imageView = TDImageLoadingView()
    private let bodyTextView = MessageTextContentView()
    private let downloadStatus = MediaDownloadStatusView()
    /// The large photo auto-download left for a tap.
    private var deferredDownload: DeferredMediaDownload?

    /// `autoDownloads` false (auto-download's photo setting for the chat) leaves a large photo to a tap on its
    /// download arrow, as ChatMessageAttachedContentNode's `automaticDownload` does.
    init(preview: LinkPreview, client: TDLibClient, autoDownloads: Bool = true) {
        self.preview = preview
        self.client = client
        super.init(frame: .zero)
        layer.cornerRadius = 5
        clipsToBounds = true
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)
        let accent = UIView()
        accent.backgroundColor = .systemBlue
        accent.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accent)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
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
        let text = UIStackView()
        text.axis = .vertical
        text.spacing = 3
        let site = label(
            preview.siteName.isEmpty
                ? (URL(string: preview.url)?.host ?? preview.displayUrl)
                : preview.siteName,
            size: 13,
            weight: .semibold,
            color: .systemBlue,
        )
        text.addArrangedSubview(site)
        if !preview.title.isEmpty { text.addArrangedSubview(label(
            preview.title,
            size: 15,
            weight: .semibold,
            color: .label,
        )) }
        if !preview.description.text.isEmpty {
            bodyTextView.configure(
                formattedText: preview.description,
                client: client,
                statusText: "",
                statusColor: .secondaryLabel,
                maximumWidth: Utils.maxMessageContentWidth - 24,
            )
            bodyTextView.onUnhandledTap = { [weak self] in self?.openLink() }
            // A timestamp in an embedded video's description plays it from there (seekToTimecode).
            bodyTextView.onMediaTimestamp = { [weak self] seconds in self?.presentPlayer(at: seconds) }
            text.addArrangedSubview(bodyTextView)
        } else if !preview.author.isEmpty {
            text.addArrangedSubview(label(preview.author, size: 14, weight: .regular, color: .secondaryLabel))
        }
        let media = Self.thumbnail(preview.type)
        if let media {
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 4
            if preview.showLargeMedia, !autoDownloads, !media.file.local.isDownloadingCompleted {
                imageView.loadPlaceholder(data: media.placeholder, client: client)
                imageView.isUserInteractionEnabled = true
                imageView.addSubview(downloadStatus)
                NSLayoutConstraint.activate([
                    downloadStatus.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
                    downloadStatus.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
                ])
                self
                    .deferredDownload = DeferredMediaDownload(
                        file: media.file,
                        client: client,
                        status: downloadStatus,
                    ) {
                        [weak self] file in
                        guard let self else { return }
                        self.deferredDownload = nil
                        imageView.load(
                            file: file,
                            placeholderData: media.placeholder,
                            maximumPixelSize: 720,
                            client: client,
                            preservingImage: true,
                        )
                    }
            } else {
                imageView.load(
                    file: media.file,
                    placeholderData: media.placeholder,
                    maximumPixelSize: 720,
                    client: client,
                )
            }
            // ChatMessageInteractiveMediaNode marks a playable embed's picture with the play button.
            if preview.showLargeMedia, WebEmbedPlayerViewController.isEmbeddedPlayer(preview.type) {
                let playIcon = UIImageView(image: UIImage(systemName: "play.circle.fill"))
                playIcon.translatesAutoresizingMaskIntoConstraints = false
                playIcon.tintColor = .white
                playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 46)
                playIcon.isUserInteractionEnabled = false
                imageView.addSubview(playIcon)
                NSLayoutConstraint.activate([
                    playIcon.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
                    playIcon.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
                ])
            }
            if preview.showLargeMedia {
                if preview.showMediaAboveDescription { content.addArrangedSubview(imageView) }
                content.addArrangedSubview(text)
                if !preview.showMediaAboveDescription { content.addArrangedSubview(imageView) }
                let aspect = min(1.3, max(0.5, media.size.height / max(1, media.size.width)))
                imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspect).isActive = true
            } else {
                let row = UIStackView(arrangedSubviews: [text, imageView])
                row.axis = .horizontal
                row.alignment = .top
                row.spacing = 8
                content.addArrangedSubview(row)
                imageView.widthAnchor.constraint(equalToConstant: 54).isActive = true
                imageView.heightAnchor.constraint(equalToConstant: 54).isActive = true
                bodyTextView.setMaximumLayoutWidth(Utils.maxMessageContentWidth - 86)
            }
        } else { content.addArrangedSubview(text) }
        if preview.instantViewVersion > 0 {
            content.addArrangedSubview(instantViewButton())
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(previewTapped(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        accessibilityLabel = [
            preview.siteName,
            preview.title,
            TelegramSpoilers.accessibilityText(preview.description, revealed: false),
        ]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityTraits = .link
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func thumbnail(_ type: LinkPreviewType) -> Thumbnail? {
        func photo(_ photo: Photo?) -> Thumbnail? {
            guard let photo,
                  let size = photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
            return Thumbnail(
                file: size.photo,
                placeholder: photo.minithumbnail?.data,
                size: CGSize(width: size.width, height: size.height),
            )
        }
        func thumbnail(_ value: TDNativeThumbnail?) -> Thumbnail? {
            guard let value else { return nil }
            return Thumbnail(file: value.file, placeholder: nil, size: CGSize(width: value.width, height: value.height))
        }
        switch type {
        case .linkPreviewTypeArticle(let value): return photo(value.photo)
        case .linkPreviewTypeApp(let value): return photo(value.photo)
        case .linkPreviewTypePhoto(let value): return photo(value.photo)
        case .linkPreviewTypeWebApp(let value): return photo(value.photo)
        case .linkPreviewTypeVideo(let value): return photo(value.cover) ?? thumbnail(value.video.thumbnail)
        case .linkPreviewTypeAnimation(let value): return thumbnail(value.animation.thumbnail)
        case .linkPreviewTypeAudio(let value): return thumbnail(value.audio.albumCoverThumbnail)
        case .linkPreviewTypeDocument(let value): return thumbnail(value.document.thumbnail)
        case .linkPreviewTypeEmbeddedVideoPlayer(let value): return photo(value.thumbnail)
        case .linkPreviewTypeEmbeddedAnimationPlayer(let value): return photo(value.thumbnail)
        case .linkPreviewTypeEmbeddedAudioPlayer(let value): return photo(value.thumbnail)
        case .linkPreviewTypeSticker(let value): return thumbnail(value.sticker.thumbnail)
        case .linkPreviewTypeAlbum(let value):
            guard let first = value.media.first else { return nil }
            switch first {
            case .linkPreviewAlbumMediaPhoto(let value): return photo(value.photo)
            case .linkPreviewAlbumMediaVideo(let value): return thumbnail(value.video.thumbnail)
            }
        default: return nil
        }
    }

    func prepareForReuse() { imageView.cancel()
        bodyTextView.prepareForReuse()
    }

    func setPlaybackVisible(_ visible: Bool) { bodyTextView.setCustomEmojiPlaybackVisible(visible) }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let view = target, view !== self {
            if view === bodyTextView || view === downloadStatus { return false }
            target = view.superview
        }
        return true
    }

    private func label(_ value: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = value
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    /// ChatMessageAttachedContentNode's action button for a page with Instant View: "INSTANT VIEW" in the accent
    /// colour across the preview.
    private func instantViewButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = AttributedString(
            L10n.telegram("Conversation.InstantPagePreview"),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]),
        )
        configuration.image = UIImage(
            systemName: "bolt.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
        )
        configuration.imagePadding = 5
        configuration.baseForegroundColor = .systemBlue
        configuration.background.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        configuration.background.cornerRadius = 6
        let button = UIButton(configuration: configuration)
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.openInstantView() }, for: .touchUpInside)
        return button
    }

    /// InstantPageController over the chat, pushed as Telegram pushes it.
    private func openInstantView() {
        guard let navigation = nearestViewController?.navigationController else { return }
        navigation.pushViewController(
            InstantViewController(url: preview.url, siteName: preview.siteName, client: client),
            animated: true,
        )
    }

    /// ChatMessageWebpageBubbleContentNode's tap: an embedded player's picture opens the player, as openMessage opens
    /// WebEmbedVideoContent in the gallery; anywhere else opens the link.
    @objc private func previewTapped(_ gesture: UITapGestureRecognizer) {
        if !imageView.isHidden, imageView.window != nil,
           imageView.bounds.contains(gesture.location(in: imageView)),
           WebEmbedPlayerViewController(preview: preview) != nil
        {
            presentPlayer(at: nil)
            return
        }
        openLink()
    }

    private func presentPlayer(at timestamp: Int?) {
        guard let player = WebEmbedPlayerViewController(preview: preview, timestamp: timestamp) else { return }
        nearestViewController?.present(player, animated: true)
    }

    @objc private func openLink() {
        // A preview with Instant View opens the article in it, as Telegram's webpage bubble does.
        if preview.instantViewVersion > 0 {
            openInstantView()
            return
        }
        guard let url = getUrl(from: preview.url), let controller = nearestViewController else { return }
        if preview.skipConfirmation {
            TelegramLinkRouter.shared.open(url, from: controller)
        } else {
            let alert = UIAlertController(
                title: L10n.telegram("OpenLinkConfirmation.Title"),
                message: url.absoluteString,
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.telegram("OpenLinkConfirmation.Open"), style: .default) { _ in
                TelegramLinkRouter.shared.open(url, from: controller)
            })
            controller.present(alert, animated: true)
        }
    }
}
