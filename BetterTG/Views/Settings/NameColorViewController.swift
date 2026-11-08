// NameColorViewController.swift

import TDLibKit
import UIKit

// MARK: - NameColorViewController

/// PeerNameColorScreen for the account, its Profile and Name tabs. Profile: the profile's header in the chosen
/// profile colour's gradient with the avatar and name, the profile colours (updateProfileAccentColors) and Reset
/// Profile Color. Name: COLOR PREVIEW with a message from the account in the chosen colour (its name, a reply to it
/// and a link preview), then PeerNameColorItem's colours (updateAccentColors' available ones, a server colour's
/// stripes split around its circle) and the description. Apply Color sets what changed, keeping the icons
/// (setProfileAccentColor, setAccentColor).
final class NameColorViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Tab: Int {
        case profile
        case name
    }

    private let client: TDLibClient
    private let user: User
    private let name: String
    private let backgroundCustomEmojiID: Int64
    private let originalColorID: Int
    private var colorID: Int
    private let originalProfileColorID: Int
    private var profileColorID: Int
    private var selectedTab = Tab.profile
    private let tabs = UISegmentedControl(items: [
        L10n.telegram("ProfileColorSetup.TitleProfile"),
        L10n.telegram("ProfileColorSetup.TitleName"),
    ])
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let applyButton = UIButton(configuration: .prominentGlass())

    init(client: TDLibClient, user: User) {
        self.client = client
        self.user = user
        self.name = ServiceMessageText.displayTitle(user)
        self.backgroundCustomEmojiID = user.backgroundCustomEmojiId
        self.originalColorID = user.accentColorId
        self.colorID = user.accentColorId
        self.originalProfileColorID = user.profileAccentColorId
        self.profileColorID = user.profileAccentColorId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabs.selectedSegmentIndex = selectedTab.rawValue
        tabs.addAction(UIAction { [weak self] _ in
            guard let self, let tab = Tab(rawValue: tabs.selectedSegmentIndex) else { return }
            selectedTab = tab
            tableView.reloadData()
        }, for: .valueChanged)
        navigationItem.titleView = tabs
        view.backgroundColor = .systemGroupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            ProfileColorPreviewCell.self,
            forCellReuseIdentifier: ProfileColorPreviewCell.reuseIdentifier,
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ResetCell")
        tableView.register(NameColorPreviewCell.self, forCellReuseIdentifier: NameColorPreviewCell.reuseIdentifier)
        tableView.register(NameColorGridCell.self, forCellReuseIdentifier: NameColorGridCell.reuseIdentifier)
        view.addSubview(tableView)
        var title = AttributedString(L10n.telegram("NameColor.ApplyColor"))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        applyButton.configuration?.attributedTitle = title
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.addAction(UIAction { [weak self] _ in self?.apply() }, for: .touchUpInside)
        view.addSubview(applyButton)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -8),
            applyButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            applyButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            applyButton.heightAnchor.constraint(equalToConstant: 50),
            applyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    func numberOfSections(in _: UITableView) -> Int {
        selectedTab == .profile && profileColorID >= 0 ? 3 : 2
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { 1 }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        selectedTab == .name && section == 0 ? L10n.telegram("NameColor.ChatPreview.Title") : nil
    }

    func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return L10n.telegram(selectedTab == .profile
            ? "ProfileColorSetup.AccountColorInfoLabel"
            : "NameColor.ChatPreview.Description.Account")
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Reset Profile Color.
        guard selectedTab == .profile, indexPath.section == 2 else { return }
        profileColorID = -1
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if selectedTab == .profile {
            return profileCell(tableView, at: indexPath)
        }
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NameColorPreviewCell.reuseIdentifier,
                for: indexPath,
            )
            (cell as? NameColorPreviewCell)?.configure(
                name: name,
                colors: AvatarColorPalette.shared.nameColors(accentColorID: colorID),
            )
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: NameColorGridCell.reuseIdentifier, for: indexPath)
        (cell as? NameColorGridCell)?.configure(
            colors: AvatarColorPalette.shared.availableAccentColorIDs.map {
                (id: $0, colors: AvatarColorPalette.shared.nameColors(accentColorID: $0))
            },
            selected: colorID,
        ) { [weak self] id in self?.choose(id) }
        return cell
    }

    /// The Profile tab: the header, the profile colours, and Reset Profile Color while one is chosen.
    private func profileCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: ProfileColorPreviewCell.reuseIdentifier,
                for: indexPath,
            )
            (cell as? ProfileColorPreviewCell)?.configure(
                user: user,
                name: name,
                background: AvatarColorPalette.shared.profileColors(id: profileColorID)?.background,
                client: client,
            )
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: NameColorGridCell.reuseIdentifier, for: indexPath)
            (cell as? NameColorGridCell)?.configure(
                colors: AvatarColorPalette.shared.availableProfileAccentColorIDs.compactMap { id in
                    AvatarColorPalette.shared.profileColors(id: id).map { (id: id, colors: $0.palette) }
                },
                selected: profileColorID,
            ) { [weak self] id in
                guard let self, id != profileColorID else { return }
                profileColorID = id
                tableView.reloadData()
            }
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ResetCell", for: indexPath)
            var configuration = cell.defaultContentConfiguration()
            configuration.text = L10n.telegram("ProfileColorSetup.ResetAction")
            configuration.textProperties.color = .systemBlue
            cell.contentConfiguration = configuration
            return cell
        }
    }

    private func choose(_ id: Int) {
        guard id != colorID else { return }
        colorID = id
        tableView.reloadData()
    }

    /// Apply Color: the colour with the reply icon the account has, then the toast over the screen it came from.
    private func apply() {
        let client = client
        let colorID = colorID
        let emojiID = backgroundCustomEmojiID
        let host = navigationController?.view
        if profileColorID != originalProfileColorID {
            let profileColorID = profileColorID
            let profileEmojiID = user.profileBackgroundCustomEmojiId
            Task {
                _ = try? await client.send(TDNativeRequests.setProfileAccentColor(
                    profileAccentColorId: profileColorID,
                    profileBackgroundCustomEmojiId: profileEmojiID,
                ))
            }
        }
        if colorID != originalColorID {
            Task {
                _ = try? await client.send(TDNativeRequests.setAccentColor(
                    accentColorId: colorID,
                    backgroundCustomEmojiId: emojiID,
                ))
            }
            if let host {
                TelegramUndoToast.show(
                    text: L10n.telegram("NameColor.YourColorUpdated"),
                    in: host,
                    bottomInset: 12,
                    undo: nil,
                )
            }
        }
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - NameColorPreviewCell

/// The preview message: the name in the colour, a reply quote to the account with the colour's bar and tint, the
/// text, and a link preview tinted the same way.
private final class NameColorPreviewCell: UITableViewCell {
    static let reuseIdentifier = "NameColorPreviewCell"

    private let bubble = UIView()
    private let nameLabel = UILabel()
    private let reply = NameColorQuoteView()
    private let textLabelView = UILabel()
    private let link = NameColorQuoteView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        bubble.backgroundColor = .tertiarySystemFill
        bubble.layer.cornerRadius = 17
        bubble.layer.cornerCurve = .continuous
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        textLabelView.font = .systemFont(ofSize: 16)
        textLabelView.numberOfLines = 0
        textLabelView.text = L10n.telegram("NameColor.ChatPreview.MessageText.Account")
        let stack = UIStackView(arrangedSubviews: [nameLabel, reply, textLabelView, link])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(6, after: reply)
        stack.setCustomSpacing(6, after: textLabelView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(stack)
        contentView.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40),
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, colors: [UIColor]) {
        let color = colors.first ?? .systemBlue
        nameLabel.text = name
        nameLabel.textColor = color
        reply.configure(
            title: name,
            text: L10n.telegram("NameColor.ChatPreview.ReplyText.Account"),
            colors: colors,
            boldText: false,
        )
        link.configure(
            title: L10n.telegram("NameColor.ChatPreview.LinkSite"),
            text: L10n.telegram("NameColor.ChatPreview.LinkTitle") + "\n"
                + L10n.telegram("NameColor.ChatPreview.LinkText"),
            colors: colors,
            boldText: true,
        )
    }
}

