// PollMediaAttachment.swift

import ImageIO
import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - PollMediaSubject

/// ComposePollScreen's MediaAttachSubject, PollAttachmentSubject in the pickers: the poll's own media (attached in
/// its description row), the quiz explanation's, or an option's.
enum PollMediaSubject: Equatable {
    case description
    case explanation
    case option

    /// openAttachedMedia's availableButtons: Gallery, File and Location for the poll and the explanation; Gallery,
    /// Sticker, Location and Link for an option.
    var tabs: [AttachmentSheetTab] {
        switch self {
        case .description, .explanation: [.gallery, .file, .location]
        case .option: [.gallery, .sticker, .location, .link]
        }
    }

    /// MediaPickerScreen's title subtitle in its `.poll` mode.
    var gallerySubtitle: String {
        switch self {
        case .description: L10n.telegram("MediaPicker.PollSubtitle.Description")
        case .explanation: L10n.telegram("MediaPicker.PollSubtitle.Explanation")
        case .option: L10n.telegram("MediaPicker.PollSubtitle.PollOption")
        }
    }

    /// LocationPickerControllerNode's subtitle for the `.poll` source.
    var locationSubtitle: String {
        switch self {
        case .description: L10n.telegram("Location.PollSubtitle.Description")
        case .explanation: L10n.telegram("Location.PollSubtitle.Explanation")
        case .option: L10n.telegram("Location.PollSubtitle.PollOption")
        }
    }
}

// MARK: - PollDraftMediaPreview

/// What ListComposePollOptionComponent's 40-point thumbnail draws for media being composed.
enum PollDraftMediaPreview {
    /// A photo, or a video's or GIF's first frame with the play button on a video.
    case image(UIImage, isVideo: Bool)
    case sticker(Sticker)
    case location(Location)
    /// A file without a preview image.
    case file
    case audio
    case link(String)
}

// MARK: - PollDraftMedia

/// ComposePollScreen's AttachedMedia: the media TDLib sends as `inputPollMedia`, the field's thumbnail and the
/// app's copies of the picked files. TDLib uploads the files when the poll is sent, so there's no upload to wait for
/// (ComposePollScreen's `isUploading`).
struct PollDraftMedia {
    let id = UUID()
    let input: TDNativeInputPollMedia
    let preview: PollDraftMediaPreview
    /// Files in `SelectedDocumentFileStore` the media sends, removed when it's replaced, deleted or discarded.
    let fileURLs: [URL]

    /// An option's attached link, which opens its editor when tapped.
    var link: String? {
        if case .link(let url) = preview { return url }
        return nil
    }

    /// The gallery's pick as legacyAssetPickerEnqueueMessages would send it: a photo, a video converted at its
    /// quality, or a muted video as a GIF. A Live Photo goes as its still.
    static func gallery(_ image: SelectedImage) -> PollDraftMedia {
        if let motion = image.livePhotoVideoURL { SelectedDocumentFileStore.remove([motion]) }
        guard let video = image.video else { return photo(at: image.url, preview: image.image) }
        let dimensions = video.sentDimensions
        let file = TDNativeInputFile.inputFileGenerated(TDNativeInputFileGenerated(
            originalPath: video.url.path(percentEncoded: false),
            conversion: video.conversion,
            expectedSize: video.estimatedSize,
        ))
        let thumbnail = TDNativeInputThumbnail(
            thumbnail: .inputFileLocal(TDNativeInputFileLocal(path: image.url.path(percentEncoded: false))),
            width: Int(video.thumbnailSize.width),
            height: Int(video.thumbnailSize.height),
        )
        let duration = Int(video.sentDuration.rounded())
        let input: TDNativeInputPollMedia =
            if video.sendsAsGIF {
                .inputPollMediaAnimation(TDNativeInputPollMediaAnimation(animation: TDNativeInputAnimation(
                    animation: file,
                    thumbnail: thumbnail,
                    addedStickerFileIds: [],
                    duration: duration,
                    width: Int(dimensions.width),
                    height: Int(dimensions.height),
                )))
            } else {
                .inputPollMediaVideo(TDNativeInputPollMediaVideo(video: TDNativeInputVideo(
                    video: file,
                    thumbnail: thumbnail,
                    cover: nil,
                    startTimestamp: 0,
                    addedStickerFileIds: [],
                    duration: duration,
                    width: Int(dimensions.width),
                    height: Int(dimensions.height),
                    supportsStreaming: true,
                )))
            }
        return PollDraftMedia(
            input: input,
            preview: .image(image.image, isVideo: !video.sendsAsGIF),
            fileURLs: image.fileURLs,
        )
    }

