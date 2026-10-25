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
    private let imageView = TDImageLoadingView()
    private let bodyTextView = MessageTextContentView()
    private let downloadStatus = MediaDownloadStatusView()
    /// The large photo auto-download left for a tap.
    private var deferredDownload: DeferredMediaDownload?

    /// `autoDownloads` false (auto-download's photo setting for the chat) leaves a large photo to a tap on its
    /// download arrow, as ChatMessageAttachedContentNode's `automaticDownload` does.
    init(preview: LinkPreview, client: TDLibClient, autoDownloads: Bool = true) {
        self.preview = preview
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(openLink))
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

    @objc private func openLink() {
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
