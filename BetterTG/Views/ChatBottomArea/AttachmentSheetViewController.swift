// AttachmentSheetViewController.swift

import Photos
import PhotosUI
import UIKit

// MARK: - AttachmentSheetTab

/// AttachmentPanel's buttons in ChatControllerOpenAttachmentMenu's order: Gallery, File, Location, Poll and
/// Contact, each where the chat allows it. Sticker (AttachmentButtonType.sticker) opens BetterTG's emoji, sticker and
/// GIF picker, which the attach button used to offer.
enum AttachmentSheetTab {
    case gallery
    case file
    case location
    case poll
    case contact
    case sticker

    var title: String {
        switch self {
        case .gallery: L10n.telegram("Attachment.Gallery")
        case .file: L10n.telegram("Attachment.File")
        case .location: L10n.telegram("Attachment.Location")
        case .poll: L10n.telegram("Attachment.Poll")
        case .contact: L10n.telegram("Attachment.Contact")
        case .sticker: L10n.telegram("Attachment.Sticker")
        }
    }

    var symbolName: String {
        switch self {
        case .gallery: "photo.fill"
        case .file: "doc.fill"
        case .location: "location.fill"
        case .poll: "chart.bar.fill"
        case .contact: "person.crop.circle.fill"
        case .sticker: "face.smiling"
        }
    }
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
    /// Saved Messages sets reminders instead of scheduling and has no Send Silently.
    var isReminders = false
    var canSchedule = false
    var canSendWhenOnline = false
    /// The composer's text, which goes as the caption.
    var caption = ""
    var captionIsAbove = false
}

// MARK: - AttachmentMediaSendRequest

/// The picked items and how the sheet asked to send them.
struct AttachmentMediaSendRequest {
    enum Timing {
        case now
        case silently
        case whenOnline
        case schedule
    }

    let assets: [PHAsset]
    let mode: ComposerMediaSendMode
    let timing: Timing
    let highQualityPhotos: Bool
    let spoilerAssetIDs: Set<String>
    let selfDestructTimer: MediaSelfDestructTimer?
    let videoPreset: VideoSendPreset
    let captionIsAbove: Bool
}

// MARK: - AttachmentSheetViewController

