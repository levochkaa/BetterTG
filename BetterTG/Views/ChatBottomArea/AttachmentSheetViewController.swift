// AttachmentSheetViewController.swift

import AVFoundation
import Lottie
import Photos
import PhotosUI
import TDLibKit
import UIKit

// MARK: - AttachmentSheetTab

/// AttachmentPanel's buttons in ChatControllerOpenAttachmentMenu's order: Gallery, File, Location, Poll, Checklist
/// and Contact, each where the chat allows it. Sticker (AttachmentButtonType.sticker) opens BetterTG's emoji, sticker
/// and
/// GIF picker, which the attach button used to offer. Link (AttachmentButtonType.link) is a poll option's
/// (presentPollAttachmentScreen). App (AttachmentButtonType.app) is an attachment menu bot, after Gallery.
enum AttachmentSheetTab: Equatable {
    case gallery
    case file
    case location
    case poll
    case checklist
    case contact
    case sticker
    case link
    case app(AttachmentMenuBotButton)

    var title: String {
        switch self {
        case .gallery: L10n.telegram("Attachment.Gallery")
        case .file: L10n.telegram("Attachment.File")
        case .location: L10n.telegram("Attachment.Location")
        case .poll: L10n.telegram("Attachment.Poll")
        case .checklist: L10n.telegram("Attachment.Todo")
        case .contact: L10n.telegram("Attachment.Contact")
        case .sticker: L10n.telegram("Attachment.Sticker")
        case .link: L10n.telegram("Attachment.Link")
        case .app(let bot): bot.name
        }
    }

    var symbolName: String {
        switch self {
        case .gallery: "photo.fill"
        case .file: "doc.fill"
        case .location: "location.fill"
        case .poll: "chart.bar.fill"
        case .checklist: "checklist"
        case .contact: "person.crop.circle.fill"
        case .sticker: "face.smiling"
        case .link: "link"
        case .app: "app.fill"
        }
    }
}

// MARK: - AttachmentMenuBotButton

/// AttachmentPanel's `.app(bot)` button: the bot's short name over its iOS icon, the animated TGS or the side menu
/// PNG once downloaded.
struct AttachmentMenuBotButton: Equatable {
    let botUserID: Int64
    let name: String
    let animatedIconPath: String?
    let imageIconPath: String?
}

// MARK: - AttachmentSheetConfiguration

/// What the chat lets the attachment sheet offer, from its send permissions.
struct AttachmentSheetConfiguration {
    var allowsPhotos = false
    var allowsVideos = false
    var allowsCamera = false
    var tabs: [AttachmentSheetTab] = [.gallery]
    var allowsSendAsFile = false
    /// MediaPickerScreen's `isSpoilerAvailable`: not in secret chats.
    var allowsSpoiler = false
    /// MediaPickerScreen's `displayLivePhotoIcon`: not in secret chats.
    var showsLivePhotos = false
    /// MediaPickerScreen's `hasTimer`: a private chat with someone other than the user.
    var allowsViewOnce = false
    /// LegacyMediaPickerGallery's `hasCoverButton`: the video editor chooses a cover in broadcast channels and Saved
    /// Messages.
    var allowsVideoCover = false
    /// Saved Messages sets reminders instead of scheduling and has no Send Silently.
    var isReminders = false
    var canSchedule = false
    var canSendWhenOnline = false
    /// Initial input only: Gallery keeps its own attributed caption while other attachment tabs are shown.
    var caption = AttributedString()
    var allowsCaptionEditing = false
    var captionIsAbove = false
    /// MediaPickerScreen's selection limit (`enableMultiselection ? 100 : 1`). With one item a tap picks it, as
    /// Done in Telegram's single item preview does.
    var selectionLimit = 100
    /// MediaPickerTitleView's subtitle under Recents, such as a poll's "Add media to this option".
    var subtitle: String?
}

// MARK: - AttachmentMediaSendRequest

/// The picked items and how the sheet asked to send them.
struct AttachmentMediaSendRequest {
    let assets: [PHAsset]
    /// TGMediaEditingContext's crops of the picked photos, by asset.
    var cropAdjustments = [String: PhotoCropAdjustments]()
    /// TGMediaEditingContext's trims and mutes of the picked videos, by asset.
    var videoEdits = [String: VideoEditAdjustments]()
    /// The picked Live Photos that go live (`TGMediaAssetsResolvedLivePhotoMode`'s Live); the others go as stills.
    var livePhotoAssetIDs = Set<String>()
    let mode: ComposerMediaSendMode
    let timing: AttachmentSendTiming
    let highQualityPhotos: Bool
    let spoilerAssetIDs: Set<String>
    let selfDestructTimer: MediaSelfDestructTimer?
    let videoPreset: VideoSendPreset
    let captionIsAbove: Bool
    let caption: AttributedString
    var schedulingState: TDNativeMessageSchedulingState?
}

// MARK: - AttachmentSheetViewController

