// ProfileAvatarGalleryViewController.swift

import AVFoundation
import Combine
import ImageIO
import TDLibKit
import UIKit

// MARK: - ProfileAvatarGalleryItem

struct ProfileAvatarGalleryItem: Hashable {
    let addedDate: Int
    let animation: AnimatedChatPhoto?
    let id: Int64
    let minithumbnail: Minithumbnail?
    let photo: Photo

    var representativeFileID: Int? {
        photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height })?.photo.id
    }

    init(photo: ChatPhoto) {
        self.addedDate = photo.addedDate
        self.animation = photo.animation
        self.id = photo.id
        self.minithumbnail = photo.minithumbnail
        self.photo = Photo(
            hasStickers: photo.sticker != nil,
            minithumbnail: photo.minithumbnail,
            sizes: photo.sizes,
        )
    }

    init?(profilePhoto: ProfilePhoto?) {
        guard let profilePhoto, profilePhoto.id != 0 else { return nil }
        self.addedDate = 0
        self.animation = nil
        self.id = profilePhoto.id
        self.minithumbnail = profilePhoto.minithumbnail
        self.photo = Photo(
            hasStickers: false,
            minithumbnail: profilePhoto.minithumbnail,
            sizes: [PhotoSize(
                height: 640,
                photo: profilePhoto.big,
                progressiveSizes: [],
                type: "i",
                width: 640,
            )],
        )
    }

    init?(current photo: ChatPhotoInfo?) {
        guard let photo else { return nil }
        self.addedDate = 0
        self.animation = nil
        self.id = -Int64(photo.big.id) - 1
        self.minithumbnail = photo.minithumbnail
        self.photo = Photo(
            hasStickers: false,
            minithumbnail: photo.minithumbnail,
            sizes: [PhotoSize(
                height: 640,
                photo: photo.big,
                progressiveSizes: [],
                type: "i",
                width: 640,
            )],
        )
    }
}

// MARK: - ProfileAvatarGalleryViewController

