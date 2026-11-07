// GiftInfoViewController.swift

import TDLibKit
import UIKit

// MARK: - GiftInfoViewController

/// GiftViewScreen for a gift on a profile, read only: the gift's sticker at 136 pt on the sheet, or on an upgraded
/// gift's backdrop; the title (Received Gift on the account's own profile, Gift elsewhere, an upgraded gift's name
/// and number), the description, then TableComponent's table and OK. A regular gift lists From, Date, Value,
/// Availability, Status and its message; an upgraded one its Owner, Model, Backdrop and Symbol with their rarity,
/// and how many were issued.
final class GiftInfoViewController: UIViewController {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let convertPeriod = 90 * 86400

    /// Runs after Hide from Profile or Show on Profile, so the grid reads the gift again.
    var onVisibilityChanged: (() -> Void)?

    private let gift: TDNativeReceivedGift
    private let isOwnProfile: Bool
    private let client: TDLibClient
    private let scrollView = UIScrollView()
    private let backgroundLayer = CALayer()
    private let backdropLayer = CAGradientLayer()
    private let patternLayer = GiftPatternLayer()
    private let stickerView = CustomEmojiInlineView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let table = GiftInfoTableView()
    private let okButton = UIButton(configuration: .prominentGlass())

    private let visibilityLabel = UILabel()
    private var isSaved = false
    private var senderName: String?

    private var upgraded: TDNativeUpgradedGift? {
        if case .sentGiftUpgraded(let value) = gift.gift { return value.gift }
        return nil
    }

    private var headerHeight: CGFloat {
        upgraded == nil ? 210 : 240
    }

    /// The visibility line for the account's own gift that it still holds (not converted, not received upgraded
    /// elsewhere): GiftViewScreen's DisplayedInfoNew or HiddenInfoNew.
    private var showsVisibility: Bool {
        isOwnProfile && !gift.receivedGiftId.isEmpty
    }

    /// From (a regular gift's sender, Hidden Name without one) and Owner (an upgraded gift's) as PeerTableCellComponent
    /// rows once TDLib names them.
    /// GiftViewScreen's `value_convert`: the account's own regular gift that TDLib would sell, within
    /// stargifts_convert_period_max (90 days by default) of its arrival.
    private var canConvert: Bool {
        guard isOwnProfile, !gift.receivedGiftId.isEmpty, gift.sellStarCount > 0,
              case .sentGiftRegular = gift.gift else { return false }
        #if DEBUG
            // `-ui-probe-gift-convert` offers the conversion past its period, to see the pill and the alert.
            if ProcessInfo.processInfo.arguments.contains("-ui-probe-gift-convert") { return true }
        #endif
        return Int(Date().timeIntervalSince1970) <= gift.date + Self.convertPeriod
    }

    init(gift: TDNativeReceivedGift, isOwnProfile: Bool, client: TDLibClient) {
        self.gift = gift
        self.isOwnProfile = isOwnProfile
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The sheet is glass, which takes a view's background colour into its effect and lets the presenter show
        // through; a plain layer keeps it opaque, as Telegram's sheet is.
        view.layer.insertSublayer(backgroundLayer, at: 0)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.backgroundLayer.backgroundColor = UIColor.secondarySystemGroupedBackground
                .resolvedColor(with: self.traitCollection)
                .cgColor
        }
        backgroundLayer.backgroundColor = UIColor.secondarySystemGroupedBackground
            .resolvedColor(with: traitCollection)
            .cgColor
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        if let upgraded {
            let colors = upgraded.backdrop.colors
            backdropLayer.type = .radial
            backdropLayer.colors = [UIColor(rgb: colors.centerColor).cgColor, UIColor(rgb: colors.edgeColor).cgColor]
            backdropLayer.backgroundColor = UIColor(rgb: colors.edgeColor).cgColor
            scrollView.layer.addSublayer(backdropLayer)
            patternLayer.masksToBounds = true
            patternLayer.setColor(UIColor(rgb: colors.symbolColor))
            scrollView.layer.addSublayer(patternLayer)
            let symbol = upgraded.symbol.sticker
            let client = client
            Task { [weak self] in
                let image = await GiftSymbolImages.image(for: symbol, client: client)
                self?.patternLayer.setImage(image)
            }
        }
        let sticker: Sticker =
            switch gift.gift {
            case .sentGiftRegular(let value): value.gift.sticker
            case .sentGiftUpgraded(let value): value.gift.model.sticker
            }
        stickerView.configure(sticker: sticker, client: client)
        scrollView.addSubview(stickerView)

        closeButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        ), for: .normal)
        closeButton.tintColor = upgraded == nil ? .label : .white
        closeButton.backgroundColor = upgraded == nil ? .tertiarySystemFill : UIColor.white.withAlphaComponent(0.15)
        closeButton.layer.cornerRadius = 22
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(closeButton)

        titleLabel.attributedText = titleText()
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        scrollView.addSubview(titleLabel)

        descriptionLabel.text = descriptionText()
        descriptionLabel.font = .systemFont(ofSize: 15)
        descriptionLabel.textColor = upgraded.map { UIColor(rgb: $0.backdrop.colors.textColor) } ?? .label
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        scrollView.addSubview(descriptionLabel)

        table.client = client
        table.rows = makeRows()
        scrollView.addSubview(table)

        var configuration = UIButton.Configuration.prominentGlass()
        configuration.title = L10n.telegram("Common.OK")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        okButton.configuration = configuration
        okButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        scrollView.addSubview(okButton)
        resolvePeers()
        if showsVisibility {
            isSaved = gift.isSaved
            visibilityLabel.numberOfLines = 0
            visibilityLabel.textAlignment = .center
            visibilityLabel.isUserInteractionEnabled = true
            visibilityLabel.addGestureRecognizer(UITapGestureRecognizer(
                target: self,
                action: #selector(toggleVisibility),
            ))
            scrollView.addSubview(visibilityLabel)
            updateVisibilityText()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        stickerView.setPlaybackVisible(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stickerView.setPlaybackVisible(false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = view.bounds
        CATransaction.commit()
        scrollView.frame = view.bounds
        let width = view.bounds.width
        let height = layout(width: width)
        scrollView.contentSize = CGSize(width: width, height: height)
        closeButton.frame = CGRect(x: 16 + view.safeAreaInsets.left, y: 16, width: 44, height: 44)
    }

    /// Opens the sheet as tall as its content.
    static func present(
        _ gift: TDNativeReceivedGift,
        isOwnProfile: Bool,
        client: TDLibClient,
        from host: UIViewController,
        onVisibilityChanged: (() -> Void)? = nil,
    ) {
        let controller = GiftInfoViewController(gift: gift, isOwnProfile: isOwnProfile, client: client)
        controller.onVisibilityChanged = onVisibilityChanged
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.custom { [weak controller] context in
                min(context.maximumDetentValue, controller?.contentHeight(width: host.view.bounds.width) ?? 500)
            }]
            sheet.prefersGrabberVisible = false
        }
        host.present(controller, animated: true)
    }

    /// The attribute's rarity as GiftViewScreen's badge: a share in per mille, or the tier's name and colour.
    private static func rarity(_ rarity: TDNativeUpgradedGiftAttributeRarity) -> (String, UIColor) {
        switch rarity {
        case .upgradedGiftAttributeRarityPerMille(let value):
            let text = value.perMille == 0 ? "<" + percentage(0.1) : percentage(Float(value.perMille) * 0.1)
            return (text, .tintColor)
        case .upgradedGiftAttributeRarityUncommon:
            return (L10n.telegram("Gift.Attribute.Uncommon"), UIColor(rgb: 0x22B447))
        case .upgradedGiftAttributeRarityRare:
            return (L10n.telegram("Gift.Attribute.Rare"), UIColor(rgb: 0x25A3B9))
        case .upgradedGiftAttributeRarityEpic:
            return (L10n.telegram("Gift.Attribute.Epic"), UIColor(rgb: 0xAF52DE))
        case .upgradedGiftAttributeRarityLegendary:
            return (L10n.telegram("Gift.Attribute.Legendary"), UIColor(rgb: 0xD57E32))
        }
    }

    /// GiftViewScreen's formatPercentage.
    private static func percentage(_ value: Float) -> String {
        String(format: "%0.1f", value)
            .replacing(".0", with: "")
            .replacing(",0", with: "") + "%"
    }

    private static func formatted(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func removingLinks(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*\[[^\]]*\]\(\)"#, with: "", options: .regularExpression)
    }

    /// The sheet's height for a width, from GiftViewScreen's vertical steps.
    func contentHeight(width: CGFloat) -> CGFloat {
        loadViewIfNeeded()
        return layout(width: width, apply: false)
    }

    @discardableResult private func layout(width: CGFloat, apply: Bool = true) -> CGFloat {
        let sideInset: CGFloat = 16 + view.safeAreaInsets.left
        let header = headerHeight
        // The title's centre stands at 196 pt and the description starts at 207 pt; an upgraded gift's backdrop runs on
        // 16 pt under the description.
        let titleWidth = width - sideInset * 2 - 60
        let titleSize = titleLabel.sizeThatFits(CGSize(width: titleWidth, height: 40))
        let titleCenterY: CGFloat = 196
        let descriptionWidth = width - sideInset * 2 - 20
        let descriptionSize = descriptionLabel.text?.isEmpty == false
            ? descriptionLabel.sizeThatFits(CGSize(width: descriptionWidth, height: .greatestFiniteMagnitude))
            : .zero
        let backdropHeight = max(header, 207 + descriptionSize.height + 16)
        var originY: CGFloat =
            if upgraded != nil {
                backdropHeight + 16
            } else if descriptionSize.height > 0 {
                207 + descriptionSize.height + 21
            } else {
                header + 9
            }
        let tableWidth = width - sideInset * 2
        let tableHeight = table.height(for: tableWidth)
        let tableFrame = CGRect(x: sideInset, y: originY, width: tableWidth, height: tableHeight)
        originY += tableHeight + 23
        // The visibility line 5 pt up from the button's place, then 16 pt to the button.
        var visibilityFrame = CGRect.zero
        if showsVisibility {
            let size = visibilityLabel.sizeThatFits(CGSize(
                width: width - sideInset * 2,
                height: .greatestFiniteMagnitude,
            ))
            originY -= 5
            visibilityFrame = CGRect(
                x: floor((width - size.width) / 2),
                y: originY,
                width: size.width,
                height: size.height,
            )
            originY += size.height + 16
        }
        let buttonFrame = CGRect(x: sideInset, y: originY, width: width - sideInset * 2, height: 52)
        originY += 52 + max(view.safeAreaInsets.bottom, 16) + 8
        guard apply else { return originY }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // PeerInfoCoverComponent's gradient centred 104 pt down, stretched up past the top for overscroll.
        backdropLayer.frame = CGRect(x: 0, y: -400, width: width, height: backdropHeight + 400)
        backdropLayer.startPoint = CGPoint(x: 0.5, y: (400 + 104) / (backdropHeight + 400))
        backdropLayer.endPoint = CGPoint(x: 1, y: 1)
        // GiftCompositionComponent's cover: the pattern around 104 pt down in a 300 pt tall area.
        patternLayer.frame = backdropLayer.frame
        patternLayer.layout(center: CGPoint(x: width / 2, y: 400 + 104), defaultHeight: 300)
        CATransaction.commit()
        stickerView.frame = CGRect(x: floor((width - 136) / 2), y: 88 - 68, width: 136, height: 136)
        titleLabel.frame = CGRect(
            x: floor((width - titleSize.width) / 2),
            y: floor(titleCenterY - titleSize.height / 2),
            width: titleSize.width,
            height: titleSize.height,
        )
        let descriptionY = max(207, titleLabel.frame.maxY + 2)
        descriptionLabel.frame = CGRect(
            x: floor((width - descriptionSize.width) / 2),
            y: descriptionY,
            width: descriptionSize.width,
            height: descriptionSize.height,
        )
        table.frame = tableFrame
        visibilityLabel.frame = visibilityFrame
        okButton.frame = buttonFrame
        return originY
    }

    /// "This gift is visible. Hide from Profile >" or, after the hidden icon, "This gift is hidden. Show on Profile
    /// >": 13 pt secondary text, the link in the accent colour. A tap on the line toggles it (toggleGiftIsSaved).
    private func updateVisibilityText() {
        let raw = L10n.telegram(isSaved ? "Gift.View.DisplayedInfoNew" : "Gift.View.HiddenInfoNew")
        let font = UIFont.systemFont(ofSize: 13)
        let result = NSMutableAttributedString()
        if !isSaved, let hidden = UIImage(named: "Gift/Hidden")?.withTintColor(
            .secondaryLabel,
            renderingMode: .alwaysOriginal,
        ) {
            let attachment = NSTextAttachment(image: hidden)
            attachment.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "  "))
        }
        // The Markdown link: plain text before it, the link's text in the accent colour with its chevron.
        if let open = raw.range(of: "["), let close = raw.range(of: "]()") {
            result.append(NSAttributedString(
                string: String(raw[..<open.lowerBound]),
                attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel],
            ))
            let link = String(raw[open.upperBound..<close.lowerBound]).replacing(" >", with: "\u{00A0}›")
            result.append(NSAttributedString(
                string: link,
                attributes: [.font: font, .foregroundColor: UIColor.tintColor],
            ))
        } else {
            result.append(NSAttributedString(
                string: raw,
                attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel],
            ))
        }
        visibilityLabel.attributedText = result
        visibilityLabel.accessibilityTraits = .button
    }

    @objc private func toggleVisibility() {
        let saved = !isSaved
        let client = client
        let giftID = gift.receivedGiftId
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.toggleGiftIsSaved(receivedGiftId: giftID, isSaved: saved))
            } catch {
                return
            }
            guard let self else { return }
            isSaved = saved
            updateVisibilityText()
            view.setNeedsLayout()
            onVisibilityChanged?()
        }
    }

    // MARK: Content

    private func titleText() -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 20, weight: .bold)
        guard let upgraded else {
            let title = isOwnProfile ? L10n.telegram("Gift.View.ReceivedTitle") : L10n.telegram("Gift.View.Title")
            return NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: UIColor.label])
        }
        // formatCollectibleNumber, smaller from four digits on, in the backdrop's text colour.
        let numberFont = upgraded.number < 1000 ? font : .systemFont(ofSize: 15, weight: .bold)
        let result = NSMutableAttributedString(
            string: upgraded.title + " ",
            attributes: [.font: font, .foregroundColor: UIColor.white],
        )
        result.append(NSAttributedString(
            string: "#" + Self.formatted(upgraded.number),
            attributes: [.font: numberFont, .foregroundColor: UIColor(rgb: upgraded.backdrop.colors.textColor)],
        ))
        return result
    }

    /// GiftViewScreen's description for a profile gift: an upgraded gift's model, or for the account's own regular
    /// gift whether it can be upgraded or converted; nothing for someone else's regular gift.
    private func descriptionText() -> String {
        if let upgraded { return upgraded.model.name }
        guard isOwnProfile, case .sentGiftRegular(let value) = gift.gift else { return "" }
        if value.gift.overallLimits != nil {
            return gift.canBeUpgraded
                ? L10n.telegram("Gift.View.UpgradeDescription")
                : L10n.telegram("Gift.View.NoConvertDescription")
        }
        guard gift.sellStarCount > 0 else { return L10n.telegram("Gift.View.NoConvertDescription") }
        let count = Int(gift.sellStarCount)
        let stars = L10n.telegramPlural(
            "Gift.View.KeepOrConvertDescription.Stars",
            count: count,
            formattedCount: Self.formatted(count),
        )
        // The More About Stars link has no screen here.
        return Self.removingLinks(L10n.telegram("Gift.View.KeepOrConvertDescription", stars))
    }

    private func makeRows() -> [GiftInfoTableView.Row] {
        var rows = [GiftInfoTableView.Row]()
        switch gift.gift {
        case .sentGiftRegular(let value):
            let regular = value.gift
            rows.append(.init(id: "from", title: L10n.telegram("Gift.View.From"), value: .peer(nil)))
            if gift.date > 0 {
                rows.append(.init(
                    id: "date",
                    title: L10n.telegram("Gift.View.Date"),
                    value: .text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(gift.date)))),
                ))
            }
            let stars = regular.starCount + max(0, gift.prepaidUpgradeStarCount)
            let valueText = Self.formatted(Int(stars)) + "⭐️"
            if canConvert {
                let count = Int(gift.sellStarCount)
                let title = L10n.telegram("Gift.View.Sale", L10n.telegramPlural(
                    "Gift.View.Sale.Stars", count: count, formattedCount: Self.formatted(count),
                ))
                rows.append(.init(
                    id: "value",
                    title: L10n.telegram("Gift.View.Value"),
                    value: .valueAction(valueText, title) { [weak self] in self?.confirmConvert() },
                ))
            } else {
                rows.append(.init(id: "value", title: L10n.telegram("Gift.View.Value"), value: .text(valueText)))
            }
            if let limits = regular.overallLimits {
                rows.append(.init(
                    id: "availability",
                    title: L10n.telegram("Gift.View.Availability"),
                    value: .text(L10n.telegram(
                        "Gift.View.Availability.NewOf",
                        Self.formatted(limits.remainingCount),
                        Self.formatted(limits.totalCount),
                    )),
                ))
            }
            if gift.canBeUpgraded {
                rows.append(.init(
                    id: "status",
                    title: L10n.telegram("Gift.View.Status"),
                    value: .text(L10n.telegram("Gift.View.Status.NonUnique")),
                ))
            }
            if !gift.text.text.isEmpty {
                rows.append(.init(id: "text", title: nil, value: .text(gift.text.text)))
            }
        case .sentGiftUpgraded(let value):
            let upgraded = value.gift
            if upgraded.ownerId != nil {
                rows.append(.init(id: "owner", title: L10n.telegram("Gift.Unique.Owner"), value: .peer(nil)))
            } else if !upgraded.ownerName.isEmpty {
                rows.append(.init(
                    id: "owner",
                    title: L10n.telegram("Gift.Unique.Owner"),
                    value: .text(upgraded.ownerName),
                ))
            }
            rows.append(.init(
                id: "model",
                title: L10n.telegram("Gift.Unique.Model"),
                value: .attribute(upgraded.model.name, Self.rarity(upgraded.model.rarity)),
            ))
            rows.append(.init(
                id: "backdrop",
                title: L10n.telegram("Gift.Unique.Backdrop"),
                value: .attribute(upgraded.backdrop.name, Self.rarity(upgraded.backdrop.rarity)),
            ))
            rows.append(.init(
                id: "symbol",
                title: L10n.telegram("Gift.Unique.Symbol"),
                value: .attribute(upgraded.symbol.name, Self.rarity(upgraded.symbol.rarity)),
            ))
            let issued = Self.formatted(upgraded.totalUpgradedCount) + "/" + Self.formatted(upgraded.maxUpgradedCount)
            rows.append(.init(
                id: "availability",
                title: L10n.telegram("Gift.Unique.Availability"),
                value: .text(L10n.telegram("Gift.Unique.Issued", issued)),
            ))
        }
        return rows
    }

    /// convertToStars: Convert Gift to Stars with the sender, the Stars and the days left, then sellGift, "Gift
    /// Converted" and the sheet closes.
    private func confirmConvert() {
        let count = Int(gift.sellStarCount)
        let daysLeft = max(
            1,
            Int(ceil(Double(gift.date + Self.convertPeriod - Int(Date().timeIntervalSince1970)) / 86400)),
        )
        let text = L10n.telegram(
            "Gift.Convert.Period.Text",
            senderName ?? L10n.telegram("Gift.View.HiddenName"),
            L10n.telegramPlural("Gift.Convert.Period.Stars", count: count, formattedCount: Self.formatted(count)),
            L10n.telegramPlural("Gift.Convert.Period.Days", count: daysLeft, formattedCount: "\(daysLeft)"),
        )
        .replacing("**", with: "")
        let alert = UIAlertController(title: L10n.telegram("Gift.Convert.Title"), message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Gift.Convert.Convert"), style: .default) { [weak self] _ in
            self?.convert(count: count)
        })
        present(alert, animated: true)
    }

    private func convert(count: Int) {
        let client = client
        let giftID = gift.receivedGiftId
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.sellGift(businessConnectionId: "", receivedGiftId: giftID))
            } catch {
                guard let self else { return }
                TelegramUndoToast.show(
                    text: (error as? TDLibError)?.message ?? error.localizedDescription,
                    in: view, bottomInset: 12, undo: nil,
                )
                return
            }
            guard let self else { return }
            let host = presentingViewController
            onVisibilityChanged?()
            dismiss(animated: true) {
                guard let host else { return }
                TelegramUndoToast.show(
                    title: L10n.telegram("Gift.Convert.Success.Title"),
                    text: L10n.telegram("Gift.Convert.Success.Text", L10n.telegramPlural(
                        "Gift.Convert.Success.Text.Stars", count: count, formattedCount: Self.formatted(count),
                    ))
                    .replacing("**", with: ""),
                    in: host.view, bottomInset: 12, undo: nil,
                )
            }
        }
    }

    private func resolvePeers() {
        let sender: MessageSender?
        let rowID: String
        switch gift.gift {
        case .sentGiftRegular:
            sender = gift.senderId
            rowID = "from"
        case .sentGiftUpgraded(let value):
            sender = value.gift.ownerId
            rowID = "owner"
        }
        guard let sender else { return }
        let client = client
        Task { [weak self] in
            guard let peer = await SettingsPeer.resolve(sender, client: client), let self else { return }
            senderName = peer.title
            table.setPeer(peer, client: client, forRow: rowID)
            view.setNeedsLayout()
        }
    }
}

