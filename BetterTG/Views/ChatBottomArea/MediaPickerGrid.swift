// MediaPickerGrid.swift

import Photos
import UIKit

// MARK: - MediaPickerGridLayout

/// MediaPickerScreen's grid: three items a row, five in compact landscape, 1 pt apart and filling the width. In
/// Recents the camera is a cutout one column wide and two rows tall at the start, which the first items flow beside.
final class MediaPickerGridLayout: UICollectionViewLayout {
    static let spacing: CGFloat = 1

    override var collectionViewContentSize: CGSize {
        let rows = rowCount
        let height = rows > 0 ? CGFloat(rows) * (itemWidth + Self.spacing) - Self.spacing : 0
        return CGSize(width: contentWidth, height: height)
    }

    /// Item 0 is the camera tile.
    var hasCameraTile = false {
        didSet { if hasCameraTile != oldValue { invalidateLayout() } }
    }

    private(set) var itemWidth: CGFloat = 0

    private var columns = 3
    private var contentWidth: CGFloat = 0
    private var itemCount = 0

    /// Rows the camera tile spans.
    private var cameraRows: Int { hasCameraTile ? 2 : 0 }
    /// Items beside the camera tile in its two rows.
    private var itemsBesideCamera: Int { hasCameraTile ? 2 * (columns - 1) : 0 }
    private var mediaCount: Int { max(0, itemCount - (hasCameraTile ? 1 : 0)) }

    private var rowCount: Int {
        let rest = max(0, mediaCount - itemsBesideCamera)
        return cameraRows + (rest + columns - 1) / columns
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let insets = collectionView.adjustedContentInset
        contentWidth = max(0, collectionView.bounds.width - insets.left - insets.right)
        columns = collectionView.traitCollection.verticalSizeClass == .compact ? 5 : 3
        let scale = max(1, collectionView.traitCollection.displayScale)
        let width = (contentWidth - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        itemWidth = max(0, floor(width * scale) / scale)
        itemCount = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard itemCount > 0, itemWidth > 0 else { return [] }
        let step = itemWidth + Self.spacing
        let firstRow = max(0, Int(floor(rect.minY / step)))
        let lastRow = min(rowCount - 1, max(firstRow, Int(floor(rect.maxY / step))))
        guard firstRow <= lastRow else { return [] }
        var items = [Int]()
        if hasCameraTile, firstRow < cameraRows { items.append(0) }
        for row in firstRow...lastRow {
            items.append(contentsOf: itemRange(inRow: row))
        }
        return items.compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, indexPath.item < itemCount else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame(forItemAt: indexPath.item)
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return newBounds.width != collectionView.bounds.width
    }

    private func itemRange(inRow row: Int) -> Range<Int> {
        let first = hasCameraTile ? 1 : 0
        let start: Int
        let count: Int
        if row < cameraRows {
            start = row * (columns - 1)
            count = columns - 1
        } else {
            start = itemsBesideCamera + (row - cameraRows) * columns
            count = columns
        }
        let lower = min(itemCount, first + start)
        return lower..<min(itemCount, lower + count)
    }

    private func frame(forItemAt item: Int) -> CGRect {
        if hasCameraTile, item == 0 {
            return CGRect(x: 0, y: 0, width: itemWidth, height: itemWidth * 2 + Self.spacing)
        }
        let index = item - (hasCameraTile ? 1 : 0)
        let row: Int
        let column: Int
        if index < itemsBesideCamera {
            row = index / (columns - 1)
            column = 1 + index % (columns - 1)
        } else {
            let rest = index - itemsBesideCamera
            row = cameraRows + rest / columns
            column = rest % columns
        }
        let step = itemWidth + Self.spacing
        let x = CGFloat(column) * step
        // GridNode's `fillWidth`: the last column takes what the rounding left.
        let width = column == columns - 1 ? max(itemWidth, contentWidth - x) : itemWidth
        return CGRect(x: x, y: CGFloat(row) * step, width: width, height: itemWidth)
    }
}

// MARK: - MediaPickerCheckView

/// Telegram's overlay CheckNode in counter mode: a white ring over the media that fills with the accent color and
/// shows the item's place in the selection.
final class MediaPickerCheckView: UIView {
    private let circle = UIView()
    private let numberLabel = UILabel()
    private var number: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        circle.layer.borderColor = UIColor.white.cgColor
        circle.layer.borderWidth = 1.5
        circle.layer.shadowColor = UIColor.black.cgColor
        circle.layer.shadowOpacity = 0.22
        circle.layer.shadowRadius = 2
        circle.layer.shadowOffset = .zero
        addSubview(circle)
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        numberLabel.font = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 14) } ?? font
        numberLabel.textColor = .white
        numberLabel.textAlignment = .center
        numberLabel.adjustsFontSizeToFitWidth = true
        numberLabel.minimumScaleFactor = 0.6
        circle.addSubview(numberLabel)
        configure(number: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 24
        circle.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        circle.layer.cornerRadius = side / 2
        numberLabel.frame = circle.bounds.insetBy(dx: 3, dy: 0)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        configure(number: number)
    }

    func configure(number: Int?) {
        self.number = number
        numberLabel.text = number.map(String.init)
        circle.backgroundColor = number == nil ? UIColor.black.withAlphaComponent(0.12) : tintColor
    }
}