/// Telegram's attachment sheet: AttachmentController with MediaPickerScreen as its Gallery. The library grid takes up
/// to 100 numbered items, with the camera tile in Recents, the albums under the title, the picked items' own view and
/// the More menu (Send as File, Send in High Quality, Send Without Grouping, Move Caption, Spoiler, the timer and the
/// video quality). The panel's buttons open the chat's other attachments; with items picked the send panel takes
/// their place, sending them with the composer's text as the caption, and holding Send offers the send options.
@MainActor final class AttachmentSheetViewController: UIViewController, UICollectionViewDataSource,
    UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIAdaptivePresentationControllerDelegate,
    PHPhotoLibraryChangeObserver
{
    // MARK: Private

    private enum DisplayMode {
        case all
        case selected
    }

    /// MediaPickerScreen's selection limit (`enableMultiselection ? 100 : 1`).
    private static let selectionLimit = 100

    // MARK: Internal

    var onSelectTab: ((AttachmentSheetTab) -> Void)?
    var onCamera: (() -> Void)?
    var onSend: ((AttachmentMediaSendRequest) -> Void)?
    var onDismiss: (() -> Void)?

    private let configuration: AttachmentSheetConfiguration
    private let imageManager = PHCachingImageManager()
    private let gridLayout = MediaPickerGridLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
    private let panel = AttachmentPanelView()
    private let placeholderView = MediaPickerPlaceholderView()
    private let manageBanner = MediaPickerManageBanner()
    private let titleButton = UIButton(type: .system)
    private let selectedButton = MediaPickerSelectedButton()
    private let moreButton = UIButton(type: .system)
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
    private var isHighQuality = UserDefaults.standard.bool(forKey: PhotoSendPreset.highQualityDefaultsKey)
    private var captionIsAbove: Bool
    private var thumbnailSize = CGSize.zero
    private var didSettleInitialOffset = false
    private var isClosing = false

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

    init(configuration: AttachmentSheetConfiguration) {
        self.configuration = configuration
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
        manageBanner.onManage = { [weak self] source in self?.showLimitedAccessOptions(from: source) }
        selectedButton.addTarget(self, action: #selector(showSelectedPressed), for: .touchUpInside)
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
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
        let insets = UIEdgeInsets(top: bannerHeight, left: 0, bottom: AttachmentPanelView.barHeight, right: 0)
        if collectionView.contentInset != insets {
            let wasAtTop = !didSettleInitialOffset
                || collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
            collectionView.contentInset = insets
            collectionView.verticalScrollIndicatorInsets = UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: AttachmentPanelView.barHeight,
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

    /// The upload default once the server's auto-download presets arrive; a quality the user picked stays.
    func setDefaultVideoPreset(_ preset: VideoSendPreset) {
        guard !choseVideoPreset else { return }
        videoPreset = preset
    }

    func makeNavigationController() -> UINavigationController {
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
        gridCell.configure(asset: asset, showsLivePhoto: configuration.showsLivePhotos)
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

    /// Telegram opens an item's preview and selects with its check; without the preview, a tap selects.
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
        toggleSelection(of: asset)
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
        panel.onSelectTab = { [weak self] tab in self?.selectTab(tab) }
        panel.onSend = { [weak self] in self?.send() }
        panel.onSendOptions = { [weak self] source in self?.showSendOptions(from: source) }
        panel.onToggleQuality = { [weak self] in self?.toggleQuality() }
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AttachmentPanelView.barHeight,
            ),
        ])
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
            guard selection.count < Self.selectionLimit else {
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
        panel.update(
            selectionCount: selection.count,
            caption: configuration.caption,
            showsQuality: selectionHasPhoto,
            isHighQuality: isHighQuality,
        )
    }

    // MARK: Navigation

    /// MediaPickerScreen's bar: Cancel, or Back from the picked items; the picked count, which shows them; the
    /// album as the title; More while items are picked.
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
                title: L10n.telegram("Common.Cancel"),
                style: .plain,
                target: self,
                action: #selector(cancelPressed),
            )
        }
        var leftItems = [leading]
        if !selection.isEmpty, displayMode == .all {
            selectedButton.configure(count: selection.count)
            leftItems.append(UIBarButtonItem(customView: selectedButton))
        }
        navigationItem.leftBarButtonItems = leftItems
        navigationItem.rightBarButtonItems = selection.isEmpty ? [] : [UIBarButtonItem(customView: moreButton)]
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
        titleConfiguration.image = switchesAlbums ? UIImage(systemName: "chevron.down") : nil
        titleButton.configuration = titleConfiguration
        titleButton.isUserInteractionEnabled = switchesAlbums
        titleButton.accessibilityLabel = text
        titleButton.accessibilityTraits = switchesAlbums ? .button : .header
    }

    @objc private func cancelPressed() {
        confirmDiscardingSelection { [weak self] in self?.close() }
    }

    /// MediaPickerScreen's groups: the albums screen; choosing one shows it from the top.
    @objc private func titlePressed() {
        guard hasLibraryAccess, displayMode == .all else { return }
        let albums = MediaPickerAlbumsViewController(imageManager: imageManager)
        albums.onSelect = { [weak self] chosen in
            guard let self else { return }
            album = chosen.isRecents ? nil : chosen.collection
            reloadLibrary()
            scrollGridToTop()
            navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(albums, animated: true)
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

    // MARK: Menus

    /// MediaPickerScreen's More menu: Send as File(s) without spoilers, Send in High Quality, Send Without Grouping
    /// for several items, then Move Caption with a caption and the spoiler outside secret chats. The timer and the
    /// video quality, which Telegram sets in the preview's toolbar, join them: the timer for one photo or video in a
    /// private chat, the quality with videos picked.
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
                title: L10n.telegram("Attachment.SendInHd"),
                image: MediaPickerQualityIcon.image(highQuality: true),
            ) { [weak self] in
                self?.isHighQuality = true
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
        if !configuration.caption.isEmpty {
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
    private func showSendOptions(from source: UIView) {
        guard !selection.isEmpty, !isClosing else { return }
        var actions = [TelegramContextMenuAction]()
        if !configuration.caption.isEmpty {
            actions.append(captionPositionAction())
        }
        let canSchedule = configuration.canSchedule && selfDestructTimer == nil
        if !configuration.isReminders {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.SendMessage.SendSilently"),
                image: UIImage(systemName: "bell.slash"),
                startsNewSection: !actions.isEmpty,
            ) { [weak self] in
                self?.send(timing: .silently)
            })
            if configuration.canSendWhenOnline, canSchedule {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.SendMessage.SendWhenOnline"),
                    image: UIImage(systemName: "person.crop.circle.badge.clock"),
                ) { [weak self] in
                    self?.send(timing: .whenOnline)
                })
            }
        }
        if canSchedule {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(configuration.isReminders
                    ? "Conversation.SendMessage.SetReminder"
                    : "Conversation.SendMessage.ScheduleMessage"),
                image: UIImage(systemName: "calendar.badge.clock"),
                startsNewSection: configuration.isReminders && !actions.isEmpty,
            ) { [weak self] in
                self?.send(timing: .schedule)
            })
        }
        presentTelegramContextMenu(sourceView: source, actions: actions, presentationStyle: .sourceMorph)
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

    /// The gallery preview's quality button (`TGMediaPickerGalleryModel`): HD and SD switch with a tooltip.
    private func toggleQuality() {
        isHighQuality.toggle()
        selectionChanged()
        showToast(L10n.telegram(isHighQuality ? "Media.PhotoHdOn" : "Media.PhotoHdOff"))
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
        let onSelectTab = onSelectTab
        close { onSelectTab?(tab) }
    }

    private func send(
        mode: ComposerMediaSendMode = .grouped,
        timing: AttachmentMediaSendRequest.Timing = .now,
    ) {
        guard !selection.isEmpty, !isClosing else { return }
        // TGMediaAssetsController keeps the photo quality for the next gallery.
        UserDefaults.standard.set(isHighQuality, forKey: PhotoSendPreset.highQualityDefaultsKey)
        let request = AttachmentMediaSendRequest(
            assets: selection,
            mode: mode,
            timing: timing,
            highQualityPhotos: isHighQuality,
            spoilerAssetIDs: spoilerAssetIDs,
            selfDestructTimer: selection.count == 1 && mode != .files ? selfDestructTimer : nil,
            videoPreset: videoPreset,
            captionIsAbove: captionIsAbove && !configuration.caption.isEmpty,
        )
        let onSend = onSend
        close { onSend?(request) }
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
        presented.dismiss(animated: true) {
            onDismiss?()
            completion?()
        }
    }
}

