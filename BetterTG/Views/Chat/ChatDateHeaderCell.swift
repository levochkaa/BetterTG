// ChatDateHeaderCell.swift

import UIKit

final class ChatDateHeaderCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatDateHeaderCell"

    /// ChatMessageDateHeaderNode's tap: a header resting at its day opens the calendar.
    var onTap: (() -> Void)?

    private let titleLabel = UILabel()
    private let pillView = UIControl()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        pillView.backgroundColor = .secondarySystemBackground
        pillView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        pillView.layer.cornerCurve = .continuous
        pillView.layer.cornerRadius = 11
        pillView.clipsToBounds = true
        titleLabel.isAccessibilityElement = false
        pillView.isAccessibilityElement = true
        pillView.accessibilityTraits = [.header, .button]
        titleLabel.isUserInteractionEnabled = false
        pillView.addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
        contentView.addSubview(pillView)
        pillView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            pillView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            pillView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            pillView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pillView.heightAnchor.constraint(equalToConstant: 22),
            pillView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -32),
            titleLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The pill's text for a day: today, yesterday, or the date. It changes at midnight and with the language.
    static func title(for id: ChatDateHeaderID) -> String {
        title(for: Date(timeIntervalSince1970: TimeInterval(id.dayTimestamp)))
    }

    private static func title(for date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return L10n.telegram("Weekday.Today")
        }
        if calendar.isDateInYesterday(date) {
            return L10n.telegram("Weekday.Yesterday")
        }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(date, equalTo: Date(), toGranularity: .year)
                ? "MMMd"
                : "yMMMd",
        )
        return formatter.string(from: date)
    }

    /// Returns the title shown, so the owner can tell when the header needs refreshing.
    @discardableResult func configure(id: ChatDateHeaderID) -> String {
        contentView.isHidden = false
        accessibilityElementsHidden = false
        isUserInteractionEnabled = true
        let text = Self.title(for: id)
        titleLabel.text = text
        pillView.accessibilityLabel = text
        pillView.accessibilityIdentifier = "chat-date-\(id.dayTimestamp)"
        return text
    }

    func resetUnavailableContent() {
        titleLabel.text = nil
        pillView.accessibilityLabel = nil
        pillView.accessibilityIdentifier = nil
        onTap = nil
    }
}