// MARK: - MediaPickerGridCell

/// MediaPickerGridItem: the library thumbnail with its type icon (video, slow motion, time-lapse, Live Photo or
/// favorite) at the top left, a video's duration at the bottom right, the numbered check at the top right and the
/// spoiler over a picked item hidden with one.
final class MediaPickerGridCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaPickerGridCell"

    var representedAssetIdentifier: String?
    let imageView = UIImageView()

    private let spoilerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let typeIconView = UIImageView()
    private let durationLabel = UILabel()
    private let checkView = MediaPickerCheckView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemFill
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        typeIconView.contentMode = .center
        typeIconView.tintColor = .white
        typeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        durationLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        for shadowed in [typeIconView, durationLabel] as [UIView] {
            shadowed.layer.shadowColor = UIColor.black.cgColor
            shadowed.layer.shadowOpacity = 0.4
            shadowed.layer.shadowRadius = 2
            shadowed.layer.shadowOffset = .zero
        }
        spoilerView.isHidden = true
        for subview in [imageView, spoilerView, typeIconView, durationLabel, checkView] as [UIView] {
            contentView.addSubview(subview)
        }
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedAssetIdentifier = nil
        imageView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        imageView.frame = bounds
        spoilerView.frame = bounds
        typeIconView.frame = CGRect(x: 0, y: 1, width: 19, height: 19)
        let durationSize = durationLabel.sizeThatFits(bounds.size)
        durationLabel.frame = CGRect(
            x: bounds.width - durationSize.width - 6,
            y: bounds.height - durationSize.height - 6,
            width: durationSize.width,
            height: durationSize.height,
        )
        let checkSide: CGFloat = 29
        checkView.frame = CGRect(x: bounds.width - checkSide - 3, y: 3, width: checkSide, height: checkSide)
    }

    /// Telegram's `stringForDuration`: m:ss, or h:mm:ss from an hour.
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// `livePhoto` is MediaPickerGridItem's Live Photo icon where the chat takes Live Photos: Live when the photo
    /// goes live and Live Off when it goes as a still, in the favorite's place; nil shows none.
    func configure(asset: PHAsset, livePhoto: Bool?) {
        var symbol: String?
        var duration: String?
        var kind = "Message.Photo"
        if asset.mediaType == .video {
            if asset.mediaSubtypes.contains(.videoHighFrameRate) {
                symbol = "slowmo"
            } else if asset.mediaSubtypes.contains(.videoTimelapse) {
                symbol = "timelapse"
            } else {
                symbol = "video.fill"
            }
            duration = Self.durationText(asset.duration)
            kind = "Message.Video"
        }
        if asset.isFavorite { symbol = "heart.fill" }
        if let livePhoto {
            symbol = livePhoto ? "livephoto" : "livephoto.slash"
            kind = "Message.LivePhoto"
        }
        typeIconView.image = symbol.flatMap { UIImage(systemName: $0) }
        durationLabel.text = duration
        durationLabel.isHidden = duration == nil
        accessibilityLabel = [
            L10n.telegram(kind),
            livePhoto.map { L10n.telegram($0 ? "VoiceOver.Common.On" : "VoiceOver.Common.Off") },
            duration,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        setNeedsLayout()
    }

    func configureSelection(number: Int?, hasSpoiler: Bool) {
        checkView.configure(number: number)
        spoilerView.isHidden = !hasSpoiler
        accessibilityTraits = number == nil ? .button : [.button, .selected]
        accessibilityValue = number.map(String.init)
    }
}

