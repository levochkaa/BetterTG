// IncomingMessagePrivacyViewController.swift

import TDLibKit
import UIKit

// MARK: - IncomingMessagePrivacyViewController

/// Telegram's IncomingMessagePrivacyScreen: who can write first (getNewChatPrivacySettings) — Everybody, My Contacts
/// and Premium Users, or Charge for Messages with its price per message, what the account earns from it, and Remove
/// Fee's exceptions (userPrivacySettingAllowUnpaidMessages). The choice saves when the screen closes, as Telegram's
/// attemptNavigation does; a paid choice without Premium is left unsaved.
final class IncomingMessagePrivacyViewController: SettingsListViewController {
    enum Value: Equatable {
        case everybody
        case premium
        case paid(Int64)

        var settings: TDNativeNewChatPrivacySettings {
            switch self {
            case .everybody: TDNativeNewChatPrivacySettings(
                    allowNewChatsFromUnknownUsers: true,
                    incomingPaidMessageStarCount: 0,
                )
            case .premium: TDNativeNewChatPrivacySettings(
                    allowNewChatsFromUnknownUsers: false,
                    incomingPaidMessageStarCount: 0,
                )
            case .paid(let stars): TDNativeNewChatPrivacySettings(
                    allowNewChatsFromUnknownUsers: true,
                    incomingPaidMessageStarCount: stars,
                )
            }
        }

        /// The Privacy row's label.
        var summary: String {
            switch self {
            case .everybody: L10n.telegram("Settings.Privacy.Messages.ValueEveryone")
            case .premium: L10n.telegram("Settings.Privacy.Messages.ValueContactsAndPremium")
            case .paid: L10n.telegram("Settings.Privacy.Messages.ValuePaid")
            }
        }

        init(_ settings: TDNativeNewChatPrivacySettings) {
            self =
                if settings.incomingPaidMessageStarCount > 0 {
                    .paid(settings.incomingPaidMessageStarCount)
                } else {
                    settings.allowNewChatsFromUnknownUsers ? .everybody : .premium
                }
        }
    }

    /// What the screen needs besides the value: limits and rates from TDLib's options and the app config.
    struct Configuration {
        /// Without Premium the contacts-and-Premium choice is locked unless the server allows it
        /// (can_set_new_chat_privacy_settings).
        var canRequirePremium = false
        /// can_enable_paid_messages: Charge for Messages shows.
        var paidMessagesAvailable = false
        /// paid_message_star_count_max.
        var maxPrice: Int64 = 10000
        /// paid_message_earnings_per_mille.
        var earningsPerMille: Int64 = 850
        /// stars_usd_withdraw_rate_x1000: cents for 1000 Stars.
        var usdWithdrawRate: Double = 1200

        static func load(client: TDLibClient, isPremium: Bool) async -> Self {
            var configuration = Self()
            configuration.canRequirePremium = isPremium
            if case .optionValueBoolean(let value) = try? await client.getOption(
                name: "can_set_new_chat_privacy_settings",
            ) {
                configuration.canRequirePremium = isPremium || value.value
            }
            if case .optionValueBoolean(let value) = try? await client.getOption(name: "can_enable_paid_messages") {
                configuration.paidMessagesAvailable = value.value
            }
            if case .optionValueInteger(let value) = try? await client.getOption(name: "paid_message_star_count_max"),
               value.value > 0
            {
                configuration.maxPrice = value.value
            }
            if case .optionValueInteger(let value) = try? await client.getOption(
                name: "paid_message_earnings_per_mille",
            ) {
                configuration.earningsPerMille = value.value
            }
            if case .jsonValueObject(let object)? = try? await client.send(TDNativeRequests.getApplicationConfig()),
               let member = object.members.first(where: { $0.key == "stars_usd_withdraw_rate_x1000" }),
               case .jsonValueNumber(let rate) = member.value
            {
                configuration.usdWithdrawRate = rate.value
            }
            return configuration
        }
    }

    private static let defaultPrice: Int64 = 400