/// Telegram's attachment sheet: AttachmentController with MediaPickerScreen as its Gallery. The library grid takes up
/// to 100 numbered items, with the camera tile in Recents, the albums under the title, the picked items' own view and
/// the More menu (Send as File, Send in Standard Quality, Send Without Grouping, Move Caption, Spoiler, the timer and
/// the
/// video quality). The panel's buttons open the chat's other attachments; with items picked the send panel takes
/// their place, sending them with the composer's text as the caption, and holding Send offers the send options.
@MainActor final class AttachmentSheetViewController: UIViewController, UICollectionViewDataSource,
    UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIAdaptivePresentationControllerDelegate,
    UIGestureRecognizerDelegate, PHPhotoLibraryChangeObserver
{
    // MARK: Private

    private enum DisplayMode {
        case all
        case selected
    }

    // MARK: Internal

    var onSelectTab: ((AttachmentSheetTab) -> Void)?
    var onCamera: (() -> Void)?
    var onSend: ((AttachmentMediaSendRequest) -> Void)?
    var onDismiss: (() -> Void)?
    /// AttachmentController's `requestController` for a flow that switches the sheet's content in place
    /// (presentPollAttachmentScreen): another tab is handed over while the sheet stays. Otherwise the sheet closes
    /// before the tab opens.
    var switchesTabsInPlace = false

    private let configuration: AttachmentSheetConfiguration
    private var captionClient: TDLibClient?
    private var caption: AttributedString

    private let imageManager = PHCachingImageManager()
    private let gridLayout = MediaPickerGridLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
    private let panel = AttachmentPanelView()
    private let placeholderView = MediaPickerPlaceholderView()
    private let manageBanner = MediaPickerManageBanner()
    private let titleButton = UIButton(type: .system)
    private let selectedButton = MediaPickerSelectedButton()
    private let moreButton = UIButton.telegramGlassIcon(
        UIImage(systemName: "ellipsis"),
        accessibilityLabel: L10n.telegram("Common.More"),
    )
    /// MediaPickerGridItem's thumbnail request: opportunistic, any size near the target.
    private let thumbnailOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()

    private var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private var observesLibrary = false
    /// The album the grid shows; nil is Recents.
    private var album: PHAssetCollection?
    private var fetchResult: PHFetchResult<PHAsset>?
    private var selection = [PHAsset]()
    private var spoilerAssetIDs = Set<String>()
    private var displayMode = DisplayMode.all
    private var selfDestructTimer: MediaSelfDestructTimer?
    /// The videos' quality: the server's upload default for the network until the user picks one
    /// (`TG_preferredVideoPreset_v0`, which the attachment menu resets when it opens).
    private var videoPreset = VideoSendPreset.medium
    private var choseVideoPreset = false
    /// Photos go in high quality unless More's Send in Standard Quality says otherwise.
    private var isHighQuality = true
    private var captionIsAbove: Bool
    private var thumbnailSize = CGSize.zero
    private var didSettleInitialOffset = false
    private var photoEdits = [String: PhotoCropEdit]()
    private var videoEdits = [String: VideoEditAdjustments]()
    /// An edited video's frame for the grid (VideoEditThumbnail), kept while the edit lasts.
    private var videoEditThumbnails = [String: UIImage]()
    /// TGMediaEditingContext's `forceLivePhotoEnabled`: picked Live Photos go as stills until the bar's Live button
    /// turns them on.
    private var forcesLivePhotos = false
    /// TGMediaEditingContext's `livePhotoModeForItem:`: Live or Live Off as a photo's own menu set it, by asset.
    private var livePhotoModes = [String: Bool]()
    private var isClosing = false
    /// AttachmentController's tap on the dimmed chat above the sheet, which closes it.
    private var outsideTap: UITapGestureRecognizer?

    var attachmentTabs: [AttachmentSheetTab] { configuration.tabs }

    private var hasCaption: Bool { caption.characters.contains { !$0.isWhitespace } }

    private var allowsMedia: Bool {
        configuration.allowsPhotos || configuration.allowsVideos
    }

    private var hasLibraryAccess: Bool {
        allowsMedia && (authorization == .authorized || authorization == .limited)
    }

    private var showsCameraTile: Bool {
        displayMode == .all && album == nil && configuration.allowsCamera && hasLibraryAccess
    }

    private var selectionHasPhoto: Bool {
        selection.contains { $0.mediaType == .image }
    }

    /// TGPhotoQualityController's highest preset for the picked videos: the best their sizes allow, nil without
    /// videos.
    private var maximumVideoPreset: VideoSendPreset? {
        selection
            .filter { $0.mediaType == .video }
            .map { VideoSendPreset.bestAvailable(for: CGSize(width: $0.pixelWidth, height: $0.pixelHeight)) }
            .max()
    }

    /// The chat's media kinds; MediaAssetsContext filters the grid to one when the other is banned.
    private var mediaPredicate: NSPredicate {
        switch (configuration.allowsPhotos, configuration.allowsVideos) {
        case (true, false):
            NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        case (false, true):
            NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        default:
            NSPredicate(
                format: "mediaType = %d || mediaType = %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue,
            )
        }
    }

    init(configuration: AttachmentSheetConfiguration, client: TDLibClient? = nil) {
        self.configuration = configuration
        self.captionClient = client
        self.caption = configuration.caption
        self.captionIsAbove = configuration.captionIsAbove
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTitle()
        configureCollectionView()
        configurePlaceholder()
        configurePanel()
        configurePhotoEditing()
        manageBanner.onManage = { [weak self] source in self?.showLimitedAccessOptions(from: source) }
        selectedButton.addTarget(self, action: #selector(showSelectedPressed), for: .touchUpInside)
        moreButton.addTarget(self, action: #selector(morePressed), for: .touchUpInside)
        reloadLibrary()
        if allowsMedia, authorization == .notDetermined {
            // MediaPickerScreen asks for the library when it first opens.
            Task { [weak self] in
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                self?.authorization = status
                self?.reloadLibrary()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Back from another tab shown in the sheet, picked items hold the sheet again.
        navigationController?.isModalInPresentation = !selection.isEmpty && !isClosing
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installOutsideTap()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = max(
            0,
            collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset
                .right,
        )
        var bannerHeight: CGFloat = 0
        if manageBanner.superview != nil {
            bannerHeight = manageBanner.height(forWidth: width)
            manageBanner.frame = CGRect(x: 0, y: -bannerHeight, width: width, height: bannerHeight)
        }
        let panelTop = panel.convert(CGPoint.zero, to: view).y
        let collectionBottom = collectionView.convert(CGPoint(x: 0, y: collectionView.bounds.maxY), to: view).y
        let automaticBottom = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let panelInset = max(AttachmentPanelView.barHeight, collectionBottom - panelTop - automaticBottom)
        let insets = UIEdgeInsets(top: bannerHeight, left: 0, bottom: panelInset, right: 0)
        if collectionView.contentInset != insets {
            let wasAtTop = !didSettleInitialOffset
                || collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
            collectionView.contentInset = insets
            collectionView.verticalScrollIndicatorInsets = UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: panelInset,
                right: 0,
            )
            if wasAtTop { scrollGridToTop() }
        }
        if !didSettleInitialOffset, collectionView.bounds.height > 0 {
            didSettleInitialOffset = true
            scrollGridToTop()
        }
        let scale = min(2, max(1, traitCollection.displayScale))
        thumbnailSize = CGSize(width: 128 * scale, height: 128 * scale)
    }

    private static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// The album's key item, 28 pt with Telegram's rounded corners, drawn in its own colours.
    private nonisolated static func albumThumbnail(
        _ album: MediaPickerAlbum,
        imageManager: PHImageManager,
    ) -> UIImage? {
        guard let asset = album.keyAsset else { return nil }
        let side: CGFloat = 28
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        var result: UIImage?
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: side * 3, height: side * 3),
            contentMode: .aspectFill,
            options: options,
        ) { image, _ in result = image }
        guard let image = result else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let rounded = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            UIBezierPath(roundedRect: rect, cornerRadius: 6).addClip()
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width,
                height: size.height,
            ))
        }
        return rounded.withRenderingMode(.alwaysOriginal)
    }

    /// The upload default once the server's auto-download presets arrive; a quality the user picked stays.
    func setDefaultVideoPreset(_ preset: VideoSendPreset) {
        guard !choseVideoPreset else { return }
        videoPreset = preset
    }

    func makeNavigationController() -> TelegramNavigationController {
        let navigation = TelegramNavigationController(rootViewController: self)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        navigation.presentationController?.delegate = self
        return navigation
    }

    // MARK: Data source

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        guard hasLibraryAccess else { return 0 }
        switch displayMode {
        case .selected:
            return selection.count
        case .all:
            return (fetchResult?.count ?? 0) + (showsCameraTile ? 1 : 0)
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        if showsCameraTile, indexPath.item == 0 {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: MediaPickerCameraCell.reuseIdentifier,
                for: indexPath,
            )
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MediaPickerGridCell.reuseIdentifier,
            for: indexPath,
        )
        guard let gridCell = cell as? MediaPickerGridCell, let asset = asset(at: indexPath.item) else { return cell }
        gridCell.configure(asset: asset, livePhoto: livePhotoMode(of: asset))
        gridCell.onToggleCheck = { [weak self] in self?.toggleSelection(of: asset) }
        configureSelection(of: gridCell, assetID: asset.localIdentifier)
        loadThumbnail(asset, into: gridCell)
        return cell
    }

    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { asset(at: $0.item) }
        guard !assets.isEmpty, thumbnailSize != .zero else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: thumbnailOptions,
        )
    }

    func collectionView(_: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { asset(at: $0.item) }
        guard !assets.isEmpty, thumbnailSize != .zero else { return }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: thumbnailOptions,
        )
    }

    // MARK: Delegate

    /// Telegram opens an item's preview and picks it with its check; a single item picker picks it at once.
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if showsCameraTile, indexPath.item == 0 {
            let onCamera = onCamera
            confirmDiscardingSelection { [weak self] in
                self?.close { onCamera?() }
            }
            return
        }
        guard let asset = asset(at: indexPath.item) else { return }
        if configuration.selectionLimit == 1 {
            toggleSelection(of: asset)
        } else {
            openPreview(at: indexPath.item)
        }
    }

    // MARK: Gestures

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === outsideTap, let sheet = navigationController?.view else { return true }
        return presentedViewController == nil && !sheet.bounds.contains(touch.location(in: sheet))
    }

    /// The sheet's own dimming tap recognizes alongside the outside tap.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        gestureRecognizer === outsideTap
    }

    // MARK: Presentation

    func presentationControllerDidAttemptToDismiss(_: UIPresentationController) {
        confirmDiscardingSelection { [weak self] in self?.close() }
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        onDismiss?()
    }

    // MARK: Library changes

    nonisolated func photoLibraryDidChange(_: PHChange) {
        Task { @MainActor [weak self] in self?.reloadLibrary() }
    }

    /// A local send failure returns the unsent selection to its owner with its caption intact.
    func prepareForRetry(assetIDs: Set<String>, captionWasSent: Bool) {
        selection.removeAll { !assetIDs.contains($0.localIdentifier) }
        if selection.isEmpty { displayMode = .all }
        if captionWasSent {
            caption = AttributedString()
            panel.setCommentText(caption)
        }
        isClosing = false
        reloadGrid()
        selectionChanged()
    }

    func updateCaptionClient(_ client: TDLibClient) {
        captionClient = client
        panel.updateCommentClient(client)
    }

    // MARK: Views

    private func configureTitle() {
        var titleConfiguration = UIButton.Configuration.plain()
        titleConfiguration.imagePlacement = .trailing
        titleConfiguration.imagePadding = 4
        titleConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 11,
            weight: .bold,
        )
        titleConfiguration.baseForegroundColor = .label
        titleConfiguration.contentInsets = .zero
        titleButton.configuration = titleConfiguration
        titleButton.addTarget(self, action: #selector(titlePressed), for: .touchUpInside)
        navigationItem.titleView = titleButton
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .systemBackground
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.alwaysBounceVertical = true
        // The bar and the panel draw their own blur; the system's edge effects would wash the panel's badge out.
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(
            MediaPickerGridCell.self,
            forCellWithReuseIdentifier: MediaPickerGridCell.reuseIdentifier,
        )
        collectionView.register(
            MediaPickerCameraCell.self,
            forCellWithReuseIdentifier: MediaPickerCameraCell.reuseIdentifier,
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configurePlaceholder() {
        placeholderView.isHidden = true
        placeholderView.onOpenSettings = { Self.openSettings() }
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderView)
        NSLayoutConstraint.activate([
            placeholderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            placeholderView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AttachmentPanelView.barHeight,
            ),
        ])
    }

    private func configurePanel() {
        panel.configureTabs(configuration.tabs)
        // A standalone single item picker (MediaPickerScreen outside AttachmentController) has no panel.
        panel.isHidden = configuration.tabs.isEmpty && configuration.selectionLimit == 1
        panel.onSelectTab = { [weak self] tab in self?.selectTab(tab) }
        panel.onSend = { [weak self] in self?.send() }
        panel.onSendOptions = { [weak self] source, gesture in self?.showSendOptions(from: source, tracking: gesture) }
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        let restingTop = panel.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -AttachmentPanelView.barHeight,
        )
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            restingTop,
        ])
        panel.configureKeyboardLayout(in: view, restingTop: restingTop)
        if configuration.allowsCaptionEditing {
            panel.configureCommentInput(caption, client: captionClient) { [weak self] in self?.caption = $0 }
            panel.onBeginCommentEditing = { [weak self] in
                guard let sheet = self?.navigationController?.sheetPresentationController else { return }
                sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
            }
        }
    }

    private func scrollGridToTop() {
        collectionView.setContentOffset(
            CGPoint(x: -collectionView.adjustedContentInset.left, y: -collectionView.adjustedContentInset.top),
            animated: false,
        )
    }

    // MARK: Library

    private func reloadLibrary() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if hasLibraryAccess {
            if !observesLibrary {
                observesLibrary = true
                PHPhotoLibrary.shared().register(self)
            }
            let options = PHFetchOptions()
            options.predicate = mediaPredicate
            if let shownAlbum = album,
               let current = PHAssetCollection.fetchAssetCollections(
                   withLocalIdentifiers: [shownAlbum.localIdentifier],
                   options: nil,
               )
               .firstObject
            {
                album = current
                fetchResult = PHAsset.fetchAssets(in: current, options: options)
            } else {
                album = nil
                fetchResult = PHAssetCollection.fetchAssetCollections(
                    with: .smartAlbum,
                    subtype: .smartAlbumUserLibrary,
                    options: nil,
                )
                .firstObject
                .map { PHAsset.fetchAssets(in: $0, options: options) }
            }
            refreshSelection()
        } else {
            fetchResult = nil
        }
        if selection.isEmpty { displayMode = .all }
        updateAccessViews()
        reloadGrid()
        selectionChanged()
    }

    /// Picked items keep their order; ones deleted from the library leave the selection.
    private func refreshSelection() {
        guard !selection.isEmpty else { return }
        let identifiers = selection.map(\.localIdentifier)
        var current = [String: PHAsset]()
        PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil).enumerateObjects { asset, _, _ in
            current[asset.localIdentifier] = asset
        }
        selection = identifiers.compactMap { current[$0] }
        spoilerAssetIDs.formIntersection(current.keys)
    }

    /// MediaPickerPlaceholderNode when the library is denied or the chat bans media, and MediaPickerManageNode above
    /// the grid while access is limited.
    private func updateAccessViews() {
        if !allowsMedia {
            placeholderView.configure(
                title: nil,
                text: L10n.telegram("Conversation.DefaultRestrictedMedia"),
                showsSettings: false,
            )
            placeholderView.isHidden = false
        } else if authorization == .denied || authorization == .restricted {
            placeholderView.configure(
                title: L10n.telegram("Attachment.MediaAccessTitle"),
                text: L10n.telegram("Attachment.MediaAccessText"),
                showsSettings: true,
            )
            placeholderView.isHidden = false
        } else {
            placeholderView.isHidden = true
        }
        collectionView.isHidden = !hasLibraryAccess
        let showsBanner = hasLibraryAccess && authorization == .limited && displayMode == .all
        if showsBanner != (manageBanner.superview != nil) {
            if showsBanner {
                collectionView.addSubview(manageBanner)
            } else {
                manageBanner.removeFromSuperview()
            }
            view.setNeedsLayout()
        }
    }

    private func reloadGrid() {
        gridLayout.hasCameraTile = showsCameraTile
        collectionView.reloadData()
    }

    private func asset(at item: Int) -> PHAsset? {
        switch displayMode {
        case .selected:
            return selection[safe: item]
        case .all:
            guard let fetchResult else { return nil }
            let index = item - (showsCameraTile ? 1 : 0)
            guard index >= 0, index < fetchResult.count else { return nil }
            // MediaPickerScreen shows Recents newest first (`reversed`).
            return fetchResult.object(at: album == nil ? fetchResult.count - 1 - index : index)
        }
    }

    private func loadThumbnail(_ asset: PHAsset, into cell: MediaPickerGridCell) {
        let identifier = asset.localIdentifier
        guard cell.representedAssetIdentifier != identifier else { return }
        cell.representedAssetIdentifier = identifier
        if let thumbnail = photoEdits[identifier]?.thumbnail ?? videoEditThumbnails[identifier] {
            cell.imageView.image = thumbnail
            return
        }
        cell.imageView.image = nil
        imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize == .zero ? CGSize(width: 256, height: 256) : thumbnailSize,
            contentMode: .aspectFill,
            options: thumbnailOptions,
        ) { [weak cell] image, _ in
            guard let cell, cell.representedAssetIdentifier == identifier, let image else { return }
            cell.imageView.image = image
        }
    }

    // MARK: Selection

    private func toggleSelection(of asset: PHAsset) {
        let identifier = asset.localIdentifier
        if let index = selection.firstIndex(where: { $0.localIdentifier == identifier }) {
            selection.remove(at: index)
            spoilerAssetIDs.remove(identifier)
        } else {
            guard selection.count < configuration.selectionLimit else {
                // MediaPickerScreen's `selectionLimitExceeded`.
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            selection.append(asset)
        }
        if displayMode == .selected {
            if selection.isEmpty {
                displayMode = .all
                updateAccessViews()
            }
            reloadGrid()
        } else {
            updateVisibleSelection()
        }
        selectionChanged()
        // A single item picker hands the item over at once.
        if configuration.selectionLimit == 1, !selection.isEmpty { send() }
    }

    private func configureSelection(of cell: MediaPickerGridCell, assetID: String) {
        let index = selection.firstIndex { $0.localIdentifier == assetID }
        cell.configureSelection(
            number: index.map { $0 + 1 },
            hasSpoiler: index != nil && spoilerAssetIDs.contains(assetID),
        )
    }

    private func updateVisibleSelection() {
        for cell in collectionView.visibleCells {
            guard let gridCell = cell as? MediaPickerGridCell,
                  let identifier = gridCell.representedAssetIdentifier else { continue }
            configureSelection(of: gridCell, assetID: identifier)
        }
    }

    private func selectionChanged() {
        // The timer is a single photo's or video's.
        if selection.count != 1 { selfDestructTimer = nil }
        navigationController?.isModalInPresentation = !selection.isEmpty && !isClosing
        updateNavigation()
        panel.update(selectionCount: selection.count, caption: String(caption.characters))
    }

    // MARK: Navigation

    /// MediaPickerScreen's glass bar: Close, or Back from the picked items; the picked count in a pill of its own in
    /// the accent color, which shows them; the album as the title; More while items are picked, with the Live button
    /// left of it while a Live Photo is.
    private func updateNavigation() {
        let leading: UIBarButtonItem
        if displayMode == .selected {
            leading = UIBarButtonItem(
                image: UIImage(systemName: "chevron.left"),
                style: .plain,
                target: self,
                action: #selector(showAllPressed),
            )
            leading.accessibilityLabel = L10n.telegram("Common.Back")
        } else {
            leading = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                style: .plain,
                target: self,
                action: #selector(cancelPressed),
            )
            leading.accessibilityLabel = L10n.telegram("Common.Cancel")
        }
        var leftItems = [leading]
        if !selection.isEmpty, displayMode == .all {
            selectedButton.configure(count: selection.count)
            let selectedItem = UIBarButtonItem(customView: selectedButton)
            selectedItem.style = .prominent
            selectedItem.tintColor = .systemBlue
            leftItems.append(selectedItem)
        }
        navigationItem.leftBarButtonItems = leftItems
        var rightItems = [UIBarButtonItem]()
        if !selection.isEmpty {
            rightItems.append(UIBarButtonItem(customView: moreButton))
            if configuration.showsLivePhotos, selection.contains(where: { $0.mediaSubtypes.contains(.photoLive) }) {
                rightItems.append(makeLivePhotoItem())
            }
        }
        navigationItem.rightBarButtonItems = rightItems
        updateTitle()
    }

    private func updateTitle() {
        let text: String
        let switchesAlbums = hasLibraryAccess && displayMode == .all
        text =
            if !hasLibraryAccess {
                L10n.telegram("Attachment.Gallery")
            } else if displayMode == .selected {
                ""
            } else {
                album?.localizedTitle ?? L10n.telegram("MediaPicker.Recents")
            }
        var titleConfiguration = titleButton.configuration ?? .plain()
        var attributes = AttributeContainer()
        attributes.font = UIFont.preferredFont(forTextStyle: .headline)
        titleConfiguration.attributedTitle = AttributedString(text, attributes: attributes)
        if let subtitle = configuration.subtitle, hasLibraryAccess, displayMode == .all {
            var subtitleAttributes = AttributeContainer()
            subtitleAttributes.font = UIFont.preferredFont(forTextStyle: .caption1)
            subtitleAttributes.foregroundColor = UIColor.secondaryLabel
            titleConfiguration.attributedSubtitle = AttributedString(subtitle, attributes: subtitleAttributes)
            titleConfiguration.titleAlignment = .center
        } else {
            titleConfiguration.attributedSubtitle = nil
        }
        titleConfiguration.image = switchesAlbums ? UIImage(systemName: "chevron.down") : nil
        titleButton.configuration = titleConfiguration
        titleButton.isUserInteractionEnabled = switchesAlbums
        titleButton.accessibilityLabel = text
        titleButton.accessibilityTraits = switchesAlbums ? .button : .header
    }

    @objc private func cancelPressed() {
        confirmDiscardingSelection { [weak self] in self?.close() }
    }

    /// A tap above the sheet closes it as Close does, asking first while items are picked: the sheet's own dimming
    /// tap closes it only while it is not modal.
    private func installOutsideTap() {
        guard outsideTap == nil, let container = navigationController?.presentationController?.containerView
        else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(outsideTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        container.addGestureRecognizer(tap)
        outsideTap = tap
    }

    @objc private func outsideTapped() {
        guard !isClosing, let navigation = navigationController, navigation.isModalInPresentation,
              !navigation.isBeingDismissed
        else { return }
        cancelPressed()
    }

    /// MediaPickerScreen's groups as a menu under the title: My Albums, then Media Types, each with its key item and
    /// count; choosing one shows it from the top.
    @objc private func titlePressed() {
        guard hasLibraryAccess, displayMode == .all else { return }
        let imageManager = imageManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fetched = MediaPickerAlbum.fetchSections()
            let albums = fetched.albums + fetched.mediaTypes
            let thumbnails = albums.map { Self.albumThumbnail($0, imageManager: imageManager) }
            DispatchQueue.main.async {
                self?.presentAlbumMenu(albums, thumbnails: thumbnails, mediaTypesStart: fetched.albums.count)
            }
        }
    }

    private func presentAlbumMenu(_ albums: [MediaPickerAlbum], thumbnails: [UIImage?], mediaTypesStart: Int) {
        guard !albums.isEmpty, titleButton.window != nil, presentedViewController == nil else { return }
        let selectedID = album?.localIdentifier
        let actions = albums.enumerated().map { index, item in
            var action = TelegramContextMenuAction(
                title: item.title,
                image: thumbnails[index],
                startsNewSection: index == mediaTypesStart,
            ) { [weak self] in
                guard let self else { return }
                album = item.isRecents ? nil : item.collection
                reloadLibrary()
                scrollGridToTop()
            }
            let isSelected = item.isRecents ? selectedID == nil : item.collection.localIdentifier == selectedID
            action.secondLine = (isSelected ? "✓ \(item.count)" : "\(item.count)", false)
            return action
        }
        presentTelegramContextMenu(sourceView: titleButton, actions: actions, presentationStyle: .sourceMorph)
    }

    @objc private func showSelectedPressed() {
        guard !selection.isEmpty else { return }
        displayMode = .selected
        updateAccessViews()
        reloadGrid()
        scrollGridToTop()
        updateNavigation()
    }

    @objc private func showAllPressed() {
        displayMode = .all
        updateAccessViews()
        reloadGrid()
        updateNavigation()
    }

    // MARK: Preview

    /// MediaPickerScreen's preview of the grid's items from the tapped one, zooming out of its thumbnail; a swipe
    /// down zooms it back into the grid, scrolled to the item shown last.
    private func openPreview(at item: Int) {
        guard presentedViewController == nil, !isClosing else { return }
        let count: Int
        let assetAt: (Int) -> PHAsset?
        let start: Int
        switch displayMode {
        case .selected:
            let items = selection
            count = items.count
            assetAt = { items[safe: $0] }
            start = item
        case .all:
            guard let result = fetchResult else { return }
            let reversed = album == nil
            count = result.count
            assetAt = { index in
                guard index >= 0, index < result.count else { return nil }
                return result.object(at: reversed ? result.count - 1 - index : index)
            }
            start = item - (showsCameraTile ? 1 : 0)
        }
        let preview = MediaPickerPreviewViewController(
            count: count,
            startIndex: start,
            imageManager: imageManager,
            assetAt: assetAt,
        )
        preview.selectionNumber = { [weak self] asset in
            self?.selection.firstIndex { $0.localIdentifier == asset.localIdentifier }.map { $0 + 1 }
        }
        preview.selectionCount = { [weak self] in self?.selection.count ?? 0 }
        preview.onToggle = { [weak self] asset in self?.toggleSelection(of: asset) }
        preview.onSend = { [weak self] asset in
            guard let self else { return }
            if selection.isEmpty { toggleSelection(of: asset) }
            send()
        }
        preview.onShow = { [weak self] asset in self?.revealGridItem(of: asset) }
        let options = UIViewController.Transition.ZoomOptions()
        options.interactiveDismissShouldBegin = { [weak preview] _ in preview?.allowsInteractiveDismiss ?? true }
        options.alignmentRectProvider = { [weak preview] _ in preview?.currentMediaFrame ?? .zero }
        preview.preferredTransition = .zoom(options: options) { [weak self, weak preview] _ in
            guard let self, !isClosing, let asset = preview?.currentAsset else { return nil }
            return gridCell(of: asset)?.imageView
        }
        present(preview, animated: true)
    }

    private func gridCell(of asset: PHAsset) -> MediaPickerGridCell? {
        collectionView.visibleCells
            .lazy
            .compactMap { $0 as? MediaPickerGridCell }
            .first { $0.representedAssetIdentifier == asset.localIdentifier }
    }

    /// Scrolls the grid to `asset` when it is out of view, so the preview zooms back into it.
    private func revealGridItem(of asset: PHAsset) {
        guard gridCell(of: asset) == nil else { return }
        let item: Int
        switch displayMode {
        case .selected:
            guard let index = selection.firstIndex(where: { $0.localIdentifier == asset.localIdentifier })
            else { return }
            item = index
        case .all:
            guard let result = fetchResult else { return }
            let index = result.index(of: asset)
            guard index != NSNotFound else { return }
            item = (album == nil ? result.count - 1 - index : index) + (showsCameraTile ? 1 : 0)
        }
        guard item < collectionView.numberOfItems(inSection: 0) else { return }
        collectionView.scrollToItem(at: IndexPath(item: item, section: 0), at: .centeredVertically, animated: false)
        collectionView.layoutIfNeeded()
    }

    // MARK: Menus

    /// MediaPickerScreen's More menu: Send as File(s) without spoilers, Send in Standard Quality (photos go in high
    /// quality otherwise), Send Without Grouping for several items, then Move Caption with a caption and the spoiler
    /// outside secret chats. The timer and the video quality, which Telegram sets in the preview's toolbar, join them:
    /// the timer for one photo or video in a private chat, the quality with videos picked.
    @objc private func morePressed() {
        let count = selection.count
        guard count > 0 else { return }
        let hasSpoilers = selection.contains { spoilerAssetIDs.contains($0.localIdentifier) }
        let hasGeneric = selection.contains { !spoilerAssetIDs.contains($0.localIdentifier) }
        var actions = [TelegramContextMenuAction]()
        if !hasSpoilers, configuration.allowsSendAsFile {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(count > 1 ? "Attachment.SendAsFiles" : "Attachment.SendAsFile"),
                image: UIImage(systemName: "doc"),
            ) { [weak self] in
                self?.send(mode: .files)
            })
        }
        if selectionHasPhoto {
            actions.append(TelegramContextMenuAction(
                title: L10n.betterTG("Attachment.SendInSd"),
                image: MediaPickerQualityIcon.image(highQuality: false),
            ) { [weak self] in
                self?.isHighQuality = false
                self?.send()
            })
        }
        if count > 1 {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Attachment.SendWithoutGrouping"),
                image: UIImage(systemName: "rectangle.split.2x2"),
            ) { [weak self] in
                self?.send(mode: .separately)
            })
        }
        var options = [TelegramContextMenuAction]()
        if hasCaption {
            options.append(captionPositionAction())
        }
        if configuration.allowsSpoiler {
            options.append(TelegramContextMenuAction(
                title: L10n.telegram(hasGeneric ? "Attachment.EnableSpoiler" : "Attachment.DisableSpoiler"),
                image: UIImage(systemName: hasGeneric ? "eye.slash" : "eye"),
            ) { [weak self] in
                self?.setSpoiler(hasGeneric)
            })
        }
        if configuration.allowsViewOnce, count == 1, let item = selection.first {
            options.append(timerAction(isVideo: item.mediaType == .video))
        }
        if let maximumVideoPreset {
            options.append(videoQualityAction(maximum: maximumVideoPreset))
        }
        if !actions.isEmpty, !options.isEmpty {
            options[0].startsNewSection = true
        }
        presentTelegramContextMenu(
            sourceView: moreButton,
            actions: actions + options,
            presentationStyle: .sourceMorph,
        )
    }

    /// ChatSendMessageContextScreen for the attachment: Move Caption with a caption, Send Without Sound and Send When
    /// Online outside Saved Messages, and Schedule Message or Set a Reminder. A media timer turns off scheduling
    /// (`hasTimers`).
    private func showSendOptions(from source: UIView, tracking gesture: UIGestureRecognizer) {
        guard !selection.isEmpty, !isClosing else { return }
        var actions = [TelegramContextMenuAction]()
        if hasCaption {
            actions.append(captionPositionAction())
        }
        var timingActions = AttachmentSendCapabilities(
            isReminders: configuration.isReminders,
            canSchedule: configuration.canSchedule && selfDestructTimer == nil,
            canSendWhenOnline: configuration.canSendWhenOnline,
        ).menuActions { [weak self] timing in self?.send(timing: timing) }
        if !actions.isEmpty, !timingActions.isEmpty {
            timingActions[0].startsNewSection = true
        }
        actions += timingActions
        presentTelegramContextMenu(
            sourceView: source,
            actions: actions,
            tracking: gesture,
            presentationStyle: .sourceMorph,
        )
    }

    private func captionPositionAction() -> TelegramContextMenuAction {
        TelegramContextMenuAction(
            title: L10n.telegram(captionIsAbove
                ? "Chat.SendMessageMenu.MoveCaptionDown"
                : "Chat.SendMessageMenu.MoveCaptionUp"),
            image: UIImage(systemName: captionIsAbove ? "text.below.photo" : "text.above.photo"),
        ) { [weak self] in
            self?.captionIsAbove.toggle()
        }
    }

    /// LegacyMessageInputPanel's presentTimeoutSetup for one item: View Once, 3, 10 or 30 seconds after opening, or
    /// Do Not Delete, with the current one checked. A change shows the tooltip naming what the item will do.
    private func timerAction(isVideo: Bool) -> TelegramContextMenuAction {
        let current = selfDestructTimer
        let choices: [(MediaSelfDestructTimer?, String)] =
            [(.viewOnce, L10n.telegram("MediaPicker.Timer.ViewOnce"))]
                + MediaSelfDestructTimer.secondsValues.map {
                    (.seconds($0), L10n.telegramPlural("MediaPicker.Timer.Seconds", count: $0))
                }
                + [(nil, L10n.telegram("MediaPicker.Timer.DoNotDelete"))]
        return TelegramContextMenuAction(
            title: L10n.telegram("Media.SendWithTimer"),
            image: UIImage(systemName: current == nil ? "timer" : "flame"),
            children: choices.map { timer, title in
                TelegramContextMenuAction(
                    title: title,
                    image: timer == current ? UIImage(systemName: "checkmark") : nil,
                ) { [weak self] in
                    self?.setSelfDestructTimer(timer, isVideo: isVideo)
                }
            },
        )
    }

    /// presentTimeoutTooltip.
    private func setSelfDestructTimer(_ timer: MediaSelfDestructTimer?, isVideo: Bool) {
        guard timer != selfDestructTimer else { return }
        selfDestructTimer = timer
        let kind = isVideo ? "Video" : "Photo"
        switch timer {
        case .viewOnce:
            showToast(L10n.telegram("MediaPicker.Timer.\(kind).ViewOnceTooltip"))
        case .seconds(let seconds):
            showToast(L10n.telegram("MediaPicker.Timer.\(kind).TimerTooltip", String(seconds)))
        case nil:
            showToast(L10n.telegram("MediaPicker.Timer.\(kind).KeepTooltip"))
        }
    }

    /// TGPhotoQualityController for the picked videos: 240p up to the best their sizes allow, with the current one
    /// checked. The choice covers this sheet's videos, each capped at its own size.
    private func videoQualityAction(maximum: VideoSendPreset) -> TelegramContextMenuAction {
        let current = min(videoPreset, maximum)
        return TelegramContextMenuAction(
            title: L10n.telegram("PhotoEditor.QualityTool") + " · " + current.title,
            image: UIImage(systemName: "film"),
            children: VideoSendPreset.allCases.filter { $0 <= maximum }.map { preset in
                TelegramContextMenuAction(
                    title: preset.title,
                    image: preset == current ? UIImage(systemName: "checkmark") : nil,
                ) { [weak self] in
                    self?.videoPreset = preset
                    self?.choseVideoPreset = true
                }
            },
        )
    }

    private func setSpoiler(_ hasSpoiler: Bool) {
        for asset in selection {
            if hasSpoiler {
                spoilerAssetIDs.insert(asset.localIdentifier)
            } else {
                spoilerAssetIDs.remove(asset.localIdentifier)
            }
        }
        updateVisibleSelection()
    }

    /// MediaPickerScreen's limited access menu: Select More Photos or Change Settings.
    private func showLimitedAccessOptions(from source: UIView) {
        presentTelegramContextMenu(
            sourceView: source,
            actions: [
                TelegramContextMenuAction(
                    title: L10n.telegram("Media.LimitedAccessSelectMore"),
                    image: UIImage(systemName: "photo.badge.plus"),
                ) { [weak self] in
                    guard let self else { return }
                    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
                },
                TelegramContextMenuAction(
                    title: L10n.telegram("Media.LimitedAccessChangeSettings"),
                    image: UIImage(systemName: "gear"),
                ) {
                    Self.openSettings()
                },
            ],
            presentationStyle: .sourceMorph,
        )
    }

    private func showToast(_ text: String) {
        TelegramUndoToast.show(text: text, in: view, bottomInset: AttachmentPanelView.barHeight + 8, undo: nil)
    }

    // MARK: Closing

    private func selectTab(_ tab: AttachmentSheetTab) {
        guard tab != .gallery else { return }
        if switchesTabsInPlace {
            onSelectTab?(tab)
            return
        }
        let onSelectTab = onSelectTab
        close { onSelectTab?(tab) }
    }

    private func send(
        mode: ComposerMediaSendMode = .grouped,
        timing: AttachmentSendTiming = .now,
        schedulingState: TDNativeMessageSchedulingState? = nil,
    ) {
        guard !selection.isEmpty, !isClosing else { return }
        if timing == .schedule, schedulingState == nil {
            ScheduleMessagePickerViewController.present(
                from: self, isReminder: configuration.isReminders,
                showsSendWhenOnline: configuration.canSendWhenOnline,
            ) { [weak self] state in self?.send(mode: mode, timing: timing, schedulingState: state) }
            return
        }
        if let text = panel.finishCommentEditing() { caption = text }
        let request = AttachmentMediaSendRequest(
            assets: selection,
            cropAdjustments: photoEdits.mapValues(\.adjustments),
            // A video sent as a file goes as it is (`LegacyMediaPickers`' `.passthrough`).
            videoEdits: mode == .files ? [:] : videoEdits,
            livePhotoAssetIDs: mode == .files
                ? []
                : Set(selection.filter { livePhotoMode(of: $0) == true }.map(\.localIdentifier)),
            mode: mode,
            timing: timing,
            highQualityPhotos: isHighQuality,
            spoilerAssetIDs: spoilerAssetIDs,
            selfDestructTimer: selection.count == 1 && mode != .files ? selfDestructTimer : nil,
            videoPreset: videoPreset,
            captionIsAbove: captionIsAbove && hasCaption,
            caption: caption,
            schedulingState: schedulingState,
        )
        close { [self] in onSend?(request) }
    }

    /// MediaPickerScreen's `requestDismiss`: picked items are dropped only after Cancel Selection is confirmed.
    private func confirmDiscardingSelection(then action: @escaping () -> Void) {
        guard !selection.isEmpty else {
            action()
            return
        }
        let alert = UIAlertController(
            title: nil,
            message: L10n.telegram("Attachment.CancelSelectionAlertText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Attachment.CancelSelectionAlertNo"), style: .cancel))
        alert
            .addAction(UIAlertAction(title: L10n.telegram("Attachment.CancelSelectionAlertYes"), style: .default) { _ in
                action()
            })
        present(alert, animated: true)
    }

    private func close(then completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        let onDismiss = onDismiss
        let presented: UIViewController = navigationController ?? self
        presented.isModalInPresentation = false
        presented.dismiss(animated: true) { [self] in
            (presented as? TelegramNavigationController)?.releaseChrome(of: self)
            if let outsideTap { outsideTap.view?.removeGestureRecognizer(outsideTap) }
            outsideTap = nil
            onDismiss?()
            completion?()
        }
    }

    // MARK: Photo editing

    /// Telegram edits a picked photo or video in its preview's editor (LegacyMediaPickerGallery); holding one here
    /// offers Edit, which opens the crop tool on a photo and the trim and mute on a video. A Live Photo also offers
    /// its preview's Live and Live Off.
    private func configurePhotoEditing() {
        let press = ContextMenuPressGestureRecognizer(target: self, action: #selector(photoLongPressed(_:)))
        press.pressedViewProvider = { [weak self] gesture in
            guard let self, let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
                  let mediaType = asset(at: path.item)?.mediaType, mediaType == .image || mediaType == .video
            else { return nil }
            return collectionView.cellForItem(at: path)
        }
        collectionView.addGestureRecognizer(press)
    }

    @objc private func photoLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, !isClosing,
              let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
              let asset = asset(at: path.item), asset.mediaType == .image || asset.mediaType == .video,
              let cell = collectionView.cellForItem(at: path)
        else { return }
        let isVideo = asset.mediaType == .video
        let edit = TelegramContextMenuAction(
            title: L10n.telegram("Common.Edit"),
            image: UIImage(systemName: isVideo ? "scissors" : "crop"),
        ) { [weak self] in
            if isVideo {
                self?.editVideo(asset)
            } else {
                self?.editPhoto(asset)
            }
        }
        var actions = [edit]
        if let isLive = livePhotoMode(of: asset) {
            actions.append(livePhotoModeAction(for: asset, isLive: isLive))
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, tracking: gesture, presentationStyle: .menuOnly)
    }

    private func editPhoto(_ asset: PHAsset) {
        let adjustments = photoEdits[asset.localIdentifier]?.adjustments
        PhotoCropViewController.loadImage(for: asset) { [weak self] image in
            guard let self, let image, !isClosing, presentedViewController == nil else { return }
            let editor = PhotoCropViewController(
                image: image,
                adjustments: adjustments,
                fullPixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
            )
            editor.onDone = { [weak self] edit in self?.finishEditing(asset, edit: edit) }
            present(editor, animated: true)
        }
    }

    /// LegacyMediaPickerGallery's `willFinishEditingItem`: the crop stays with the photo and picks it; the grid shows
    /// the cropped thumbnail (`didFinishEditingItem`).
    private func finishEditing(_ asset: PHAsset, edit: PhotoCropEdit?) {
        let identifier = asset.localIdentifier
        photoEdits[identifier] = edit
        if edit != nil, !selection.contains(where: { $0.localIdentifier == identifier }) {
            toggleSelection(of: asset)
        }
        reloadThumbnail(of: asset)
    }

    /// Shows the asset's current thumbnail in its visible cells.
    private func reloadThumbnail(of asset: PHAsset) {
        let identifier = asset.localIdentifier
        for cell in collectionView.visibleCells {
            guard let gridCell = cell as? MediaPickerGridCell,
                  gridCell.representedAssetIdentifier == identifier else { continue }
            gridCell.representedAssetIdentifier = nil
            loadThumbnail(asset, into: gridCell)
        }
    }

    /// TGMediaPickerGalleryVideoItemView's editing, which doesn't trim slow-motion videos
    /// (`itemIsHighFramerateVideo`) and chooses a cover where the chat takes one.
    private func editVideo(_ asset: PHAsset) {
        let adjustments = videoEdits[asset.localIdentifier]
        VideoEditViewController.loadAsset(for: asset) { [weak self] video in
            guard let self, let video, !isClosing, presentedViewController == nil else { return }
            let editor = VideoEditViewController(
                asset: video,
                adjustments: adjustments,
                allowsTrimming: !asset.mediaSubtypes.contains(.videoHighFrameRate),
                allowsCover: configuration.allowsVideoCover,
            )
            editor.onDone = { [weak self] edit in self?.finishEditing(asset, videoEdit: edit, video: video) }
            present(editor, animated: true)
        }
    }

    /// The trim, mute and crop stay with the video while the sheet is open, and an edit picks it. The grid shows the
    /// edited frame once it is read, as it shows a cropped photo.
    private func finishEditing(_ asset: PHAsset, videoEdit: VideoEditAdjustments?, video: AVAsset) {
        let identifier = asset.localIdentifier
        videoEdits[identifier] = videoEdit
        if videoEdit != nil, !selection.contains(where: { $0.localIdentifier == identifier }) {
            toggleSelection(of: asset)
        }
        guard let videoEdit, VideoEditThumbnail.isNeeded(for: videoEdit) else {
            if videoEditThumbnails.removeValue(forKey: identifier) != nil {
                reloadThumbnail(of: asset)
            }
            return
        }
        Task { [weak self] in
            let thumbnail = await VideoEditThumbnail.make(for: videoEdit, of: video)
            guard let self, videoEdits[identifier] == videoEdit else { return }
            videoEditThumbnails[identifier] = thumbnail
            reloadThumbnail(of: asset)
        }
    }

    // MARK: Live Photos

    /// `TGMediaAssetsResolvedLivePhotoMode` where the chat takes Live Photos: whether a Live Photo goes live, by its
    /// own mode or else the bar's; nil for any other item.
    private func livePhotoMode(of asset: PHAsset) -> Bool? {
        guard configuration.showsLivePhotos, asset.mediaType == .image, asset.mediaSubtypes.contains(.photoLive)
        else { return nil }
        return livePhotoModes[asset.localIdentifier] ?? forcesLivePhotos
    }

    /// MediaPickerScreen's Live button for the picked Live Photos.
    private func makeLivePhotoItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: forcesLivePhotos ? "livephoto" : "livephoto.slash"),
            style: .plain,
            target: self,
            action: #selector(livePhotoPressed),
        )
        item.accessibilityLabel = L10n.telegram("Message.LivePhoto")
        item.accessibilityValue = L10n.telegram(forcesLivePhotos ? "VoiceOver.Common.On" : "VoiceOver.Common.Off")
        return item
    }

    /// The Live button's `setForceLivePhotoEnabled`: every Live Photo without its own mode goes live or as a still,
    /// with the tooltip.
    @objc private func livePhotoPressed() {
        forcesLivePhotos.toggle()
        updateNavigation()
        updateVisibleLivePhotos()
        showToast(L10n.telegram(forcesLivePhotos
                ? "MediaPicker.LivePhoto.Tooltip.Live"
                : "MediaPicker.LivePhoto.Tooltip.LiveOff"))
    }

    /// The gallery preview's LivePhotoButton for one Live Photo: its mode as the title, and its menu's Live and Live
    /// Off. Loop and Bounce aren't offered.
    private func livePhotoModeAction(for asset: PHAsset, isLive: Bool) -> TelegramContextMenuAction {
        TelegramContextMenuAction(
            title: L10n.telegram(isLive ? "MediaPicker.LivePhoto.Live" : "MediaPicker.LivePhoto.LiveOff"),
            image: UIImage(systemName: isLive ? "livephoto" : "livephoto.slash"),
            children: [true, false].map { mode in
                TelegramContextMenuAction(
                    title: L10n.telegram(mode ? "MediaPicker.LivePhoto.Live" : "MediaPicker.LivePhoto.LiveOff"),
                    image: UIImage(systemName: mode ? "livephoto" : "livephoto.slash"),
                ) { [weak self] in
                    self?.setLivePhotoMode(mode, of: asset)
                }
            },
        )
    }

    /// TGMediaPickerGalleryInterfaceView's `livePhotoModeUpdated`: the photo keeps the mode and is picked, with
    /// LivePhotoButton's tooltip when the mode changes.
    private func setLivePhotoMode(_ isLive: Bool, of asset: PHAsset) {
        let identifier = asset.localIdentifier
        let changed = livePhotoMode(of: asset) != isLive
        livePhotoModes[identifier] = isLive
        updateVisibleLivePhotos()
        if !selection.contains(where: { $0.localIdentifier == identifier }) {
            toggleSelection(of: asset)
        }
        guard changed, !isClosing else { return }
        showToast(L10n.telegram(isLive
                ? "MediaPicker.LivePhoto.Tooltip.Live"
                : "MediaPicker.LivePhoto.Tooltip.LiveOff"))
    }

    /// MediaPickerGridItem's `updateLivePhotoMode` for the visible Live Photos.
    private func updateVisibleLivePhotos() {
        for path in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: path) as? MediaPickerGridCell,
                  let asset = asset(at: path.item),
                  let isLive = livePhotoMode(of: asset)
            else { continue }
            cell.configure(asset: asset, livePhoto: isLive)
        }
    }
}