// MARK: - MediaPickerCameraCell

/// MediaPickerScreen's camera tile at the start of Recents. Telegram shows the live camera in it; here it opens the
/// camera.
final class MediaPickerCameraCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaPickerCameraCell"

    private let iconView = UIImageView(image: UIImage(systemName: "camera.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = L10n.telegram("Attachment.Camera")
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }
}

// MARK: - MediaPickerManageBanner

/// MediaPickerManageNode for limited library access: the explanation and Manage, above the grid.
final class MediaPickerManageBanner: UIView {
    var onManage: ((UIView) -> Void)?

    private let textLabel = UILabel()
    private let manageButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        textLabel.text = L10n.telegram("Attachment.LimitedMediaAccessText")
        textLabel.font = .preferredFont(forTextStyle: .footnote)
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 0
        manageButton.setTitle(L10n.telegram("Attachment.Manage"), for: .normal)
        manageButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        manageButton.titleLabel?.adjustsFontForContentSizeCategory = true
        manageButton.setContentHuggingPriority(.required, for: .horizontal)
        manageButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        manageButton.addTarget(self, action: #selector(managePressed), for: .touchUpInside)
        for subview in [textLabel, manageButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            manageButton.leadingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 12),
            manageButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            manageButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func height(forWidth width: CGFloat) -> CGFloat {
        systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        ).height
    }

    @objc private func managePressed() {
        onManage?(manageButton)
    }
}

// MARK: - MediaPickerPlaceholderView

/// MediaPickerPlaceholderNode: Access Your Photos and Videos with Go to Settings when the library is denied, or the
/// chat's media restriction.
final class MediaPickerPlaceholderView: UIView {
    var onOpenSettings: (() -> Void)?

    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let settingsButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.cornerStyle = .large
        buttonConfiguration.title = L10n.telegram("Attachment.OpenSettings")
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        settingsButton.configuration = buttonConfiguration
        settingsButton.addTarget(self, action: #selector(settingsPressed), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [titleLabel, textLabel, settingsButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: textLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func configure(title: String?, text: String, showsSettings: Bool) {
        titleLabel.text = title
        titleLabel.isHidden = title == nil
        textLabel.text = text
        settingsButton.isHidden = !showsSettings
    }

    @objc private func settingsPressed() {
        onOpenSettings?()
    }
}

// MARK: - MediaPickerAlbum

/// An album MediaPickerScreen lets the grid switch to, with its item count and the item its row shows.
struct MediaPickerAlbum {
    let collection: PHAssetCollection
    let count: Int
    let keyAsset: PHAsset?

    var isRecents: Bool { collection.assetCollectionSubtype == .smartAlbumUserLibrary }

    var title: String {
        isRecents ? L10n.telegram("MediaPicker.Recents") : collection.localizedTitle ?? ""
    }

    /// Recents and Favorites show their newest item, other albums their first.
    private init?(collection: PHAssetCollection) {
        let assets = PHAsset.fetchAssets(in: collection, options: nil)
        // PHFetchResult has no isEmpty.
        guard assets.firstObject != nil else { return nil }
        self.collection = collection
        self.count = assets.count
        let subtype = collection.assetCollectionSubtype
        self.keyAsset = subtype == .smartAlbumUserLibrary || subtype == .smartAlbumFavorites
            ? assets.lastObject
            : assets.firstObject
    }

