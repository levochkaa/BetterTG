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

    var largestSize: PhotoSize? {
        photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height })
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

    private init(
        addedDate: Int,
        animation: AnimatedChatPhoto?,
        id: Int64,
        minithumbnail: Minithumbnail?,
        photo: Photo,
    ) {
        self.addedDate = addedDate
        self.animation = animation
        self.id = id
        self.minithumbnail = minithumbnail
        self.photo = photo
    }

    @MainActor private static func remoteFile(_ file: File, client: TDLibClient) async -> File? {
        guard !file.remote.id.isEmpty else { return nil }
        return try? await client.send(TDNativeRequests.getRemoteFile(remoteFileId: file.remote.id, fileType: nil))
    }

    /// The same photo with the files the gallery uses, resolved by remote ID on another client of the same account.
    @MainActor func rebound(on client: TDLibClient) async -> ProfileAvatarGalleryItem? {
        guard let size = largestSize, let image = await Self.remoteFile(size.photo, client: client) else { return nil }
        var animation: AnimatedChatPhoto?
        if let current = self.animation {
            guard let file = await Self.remoteFile(current.file, client: client) else { return nil }
            animation = AnimatedChatPhoto(
                length: current.length,
                file: file,
                mainFrameTimestamp: current.mainFrameTimestamp,
            )
        }
        return ProfileAvatarGalleryItem(
            addedDate: addedDate,
            animation: animation,
            id: id,
            minithumbnail: minithumbnail,
            photo: Photo(
                hasStickers: photo.hasStickers,
                minithumbnail: photo.minithumbnail,
                sizes: [PhotoSize(
                    height: size.height,
                    photo: image,
                    progressiveSizes: size.progressiveSizes,
                    type: size.type,
                    width: size.width,
                )],
            ),
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
    var onDismissed: (() -> Void)?
    /// The gallery moved to the account's renewed client; requests for it now go through `client`.
    var onClientRenewed: (() -> Void)?

    /// The profile's client, or the same account's renewed client the gallery moved its files to.
    private(set) var client: TDLibClient

    fileprivate let transitionSource: MediaGalleryTransitionTarget?
    fileprivate let transitionSourceProvider: ((ProfileAvatarGalleryItem) -> MediaGalleryTransitionTarget?)?

    private let accountID: UUID
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
    private var clientRenewalCancellable: AnyCancellable?
    private var clientRenewalTask: Task<Void, Never>?

    fileprivate var selectedItemID: Int64? {
        items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
    }

    /// The shared demand the profile header also uses: TDLib cancels a page's download only once no view needs the
    /// file, as Telegram's gallery cancels a page's fetch when the page leaves.
    private var downloadOrigin: TDImageOrigin {
        let client = client
        let source = TdUpdateSource(accountID: accountID, clientID: client.id)
        return TDImageOrigin(
            source: source,
            backend: .init(
                download: { id in
                    guard TDLib.shared.activeUpdateSource == source else { return nil }
                    return try? await client.downloadFile(
                        fileId: id,
                        limit: 0,
                        offset: 0,
                        priority: 1,
                        synchronous: false,
                    )
                },
                cancel: { _ = try? await client.cancelDownloadFile(fileId: $0, onlyIfPending: false) },
            ),
            demand: .shared,
            currentSource: { TDLib.shared.activeUpdateSource },
            changes: TDLib.shared.activeClientChanges,
        )
    }

    init(
        accountID: UUID,
        client: TDLibClient,
        items: [ProfileAvatarGalleryItem],
        selection: Int64,
        totalCount: Int,
        transitionSource: MediaGalleryTransitionTarget?,
        transitionSourceProvider: ((ProfileAvatarGalleryItem) -> MediaGalleryTransitionTarget?)?,
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
        observeClientRenewal()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clientRenewalTask?.cancel()
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
        let cells = collectionView.visibleCells.compactMap { $0 as? ProfileAvatarGalleryCell }
        cells.forEach { $0.setPlaybackVisible(false) }
        guard isBeingDismissed else { return }
        cells.forEach { $0.setDownloadsActive(false) }
        clientRenewalTask?.cancel()
        clientRenewalTask = nil
        clientRenewalCancellable = nil
        onDismissed?()
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
        cell.configure(item: items[indexPath.item], origin: downloadOrigin)
        return cell
    }

    func collectionView(
        _: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath,
    ) {
        // Telegram's pager fetches the pages on screen; only the shown page plays.
        (cell as? ProfileAvatarGalleryCell)?.setDownloadsActive(true)
        (cell as? ProfileAvatarGalleryCell)?.setPlaybackVisible(indexPath.item == selectedIndex)
        requestMoreItemsIfNeeded(near: indexPath.item)
    }

    func collectionView(
        _: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt _: IndexPath,
    ) {
        (cell as? ProfileAvatarGalleryCell)?.setPlaybackVisible(false)
        (cell as? ProfileAvatarGalleryCell)?.setDownloadsActive(false)
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
        guard items.indices.contains(selectedIndex) else { return nil }
        return transitionSourceProvider?(items[selectedIndex])
    }

    /// TDLib's client is renewed when the app returns from the background. As the media gallery does, this one stays
    /// open for the same account and moves its photos to the renewed client.
    private func observeClientRenewal() {
        let accountID = accountID
        clientRenewalCancellable = TDLib.shared
            .readyClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, let source, source.accountID == accountID else { return }
                renewClient(source)
            }
    }

    private func renewClient(_ source: TdUpdateSource) {
        guard source.clientID != client.id,
              !isBeingDismissed,
              TDLib.shared.activeUpdateSource == source,
              TDLib.shared.activeClient.id == source.clientID,
              contextIsCurrent?() != false
        else { return }
        let renewed = TDLib.shared.activeClient
        let items = items
        clientRenewalTask?.cancel()
        clientRenewalTask = Task { [weak self] in
            // File IDs belong to one client: each photo is found again by its remote ID.
            var rebound = [Int64: ProfileAvatarGalleryItem]()
            for item in items {
                guard !Task.isCancelled else { return }
                if let item = await item.rebound(on: renewed) { rebound[item.id] = item }
            }
            guard let self, !Task.isCancelled, TDLib.shared.activeUpdateSource == source else { return }
            clientRenewalTask = nil
            adoptRenewedClient(renewed, source: source, items: rebound)
        }
    }

    private func adoptRenewedClient(
        _ renewed: TDLibClient,
        source: TdUpdateSource,
        items rebound: [Int64: ProfileAvatarGalleryItem],
        attempt: Int = 0,
    ) {
        guard !isBeingDismissed, TDLib.shared.activeUpdateSource == source, contextIsCurrent?() != false else { return }
        // An insert or a transition owns the pager; adopt the client once it settles.
        guard !paginationMutationInProgress, transitionCoordinator == nil else {
            guard attempt < 20 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.adoptRenewedClient(renewed, source: source, items: rebound, attempt: attempt + 1)
            }
            return
        }
        guard let selectedItemID, rebound[selectedItemID] != nil else {
            // The shown photo is gone from the renewed client.
            close()
            return
        }
        let previousCount = items.count
        client = renewed
        items = items.compactMap { rebound[$0.id] }
        selectedIndex = items.firstIndex { $0.id == selectedItemID } ?? 0
        totalCount = max(totalCount - (previousCount - items.count), items.count)
        // A reconciliation or page loaded through the previous client carries its file IDs.
        pendingReconciliation = nil
        paginationRequestedItemCount = nil
        onClientRenewed?()
        guard isViewLoaded else { return }
        if items.count != previousCount {
            collectionView.reloadData()
        } else {
            // Reconfiguring keeps each page's cell, so the shown photo stays on screen while it reloads.
            collectionView.reconfigureItems(at: items.indices.map { IndexPath(item: $0, section: 0) })
        }
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        updateCounter()
        requestMoreItemsIfNeeded(near: selectedIndex)
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
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.accessibilityIdentifier = "avatar-gallery-close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle(L10n.telegram("ChatImportActivity.Retry"), for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retryButton.accessibilityLabel = L10n.betterTG("Accessibility.RetryProfilePhotos")
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
        counterLabel.text = totalCount > 1 ? L10n.telegram("Items.NOfM", "\(selectedIndex + 1)", "\(totalCount)") : ""
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
        mediaView.setPlaybackVisible(false)
        mediaView.setDownloadsActive(false)
        mediaView.prepareForReuse()
    }

    func configure(item: ProfileAvatarGalleryItem, origin: TDImageOrigin) {
        mediaView.configure(item: item, origin: origin)
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        mediaView.setPlaybackVisible(isVisible)
    }

    func setDownloadsActive(_ isActive: Bool) {
        mediaView.setDownloadsActive(isActive)
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
    private var origin: TDImageOrigin?
    private var representedItem: ProfileAvatarGalleryItem?
    /// Leases on the shared download demand, one per file this page is fetching.
    private var downloads = [Int: AnimatedFileDownload]()
    private var decodeTask: Task<Void, Never>?
    private var decodeGeneration: UUID?
    private var playbackEndObserver: NSObjectProtocol?
    private var player: AVPlayer?
    private var playerReadyCancellable: AnyCancellable?
    private var playbackIsVisible = false
    private var downloadsAreActive = false
    /// The file whose full pixels the page shows, so a page back on screen redecodes only what it lost.
    private var displayedImageFileID: Int?

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

    func configure(item: ProfileAvatarGalleryItem, origin: TDImageOrigin) {
        // The same photo again (a list update or a client renewal) keeps its pixels and zoom until the new file loads.
        let keptImage = representedItem?.id == item.id ? imageView.image : nil
        let keptZoom: (scale: CGFloat, offset: CGPoint)? = keptImage == nil ? nil : (zoomScale, contentOffset)
        prepareForReuse()
        guard let imageSize = item.largestSize else { return }
        representedItem = item
        self.origin = origin
        represented = Representation(
            accountID: origin.source.accountID,
            animationFileID: item.animation?.file.id,
            clientID: origin.source.clientID,
            imageFileID: imageSize.photo.id,
            itemID: item.id,
        )
        imageView.image = keptImage ?? item.minithumbnail.flatMap { UIImage(data: $0.data) }
        if let keptZoom, keptZoom.scale > minimumZoomScale {
            layoutIfNeeded()
            setZoomScale(keptZoom.scale, animated: false)
            contentOffset = keptZoom.offset
        }
        updateImage(file: imageSize.photo)
        if let animation = item.animation {
            updateAnimation(file: animation.file)
        }
        // A page downloads while it is on screen.
        if downloadsAreActive { resumeDownloads() }
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = item.addedDate > 0
            ? L10n.betterTG("Accessibility.ProfilePhotoDated", ProfileAvatarDateFormatting.string(item.addedDate))
            : L10n.betterTG("Accessibility.ProfilePhoto")
    }

    func prepareForReuse() {
        setZoomScale(1, animated: false)
        panGestureRecognizer.isEnabled = false
        cancelDownloads()
        represented = nil
        origin = nil
        representedItem = nil
        imageView.image = nil
        displayedImageFileID = nil
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
            player?.play()
        } else {
            player?.pause()
            if let timestamp = representedItem?.animation?.mainFrameTimestamp,
               timestamp.isFinite,
               timestamp >= 0
            {
                player?.seek(to: CMTime(seconds: timestamp, preferredTimescale: 600))
            }
        }
    }

    func setDownloadsActive(_ isActive: Bool) {
        downloadsAreActive = isActive
        if isActive {
            resumeDownloads()
        } else {
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

    private func requestDownload(file: File) {
        guard let origin, origin.isCurrent, !file.local.isDownloadingCompleted,
              downloads[file.id] == nil else { return }
        let fileID = file.id
        let download = origin.request(fileID: fileID)
        downloads[fileID] = download
        download.start(file: file) { [weak self] file in
            self?.receiveDownloadedFile(file)
        } onInvalidated: { [weak self] in
            self?.downloads[fileID] = nil
        }
    }

    private func receiveDownloadedFile(_ file: File) {
        guard file.local.isDownloadingCompleted else { return }
        downloads.removeValue(forKey: file.id)?.cancel()
        if file.id == represented?.imageFileID {
            updateImage(file: file)
        }
        if file.id == represented?.animationFileID {
            updateAnimation(file: file)
        }
    }

    private func resumeDownloads() {
        guard let representedItem else { return }
        if let imageSize = representedItem.largestSize {
            if displayedImageFileID != imageSize.photo.id, decodeTask == nil {
                updateImage(file: imageSize.photo)
            }
            requestDownload(file: imageSize.photo)
        }
        if let animation = representedItem.animation {
            requestDownload(file: animation.file)
        }
    }

    /// Releases this page's leases; TDLib stops a download no other view still needs.
    private func cancelDownloads() {
        let leases = downloads.values
        downloads = [:]
        leases.forEach { $0.cancel() }
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
        // The remote unique ID names the same photo on a renewed client, whose file IDs differ.
        let key = (file.remote.uniqueId.isEmpty
            ? "\(represented.accountID.uuidString):\(represented.clientID):\(file.id)"
            : "\(represented.accountID.uuidString):\(file.remote.uniqueId)") as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            imageView.image = cached
            displayedImageFileID = file.id
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
            displayedImageFileID = file.id
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
