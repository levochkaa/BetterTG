// ProfileAvatarGalleryViewController.swift

import AVFoundation
import Combine
import ImageIO
import Photos
import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - ProfileAvatarGalleryItem

struct ProfileAvatarGalleryItem: Hashable {
    let addedDate: Int
    let animation: AnimatedChatPhoto?
    let id: Int64
    let minithumbnail: Minithumbnail?
    let photo: Photo
    /// The ID is TDLib's photo ID, not one made up for a chat's current photo, so the photo can be managed.
    let hasPhotoID: Bool

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
        self.hasPhotoID = true
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
        self.hasPhotoID = true
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
        self.hasPhotoID = false
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
        hasPhotoID: Bool,
    ) {
        self.addedDate = addedDate
        self.animation = animation
        self.id = id
        self.minithumbnail = minithumbnail
        self.photo = photo
        self.hasPhotoID = hasPhotoID
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
            hasPhotoID: hasPhotoID,
        )
    }
}

// MARK: - ProfileAvatarGalleryViewController

@MainActor final class ProfileAvatarGalleryViewController: UIViewController, UICollectionViewDataSource,
    UICollectionViewDelegate, UIGestureRecognizerDelegate
{
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    var contextIsCurrent: (() -> Bool)?
    var onRequestMoreItems: (() -> Void)?
    var onDismissed: (() -> Void)?
    /// The gallery moved to the account's renewed client; requests for it now go through `client`.
    var onClientRenewed: (() -> Void)?
    /// Telegram hides Share and Save for a chat that protects its content.
    var allowsSaving = true {
        didSet { updateActionButtons() }
    }

    /// The account's own profile: its photos can be set as main or deleted (AvatarGalleryController, editEntry).
    var managesOwnPhotos = false {
        didSet { updateActionButtons() }
    }

    /// The account's photos changed through this gallery; the owner reloads the list.
    var onPhotosChanged: (() -> Void)?

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
    private let shareButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var transitionController: ProfileAvatarGalleryTransitionController?
    private var clientRenewalCancellable: AnyCancellable?
    private var clientRenewalTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var interactiveDismissalTranslation = CGFloat.zero
    private lazy var dismissPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        return gesture
    }()

    fileprivate var selectedItemID: Int64? {
        items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
    }

    private var selectedItem: ProfileAvatarGalleryItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    /// Telegram (GalleryControllerNode) drags a photo away only at its fitted size.
    private var canBeginInteractiveDismissal: Bool {
        guard !UIAccessibility.isVoiceOverRunning,
              presentedViewController == nil,
              transitionCoordinator == nil,
              !isBeingDismissed,
              !paginationMutationInProgress,
              transitionController?.isInteractiveDismissalInProgress != true,
              items.indices.contains(selectedIndex),
              let cell = collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
              as? ProfileAvatarGalleryCell
        else { return false }
        return cell.isAtMinimumZoom
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
        actionTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityViewIsModal = true
        configureCollectionView()
        configureFooter()
        view.addGestureRecognizer(dismissPanGesture)
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
        actionTask?.cancel()
        actionTask = nil
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

    // MARK: Interactive Dismissal

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === dismissPanGesture else { return true }
        return touch.view?.isDescendant(of: footer) != true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPanGesture else { return true }
        let velocity = dismissPanGesture.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x) * 1.2 && canBeginInteractiveDismissal
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        gestureRecognizer === dismissPanGesture && otherGestureRecognizer is UIPanGestureRecognizer
            && otherGestureRecognizer.view is UIScrollView
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

    fileprivate func setTransitionContentHidden(_ hidden: Bool) {
        collectionView.isHidden = hidden
    }

    fileprivate func setInteractiveDismissalChromeAlpha(_ alpha: CGFloat) {
        footer.alpha = alpha
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
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = .white
        shareButton.accessibilityLabel = L10n.telegram("Gallery.VoiceOver.Share")
        shareButton.accessibilityIdentifier = "avatar-gallery-share"
        shareButton.addTarget(self, action: #selector(shareSelectedPhoto), for: .touchUpInside)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.tintColor = .white
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.accessibilityIdentifier = "avatar-gallery-more"
        moreButton.addTarget(self, action: #selector(showMoreActions), for: .touchUpInside)
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
        footer.contentView.addSubview(shareButton)
        footer.contentView.addSubview(moreButton)
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
            shareButton.topAnchor.constraint(equalTo: footer.contentView.topAnchor),
            shareButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 50),
            moreButton.topAnchor.constraint(equalTo: footer.contentView.topAnchor),
            moreButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            moreButton.widthAnchor.constraint(equalToConstant: 52),
            moreButton.heightAnchor.constraint(equalToConstant: 50),
            retryButton.topAnchor.constraint(equalTo: footer.contentView.topAnchor),
            retryButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -4),
            retryButton.heightAnchor.constraint(equalToConstant: 50),
            counterLabel.centerXAnchor.constraint(equalTo: footer.contentView.centerXAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])
        updateActionButtons()
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
        updateActionButtons()
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

    private func updateActionButtons() {
        guard isViewLoaded else { return }
        shareButton.isHidden = !allowsSaving || selectedItem == nil
        moreButton.isHidden = moreActions().isEmpty
        shareButton.isEnabled = actionTask == nil
        moreButton.isEnabled = actionTask == nil
    }

    /// Telegram's avatar gallery saves any photo and, on the account's own profile, sets one as main or deletes it
    /// after a Remove confirmation (AvatarGalleryController, editEntry).
    private func moreActions() -> [TelegramContextMenuAction] {
        guard let item = selectedItem else { return [] }
        let isVideo = item.animation != nil
        var actions = [TelegramContextMenuAction]()
        if allowsSaving {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isVideo ? "Gallery.SaveVideo" : "Gallery.SaveImage"),
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] in
                self?.saveSelectedPhoto()
            })
        }
        guard managesOwnPhotos, item.hasPhotoID else { return actions }
        // The first photo is the main one.
        if selectedIndex > 0 {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isVideo ? "ProfilePhoto.SetMainVideo" : "ProfilePhoto.SetMainPhoto"),
                image: UIImage(systemName: "checkmark.circle"),
            ) { [weak self] in
                self?.setSelectedPhotoAsMain()
            })
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram(isVideo ? "Settings.RemoveVideo" : "GroupInfo.SetGroupPhotoDelete"),
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            startsNewSection: true,
            children: [
                TelegramContextMenuAction(
                    title: L10n.telegram("Settings.RemoveConfirmation"),
                    image: UIImage(systemName: "trash"),
                    isDestructive: true,
                ) { [weak self] in
                    self?.deleteSelectedPhoto()
                },
            ],
        ))
        return actions
    }

    @objc private func showMoreActions() {
        guard presentedViewController == nil, actionTask == nil else { return }
        presentTelegramContextMenu(sourceView: moreButton, actions: moreActions(), presentationStyle: .sourceMorph)
    }

    /// The file Save and Share hand over: a video avatar's video, otherwise the largest photo.
    private func exportedFile(of item: ProfileAvatarGalleryItem) -> (file: File, isVideo: Bool)? {
        if let animation = item.animation { return (animation.file, true) }
        return item.largestSize.map { ($0.photo, false) }
    }

    private func completedFile(_ file: File) async throws -> File {
        if file.local.isDownloadingCompleted, FileManager.default.fileExists(atPath: file.local.path) {
            return file
        }
        guard let downloaded = await downloadOrigin.request(fileID: file.id).completedFile(file: file),
              downloaded.local.isDownloadingCompleted,
              FileManager.default.fileExists(atPath: downloaded.local.path)
        else { throw ProfileAvatarExportError.downloadFailed }
        return downloaded
    }

    private func saveSelectedPhoto() {
        guard actionTask == nil, allowsSaving, let item = selectedItem, let exported = exportedFile(of: item) else {
            return
        }
        UIAccessibility.post(notification: .announcement, argument: L10n.betterTG("Accessibility.PreparingMediaSave"))
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await completedFile(exported.file)
                var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                if authorization == .notDetermined {
                    authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                }
                guard authorization == .authorized || authorization == .limited else {
                    throw ProfileAvatarExportError.photosAccessDenied
                }
                try Task.checkCancellation()
                let url = URL(filePath: file.local.path)
                let isVideo = exported.isVideo
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    options.uniformTypeIdentifier = isVideo ? UTType.mpeg4Movie.identifier : UTType.jpeg.identifier
                    request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: options)
                }
                finishAction()
                TelegramUndoToast.show(
                    text: L10n.telegram(isVideo ? "Gallery.VideoSaved" : "Gallery.ImageSaved"),
                    in: view,
                    bottomInset: 58,
                    undo: nil,
                )
            } catch {
                finishAction()
                guard !(error is CancellationError) else { return }
                presentExportFailure(error, title: L10n.betterTG("Gallery.SaveFailedTitle"))
            }
        }
        updateActionButtons()
    }

    @objc private func shareSelectedPhoto() {
        guard actionTask == nil, allowsSaving, presentedViewController == nil, let item = selectedItem,
              let exported = exportedFile(of: item)
        else { return }
        UIAccessibility.post(notification: .announcement, argument: L10n.betterTG("Accessibility.PreparingMediaShare"))
        actionTask = Task { [weak self] in
            guard let self else { return }
            let directory = FileManager.default
                .temporaryDirectory
                .appending(path: "avatar-share-\(UUID().uuidString)", directoryHint: .isDirectory)
            do {
                let file = try await completedFile(exported.file)
                try Task.checkCancellation()
                // A named copy, so the receiving app sees the file's type.
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appending(path: exported.isVideo ? "video.mp4" : "photo.jpg")
                try FileManager.default.copyItem(at: URL(filePath: file.local.path), to: url)
                finishAction()
                guard presentedViewController == nil, !isBeingDismissed else {
                    try? FileManager.default.removeItem(at: directory)
                    return
                }
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activity.popoverPresentationController?.sourceView = shareButton
                activity.popoverPresentationController?.sourceRect = shareButton.bounds
                activity.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: directory)
                }
                present(activity, animated: true)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                finishAction()
                guard !(error is CancellationError) else { return }
                presentExportFailure(error, title: L10n.betterTG("Gallery.ShareFailedTitle"))
            }
        }
        updateActionButtons()
    }

    private func setSelectedPhotoAsMain() {
        guard actionTask == nil, managesOwnPhotos, let item = selectedItem, item.hasPhotoID else { return }
        let client = client
        actionTask = Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setProfilePhoto(
                    photo: .inputChatPhotoPrevious(TDNativeInputChatPhotoPrevious(chatPhotoId: item.id)),
                    isPublic: false,
                ))
                guard let self else { return }
                finishAction()
                onPhotosChanged?()
            } catch {
                guard let self else { return }
                finishAction()
                guard !(error is CancellationError) else { return }
                presentChatListActionFailure()
            }
        }
        updateActionButtons()
    }

    private func deleteSelectedPhoto() {
        guard actionTask == nil, managesOwnPhotos, let item = selectedItem, item.hasPhotoID else { return }
        let client = client
        actionTask = Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.deleteProfilePhoto(profilePhotoId: item.id))
                guard let self else { return }
                finishAction()
                removeDeletedItem(id: item.id)
            } catch {
                guard let self else { return }
                finishAction()
                guard !(error is CancellationError) else { return }
                presentChatListActionFailure()
            }
        }
        updateActionButtons()
    }

    /// Telegram (performDeleteEntry) closes the gallery when the main photo goes and otherwise shows the one before.
    private func removeDeletedItem(id: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard index > 0, !paginationMutationInProgress, isViewLoaded else {
            if index == 0 { close() } else { onPhotosChanged?() }
            return
        }
        items.remove(at: index)
        totalCount = max(items.count, totalCount - 1)
        selectedIndex = index - 1
        collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: false,
        )
        collectionView.cellForItem(at: IndexPath(item: selectedIndex, section: 0))
            .flatMap { $0 as? ProfileAvatarGalleryCell }?
            .setPlaybackVisible(true)
        updateCounter()
        onPhotosChanged?()
    }

    private func finishAction() {
        actionTask = nil
        updateActionButtons()
    }

    private func presentExportFailure(_ error: any Error, title: String) {
        guard presentedViewController == nil, !isBeingDismissed else { return }
        let message = (error as? ProfileAvatarExportError)?.errorDescription ?? L10n.telegram("Login.UnknownError")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if case .photosAccessDenied? = error as? ProfileAvatarExportError,
           let settingsURL = URL(string: UIApplication.openSettingsURLString)
        {
            alert.addAction(UIAlertAction(title: L10n.telegram("AccessDenied.Settings"), style: .default) { _ in
                UIApplication.shared.open(settingsURL)
            })
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .cancel))
        present(alert, animated: true)
    }

    /// Telegram drags the photo down or up and closes past a quarter of the screen or on a fast flick.
    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard let transitionController else { return }
        switch gesture.state {
        case .began:
            guard canBeginInteractiveDismissal else { return }
            interactiveDismissalTranslation = 0
            collectionView.panGestureRecognizer.isEnabled = false
            let began = transitionController.beginInteractiveDismissal(from: self) { [weak self] completed in
                self?.interactiveDismissalEnded(completed: completed)
            }
            if !began { interactiveDismissalEnded(completed: false) }
        case .changed:
            interactiveDismissalTranslation = gesture.translation(in: view).y
            transitionController.updateInteractiveDismissal(interactiveDismissalTranslation)
        case .ended:
            let velocity = gesture.velocity(in: view)
            if abs(interactiveDismissalTranslation) > view.bounds.height / 4 || abs(velocity.y) > 1000 {
                transitionController.finishInteractiveDismissal()
            } else {
                transitionController.cancelInteractiveDismissal()
            }
        case .cancelled,
             .failed:
            transitionController.cancelInteractiveDismissal()
        case .possible:
            break
        @unknown default:
            transitionController.cancelInteractiveDismissal()
        }
    }

    private func interactiveDismissalEnded(completed: Bool) {
        collectionView.panGestureRecognizer.isEnabled = true
        interactiveDismissalTranslation = 0
        guard !completed else { return }
        view.backgroundColor = .black
        setTransitionContentHidden(false)
        setInteractiveDismissalChromeAlpha(1)
    }
}