// MARK: - GiftInfoTableView

/// TableComponent: rows at least 40 pt tall with 11 pt of padding, titles in 15 pt in a left column at least 100 pt
/// wide on the secondary background, values beside them, 1 pt borders and 14 pt outer corners. A row without a title
/// spans the table.
final class GiftInfoTableView: UIView {
    struct Row {
        enum Value {
            case text(String)
            /// PeerTableCellComponent: a 22 pt avatar and the name in the accent colour, Hidden Name without a peer.
            case peer(SettingsPeer?)
            /// An attribute's name with its rarity badge (ButtonContentComponent: 11 pt on a pill of its colour).
            case attribute(String, (String, UIColor))
            /// A value with an accent pill that acts, as Value's "sell for N Stars".
            case valueAction(String, String, () -> Void)
        }

        let id: String
        let title: String?
        var value: Value
    }

    private static let verticalPadding: CGFloat = 11
    private static let horizontalPadding: CGFloat = 12
    private static let font = UIFont.systemFont(ofSize: 15)

    var rows = [Row]() {
        didSet { rebuild() }
    }

    var client: TDLibClient?

    private var titleLabels = [UILabel?]()
    private var valueViews = [UIView]()
    private let titleColumn = CALayer()
    private let borderLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.addSublayer(titleColumn)
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rowFrames = frames(for: bounds.width)
        let leftWidth = leftColumnWidth()
        let hasTitles = rows.contains { $0.title != nil }
        let titledHeight = zip(rows, rowFrames).filter { $0.0.title != nil }.map(\.1.maxY).max() ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleColumn.frame = CGRect(x: 0, y: 0, width: hasTitles ? leftWidth : 0, height: titledHeight)
        titleColumn.backgroundColor = UIColor.tertiarySystemFill.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
        for index in rows.indices {
            let frame = rowFrames[index]
            let valueView = valueViews[index]
            if let label = titleLabels[index] {
                let size = label.sizeThatFits(CGSize(width: leftWidth - Self.horizontalPadding * 2, height: 100))
                label.frame = CGRect(
                    x: Self.horizontalPadding,
                    y: frame.minY + Self.verticalPadding,
                    width: min(size.width, leftWidth - Self.horizontalPadding * 2),
                    height: size.height,
                )
                let valueWidth = bounds.width - leftWidth - Self.horizontalPadding * 2
                let valueSize = valueView.sizeThatFits(CGSize(width: valueWidth, height: .greatestFiniteMagnitude))
                valueView.frame = CGRect(
                    x: leftWidth + Self.horizontalPadding,
                    y: frame.minY + floor((frame.height - valueSize.height) / 2),
                    width: min(valueSize.width, valueWidth),
                    height: valueSize.height,
                )
            } else {
                let valueWidth = bounds.width - Self.horizontalPadding * 2
                let valueSize = valueView.sizeThatFits(CGSize(width: valueWidth, height: .greatestFiniteMagnitude))
                valueView.frame = CGRect(
                    x: floor((bounds.width - valueSize.width) / 2),
                    y: frame.minY + Self.verticalPadding,
                    width: valueSize.width,
                    height: valueSize.height,
                )
            }
        }
        // The outer border, each row's bottom line and the column line.
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 13.5)
        for frame in rowFrames.dropLast() {
            path.move(to: CGPoint(x: 0, y: frame.maxY - 0.5))
            path.addLine(to: CGPoint(x: bounds.width, y: frame.maxY - 0.5))
        }
        if hasTitles {
            path.move(to: CGPoint(x: leftWidth - 0.5, y: 0))
            path.addLine(to: CGPoint(x: leftWidth - 0.5, y: titledHeight))
        }
        borderLayer.frame = bounds
        borderLayer.path = path.cgPath
        borderLayer.strokeColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }

    private static func makeValueView(_ value: Row.Value, client: TDLibClient?) -> UIView {
        switch value {
        case .text(let text):
            let label = UILabel()
            label.text = text
            label.font = font
            label.textColor = .label
            label.numberOfLines = 0
            return label
        case .peer(let peer):
            return GiftInfoPeerView(peer: peer, client: client)
        case .attribute(let name, let rarity):
            return GiftInfoAttributeView(name: name, badge: rarity.0, color: rarity.1)
        case .valueAction(let text, let title, let action):
            return GiftInfoAttributeView(name: text, badge: title, color: .tintColor, action: action)
        }
    }

    func setPeer(_ peer: SettingsPeer, client: TDLibClient, forRow id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        self.client = client
        rows[index].value = .peer(peer)
    }

    func height(for width: CGFloat) -> CGFloat {
        frames(for: width).last?.maxY ?? 0
    }

    private func rebuild() {
        titleLabels.forEach { $0?.removeFromSuperview() }
        valueViews.forEach { $0.removeFromSuperview() }
        titleLabels = rows.map { row in
            guard let title = row.title else { return nil }
            let label = UILabel()
            label.text = title
            label.font = Self.font
            label.textColor = .label
            addSubview(label)
            return label
        }
        valueViews = rows.map { row in
            let view = Self.makeValueView(row.value, client: client)
            addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    private func leftColumnWidth() -> CGFloat {
        let widest = rows.compactMap(\.title)
            .map {
                ceil(($0 as NSString).size(withAttributes: [.font: Self.font]).width)
            }
            .max() ?? 0
        return max(100, widest + Self.horizontalPadding * 2)
    }

    private func frames(for width: CGFloat) -> [CGRect] {
        let leftWidth = leftColumnWidth()
        var originY: CGFloat = 0
        var result = [CGRect]()
        for (index, row) in rows.enumerated() {
            let valueView = valueViews.indices.contains(index) ? valueViews[index] : nil
            let valueWidth = row.title == nil
                ? width - Self.horizontalPadding * 2
                : width - leftWidth - Self.horizontalPadding * 2
            let valueHeight = valueView?.sizeThatFits(CGSize(width: valueWidth, height: .greatestFiniteMagnitude))
                .height ?? 18
            let titleHeight = ceil(Self.font.lineHeight)
            let height = max(40, max(titleHeight, valueHeight) + Self.verticalPadding * 2)
            result.append(CGRect(x: 0, y: originY, width: width, height: height))
            originY += height
        }
        return result
    }
}

// MARK: - GiftInfoPeerView

/// PeerTableCellComponent: the 22 pt avatar, 6 pt, then the name in the accent colour, or Telegram's anonymous
/// sender and Hidden Name in the text colour.
private final class GiftInfoPeerView: UIView {
    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()

    init(peer: SettingsPeer?, client: TDLibClient?) {
        super.init(frame: .zero)
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        addSubview(avatarView)
        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        if let peer {
            nameLabel.text = peer.title
            nameLabel.textColor = .tintColor
            if let client {
                avatarView.configure(
                    file: peer.file,
                    minithumbnail: peer.minithumbnail,
                    placeholder: peer.placeholder,
                    client: client,
                )
            }
        } else {
            nameLabel.text = L10n.telegram("Gift.View.HiddenName")
            nameLabel.textColor = .label
            if let client {
                avatarView.configure(
                    file: nil,
                    minithumbnail: nil,
                    placeholder: TelegramAvatarPlaceholder(
                        peerID: 2_666_000, accentColorID: 0, upgradedGiftColors: nil, letters: [], isDeleted: false,
                    ),
                    client: client,
                )
            }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let nameSize = nameLabel.sizeThatFits(CGSize(width: size.width - 28, height: size.height))
        return CGSize(width: min(size.width, 28 + nameSize.width), height: max(22, nameSize.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarView.frame = CGRect(x: 0, y: floor((bounds.height - 22) / 2), width: 22, height: 22)
        nameLabel.frame = CGRect(x: 28, y: 0, width: bounds.width - 28, height: bounds.height)
    }
}

// MARK: - GiftInfoAttributeView

/// An attribute row's value: the name, 4 pt, then the rarity on an 18 pt pill of its colour at 0.1.
private final class GiftInfoAttributeView: UIView {
    private let nameLabel = UILabel()
    private let badgeLabel = UILabel()
    private let badgeBackground = CALayer()

    private var action: (() -> Void)?

    init(name: String, badge: String, color: UIColor, action: (() -> Void)? = nil) {
        super.init(frame: .zero)
        self.action = action
        if action != nil {
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(badgeTapped(_:))))
        }
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.textColor = .label
        addSubview(nameLabel)
        badgeBackground.backgroundColor = color.withAlphaComponent(0.1).cgColor
        badgeBackground.cornerRadius = 9
        layer.addSublayer(badgeBackground)
        badgeLabel.text = badge
        badgeLabel.font = .systemFont(ofSize: 11)
        badgeLabel.textColor = color
        addSubview(badgeLabel)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let badgeWidth = badgeLabel.sizeThatFits(.zero).width + 12
        let nameSize = nameLabel.sizeThatFits(CGSize(width: size.width - badgeWidth - 4, height: size.height))
        return CGSize(width: min(size.width, nameSize.width + 4 + badgeWidth), height: max(18, nameSize.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let badgeSize = badgeLabel.sizeThatFits(.zero)
        let badgeWidth = badgeSize.width + 12
        let nameWidth = min(nameLabel.sizeThatFits(bounds.size).width, bounds.width - badgeWidth - 4)
        nameLabel.frame = CGRect(x: 0, y: 0, width: nameWidth, height: bounds.height)
        let badgeFrame = CGRect(x: nameWidth + 4, y: floor((bounds.height - 18) / 2), width: badgeWidth, height: 18)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badgeBackground.frame = badgeFrame
        CATransaction.commit()
        badgeLabel.frame = CGRect(
            x: badgeFrame.minX + 6,
            y: badgeFrame.minY + floor((18 - badgeSize.height) / 2),
            width: badgeSize.width,
            height: badgeSize.height,
        )
    }

    /// Only the pill acts.
    @objc private func badgeTapped(_ gesture: UITapGestureRecognizer) {
        guard badgeBackground.frame.insetBy(dx: -8, dy: -8).contains(gesture.location(in: self)) else { return }
        action?()
    }
}