// MARK: - MediaPickerSelectedButton

/// MediaPickerScreen's glass SelectedButtonNode: a check and the picked count in white, which shows the picked items.
/// The bar draws its pill as glass in the accent color.
final class MediaPickerSelectedButton: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override var intrinsicContentSize: CGSize {
        // SelectedButtonNode's glass size: the count's width, 28 pt and 10 pt more.
        CGSize(width: ceil(countLabel.intrinsicContentSize.width) + 38, height: 44)
    }

    private let iconView = UIImageView(image: UIImage(systemName: "checkmark"))
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        countLabel.textColor = .white
        for subview in [iconView, countLabel] {
            subview.isUserInteractionEnabled = false
            addSubview(subview)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func sizeThatFits(_: CGSize) -> CGSize {
        intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The 24 pt check at 6 pt and the count at 27 pt, centred in the pill's height.
        iconView.frame = CGRect(x: 6, y: (bounds.height - 24) / 2, width: 24, height: 24)
        let countWidth = ceil(countLabel.intrinsicContentSize.width)
        countLabel.frame = CGRect(x: 27, y: 0, width: countWidth, height: bounds.height)
    }

    func configure(count: Int) {
        countLabel.text = String(max(1, count))
        accessibilityLabel = L10n.telegramPlural("Attachment.SelectedMedia", count: count)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

// MARK: - MediaPickerQualityIcon

/// MediaPickerPhotoToolbarView's `generateQualityIcon` for photos: HD or SD in a rounded frame.
enum MediaPickerQualityIcon {
    static func image(highQuality: Bool) -> UIImage {
        let label = (highQuality ? "HD" : "SD") as NSString
        let size = CGSize(width: 24, height: 24)
        let lineWidth: CGFloat = 1.67
        return UIGraphicsImageRenderer(size: size)
            .image { _ in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 7)
                path.lineWidth = lineWidth
                UIColor.black.setStroke()
                path.stroke()
                let base = UIFont.systemFont(ofSize: 11, weight: .bold)
                let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 11) } ?? base
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.black,
                    .kern: -0.7,
                ]
                let textSize = label.size(withAttributes: attributes)
                label.draw(
                    at: CGPoint(x: floor((size.width - textSize.width) / 2) + 0.5, y: 5),
                    withAttributes: attributes,
                )
            }
            .withRenderingMode(.alwaysTemplate)
    }
}