@MainActor final class ProfileAvatarGalleryViewController: UIViewController, UICollectionViewDataSource,
    UICollectionViewDelegate
{
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    var contextIsCurrent: (() -> Bool)?
    var onRequestMoreItems: (() -> Void)?

    fileprivate let transitionSource: MediaGalleryTransitionTarget?
    fileprivate let transitionSourceProvider: ((Int64) -> MediaGalleryTransitionTarget?)?

    private let accountID: UUID
    private let client: TDLibClient
    private var items: [ProfileAvatarGalleryItem]
    private var selectedIndex: Int
    private var totalCount: Int
    private var paginationRequestedItemCount: Int?
    private var paginationMutationInProgress = false
    private var pendingReconciliation: (items: [ProfileAvatarGalleryItem], totalCount: Int)?
    private var didSetInitialPosition = false
    private let footer = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let closeButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var transitionController: ProfileAvatarGalleryTransitionController?

    fileprivate var selectedItemID: Int64? {
        items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
    }

    init(
        accountID: UUID,
        client: TDLibClient,
        items: [ProfileAvatarGalleryItem],
        selection: Int64,
        totalCount: Int,
        transitionSource: MediaGalleryTransitionTarget?,
        transitionSourceProvider: ((Int64) -> MediaGalleryTransitionTarget?)?,
    ) {
        self.accountID = accountID
        self.client = client
        self.items = Self.deduplicated(items)
        self.totalCount = max(totalCount, self.items.count)
        self.selectedIndex = self.items.firstIndex(where: { $0.id == selection }) ?? 0
        self.transitionSource = transitionSource
        self.transitionSourceProvider = transitionSourceProvider
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
        let transitionController = ProfileAvatarGalleryTransitionController()
        self.transitionController = transitionController
        transitioningDelegate = transitionController
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityViewIsModal = true
        configureCollectionView()
        configureFooter()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
           layout.itemSize != collectionView.bounds.size
        {
            layout.itemSize = collectionView.bounds.size
            layout.invalidateLayout()
        }
        guard !didSetInitialPosition, items.indices.contains(selectedIndex) else { return }
        didSetInitialPosition = true
        collectionView.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        updateCounter()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        collectionView.visibleCells
            .compactMap { $0 as? ProfileAvatarGalleryCell }
            .forEach { $0.setPlaybackVisible(false) }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator,
    ) {
        let selectedItemID = selectedItemID
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self,
                  let selectedItemID,
                  let selectedIndex = items.firstIndex(where: { $0.id == selectedItemID })
            else { return }
            self.selectedIndex = selectedIndex
            view.layoutIfNeeded()
            collectionView.scrollToItem(
                at: IndexPath(item: selectedIndex, section: 0),
                at: .centeredHorizontally,
                animated: false,
            )
            collectionView.layoutIfNeeded()
            updateCounter()
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    private static func deduplicated(_ items: [ProfileAvatarGalleryItem]) -> [ProfileAvatarGalleryItem] {
        var seen = Set<Int64>()
        return items.filter { seen.insert($0.id).inserted }
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ProfileAvatarGalleryCell.reuseIdentifier,
            for: indexPath,
        ) as? ProfileAvatarGalleryCell else { return UICollectionViewCell() }
        guard contextIsCurrent?() != false else { return cell }
        cell.configure(item: items[indexPath.item], client: client, accountID: accountID)
        return cell
    }

    func collectionView(
        _: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath,
    ) {
        (cell as? ProfileAvatarGalleryCell)?.setPlaybackVisible(indexPath.item == selectedIndex)
        requestMoreItemsIfNeeded(near: indexPath.item)
    }

    func collectionView(
        _: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt _: IndexPath,
    ) {
        (cell as? ProfileAvatarGalleryCell)?.setPlaybackVisible(false)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateSelection(from: scrollView)
        requestMoreItemsIfNeeded(near: selectedIndex)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateSelection(from: scrollView)
            requestMoreItemsIfNeeded(near: selectedIndex)
        }
    }

    func appendItems(
        _ appendedItems: [ProfileAvatarGalleryItem],
        before trailingItemID: Int64? = nil,
        totalCount: Int,
    ) {
        guard contextIsCurrent?() != false else { return }
        retryButton.isHidden = true
        let existingIDs = Set(items.map(\.id))
        let appendedItems = Self.deduplicated(appendedItems).filter { !existingIDs.contains($0.id) }
        self.totalCount = max(totalCount, items.count + appendedItems.count)
        paginationRequestedItemCount = nil
        guard !appendedItems.isEmpty else {
            updateCounter()
            requestMoreItemsIfNeeded(near: selectedIndex)
            return
        }
        let selectedItemID = selectedItemID
        let startIndex = trailingItemID.flatMap { trailingItemID in
            items.firstIndex(where: { $0.id == trailingItemID })
        } ?? items.count
        items.insert(contentsOf: appendedItems, at: startIndex)
        if let selectedItemID,
           let updatedSelectedIndex = items.firstIndex(where: { $0.id == selectedItemID })
        {
            selectedIndex = updatedSelectedIndex
        }
        paginationMutationInProgress = true
        collectionView.performBatchUpdates {
            collectionView.insertItems(at: (startIndex..<(startIndex + appendedItems.count)).map {
                IndexPath(item: $0, section: 0)
            })
        } completion: { [weak self] _ in
            guard let self else { return }
            paginationMutationInProgress = false
            if let pendingReconciliation {
                self.pendingReconciliation = nil
                reconcileItems(
                    pendingReconciliation.items,
                    totalCount: pendingReconciliation.totalCount,
                )
                return
            }
            paginationRequestedItemCount = nil
            if let selectedItemID,
               let selectedIndex = items.firstIndex(where: { $0.id == selectedItemID })
            {
                self.selectedIndex = selectedIndex
                collectionView.scrollToItem(
                    at: IndexPath(item: selectedIndex, section: 0),
                    at: .centeredHorizontally,
                    animated: false,
                )
            }
            updateCounter()
            requestMoreItemsIfNeeded(near: selectedIndex)
        }
    }

    func reconcileItems(_ updatedItems: [ProfileAvatarGalleryItem], totalCount: Int) {
        guard contextIsCurrent?() != false else { return }
        let updatedItems = Self.deduplicated(updatedItems)
        if paginationMutationInProgress {
            pendingReconciliation = (updatedItems, totalCount)
            return
        }
        guard !updatedItems.isEmpty else {
            items = []
            self.totalCount = 0
            paginationRequestedItemCount = nil
            dismiss(animated: false)
            return
        }
        let selectedItemID = selectedItemID
        items = updatedItems
        self.totalCount = max(totalCount, updatedItems.count)
        selectedIndex = selectedItemID.flatMap { selectedItemID in
            updatedItems.firstIndex(where: { $0.id == selectedItemID })
        } ?? 0
        paginationRequestedItemCount = nil
        retryButton.isHidden = true
        guard isViewLoaded else { return }
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        updateCounter()
        requestMoreItemsIfNeeded(near: selectedIndex)
    }

    func showMoreItemsRetry() {
        paginationRequestedItemCount = nil
        retryButton.isHidden = false
    }

    fileprivate func transitionContentFrame(in coordinateSpace: UIView) -> CGRect? {
        selectedCell()?.transitionContentFrame(in: coordinateSpace)
    }

    fileprivate func makeTransitionSnapshot() -> UIView? {
        selectedCell()?.makeTransitionSnapshot()
    }

    fileprivate func currentTransitionTarget() -> MediaGalleryTransitionTarget? {
        guard let selectedItemID else { return nil }
        return transitionSourceProvider?(selectedItemID)
    }

    private func makeLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        return layout
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            ProfileAvatarGalleryCell.self,
            forCellWithReuseIdentifier: ProfileAvatarGalleryCell.reuseIdentifier,
        )
        view.addSubview(collectionView)
    }

    private func configureFooter() {
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.accessibilityIdentifier = "avatar-gallery-footer"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "Close"
        closeButton.accessibilityIdentifier = "avatar-gallery-close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Retry", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retryButton.accessibilityLabel = "Retry loading profile photos"
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        counterLabel.font = .preferredFont(forTextStyle: .subheadline)
        counterLabel.adjustsFontForContentSizeCategory = true
        counterLabel.textColor = .white
        counterLabel.textAlignment = .center
        counterLabel.accessibilityIdentifier = "avatar-gallery-counter"
        footer.contentView.addSubview(closeButton)
        footer.contentView.addSubview(retryButton)
        footer.contentView.addSubview(counterLabel)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            closeButton.topAnchor.constraint(equalTo: footer.contentView.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 52),
            closeButton.heightAnchor.constraint(equalToConstant: 50),
            retryButton.topAnchor.constraint(equalTo: footer.contentView.topAnchor),
            retryButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            retryButton.heightAnchor.constraint(equalToConstant: 50),
            counterLabel.centerXAnchor.constraint(equalTo: footer.contentView.centerXAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])
    }

    private func updateSelection(from scrollView: UIScrollView) {
        guard !items.isEmpty else { return }
        let updatedIndex = min(
            items.count - 1,
            max(0, Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))),
        )
        guard updatedIndex != selectedIndex else { return }
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? ProfileAvatarGalleryCell }?
            .setPlaybackVisible(false)
        selectedIndex = updatedIndex
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? ProfileAvatarGalleryCell }?
            .setPlaybackVisible(true)
        updateCounter()
    }

    private func updateCounter() {
        counterLabel.text = totalCount > 1 ? "\(selectedIndex + 1) of \(totalCount)" : ""
        counterLabel.accessibilityLabel = counterLabel.text
    }

    private func requestMoreItemsIfNeeded(near index: Int) {
        guard index >= max(0, items.count - 3),
              !paginationMutationInProgress,
              items.count < totalCount,
              paginationRequestedItemCount != items.count,
              let onRequestMoreItems
        else { return }
        paginationRequestedItemCount = items.count
        onRequestMoreItems()
    }

    private func selectedCell() -> ProfileAvatarGalleryCell? {
        guard items.indices.contains(selectedIndex) else { return nil }
        view.layoutIfNeeded()
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        if collectionView.cellForItem(at: indexPath) == nil {
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
            collectionView.layoutIfNeeded()
        }
        return collectionView.cellForItem(at: indexPath) as? ProfileAvatarGalleryCell
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func retryLoading() {
        retryButton.isHidden = true
        paginationRequestedItemCount = nil
        onRequestMoreItems?()
    }
}

