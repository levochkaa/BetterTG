// PeerProfileGiftsPane.swift

import Combine
import Lottie
import TDLibKit
import UIKit

// MARK: - PeerProfileGiftsPane

/// PeerInfoGiftsPaneNode over ProfileGiftsContext: the gifts a user or a channel keeps on its profile, from TDLib's
/// getReceivedGifts a page at a time, in TDLib's order (pinned first). The pane shows once the full info's gift count
/// is above zero.
@MainActor final class PeerProfileGiftsPane {
    /// ProfileGiftsContext.Filters: the kinds of gift the list shows, all at first.
    struct Filter: OptionSet {
        static let unlimited = Filter(rawValue: 1 << 0)
        static let limitedNonUpgradable = Filter(rawValue: 1 << 1)
        static let limitedUpgradable = Filter(rawValue: 1 << 2)
        static let unique = Filter(rawValue: 1 << 3)
        static let displayed = Filter(rawValue: 1 << 4)
        static let hidden = Filter(rawValue: 1 << 5)

        static let kinds: Filter = [.unlimited, .limitedNonUpgradable, .limitedUpgradable, .unique]
        static let visibility: Filter = [.displayed, .hidden]
        static let all: Filter = kinds.union(visibility)

        let rawValue: Int
    }

    private static let pageSize = 50

    var onChange: (() -> Void)?

    private(set) var items = [Int64]()
    private(set) var hasMore = true
    private(set) var error: String?

    /// ProfileGiftsCollectionsContext: the profile's gift collections, and the one the grid shows (nil for All Gifts).
    private(set) var collections = [(id: Int, name: String, giftCount: Int)]()
    private(set) var selectedCollectionID: Int?

    private let ownerID: MessageSender
    private let client: TDLibClient
    private let isCurrent: () -> Bool
    private var gifts = [Int64: TDNativeReceivedGift]()
    /// A received gift's TDLib ID to the pane's item ID, which the data source needs as an integer.
    private var itemIDs = [String: Int64]()
    private var nextItemID: Int64 = 1
    private var offset = ""
    private var loadTask: Task<Void, Never>?
    private var replacesOnNextPage = false
    private let filter = CurrentValueSubject<Filter, Never>(.all)
    private var collectionsTask: Task<Void, Never>?
    private let sortsByValue = CurrentValueSubject<Bool, Never>(false)

    var isLoading: Bool { loadTask != nil }

    /// Whether the filter hides some kind of gift, which turns an empty list into GiftsListView's no-results state.
    var isFiltered: Bool {
        filter.value != .all
    }

    init(ownerID: MessageSender, client: TDLibClient, isCurrent: @escaping () -> Bool) {
        self.ownerID = ownerID
        self.client = client
        self.isCurrent = isCurrent
    }

    private static func showError(_ error: Error, in host: UIViewController) {
        let message = (error as? TDLibError)?.message ?? error.localizedDescription
        TelegramUndoToast.show(text: message, in: host.view, bottomInset: 12, undo: nil)
    }

    private static func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func gift(for id: Int64) -> TDNativeReceivedGift? {
        gifts[id]
    }

    /// The first gifts' stickers (an upgraded gift's model), for the pane's tab.
    func leadingStickers(_ count: Int) -> [Sticker] {
        items.prefix(count).compactMap { gifts[$0] }.map { gift in
            switch gift.gift {
            case .sentGiftRegular(let value): value.gift.sticker
            case .sentGiftUpgraded(let value): value.gift.model.sticker
            }
        }
    }

