// ProfileInfoCardView.swift

import TDLibKit
import UIKit

// MARK: - ProfileInfoCardView

/// PeerInfoProfileItems' peerInfo section on one block: PeerInfoScreenLabeledValueItems (a 14 pt label, with a
/// secondary note on the right as Notes' "only visible to you", over its text), PeerInfoScreenBusinessHoursItem and
/// PeerInfoScreenAddressItem, separated by inset lines.
final class ProfileInfoCardView: UIView {
    enum Row: Equatable {
        case value(label: String, rightLabel: String? = nil, text: String, tapOpensMenu: Bool = false)
        case hours(BusinessHours)
        case address(label: String, text: String, opens: Bool)
        /// PeerInfoScreenActionItem: an accent title that acts on a tap, as Add to Contacts.
        case action(title: String)
        /// PeerInfoScreenDisclosureEncryptionKeyItem: a title with the key's picture and a chevron on the right.
        case disclosure(title: String, image: UIImage?)
    }

    /// TDLib's businessOpeningHours in the business's time zone and the account's, minutes from Monday 00:00.
    struct BusinessHours: Equatable {
        let timeZoneID: String
        let intervals: [Range<Int>]
        let localIntervals: [Range<Int>]
    }

    var onOpenAddress: (() -> Void)?
    /// The row's menu, from a long press or, for a row that asks for it, a tap.
    var onMenu: ((Row, UIView) -> Void)?
    var onAction: ((Row) -> Void)?

    private(set) var rows = [Row]()

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(rows: [Row]) {
        guard rows != self.rows else { return }
        self.rows = rows
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.enumerated() {
            let view: UIView =
                switch row {
                case .value(let label, let rightLabel, let text, let tapOpensMenu):
                    ProfileInfoValueRowView(
                        label: label,
                        rightLabel: rightLabel,
                        text: text,
                        action: tapOpensMenu
                            ? {
                                [weak self] in self?.openMenu(for: index)
                            }
                            : nil,
                    )
                case .hours(let hours):
                    BusinessHoursRowView(hours: hours) { [weak self] in self?.relayout() }
                case .address(let label, let text, let opens):
                    ProfileInfoValueRowView(
                        label: label,
                        rightLabel: nil,
                        text: text,
                        action: opens
                            ? { [weak self] in
                                self?.onOpenAddress?()
                            }
                            : nil,
                    )
                case .disclosure(let title, let image):
                    ProfileInfoActionRowView(title: title, image: image) { [weak self] in
                        guard let self, rows.indices.contains(index) else { return }
                        onAction?(rows[index])
                    }
                case .action(let title):
                    ProfileInfoActionRowView(title: title) { [weak self] in
                        guard let self, rows.indices.contains(index) else { return }
                        onAction?(rows[index])
                    }
                }
            if index > 0 { addSeparator(to: view) }
            switch row {
            case .action,
                 .disclosure: break
            default:
                view.addGestureRecognizer(UILongPressGestureRecognizer(
                    target: self,
                    action: #selector(longPressed(_:)),
                ))
            }
            view.tag = index
            stack.addArrangedSubview(view)
        }
        isHidden = rows.isEmpty
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view else { return }
        (view as? UIControl)?.cancelTracking(with: nil)
        openMenu(for: view.tag)
    }

    private func openMenu(for index: Int) {
        guard rows.indices.contains(index), stack.arrangedSubviews.indices.contains(index) else { return }
        onMenu?(rows[index], stack.arrangedSubviews[index])
    }

    private func relayout() {
        var view: UIView? = self
        while let current = view {
            current.setNeedsLayout()
            view = current.superview
        }
        UIView.animate(withDuration: 0.25) { self.window?.layoutIfNeeded() }
    }

    private func addSeparator(to view: UIView) {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
        ])
    }
}

// MARK: - ProfileInfoValueRowView

/// PeerInfoScreenLabeledValueItem: the label over the text; a row with an action highlights under the finger.
private final class ProfileInfoValueRowView: UIControl {
    override var isHighlighted: Bool {
        didSet {
            guard action != nil else { return }
            backgroundColor = isHighlighted ? .systemFill : .clear
        }
    }

    private let action: (() -> Void)?

