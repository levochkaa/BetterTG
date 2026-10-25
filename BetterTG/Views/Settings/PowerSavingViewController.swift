// PowerSavingViewController.swift

import UIKit

// MARK: - PowerSavingViewController

/// Telegram's Power Saving (EnergySavingSettingsScreen): Power Saving Mode's battery level on
/// EnergyUsageBatteryLevelItem's slider, with the header showing whether it is on now and the footer what the level
/// means, then the resource-intensive processes BetterTG has. While Power Saving Mode is on they read off and can't
/// change; a tap says why.
final class PowerSavingViewController: SettingsListViewController {
    private var energyObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PowerSavingScreen.Title")
        tableView.register(
            PowerSavingBatteryLevelCell.self,
            forCellReuseIdentifier: PowerSavingBatteryLevelCell.reuseIdentifier,
        )
        energyObserver = NotificationCenter.default.addObserver(
            forName: EnergyUsage.didChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAfterThresholdChange() }
        }
    }

    override func makeSections() -> [SettingsSection] {
        let energy = EnergyUsage.shared
        let threshold = energy.activationThreshold
        let header: String
        let footer: String
        let itemsEnabled: Bool
        if threshold <= 4 {
            header = L10n.telegram("PowerSavingScreen.ToggleHeaderEmpty")
            footer = L10n.telegram("PowerSaving.AllDescriptionNever")
            itemsEnabled = true
        } else if threshold >= 96 {
            header = L10n.telegram("PowerSavingScreen.ToggleHeaderEmpty")
            footer = L10n.telegram("PowerSaving.AllDescriptionAlways")
            itemsEnabled = false
        } else {
            header = L10n.telegram(energy.isPowerSavingOn
                ? "PowerSavingScreen.ToggleHeaderOn"
                : "PowerSavingScreen.ToggleHeaderOff")
            footer = powerSavingPercentText("PowerSaving.AllDescriptionLimit", threshold)
            itemsEnabled = !energy.isPowerSavingOn
        }
        // The slider's cell stands in for this row.
        let levelSection = SettingsSection(header: header, footer: footer, rows: [SettingsRow(title: "")])
        let items = EnergyUsage.Item.allCases.map { item in
            SettingsRow(
                title: item.title,
                detail: item.text,
                style: .subtitle,
                symbol: item.symbol,
                symbolTint: item.tint,
                accessory: .toggle(isOn: energy.isEnabled(item) && itemsEnabled) { isOn in
                    EnergyUsage.shared.setEnabled(item, isOn)
                },
                isEnabled: itemsEnabled,
            )
        }
        return [levelSection, SettingsSection(header: L10n.telegram("PowerSavingScreen.OptionsHeader"), rows: items)]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 0 else { return super.tableView(tableView, cellForRowAt: indexPath) }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: PowerSavingBatteryLevelCell.reuseIdentifier,
            for: indexPath,
        )
        if let cell = cell as? PowerSavingBatteryLevelCell {
            cell.configure(value: EnergyUsage.shared.activationThreshold) { value in
                EnergyUsage.shared.activationThreshold = value
            }
        }
        return cell
    }

    /// activatedWhileDisabled: why the processes can't change now.
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1, settingsRow(at: indexPath)?.isEnabled == false else {
            super.tableView(tableView, didSelectRowAt: indexPath)
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        showToast(L10n.telegram(EnergyUsage.shared.activationThreshold >= 96
                ? "PowerSavingScreen.OptionChangeAlertAlways"
                : "PowerSavingScreen.OptionChangeAlertConditional"))
    }

    /// The slider keeps its cell while it moves: the level's header and footer change in place and the processes
    /// redraw.
    private func refreshAfterThresholdChange() {
        let previous = sections.first
        reload(sections: [1])
        guard let current = sections.first else { return }
        if previous?.header != current.header, let header = tableView.headerView(forSection: 0) {
            var content = header.defaultContentConfiguration()
            content.text = current.header
            header.contentConfiguration = content
        }
        if previous?.footer != current.footer, let footer = tableView.footerView(forSection: 0) {
            var content = footer.defaultContentConfiguration()
            content.text = current.footer
            footer.contentConfiguration = content
            UIView.performWithoutAnimation {
                tableView.performBatchUpdates(nil)
            }
        }
    }
}

/// A Telegram string with "%@%": the percent sign follows the value, which `String(format:)` would read as a
/// specifier.
private func powerSavingPercentText(_ key: String, _ value: Int) -> String {
    L10n.telegram(key).replacing("%@", with: String(value))
}

// MARK: - PowerSavingBatteryLevelCell

/// EnergyUsageBatteryLevelItem: Off and On in 13 pt at the ends, the level in 16 pt in the middle ("When Below 15%"
/// with a battery filled to it, red at 20% and below; "Always Off" or "Always On" at the ends), and a native slider
/// below spanning 4% to 96%.
private final class PowerSavingBatteryLevelCell: UITableViewCell {
    static let reuseIdentifier = "PowerSavingBatteryLevelCell"

