// PeerProfileGiftsPane.swift

import TDLibKit
import UIKit

// MARK: - PeerProfileGiftsPane

/// PeerInfoGiftsPaneNode over ProfileGiftsContext: the gifts a user or a channel keeps on its profile, from TDLib's
/// getReceivedGifts a page at a time, in TDLib's order (pinned first). The pane shows once the full info's gift count
/// is above zero.
@MainActor final class PeerProfileGiftsPane {
    private static let pageSize = 50

    var onChange: (() -> Void)?

    private(set) var items = [Int64]()
    private(set) var hasMore = true
    private(set) var error: String?

    private let ownerID: MessageSender
    private let client: TDLibClient
    private let isCurrent: () -> Bool
    private var gifts = [Int64: TDNativeReceivedGift]()
    /// A received gift's TDLib ID to the pane's item ID, which the data source needs as an integer.
    private var itemIDs = [String: Int64]()
    private var nextItemID: Int64 = 1
    private var offset = ""
    private var loadTask: Task<Void, Never>?

    var isLoading: Bool { loadTask != nil }

    init(ownerID: MessageSender, client: TDLibClient, isCurrent: @escaping () -> Bool) {
        self.ownerID = ownerID
        self.client = client
        self.isCurrent = isCurrent
    }

    func gift(for id: Int64) -> TDNativeReceivedGift? {
        gifts[id]
    }

    func loadMore() {
        guard loadTask == nil, hasMore, isCurrent() else { return }
        error = nil
        let client = client
        let ownerID = ownerID
        let offset = offset
        loadTask = Task { [weak self] in
            let result = await Result {
                try await client.send(TDNativeRequests.getReceivedGifts(
                    businessConnectionId: "",
                    ownerId: ownerID,
                    collectionId: 0,
                    excludeUnsaved: false,
                    excludeSaved: false,
                    excludeUnlimited: false,
                    excludeUpgradable: false,
                    excludeNonUpgradable: false,
                    excludeUpgraded: false,
                    excludeWithoutColors: false,
                    excludeHosted: false,
                    sortByPrice: false,
                    offset: offset,
                    limit: Self.pageSize,
                ))
            }
            guard let self, !Task.isCancelled else { return }
            loadTask = nil
            guard isCurrent() else { return }
            switch result {
            case .success(let page):
                for gift in page.gifts {
                    let key = gift.receivedGiftId.isEmpty ? "\(offset)#\(items.count)" : gift.receivedGiftId
                    let id = itemIDs[key] ?? nextItemID
                    if itemIDs[key] == nil {
                        itemIDs[key] = id
                        nextItemID += 1
                        items.append(id)
                    }
                    gifts[id] = gift
                }
                self.offset = page.nextOffset
                hasMore = !page.nextOffset.isEmpty && !page.gifts.isEmpty
            case .failure:
                error = L10n.betterTG("Profile.GiftsLoadFailed")
            }
            onChange?()
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }
}

// MARK: - ProfileGiftCell

/// GiftItemComponent in `.profile` mode with the glass style: a square tile in the list's block colour with 16 pt
/// corners, or an upgraded gift's backdrop as a radial gradient from its centre colour; the gift's sticker centred at
/// 88 / 116 of the tile's height; the sender's 20 pt avatar at the top left, or the pin there on a gift pinned to the
/// profile's top; the ribbon at the top right ("1 of N" for a limited gift, the number or "sale" for an upgraded one);
/// and a gift hidden from the profile shows the crossed eye on a dark blur over the sticker.
final class ProfileGiftCell: UICollectionViewCell {
    private enum RibbonStyle: Equatable {
        case generic
        case sale
        case number(edge: Int)
    }

    static let reuseIdentifier = "ProfileGiftCell"

    private static let anonymousPlaceholder = TelegramAvatarPlaceholder(
        peerID: 2_666_000,
        accentColorID: 0,
        upgradedGiftColors: nil,
        letters: [],
        isDeleted: false,
    )