// MARK: - AttachmentPanelContent

/// A tab whose selection drives the sheet's shared panel, as AttachmentMediaPickerContext does in Telegram.
@MainActor protocol AttachmentPanelContent: AnyObject {
    func configureAttachmentPanel(_ panel: AttachmentPanelView)
}

// MARK: - AttachmentPanelView

/// AttachmentPanel: the buttons for the chat's attachments with the shown one current. With items picked the send
/// panel (AttachmentTextInputPanelNode) takes their place: the composer's caption and Send with the picked count,
/// which holds for the send options.
@MainActor final class AttachmentPanelView: UIView {
    /// Telegram 13's attachment tab bar: a 58 pt glass capsule with 4 pt above and below it.
    static let barHeight: CGFloat = 66

    var onSelectTab: ((AttachmentSheetTab) -> Void)?
    var onSend: (() -> Void)?
    var onSendOptions: ((UIView, UIGestureRecognizer) -> Void)?
    var onBeginCommentEditing: (() -> Void)?

    private let background = TelegramBarBackgroundView(edge: .bottom)
    /// AttachmentPanel's buttons in Telegram 13's glass tab bar, scrolling sideways once more than fit.
    private let tabsScroll = AttachmentTabStrip()
    private let sendRow = UIView()
    private let sendGlass = UIVisualEffectView()
    private let captionLabel = UILabel()
    private var commentInput: FormattedTextView?
    private var sendRowHeight: NSLayoutConstraint!
    private var restingTop: NSLayoutConstraint?
    private var restingTopOffset: CGFloat = 0
    private var keyboardTop: NSLayoutConstraint?
    private let sendButton = UIButton(type: .system)
    /// BadgeNode on Send's corner: the picked count, 18 pt high and 8 pt wider than its text.
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private var isSelecting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        tabsScroll.onSelect = { [weak self] tab in self?.onSelectTab?(tab) }
        captionLabel.font = .preferredFont(forTextStyle: .subheadline)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = .secondaryLabel
        captionLabel.lineBreakMode = .byTruncatingTail
        var sendConfiguration = UIButton.Configuration.filled()
        sendConfiguration.image = UIImage(systemName: "arrow.up")
        sendConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .bold,
        )
        sendConfiguration.cornerStyle = .capsule
        sendConfiguration.contentInsets = .zero
        sendButton.configuration = sendConfiguration
        sendButton.accessibilityLabel = L10n.telegram("MediaPicker.Send")
        sendButton.addTarget(self, action: #selector(sendPressed), for: .touchUpInside)
        sendButton.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self,
            action: #selector(sendLongPressed(_:)),
        ))
        let badgeFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        badgeLabel.font = badgeFont.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 13) }
            ?? badgeFont
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.layer.cornerRadius = 9
        badgeView.isUserInteractionEnabled = false
        badgeView.addSubview(badgeLabel)
        sendRow.alpha = 0
        sendRow.isHidden = true
        sendGlass.translatesAutoresizingMaskIntoConstraints = false
        sendGlass.cornerConfiguration = .corners(radius: .fixed(20))
        sendRow.addSubview(sendGlass)
        for subview in [captionLabel, sendButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            sendGlass.contentView.addSubview(subview)
        }
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        sendRow.addSubview(badgeView)
        for subview in [background, tabsScroll, sendRow] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        self.sendRowHeight = sendRow.heightAnchor.constraint(equalToConstant: Self.barHeight)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            tabsScroll.topAnchor.constraint(equalTo: topAnchor),
            tabsScroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            tabsScroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            tabsScroll.heightAnchor.constraint(equalToConstant: Self.barHeight),
            sendRow.topAnchor.constraint(equalTo: topAnchor),
            sendRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            sendRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            sendRowHeight,
            sendGlass.leadingAnchor.constraint(equalTo: sendRow.leadingAnchor, constant: 8),
            sendGlass.trailingAnchor.constraint(equalTo: sendRow.trailingAnchor, constant: -8),
            sendGlass.topAnchor.constraint(equalTo: sendRow.topAnchor, constant: 13),
            sendGlass.bottomAnchor.constraint(equalTo: sendRow.bottomAnchor, constant: -13),
            captionLabel.leadingAnchor.constraint(equalTo: sendRow.leadingAnchor, constant: 16),
            captionLabel.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -12),
            captionLabel.centerYAnchor.constraint(equalTo: sendRow.centerYAnchor),
            // Telegram 13's glass Send: a 40 pt circle 6 pt further in than the panel's edge.
            sendButton.trailingAnchor.constraint(equalTo: sendRow.trailingAnchor, constant: -16),
            sendButton.bottomAnchor.constraint(equalTo: sendRow.bottomAnchor, constant: -13),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),
            // The badge's corner sits just outside Send's, over its rim.
            badgeView.trailingAnchor.constraint(equalTo: sendButton.trailingAnchor, constant: 4),
            badgeView.topAnchor.constraint(equalTo: sendButton.topAnchor, constant: -4),
            badgeView.heightAnchor.constraint(equalToConstant: 18),
            badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            badgeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: badgeView.leadingAnchor, constant: 4),
            badgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeView.trailingAnchor, constant: -4),
        ])
        updateBadgeColor()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.updateBadgeColor()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentHeight()
    }

    /// AttachmentController keeps one panel under whichever tab's controller it shows. A controller shown in the
    /// attachment sheet in place of the gallery gets its own panel with its tab current, over its bottom edge, and
    /// its safe area ends above the buttons.
    @discardableResult static func install(
        in controller: UIViewController,
        tabs: [AttachmentSheetTab],
        current: AttachmentSheetTab,
        onSelectTab: @escaping (AttachmentSheetTab) -> Void,
    ) -> AttachmentPanelView {
        controller.loadViewIfNeeded()
        let panel = AttachmentPanelView()
        panel.configureTabs(tabs, current: current)
        panel.onSelectTab = onSelectTab
        controller.additionalSafeAreaInsets.bottom += barHeight
        panel.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(panel)
        let restingTop = panel.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor)
        panel.configureKeyboardLayout(in: controller.view, restingTop: restingTop)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            restingTop,
        ])
        let content = (controller as? AttachmentSheetTabContainer)?.content ?? controller
        (content as? AttachmentPanelContent)?.configureAttachmentPanel(panel)
        return panel
    }

    /// AttachmentPanel edits the active picker's caption. It does not write into the chat's compose draft.
    func configureKeyboardLayout(in host: UIView, restingTop: NSLayoutConstraint) {
        self.restingTop = restingTop
        restingTopOffset = restingTop.constant
        host.keyboardLayoutGuide.usesBottomSafeArea = false
        keyboardTop = topAnchor.constraint(
            lessThanOrEqualTo: host.keyboardLayoutGuide.topAnchor, constant: -Self.barHeight,
        )
    }

    func configureCommentInput(
        _ value: AttributedString,
        client: TDLibClient?,
        onChange: @escaping (AttributedString) -> Void,
    ) {
        guard commentInput == nil else { return }
        let input = FormattedTextView(placeholder: L10n.telegram("Conversation.InputTextPlaceholderComment"))
        input.accessibilityIdentifier = "attachment-comment"
        input.minimumHeight = 40
        input.maximumHeight = 160
        input.customEmojiClient = client
        input.setAttributedText(value)
        input.onBeginEditing = { [weak self] in self?.onBeginCommentEditing?() }
        input.onTextChange = { [weak self] text in
            onChange(text)
            self?.updateContentHeight()
        }
        input.translatesAutoresizingMaskIntoConstraints = false
        sendGlass.contentView.addSubview(input)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: sendGlass.contentView.leadingAnchor, constant: 8),
            input.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            input.topAnchor.constraint(equalTo: sendGlass.contentView.topAnchor),
            input.bottomAnchor.constraint(equalTo: sendGlass.contentView.bottomAnchor),
        ])
        commentInput = input
        captionLabel.isHidden = true
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        sendGlass.effect = effect
        restingTop?.isActive = false
        // The keyboard guide has its own optional geometry constraints. Resting below it must yield to those.
        restingTop?.priority = .defaultLow
        restingTop?.isActive = true
        updateContentHeight()
    }

    func configureTabs(_ tabs: [AttachmentSheetTab], current: AttachmentSheetTab = .gallery) {
        tabsScroll.configure(tabs: tabs, current: current)
    }

    func finishCommentEditing() -> AttributedString? {
        guard let input = commentInput else { return nil }
        input.unmarkText()
        input.resignFirstResponder()
        return ComposerText.value(input.attributedText)
    }

    func setCommentText(_ value: AttributedString) {
        commentInput?.setAttributedText(value)
        updateContentHeight()
    }

    func updateCommentClient(_ client: TDLibClient) {
        commentInput?.customEmojiClient = client
    }

    func update(selectionCount: Int, caption: String) {
        badgeLabel.text = String(selectionCount)
        captionLabel.text = caption
        sendButton.accessibilityValue = String(selectionCount)
        let selecting = selectionCount > 0
        sendRow.isUserInteractionEnabled = selecting
        sendRow.accessibilityElementsHidden = !selecting
        tabsScroll.isUserInteractionEnabled = !selecting
        tabsScroll.accessibilityElementsHidden = selecting
        guard selecting != isSelecting else { return }
        isSelecting = selecting
        if !selecting { commentInput?.resignFirstResponder() }
        updateContentHeight()
        tabsScroll.isHidden = false
        sendRow.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.tabsScroll.alpha = selecting ? 0 : 1
            self.sendRow.alpha = selecting ? 1 : 0
        } completion: { _ in
            guard self.isSelecting == selecting else { return }
            self.tabsScroll.isHidden = selecting
            self.sendRow.isHidden = !selecting
        }
    }

    private func updateContentHeight() {
        let height = isSelecting
            ? max(Self.barHeight, (commentInput?.intrinsicContentSize.height ?? 40) + 26)
            : Self.barHeight
        if abs(sendRowHeight.constant - height) > 0.5 {
            sendRowHeight.constant = height
            restingTop?.constant = restingTopOffset - (height - Self.barHeight)
            keyboardTop?.constant = -height
            superview?.setNeedsLayout()
        }
        keyboardTop?.isActive = commentInput != nil && isSelecting
    }

    /// The badge's red on its layer: in a sheet on iOS 26 a view's dynamic background color draws see-through.
    private func updateBadgeColor() {
        badgeView.layer.backgroundColor = UIColor.systemRed.resolvedColor(with: traitCollection).cgColor
    }

    @objc private func sendPressed() {
        guard isSelecting else { return }
        onSend?()
    }

    @objc private func sendLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard isSelecting, gesture.state == .began else { return }
        onSendOptions?(sendButton, gesture)
    }
}

