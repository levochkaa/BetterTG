// GalleryThumbnailStripView.swift

import TDLibKit
import UIKit

final class GalleryThumbnailStripView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private final class ThumbnailCell: UICollectionViewCell {
        private let image = TDImageLoadingView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 2
            image.frame = contentView.bounds
            image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(image)
            isAccessibilityElement = true
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func prepareForReuse() { super.prepareForReuse()
            image.cancel()
        }

        func configure(_ message: Message, selected: Bool, client: TDLibClient) {
            switch message.content {
            case .messagePhoto(let value): image.load(
                    photo: value.photo,
                    preferredSize: .mBox,
                    maximumPixelSize: 160,
                    client: client,
                )
            case .messageVideo(let value):
                if let thumbnail = value.video.thumbnail { image.load(
                    file: thumbnail.file,
                    placeholderData: value.video.minithumbnail?.data,
                    maximumPixelSize: 160,
                    client: client,
                ) }
            case .messageAnimation(let value):
                if let thumbnail = value.animation.thumbnail { image.load(
                    file: thumbnail.file,
                    placeholderData: value.animation.minithumbnail?.data,
                    maximumPixelSize: 160,
                    client: client,
                ) }
            case .messageSticker(let value):
                if let thumbnail = value.sticker.thumbnail { image.load(
                    file: thumbnail.file,
                    maximumPixelSize: 160,
                    client: client,
                ) }
            default: image.cancel()
            }
            updateSelection(selected)
        }

        func updateSelection(_ selected: Bool) {
            accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    var onSelect: ((Int) -> Void)?

    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var messages = [Message]()
    private var client: TDLibClient?
    private var selectedIndex = 0
    private var pagingPosition = CGFloat.zero
    private var isScrubbing = false
    private var isSelectingByTap = false
    private var isUpdatingLayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        collection.dataSource = self
        collection.delegate = self
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.register(ThumbnailCell.self, forCellWithReuseIdentifier: "thumbnail")
        addSubview(collection)
        accessibilityIdentifier = "gallery-thumbnails"
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let wasUpdating = isUpdatingLayout
        isUpdatingLayout = true
        defer { isUpdatingLayout = wasUpdating }
        let changed = collection.bounds.size != bounds.size
        collection.frame = bounds
        collection.contentInset = UIEdgeInsets(
            top: 5,
            left: max(0, bounds.width / 2 - 12),
            bottom: 5,
            right: max(0, bounds.width / 2 - 12),
        )
        if changed { centerSelection(animated: false) }
    }

    private static func mediaSize(_ message: Message) -> CGSize {
        switch message.content {
        case .messagePhoto(let value):
            let size = value.photo.sizes.last
            return CGSize(width: size?.width ?? 1, height: size?.height ?? 1)
        case .messageVideo(let value): return CGSize(width: value.video.width, height: value.video.height)
        case .messageAnimation(let value): return CGSize(width: value.animation.width, height: value.animation.height)
        case .messageSticker(let value): return CGSize(width: value.sticker.width, height: value.sticker.height)
        default: return CGSize(width: 1, height: 1)
        }
    }

    func configure(messages: [Message], selectedIndex: Int, client: TDLibClient) {
        self.client = client
        isUpdatingLayout = true
        defer { isUpdatingLayout = false }
        let changed = self.messages.map(\.id) != messages.map(\.id)
        let previousPosition = pagingPosition
        self.messages = messages
        self.selectedIndex = selectedIndex
        if !isScrubbing { pagingPosition = CGFloat(selectedIndex) }
        if changed { collection.reloadData() }
        // Reconfigure selection without reloading images or crossfading cells.
        for indexPath in collection.indexPathsForVisibleItems {
            (collection.cellForItem(at: indexPath) as? ThumbnailCell)?.updateSelection(indexPath.item == selectedIndex)
        }
        if !isScrubbing {
            updateLayout(animated: window != nil && !changed && abs(previousPosition - pagingPosition) > 0.001)
        }
    }

    func updatePagingPosition(_ position: CGFloat) {
        guard !isScrubbing, !isSelectingByTap, !isUpdatingLayout, !messages.isEmpty else { return }
        let position = min(CGFloat(messages.count - 1), max(0, position))
        guard abs(position - pagingPosition) > 0.001 else { return }
        pagingPosition = position
        isUpdatingLayout = true
        updateLayout(animated: false)
        isUpdatingLayout = false
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int { messages.count }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "thumbnail",
            for: indexPath,
        ) as! ThumbnailCell
        if let client { cell.configure(
            messages[indexPath.item],
            selected: indexPath.item == selectedIndex,
            client: client,
        ) }
        cell.accessibilityLabel = L10n.betterTG("Accessibility.MediaNumber", indexPath.item + 1)
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        isSelectingByTap = true
        onSelect?(indexPath.item)
        isSelectingByTap = false
    }

    func collectionView(
        _: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath,
    ) -> CGSize {
        let size = Self.mediaSize(messages[indexPath.item])
        let expandedWidth = min(75, max(31, 42 * size.width / max(1, size.height)))
        let expansion = isScrubbing ? 0 : max(0, 1 - abs(CGFloat(indexPath.item) - pagingPosition))
        return CGSize(width: 23 + (expandedWidth - 23) * expansion, height: 42)
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        isUpdatingLayout = true
        isScrubbing = true
        layout.invalidateLayout()
        centerSelection(animated: false)
        isUpdatingLayout = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isScrubbing, !isUpdatingLayout,
              scrollView.isDragging || scrollView.isDecelerating,
              !messages.isEmpty
        else { return }
        // Telegram collapses the selected thumbnail while panning and selects the center item.
        let index = min(messages.count - 1, max(0, Int(round((collection.bounds.midX - 11.5) / 25))))
        if index != selectedIndex { onSelect?(index) }
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishScrubbing() }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        finishScrubbing()
    }

    private func finishScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        pagingPosition = CGFloat(selectedIndex)
        isUpdatingLayout = true
        updateLayout(animated: true)
        isUpdatingLayout = false
    }

    private func updateLayout(animated: Bool) {
        layout.invalidateLayout()
        let changes = {
            self.collection.layoutIfNeeded()
            self.centerSelection(animated: false)
        }
        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: changes,
            )
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }

    private func centerSelection(animated: Bool) {
        guard messages.indices.contains(selectedIndex), collection.bounds.width > 0 else { return }
        collection.layoutIfNeeded()
        let position = isScrubbing ? CGFloat(selectedIndex) : pagingPosition
        let lower = min(messages.count - 1, max(0, Int(floor(position))))
        let upper = min(messages.count - 1, lower + 1)
        guard let first = layout.layoutAttributesForItem(at: IndexPath(item: lower, section: 0)),
              let second = layout.layoutAttributesForItem(at: IndexPath(item: upper, section: 0))
        else { return }
        let fraction = position - CGFloat(lower)
        let center = first.center.x + (second.center.x - first.center.x) * fraction
        collection.setContentOffset(
            CGPoint(x: center - collection.bounds.width / 2, y: -collection.adjustedContentInset.top),
            animated: animated,
        )
    }
}
