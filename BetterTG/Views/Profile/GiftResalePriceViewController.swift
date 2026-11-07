// GiftResalePriceViewController.swift

import TDLibKit
import UIKit

// MARK: - GiftResalePriceViewController

/// StarsWithdrawScreen's `.starGiftResell` mode: Sell Gift, a PRICE IN STARS field with the star and "You will receive
/// N Stars." under it (TDLib's gift_resale_star_earnings_per_mille, the share before a price is entered), then Only
/// Accept GRAM, which prices the gift in GRAM instead, and "Sell for N" at the bottom. A price above the maximum
/// stops at it; one below the minimum says so instead of selling.
final class GiftResalePriceViewController: UIViewController, UITextFieldDelegate {
    private struct Limits {
        var min: Int64
        var max: Int64
        var perMille: Int64
    }

    /// The price picked; the caller lists the gift and closes the screen.
    var onSell: ((TDNativeGiftResalePrice) -> Void)?

    private let client: TDLibClient
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let amountTitleLabel = UILabel()
    private let fieldBackground = UIView()
    private let currencyIcon = UIImageView()
    private let textField = UITextField()
    private let amountFooterLabel = UILabel()
    private let onlyGramSwitch = UISwitch()
    private let sellButton = UIButton(configuration: .prominentGlass())
    private var stars = Limits(min: 125, max: 100_000, perMille: 800)
    /// GRAM in cents, as TDLib counts them.
    private var grams = Limits(min: 700, max: 10_000_000, perMille: 900)
    private var isGram = false
    /// The entered price: Stars, or GRAM cents.
    private var amount: Int64 = 0

    private var limits: Limits {
        isGram ? grams : stars
    }

    init(client: TDLibClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = L10n.telegram("Stars.SellGift.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )

        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        amountTitleLabel.font = .systemFont(ofSize: 13)
        amountTitleLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(inset(amountTitleLabel))

        fieldBackground.backgroundColor = .secondarySystemGroupedBackground
        fieldBackground.layer.cornerRadius = 26
        fieldBackground.layer.cornerCurve = .continuous
        currencyIcon.contentMode = .scaleAspectFit
        currencyIcon.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.addSubview(currencyIcon)
        textField.placeholder = L10n.telegram("Stars.SellGift.AmountPlaceholder")
        textField.font = .systemFont(ofSize: 17)
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        textField.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.addSubview(textField)
        NSLayoutConstraint.activate([
            fieldBackground.heightAnchor.constraint(equalToConstant: 52),
            currencyIcon.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: 16),
            currencyIcon.centerYAnchor.constraint(equalTo: fieldBackground.centerYAnchor),
            currencyIcon.widthAnchor.constraint(equalToConstant: 22),
            currencyIcon.heightAnchor.constraint(equalToConstant: 22),
            textField.leadingAnchor.constraint(equalTo: currencyIcon.trailingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -16),
            textField.topAnchor.constraint(equalTo: fieldBackground.topAnchor),
            textField.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
        ])
        stack.addArrangedSubview(fieldBackground)

        amountFooterLabel.numberOfLines = 0
        stack.addArrangedSubview(inset(amountFooterLabel))
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)

        let toggleBackground = UIView()
        toggleBackground.backgroundColor = .secondarySystemGroupedBackground
        toggleBackground.layer.cornerRadius = 26
        toggleBackground.layer.cornerCurve = .continuous
        let toggleLabel = UILabel()
        toggleLabel.text = L10n.telegram("Stars.SellGift.OnlyTon")
        toggleLabel.font = .systemFont(ofSize: 17)
        toggleLabel.translatesAutoresizingMaskIntoConstraints = false
        toggleBackground.addSubview(toggleLabel)
        onlyGramSwitch.addAction(UIAction { [weak self] _ in self?.currencyChanged() }, for: .valueChanged)
        onlyGramSwitch.translatesAutoresizingMaskIntoConstraints = false
        toggleBackground.addSubview(onlyGramSwitch)
        NSLayoutConstraint.activate([
            toggleBackground.heightAnchor.constraint(equalToConstant: 52),
            toggleLabel.leadingAnchor.constraint(equalTo: toggleBackground.leadingAnchor, constant: 16),
            toggleLabel.centerYAnchor.constraint(equalTo: toggleBackground.centerYAnchor),
            onlyGramSwitch.trailingAnchor.constraint(equalTo: toggleBackground.trailingAnchor, constant: -16),
            onlyGramSwitch.centerYAnchor.constraint(equalTo: toggleBackground.centerYAnchor),
            toggleLabel.trailingAnchor.constraint(lessThanOrEqualTo: onlyGramSwitch.leadingAnchor, constant: -8),
        ])
        stack.addArrangedSubview(toggleBackground)
        let toggleFooter = UILabel()
        toggleFooter.text = L10n.telegram("Stars.SellGift.OnlyTonInfo")
        toggleFooter.font = .systemFont(ofSize: 13)
        toggleFooter.textColor = .secondaryLabel
        toggleFooter.numberOfLines = 0
        stack.addArrangedSubview(inset(toggleFooter))