// MARK: - AttachmentSheetTabContainer

/// A tab's screen whose root view scrolls (a table view controller), held in a plain view so the panel pins to the
/// sheet's edges instead of the scrolling content. The bar shows the screen's own title and items.
final class AttachmentSheetTabContainer: UIViewController {
    override var navigationItem: UINavigationItem { content.navigationItem }

    let content: UIViewController

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = content.view.backgroundColor ?? .systemBackground
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)
    }
}

// MARK: - AttachmentTabContentView

/// An AttachmentPanel tab's look: its icon over its 10 pt title in `color`.
private final class AttachmentTabContentView: UIView {
    init(tab: AttachmentSheetTab, color: UIColor, isCurrent: Bool) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let iconView: UIView
        if case .app(let bot) = tab {
            iconView = AttachmentBotIconView(bot: bot, symbolName: tab.symbolName, color: color)
            iconView.widthAnchor.constraint(equalToConstant: 26).isActive = true
        } else {
            let imageView = UIImageView(image: UIImage(systemName: tab.symbolName))
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            imageView.tintColor = color
            imageView.contentMode = .center
            iconView = imageView
        }
        let titleLabel = UILabel()
        titleLabel.text = tab.title
        titleLabel.font = .systemFont(ofSize: 10, weight: isCurrent ? .semibold : .medium)
        titleLabel.textColor = color
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 26),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }
}