    func loadMore() {
        guard loadTask == nil, hasMore, isCurrent() else { return }
        error = nil
        let client = client
        let ownerID = ownerID
        let offset = offset
        let filter = filter.value
        let sortByPrice = sortsByValue.value
        let collectionID = selectedCollectionID ?? 0
        loadTask = Task { [weak self] in
            let result = await Result {
                try await client.send(TDNativeRequests.getReceivedGifts(
                    businessConnectionId: "",
                    ownerId: ownerID,
                    collectionId: collectionID,
                    excludeUnsaved: !filter.contains(.hidden),
                    excludeSaved: !filter.contains(.displayed),
                    excludeUnlimited: !filter.contains(.unlimited),
                    excludeUpgradable: !filter.contains(.limitedUpgradable),
                    excludeNonUpgradable: !filter.contains(.limitedNonUpgradable),
                    excludeUpgraded: !filter.contains(.unique),
                    excludeWithoutColors: false,
                    excludeHosted: false,
                    sortByPrice: sortByPrice,
                    offset: offset,
                    limit: Self.pageSize,
                ))
            }
            guard let self, !Task.isCancelled else { return }
            loadTask = nil
            guard isCurrent() else { return }
            switch result {
            case .success(let page):
                // A reload replaces the list with its first page; item IDs stay with their gifts.
                if replacesOnNextPage {
                    replacesOnNextPage = false
                    items = []
                    gifts = [:]
                }
                var listed = Set(items)
                for gift in page.gifts {
                    let key = gift.receivedGiftId.isEmpty ? "\(offset)#\(items.count)" : gift.receivedGiftId
                    let id = itemIDs[key] ?? nextItemID
                    if itemIDs[key] == nil {
                        itemIDs[key] = id
                        nextItemID += 1
                    }
                    if listed.insert(id).inserted { items.append(id) }
                    gifts[id] = gift
                }
                self.offset = page.nextOffset
                hasMore = !page.nextOffset.isEmpty && !page.gifts.isEmpty
            case .failure:
                // A reload for another collection or filter must not leave the previous list standing.
                if replacesOnNextPage {
                    replacesOnNextPage = false
                    items = []
                    gifts = [:]
                }
                error = L10n.betterTG("Profile.GiftsLoadFailed")
            }
            onChange?()
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// Reads the list again from its first page after a change, keeping the shown gifts until it arrives.
    func reload() {
        cancel()
        offset = ""
        hasMore = true
        replacesOnNextPage = true
        loadMore()
    }

    // MARK: Collections

    /// getGiftCollections, read once the pane is made; PeerInfoGiftsPaneNode shows their tabs when one has gifts, or
    /// to whoever manages them.
    func loadCollections() {
        guard collectionsTask == nil else { return }
        let client = client
        let ownerID = ownerID
        collectionsTask = Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.getGiftCollections(ownerId: ownerID))
            guard let self, !Task.isCancelled, isCurrent() else { return }
            collections = (result?.collections ?? []).map { (id: $0.id, name: $0.name, giftCount: $0.giftCount) }
            #if DEBUG
                // `-ui-probe-gift-collections` names two made-up collections so the tabs show on any profile; a
                // made-up collection fails to load in TDLib.
                if collections.isEmpty, ProcessInfo.processInfo.arguments.contains("-ui-probe-gift-collections") {
                    collections = [
                        (id: 9_000_001, name: "Favorites", giftCount: 3),
                        (id: 9_000_002, name: "Rare", giftCount: 1),
                    ]
                }
            #endif
            onChange?()
        }
    }

    func showsCollectionTabs(canManage: Bool) -> Bool {
        !collections.isEmpty && (canManage || collections.contains { $0.giftCount > 0 })
    }

    /// The tab's collection, or All Gifts; the grid reads it from its first page.
    func selectCollection(_ id: Int?) {
        guard id != selectedCollectionID else { return }
        selectedCollectionID = id
        reload()
    }

    // MARK: Filter

    /// PeerInfoScreenDisplayGiftsContextMenu: Sort by Value or by Date, then the kinds of gift (Unlimited, Limited,
    /// Upgradable, Unique) and, where the viewer manages the gifts, Displayed and Hidden, each checked while shown. A
    /// kind toggles with the menu open; the last kind left switches Unlimited back on, and the last visibility left
    /// switches the other one on.
    func filterMenuActions(hasVisibility: Bool) -> [TelegramContextMenuAction] {
        let sortsByValue = sortsByValue.value
        var actions = [TelegramContextMenuAction(
            title: L10n.telegram(sortsByValue ? "PeerInfo.Gifts.SortByDate" : "PeerInfo.Gifts.SortByValue"),
            image: UIImage(systemName: sortsByValue ? "calendar" : "dollarsign.circle"),
        ) { [weak self] in
            guard let self else { return }
            self.sortsByValue.send(!sortsByValue)
            reload()
        }]
        var kinds: [(String, Filter)] = [
            ("PeerInfo.Gifts.Unlimited", .unlimited),
            ("PeerInfo.Gifts.Limited", .limitedNonUpgradable),
            ("PeerInfo.Gifts.Upgradable", .limitedUpgradable),
            ("PeerInfo.Gifts.Unique", .unique),
        ]
        if hasVisibility {
            kinds += [("PeerInfo.Gifts.Displayed", .displayed), ("PeerInfo.Gifts.Hidden", .hidden)]
        }
        let check = UIImage(systemName: "checkmark")
        for (index, (key, value)) in kinds.enumerated() {
            var action = TelegramContextMenuAction(
                title: L10n.telegram(key),
                image: filter.value.contains(value) ? check : nil,
            ) { [weak self] in self?.toggle(value) }
            action.imageUpdates = filter.map { $0.contains(value) ? check : nil }
                .removeDuplicates()
                .eraseToAnyPublisher()
            action.keepsMenuOpen = true
            action.startsNewSection = index == 0 || value == .displayed
            actions.append(action)
        }
        return actions
    }

