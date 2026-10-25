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
        case .description,
             .explanation: [.gallery, .file, .location]
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

    /// AttachmentFileController's subtitle for its `.poll` source, which takes an option as a quiz answer.
    var fileSubtitle: String {
        switch self {
        case .description: L10n.telegram("Attachment.File.PollSubtitle.Description")
        case .explanation,
             .option: L10n.telegram("Attachment.File.PollSubtitle.Explanation")
        }
    }
}

// MARK: - PollDraftMediaPreview

/// What ListComposePollOptionComponent's 40-point thumbnail draws for media being composed.
enum PollDraftMediaPreview {
    /// A photo, or a video's or GIF's first frame with the play button on a video.
    case image(UIImage, isVideo: Bool)
    case sticker(Sticker)
    /// A point, or a place with its venue, which the menu's map marks as LocationViewController does.
    case location(Location, venue: TDNativeVenue?)
    /// A file without a preview image.
    case file
    case audio
    /// A link with its web page, once getLinkPreview has one.
    case link(String, LinkPreview?)
}

// MARK: - PollDraftMedia

/// ComposePollScreen's AttachedMedia: the media TDLib sends as `inputPollMedia`, the field's thumbnail and the
/// app's copies of the picked files. A picked file `requiresUpload`: the poll creator uploads it ahead of the poll
/// and the media then sends the uploaded file.
struct PollDraftMedia {
    /// The picked file TDLib uploads ahead of the poll (`preliminaryUploadFile`), and the media with another file
    /// in its place.
    struct Upload {
        let file: TDNativeInputFile
        let type: TDNativeFileType
        let media: (TDNativeInputFile) -> TDNativeInputPollMedia
        /// The original of a video TDLib generates by converting it (`inputFileGenerated`).
        var convertedPath: String?
    }

    let id = UUID()
    private(set) var input: TDNativeInputPollMedia
    private(set) var preview: PollDraftMediaPreview
    /// Files in `SelectedDocumentFileStore` the media sends, removed when it's replaced, deleted or discarded.
    let fileURLs: [URL]
    /// The file still to upload; nil once uploaded, or for media without a picked file.
    private(set) var upload: Upload?

    /// An option's attached link, which opens its editor when tapped.
    var link: String? {
        if case .link(let url, _) = preview { return url }
        return nil
    }

    /// ComposePollScreen's `requiresUpload` for a link: a link without its web page (makePollAttachmentLinkWebpage)
    /// asks getLinkPreview for it ahead of the poll.
    var needsLinkPreview: Bool {
        if case .link(_, nil) = preview { return true }
        return false
    }

    init(input: TDNativeInputPollMedia, preview: PollDraftMediaPreview, fileURLs: [URL], upload: Upload? = nil) {
        self.input = input
        self.preview = preview
        self.fileURLs = fileURLs
        self.upload = upload
    }

    /// The gallery's pick as legacyAssetPickerEnqueueMessages would send it: a photo, a video converted at its
    /// quality, or a muted video as a GIF. A Live Photo goes as its still.
    static func gallery(_ image: SelectedImage) -> PollDraftMedia {
        if let motion = image.livePhotoVideoURL { SelectedDocumentFileStore.remove([motion]) }
        guard let video = image.video else { return photo(at: image.url, preview: image.image) }
        let width = Int(video.sentDimensions.width)
        let height = Int(video.sentDimensions.height)
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
        let type: TDNativeFileType
        let media: (TDNativeInputFile) -> TDNativeInputPollMedia
        if video.sendsAsGIF {
            type = .fileTypeAnimation
            media = { file in
                let animation = TDNativeInputAnimation(
                    animation: file,
                    thumbnail: thumbnail,
                    addedStickerFileIds: [],
                    duration: duration,
                    width: width,
                    height: height,
                )
                return .inputPollMediaAnimation(TDNativeInputPollMediaAnimation(animation: animation))
            }
        } else {
            type = .fileTypeVideo
            media = { file in
                let video = TDNativeInputVideo(
                    video: file,
                    thumbnail: thumbnail,
                    cover: nil,
                    startTimestamp: 0,
                    addedStickerFileIds: [],
                    duration: duration,
                    width: width,
                    height: height,
                    supportsStreaming: true,
                )
                return .inputPollMediaVideo(TDNativeInputPollMediaVideo(video: video))
            }
        }
        return PollDraftMedia(
            input: media(file),
            preview: .image(image.image, isVideo: !video.sendsAsGIF),
            fileURLs: image.fileURLs,
            upload: Upload(file: file, type: type, media: media, convertedPath: video.url.path(percentEncoded: false)),
        )
    }