// MARK: - NameColorQuoteView

/// A reply or link preview block: the colour's bar (striped for a server colour) over its tint, the title in the
/// colour and the text.
private final class NameColorQuoteView: UIView {
    private let bar = UIView()
    private let stripes = CAGradientLayer()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true
        bar.layer.addSublayer(stripes)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 1
        for view in [bar, stack] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),
            stack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stripes.frame = bar.bounds
    }

    func configure(title: String, text: String, colors: [UIColor], boldText: Bool) {
        let color = colors.first ?? .systemBlue
        backgroundColor = color.withAlphaComponent(0.1)
        bar.backgroundColor = color
        titleLabel.text = title
        titleLabel.textColor = color
        if boldText, let newline = text.firstIndex(of: "\n") {
            let attributed = NSMutableAttributedString(
                string: String(text[..<newline]),
                attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)],
            )
            attributed.append(NSAttributedString(
                string: String(text[newline...]),
                attributes: [.font: UIFont.systemFont(ofSize: 14)],
            ))
            bodyLabel.attributedText = attributed
        } else {
            bodyLabel.text = text
        }
        // A server colour's stripes run down the bar, 6 pt each, as ChatMessageReplyInfoNode dashes it.
        stripes.isHidden = colors.count < 2
        if colors.count >= 2 {
            var gradientColors = [CGColor]()
            var locations = [NSNumber]()
            let count = 12
            for index in 0..<count {
                let stripe = colors[index % colors.count].cgColor
                gradientColors += [stripe, stripe]
                locations += [
                    NSNumber(value: Double(index) / Double(count)),
                    NSNumber(value: Double(index + 1) / Double(count)),
                ]
            }
            stripes.colors = gradientColors
            stripes.locations = locations
            stripes.startPoint = CGPoint(x: 0.5, y: 0)
            stripes.endPoint = CGPoint(x: 0.5, y: 1)
        }
    }
}