// MARK: - AttachmentTabStrip

/// Telegram 13's attachment tab bar: the tabs in an interactive glass capsule, the current one under UIKit's liquid
/// lens (`LiquidLens`), as the folder strip draws it. A tap lifts the lens and carries it to the tapped tab, which
/// then opens; a hold lifts it under the finger, which carries it and opens the tab it is let go over, as UIKit's tab
/// bar does. Tabs past the capsule's width scroll.
private final class AttachmentTabStrip: UIView, UIGestureRecognizerDelegate {
    // MARK: Private

    private static let capsuleHeight: CGFloat = 58
    private static let sideInset: CGFloat = 16
    private static let endInset: CGFloat = 4
    private static let minimumTabWidth: CGFloat = 60
    private static let selectionTint = UIColor.label.withAlphaComponent(0.08)
    private static let springDuration: TimeInterval = 0.4
    /// The least time the lens stays lifted after a tap, so that it crosses the bar as a lens.
    private static let liftDuration: TimeInterval = 0.3
    /// How far a finger on a scrolling bar moves before its touch is a scroll rather than a tap.
    private static let tapSlop: CGFloat = 10

    // MARK: Internal

    var onSelect: ((AttachmentSheetTab) -> Void)?

    private let liftedContainer = UIView()
    private let capsule = UIVisualEffectView()
    private let scroll = UIScrollView()
    private let stripView = UIView()
    /// The tabs in the accent colour over the resting tint, shown inside the lens.
    private let selectedTabsView = UIView()
    private let restingTintView = UIView()
    /// The tabs as they rest, cut away under the lens.
    private let tabsView = UIView()
    private let buttonsView = UIView()
    private let selectionView = UIVisualEffectView()
    private var lens: LiquidLens?
    private var tabs = [AttachmentSheetTab]()
    private var currentIndex = 0
    private var needsSelectionReveal = true
    private var lastViewportWidth: CGFloat = 0
    private var tabWidth: CGFloat = 0
    private var isSelecting = false
    private var heldIndex: Int?
    /// The touched tab's frame, whether the lens lifted to follow the finger, and when the touch began. On a bar
    /// that scrolls, the finger scrolls it and a tap selects, as in Telegram's AttachmentPanel.
    private var drag: (frame: CGRect, isLifted: Bool, time: CFTimeInterval)?
    private lazy var tabGesture: LiquidLensTabRecognizer = {
        let gesture = LiquidLensTabRecognizer(target: self, action: #selector(stripTouched(_:)))
        gesture.delegate = self
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(liftedContainer)
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        capsule.effect = effect
        capsule.cornerConfiguration = .capsule()
        capsule.clipsToBounds = true
        liftedContainer.addSubview(capsule)
        scroll.showsHorizontalScrollIndicator = false
        scroll.scrollsToTop = false
        scroll.delaysContentTouches = false
        scroll.alwaysBounceHorizontal = false
        scroll.addGestureRecognizer(tabGesture)
        capsule.contentView.addSubview(scroll)
        scroll.addSubview(stripView)
        for layer in [selectedTabsView, tabsView, buttonsView] {
            stripView.addSubview(layer)
        }
        selectedTabsView.isUserInteractionEnabled = false
        selectedTabsView.accessibilityElementsHidden = true
        tabsView.isUserInteractionEnabled = false
        tabsView.accessibilityElementsHidden = true
        restingTintView.backgroundColor = Self.selectionTint
        selectedTabsView.addSubview(restingTintView)
        self.lens = LiquidLens(liftedContainer: liftedContainer, liftedContent: selectedTabsView, punchout: tabsView)
        if lens == nil {
            selectedTabsView.removeFromSuperview()
            let selection = UIGlassEffect(style: .regular)
            selection.tintColor = Self.selectionTint
            selectionView.effect = selection
            selectionView.isUserInteractionEnabled = false
            selectionView.clipsToBounds = true
            stripView.insertSubview(selectionView, belowSubview: tabsView)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        liftedContainer.frame = bounds
        capsule.frame = CGRect(
            x: Self.sideInset,
            y: (bounds.height - Self.capsuleHeight) / 2,
            width: max(0, bounds.width - Self.sideInset * 2),
            height: Self.capsuleHeight,
        )
        scroll.frame = capsule.contentView.bounds
        let available = scroll.bounds.width - Self.endInset * 2
        let width = tabs.isEmpty ? 0 : max(Self.minimumTabWidth, available / CGFloat(tabs.count))
        let stripWidth = width * CGFloat(tabs.count) + Self.endInset * 2
        scroll.contentSize = CGSize(width: stripWidth, height: scroll.bounds.height)
        scroll.isScrollEnabled = stripWidth - scroll.bounds.width > 1
        stripView.frame = CGRect(x: 0, y: 0, width: stripWidth, height: scroll.bounds.height)
        for layer in [selectedTabsView, tabsView, buttonsView] {
            layer.frame = stripView.bounds
        }
        let contentViews = [selectedTabsView, tabsView].map { $0.subviews.filter { $0 !== restingTintView } }
        for index in tabs.indices {
            let frame = tabFrame(at: index, width: width)
            for views in contentViews where views.indices.contains(index) {
                views[index].frame = frame
            }
            if buttonsView.subviews.indices.contains(index) { buttonsView.subviews[index].frame = frame }
        }
        tabWidth = width
        // Each replacement owns a fresh strip. Reveal its selected tab after real geometry is available, as
        // AttachmentPanel scrolls the chosen button into view with 35 pt of context. Ordinary scrolls stay put.
        if scroll.bounds.width > 0, tabs.indices.contains(currentIndex),
           needsSelectionReveal || lastViewportWidth != scroll.bounds.width
        {
            needsSelectionReveal = false
            lastViewportWidth = scroll.bounds.width
            scroll.scrollRectToVisible(
                tabFrame(at: currentIndex, width: width).insetBy(dx: -35, dy: 0),
                animated: false,
            )
        }
        restingTintView.frame = selectedTabsView.bounds
        placeSelection(at: currentIndex, isLifted: false, animated: false)
    }

    /// A tab that opened in the sheet's place leaves the lens on it; back in the sheet the lens rests on the
    /// current tab again.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !isSelecting, drag == nil else { return }
        placeSelection(at: currentIndex, isLifted: false, animated: false)
    }

    func configure(tabs: [AttachmentSheetTab], current: AttachmentSheetTab) {
        self.tabs = tabs
        currentIndex = tabs.firstIndex(of: current) ?? 0
        needsSelectionReveal = true
        for view in selectedTabsView.subviews + tabsView.subviews + buttonsView.subviews
            where view !== restingTintView
        {
            view.removeFromSuperview()
        }
        for (index, tab) in tabs.enumerated() {
            let isCurrent = index == currentIndex
            selectedTabsView.addSubview(AttachmentTabContentView(tab: tab, color: .tintColor, isCurrent: true))
            // The lens tints the current tab; where it rests or travels, the punched-out copy shows through.
            tabsView.addSubview(AttachmentTabContentView(tab: tab, color: .secondaryLabel, isCurrent: false))
            let button = UIButton(type: .custom)
            button.accessibilityLabel = tab.title
            button.accessibilityTraits = isCurrent ? [.button, .selected] : .button
            button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            buttonsView.addSubview(button)
        }
        setNeedsLayout()
    }

    /// The touch leaves the bar's scrolling running.
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        recognizer === tabGesture
    }