    /// A photo file in the store at its pixel size.
    static func photo(at url: URL, preview: UIImage) -> PollDraftMedia {
        let size = pixelSize(of: url) ?? CGSize(
            width: preview.size.width * preview.scale,
            height: preview.size.height * preview.scale,
        )
        let width = Int(size.width)
        let height = Int(size.height)
        let file = TDNativeInputFile.inputFileLocal(TDNativeInputFileLocal(path: url.path(percentEncoded: false)))
        let media: (TDNativeInputFile) -> TDNativeInputPollMedia = { file in
            let photo = TDNativeInputPhoto(
                photo: file,
                thumbnail: nil,
                video: nil,
                addedStickerFileIds: [],
                width: width,
                height: height,
            )
            return .inputPollMediaPhoto(TDNativeInputPollMediaPhoto(photo: photo))
        }
        return PollDraftMedia(
            input: media(file),
            preview: .image(preview, isVideo: false),
            fileURLs: [url],
            upload: Upload(file: file, type: .fileTypePhoto, media: media),
        )
    }

    /// The file list's gallery pick (MediaPickerScreen's `asFile`), sent as Send as File sends it: the photo's file,
    /// or the video's with its first frame as the thumbnail.
    static func galleryFile(_ image: SelectedImage) -> PollDraftMedia {
        if let motion = image.livePhotoVideoURL { SelectedDocumentFileStore.remove([motion]) }
        let url = image.video?.url ?? image.url
        var thumbnail: TDNativeInputThumbnail?
        if let video = image.video {
            thumbnail = TDNativeInputThumbnail(
                thumbnail: .inputFileLocal(TDNativeInputFileLocal(path: image.url.path(percentEncoded: false))),
                width: Int(video.thumbnailSize.width),
                height: Int(video.thumbnailSize.height),
            )
        }
        let file = TDNativeInputFile.inputFileLocal(TDNativeInputFileLocal(path: url.path(percentEncoded: false)))
        let media = documentMedia(thumbnail: thumbnail)
        return PollDraftMedia(
            input: media(file),
            preview: .image(image.image, isVideo: false),
            fileURLs: image.fileURLs,
            upload: Upload(file: file, type: .fileTypeDocument, media: media),
        )
    }

    /// A recently sent file from the file list, attached by its uploaded file and previewed by its minithumbnail.
    static func sentDocument(_ document: Document) -> PollDraftMedia {
        let image = document.minithumbnail.flatMap { UIImage(data: $0.data) }
        return PollDraftMedia(
            input: documentMedia(thumbnail: nil)(.inputFileId(TDNativeInputFileId(id: document.document.id))),
            preview: image.map { .image($0, isVideo: false) } ?? .file,
            fileURLs: [],
        )
    }