    /// A photo file in the store at its pixel size.
    static func photo(at url: URL, preview: UIImage) -> PollDraftMedia {
        let size = pixelSize(of: url) ?? CGSize(
            width: preview.size.width * preview.scale,
            height: preview.size.height * preview.scale,
        )
        let photo = TDNativeInputPhoto(
            photo: .inputFileLocal(TDNativeInputFileLocal(path: url.path(percentEncoded: false))),
            thumbnail: nil,
            video: nil,
            addedStickerFileIds: [],
            width: Int(size.width),
            height: Int(size.height),
        )
        return PollDraftMedia(
            input: .inputPollMediaPhoto(TDNativeInputPollMediaPhoto(photo: photo)),
            preview: .image(preview, isVideo: false),
            fileURLs: [url],
        )
    }

    /// The File button's pick: music with its tags and cover as an audio (the iCloud item's `audioMetadata`), any
    /// other file as a document, previewed by its image when it is one.
    static func document(_ document: SelectedDocument, music: ComposerAudioMetadata?) -> PollDraftMedia {
        let file = TDNativeInputFile
            .inputFileLocal(TDNativeInputFileLocal(path: document.url.path(percentEncoded: false)))
        if let music {
            let audio = TDNativeInputAudio(
                audio: file,
                albumCoverThumbnail: music.coverURL.map { cover in
                    TDNativeInputThumbnail(
                        thumbnail: .inputFileLocal(TDNativeInputFileLocal(path: cover.path(percentEncoded: false))),
                        width: Int(music.coverSize.width),
                        height: Int(music.coverSize.height),
                    )
                },
                duration: music.duration,
                title: music.title,
                performer: music.performer,
            )
            let cover = music.coverURL.flatMap { thumbnailImage(at: $0) }
            return PollDraftMedia(
                input: .inputPollMediaAudio(TDNativeInputPollMediaAudio(audio: audio)),
                preview: cover.map { .image($0, isVideo: false) } ?? .audio,
                fileURLs: [document.url],
            )
        }
        let isImage = UTType(filenameExtension: document.url.pathExtension)?.conforms(to: .image) == true
        let image = isImage ? thumbnailImage(at: document.url) : nil
        return PollDraftMedia(
            input: .inputPollMediaDocument(TDNativeInputPollMediaDocument(document: TDNativeInputDocument(
                document: file,
                thumbnail: nil,
                disableContentTypeDetection: true,
            ))),
            preview: image.map { .image($0, isVideo: false) } ?? .file,
            fileURLs: [document.url],
        )
    }

    /// The location picker's pick: a place as a venue, any other point as a location. A live location isn't offered.
    static func location(_ content: InputMessageContent) -> PollDraftMedia? {
        switch content {
        case .inputMessageLocation(let value):
            PollDraftMedia(
                input: .inputPollMediaLocation(TDNativeInputPollMediaLocation(location: value.location)),
                preview: .location(value.location),
                fileURLs: [],
            )
        case .inputMessageVenue(let value):
            PollDraftMedia(
                input: .inputPollMediaVenue(TDNativeInputPollMediaVenue(venue: value.venue)),
                preview: .location(value.venue.location),
                fileURLs: [],
            )
        default:
            nil
        }
    }

    /// StickerAttachmentScreen's pick, sent by its file as the chat sends stickers.
    static func sticker(_ sticker: Sticker) -> PollDraftMedia {
        PollDraftMedia(
            input: .inputPollMediaSticker(TDNativeInputPollMediaSticker(sticker: TDNativeInputSticker(
                sticker: .inputFileId(TDNativeInputFileId(id: sticker.sticker.id)),
                thumbnail: nil,
                width: sticker.width,
                height: sticker.height,
            ))),
            preview: .sticker(sticker),
            fileURLs: [],
        )
    }

    static func link(_ url: String) -> PollDraftMedia {
        PollDraftMedia(
            input: .inputPollMediaLink(TDNativeInputPollMediaLink(url: url)),
            preview: .link(url),
            fileURLs: [],
        )
    }