    init(label: String, rightLabel: String?, text: String, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)
        let labelView = UILabel()
        labelView.text = label
        labelView.font = .systemFont(ofSize: 14)
        labelView.textColor = .label
        let rightLabelView = UILabel()
        rightLabelView.text = rightLabel
        rightLabelView.font = .systemFont(ofSize: 14)
        rightLabelView.textColor = .secondaryLabel
        rightLabelView.textAlignment = .right
        let textView = UILabel()
        textView.text = text
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .label
        textView.numberOfLines = 0
        for view in [labelView, rightLabelView, textView] {
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            labelView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rightLabelView.firstBaselineAnchor.constraint(equalTo: labelView.firstBaselineAnchor),
            rightLabelView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 8),
            rightLabelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textView.topAnchor.constraint(equalTo: labelView.bottomAnchor, constant: 2),
            textView.leadingAnchor.constraint(equalTo: labelView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityValue = text
        if action != nil {
            accessibilityTraits = .button
            addTarget(self, action: #selector(tapped), for: .touchUpInside)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        action?()
    }
}

// MARK: - ProfileInfoActionRowView

private final class ProfileInfoActionRowView: UIControl {
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .systemFill : .clear }
    }

    private let action: () -> Void

    /// An accent title alone, or, with an image, a disclosure row: the title in the primary colour, then the image and
    /// a
    /// chevron on the right.
    init(title: String, image: UIImage? = nil, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 17)
        label.textColor = image == nil ? .tintColor : .label
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        if let image {
            let imageView = UIImageView(image: image)
            imageView.layer.magnificationFilter = .nearest
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = .tertiaryLabel
            chevron.preferredSymbolConfiguration = .init(pointSize: 13, weight: .semibold)
            for view in [imageView, chevron] {
                view.isUserInteractionEnabled = false
                view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(view)
            }
            NSLayoutConstraint.activate([
                chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
                chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: imageView.leadingAnchor, constant: -8),
            ])
            accessibilityTraits = .button
        } else {
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16).isActive = true
        }
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        action()
    }
}

// MARK: - BusinessHoursRowView

/// PeerInfoScreenBusinessHoursItem: business hours, then Open in green or Closed in red with today's hours or when it
/// opens, and a chevron; a tap lists the week, Monday first, and, when the hours read differently in the account's time
/// zone, a switch between the business's local time and the account's.
final class BusinessHoursRowView: UIControl {
    // MARK: Week