    /// The File button's pick: music with its tags and cover as an audio (the iCloud item's `audioMetadata`), any
    /// other file as a document, previewed by its image when it is one.
    static func document(_ document: SelectedDocument, music: ComposerAudioMetadata?) -> PollDraftMedia {
        let file = TDNativeInputFile
            .inputFileLocal(TDNativeInputFileLocal(path: document.url.path(percentEncoded: false)))
        if let music {
            var cover: TDNativeInputThumbnail?
            if let url = music.coverURL {
                cover = TDNativeInputThumbnail(
                    thumbnail: .inputFileLocal(TDNativeInputFileLocal(path: url.path(percentEncoded: false))),
                    width: Int(music.coverSize.width),
                    height: Int(music.coverSize.height),
                )
            }
            let media: (TDNativeInputFile) -> TDNativeInputPollMedia = { file in
                let audio = TDNativeInputAudio(
                    audio: file,
                    albumCoverThumbnail: cover,
                    duration: music.duration,
                    title: music.title,
                    performer: music.performer,
                )
                return .inputPollMediaAudio(TDNativeInputPollMediaAudio(audio: audio))
            }
            let coverImage = music.coverURL.flatMap { thumbnailImage(at: $0) }
            return PollDraftMedia(
                input: media(file),
                preview: coverImage.map { .image($0, isVideo: false) } ?? .audio,
                fileURLs: [document.url],
                upload: Upload(file: file, type: .fileTypeAudio, media: media),
            )
        }
        let isImage = UTType(filenameExtension: document.url.pathExtension)?.conforms(to: .image) == true
        let image = isImage ? thumbnailImage(at: document.url) : nil
        let media = documentMedia(thumbnail: nil)
        return PollDraftMedia(
            input: media(file),
            preview: image.map { .image($0, isVideo: false) } ?? .file,
            fileURLs: [document.url],
            upload: Upload(file: file, type: .fileTypeDocument, media: media),
        )
    }