// MARK: - ProfileAvatarGalleryCell

private final class ProfileAvatarGalleryCell: UICollectionViewCell {
    static let reuseIdentifier = "ProfileAvatarGalleryCell"

    private let mediaView = ProfileAvatarMediaView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mediaView)
        NSLayoutConstraint.activate([
            mediaView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        mediaView.prepareForReuse()
    }

    func configure(item: ProfileAvatarGalleryItem, client: TDLibClient, accountID: UUID) {
        mediaView.configure(item: item, client: client, accountID: accountID)
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        mediaView.setPlaybackVisible(isVisible)
    }

    func transitionContentFrame(in coordinateSpace: UIView) -> CGRect {
        let frame = AVMakeRect(aspectRatio: CGSize(width: 1, height: 1), insideRect: contentView.bounds)
        return contentView.convert(frame, to: coordinateSpace)
    }

    func makeTransitionSnapshot() -> UIView? {
        mediaView.makeTransitionSnapshot()
    }
}

// MARK: - ProfileAvatarMediaView

private final class ProfileAvatarMediaView: UIScrollView, UIScrollViewDelegate {
    private struct Representation {
        let accountID: UUID
        let animationFileID: Int?
        let clientID: Int32
        let imageFileID: Int
        let itemID: Int64
    }

    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private let imageView = UIImageView()
    private let playerLayer = AVPlayerLayer()
    private var represented: Representation?
    private var representedClient: TDLibClient?
    private var representedItem: ProfileAvatarGalleryItem?
    private var downloadTasks = [Int: Task<Void, Never>]()
    private var downloadGenerations = [Int: UUID]()
    private var decodeTask: Task<Void, Never>?
    private var decodeGeneration: UUID?
    private var playbackEndObserver: NSObjectProtocol?
    private var player: AVPlayer?
    private var playerReadyCancellable: AnyCancellable?
    private var playbackIsVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        panGestureRecognizer.isEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        imageView.layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.isHidden = true
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
        ])
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    deinit {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = imageView.bounds
    }

    func viewForZooming(in _: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_: UIScrollView) {
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale + 0.001
    }

    func configure(item: ProfileAvatarGalleryItem, client: TDLibClient, accountID: UUID) {
        prepareForReuse()
        guard let imageSize = item.photo.sizes.max(by: {
            $0.width * $0.height < $1.width * $1.height
        }) else { return }
        representedItem = item
        representedClient = client
        represented = Representation(
            accountID: accountID,
            animationFileID: item.animation?.file.id,
            clientID: client.id,
            imageFileID: imageSize.photo.id,
            itemID: item.id,
        )
        imageView.image = item.minithumbnail.flatMap { UIImage(data: $0.data) }
        updateImage(file: imageSize.photo)
        if let animation = item.animation {
            updateAnimation(file: animation.file)
        }
        requestDownload(file: imageSize.photo, client: client)
        if let animation = item.animation {
            requestDownload(file: animation.file, client: client)
        }
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = item.addedDate > 0
            ? "Profile photo, \(ProfileAvatarDateFormatting.string(item.addedDate))"
            : "Profile photo"
    }

    func prepareForReuse() {
        setZoomScale(1, animated: false)
        panGestureRecognizer.isEnabled = false
        cancelDownloads()
        represented = nil
        representedClient = nil
        representedItem = nil
        imageView.image = nil
        player?.pause()
        player = nil
        playerReadyCancellable?.cancel()
        playerReadyCancellable = nil
        playerLayer.player = nil
        playerLayer.isHidden = true
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackIsVisible = isVisible
        if isVisible {
            resumeDownloads()
            player?.play()
        } else {
            player?.pause()
            if let timestamp = representedItem?.animation?.mainFrameTimestamp,
               timestamp.isFinite,
               timestamp >= 0
            {
                player?.seek(to: CMTime(seconds: timestamp, preferredTimescale: 600))
            }
            cancelDownloads()
        }
    }

    func makeTransitionSnapshot() -> UIView? {
        guard let image = imageView.image else { return snapshotView(afterScreenUpdates: false) }
        let snapshot = UIImageView(image: image)
        snapshot.contentMode = .scaleAspectFill
        snapshot.clipsToBounds = true
        return snapshot
    }

    private func requestDownload(file: File, client: TDLibClient) {
        guard !file.local.isDownloadingCompleted,
              downloadTasks[file.id] == nil
        else { return }
        let generation = UUID()
        downloadGenerations[file.id] = generation
        downloadTasks[file.id] = Task { [weak self] in
            let downloaded = try? await client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: true,
            )
            guard let self,
                  downloadGenerations[file.id] == generation
            else { return }
            finishDownload(fileID: file.id, generation: generation)
            guard let downloaded else { return }
            if downloaded.id == represented?.imageFileID {
                updateImage(file: downloaded)
            }
            if downloaded.id == represented?.animationFileID {
                updateAnimation(file: downloaded)
            }
        }
    }

    private func finishDownload(fileID: Int, generation: UUID) {
        guard downloadGenerations[fileID] == generation else { return }
        downloadGenerations[fileID] = nil
        downloadTasks[fileID] = nil
    }

    private func resumeDownloads() {
        guard let representedClient, let representedItem else { return }
        if let imageSize = representedItem.photo.sizes.max(by: {
            $0.width * $0.height < $1.width * $1.height
        }) {
            requestDownload(file: imageSize.photo, client: representedClient)
        }
        if let animation = representedItem.animation {
            requestDownload(file: animation.file, client: representedClient)
        }
    }

    private func cancelDownloads() {
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks = [:]
        downloadGenerations = [:]
        decodeTask?.cancel()
        decodeTask = nil
        decodeGeneration = nil
    }

    private func updateImage(file: File) {
        guard let represented,
              file.id == represented.imageFileID,
              represented.accountID == TDLib.shared.activeAccountID,
              represented.clientID == TDLib.shared.activeClient.id,
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty
        else { return }
        let key = "\(represented.accountID.uuidString):\(represented.clientID):\(file.id)" as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            imageView.image = cached
            return
        }
        let itemID = represented.itemID
        let path = file.local.path
        decodeTask?.cancel()
        let generation = UUID()
        decodeGeneration = generation
        decodeTask = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                profileAvatarDownsampledImage(at: path, maximumPixelSize: 1600)
            }.value
            guard let self,
                  decodeGeneration == generation,
                  self.represented?.itemID == itemID,
                  let image
            else { return }
            let cost = max(1, image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
            Self.imageCache.setObject(image, forKey: key, cost: cost)
            imageView.image = image
            decodeTask = nil
            decodeGeneration = nil
        }
    }

    private func updateAnimation(file: File) {
        guard let represented,
              file.id == represented.animationFileID,
              represented.accountID == TDLib.shared.activeAccountID,
              represented.clientID == TDLib.shared.activeClient.id,
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty,
              player == nil
        else { return }
        let item = AVPlayerItem(url: URL(filePath: file.local.path))
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        self.player = player
        playerLayer.player = player
        playerReadyCancellable = playerLayer.publisher(for: \.isReadyForDisplay, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player] isReady in
                guard let self, self.player === player else { return }
                playerLayer.isHidden = !isReady
            }
        if let timestamp = representedItem?.animation?.mainFrameTimestamp,
           timestamp.isFinite,
           timestamp > 0
        {
            player.seek(to: CMTime(seconds: timestamp, preferredTimescale: 600))
        }
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main,
        ) { [weak self, weak player] _ in
            player?.seek(to: .zero)
            if self?.playbackIsVisible == true {
                player?.play()
            }
        }
        if playbackIsVisible {
            player.play()
        }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / maximumZoomScale, height: bounds.height / maximumZoomScale)
            zoom(to: CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height,
            ), animated: true)
        }
    }
}