// MARK: - ProfileAvatarGalleryCell

private final class ProfileAvatarGalleryCell: UICollectionViewCell {
    static let reuseIdentifier = "ProfileAvatarGalleryCell"

    private let mediaView = ProfileAvatarMediaView()

    var isAtMinimumZoom: Bool {
        mediaView.zoomScale <= mediaView.minimumZoomScale + 0.001
    }

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
    private(set) var isInteractiveDismissalInProgress = false

    private var dismissalInteraction: ProfileAvatarGalleryDismissalInteraction?
    private var interactiveDismissalCompletion: ((Bool) -> Void)?

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

    func interactionControllerForDismissal(
        using _: any UIViewControllerAnimatedTransitioning,
    ) -> (any UIViewControllerInteractiveTransitioning)? {
        isInteractiveDismissalInProgress ? dismissalInteraction : nil
    }

    func beginInteractiveDismissal(
        from gallery: ProfileAvatarGalleryViewController,
        completion: @escaping (Bool) -> Void,
    ) -> Bool {
        guard !isInteractiveDismissalInProgress, gallery.presentingViewController != nil else { return false }
        dismissalInteraction = ProfileAvatarGalleryDismissalInteraction { [weak self] completed in
            self?.dismissalTransitionEnded(completed: completed)
        }
        interactiveDismissalCompletion = completion
        isInteractiveDismissalInProgress = true
        gallery.dismiss(animated: true)
        return true
    }