    private let backgroundLayer = CALayer()
    private let backdropLayer = CAGradientLayer()
    private let patternLayer = GiftPatternLayer()
    private var patternTask: Task<Void, Never>?
    private let stickerView = CustomEmojiInlineView()
    private let avatarView = ProfileAvatarView()
    private let pinView = UIImageView(image: UIImage(named: "Gift/Pinned")?.withRenderingMode(.alwaysTemplate))
    private let hiddenBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let hiddenIcon = UIImageView(image: UIImage(named: "Gift/Hidden")?
        .withTintColor(.white, renderingMode: .alwaysOriginal))
    private let ribbonView = UIImageView()
    private let ribbonLabel = UILabel()
    private var ribbonStyle: RibbonStyle?
    private var avatarTask: Task<Void, Never>?
    private var hasBackdrop = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundLayer.cornerRadius = 16
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.masksToBounds = true
        backdropLayer.type = .radial
        backdropLayer.isHidden = true
        backgroundLayer.addSublayer(backdropLayer)
        patternLayer.isHidden = true
        backgroundLayer.addSublayer(patternLayer)
        contentView.layer.addSublayer(backgroundLayer)
        contentView.addSubview(stickerView)
        hiddenBackground.clipsToBounds = true
        hiddenBackground.isHidden = true
        hiddenIcon.isHidden = true
        contentView.addSubview(hiddenBackground)
        contentView.addSubview(hiddenIcon)
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        avatarView.isHidden = true
        contentView.addSubview(avatarView)
        pinView.isHidden = true
        contentView.addSubview(pinView)
        ribbonLabel.textColor = .white
        ribbonLabel.textAlignment = .center
        ribbonLabel.transform = CGAffineTransform(rotationAngle: .pi / 4)
        contentView.addSubview(ribbonView)
        contentView.addSubview(ribbonLabel)
        isAccessibilityElement = true
        accessibilityTraits = .button
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            if !self.hasBackdrop {
                self.backgroundLayer.backgroundColor = UIColor.secondarySystemGroupedBackground
                    .resolvedColor(with: self.traitCollection)
                    .cgColor
            }
            if let style = self.ribbonStyle {
                self.ribbonView.image = Self.ribbonImage(style, traits: self.traitCollection)
            }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = contentView.bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = contentView.bounds
        backdropLayer.frame = backgroundLayer.bounds
        CATransaction.commit()
        let side = floor(88 * size.height / 116)
        let iconFrame = CGRect(
            x: floor((size.width - side) / 2),
            y: floor((size.height - side) / 2),
            width: side,
            height: side,
        )
        stickerView.frame = iconFrame
        // PeerInfoCoverComponent's gradient, centred on the sticker.
        backdropLayer.startPoint = CGPoint(x: 0.5, y: size.height > 0 ? iconFrame.midY / size.height : 0.5)
        backdropLayer.endPoint = CGPoint(x: 1, y: 1)
        // GiftItemComponent's cover: the pattern centred on the sticker, as tall as the tile.
        patternLayer.frame = backgroundLayer.bounds
        patternLayer.layout(center: CGPoint(x: iconFrame.midX, y: iconFrame.midY), defaultHeight: size.height)
        let hiddenSide: CGFloat = 30
        hiddenBackground.frame = CGRect(
            x: iconFrame.midX - hiddenSide / 2,
            y: iconFrame.midY - hiddenSide / 2,
            width: hiddenSide,
            height: hiddenSide,
        )
        hiddenBackground.layer.cornerRadius = hiddenSide / 2
        hiddenIcon.frame = hiddenBackground.frame
        avatarView.frame = CGRect(x: 5, y: 5, width: 20, height: 20)
        pinView.frame = CGRect(x: 3, y: 3, width: 24, height: 24)
        // The ribbon sits 2 pt out past the top right corner, its text turned 45° about a point 22 pt in.
        if let image = ribbonView.image {
            ribbonView.frame = CGRect(
                x: size.width - image.size.width + 2,
                y: -2,
                width: image.size.width,
                height: image.size.height,
            )
        }
        let labelSize = ribbonLabel.sizeThatFits(CGSize(width: 100, height: 20))
        ribbonLabel.bounds = CGRect(origin: .zero, size: labelSize)
        ribbonLabel.center = CGPoint(x: size.width - 22 + 2, y: 22 - 2)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarTask?.cancel()
        avatarTask = nil
        patternTask?.cancel()
        patternTask = nil
        patternLayer.setImage(nil)
        avatarView.prepareForReuse()
        stickerView.setPlaybackVisible(false)
    }

