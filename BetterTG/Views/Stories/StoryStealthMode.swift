// StoryStealthMode.swift

import TDLibKit
import UIKit

// MARK: - StoryStealthMode

/// updateStoryStealthMode for each account's client: until when Stealth Mode hides the account's story views, and
/// until when it can't be turned on again.
@MainActor final class StoryStealthMode {
    static let shared = StoryStealthMode()

    private var states = [UUID: (clientID: Int32, activeUntil: Int, cooldownUntil: Int)]()

    /// stories_stealth_past_period and stories_stealth_future_period: TDLib's story_stealth_mode options, five and
    /// twenty-five minutes without them.
    static func periods(client: TDLibClient) async -> (past: Int, future: Int) {
        func option(_ name: String, fallback: Int) async -> Int {
            if case .optionValueInteger(let value)? = try? await client.send(TDNativeRequests.getOption(name: name)),
               value.value > 0
            {
                return Int(value.value)
            }
            return fallback
        }
        return await (
            option("story_stealth_mode_past_period", fallback: 5 * 60),
            option("story_stealth_mode_future_period", fallback: 25 * 60),
        )
    }

    /// ChatListController.requestStealthMode: with Stealth Mode on, the stories open with Telegram's tooltip on the
    /// time left; otherwise StoryStealthModeSheetScreen offers to turn it on and open them, or the time until it can.
    /// Without Premium the sheet offers Premium instead (presentStealthModeUpgrade).
    static func request(
        isPremium: Bool,
        from host: UIViewController,
        client: TDLibClient,
        source: TdUpdateSource?,
        openStories: @escaping (_ toast: (title: String, text: String)?) -> Void,
    ) {
        Task { @MainActor [weak host] in
            let periods = await periods(client: client)
            guard let host else { return }
            let now = Int(Date().timeIntervalSince1970)
            let state = shared.state(for: source)
            if isPremium, state.activeUntil > now {
                openStories((
                    L10n.telegram("Story.ToastStealthModeActiveTitle"),
                    L10n.telegram(
                        "Story.ToastStealthModeActiveText",
                        SettingsFormatting.timeInterval(seconds: state.activeUntil - now),
                    )
                    .withoutTelegramMarkup,
                ))
                return
            }
            let sheet = StoryStealthModeSheetController(
                isUpgrade: !isPremium,
                cooldownUntil: state.cooldownUntil,
                periods: periods,
            )
            sheet.action = { [weak sheet] in
                guard isPremium else {
                    sheet?.dismiss(animated: true)
                    return
                }
                Task { @MainActor in
                    guard await (try? client.send(TDNativeRequests.activateStoryStealthMode())) != nil else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    sheet?.dismiss(animated: true) {
                        openStories((
                            L10n.telegram("Story.ToastStealthModeActivatedTitle"),
                            L10n.telegram(
                                "Story.ToastStealthModeActivatedText",
                                SettingsFormatting.timeInterval(seconds: periods.past),
                                SettingsFormatting.timeInterval(seconds: periods.future),
                            )
                            .withoutTelegramMarkup,
                        ))
                    }
                }
            }
            sheet.modalPresentationStyle = .pageSheet
            if let presentation = sheet.sheetPresentationController {
                presentation.detents = [.custom { [weak sheet] _ in sheet?.contentHeight ?? 520 }]
                presentation.prefersGrabberVisible = false
            }
            host.present(sheet, animated: true)
        }
    }

    func receive(_ update: TDNativeUpdateStoryStealthMode, source: TdUpdateSource) {
        states[source.accountID] = (source.clientID, update.activeUntilDate, update.cooldownUntilDate)
    }

    func state(for source: TdUpdateSource?) -> (activeUntil: Int, cooldownUntil: Int) {
        guard let source, let entry = states[source.accountID], entry.clientID == source.clientID else { return (0, 0) }
        return (entry.activeUntil, entry.cooldownUntil)
    }
}

// MARK: - StoryStealthModeSheetController

