// GiftUpgradeViewController.swift

import TDLibKit
import UIKit

// MARK: - GiftUpgradeViewController

/// GiftViewScreen's upgrade preview for the account's own regular gift: the header cycles the upgrade's models,
/// backdrops and symbols from getGiftUpgradePreview under Upgrade Gift and its description, then the Unique, Tradable
/// and Wearable perks, "Add sender's name (and comment)" (kept by default for a prepaid upgrade), and "Upgrade for
/// N Stars", or Confirm when the sender prepaid it. upgradeGift then closes the sheets with "The gift is now
/// collectible".
final class GiftUpgradeViewController: UIViewController {
    /// Runs once the gift is upgraded and the sheets are closing; the grid reads the gifts again.
    var onUpgraded: (() -> Void)?

    private let gift: TDNativeReceivedGift
    private let regular: TDNativeGift
    private let client: TDLibClient
    private let scrollView = UIScrollView()
    private let backgroundLayer = CALayer()
    private let backdropLayer = CAGradientLayer()
    private let patternLayer = GiftPatternLayer()
    private let stickerView = CustomEmojiInlineView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private var perkViews = [GiftUpgradePerkView]()
    private let keepButton = UIButton(type: .system)
    private let checkView = UIImageView()
    private let keepLabel = UILabel()
    private let upgradeButton = UIButton(configuration: .prominentGlass())
    private var keepOriginalDetails: Bool
    private var preview: TDNativeGiftUpgradePreview?
    private var variantIndex = 0
    private var cycleTimer: Timer?
    private var isUpgrading = false

    private var isPrepaid: Bool {
        gift.prepaidUpgradeStarCount > 0
    }

    /// The price in effect now: the latest of the preview's prices that has started, else the gift's.
    private var price: Int64 {
        let now = Int(Date().timeIntervalSince1970)
        return preview?.prices.last { $0.date <= now }?.starCount ?? regular.upgradeStarCount
    }

    init(gift: TDNativeReceivedGift, regular: TDNativeGift, client: TDLibClient) {
        self.gift = gift
        self.regular = regular
        self.client = client
        let hasSender = gift.senderId != nil
        self.keepOriginalDetails = gift.prepaidUpgradeStarCount > 0 && hasSender && !gift.isUpgradeSeparate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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

        backdropLayer.type = .radial
        backdropLayer.colors = [UIColor.systemGray.cgColor, UIColor.systemGray2.cgColor]
        scrollView.layer.addSublayer(backdropLayer)
        patternLayer.masksToBounds = true
        scrollView.layer.addSublayer(patternLayer)
        stickerView.configure(sticker: regular.sticker, client: client)
        scrollView.addSubview(stickerView)

        closeButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        ), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        closeButton.layer.cornerRadius = 22
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(closeButton)

        titleLabel.text = L10n.telegram("Gift.Upgrade.Title")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        scrollView.addSubview(titleLabel)
        descriptionLabel.text = L10n.telegram("Gift.Upgrade.Description")
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        scrollView.addSubview(descriptionLabel)

        perkViews = [
            GiftUpgradePerkView(
                symbol: "sparkles",
                title: L10n.telegram("Gift.Upgrade.Unique.Title"),
                text: L10n.telegram("Gift.Upgrade.Unique.Description"),
            ),
            GiftUpgradePerkView(
                symbol: "arrow.left.arrow.right.circle",
                title: L10n.telegram("Gift.Upgrade.Tradable.Title"),
                text: L10n.telegram("Gift.Upgrade.Tradable.Description"),
            ),
            GiftUpgradePerkView(
                symbol: "crown",
                title: L10n.telegram("Gift.Upgrade.Wearable.Title"),
                text: L10n.telegram("Gift.Upgrade.Wearable.Text"),
            ),
        ]
        perkViews.forEach(scrollView.addSubview)

        // An incoming gift with a sender offers to keep the sender's name, and the comment when there is one.
        if gift.senderId != nil {
            keepLabel.text = L10n.telegram(
                gift.text.text.isEmpty ? "Gift.Upgrade.AddName" : "Gift.Upgrade.AddNameAndComment",
            )
            keepLabel.font = .systemFont(ofSize: 13)
            keepLabel.textColor = .secondaryLabel
            keepButton.addSubview(checkView)
            keepButton.addSubview(keepLabel)
            keepButton.accessibilityLabel = keepLabel.text
            keepButton.addAction(UIAction { [weak self] _ in self?.toggleKeep() }, for: .touchUpInside)
            scrollView.addSubview(keepButton)
            updateCheck()
        }

