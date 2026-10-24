// LocationDistancePickerViewController.swift

import UIKit

// MARK: - LocationDistancePickerViewController

/// Telegram's LocationDistancePickerScreen: the proximity alert's distance on a wheel of whole kilometers and meters,
/// or miles and their fractions where the region doesn't use the metric system. The map behind the sheet stays
/// undimmed for the viewer's radius indicator, which follows the wheel; a distance beyond the farthest pin isn't
/// offered, since the user is already that close.
final class LocationDistancePickerViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    // MARK: Private

    /// The wheel's choice: the radius in meters, as a distance, and as the button shows it.
    private struct SelectedDistance {
        let convertedValue: Int
        let convertedDistance: Double
        let text: String
    }

    // MARK: Internal

    /// The sheet's height above the bottom safe area: the title, the wheel and the button.
    static let contentHeight: CGFloat = topInset + titleHeight + pickerHeight + buttonSpacing + buttonHeight + 16

    /// 0-98 whole kilometers or miles.
    private static let unitValues = Array(0..<99)
    /// Tens of meters, or thousandths of a mile: 0, 50, then 100-900.
    private static let smallUnitValues = [0, 5] + (1..<10).map { $0 * 10 }
    private static let detentIdentifier = UISheetPresentationController.Detent.Identifier(
        "LocationDistancePicker",
    )
    private static let sideInset: CGFloat = 16
    private static let topInset: CGFloat = 16
    private static let closeAreaSize: CGFloat = 44
    private static let titleHeight: CGFloat = 54
    private static let pickerHeight: CGFloat = 216
    private static let buttonSpacing: CGFloat = 17
    private static let buttonHeight: CGFloat = 52
    private static let buttonSideInset: CGFloat = 30
    private static let pollInterval: TimeInterval = 0.4
    /// Telegram's miles to meters.
    private static let metersPerMile = 1.60934

    private let compactDisplayTitle: String?
    private let distances: () -> [Double]
    private let updated: (Int) -> Void
    private let completion: (Int, LocationDistancePickerViewController) -> Void
    private let willDismiss: () -> Void
    private let usesMetricSystem: Bool
    private let closeButton = UIButton(type: .close)
    private let titleLabel = UILabel()
    private let pickerView = UIPickerView()
    private let unitLabel = UILabel()
    private let smallUnitLabel = UILabel()
    private let button = UIButton(type: .system)
    private let warningLabel = UILabel()
    private var pollTimer: Timer?
    private var currentDistances = [Double]()
    private var previousReportedValue: Int?
    private var isCompleting = false
    private var didCallWillDismiss = false
    private var isTooFar: Bool?
    private var buttonTitle: String?
    private var lastLayoutWidth: CGFloat?

    /// - Parameters:
    ///   - compactDisplayTitle: The other user's name in a private chat, for Notify when ... is within.
    ///   - distances: How far the user is from every other pin, nearest first; asked for while the sheet is open.
    ///   - updated: The radius in meters as the wheel moves.
    ///   - completion: The chosen radius in meters; the owner dismisses the sheet.
    ///   - willDismiss: The sheet is about to close.
    init(
        compactDisplayTitle: String?,
        distances: @escaping () -> [Double],
        updated: @escaping (Int) -> Void,
        completion: @escaping (Int, LocationDistancePickerViewController) -> Void,
        willDismiss: @escaping () -> Void,
    ) {
        self.compactDisplayTitle = compactDisplayTitle
        self.distances = distances
        self.updated = updated
        self.completion = completion
        self.willDismiss = willDismiss
        // localeWithStrings(...).usesMetricSystem, with miles for the UK: its measurement system isn't the metric one.
        self.usesMetricSystem = Locale.current.measurementSystem == .metric
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            let height = Self.contentHeight
            sheet.detents = [.custom(identifier: Self.detentIdentifier) { _ in height }]
            // Telegram's sheet has no dim view: the viewer dims the map around the radius itself.
            sheet.largestUndimmedDetentIdentifier = Self.detentIdentifier
            sheet.prefersGrabberVisible = false
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pollTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(closeButton)

        titleLabel.text = L10n.telegram("Location.ProximityNotification.Title")
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header
        view.addSubview(titleLabel)

        pickerView.dataSource = self
        pickerView.delegate = self
        view.addSubview(pickerView)
        pickerView.selectRow(0, inComponent: 0, animated: false)
        pickerView.selectRow(usesMetricSystem ? 6 : 4, inComponent: 1, animated: false)

        for label in [unitLabel, smallUnitLabel] {
            label.font = .systemFont(ofSize: 15)
            label.textColor = .label
            label.isAccessibilityElement = false
            view.addSubview(label)
        }
        unitLabel.text = L10n.telegram(
            usesMetricSystem
                ? "Location.ProximityNotification.DistanceKM"
                : "Location.ProximityNotification.DistanceMI",
        )
        smallUnitLabel.text = usesMetricSystem ? L10n.telegram("Location.ProximityNotification.DistanceM") : ""

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.titleLineBreakMode = .byTruncatingTail
        button.configuration = configuration
        button.addAction(UIAction { [weak self] _ in self?.notifyPressed() }, for: .touchUpInside)
        view.addSubview(button)

        warningLabel.font = .systemFont(ofSize: 14)
        warningLabel.textColor = .secondaryLabel
        warningLabel.textAlignment = .center
        warningLabel.numberOfLines = 0
        warningLabel.alpha = 0
        view.addSubview(warningLabel)

        currentDistances = distances()
        // Telegram reads the wheel every 0.4 seconds, so the radius follows it while it spins.
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.pollTimerFired()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        reportSelectedValue()
        updateContent(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let closeSize = closeButton.intrinsicContentSize
        closeButton.frame = CGRect(
            x: Self.sideInset + (Self.closeAreaSize - closeSize.width) / 2,
            y: Self.topInset + (Self.closeAreaSize - closeSize.height) / 2,
            width: closeSize.width,
            height: closeSize.height,
        )
        let titleSize = titleLabel.sizeThatFits(CGSize(width: max(0, width - 120), height: Self.titleHeight))
        titleLabel.frame = CGRect(
            x: floor((width - min(titleSize.width, width - 120)) / 2),
            y: Self.topInset + floor((Self.closeAreaSize - titleSize.height) / 2),
            width: min(titleSize.width, max(0, width - 120)),
            height: titleSize.height,
        )
        let pickerFrame = CGRect(x: 0, y: Self.topInset + Self.titleHeight, width: width, height: Self.pickerHeight)
        pickerView.frame = pickerFrame
        let unitSize = unitLabel.sizeThatFits(CGSize(width: width, height: Self.titleHeight))
        unitLabel.frame = CGRect(
            x: floor(pickerFrame.width / 4) + 50,
            y: floor(pickerFrame.midY - unitSize.height / 2),
            width: unitSize.width,
            height: unitSize.height,
        )
        let smallUnitSize = smallUnitLabel.sizeThatFits(CGSize(width: width, height: Self.titleHeight))
        smallUnitLabel.frame = CGRect(
            x: floor(pickerFrame.width / 4 * 3) + 50,
            y: floor(pickerFrame.midY - smallUnitSize.height / 2),
            width: smallUnitSize.width,
            height: smallUnitSize.height,
        )
        let bottomY = pickerFrame.maxY + Self.buttonSpacing
        button.frame = CGRect(
            x: Self.buttonSideInset,
            y: bottomY,
            width: max(0, width - Self.buttonSideInset * 2),
            height: Self.buttonHeight,
        )
        let warningSize = warningLabel.sizeThatFits(CGSize(
            width: max(0, width - Self.sideInset * 2),
            height: Self.buttonHeight,
        ))
        warningLabel.frame = CGRect(
            x: floor((width - warningSize.width) / 2),
            y: bottomY + floor((Self.buttonHeight - warningSize.height) / 2),
            width: warningSize.width,
            height: warningSize.height,
        )
        if lastLayoutWidth != width {
            lastLayoutWidth = width
            updateContent(animated: false)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard didCallWillDismiss else { return }
        // A swipe to dismiss was given up: the viewer shows the radius again.
        didCallWillDismiss = false
        previousReportedValue = nil
        reportSelectedValue()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isBeingDismissed || presentingViewController?.isBeingDismissed == true else { return }
        performWillDismissOnce()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController?.isBeingDismissed == true else { return }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Picker

    func numberOfComponents(in _: UIPickerView) -> Int {
        2
    }

    func pickerView(_: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? Self.unitValues.count : Self.smallUnitValues.count
    }

    func pickerView(
        _: UIPickerView,
        attributedTitleForRow row: Int,
        forComponent component: Int,
    ) -> NSAttributedString? {
        let string: String
        if component == 0 {
            string = "\(Self.unitValues[row])"
        } else if usesMetricSystem {
            string = "\(Self.smallUnitValues[row] * 10)"
        } else {
            let value = Self.smallUnitValues[row]
            string =
                switch value {
                case 0: ".0"
                case 5: ".05"
                default: ".\(value / 10)"
                }
        }
        return NSAttributedString(
            string: string,
            attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label],
        )
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow _: Int, inComponent _: Int) {
        // Zero isn't a distance: the wheel moves on to the smallest one.
        if pickerView.selectedRow(inComponent: 0) == 0, pickerView.selectedRow(inComponent: 1) == 0 {
            pickerView.selectRow(1, inComponent: 1, animated: true)
        }
        reportSelectedValue()
        updateContent(animated: true)
    }

    /// The wheel's distance, at least 50 meters or 0.05 miles; a value is meters, or thousandths of a mile.
    private func selectedDistance() -> SelectedDistance {
        let largeRow = max(0, pickerView.selectedRow(inComponent: 0))
        var smallRow = max(0, pickerView.selectedRow(inComponent: 1))
        if largeRow == 0, smallRow == 0 {
            smallRow = 1
        }
        let largeValue = Self.unitValues[min(largeRow, Self.unitValues.count - 1)]
        let smallValue = Self.smallUnitValues[min(smallRow, Self.smallUnitValues.count - 1)]
        let value = largeValue * 1000 + smallValue * 10
        var formattedValue = String(format: "%0.1f", Double(value) / 1000)
        if smallValue == 5 {
            formattedValue = formattedValue
                .replacing(".1", with: ".05")
                .replacing(",1", with: ",05")
        }
        let unit = L10n.telegram(
            usesMetricSystem
                ? "Location.ProximityNotification.DistanceKM"
                : "Location.ProximityNotification.DistanceMI",
        )
        var convertedDistance = Double(value)
        if !usesMetricSystem {
            convertedDistance *= Self.metersPerMile
        }
        return SelectedDistance(
            convertedValue: Int(convertedDistance),
            convertedDistance: convertedDistance,
            text: "\(formattedValue) \(unit)",
        )
    }

    /// The viewer hears about a new radius only.
    @discardableResult private func reportSelectedValue() -> Bool {
        let value = selectedDistance().convertedValue
        guard value != previousReportedValue else { return false }
        previousReportedValue = value
        updated(value)
        return true
    }

    private func pollTimerFired() {
        currentDistances = distances()
        reportSelectedValue()
        updateContent(animated: true)
    }

    /// Notify me within ..., or Notify when ... is within ... when that fits; a radius beyond the farthest pin gives
    /// You are already closer than ... instead.
    private func updateContent(animated: Bool) {
        guard isViewLoaded else { return }
        let selected = selectedDistance()
        let tooFar = currentDistances.last.map { selected.convertedDistance > $0 } ?? false
        var title = L10n.telegram("Location.ProximityNotification.Notify", selected.text)
        let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        if let compactDisplayTitle {
            let longTitle = L10n.telegram(
                "Location.ProximityNotification.NotifyLong",
                compactDisplayTitle,
                selected.text,
            )
            let longWidth = (longTitle as NSString)
                .boundingRect(
                    with: CGSize(width: view.bounds.width * 2, height: 50),
                    options: .usesLineFragmentOrigin,
                    attributes: [.font: titleFont],
                    context: nil,
                )
                .width
            if longWidth < view.bounds.width - 70 {
                title = longTitle
            }
        }
        if title != buttonTitle {
            buttonTitle = title
            UIView.performWithoutAnimation {
                button.configuration?.attributedTitle = AttributedString(
                    title,
                    attributes: AttributeContainer([.font: titleFont]),
                )
                button.layoutIfNeeded()
            }
            button.accessibilityLabel = title
        }
        button.isEnabled = !tooFar && !isCompleting
        let warning = L10n.telegram("Location.ProximityNotification.AlreadyClose", selected.text)
        if warningLabel.text != warning {
            warningLabel.text = warning
            view.setNeedsLayout()
        }
        guard tooFar != isTooFar else { return }
        isTooFar = tooFar
        let changes = {
            self.button.alpha = tooFar ? 0 : 1
            self.warningLabel.alpha = tooFar ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                changes()
            }
        } else {
            changes()
        }
    }

    private func notifyPressed() {
        guard !isCompleting else { return }
        isCompleting = true
        updateContent(animated: false)
        completion(selectedDistance().convertedValue, self)
    }

    private func performWillDismissOnce() {
        guard !didCallWillDismiss else { return }
        didCallWillDismiss = true
        willDismiss()
    }
}