    func updateInteractiveDismissal(_ translation: CGFloat) {
        guard isInteractiveDismissalInProgress else { return }
        dismissalInteraction?.update(translation: translation)
    }

    func finishInteractiveDismissal() {
        guard isInteractiveDismissalInProgress else { return }
        dismissalInteraction?.end(completed: true)
    }

    func cancelInteractiveDismissal() {
        guard isInteractiveDismissalInProgress else { return }
        dismissalInteraction?.end(completed: false)
    }

    private func dismissalTransitionEnded(completed: Bool) {
        guard isInteractiveDismissalInProgress else { return }
        isInteractiveDismissalInProgress = false
        dismissalInteraction = nil
        let completion = interactiveDismissalCompletion
        interactiveDismissalCompletion = nil
        completion?(completed)
    }
}

// MARK: - ProfileAvatarGalleryDismissalInteraction

/// The media gallery's drag (MediaGalleryDismissalInteraction): the photo follows the finger at full size, then on
/// release flies back into the profile's avatar or off the screen.
private final class ProfileAvatarGalleryDismissalInteraction: NSObject, UIViewControllerInteractiveTransitioning {
    private var context: (any UIViewControllerContextTransitioning)?
    private var snapshot: UIView?
    private var startFrame = CGRect.zero
    private var translation = CGFloat.zero
    private var pendingCompletion: Bool?
    private var dragSourceTarget: MediaGalleryTransitionTarget?
    private var dragSourceView: UIView?
    private var dragSourceAlpha = CGFloat(1)
    private var isEnding = false
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func startInteractiveTransition(_ transitionContext: any UIViewControllerContextTransitioning) {
        context = transitionContext
        guard let gallery = transitionContext.viewController(forKey: .from) as? ProfileAvatarGalleryViewController,
              let toController = transitionContext.viewController(forKey: .to),
              let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.cancelInteractiveTransition()
            transitionContext.completeTransition(false)
            context = nil
            completion(false)
            return
        }
        let container = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: toController)
        container.insertSubview(toView, belowSubview: fromView)
        toView.layoutIfNeeded()
        if let frame = gallery.transitionContentFrame(in: container),
           let mediaSnapshot = gallery.makeTransitionSnapshot()
        {
            startFrame = frame
            mediaSnapshot.frame = frame
            mediaSnapshot.clipsToBounds = true
            container.addSubview(mediaSnapshot)
            snapshot = mediaSnapshot
            gallery.setTransitionContentHidden(true)
        }
        dragSourceTarget = gallery.currentTransitionTarget()
        dragSourceView = dragSourceTarget?.validatedSourceView
        dragSourceAlpha = dragSourceView?.alpha ?? 1
        dragSourceView?.alpha = 0
        update(translation: translation)
        if let pendingCompletion { end(completed: pendingCompletion) }
    }

    func update(translation: CGFloat) {
        guard !isEnding else { return }
        self.translation = translation
        guard let context,
              let gallery = context.viewController(forKey: .from) as? ProfileAvatarGalleryViewController,
              let fromView = context.view(forKey: .from)
        else { return }
        // GalleryControllerNode: controls fade over 50 pt, background over 80 pt.
        snapshot?.frame = startFrame.offsetBy(dx: 0, dy: translation)
        fromView.backgroundColor = UIColor.black.withAlphaComponent(1 - min(1, abs(translation) / 80))
        gallery.setInteractiveDismissalChromeAlpha(1 - min(1, abs(translation) / 50))
        context.updateInteractiveTransition(min(1, abs(translation) / max(1, fromView.bounds.height / 4)))
    }

    func end(completed: Bool) {
        guard !isEnding else { return }
        guard let context,
              let gallery = context.viewController(forKey: .from) as? ProfileAvatarGalleryViewController,
              let fromView = context.view(forKey: .from)
        else {
            pendingCompletion = completed
            return
        }
        isEnding = true
        if completed {
            context.finishInteractiveTransition()
        } else {
            context.cancelInteractiveTransition()
        }
        if dragSourceTarget?.validatedSourceView === dragSourceView {
            dragSourceView?.alpha = dragSourceAlpha
        }
        dragSourceTarget = nil
        dragSourceView = nil
        // The destination is resolved on release; the profile may have changed during the drag.
        let target = completed ? gallery.currentTransitionTarget() : nil
        let sourceView = target?.validatedSourceView
        let sourceAlpha = sourceView?.alpha ?? 1
        let destination = target?.frame(in: context.containerView)
        sourceView?.alpha = 0
        let snapshot = snapshot
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.38,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut],
        ) {
            fromView.backgroundColor = UIColor.black.withAlphaComponent(completed ? 0 : 1)
            gallery.setInteractiveDismissalChromeAlpha(completed ? 0 : 1)
            if !completed {
                snapshot?.frame = self.startFrame
            } else if let target, let destination, !UIAccessibility.isReduceMotionEnabled {
                snapshot?.frame = destination
                snapshot?.layer.cornerRadius = target.cornerRadius
                snapshot?.layer.maskedCorners = target.maskedCorners
            } else {
                snapshot?.alpha = 0
                if !UIAccessibility.isReduceMotionEnabled {
                    snapshot?.frame = self.startFrame.offsetBy(
                        dx: 0,
                        dy: self.translation + (self.translation < 0 ? -1 : 1) * fromView.bounds.height,
                    )
                }
            }
        } completion: { _ in
            context.completeTransition(completed)
            if target?.validatedSourceView === sourceView { sourceView?.alpha = sourceAlpha }
            snapshot?.removeFromSuperview()
            gallery.setTransitionContentHidden(false)
            self.snapshot = nil
            self.context = nil
            self.completion(completed)
        }
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

// MARK: - ProfileAvatarExportError

private enum ProfileAvatarExportError: LocalizedError {
    case downloadFailed
    case photosAccessDenied

    var errorDescription: String? {
        switch self {
        case .downloadFailed: L10n.betterTG("Gallery.ErrorDownloadFailed")
        case .photosAccessDenied: L10n.betterTG("Gallery.ErrorPhotosAccess")
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