// MARK: - MediaPickerSelectedButton

/// MediaPickerScreen's SelectedButtonNode: a pill with a check and the picked count, which shows the picked items.
final class MediaPickerSelectedButton: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    private let pill = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "checkmark"))
    private let countLabel = UILabel()

    private var pillWidth: CGFloat {
        ceil(countLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 22)).width) + 33
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.isUserInteractionEnabled = false
        pill.layer.cornerRadius = 11
        pill.backgroundColor = tintColor
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        countLabel.font = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 14) } ?? font
        countLabel.textColor = .white
        addSubview(pill)
        pill.addSubview(iconView)
        pill.addSubview(countLabel)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func sizeThatFits(_: CGSize) -> CGSize {
        CGSize(width: pillWidth, height: 44)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = pillWidth
        pill.frame = CGRect(
            x: max(0, (bounds.width - width) / 2),
            y: (bounds.height - 22) / 2,
            width: width,
            height: 22,
        )
        iconView.frame = CGRect(x: 7, y: 0, width: 14, height: 22)
        countLabel.frame = CGRect(x: 24, y: 0, width: width - 33, height: 22)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        pill.backgroundColor = tintColor
    }

    func configure(count: Int) {
        countLabel.text = String(count)
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

// MARK: - AttachmentPanelView

/// AttachmentPanel: the buttons for the chat's attachments with Gallery current. With items picked the send panel
/// (AttachmentTextInputPanelNode) takes their place: the photo quality switch, the composer's caption and Send with
/// the picked count, which holds for the send options.
@MainActor final class AttachmentPanelView: UIView {
    static let barHeight: CGFloat = 49

    var onSelectTab: ((AttachmentSheetTab) -> Void)?
    var onSend: (() -> Void)?
    var onSendOptions: ((UIView) -> Void)?
    var onToggleQuality: (() -> Void)?

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let separator = UIView()
    private let tabsStack = UIStackView()
    private let sendRow = UIView()
    private let qualityButton = UIButton(type: .system)
    private let captionLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let badgeLabel = UILabel()
    private var isSelecting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        separator.backgroundColor = .separator
        tabsStack.axis = .horizontal
        tabsStack.distribution = .fillEqually
        captionLabel.font = .preferredFont(forTextStyle: .subheadline)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = .secondaryLabel
        captionLabel.lineBreakMode = .byTruncatingTail
        qualityButton.tintColor = .label
        qualityButton.addTarget(self, action: #selector(qualityPressed), for: .touchUpInside)
        var sendConfiguration = UIButton.Configuration.filled()
        sendConfiguration.image = UIImage(systemName: "arrow.up")
        sendConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 15,
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
        badgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.backgroundColor = .systemRed
        badgeLabel.layer.cornerRadius = 9
        badgeLabel.layer.borderWidth = 1.5
        badgeLabel.layer.borderColor = UIColor.systemBackground.cgColor
        badgeLabel.clipsToBounds = true
        badgeLabel.isUserInteractionEnabled = false
        sendRow.alpha = 0
        sendRow.isHidden = true
        for subview in [qualityButton, captionLabel, sendButton, badgeLabel] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            sendRow.addSubview(subview)
        }
        for subview in [background, separator, tabsStack, sendRow] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        let pixel = 1 / max(1, traitCollection.displayScale)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: pixel),
            tabsStack.topAnchor.constraint(equalTo: topAnchor),
            tabsStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            tabsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            tabsStack.heightAnchor.constraint(equalToConstant: Self.barHeight),
            sendRow.topAnchor.constraint(equalTo: topAnchor),
            sendRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            sendRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            sendRow.heightAnchor.constraint(equalToConstant: Self.barHeight),
            qualityButton.leadingAnchor.constraint(equalTo: sendRow.leadingAnchor, constant: 6),
            qualityButton.centerYAnchor.constraint(equalTo: sendRow.centerYAnchor),
            qualityButton.widthAnchor.constraint(equalToConstant: 44),
            qualityButton.heightAnchor.constraint(equalToConstant: 44),
            captionLabel.leadingAnchor.constraint(equalTo: qualityButton.trailingAnchor, constant: 6),
            captionLabel.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -12),
            captionLabel.centerYAnchor.constraint(equalTo: sendRow.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: sendRow.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: sendRow.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
            badgeLabel.centerXAnchor.constraint(equalTo: sendButton.trailingAnchor, constant: -3),
            badgeLabel.centerYAnchor.constraint(equalTo: sendButton.topAnchor, constant: 3),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.badgeLabel.layer.borderColor = UIColor.systemBackground
                .resolvedColor(with: self.traitCollection)
                .cgColor
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func configureTabs(_ tabs: [AttachmentSheetTab]) {
        for view in tabsStack.arrangedSubviews {
            view.removeFromSuperview()
        }
        for tab in tabs {
            let button = AttachmentTabButton(tab: tab, current: tab == .gallery)
            button.addAction(UIAction { [weak self] _ in self?.onSelectTab?(tab) }, for: .touchUpInside)
            tabsStack.addArrangedSubview(button)
        }
    }

    func update(selectionCount: Int, caption: String, showsQuality: Bool, isHighQuality: Bool) {
        badgeLabel.text = " \(selectionCount) "
        captionLabel.text = caption
        qualityButton.isHidden = !showsQuality
        qualityButton.setImage(MediaPickerQualityIcon.image(highQuality: isHighQuality), for: .normal)
        qualityButton.accessibilityLabel = L10n.telegram(isHighQuality ? "Media.PhotoHdOn" : "Media.PhotoHdOff")
        sendButton.accessibilityValue = String(selectionCount)
        let selecting = selectionCount > 0
        guard selecting != isSelecting else { return }
        isSelecting = selecting
        tabsStack.isHidden = false
        sendRow.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.tabsStack.alpha = selecting ? 0 : 1
            self.sendRow.alpha = selecting ? 1 : 0
        } completion: { _ in
            guard self.isSelecting == selecting else { return }
            self.tabsStack.isHidden = selecting
            self.sendRow.isHidden = !selecting
        }
    }

    @objc private func sendPressed() {
        onSend?()
    }

    @objc private func sendLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onSendOptions?(sendButton)
    }

    @objc private func qualityPressed() {
        onToggleQuality?()
    }
}

// MARK: - AttachmentTabButton

/// An AttachmentPanel button: its icon over its 10 pt title, in the accent color while current.
private final class AttachmentTabButton: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }

    init(tab: AttachmentSheetTab, current: Bool) {
        super.init(frame: .zero)
        let color: UIColor = current ? .tintColor : .secondaryLabel
        let iconView = UIImageView(image: UIImage(systemName: tab.symbolName))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        iconView.tintColor = color
        iconView.contentMode = .center
        let titleLabel = UILabel()
        titleLabel.text = tab.title
        titleLabel.font = .systemFont(ofSize: 10, weight: current ? .medium : .regular)
        titleLabel.textColor = color
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 26),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
        ])
        isAccessibilityElement = true
        accessibilityLabel = tab.title
        accessibilityTraits = current ? [.button, .selected] : .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }
}