// MARK: - ProfileAvatarGalleryTransitionController

private final class ProfileAvatarGalleryTransitionController: NSObject, UIViewControllerTransitioningDelegate {
    func animationController(
        forPresented presented: UIViewController,
        presenting _: UIViewController,
        source _: UIViewController,
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        guard presented is ProfileAvatarGalleryViewController else { return nil }
        return ProfileAvatarGalleryTransitionAnimator(isPresenting: true)
    }

    func animationController(
        forDismissed dismissed: UIViewController,
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        guard dismissed is ProfileAvatarGalleryViewController else { return nil }
        return ProfileAvatarGalleryTransitionAnimator(isPresenting: false)
    }
}

// MARK: - ProfileAvatarGalleryTransitionAnimator

private final class ProfileAvatarGalleryTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    func transitionDuration(using _: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.38 }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        if isPresenting {
            present(using: transitionContext)
        } else {
            dismiss(using: transitionContext)
        }
    }

    private func present(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let gallery = transitionContext.viewController(forKey: .to) as? ProfileAvatarGalleryViewController,
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }
        let container = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: gallery)
        container.addSubview(toView)
        toView.layoutIfNeeded()
        guard let source = gallery.transitionSource,
              let snapshot = source.snapshotView,
              let sourceFrame = source.frame(in: container),
              let destinationFrame = gallery.transitionContentFrame(in: container)
        else {
            fade(appearing: toView, disappearing: nil, context: transitionContext)
            return
        }
        let sourceView = source.validatedSourceView
        let wasHidden = sourceView?.isHidden ?? false
        sourceView?.isHidden = true
        snapshot.frame = sourceFrame
        snapshot.layer.cornerRadius = source.cornerRadius
        snapshot.clipsToBounds = true
        container.addSubview(snapshot)
        toView.alpha = 0
        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            toView.alpha = 1
            snapshot.frame = destinationFrame
            snapshot.layer.cornerRadius = 0
        } completion: { _ in
            let completed = !transitionContext.transitionWasCancelled
            if source.validatedSourceView === sourceView {
                sourceView?.isHidden = wasHidden
            }
            snapshot.removeFromSuperview()
            transitionContext.completeTransition(completed)
        }
    }

    private func dismiss(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let gallery = transitionContext.viewController(forKey: .from) as? ProfileAvatarGalleryViewController,
              let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toController = transitionContext.viewController(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }
        let container = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: toController)
        container.insertSubview(toView, belowSubview: fromView)
        toView.layoutIfNeeded()
        let target = gallery.currentTransitionTarget()
        let sourceView = target?.validatedSourceView
        let sourceWasHidden = sourceView?.isHidden ?? false
        let snapshot = gallery.makeTransitionSnapshot()
        guard let target,
              let snapshot,
              let startFrame = gallery.transitionContentFrame(in: container),
              let destinationFrame = target.frame(in: container)
        else {
            fade(appearing: toView, disappearing: fromView, context: transitionContext)
            return
        }
        sourceView?.isHidden = true
        snapshot.frame = startFrame
        snapshot.layer.cornerRadius = 0
        snapshot.clipsToBounds = true
        container.addSubview(snapshot)
        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
        ) {
            fromView.alpha = 0
            snapshot.frame = destinationFrame
            snapshot.layer.cornerRadius = target.cornerRadius
        } completion: { _ in
            let completed = !transitionContext.transitionWasCancelled
            if !completed {
                fromView.alpha = 1
            }
            if target.validatedSourceView === sourceView {
                sourceView?.isHidden = sourceWasHidden
            }
            snapshot.removeFromSuperview()
            transitionContext.completeTransition(completed)
        }
    }

    private func fade(
        appearing: UIView,
        disappearing: UIView?,
        context: any UIViewControllerContextTransitioning,
    ) {
        appearing.alpha = 0
        UIView.animate(withDuration: transitionDuration(using: context)) {
            appearing.alpha = 1
            disappearing?.alpha = 0
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            if !completed {
                disappearing?.alpha = 1
            }
            context.completeTransition(completed)
        }
    }
}

// MARK: - ProfileAvatarDateFormatting

private enum ProfileAvatarDateFormatting {
    static let style = Date.FormatStyle(date: .abbreviated, time: .omitted)

    static func string(_ timestamp: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(style)
    }
}

private func profileAvatarDownsampledImage(at path: String, maximumPixelSize: Int) -> UIImage? {
    guard FileManager.default.fileExists(atPath: path),
          let source = CGImageSourceCreateWithURL(URL(filePath: path) as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
              kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
}
