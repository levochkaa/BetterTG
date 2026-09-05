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

        func configure(_ message: Message, selected: Bool) {
            switch message.content {
            case .messagePhoto(let value): image.load(photo: value.photo, preferredSize: .mBox, maximumPixelSize: 160)
            case .messageVideo(let value):
                if let thumbnail = value.video.thumbnail { image.load(
                    file: thumbnail.file,
                    placeholderData: value.video.minithumbnail?.data,
                    maximumPixelSize: 160,
                ) }
            case .messageAnimation(let value):
                if let thumbnail = value.animation.thumbnail { image.load(
                    file: thumbnail.file,
                    placeholderData: value.animation.minithumbnail?.data,
                    maximumPixelSize: 160,
                ) }
            case .messageSticker(let value):
                if let thumbnail = value.sticker.thumbnail { image.load(file: thumbnail.file, maximumPixelSize: 160) }
            default: image.cancel()
            }
            accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    var onSelect: ((Int) -> Void)?

    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var messages = [Message]()
    private var selectedIndex = 0

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

    func configure(messages: [Message], selectedIndex: Int) {
        let changed = self.messages.map(\.id) != messages.map(\.id)
        let previous = self.selectedIndex
        self.messages = messages
        self.selectedIndex = selectedIndex
        if changed { collection.reloadData() }
        else if previous != selectedIndex {
            collection
                .reloadItems(at: [previous, selectedIndex].filter { messages.indices.contains($0) }.map { IndexPath(
                    item: $0,
                    section: 0,
                ) })
        }
        layout.invalidateLayout()
        centerSelection(animated: window != nil && !changed)
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
        cell.configure(messages[indexPath.item], selected: indexPath.item == selectedIndex)
        cell.accessibilityLabel = "Media \(indexPath.item + 1)"
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) { onSelect?(indexPath.item) }

    func collectionView(
        _: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath,
    ) -> CGSize {
        let size = Self.mediaSize(messages[indexPath.item])
        return CGSize(
            width: indexPath.item == selectedIndex
                ? min(75, max(23, 42 * size.width / max(1, size.height)))
                : 23,
            height: 42,
        )
    }

    private func centerSelection(animated: Bool) {
        guard messages.indices.contains(selectedIndex), collection.bounds.width > 0 else { return }
        collection.layoutIfNeeded()
        collection.scrollToItem(
            at: IndexPath(item: selectedIndex, section: 0),
            at: .centeredHorizontally,
            animated: animated,
        )
    }
}