        upgradeButton.addAction(UIAction { [weak self] _ in self?.upgrade() }, for: .touchUpInside)
        scrollView.addSubview(upgradeButton)
        updateButton()
        loadPreview()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        stickerView.setPlaybackVisible(true)
        cycleTimer?.invalidate()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.showNextVariant(animated: true) }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stickerView.setPlaybackVisible(false)
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = view.bounds
        CATransaction.commit()
        scrollView.frame = view.bounds
        let height = layout(width: view.bounds.width)
        scrollView.contentSize = CGSize(width: view.bounds.width, height: height)
        closeButton.frame = CGRect(x: 16 + view.safeAreaInsets.left, y: 16, width: 44, height: 44)
    }

    /// Opens the sheet as tall as its content.
    static func present(
        _ gift: TDNativeReceivedGift,
        regular: TDNativeGift,
        client: TDLibClient,
        from host: UIViewController,
        onUpgraded: @escaping () -> Void,
    ) {
        let controller = GiftUpgradeViewController(gift: gift, regular: regular, client: client)
        controller.onUpgraded = onUpgraded
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.custom { [weak controller] context in
                min(context.maximumDetentValue, controller?.contentHeight(width: host.view.bounds.width) ?? 600)
            }]
        }
        host.present(controller, animated: true)
    }

    func contentHeight(width: CGFloat) -> CGFloat {
        loadViewIfNeeded()
        return layout(width: width, apply: false)
    }

    /// GiftViewScreen's upgrade preview: a 246 pt header, the title and description centred around 196 pt, 24 pt to
    /// the perks inset 32 pt, 16 pt to the check, then the button.
    @discardableResult private func layout(width: CGFloat, apply: Bool = true) -> CGFloat {
        let sideInset: CGFloat = 16 + view.safeAreaInsets.left
        let header: CGFloat = 246
        let textWidth = width - sideInset * 2 - 40
        let titleSize = titleLabel.sizeThatFits(CGSize(width: textWidth, height: 40))
        let descriptionSize = descriptionLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let total = titleSize.height + 6 + descriptionSize.height
        var originY = header + 24
        let perksInset = sideInset + 16
        var perkFrames = [CGRect]()
        for perk in perkViews {
            let size = perk.sizeThatFits(CGSize(width: width - perksInset * 2, height: .greatestFiniteMagnitude))
            perkFrames.append(CGRect(x: perksInset, y: originY, width: width - perksInset * 2, height: size.height))
            originY += size.height + 20
        }
        originY -= 4
        var keepFrame = CGRect.zero
        if keepButton.superview != nil {
            let labelSize = keepLabel.sizeThatFits(CGSize(width: width - sideInset * 2 - 28, height: 40))
            let keepWidth = 18 + 10 + labelSize.width
            keepFrame = CGRect(x: floor((width - keepWidth) / 2), y: originY, width: keepWidth, height: 30)
            originY += 30 + 16
        }
        let buttonFrame = CGRect(x: sideInset, y: originY, width: width - sideInset * 2, height: 52)
        originY += 52 + max(view.safeAreaInsets.bottom, 16) + 8
        guard apply else { return originY }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.frame = CGRect(x: 0, y: -400, width: width, height: header + 400)
        backdropLayer.startPoint = CGPoint(x: 0.5, y: (400 + 104) / (header + 400))
        backdropLayer.endPoint = CGPoint(x: 1, y: 1)
        patternLayer.frame = backdropLayer.frame
        patternLayer.layout(center: CGPoint(x: width / 2, y: 400 + 104), defaultHeight: 300)
        CATransaction.commit()
        stickerView.frame = CGRect(x: floor((width - 136) / 2), y: 88 - 68, width: 136, height: 136)
        titleLabel.frame = CGRect(
            x: floor((width - titleSize.width) / 2),
            y: floor(194 - total / 2),
            width: titleSize.width,
            height: titleSize.height,
        )
        descriptionLabel.frame = CGRect(
            x: floor((width - descriptionSize.width) / 2),
            y: titleLabel.frame.maxY + 6,
            width: descriptionSize.width,
            height: descriptionSize.height,
        )
        for (perk, frame) in zip(perkViews, perkFrames) {
            perk.frame = frame
        }
        keepButton.frame = keepFrame
        checkView.frame = CGRect(x: 0, y: 6, width: 18, height: 18)
        keepLabel.frame = CGRect(x: 28, y: 0, width: keepFrame.width - 28, height: 30)
        upgradeButton.frame = buttonFrame
        return originY
    }

    // MARK: Preview

    private func loadPreview() {
        let client = client
        let giftID = regular.id
        Task { [weak self] in
            var preview = try? await client.send(TDNativeRequests.getGiftUpgradePreview(regularGiftId: giftID))
            #if DEBUG
                // `-ui-probe-gift-upgrade` previews an upgradable gift from the catalogue when this one has none.
                if preview?.models.isEmpty != false,
                   ProcessInfo.processInfo.arguments.contains("-ui-probe-gift-upgrade"),
                   let other = await (try? client.send(TDNativeRequests.getAvailableGifts()))?.gifts
                   .first(where: { $0.gift.upgradeStarCount > 0 })
                {
                    preview = try? await client.send(TDNativeRequests.getGiftUpgradePreview(
                        regularGiftId: other.gift.id,
                    ))
                }
            #endif
            guard let self, let preview else { return }
            self.preview = preview
            updateButton()
            showNextVariant(animated: false)
        }
    }

    /// GiftCompositionComponent's `.preview`: the next model, backdrop and symbol, crossfading.
    private func showNextVariant(animated: Bool) {
        guard let preview, !preview.models.isEmpty else { return }
        let model = preview.models[variantIndex % preview.models.count]
        let backdrop = preview.backdrops.isEmpty ? nil : preview.backdrops[variantIndex % preview.backdrops.count]
        let symbol = preview.symbols.isEmpty ? nil : preview.symbols[variantIndex % preview.symbols.count]
        variantIndex += 1
        if animated {
            let fade = CATransition()
            fade.duration = 0.3
            fade.type = .fade
            backdropLayer.add(fade, forKey: "variant")
            patternLayer.add(fade, forKey: "variant")
            stickerView.layer.add(fade, forKey: "variant")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let backdrop {
            let colors = backdrop.colors
            backdropLayer.colors = [UIColor(rgb: colors.centerColor).cgColor, UIColor(rgb: colors.edgeColor).cgColor]
            backdropLayer.backgroundColor = UIColor(rgb: colors.edgeColor).cgColor
            patternLayer.setColor(UIColor(rgb: colors.symbolColor))
            descriptionLabel.textColor = UIColor(rgb: colors.textColor)
        }
        CATransaction.commit()
        stickerView.configure(sticker: model.sticker, client: client)
        stickerView.setPlaybackVisible(view.window != nil)
        if let symbol {
            let client = client
            Task { [weak self] in
                let image = await GiftSymbolImages.image(for: symbol.sticker, client: client)
                self?.patternLayer.setImage(image)
            }
        }
    }

    private func toggleKeep() {
        keepOriginalDetails.toggle()
        updateCheck()
    }

    private func updateCheck() {
        checkView.image = UIImage(
            systemName: keepOriginalDetails ? "checkmark.circle.fill" : "circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17),
        )
        checkView.tintColor = keepOriginalDetails ? .tintColor : .tertiaryLabel
        keepButton.accessibilityTraits = keepOriginalDetails ? [.button, .selected] : .button
    }

    /// Confirm for a prepaid upgrade, "Upgrade for N Stars" otherwise, and Upgrade until the price is known.
    private func updateButton() {
        var configuration = upgradeButton.configuration ?? .prominentGlass()
        let price = price
        configuration.title =
            if isPrepaid {
                L10n.telegram("Gift.Upgrade.Confirm")
            } else if price > 0 {
                L10n.telegram("Gift.Upgrade.UpgradeFor", L10n.telegramPlural(
                    "Gift.Transfer.Confirmation.Text.Stars",
                    count: Int(price),
                    formattedCount: GiftActions.formatted(Int(price)),
                ))
            } else {
                L10n.telegram("Gift.Upgrade.Upgrade")
            }
        configuration.showsActivityIndicator = isUpgrading
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        upgradeButton.configuration = configuration
        upgradeButton.isEnabled = !isUpgrading
    }

    /// upgradeGift, free for a prepaid upgrade and for the price in effect otherwise.
    private func upgrade() {
        guard !isUpgrading else { return }
        isUpgrading = true
        updateButton()
        let client = client
        let giftID = gift.receivedGiftId
        let keep = keepOriginalDetails
        let starCount = isPrepaid ? 0 : price
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.upgradeGift(
                    businessConnectionId: "",
                    receivedGiftId: giftID,
                    keepOriginalDetails: keep,
                    starCount: starCount,
                ))
            } catch {
                guard let self else { return }
                isUpgrading = false
                updateButton()
                GiftActions.showError(error, in: self)
                return
            }
            guard let self else { return }
            onUpgraded?()
            // Both sheets close; the toast stands on the profile.
            let root = presentingViewController?.presentingViewController ?? presentingViewController
            root?.dismiss(animated: true) { [weak root] in
                guard let root else { return }
                TelegramUndoToast.show(
                    title: L10n.telegram("Gift.Upgrade.Succeed.Title"),
                    text: L10n.telegram("Gift.Upgrade.Succeed.Text"),
                    in: root.view, bottomInset: 12, undo: nil,
                )
            }
        }
    }
}

// MARK: - GiftUpgradePerkView

/// InfoParagraphComponent: the accent icon on the left, the 15 pt semibold title and the 15 pt secondary text beside
/// it.
private final class GiftUpgradePerkView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()

    init(symbol: String, title: String, text: String) {
        super.init(frame: .zero)
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular),
        )
        iconView.tintColor = .tintColor
        iconView.contentMode = .center
        addSubview(iconView)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 0
        addSubview(titleLabel)
        textLabel.text = text
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 0
        addSubview(textLabel)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textWidth = size.width - 46
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let textHeight = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        return CGSize(width: size.width, height: titleHeight + 2 + textHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let textWidth = bounds.width - 46
        iconView.frame = CGRect(x: 0, y: 2, width: 30, height: 30)
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        titleLabel.frame = CGRect(x: 46, y: 0, width: textWidth, height: titleHeight)
        let textHeight = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        textLabel.frame = CGRect(x: 46, y: titleHeight + 2, width: textWidth, height: textHeight)
    }
}