    private enum Day: Equatable {
        case open
        case closed
        case intervals([Range<Int>])
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .systemFill : .clear }
    }

    private let hours: ProfileInfoCardView.BusinessHours
    private let onResize: () -> Void
    private let statusLabel = UILabel()
    private let todayLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
    private let daysStack = UIStackView()
    private let timeZoneButton = UIButton(configuration: .filled())
    private var daysBottom: NSLayoutConstraint!
    private var collapsedBottom: NSLayoutConstraint!
    private var isExpanded = false
    private var showsLocalTime = false

    private var displayedIntervals: [Range<Int>] {
        showsLocalTime ? hours.localIntervals : hours.intervals
    }

    init(hours: ProfileInfoCardView.BusinessHours, onResize: @escaping () -> Void) {
        self.hours = hours
        self.onResize = onResize
        super.init(frame: .zero)
        clipsToBounds = true
        let label = UILabel()
        label.text = L10n.telegram("PeerInfo.BusinessHours.Label")
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        statusLabel.font = .systemFont(ofSize: 15)
        todayLabel.font = .systemFont(ofSize: 15)
        todayLabel.textColor = .secondaryLabel
        todayLabel.textAlignment = .right
        todayLabel.numberOfLines = 0
        chevron.tintColor = .tertiaryLabel
        chevron.preferredSymbolConfiguration = .init(pointSize: 13, weight: .semibold)
        daysStack.axis = .vertical
        daysStack.spacing = 6
        daysStack.alpha = 0
        timeZoneButton.configuration?.baseBackgroundColor = .tintColor.withAlphaComponent(0.1)
        timeZoneButton.configuration?.baseForegroundColor = .tintColor
        timeZoneButton.configuration?.cornerStyle = .capsule
        timeZoneButton.configuration?.contentInsets = .init(top: 2, leading: 6, bottom: 2, trailing: 6)
        timeZoneButton.addTarget(self, action: #selector(switchTimeZone), for: .touchUpInside)
        timeZoneButton.isHidden = true
        for view in [label, statusLabel, todayLabel, chevron, daysStack, timeZoneButton] {
            if view !== timeZoneButton { view.isUserInteractionEnabled = false }
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        self.daysBottom = daysStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        self.collapsedBottom = statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            timeZoneButton.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            timeZoneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2),
            statusLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            chevron.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            todayLabel.firstBaselineAnchor.constraint(equalTo: statusLabel.firstBaselineAnchor),
            todayLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusLabel.trailingAnchor, constant: 8),
            todayLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            daysStack.topAnchor.constraint(equalTo: todayLabel.bottomAnchor, constant: 8),
            daysStack.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            daysStack.trailingAnchor.constraint(equalTo: todayLabel.trailingAnchor),
            collapsedBottom,
        ])
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        addTarget(self, action: #selector(toggle), for: .touchUpInside)
        accessibilityTraits = .button
        isAccessibilityElement = false
        update()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// businessHoursTextToCopy: each day on its line, "Monday: 09:00 - 18:00", in the business's time.
    static func copyText(_ hours: ProfileInfoCardView.BusinessHours) -> String {
        let titles = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return weekDays(hours.intervals)
            .enumerated()
            .map { index, day in
                "\(L10n.telegram("Weekday.\(titles[index])")): \(text(for: day, separator: ", "))"
            }
            .joined(separator: "\n")
    }

    private static func minuteSet(_ intervals: [Range<Int>]) -> IndexSet {
        var result = IndexSet()
        for interval in intervals where interval.lowerBound < interval.upperBound {
            result.insert(integersIn: interval)
        }
        return result
    }

    /// TelegramBusinessHours.splitIntoWeekDays: a range that starts within a day belongs to it, up to noon the next
    /// day; a whole day reads open 24 hours, an empty one closed.
    private static func weekDays(_ intervals: [Range<Int>]) -> [Day] {
        var weekMinutes = minuteSet(intervals)
        var mapped = Array(repeating: [Range<Int>](), count: 7)
        for index in 0..<7 {
            let day = index * 24 * 60..<(index + 1) * 24 * 60
            var removed = IndexSet()
            for range in weekMinutes.rangeView {
                if range.lowerBound >= day.upperBound { break }
                let clipped = range.lowerBound == day.lowerBound
                    ? range.lowerBound..<min(range.upperBound, day.upperBound)
                    : range.lowerBound..<min(range.upperBound, day.upperBound + 12 * 60)
                mapped[index].append(clipped.lowerBound - day.lowerBound..<clipped.upperBound - day.lowerBound)
                removed.insert(integersIn: clipped)
            }
            weekMinutes.subtract(removed)
        }
        return mapped.map { day in
            let minutes = minuteSet(day)
            if minutes.isEmpty { return .closed }
            if minutes == IndexSet(integersIn: 0..<24 * 60) || minutes == IndexSet(integersIn: 0..<24 * 60 - 1) {
                return .open
            }
            return .intervals(day)
        }
    }

    /// dayBusinessHoursText: open 24 hours, closed, or each range on its line.
    private static func text(for day: Day, separator: String = "\n") -> String {
        switch day {
        case .open:
            L10n.telegram("PeerInfo.BusinessHours.DayOpen24h")
        case .closed:
            L10n.telegram("PeerInfo.BusinessHours.DayClosed")
        case .intervals(let ranges):
            ranges.map { "\(timeText(minute: $0.lowerBound)) - \(timeText(minute: $0.upperBound))" }
                .joined(separator: separator)
        }
    }

    private static func timeText(minute: Int) -> String {
        let clipped = ((minute % (24 * 60)) + 24 * 60) % (24 * 60)
        var components = DateComponents()
        components.hour = clipped / 60
        components.minute = clipped % 60
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Monday is 0, as TDLib's week starts.
    private static func weekdayIndex(of date: Date, in calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    private static func weekMinute(of date: Date, in calendar: Calendar) -> Int {
        weekdayIndex(of: date, in: calendar) * 24 * 60
            + calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private func update() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = showsLocalTime
            ? Foundation.TimeZone.current
            : Foundation.TimeZone(identifier: hours.timeZoneID) ?? .current
        let businessCalendar: Calendar = {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = Foundation.TimeZone(identifier: hours.timeZoneID) ?? .current
            return value
        }()
        let now = Date()
        let weekMinute = Self.weekMinute(of: now, in: businessCalendar)
        let weekMinutes = Self.minuteSet(hours.intervals)
        let isOpen = weekMinutes.contains(weekMinute) || weekMinutes.contains(weekMinute + 7 * 24 * 60)
        statusLabel.text = L10n.telegram(isOpen
            ? "PeerInfo.BusinessHours.StatusOpen"
            : "PeerInfo.BusinessHours.StatusClosed")
        statusLabel.textColor = isOpen ? .systemGreen : .systemRed

        let days = Self.weekDays(displayedIntervals)
        let today = Self.weekdayIndex(of: now, in: calendar)
        var todayText = Self.text(for: days[today])
        if !isOpen, let next = weekMinutes.rangeView.first(where: { $0.lowerBound > weekMinute }) {
            let minutes = next.lowerBound - weekMinute
            if minutes < 60 {
                todayText = L10n.telegramPlural("PeerInfo.BusinessHours.StatusOpensInMinutes", count: minutes)
            } else if minutes < 6 * 60 {
                todayText = L10n.telegramPlural("PeerInfo.BusinessHours.StatusOpensInHours", count: minutes / 60)
            } else {
                let opening = now.addingTimeInterval(TimeInterval(minutes * 60))
                let time = Self.timeText(minute: calendar.component(.hour, from: opening) * 60
                    + calendar.component(.minute, from: opening))
                let dayDifference = calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: opening),
                )
                .day ?? 0
                todayText =
                    switch dayDifference {
                    case 0: L10n.telegram("PeerInfo.BusinessHours.StatusOpensTodayAt", time)
                    case 1: L10n.telegram("PeerInfo.BusinessHours.StatusOpensTomorrowAt", time)
                    default: L10n.telegramPlural("PeerInfo.BusinessHours.StatusOpensInDays", count: dayDifference)
                    }
            }
        }
        todayLabel.text = todayText

        daysStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let titles = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        for (index, day) in days.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .firstBaseline
            let title = UILabel()
            title.text = L10n.telegram("Weekday.\(titles[index])")
            title.font = .systemFont(ofSize: 15)
            title.textColor = .label
            title.setContentCompressionResistancePriority(.required, for: .horizontal)
            let value = UILabel()
            value.text = Self.text(for: day)
            value.font = .systemFont(ofSize: 15)
            value.textColor = .secondaryLabel
            value.textAlignment = .right
            value.numberOfLines = 0
            row.addArrangedSubview(title)
            row.addArrangedSubview(value)
            daysStack.addArrangedSubview(row)
        }
        let dependsOnTimeZone = Self.weekDays(hours.intervals) != Self.weekDays(hours.localIntervals)
        timeZoneButton.configuration?.attributedTitle = AttributedString(
            L10n.telegram(showsLocalTime
                ? "PeerInfo.BusinessHours.TimezoneSwitchMy"
                : "PeerInfo.BusinessHours.TimezoneSwitchBusiness"),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 12)]),
        )
        timeZoneButton.isHidden = !(isExpanded && dependsOnTimeZone)
        chevron.transform = isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        daysStack.alpha = isExpanded ? 1 : 0
        collapsedBottom.isActive = !isExpanded
        daysBottom.isActive = isExpanded
        accessibilityLabel = [L10n.telegram("PeerInfo.BusinessHours.Label"), statusLabel.text, todayLabel.text]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    @objc private func toggle() {
        isExpanded.toggle()
        update()
        onResize()
    }

    /// PeerInfoScreenBusinessHoursItem's timezone switch, which opens the list if it was closed.
    @objc private func switchTimeZone() {
        showsLocalTime.toggle()
        isExpanded = true
        update()
        onResize()
    }
}

// MARK: - Birthdate

extension TDNativeBirthdate {
    /// stringForCompactBirthday with showAge: "5 January 1999 (25 years old)", the year and age when known.
    var compactText: String {
        compactText(showsAge: true)
    }

    func compactText(showsAge: Bool) -> String {
        let months = [
            "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
            "November", "December",
        ]
        var components = ["\(day)"]
        if (1...12).contains(month) {
            components.append(L10n.telegram("Month.Gen\(months[month - 1])"))
        }
        if year > 0 {
            components.append("\(year)")
            guard showsAge else { return components.joined(separator: " ") }
            let calendar = Calendar(identifier: .gregorian)
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               let age = calendar.dateComponents([.year], from: date, to: Date()).year, age > 0
            {
                components.append("(\(L10n.telegramPlural("UserInfo.Age", count: age)))")
            }
        }
        return components.joined(separator: " ")
    }

    /// hasBirthdayToday: the day and month are today's.
    var isToday: Bool {
        let today = Calendar(identifier: .gregorian).dateComponents([.day, .month], from: Date())
        return today.day == day && today.month == month
    }
}
