// FolderTagViews.swift

import UIKit

// MARK: - FolderTagPalette

/// PeerNameColors.getChatFolderTag: a folder's tag colour, one of the seven name colours.
@MainActor enum FolderTagPalette {
    static let colorIDs = Array(0...6)

    static func color(_ colorId: Int) -> UIColor {
        AvatarColorPalette.shared.nameColor(accentColorID: colorId)
    }
}

// MARK: - FolderTagLabel

/// ChatListItemTagListComponent's item: the folder's name in semibold 11 pt capitals in its colour over the colour at
/// 10%, 4 pt from the sides and 2 pt from the top and bottom, its corners rounded.
final class FolderTagLabel: UIView {
    private let label = UILabel()

    init(fontSize: CGFloat = 11) {
        super.init(frame: .zero)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous
        label.font = .systemFont(ofSize: fontSize, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, color: UIColor) {
        label.text = text
        label.textColor = color
        backgroundColor = color.withAlphaComponent(0.1)
    }
}

// MARK: - FolderTagHeaderView

/// ChatListFilterTagSectionHeaderItem: the section's title as the list's other headers show theirs, with the folder's
/// tag, or a plain note, on the right.
final class FolderTagHeaderView: UITableViewHeaderFooterView {
    enum Badge {
        case tag(String, UIColor)
        case text(String)
    }

    static let reuseIdentifier = "FolderTagHeaderView"

    private let noteLabel = UILabel()
    private let tagLabel = FolderTagLabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        noteLabel.font = .preferredFont(forTextStyle: .footnote)
        noteLabel.adjustsFontForContentSizeCategory = true
        noteLabel.textColor = .secondaryLabel
        // On the header itself: a content configuration manages the content view's own subviews.
        for view in [noteLabel, tagLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                view.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor),
            ])
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, badge: Badge?) {
        var configuration = defaultContentConfiguration()
        configuration.text = title
        contentConfiguration = configuration
        switch badge {
        case .tag(let text, let color):
            tagLabel.configure(text: text, color: color)
            tagLabel.isHidden = false
            noteLabel.isHidden = true
        case .text(let text):
            noteLabel.text = text
            noteLabel.isHidden = false
            tagLabel.isHidden = true
        case nil:
            noteLabel.isHidden = true
            tagLabel.isHidden = true
        }
        bringSubviewToFront(noteLabel)
        bringSubviewToFront(tagLabel)
    }
}

// MARK: - FolderTagColorCell

/// PeerNameColorItem in its folder tag mode: no colour, then the seven colours, as circles spread across the row; the
/// chosen one is ringed. Locked without Premium.
final class FolderTagColorCell: UITableViewCell {
    static let reuseIdentifier = "FolderTagColorCell"

    private let stack = UIStackView()
    private var buttons = [(colorId: Int, button: UIButton)]()
    private var onSelect: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        for colorId in [-1] + FolderTagPalette.colorIDs {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(colorId) }, for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 32),
                button.heightAnchor.constraint(equalToConstant: 32),
            ])
            stack.addArrangedSubview(button)
            buttons.append((colorId, button))
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A 28 pt circle in the colour, or a grey one struck through for none; the chosen one sits in a ring.
    private static func circle(colorId: Int, isSelected: Bool) -> UIImage {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            let color = colorId < 0 ? UIColor.systemGray3 : FolderTagPalette.color(colorId)
            let inset: CGFloat = isSelected ? 5 : 2
            color.setFill()
            UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).fill()
            if isSelected {
                color.setStroke()
                let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 2
                ring.stroke()
            }
            if colorId < 0 {
                UIColor.white.setStroke()
                let line = UIBezierPath()
                line.move(to: CGPoint(x: bounds.maxX - 10, y: 10))
                line.addLine(to: CGPoint(x: 10, y: bounds.maxY - 10))
                line.lineWidth = 2
                line.lineCapStyle = .round
                line.stroke()
            }
            _ = context
        }
    }

    private static func lockCircle() -> UIImage {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.systemGray3.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)).fill()
            let lock = UIImage(
                systemName: "lock.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            )?.withTintColor(.white, renderingMode: .alwaysOriginal)
            if let lock {
                lock.draw(at: CGPoint(x: (size.width - lock.size.width) / 2, y: (size.height - lock.size.height) / 2))
            }
        }
    }

    /// `selected` is nil for no colour; locked circles carry a lock instead of the ring.
    func configure(selected: Int?, isLocked: Bool, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        for (colorId, button) in buttons {
            button.setImage(
                Self.circle(colorId: colorId, isSelected: (selected ?? -1) == colorId && !isLocked),
                for: .normal,
            )
            button.accessibilityLabel = colorId < 0 ? L10n.telegram("ChatListFilter.TagLabelNoTag") : nil
            button.accessibilityTraits = (selected ?? -1) == colorId ? [.button, .selected] : .button
        }
        if isLocked, let first = buttons.first?.button {
            first.setImage(Self.lockCircle(), for: .normal)
        }
    }
}

// MARK: - ChatListFolderTagsView

/// ChatListItemTagListComponent: up to three folder tags 5 pt apart, then +N in the date colour for the rest.
final class ChatListFolderTagsView: UIView {
    private let stack = UIStackView()
    private var labels = [FolderTagLabel]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ tags: [(id: Int, name: String, colorId: Int)]) {
        var items = tags.prefix(3).map { (text: $0.name.uppercased(), color: FolderTagPalette.color($0.colorId)) }
        if tags.count > 3 { items.append((text: "+\(tags.count - 3)", color: .secondaryLabel)) }
        while labels.count < items.count {
            let label = FolderTagLabel()
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            labels.append(label)
            stack.addArrangedSubview(label)
        }
        for (index, label) in labels.enumerated() {
            if let item = items[safe: index] {
                label.configure(text: item.text, color: item.color)
                label.isHidden = false
            } else {
                label.isHidden = true
            }
        }
    }
}