        sellButton.addAction(UIAction { [weak self] _ in self?.sellPressed() }, for: .touchUpInside)
        sellButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sellButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sellButton.topAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            sellButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            sellButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            sellButton.heightAnchor.constraint(equalToConstant: 52),
            // The keyboard guide stands on the safe area while the keyboard is down.
            sellButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
        ])
        update()
        loadLimits()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    /// The footer's **bold** spans, in 13 pt secondary text.
    private static func markdown(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in text.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: index % 2 == 1 ? .semibold : .regular),
                .foregroundColor: UIColor.secondaryLabel,
            ]))
        }
        return result
    }

    // MARK: Input

    /// Digits only for Stars, and up to two decimals for GRAM; a price past the maximum stops at it.
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString: String,
    ) -> Bool {
        let current = textField.text ?? ""
        guard let swiftRange = Range(range, in: current) else { return false }
        var updated = current.replacingCharacters(in: swiftRange, with: replacementString)
        updated = updated.replacing(",", with: ".")
        if updated.isEmpty { return true }
        let pattern = isGram ? #"^\d+(\.\d{0,2})?$"# : #"^\d+$"#
        guard updated.range(of: pattern, options: .regularExpression) != nil else { return false }
        if let value = parse(updated), value > limits.max {
            textField.text = format(limits.max)
            textChanged()
            return false
        }
        if updated != current.replacingCharacters(in: swiftRange, with: replacementString) {
            textField.text = updated
            textChanged()
            return false
        }
        return true
    }

    @objc private func textChanged() {
        amount = parse(textField.text ?? "") ?? 0
        update()
    }

    private func currencyChanged() {
        isGram = onlyGramSwitch.isOn
        textField.text = ""
        amount = 0
        update()
    }

    private func parse(_ text: String) -> Int64? {
        guard !text.isEmpty else { return nil }
        if isGram {
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return NSDecimalNumber(decimal: value * 100).int64Value
        }
        return Int64(text)
    }

    /// Stars as a number; GRAM cents as GRAM with the decimals they need.
    private func format(_ value: Int64) -> String {
        guard isGram else { return "\(value)" }
        let whole = value / 100
        let cents = value % 100
        if cents == 0 { return "\(whole)" }
        return cents % 10 == 0 ? "\(whole).\(cents / 10)" : String(format: "%lld.%02lld", whole, cents)
    }

    /// Currency.Grams: "1 Gram", otherwise "N Grams".
    private func gramsText(_ cents: Int64) -> String {
        L10n.telegramPlural("Currency.Grams", count: cents == 100 ? 1 : 2, formattedCount: format(cents))
    }

    private func amountText(_ value: Int64) -> String {
        if isGram {
            return gramsText(value)
        }
        return L10n.telegramPlural(
            "Stars.SellGift.AmountInfo.Stars", count: Int(value), formattedCount: GiftActions.formatted(Int(value)),
        )
    }

    // MARK: State

    private func update() {
        amountTitleLabel.text = L10n.telegram(isGram ? "Stars.SellGift.TonAmountTitle" : "Stars.SellGift.AmountTitle")
        currencyIcon.image = isGram
            ? UIImage(systemName: "diamond.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            : UIImage(named: "Message/PremiumStar")?.withTintColor(
                UIColor(rgb: 0xFFB10D), renderingMode: .alwaysOriginal,
            )
        textField.keyboardType = isGram ? .decimalPad : .numberPad
        textField.reloadInputViews()
        let earnings = amount > 0
            ? amountText(amount * limits.perMille / 1000)
            : "\(limits.perMille / 10)%"
        let footer = L10n.telegram("Stars.SellGift.AmountInfo", earnings)
        amountFooterLabel.attributedText = Self.markdown(footer)

        var configuration = sellButton.configuration ?? .prominentGlass()
        configuration.title = amount > 0
            ? L10n.telegram("Stars.SellGift.SellFor") + " " + amountText(amount)
            : L10n.telegram("Stars.SellGift.Sell")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        sellButton.configuration = configuration
        sellButton.isEnabled = amount > 0
    }

    /// TDLib's gift_resale_* options, which the server keeps current.
    private func loadLimits() {
        let client = client
        Task { [weak self] in
            func value(_ name: String) async -> Int64? {
                if case .optionValueInteger(let value) = try? await client.getOption(name: name) {
                    return value.value
                }
                return nil
            }
            let stars = await Limits(
                min: value("gift_resale_star_count_min") ?? 125,
                max: value("gift_resale_star_count_max") ?? 100_000,
                perMille: value("gift_resale_star_earnings_per_mille") ?? 800,
            )
            let grams = await Limits(
                min: value("gift_resale_gram_cent_count_min") ?? 700,
                max: value("gift_resale_gram_cent_count_max") ?? 10_000_000,
                perMille: value("gift_resale_gram_earnings_per_mille") ?? 900,
            )
            guard let self else { return }
            self.stars = stars
            self.grams = grams
            update()
        }
    }

    /// presentMinAmountTooltip below the minimum; otherwise the price goes back to the caller.
    private func sellPressed() {
        guard amount > 0 else { return }
        guard amount >= limits.min else {
            TelegramUndoToast.show(
                text: L10n.telegram(
                    "Stars.SellGiftMinAmountToast.Text",
                    isGram
                        ? gramsText(limits.min)
                        : L10n.telegramPlural(
                            "Stars.Withdraw.Withdraw.ErrorMinimum.Stars",
                            count: Int(limits.min),
                            formattedCount: GiftActions.formatted(Int(limits.min)),
                        ),
                ),
                in: view, bottomInset: view.safeAreaLayoutGuide.layoutFrame.maxY - sellButton.frame.minY + 8, undo: nil,
            )
            return
        }
        let price: TDNativeGiftResalePrice = isGram
            ? .giftResalePriceGram(.init(gramCentCount: amount))
            : .giftResalePriceStar(.init(starCount: amount))
        onSell?(price)
    }

    // MARK: Helpers

    private func inset(_ label: UILabel) -> UIView {
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
