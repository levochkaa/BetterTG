// ChatDateHeaderCell.swift

import UIKit

final class ChatDateHeaderCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatDateHeaderCell"

    private let titleLabel = UILabel()
    private let pillView = UIView()

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
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = .header
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

    private static func title(for date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
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

    func configure(id: ChatDateHeaderID) {
        contentView.isHidden = false
        accessibilityElementsHidden = false
        isUserInteractionEnabled = true
        let date = Date(timeIntervalSince1970: TimeInterval(id.dayTimestamp))
        let text = Self.title(for: date)
        titleLabel.text = text
        titleLabel.accessibilityLabel = text
        titleLabel.accessibilityIdentifier = "chat-date-\(id.dayTimestamp)"
    }

    func resetUnavailableContent() {
        titleLabel.text = nil
        titleLabel.accessibilityLabel = nil
        titleLabel.accessibilityIdentifier = nil
    }
}