    private static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// A small decoded image for the 40-point thumbnail.
    private static func thumbnailImage(at url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: - PollLinkEditor

/// chatTextLinkEditController as a poll option's link editor: Add Link, or Edit Link for an attached one, "Attach a
/// link to this option.", the URL field and Done. Done takes a link Telegram would open (`explicitUrl` adds
/// https://, `isValidUrl` wants an http, https or tonsite address with a domain) or an empty field, which removes
/// the link. A new link starts from a URL on the pasteboard.
enum PollLinkEditor {
    /// - Parameter apply: The link, empty to remove it, or nil for Cancel.
    @MainActor static func make(link: String?, apply: @escaping (String?) -> Void) -> UIAlertController {
        let alert = UIAlertController(
            title: L10n.telegram(link == nil ? "TextFormat.AddLinkTitle" : "TextFormat.EditLinkTitle"),
            message: L10n.telegram("CreatePoll.Link.Description"),
            preferredStyle: .alert,
        )
        let done = UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [weak alert] _ in
            let value = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            apply(value.isEmpty ? "" : explicitURL(value))
        }
        alert.addTextField { [weak done] field in
            field.placeholder = L10n.telegram("TextFormat.AddLinkPlaceholder")
            field.text = link
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.returnKeyType = .done
            if link == nil, UIPasteboard.general.hasURLs, let url = UIPasteboard.general.url?.absoluteString {
                field.text = url
            }
            field.addAction(UIAction { [weak field] _ in
                done?.isEnabled = isAcceptable(field?.text ?? "")
            }, for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { _ in apply(nil) })
        alert.addAction(done)
        alert.preferredAction = done
        done.isEnabled = isAcceptable(alert.textFields?.first?.text ?? "")
        return alert
    }

    /// An empty field, or a link Telegram accepts.
    private static func isAcceptable(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || isValidURL(explicitURL(value))
    }

    /// UrlEscaping's explicitUrl: an address without a scheme gets https://, or tonsite:// on a .ton domain.
    private static func explicitURL(_ value: String) -> String {
        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("http:"), !lowercased.hasPrefix("https:"), !lowercased.hasPrefix("tonsite:"),
              !value.contains("://")
        else { return value }
        if URL(string: "http://\(value)")?.host?.hasSuffix(".ton") == true { return "tonsite://\(value)" }
        return "https://\(value)"
    }

    /// UrlEscaping's isValidUrl with chatTextLinkEditController's schemes: http, https and tonsite, the web ones
    /// with a top level domain, and no user.
    private static func isValidURL(_ value: String) -> Bool {
        let requiresTopLevelDomain = ["http": true, "https": true, "tonsite": true]
        guard let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: escaped), let scheme = url.scheme?.lowercased(),
              let requiresDomain = requiresTopLevelDomain[scheme], let host = url.host, url.user == nil
        else { return false }
        guard requiresDomain else { return true }
        return host.contains(".") && host.components(separatedBy: ".").last?.isEmpty == false
    }
}

// MARK: - PollMediaAttachmentFlow

/// presentPollAttachmentScreen: the attachment sheet with the subject's buttons opens on the gallery, one item at a
/// time; File opens the document picker, Location the location picker, Sticker the sticker tab and Link the link
/// editor. Telegram switches its pickers inside one sheet; BetterTG's sheet closes and the chosen picker opens, as
/// the chat's attachment menu does. The flow ends once with the picked media, or nil when every picker was closed.
@MainActor final class PollMediaAttachmentFlow: NSObject, UIDocumentPickerDelegate,
    UIAdaptivePresentationControllerDelegate
{
    private let subject: PollMediaSubject
    private let client: TDLibClient
    private let accountID: UUID?
    private let chatID: Int64
    private weak var presenter: UIViewController?
    private var completion: ((PollDraftMedia?) -> Void)?
    /// The picker on screen. A picker's close that isn't followed by another picker or a pick ends the flow.
    private var pickerID = 0
    /// A pick being read, whose picker has already closed.
    private var isLoading = false

    /// - Parameters:
    ///   - accountID: The account whose stickers the Sticker button offers; without one there's no Sticker button.
    ///   - chatID: The chat the poll goes to, for the stickers and the venue search bot.
    ///   - presenter: The poll creator, which presents the pickers.
    ///   - completion: Called once, with the picked media or nil.
    init(
        subject: PollMediaSubject,
        client: TDLibClient,
        accountID: UUID?,
        chatID: Int64,
        presenter: UIViewController,
        completion: @escaping (PollDraftMedia?) -> Void,
    ) {
        self.subject = subject
        self.client = client
        self.accountID = accountID
        self.chatID = chatID
        self.presenter = presenter
        self.completion = completion
        super.init()
    }

    /// AttachmentController's `initialButton: .gallery`.
    func start() {
        presentGallery()
    }

    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return finish(nil) }
        isLoading = true
        Task { [self] in
            let documents = await Task.detached(priority: .userInitiated) {
                SelectedDocumentFileStore.copy([url])
            }.value
            guard let document = documents.first else {
                isLoading = false
                return finish(nil)
            }
            let music = await ComposerAudioMetadata.read(document.url)
            isLoading = false
            finish(PollDraftMedia.document(document, music: music))
        }
    }

    func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
        pickerDidClose(pickerID)
    }

    /// A picker swiped away.
    func presentationControllerDidDismiss(_: UIPresentationController) {
        pickerDidClose(pickerID)
    }

    // MARK: Pickers

    private func presentGallery() {
        guard let presenter else { return finish(nil) }
        var tabs = subject.tabs
        if accountID == nil { tabs.removeAll { $0 == .sticker } }
        let configuration = AttachmentSheetConfiguration(
            allowsPhotos: true,
            allowsVideos: true,
            tabs: tabs,
            selectionLimit: 1,
            subtitle: subject.gallerySubtitle,
        )
        let sheet = AttachmentSheetViewController(configuration: configuration)
        let client = client
        Task { [weak sheet] in
            let preset = await VideoSendPreset.uploadDefault(client: client)
            sheet?.setDefaultVideoPreset(preset)
        }
        let id = nextPickerID()
        sheet.onSelectTab = { [self] tab in openTab(tab) }
        sheet.onSend = { [self] request in load(request) }
        sheet.onDismiss = { [self] in pickerDidClose(id) }
        presenter.present(sheet.makeNavigationController(), animated: true)
    }

    private func openTab(_ tab: AttachmentSheetTab) {
        switch tab {
        case .file: presentDocumentPicker()
        case .location: presentLocationPicker()
        case .sticker: presentStickerPicker()
        case .link: presentLinkEditor()
        case .app, .contact, .gallery, .poll: finish(nil)
        }
    }

    /// AttachmentFileController's Select from Files (`legacyICloudFilePicker` with "public.item"), one file.
    private func presentDocumentPicker() {
        guard let presenter else { return finish(nil) }
        nextPickerID()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        picker.presentationController?.delegate = self
        presenter.present(picker, animated: true)
    }

    /// LocationPickerController in its `.poll` source: no live location, and the subject's subtitle.
    private func presentLocationPicker() {
        guard let presenter else { return finish(nil) }
        let id = nextPickerID()
        let picker = LocationPickerViewController(
            peerName: nil,
            allowsLiveLocation: false,
            client: client,
            chatID: chatID,
        ) { [self] content in
            finish(PollDraftMedia.location(content))
        }
        picker.pollSubtitle = subject.locationSubtitle
        picker.onDismiss = { [self] in pickerDidClose(id) }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.presentationController?.delegate = self
        presenter.present(navigation, animated: true)
    }

    /// StickerAttachmentScreen with the `.stickers` content: the sticker tab, titled Sticker, "Add sticker to this
    /// option".
    private func presentStickerPicker() {
        guard let presenter, let accountID else { return finish(nil) }
        let id = nextPickerID()
        let picker = ComposerMediaPickerViewController(accountID: accountID, chatID: chatID, client: client)
        picker.showsStickersOnly = true
        picker.stickersSubtitle = L10n.telegram("StickerPicker.PollSubtitle.PollOption")
        picker.onSticker = { [self, weak picker] sticker in
            let media = PollDraftMedia.sticker(sticker)
            isLoading = true
            // The picker and a pack it opened close together, from the poll creator's sheet.
            let host = picker?.navigationController?.presentingViewController ?? self.presenter
            guard let host else {
                isLoading = false
                return finish(media)
            }
            host.dismiss(animated: true) { [self] in
                isLoading = false
                finish(media)
            }
        }
        picker.onDismiss = { [self] in pickerDidClose(id) }
        let navigation = TelegramNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = false
        navigation.presentationController?.delegate = self
        presenter.present(navigation, animated: true)
    }

    /// The Link button dismisses the sheet and opens chatTextLinkEditController.
    private func presentLinkEditor() {
        guard let presenter else { return finish(nil) }
        nextPickerID()
        let editor = PollLinkEditor.make(link: nil) { [self] link in
            guard let link, !link.isEmpty else { return finish(nil) }
            finish(PollDraftMedia.link(link))
        }
        presenter.present(editor, animated: true)
    }

    // MARK: Picks

    /// The gallery's item, read as the chat reads its attachment sheet's picks.
    private func load(_ request: AttachmentMediaSendRequest) {
        isLoading = true
        PhotoAssetSelectionLoader.load(
            request.assets,
            cropAdjustments: request.cropAdjustments,
            videoEdits: request.videoEdits,
            highQualityPhotos: request.highQualityPhotos,
            videoPreset: request.videoPreset,
        ) { [self] images in
            isLoading = false
            SelectedDocumentFileStore.remove(images.dropFirst().flatMap(\.fileURLs))
            finish(images.first.map { PollDraftMedia.gallery($0) })
        }
    }

    // MARK: Ending

    @discardableResult private func nextPickerID() -> Int {
        pickerID += 1
        return pickerID
    }

    /// A picker reports its close before handing over its pick or opening the next picker, so the flow waits a turn.
    private func pickerDidClose(_ id: Int) {
        DispatchQueue.main.async { [self] in
            guard id == pickerID, !isLoading else { return }
            finish(nil)
        }
    }

    private func finish(_ media: PollDraftMedia?) {
        guard let completion else {
            if let media { SelectedDocumentFileStore.remove(media.fileURLs) }
            return
        }
        self.completion = nil
        completion(media)
    }
}