// MARK: - NameColorGridCell

/// PeerNameColorItem: the colours seven to a row, a server colour's circle split into its colours, the chosen one
/// ringed.
private final class NameColorGridCell: UITableViewCell {
    static let reuseIdentifier = "NameColorGridCell"

    private let grid = UIStackView()
    private var onSelect: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        grid.axis = .vertical
        grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            grid.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The circle: the first colour, a second taking the lower right half and a third a band across the middle; the
    /// chosen one shrinks inside a ring.
    private static func circle(_ colors: [UIColor], isSelected: Bool) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            let inset: CGFloat = isSelected ? 6 : 2
            let disc = bounds.insetBy(dx: inset, dy: inset)
            let cg = context.cgContext
            cg.saveGState()
            cg.addEllipse(in: disc)
            cg.clip()
            (colors.first ?? .systemBlue).setFill()
            cg.fill(disc)
            if colors.count >= 2 {
                colors[1].setFill()
                let half = UIBezierPath()
                half.move(to: CGPoint(x: disc.maxX, y: disc.minY))
                half.addLine(to: CGPoint(x: disc.maxX, y: disc.maxY))
                half.addLine(to: CGPoint(x: disc.minX, y: disc.maxY))
                half.close()
                half.fill()
            }
            if colors.count >= 3 {
                colors[2].setFill()
                cg.translateBy(x: disc.midX, y: disc.midY)
                cg.rotate(by: -.pi / 4)
                cg.fill(CGRect(
                    x: -disc.width,
                    y: -disc.height * 0.12,
                    width: disc.width * 2,
                    height: disc.height * 0.24,
                ))
            }
            cg.restoreGState()
            if isSelected {
                (colors.first ?? .systemBlue).setStroke()
                let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
                ring.lineWidth = 2
                ring.stroke()
            }
        }
    }

    func configure(colors: [(id: Int, colors: [UIColor])], selected: Int, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let perRow = 7
        for start in stride(from: 0, to: colors.count, by: perRow) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .equalSpacing
            for (id, circleColors) in colors[start..<min(start + perRow, colors.count)] {
                let button = UIButton(type: .custom)
                button.setImage(Self.circle(circleColors, isSelected: id == selected), for: .normal)
                button.accessibilityTraits = id == selected ? [.button, .selected] : .button
                button.addAction(UIAction { [weak self] _ in self?.onSelect?(id) }, for: .touchUpInside)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 40),
                    button.heightAnchor.constraint(equalToConstant: 40),
                ])
                row.addArrangedSubview(button)
            }
            // A short last row keeps the columns.
            for _ in 0..<(perRow - row.arrangedSubviews.count) {
                let spacer = UIView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(equalToConstant: 40).isActive = true
                row.addArrangedSubview(spacer)
            }
            grid.addArrangedSubview(row)
        }
    }
}

// MARK: - ProfileColorPreviewCell

/// PeerInfoHeaderNode in the profile colour: the avatar and the name, in white over the colour's gradient, or in the
/// list's colours without one.
private final class ProfileColorPreviewCell: UITableViewCell {
    static let reuseIdentifier = "ProfileColorPreviewCell"

    private let gradient = CAGradientLayer()
    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.layer.insertSublayer(gradient, at: 0)
        avatarView.layer.cornerRadius = 40
        avatarView.clipsToBounds = true
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.text = L10n.telegram("Presence.online")
        let stack = UIStackView(arrangedSubviews: [avatarView, nameLabel, statusLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.setCustomSpacing(12, after: avatarView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 80),
            avatarView.heightAnchor.constraint(equalToConstant: 80),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = contentView.bounds
    }

    func configure(user: User, name: String, background: [UIColor]?, client: TDLibClient) {
        avatarView.configure(
            file: user.profilePhoto?.small,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
            usesPeerPhotoForSavedMessages: true,
            accountUserID: user.id,
            client: client,
        )
        nameLabel.text = name
        if let background, !background.isEmpty {
            let colors = background.count == 1 ? [background[0], background[0]] : background
            gradient.colors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
            gradient.isHidden = false
            nameLabel.textColor = .white
            statusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        } else {
            gradient.isHidden = true
            nameLabel.textColor = .label
            statusLabel.textColor = .systemBlue
        }
    }
}