    private func tabFrame(at index: Int, width: CGFloat) -> CGRect {
        CGRect(x: Self.endInset + CGFloat(index) * width, y: 0, width: width, height: stripView.bounds.height)
            .insetBy(dx: 0, dy: Self.endInset)
    }

    private func placeSelection(at index: Int, isLifted: Bool, animated: Bool) {
        guard tabs.indices.contains(index), tabWidth > 0 else { return }
        placeLens(tabFrame(at: index, width: tabWidth), isLifted: isLifted, animated: animated)
    }

    private func placeLens(_ frame: CGRect, isLifted: Bool, animated: Bool) {
        if let lens {
            restingTintView.alpha = isLifted ? 0 : 1
            lens.place(frame, isLifted: isLifted, springDuration: animated ? Self.springDuration : nil)
            return
        }
        let changes = {
            self.selectionView.frame = frame
            self.selectionView.layer.cornerRadius = frame.height / 2
        }
        if animated {
            UIView.animate(springDuration: Self.springDuration, bounce: 0.15, animations: changes)
        } else {
            changes()
        }
    }

    /// Telegram's AttachmentPanel: where the bar fits, a touch lifts the lens onto the touched tab, the lens follows
    /// the finger, and the tab under it opens as it lands when the finger lets go. Where the bar scrolls, the lens
    /// stays and a tap carries it to the tapped tab.
    @objc private func stripTouched(_ gesture: LiquidLensTabRecognizer) {
        guard tabWidth > 0, !tabs.isEmpty, !isSelecting else { return }
        switch gesture.state {
        case .began:
            let x = gesture.location(in: stripView).x
            let index = min(max(0, Int((x - Self.endInset) / tabWidth)), tabs.count - 1)
            let frame = tabFrame(at: index, width: tabWidth)
            let isLifted = !scroll.isScrollEnabled
            drag = (frame, isLifted, CACurrentMediaTime())
            heldIndex = index
            if isLifted { placeLens(frame, isLifted: true, animated: true) }
        case .changed:
            guard let drag else { return }
            guard drag.isLifted else {
                if abs(gesture.translation.x) > Self.tapSlop || abs(gesture.translation.y) > Self.tapSlop {
                    self.drag = nil
                    heldIndex = nil
                }
                return
            }
            let maxX = max(Self.endInset, stripView.bounds.width - Self.endInset - tabWidth)
            let x = min(max(drag.frame.minX + gesture.translation.x, Self.endInset), maxX)
            let frame = drag.frame.offsetBy(dx: x - drag.frame.minX, dy: 0)
            let index = min(max(0, Int((frame.midX - Self.endInset) / tabWidth)), tabs.count - 1)
            if index != heldIndex {
                UISelectionFeedbackGenerator().selectionChanged()
                heldIndex = index
            }
            placeLens(frame, isLifted: true, animated: false)
        case .ended:
            guard let drag, let index = heldIndex else { return }
            self.drag = nil
            heldIndex = nil
            // A tap, also one that lifted the lens, opens the tab as a tap on it does; a held lens lands where it is.
            let isTap = !drag.isLifted || CACurrentMediaTime() - drag.time < Self.liftDuration
            guard index != currentIndex else {
                if drag.isLifted { placeSelection(at: currentIndex, isLifted: false, animated: true) }
                if isTap { onSelect?(tabs[index]) }
                return
            }
            guard !isTap else {
                select(index)
                return
            }
            isSelecting = true
            placeSelection(at: index, isLifted: false, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                isSelecting = false
                onSelect?(tabs[index])
            }
        default:
            let wasLifted = drag?.isLifted == true
            drag = nil
            heldIndex = nil
            if wasLifted { placeSelection(at: currentIndex, isLifted: false, animated: true) }
        }
    }