    /// MediaGroupsScreen's sections: My Albums (Recents, Favorites, then the user's albums newest first) and Media
    /// Types (the supported smart albums), each listing only albums with items. Call off the main thread.
    static func fetchSections() -> (albums: [MediaPickerAlbum], mediaTypes: [MediaPickerAlbum]) {
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        let mediaTypeSubtypes: Set<PHAssetCollectionSubtype> = [
            .smartAlbumBursts, .smartAlbumPanoramas, .smartAlbumScreenshots, .smartAlbumSelfPortraits,
            .smartAlbumSlomoVideos, .smartAlbumTimelapses, .smartAlbumVideos, .smartAlbumAllHidden,
            .smartAlbumAnimated, .smartAlbumDepthEffect, .smartAlbumLivePhotos,
        ]
        var albums = [MediaPickerAlbum]()
        var mediaTypes = [MediaPickerAlbum]()
        smartAlbums.enumerateObjects { collection, _, _ in
            let subtype = collection.assetCollectionSubtype
            if subtype == .smartAlbumUserLibrary || subtype == .smartAlbumFavorites {
                if let album = MediaPickerAlbum(collection: collection) { albums.append(album) }
            }
        }
        userAlbums.enumerateObjects(options: [.reverse]) { collection, _, _ in
            if let album = MediaPickerAlbum(collection: collection) { albums.append(album) }
        }
        smartAlbums.enumerateObjects { collection, _, _ in
            if mediaTypeSubtypes.contains(collection.assetCollectionSubtype),
               let album = MediaPickerAlbum(collection: collection)
            {
                mediaTypes.append(album)
            }
        }
        return (albums, mediaTypes)
    }
}

// MARK: - MediaPickerAlbumsViewController

/// MediaGroupsScreen, opened from the grid's title: the albums with their key item, title and count. Choosing one
/// switches the grid to it.
@MainActor final class MediaPickerAlbumsViewController: UIViewController, UITableViewDataSource,
    UITableViewDelegate
{
    private static let thumbnailSide: CGFloat = 44

    var onSelect: ((MediaPickerAlbum) -> Void)?

    private let imageManager: PHImageManager
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections = [(title: String, albums: [MediaPickerAlbum])]()
    private var thumbnails = [String: UIImage]()

    init(imageManager: PHImageManager) {
        self.imageManager = imageManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.betterTG("MediaPicker.AlbumsTitle")
        view.backgroundColor = .systemGroupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Album")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fetched = MediaPickerAlbum.fetchSections()
            DispatchQueue.main.async {
                guard let self else { return }
                var sections = [(title: String, albums: [MediaPickerAlbum])]()
                if !fetched.albums.isEmpty {
                    sections.append((L10n.telegram("Attachment.MyAlbums"), fetched.albums))
                }
                if !fetched.mediaTypes.isEmpty {
                    sections.append((L10n.telegram("Attachment.MediaTypes"), fetched.mediaTypes))
                }
                self.sections = sections
                self.tableView.reloadData()
            }
        }
    }

    /// The key item cropped to a square, as Telegram's album thumbnails fill theirs.
    private static func squareImage(_ image: UIImage, side: CGFloat, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(1, scale)
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let factor = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
            let drawn = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            image.draw(in: CGRect(
                x: (side - drawn.width) / 2,
                y: (side - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height,
            ))
        }
    }

    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[safe: section]?.albums.count ?? 0
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[safe: section]?.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Album", for: indexPath)
        guard let album = sections[safe: indexPath.section]?.albums[safe: indexPath.row] else { return cell }
        var content = UIListContentConfiguration.subtitleCell()
        content.text = album.title
        content.secondaryText = String(album.count)
        content.secondaryTextProperties.color = .secondaryLabel
        let side = Self.thumbnailSide
        content.imageProperties.maximumSize = CGSize(width: side, height: side)
        content.imageProperties.reservedLayoutSize = CGSize(width: side, height: side)
        content.imageProperties.cornerRadius = 6
        let identifier = album.collection.localIdentifier
        content.image = thumbnails[identifier] ?? UIImage(systemName: "photo.on.rectangle")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        if thumbnails[identifier] == nil, let asset = album.keyAsset {
            loadThumbnail(for: asset, albumID: identifier)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let album = sections[safe: indexPath.section]?.albums[safe: indexPath.row] else { return }
        onSelect?(album)
    }

    private func loadThumbnail(for asset: PHAsset, albumID: String) {
        let scale = traitCollection.displayScale
        let pixels = Self.thumbnailSide * max(1, scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            contentMode: .aspectFill,
            options: options,
        ) { [weak self] image, _ in
            guard let self, let image else { return }
            thumbnails[albumID] = Self.squareImage(image, side: Self.thumbnailSide, scale: scale)
            for indexPath in tableView.indexPathsForVisibleRows ?? []
                where sections[safe: indexPath.section]?.albums[safe: indexPath.row]?.collection
                .localIdentifier == albumID
            {
                tableView.reconfigureRows(at: [indexPath])
            }
        }
    }
}