/// StoryStealthModeSheetScreen with StoryStealthModeInfoContentComponent: a 90 pt circle in Telegram's blue-to-green
/// gradient with the stealth icon, Stealth Mode in 19 pt semibold, the explanation centred in 15 pt, Hide Recent Views
/// and Hide Next Views with their icons in the accent colour and the periods in bold, then a 52 pt button 30 pt from
/// the sides: Enable and Open the Story, Available in mm:ss while it cools down (a tap shows the cooldown toast over
/// the sheet), or Unlock Stealth Mode without Premium, which also gets the close button.
final class StoryStealthModeSheetController: UIViewController {
    var action: (() -> Void)?

    private(set) var contentHeight: CGFloat = 520

    private let isUpgrade: Bool
    private let cooldownUntil: Int
    private let periods: (past: Int, future: Int)
    private let button = UIButton(configuration: .prominentGlass())
    private var timer: Timer?
    private var toast: UIView?

    private var layoutContent: ((CGFloat) -> CGFloat)?

    private var remainingCooldown: Int {
        max(0, cooldownUntil - Int(Date().timeIntervalSince1970))
    }

    init(isUpgrade: Bool, cooldownUntil: Int, periods: (past: Int, future: Int)) {
        self.isUpgrade = isUpgrade
        self.cooldownUntil = cooldownUntil
        self.periods = periods
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let icon = UIImageView(image: Self.gradientCircle(diameter: 90))
        let glyph = UIImageView(image: UIImage(named: "MediaEditor/StealthModeIntroIconMain")?
            .withRenderingMode(.alwaysTemplate))
        glyph.tintColor = .white
        let title = UILabel()
        title.text = L10n.telegram("Story.StealthMode.Title")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        title.textAlignment = .center
        let text = UILabel()
        text.attributedText = Self.markdown(
            L10n.telegram(isUpgrade ? "Story.StealthMode.UpgradeText" : "Story.StealthMode.ControlText"),
            alignment: .center,
        )
        text.numberOfLines = 0
        for subview in [icon, glyph, title, text] {
            view.addSubview(subview)
        }
        let items = [
            (
                "MediaEditor/StealthModeIntroIconHidePrevious",
                "Story.StealthMode.RecentTitle",
                L10n.telegram("Story.StealthMode.RecentText", SettingsFormatting.timeInterval(seconds: periods.past)),
            ),
            (
                "MediaEditor/StealthModeIntroIconHideNext",
                "Story.StealthMode.NextTitle",
                L10n.telegram("Story.StealthMode.NextText", SettingsFormatting.timeInterval(seconds: periods.future)),
            ),
        ].map { iconName, titleKey, body -> (UIImageView, UILabel, UILabel) in
            let itemIcon = UIImageView(image: UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate))
            itemIcon.tintColor = view.tintColor
            let itemTitle = UILabel()
            itemTitle.text = L10n.telegram(titleKey)
            itemTitle.font = .systemFont(ofSize: 15, weight: .semibold)
            itemTitle.numberOfLines = 0
            let itemText = UILabel()
            itemText.attributedText = Self.markdown(body, alignment: .natural)
            itemText.numberOfLines = 0
            for subview in [itemIcon, itemTitle, itemText] {
                view.addSubview(subview)
            }
            return (itemIcon, itemTitle, itemText)
        }
        button.addAction(UIAction { [weak self] _ in self?.pressed() }, for: .touchUpInside)
        view.addSubview(button)
        if isUpgrade {
            var close = UIButton.Configuration.glass()
            close.image = UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(weight: .semibold),
            )
            close.baseForegroundColor = .label
            let closeButton = UIButton(configuration: close)
            closeButton.accessibilityLabel = L10n.telegram("Common.Close")
            closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
            closeButton.frame = CGRect(x: 16, y: 16, width: 44, height: 44)
            view.addSubview(closeButton)
        }
        layoutContent = { [weak self] width in
            guard let self else { return 0 }
            let side: CGFloat = 32
            let textWidth = width - side * 2
            var y: CGFloat = 32
            icon.frame = CGRect(x: ((width - 90) / 2).rounded(.down), y: y, width: 90, height: 90)
            if let size = glyph.image?.size {
                glyph.frame = CGRect(
                    x: icon.frame.minX + ((90 - size.width) / 2).rounded(.down),
                    y: icon.frame.minY + ((90 - size.height) / 2).rounded(.down),
                    width: size.width,
                    height: size.height,
                )
            }
            y += 90 + 15
            let titleHeight = ceil(title.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
                .height)
            title.frame = CGRect(x: side, y: y, width: textWidth, height: titleHeight)
            y += titleHeight + 15
            let textHeight = ceil(text.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
            text.frame = CGRect(x: side, y: y, width: textWidth, height: textHeight)
            y += textHeight + 24
            for (index, item) in items.enumerated() {
                if index > 0 { y += 24 }
                let itemWidth = textWidth - 40
                let size = item.0.image?.size ?? .zero
                item.0.frame = CGRect(x: side, y: y + 4, width: size.width, height: size.height)
                let titleHeight = ceil(item.1
                    .sizeThatFits(CGSize(width: itemWidth, height: .greatestFiniteMagnitude))
                    .height)
                item.1.frame = CGRect(x: side + 40, y: y, width: itemWidth, height: titleHeight)
                y += titleHeight + 2
                let bodyHeight = ceil(item.2
                    .sizeThatFits(CGSize(width: itemWidth, height: .greatestFiniteMagnitude))
                    .height)
                item.2.frame = CGRect(x: side + 40, y: y, width: itemWidth, height: bodyHeight)
                y += bodyHeight
            }
            y += 41
            button.frame = CGRect(x: 30, y: y, width: width - 60, height: 52)
            y += 52
            y += view.safeAreaInsets.bottom > 0 ? view.safeAreaInsets.bottom + 10 : 16
            return y
        }
        updateButton()
        if !isUpgrade, remainingCooldown > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateButton() }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let height = layoutContent?(view.bounds.width), abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        sheetPresentationController?.animateChanges {
            sheetPresentationController?.invalidateDetents()
        }
    }

    /// The text with Telegram's **bold** in semibold, 15 pt in the secondary colour.
    private static func markdown(_ text: String, alignment: NSTextAlignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = 1.5
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: index.isMultiple(of: 2) ? .regular : .semibold),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    /// generateGradientFilledCircleImage with 0x3DA1FD to 0x34C76F.
    private static func gradientCircle(diameter: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { context in
            let colors = [
                UIColor(red: 0x3D / 255, green: 0xA1 / 255, blue: 0xFD / 255, alpha: 1).cgColor,
                UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x6F / 255, alpha: 1).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1],
            )
            else { return }
            context.cgContext.addEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            context.cgContext.clip()
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: diameter),
                options: [],
            )
        }
    }

    private func updateButton() {
        let title: String
        if isUpgrade {
            title = L10n.telegram("Story.StealthMode.UpgradeAction")
        } else if remainingCooldown > 0 {
            let seconds = remainingCooldown
            title = L10n.telegram(
                "Story.StealthMode.CooldownAction",
                String(format: "%d:%02d", seconds / 60, seconds % 60),
            )
        } else {
            title = L10n.telegram("Story.StealthMode.EnableAndOpenAction")
            timer?.invalidate()
            timer = nil
        }
        var configuration = button.configuration ?? .prominentGlass()
        configuration.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]),
        )
        button.configuration = configuration
        button.alpha = !isUpgrade && remainingCooldown > 0 ? 0.5 : 1
    }

    private func pressed() {
        if !isUpgrade, remainingCooldown > 0 {
            showCooldownToast()
            return
        }
        action?()
    }

    /// displayCooldown: Telegram's toast over the sheet asking to wait until Stealth Mode is ready.
    private func showCooldownToast() {
        toast?.removeFromSuperview()
        TelegramUndoToast.show(
            text: L10n.telegram("Story.StealthMode.ToastCooldownText").withoutTelegramMarkup,
            in: view,
            bottomInset: view.bounds.height - button.frame.minY + 8,
            undo: nil,
        )
    }
}