    /// GiftItemComponent.Ribbon.Color's gradient over the ribbon's shape (generateGradientTintedImage's
    /// mirroredDiagonal: the first colour at the bottom right, the second at the top left).
    private static func ribbonImage(_ style: RibbonStyle, traits: UITraitCollection) -> UIImage? {
        guard let shape = UIImage(named: "Gift/Ribbon") else { return nil }
        let colors: [UIColor] =
            switch style {
            case .generic:
                traits.userInterfaceStyle == .dark
                    ? [UIColor(rgb: 0x142E42), UIColor(rgb: 0x354F5B)]
                    : [UIColor(rgb: 0x34A4FC), UIColor(rgb: 0x6FD3FF)]
            case .sale:
                [UIColor(rgb: 0x4BB121), UIColor(rgb: 0x53D654)]
            case .number(let edge):
                [
                    UIColor(rgb: edge).multiplied(hue: 0.97, saturation: 1.45, brightness: 0.89),
                    UIColor(rgb: edge).multiplied(hue: 1.01, saturation: 1.22, brightness: 1.04),
                ]
            }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = shape.scale
        return UIGraphicsImageRenderer(size: shape.size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: shape.size)
            let cgColors = colors.map(\.cgColor) as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: cgColors,
                locations: [0, 1],
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.maxX, y: rect.maxY),
                    end: CGPoint(x: 0, y: 0),
                    options: [],
                )
            }
            shape.withRenderingMode(.alwaysOriginal).draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }

    func setPlaybackVisible(_ visible: Bool) {
        stickerView.setPlaybackVisible(visible)
    }

    func configure(gift received: TDNativeReceivedGift, client: TDLibClient) {
        let sticker: Sticker
        var ribbon: (text: String, style: RibbonStyle)?
        var showsSender: Bool
        var backdrop: TDNativeUpgradedGiftBackdropColors?
        switch received.gift {
        case .sentGiftRegular(let value):
            let gift = value.gift
            sticker = gift.sticker
            if let limits = gift.overallLimits {
                ribbon = (
                    L10n.telegram("PeerInfo.Gifts.OneOf", compactNumericCountString(limits.totalCount)),
                    .generic,
                )
            }
            showsSender = true
            accessibilityLabel = L10n.telegram("PeerInfo.PaneGifts")
        case .sentGiftUpgraded(let value):
            let gift = value.gift
            sticker = gift.model.sticker
            backdrop = gift.backdrop.colors
            if gift.resaleParameters != nil {
                ribbon = (L10n.telegram("PeerInfo.Gifts.Sale"), .sale)
            } else {
                ribbon = ("#\(gift.number)", .number(edge: gift.backdrop.colors.edgeColor))
            }
            // An upgraded gift names its sender only beside a message the sender left visible.
            showsSender = !received.text.text.isEmpty && !received.isPrivate
            accessibilityLabel = gift.title.isEmpty ? L10n.telegram("PeerInfo.PaneGifts") : gift.title
        }
        if received.isPinned { showsSender = false }

        hasBackdrop = backdrop != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let backdrop {
            backgroundLayer.backgroundColor = UIColor(rgb: backdrop.edgeColor).cgColor
            backdropLayer.colors = [
                UIColor(rgb: backdrop.centerColor).cgColor,
                UIColor(rgb: backdrop.edgeColor).cgColor,
            ]
            backdropLayer.isHidden = false
            patternLayer.setColor(UIColor(rgb: backdrop.symbolColor))
            patternLayer.isHidden = false
        } else {
            backgroundLayer.backgroundColor = UIColor.secondarySystemGroupedBackground
                .resolvedColor(with: traitCollection)
                .cgColor
            backdropLayer.isHidden = true
            patternLayer.isHidden = true
        }
        CATransaction.commit()
        patternTask?.cancel()
        patternLayer.setImage(nil)
        if case .sentGiftUpgraded(let value) = received.gift {
            let symbol = value.gift.symbol.sticker
            patternTask = Task { [weak self] in
                let image = await GiftSymbolImages.image(for: symbol, client: client)
                guard !Task.isCancelled, let self else { return }
                patternLayer.setImage(image)
            }
        }

        stickerView.configure(sticker: sticker, client: client)
        stickerView.setPlaybackVisible(window != nil)

        pinView.isHidden = !received.isPinned
        pinView.tintColor = backdrop == nil ? .secondaryLabel : .white
        let isHidden = !received.isSaved
        hiddenBackground.isHidden = !isHidden
        hiddenIcon.isHidden = !isHidden

        if let ribbon {
            ribbonStyle = ribbon.style
            ribbonView.image = Self.ribbonImage(ribbon.style, traits: traitCollection)
            ribbonLabel.text = ribbon.text
            ribbonLabel.font =
                switch ribbon.style {
                case .generic: .systemFont(ofSize: 9, weight: .semibold)
                case .sale: .systemFont(ofSize: 10, weight: .semibold)
                case .number: .monospacedSystemFont(ofSize: 10, weight: .semibold)
                }
            ribbonView.isHidden = false
            ribbonLabel.isHidden = false
        } else {
            ribbonStyle = nil
            ribbonView.isHidden = true
            ribbonLabel.isHidden = true
        }

        avatarTask?.cancel()
        avatarView.isHidden = !showsSender
        if showsSender {
            configureSender(received.senderId, client: client)
        }
        setNeedsLayout()
    }

    /// The sender's avatar, or Telegram's anonymous sender for a gift sent without a name.
    private func configureSender(_ sender: MessageSender?, client: TDLibClient) {
        avatarView.configure(
            file: nil,
            minithumbnail: nil,
            placeholder: Self.anonymousPlaceholder,
            client: client,
        )
        guard let sender else { return }
        avatarTask = Task { [weak self] in
            guard let peer = await SettingsPeer.resolve(sender, client: client), !Task.isCancelled, let self
            else { return }
            avatarView.configure(
                file: peer.file,
                minithumbnail: peer.minithumbnail,
                placeholder: peer.placeholder,
                client: client,
            )
        }
    }
}

private extension UIColor {
    /// Display's withMultiplied(hue:saturation:brightness:), each component clamped to 0...1.
    func multiplied(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> UIColor {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(
            hue: max(0, min(1, h * hue)),
            saturation: max(0, min(1, s * saturation)),
            brightness: max(0, min(1, b * brightness)),
            alpha: a,
        )
    }
}