    // MARK: Menu

    /// PeerInfoGiftsPaneNode.contextAction: on the account's own profile Pin or Unpin for an upgraded gift, then for
    /// an upgraded gift Copy Link and Share (its t.me/nft link), then Hide or Show on the profile. Add to Collection,
    /// Reorder, Wear and Transfer are not offered.
    func menuActions(for id: Int64, canManage: Bool, host: UIViewController) -> [TelegramContextMenuAction] {
        guard let gift = gifts[id] else { return [] }
        var actions = [TelegramContextMenuAction]()
        let upgraded: TDNativeUpgradedGift? =
            if case .sentGiftUpgraded(let value) = gift.gift {
                value.gift
            } else {
                nil
            }
        if canManage, let upgraded, !gift.receivedGiftId.isEmpty {
            let isPinned = gift.isPinned
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isPinned ? "PeerInfo.Gifts.Context.Unpin" : "PeerInfo.Gifts.Context.Pin"),
                image: UIImage(systemName: isPinned ? "pin.slash" : "pin"),
            ) { [weak self, weak host] in
                guard let self, let host else { return }
                setPinned(gift, upgraded: upgraded, pinned: !isPinned, host: host)
            })
        }
        if let upgraded, !upgraded.name.isEmpty {
            let link = "https://t.me/nft/\(upgraded.name)"
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("PeerInfo.Gifts.Context.CopyLink"),
                image: UIImage(systemName: "link"),
            ) { [weak host] in
                UIPasteboard.setPlainText(link)
                guard let host else { return }
                TelegramUndoToast.show(
                    text: L10n.telegram("Conversation.LinkCopied"), in: host.view, bottomInset: 12, undo: nil,
                )
            })
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("PeerInfo.Gifts.Context.Share"),
                image: UIImage(systemName: "arrowshape.turn.up.right"),
            ) { [weak host] in
                // Telegram's share screen; BetterTG shares the link through the system sheet.
                guard let host, let url = URL(string: link) else { return }
                let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = host.view
                host.present(sheet, animated: true)
            })
        }
        if canManage, !gift.receivedGiftId.isEmpty {
            let isSaved = gift.isSaved
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isSaved ? "PeerInfo.Gifts.Context.Hide" : "PeerInfo.Gifts.Context.Show"),
                image: UIImage(systemName: isSaved ? "eye.slash" : "eye"),
            ) { [weak self, weak host] in
                guard let self, let host else { return }
                setSaved(gift, saved: !isSaved, host: host)
            })
        }
        return actions
    }

    /// GiftsListView's View All Gifts: `updateFilter(.All)`.
    func resetFilter() {
        guard isFiltered else { return }
        filter.send(.all)
        reload()
    }

    private func toggle(_ value: Filter) {
        var updated = filter.value
        if updated.contains(value) {
            updated.remove(value)
        } else {
            updated.insert(value)
        }
        if updated.isDisjoint(with: .kinds) { updated.insert(.unlimited) }
        if updated.isDisjoint(with: .visibility) {
            updated.insert(value == .displayed ? .hidden : .displayed)
        }
        guard updated != filter.value else { return }
        filter.send(updated)
        reload()
    }

    /// ProfileGiftsContext.updateStarGiftPinnedToTop: the gift joins the end of the pinned list or leaves it, up to
    /// TDLib's pinned_gift_count_max.
    private func setPinned(
        _ gift: TDNativeReceivedGift,
        upgraded: TDNativeUpgradedGift,
        pinned: Bool,
        host: UIViewController,
    ) {
        let client = client
        let ownerID = ownerID
        var pinnedIDs = items.compactMap { gifts[$0] }.filter(\.isPinned).map(\.receivedGiftId)
        if pinned {
            pinnedIDs.append(gift.receivedGiftId)
        } else {
            pinnedIDs.removeAll { $0 == gift.receivedGiftId }
        }
        let newIDs = pinnedIDs
        Task { [weak self, weak host] in
            if pinned {
                var limit = 6
                if case .optionValueInteger(let value) = try? await client.getOption(name: "pinned_gift_count_max") {
                    limit = Int(value.value)
                }
                guard newIDs.count <= limit else {
                    if let host {
                        TelegramUndoToast.show(
                            text: L10n.telegramPlural(
                                "PeerInfo.Gifts.ToastPinLimit.Text", count: limit, formattedCount: "\(limit)",
                            ),
                            in: host.view, bottomInset: 12, undo: nil,
                        )
                    }
                    return
                }
            }
            do {
                _ = try await client.send(TDNativeRequests.setPinnedGifts(ownerId: ownerID, receivedGiftIds: newIDs))
            } catch {
                if let host { Self.showError(error, in: host) }
                return
            }
            guard let self else { return }
            reload()
            guard let host else { return }
            if pinned {
                let title = upgraded.title + " #" + Self.formattedNumber(upgraded.number)
                TelegramUndoToast.show(
                    title: L10n.telegram("PeerInfo.Gifts.ToastPinned.TitleNew", title),
                    text: L10n.telegram("PeerInfo.Gifts.ToastPinned.Text"),
                    in: host.view, bottomInset: 12, undo: nil,
                )
            } else {
                TelegramUndoToast.show(
                    text: L10n.telegram("PeerInfo.Gifts.ToastUnpinned.Text"), in: host.view, bottomInset: 12, undo: nil,
                )
            }
        }
    }

    /// ProfileGiftsContext.updateStarGiftAddedToProfile through toggleGiftIsSaved, with Telegram's toast.
    private func setSaved(_ gift: TDNativeReceivedGift, saved: Bool, host: UIViewController) {
        let client = client
        let isChannel =
            if case .messageSenderChat = ownerID {
                true
            } else {
                false
            }
        Task { [weak self, weak host] in
            do {
                _ = try await client.send(TDNativeRequests.toggleGiftIsSaved(
                    receivedGiftId: gift.receivedGiftId, isSaved: saved,
                ))
            } catch {
                if let host { Self.showError(error, in: host) }
                return
            }
            self?.reload()
            guard let host else { return }
            let key =
                switch (saved, isChannel) {
                case (true, true): "Gift.Displayed.ChannelText"
                case (true, false): "Gift.Displayed.NewText"
                case (false, true): "Gift.Hidden.ChannelText"
                case (false, false): "Gift.Hidden.NewText"
                }
            TelegramUndoToast.show(text: L10n.telegram(key), in: host.view, bottomInset: 12, undo: nil)
        }
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

// MARK: - GiftsNoResultsView

/// GiftsListView's `filteredResultsAreEmpty` state: ChatListNoResults played once at 148 pt, No Matching Gifts in
/// 17 pt semibold 20 pt under it, and View All Gifts in the accent colour 18 pt lower, which clears the filter.
final class GiftsNoResultsView: UIView {
    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic,
        decodingStrategy: .legacyCodable,
    ))
    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)

    init(onViewAll: @escaping () -> Void) {
        super.init(frame: .zero)
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        titleLabel.text = L10n.telegram("PeerInfo.Gifts.NoResults")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        button.setTitle(L10n.telegram("PeerInfo.Gifts.NoResults.ViewAll"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.addAction(UIAction { _ in onViewAll() }, for: .touchUpInside)
        for view in [animationView, titleLabel, button] as [UIView] {
            addSubview(view)
        }
        if let path = Bundle.main.path(forResource: "ChatListNoResults", ofType: "tgs") {
            Task { [weak self] in
                guard let animation = await TGSAnimationRepository.animation(at: path), let self else { return }
                animationView.animation = animation
                animationView.play()
            }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 148
        let width = bounds.width - 88
        let titleSize = titleLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let buttonSize = button.sizeThatFits(CGSize(width: width, height: 44))
        let total = side + 20 + titleSize.height + 18 + buttonSize.height
        var y = floor((bounds.height - total) / 2)
        animationView.frame = CGRect(x: floor((bounds.width - side) / 2), y: y, width: side, height: side)
        y += side + 20
        titleLabel.frame = CGRect(
            x: floor((bounds.width - titleSize.width) / 2), y: y, width: titleSize.width, height: titleSize.height,
        )
        y += titleSize.height + 18
        button.frame = CGRect(
            x: floor((bounds.width - buttonSize.width) / 2), y: y, width: buttonSize.width, height: buttonSize.height,
        )
    }
}