    /// The location picker's pick: a place as a venue, any other point as a location. A live location isn't offered.
    static func location(_ content: InputMessageContent) -> PollDraftMedia? {
        switch content {
        case .inputMessageLocation(let value):
            PollDraftMedia(
                input: .inputPollMediaLocation(TDNativeInputPollMediaLocation(location: value.location)),
                preview: .location(value.location, venue: nil),
                fileURLs: [],
            )
        case .inputMessageVenue(let value):
            PollDraftMedia(
                input: .inputPollMediaVenue(TDNativeInputPollMediaVenue(venue: value.venue)),
                preview: .location(value.venue.location, venue: value.venue),
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

    /// chatTextLinkEditController's link, with the web page it previewed for that link.
    static func link(_ url: String, preview: LinkPreview? = nil) -> PollDraftMedia {
        PollDraftMedia(
            input: .inputPollMediaLink(TDNativeInputPollMediaLink(url: url)),
            preview: .link(url, preview),
            fileURLs: [],
        )
    }

    /// A document sent as it is, without TDLib guessing its kind.
    private static func documentMedia(
        thumbnail: TDNativeInputThumbnail?,
    ) -> (TDNativeInputFile) -> TDNativeInputPollMedia {
        { file in
            let document = TDNativeInputDocument(
                document: file,
                thumbnail: thumbnail,
                disableContentTypeDetection: true,
            )
            return .inputPollMediaDocument(TDNativeInputPollMediaDocument(document: document))
        }
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

    /// ComposePollScreen's uploaded media (`standaloneUploadedImage`, `standaloneUploadedFile`): it sends the
    /// uploaded file and needs no further upload.
    func uploaded(fileID: Int) -> PollDraftMedia {
        guard let upload else { return self }
        var media = self
        media.input = upload.media(.inputFileId(TDNativeInputFileId(id: fileID)))
        media.upload = nil
        return media
    }

    /// uploadAttachedMediaIfNeeded's `webpagePreview` result for a link: TDLib sends the link by its URL, and the
    /// web page only draws its thumbnail.
    func withLinkPreview(_ linkPreview: LinkPreview) -> PollDraftMedia {
        guard case .link(let url, _) = preview else { return self }
        var media = self
        media.preview = .link(url, linkPreview)
        return media
    }
}

// MARK: - PollMediaAttachmentFlow

/// presentPollAttachmentScreen: one attachment sheet with the subject's buttons, opening on the gallery with one item
/// at a time. The sheet's buttons switch its content in place, as AttachmentController.switchToController does with
/// its crossfade: Gallery, File (AttachmentFileController's list), Location (the location picker) and Sticker (the
/// sticker tab). Link closes the sheet and opens the link editor, and the file list's Select from Gallery and Select
/// from Files close it for their pickers. The flow ends once with the picked media, or nil when everything was
/// closed.
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
    /// The attachment sheet, whose root is the current tab's controller.
    private weak var sheet: UINavigationController?
    private var currentTab = AttachmentSheetTab.gallery

    /// The subject's buttons; without an account there's no Sticker button.
    private var tabs: [AttachmentSheetTab] {
        var tabs = subject.tabs
        if accountID == nil { tabs.removeAll { $0 == .sticker } }
        return tabs
    }

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
        guard let presenter else { return finish(nil) }
        let id = nextPickerID()
        currentTab = .gallery
        let navigation = makeGallery(id: id).makeNavigationController()
        // The sheet outlives the gallery once another tab takes its place, so the flow hears its swipe down.
        navigation.presentationController?.delegate = self
        sheet = navigation
        presenter.present(navigation, animated: true)
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

    // MARK: Tabs

    private func switchTab(to tab: AttachmentSheetTab, id: Int) {
        guard id == pickerID, tab != currentTab, let sheet, sheet.presentingViewController != nil else { return }
        let controller: UIViewController
        switch tab {
        case .gallery:
            controller = makeGallery(id: id)
        case .file:
            controller = makeFileList(id: id)
        case .location:
            controller = makeLocationPicker(id: id)
        case .sticker:
            guard let picker = makeStickerPicker(id: id) else { return }
            controller = picker
        case .link:
            // The Link button dismisses the sheet and opens chatTextLinkEditController.
            return closeSheet { [self] in presentLinkEditor() }
        case .app,
             .checklist,
             .contact,
             .poll:
            return
        }
        currentTab = tab
        if tab != .gallery {
            AttachmentPanelView.install(in: controller, tabs: tabs, current: tab) { [weak self] tab in
                self?.switchTab(to: tab, id: id)
            }
        }
        replaceContent(of: sheet, with: controller)
    }

    /// AttachmentController.animateSwitchTransition: the old content's snapshot fades out over 0.23 s while the sheet
    /// dips 10 points for 0.2 s and springs back.
    private func replaceContent(of sheet: UINavigationController, with controller: UIViewController) {
        let snapshot = sheet.view.snapshotView(afterScreenUpdates: false)
        sheet.setViewControllers([controller], animated: false)
        guard let snapshot else { return }
        snapshot.frame = sheet.view.bounds
        snapshot.isUserInteractionEnabled = false
        sheet.view.addSubview(snapshot)
        UIView.animate(withDuration: 0.23) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
        let layer = sheet.view.layer
        let dip = CABasicAnimation(keyPath: "transform.translation.y")
        dip.fromValue = 0
        dip.toValue = 10
        dip.duration = 0.2
        dip.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dip.fillMode = .forwards
        dip.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in
            // Display's animateSpring: CASpringAnimation's mass 5 and stiffness 900 with the damping, played in 0.3 s.
            let spring = CASpringAnimation(keyPath: "transform.translation.y")
            spring.mass = 5
            spring.stiffness = 900
            spring.damping = 70
            spring.fromValue = 10
            spring.toValue = 0
            spring.duration = spring.settlingDuration
            spring.speed = Float(spring.settlingDuration / 0.3)
            layer?.add(spring, forKey: "attachmentSwitchSpring")
            layer?.removeAnimation(forKey: "attachmentSwitchDip")
        }
        layer.add(dip, forKey: "attachmentSwitchDip")
        CATransaction.commit()
    }

    private func closeSheet(then next: @escaping () -> Void) {
        guard let sheet, sheet.presentingViewController != nil else { return next() }
        sheet.dismiss(animated: true, completion: next)
    }

    // MARK: Pickers

    /// MediaPickerScreen in its `.poll(mode:asFile: false)` mode, one item at a time.
    private func makeGallery(id: Int) -> AttachmentSheetViewController {
        let sheet = makeMediaPicker(tabs: tabs)
        sheet.switchesTabsInPlace = true
        sheet.onSelectTab = { [self] tab in switchTab(to: tab, id: id) }
        sheet.onSend = { [self] request in load(request, asFile: false) }
        sheet.onDismiss = { [self] in pickerDidClose(id) }
        return sheet
    }

    private func makeMediaPicker(tabs: [AttachmentSheetTab]) -> AttachmentSheetViewController {
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
        return sheet
    }

    /// AttachmentFileController's `.recent` list. Its pickers open once the sheet has gone, and a recent file is
    /// attached as it was sent.
    private func makeFileList(id: Int) -> PollFileAttachmentViewController {
        let list = PollFileAttachmentViewController(client: client, subtitle: subject.fileSubtitle)
        list.onDismiss = { [self] in pickerDidClose(id) }
        list.onSelectFromGallery = { [self] in closeSheet { [self] in presentFileGallery() } }
        list.onSelectFromFiles = { [self] in closeSheet { [self] in presentDocumentPicker() } }
        list.onPick = { [self] document in
            isLoading = true
            closeSheet { [self] in
                isLoading = false
                finish(PollDraftMedia.sentDocument(document))
            }
        }
        return list
    }

    /// LocationPickerController in its `.poll` source: no live location, and the subject's subtitle.
    private func makeLocationPicker(id: Int) -> LocationPickerViewController {
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
        return picker
    }

    /// StickerAttachmentScreen with the `.stickers` content: the sticker tab, titled Sticker, "Add sticker to this
    /// option".
    private func makeStickerPicker(id: Int) -> ComposerMediaPickerViewController? {
        guard let accountID else { return nil }
        let picker = ComposerMediaPickerViewController(accountID: accountID, chatID: chatID, client: client)
        picker.showsStickersOnly = true
        picker.stickersSubtitle = L10n.telegram("StickerPicker.PollSubtitle.PollOption")
        picker.onSticker = { [self, weak picker] sticker, _ in
            let media = PollDraftMedia.sticker(sticker)
            isLoading = true
            // The sheet and a pack it opened close together, from the poll creator's sheet.
            let host = picker?.navigationController?.presentingViewController ?? presenter
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
        return picker
    }

    /// AttachmentFileController's Select from Gallery: MediaPickerScreen in its `.poll(mode:asFile: true)` mode,
    /// whose pick goes as a file.
    private func presentFileGallery() {
        guard let presenter else { return finish(nil) }
        let id = nextPickerID()
        let picker = makeMediaPicker(tabs: [])
        picker.onSend = { [self] request in load(request, asFile: true) }
        picker.onDismiss = { [self] in pickerDidClose(id) }
        presenter.present(picker.makeNavigationController(), animated: true)
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

    private func presentLinkEditor() {
        guard let presenter else { return finish(nil) }
        nextPickerID()
        let editor = PollLinkEditor.make(link: nil, client: client) { [self] link, preview in
            guard let link, !link.isEmpty else { return finish(nil) }
            finish(PollDraftMedia.link(link, preview: preview))
        }
        presenter.present(editor, animated: true)
    }

    // MARK: Picks

    /// The gallery's item, read as the chat reads its attachment sheet's picks; a file goes as it is, as Send as File
    /// sends a video (`LegacyMediaPickers`' `.passthrough`).
    private func load(_ request: AttachmentMediaSendRequest, asFile: Bool) {
        isLoading = true
        PhotoAssetSelectionLoader.load(
            request.assets,
            cropAdjustments: request.cropAdjustments,
            videoEdits: asFile ? [:] : request.videoEdits,
            highQualityPhotos: request.highQualityPhotos,
            videoPreset: request.videoPreset,
        ) { [self] images in
            isLoading = false
            SelectedDocumentFileStore.remove(images.dropFirst().flatMap(\.fileURLs))
            let media = images.first.map { asFile ? PollDraftMedia.galleryFile($0) : PollDraftMedia.gallery($0) }
            finish(media)
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