    private static let lockView = SettingsTrailingView {
        let view = UIImageView(image: UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
        ))
        view.tintColor = .secondaryLabel
        return view
    }

    var onChange: ((Value) -> Void)?

    private var value: Value
    private let savedValue: Value
    private let isPremium: Bool
    private let configuration: Configuration
    /// Remove Fee's people and groups.
    private var unpaid: PrivacyRuleState?

    private var exceptionCount: Int {
        (unpaid?.allowUserIDs.count ?? 0) + (unpaid?.allowChatIDs.count ?? 0)
    }

    init(value: Value, isPremium: Bool, configuration: Configuration) {
        self.value = value
        self.savedValue = value
        self.isPremium = isPremium
        self.configuration = configuration
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Privacy.Messages.Title")
        tableView.register(MessagePriceCell.self, forCellReuseIdentifier: MessagePriceCell.reuseIdentifier)
        loadExceptions()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isLeavingNavigation else { return }
        save()
    }

    override func makeSections() -> [SettingsSection] {
        let isPaid =
            if case .paid = value {
                true
            } else {
                false
            }
        var options = [
            SettingsRow(
                title: L10n.telegram("Privacy.Messages.ValueEveryone"),
                accessory: value == .everybody ? .checkmark : .none,
            ) { [weak self] in self?.choose(.everybody) },
            SettingsRow(
                title: L10n.telegram("Privacy.Messages.ValueContactsAndPremium"),
                accessory: configuration.canRequirePremium && value == .premium ? .checkmark : .none,
                action: { [weak self] in self?.choosePremium() },
                trailingView: configuration.canRequirePremium ? nil : Self.lockView,
            ),
        ]
        if configuration.paidMessagesAvailable {
            options.append(SettingsRow(
                title: L10n.telegram("Privacy.Messages.ChargeForMessages"),
                accessory: isPaid ? .checkmark : .none,
                action: { [weak self] in self?.choosePaid() },
                trailingView: isPremium || isPaid ? nil : Self.lockView,
            ))
        }
        var sections = [SettingsSection(
            header: L10n.telegram("Privacy.Messages.SectionTitle"),
            footer: L10n.telegram(isPaid ? "Privacy.Messages.ChargeForMessagesInfo" : "Privacy.Messages.SectionFooter"),
            rows: options,
        )]
        guard case .paid(let stars) = value else { return sections }
        // The price row is drawn by MessagePriceCell; the row only holds its place.
        sections.append(SettingsSection(
            header: L10n.telegram("Privacy.Messages.MessagePrice"),
            footer: priceInfo(stars),
            rows: [SettingsRow(title: "")],
        ))
        if isPremium {
            sections.append(SettingsSection(
                header: L10n.telegram("Privacy.Messages.RemoveFeeHeader"),
                footer: L10n.telegram("Privacy.Messages.RemoveFeeInfo"),
                rows: [SettingsRow(
                    title: L10n.telegram("Privacy.Messages.RemoveFee"),
                    detail: exceptionCount > 0 ? "\(exceptionCount)" : "",
                    accessory: .disclosure,
                ) { [weak self] in self?.openExceptions() }],
            ))
        }
        return sections
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 1, case .paid(let stars) = value else {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: MessagePriceCell.reuseIdentifier, for: indexPath)
        (cell as? MessagePriceCell)?.configure(
            stars: stars,
            maxStars: configuration.maxPrice,
            isEnabled: isPremium,
            price: { [weak self] in self?.usdText($0) ?? "" },
            onChange: { [weak self] stars in self?.priceChanged(stars) },
            onCommit: { [weak self] in self?.reload() },
        )
        return cell
    }

    /// UITableViewController leaves this delegate method out, so it can't go to super.
    override func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 1, case .paid = value { return false }
        return true
    }

    /// Privacy.Messages.MessagePriceInfo: the account's share of the fee and the fee in dollars.
    private func priceInfo(_ stars: Int64) -> String {
        L10n.telegram(
            "Privacy.Messages.MessagePriceInfo",
            "\(configuration.earningsPerMille / 10)",
            usdText(stars),
        )
        .withoutTelegramMarkup
    }

    /// formatTonUsdValue at the Stars withdrawal rate: "~$4.80" for 400 Stars.
    private func usdText(_ stars: Int64) -> String {
        let usd = Double(stars) * configuration.usdWithdrawRate / 1000 / 100
        return "~" + usd.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    private func choose(_ newValue: Value) {
        guard newValue != value else { return }
        value = newValue
        reload()
    }

    private func choosePremium() {
        guard configuration.canRequirePremium else {
            TelegramUndoToast.show(
                title: L10n.telegram("Privacy.Messages.PremiumToast.Title"),
                text: L10n.telegram("Privacy.Messages.PremiumToast.Text").withoutTelegramMarkup,
                in: view,
                bottomInset: 12,
                undo: nil,
            )
            return
        }
        choose(.premium)
    }

    private func choosePaid() {
        if case .paid = value { return }
        choose(.paid(Self.defaultPrice))
    }

    /// The price footer follows the slider; the list catches up when the finger lifts.
    private func priceChanged(_ stars: Int64) {
        value = .paid(stars)
        guard let footer = tableView.footerView(forSection: 1) else { return }
        footer.textLabel?.text = priceInfo(stars)
        footer.setNeedsLayout()
    }

    private func save() {
        guard value != savedValue else { return }
        if case .paid = value, !isPremium { return }
        let settings = value.settings
        let value = value
        onChange?(value)
        let client = client
        Task { _ = try? await client.send(TDNativeRequests.setNewChatPrivacySettings(settings: settings)) }
    }

    private func loadExceptions() {
        let client = client
        Task { [weak self] in
            let rules = try? await client.send(TDNativeRequests.getUserPrivacySettingRules(
                setting: .userPrivacySettingAllowUnpaidMessages,
            ))
            guard let self, contextIsCurrent, let rules else { return }
            unpaid = PrivacyRuleState(rules: rules)
            refreshRowsInPlace()
        }
    }

    /// Remove Fee: the people and groups who write for free, saved as SelectivePrivacySettings.enableContacts with
    /// them allowed.
    private func openExceptions() {
        guard let unpaid else { return }
        let controller = PrivacyExceptionsViewController(
            title: L10n.telegram("Privacy.Messages.Exceptions.Title"),
            userIDs: unpaid.allowUserIDs,
            chatIDs: unpaid.allowChatIDs,
        )
        controller.onChange = { [weak self] userIDs, chatIDs in
            guard let self, var updated = self.unpaid else { return }
            updated.base = .contacts
            updated.allowUserIDs = userIDs
            updated.allowChatIDs = chatIDs
            updated.restrictUserIDs = []
            updated.restrictChatIDs = []
            let rules = updated.tdRules
            perform { client in
                _ = try await client.send(TDNativeRequests.setUserPrivacySettingRules(
                    setting: .userPrivacySettingAllowUnpaidMessages,
                    rules: rules,
                ))
            } completion: { [weak self] in
                self?.unpaid = updated
                self?.refreshRowsInPlace()
            }
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}

// MARK: - MessagePriceCell

/// MessagePriceItem: 1 and the maximum at the sides in 13 pt, the price in Stars in 17 pt with its dollar estimate in
/// 13 pt between them, and a slider over Telegram's logarithmic steps (1, 10, 50, 100, 500, 1000, 2000, 5000, 7500,
/// 10000, up to the maximum). Without Premium the slider is off.
private final class MessagePriceCell: UITableViewCell {
    static let reuseIdentifier = "MessagePriceCell"

    private static let sliderMax: Float = 999

    private let minLabel = UILabel()
    private let maxLabel = UILabel()
    private let valueLabel = UILabel()
    private let priceLabel = UILabel()
    private let slider = UISlider()
    private var steps = [Int64]()
    private var price: ((Int64) -> String)?
    private var onChange: ((Int64) -> Void)?
    private var onCommit: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        for label in [minLabel, maxLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
        }
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        priceLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        priceLabel.textColor = .secondaryLabel
        slider.minimumValue = 0
        slider.maximumValue = Self.sliderMax
        slider.minimumTrackTintColor = .tintColor
        slider.addAction(UIAction { [weak self] _ in self?.sliderMoved() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.onCommit?() }, for: [.touchUpInside, .touchUpOutside])
        let center = UIStackView(arrangedSubviews: [valueLabel, priceLabel])
        center.spacing = 6
        center.alignment = .lastBaseline
        for view in [minLabel, maxLabel, center, slider] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        let height = contentView.heightAnchor.constraint(equalToConstant: 88)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            height,
            minLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            minLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            maxLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            maxLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            center.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            center.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            slider.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 36),
            slider.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        stars: Int64,
        maxStars: Int64,
        isEnabled: Bool,
        price: @escaping (Int64) -> String,
        onChange: @escaping (Int64) -> Void,
        onCommit: @escaping () -> Void,
    ) {
        self.price = price
        self.onChange = onChange
        self.onCommit = onCommit
        steps = [1, 10, 50, 100, 500, 1000, 2000, 5000, 7500, 10000].filter { $0 < maxStars } + [maxStars]
        minLabel.text = "1"
        maxLabel.text = "\(maxStars)"
        slider.isEnabled = isEnabled
        slider.value = sliderValue(for: stars)
        show(stars: stars)
    }

    private func show(stars: Int64) {
        valueLabel.text = L10n.telegramPlural(
            "Privacy.Messages.Stars",
            count: Int(stars),
            formattedCount: "\(stars)",
        )
        priceLabel.text = price?(stars)
    }

    /// remapValueToSlider: each step takes an equal share of the track.
    private func sliderValue(for stars: Int64) -> Float {
        guard let first = steps.first, let last = steps.last, stars >= first, stars <= last, steps.count > 1 else {
            return 0
        }
        let share = Self.sliderMax / Float(steps.count - 1)
        for index in 0..<(steps.count - 1) where stars <= steps[index + 1] {
            let fraction = Float(stars - steps[index]) / Float(steps[index + 1] - steps[index])
            return Float(index) * share + fraction * share
        }
        return Self.sliderMax
    }

    /// remapSliderToValue.
    private func stars(for sliderValue: Float) -> Int64 {
        guard steps.count > 1 else { return steps.first ?? 1 }
        let position = sliderValue / Self.sliderMax * Float(steps.count - 1)
        let index = Int(position)
        guard index < steps.count - 1 else { return steps.last ?? 1 }
        let fraction = position - Float(index)
        return steps[index] + Int64(fraction * Float(steps[index + 1] - steps[index]))
    }

    private func sliderMoved() {
        let value = stars(for: slider.value)
        onChange?(value)
        show(stars: value)
    }
}
