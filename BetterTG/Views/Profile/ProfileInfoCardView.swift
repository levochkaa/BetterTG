// ProfileInfoCardView.swift

import TDLibKit
import UIKit

// MARK: - ProfileInfoCardView

/// PeerInfoProfileItems' peerInfo section as PeerInfoScreenLabeledValueItems on one block: each row a 14 pt label
/// (with a secondary note on the right, as Notes' "only visible to you") over its text, separated by inset lines.
final class ProfileInfoCardView: UIView {
    struct Row: Equatable {
        let label: String
        var rightLabel: String?
        let text: String
    }

    private(set) var rows = [Row]()

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
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
            stack.addArrangedSubview(rowView(row, showsSeparator: index > 0))
        }
        isHidden = rows.isEmpty
    }

    private func rowView(_ row: Row, showsSeparator: Bool) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = row.label
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        let rightLabel = UILabel()
        rightLabel.text = row.rightLabel
        rightLabel.font = .systemFont(ofSize: 14)
        rightLabel.textColor = .secondaryLabel
        rightLabel.textAlignment = .right
        let text = UILabel()
        text.text = row.text
        text.font = .systemFont(ofSize: 17)
        text.textColor = .label
        text.numberOfLines = 0
        for view in [label, rightLabel, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            rightLabel.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            rightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            rightLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            text.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2),
            text.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            text.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        if showsSeparator {
            let separator = UIView()
            separator.backgroundColor = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: container.topAnchor),
                separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
            ])
        }
        container.isAccessibilityElement = true
        container.accessibilityLabel = row.label
        container.accessibilityValue = row.text
        return container
    }
}

// MARK: - Birthdate

extension TDNativeBirthdate {
    /// stringForCompactBirthday with showAge: "5 January 1999 (25 years old)", the year and age when known.
    var compactText: String {
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