    private let leftLabel = UILabel()
    private let rightLabel = UILabel()
    private let centerLabel = UILabel()
    private let batteryView = PowerSavingBatteryView()
    private let slider = UISlider()
    private var value = 15
    private var onChange: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        for label in [leftLabel, rightLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
        }
        leftLabel.text = L10n.telegram("PowerSaving.BatteryLevelLimit.Off")
        rightLabel.text = L10n.telegram("PowerSaving.BatteryLevelLimit.On")
        centerLabel.font = .systemFont(ofSize: 16)
        centerLabel.textColor = .label
        slider.minimumTrackTintColor = .tintColor
        slider.addAction(UIAction { [weak self] _ in self?.sliderMoved() }, for: .valueChanged)
        for subview in [leftLabel, rightLabel, centerLabel, batteryView, slider] {
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([contentView.heightAnchor.constraint(equalToConstant: 96)])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let verticalInset: CGFloat = 4
        let sideInset: CGFloat = 18
        leftLabel.sizeToFit()
        rightLabel.sizeToFit()
        leftLabel.frame.origin = CGPoint(x: sideInset, y: 15 + verticalInset)
        rightLabel.frame.origin = CGPoint(x: width - sideInset - rightLabel.bounds.width, y: 15 + verticalInset)

        let measureText = batteryView.isHidden
            ? centerLabel.text ?? ""
            : powerSavingPercentText("PowerSaving.BatteryLevelLimit.WhenBelow", 99)
        let measureWidth = ceil((measureText as NSString).size(withAttributes: [.font: centerLabel.font as Any]).width)
        centerLabel.sizeToFit()
        var centerX = floor((width - measureWidth) / 2)
        if !batteryView.isHidden { centerX -= 12 }
        centerLabel.frame.origin = CGPoint(x: centerX, y: 11 + verticalInset)
        batteryView.frame = CGRect(
            x: centerX + measureWidth + 4,
            y: floor(centerLabel.frame.midY - 6.5),
            width: 29,
            height: 13,
        )
        slider.frame = CGRect(x: 15, y: 36 + verticalInset, width: width - 30, height: 44)
    }

    func configure(value: Int, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        self.value = value
        slider.value = Float(max(0, min(1, (CGFloat(value) / 100 - 0.04) / 0.92)))
        updateLevel()
    }

    private func sliderMoved() {
        let value = Int(0.04 * 100 + 0.92 * CGFloat(slider.value) * 100)
        guard value != self.value else { return }
        self.value = value
        updateLevel()
        onChange?(value)
    }

    private func updateLevel() {
        if value <= 4 {
            centerLabel.text = L10n.telegram("PowerSaving.BatteryLevelLimit.AlwaysOff")
            batteryView.isHidden = true
        } else if value >= 96 {
            centerLabel.text = L10n.telegram("PowerSaving.BatteryLevelLimit.AlwaysOn")
            batteryView.isHidden = true
        } else {
            centerLabel.text = powerSavingPercentText("PowerSaving.BatteryLevelLimit.WhenBelow", value)
            batteryView.isHidden = false
        }
        batteryView.level = CGFloat(value) / 100
        setNeedsLayout()
    }
}

// MARK: - PowerSavingBatteryView

/// Settings/UsageBatteryFrame: a 24×12 rounded frame with its cap, filled to the level in green, or red at 20% and
/// below.
private final class PowerSavingBatteryView: UIView {
    var level: CGFloat = 0.15 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_: CGRect) {
        let frameColor = UIColor.label.withAlphaComponent(0.9)
        frameColor.withAlphaComponent(0.35 * 0.9).setStroke()
        let frame = UIBezierPath(roundedRect: CGRect(x: 1.336, y: 0.5, width: 24, height: 12), cornerRadius: 4)
        frame.lineWidth = 1
        frame.stroke()
        frameColor.withAlphaComponent(0.4 * 0.9).setFill()
        let cap = UIBezierPath()
        cap.move(to: CGPoint(x: 26.836, y: 4.667))
        cap.addLine(to: CGPoint(x: 26.836, y: 8.667))
        cap.addCurve(
            to: CGPoint(x: 26.836, y: 4.667),
            controlPoint1: CGPoint(x: 28.7, y: 8.0),
            controlPoint2: CGPoint(x: 28.7, y: 5.3),
        )
        cap.fill()
        let content = CGRect(x: 3, y: 2, width: 20.8, height: 9)
        UIBezierPath(roundedRect: content, cornerRadius: 2).addClip()
        (level <= 0.2 ? UIColor.systemRed : UIColor.systemGreen).setFill()
        UIBezierPath(
            roundedRect: CGRect(x: content.minX, y: content.minY, width: content.width * level, height: content.height),
            cornerRadius: 1,
        )
        .fill()
    }
}