    /// The lens lifts, carries the selection to the tapped tab and settles; the tab opens as it lands.
    private func select(_ index: Int) {
        guard !isSelecting, tabs.indices.contains(index) else { return }
        guard index != currentIndex else {
            onSelect?(tabs[index])
            return
        }
        isSelecting = true
        UISelectionFeedbackGenerator().selectionChanged()
        scroll.scrollRectToVisible(tabFrame(at: index, width: tabWidth), animated: true)
        placeSelection(at: index, isLifted: true, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.liftDuration) { [weak self] in
            guard let self else { return }
            placeSelection(at: index, isLifted: false, animated: true)
            isSelecting = false
            onSelect?(tabs[index])
        }
    }
}

// MARK: - AttachmentBotIconView

/// AttachmentPanel's app icon in the panel's tint: the bot's `iOSAnimated` TGS held at its first frame
/// (AnimatedStickerComponent with `isAnimating` only while selected), or its side menu PNG; a generic glyph until
/// either is on disk.
private final class AttachmentBotIconView: UIView {
    private let imageView = UIImageView()
    private let color: UIColor

    init(bot: AttachmentMenuBotButton, symbolName: String, color: UIColor) {
        self.color = color
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        imageView.tintColor = color
        if let path = bot.imageIconPath, let image = UIImage(contentsOfFile: path) {
            imageView.image = image.withRenderingMode(.alwaysTemplate)
            imageView.contentMode = .scaleAspectFit
        } else {
            imageView.image = UIImage(systemName: symbolName)
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            imageView.contentMode = .center
        }
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        guard let path = bot.animatedIconPath else { return }
        Task { [weak self] in
            let animation = await TGSAnimationRepository.animation(at: path)
            guard let self, let animation else { return }
            show(animation)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    private func show(_ animation: LottieAnimation) {
        let animationView = LottieAnimationView(configuration: LottieConfiguration(
            renderingEngine: .automatic,
            decodingStrategy: .legacyCodable,
        ))
        animationView.contentMode = .scaleAspectFit
        animationView.isUserInteractionEnabled = false
        animationView.animation = animation
        animationView.setValueProvider(
            ColorValueProvider(color.resolvedColor(with: traitCollection).lottieColorValue),
            keypath: AnimationKeypath(keypath: "**.Color"),
        )
        animationView.currentProgress = 0
        animationView.forceDisplayUpdate()
        animationView.frame = bounds
        animationView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(animationView)
        imageView.isHidden = true
    }
}
