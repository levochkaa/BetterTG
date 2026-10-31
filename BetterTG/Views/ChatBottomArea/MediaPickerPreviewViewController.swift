// MediaPickerPreviewViewController.swift

import AVFoundation
import Photos
import UIKit

// MARK: - MediaPickerPreviewViewController

/// MediaPickerScreen's item preview (LegacyMediaPickerGallery): the grid's items full screen, paged sideways with a
/// gap, under Back, the numbered check that picks the shown item and Send with the picked count. A photo zooms with a
/// pinch or a double tap and a tap hides the controls; a video plays on its own, looping, and a tap pauses it. A swipe
/// down zooms the item back into the grid.
@MainActor final class MediaPickerPreviewViewController: UIViewController, UICollectionViewDataSource,
    UICollectionViewDelegate
{
    // MARK: Private

    /// LegacyMediaPickerGallery's page gap.
    private static let pageGap: CGFloat = 20

    override var prefersStatusBarHidden: Bool { controlsHidden }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: Internal

    /// The shown item's place among the picked ones, nil while it is not picked.
    var selectionNumber: ((PHAsset) -> Int?)?
    var selectionCount: (() -> Int)?
    var onToggle: ((PHAsset) -> Void)?
    /// Send: the picked items, or the shown one when none is picked.
    var onSend: ((PHAsset) -> Void)?
    /// The shown item changed; the grid keeps it in view for the zoom back.
    var onShow: ((PHAsset) -> Void)?

    private let count: Int
    private let assetAt: (Int) -> PHAsset?
    private let imageManager: PHCachingImageManager
    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let backPlatter = TelegramGlassPlatter(role: .leading)
    private let backButton = UIButton.telegramGlassIcon(
        UIImage(systemName: "chevron.left"),
        accessibilityLabel: L10n.telegram("Common.Back"),
    )
    private let checkPlatter = TelegramGlassPlatter(role: .trailing(0))
    private let checkButton = UIButton(type: .custom)
    private let checkView = MediaPickerCheckView()
    private let sendButton = UIButton(type: .system)
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private var currentIndex: Int
    private var controlsHidden = false
    private var laidOutWidth: CGFloat = 0

    var currentAsset: PHAsset? { assetAt(currentIndex) }

    /// A swipe down returns to the grid unless a photo is zoomed in.
    var allowsInteractiveDismiss: Bool { currentCell?.isZoomed != true }

    /// The shown item's frame in this view, which the zoom aligns with the grid's thumbnail.
    var currentMediaFrame: CGRect {
        guard let cell = currentCell else { return view.bounds }
        return cell.mediaFrame(in: view)
    }

    private var currentCell: MediaPickerPreviewCell? {
        collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? MediaPickerPreviewCell
    }

    private var pageWidth: CGFloat { collectionView.bounds.width }

    init(count: Int, startIndex: Int, imageManager: PHCachingImageManager, assetAt: @escaping (Int) -> PHAsset?) {
        self.count = count
        self.assetAt = assetAt
        self.imageManager = imageManager
        self.currentIndex = min(max(0, startIndex), max(0, count - 1))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            MediaPickerPreviewCell.self,
            forCellWithReuseIdentifier: MediaPickerPreviewCell.reuseIdentifier,
        )
        view.addSubview(collectionView)
        configureControls()
        refreshSelection()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        applyIPhoneDuoTopSafeArea()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Each page is the screen and the gap, half on either side, so paging stops on whole items.
        collectionView.frame = view.bounds.insetBy(dx: -Self.pageGap / 2, dy: 0)
        if laidOutWidth != collectionView.bounds.width {
            laidOutWidth = collectionView.bounds.width
            layout.itemSize = collectionView.bounds.size
            layout.invalidateLayout()
            collectionView.layoutIfNeeded()
            collectionView.contentOffset = CGPoint(x: CGFloat(currentIndex) * pageWidth, y: 0)
        }
        let safe = view.safeAreaInsets
        let edge = TelegramGlassPlatter.edgeInset
        let side = TelegramGlassPlatter.height
        backPlatter.frame = CGRect(x: safe.left + edge, y: safe.top, width: side, height: side)
        checkPlatter.frame = CGRect(
            x: view.bounds.width - safe.right - edge - side,
            y: safe.top,
            width: side,
            height: side,
        )
        sendButton.frame = CGRect(
            x: view.bounds.width - safe.right - edge - 40,
            y: view.bounds.height - max(safe.bottom, 16) - 8 - 40,
            width: 40,
            height: 40,
        )
        let badgeWidth = max(18, ceil(badgeLabel.intrinsicContentSize.width) + 8)
        badgeView.frame = CGRect(
            x: sendButton.frame.maxX + 4 - badgeWidth,
            y: sendButton.frame.minY - 4,
            width: badgeWidth,
            height: 18,
        )
        badgeLabel.frame = badgeView.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        currentCell?.startPlayback()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        currentCell?.stopPlayback()
    }

    // MARK: Data source

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MediaPickerPreviewCell.reuseIdentifier,
            for: indexPath,
        )
        guard let previewCell = cell as? MediaPickerPreviewCell,
              let asset = assetAt(indexPath.item) else { return cell }
        previewCell.pageInset = Self.pageGap / 2
        previewCell.configure(asset: asset, imageManager: imageManager)
        previewCell.onTap = { [weak self, weak previewCell] in
            guard let self, let previewCell else { return }
            if asset.mediaType == .video {
                previewCell.togglePlayback()
            } else {
                setControlsHidden(!controlsHidden)
            }
        }
        return cell
    }

    func collectionView(_: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? MediaPickerPreviewCell)?.stopPlayback()
    }

    // MARK: Scrolling

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        settlePage()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settlePage() }
    }

    /// The check and Send's count for the shown item and the picked ones.
    func refreshSelection() {
        let number = currentAsset.flatMap { selectionNumber?($0) }
        checkView.configure(number: number)
        checkButton.accessibilityLabel = L10n.telegram("Common.Select")
        checkButton.accessibilityTraits = number == nil ? .button : [.button, .selected]
        let picked = selectionCount?() ?? 0
        badgeLabel.text = String(picked)
        badgeView.isHidden = picked == 0
        sendButton.accessibilityValue = picked > 0 ? String(picked) : nil
        view.setNeedsLayout()
    }

    // MARK: Controls

    private func configureControls() {
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        backPlatter.setItems([backButton])
        checkView.isUserInteractionEnabled = false
        checkButton.addSubview(checkView)
        checkButton.addTarget(self, action: #selector(checkPressed), for: .touchUpInside)
        checkPlatter.setItems([checkButton])
        checkView.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
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
        let badgeFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        badgeLabel.font = badgeFont.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 13) }
            ?? badgeFont
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeView.backgroundColor = .systemRed
        badgeView.layer.cornerRadius = 9
        badgeView.isUserInteractionEnabled = false
        badgeView.addSubview(badgeLabel)
        for control in [backPlatter, checkPlatter, sendButton, badgeView] as [UIView] {
            view.addSubview(control)
        }
    }

    private func setControlsHidden(_ hidden: Bool) {
        controlsHidden = hidden
        UIView.animate(withDuration: 0.2) {
            for control in [self.backPlatter, self.checkPlatter, self.sendButton, self.badgeView] as [UIView] {
                control.alpha = hidden ? 0 : 1
            }
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func settlePage() {
        guard pageWidth > 0 else { return }
        let index = min(max(0, Int((collectionView.contentOffset.x / pageWidth).rounded())), max(0, count - 1))
        guard index != currentIndex else { return }
        currentCell?.stopPlayback()
        currentIndex = index
        currentCell?.startPlayback()
        refreshSelection()
        if let asset = currentAsset { onShow?(asset) }
    }

    @objc private func backPressed() {
        dismiss(animated: true)
    }

    @objc private func checkPressed() {
        guard let asset = currentAsset else { return }
        onToggle?(asset)
        refreshSelection()
    }

    @objc private func sendPressed() {
        guard let asset = currentAsset else { return }
        onSend?(asset)
    }
}

// MARK: - MediaPickerPreviewCell

/// One item of the preview: the photo fitted to the screen in a zooming scroll view, or the video's frame with the
/// video playing over it.
private final class MediaPickerPreviewCell: UICollectionViewCell, UIScrollViewDelegate {
    static let reuseIdentifier = "MediaPickerPreviewCell"

    var onTap: (() -> Void)?
    /// Half the page gap on either side of the item.
    var pageInset: CGFloat = 0

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
    private var asset: PHAsset?
    private var imageRequest: PHImageRequestID?
    private var playerRequest: PHImageRequestID?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private weak var imageManager: PHCachingImageManager?
    private var laidOutSize = CGSize.zero

    var isZoomed: Bool { scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)
        contentView.addSubview(scrollView)
        playIcon.tintColor = .white
        playIcon.contentMode = .center
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        playIcon.layer.shadowColor = UIColor.black.cgColor
        playIcon.layer.shadowOpacity = 0.3
        playIcon.layer.shadowRadius = 8
        playIcon.layer.shadowOffset = .zero
        playIcon.isHidden = true
        contentView.addSubview(playIcon)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(tap)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopPlayback()
        if let imageRequest { imageManager?.cancelImageRequest(imageRequest) }
        imageRequest = nil
        imageView.image = nil
        asset = nil
        onTap = nil
        laidOutSize = .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = contentView.bounds.insetBy(dx: pageInset, dy: 0)
        playIcon.frame = scrollView.frame
        if laidOutSize != scrollView.bounds.size {
            laidOutSize = scrollView.bounds.size
            layoutMedia()
        }
    }

    /// The media's frame in `view`'s coordinates.
    func mediaFrame(in view: UIView) -> CGRect {
        imageView.convert(imageView.bounds, to: view)
    }

    func configure(asset: PHAsset, imageManager: PHCachingImageManager) {
        self.asset = asset
        self.imageManager = imageManager
        scrollView.maximumZoomScale = asset.mediaType == .image ? 3 : 1
        laidOutSize = .zero
        setNeedsLayout()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        // The screen's pixels and half again, for a pinch's first steps.
        let scale = traitCollection.displayScale * 1.5
        let screen = window?.bounds.size ?? CGSize(width: 440, height: 956)
        let target = CGSize(width: screen.width * scale, height: screen.height * scale)
        let identifier = asset.localIdentifier
        imageRequest = imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options,
        ) { [weak self] image, _ in
            guard let self, self.asset?.localIdentifier == identifier, let image else { return }
            imageView.image = image
        }
    }

    func startPlayback() {
        guard let asset, asset.mediaType == .video, player == nil, playerRequest == nil,
              let imageManager else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let identifier = asset.localIdentifier
        playerRequest = imageManager.requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.asset?.localIdentifier == identifier, self.playerRequest != nil, let item
                else { return }
                self.playerRequest = nil
                self.play(item)
            }
        }
    }

    func stopPlayback() {
        if let playerRequest { imageManager?.cancelImageRequest(playerRequest) }
        playerRequest = nil
        if let item = player?.currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
            )
        }
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        playIcon.isHidden = true
    }

    func togglePlayback() {
        guard let player else {
            startPlayback()
            return
        }
        if player.timeControlStatus == .paused {
            player.play()
            playIcon.isHidden = true
        } else {
            player.pause()
            playIcon.isHidden = false
        }
    }

    // MARK: Zoom

    func viewForZooming(in _: UIScrollView) -> UIView? {
        asset?.mediaType == .image ? imageView : nil
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerMedia()
    }

    private func play(_ item: AVPlayerItem) {
        let player = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = imageView.bounds
        imageView.layer.addSublayer(layer)
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidPlayToEnd),
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
        )
        self.player = player
        playerLayer = layer
        playIcon.isHidden = true
        player.play()
    }

    /// Fits the media's own aspect into the page, from the asset's size so the first, smaller image does not jump.
    private func layoutMedia() {
        scrollView.zoomScale = 1
        let bounds = scrollView.bounds.size
        guard let asset, asset.pixelWidth > 0, asset.pixelHeight > 0, bounds.width > 0,
              bounds.height > 0 else { return }
        let size = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        imageView.frame = CGRect(origin: .zero, size: fitted)
        playerLayer?.frame = imageView.bounds
        scrollView.contentSize = fitted
        centerMedia()
    }

    private func centerMedia() {
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        scrollView.contentInset = UIEdgeInsets(
            top: max(0, (bounds.height - content.height) / 2),
            left: max(0, (bounds.width - content.width) / 2),
            bottom: 0,
            right: 0,
        )
    }

    @objc private func tapped() {
        onTap?()
    }

    /// The preview loops a video.
    @objc private func playerDidPlayToEnd() {
        player?.seek(to: .zero)
        player?.play()
    }

    /// Telegram's double tap: zoom in around the tap, or back out.
    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard asset?.mediaType == .image else { return }
        if isZoomed {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale = scrollView.maximumZoomScale / 1.5
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        scrollView.zoom(
            to: CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height,
            ),
            animated: true,
        )
    }
}
