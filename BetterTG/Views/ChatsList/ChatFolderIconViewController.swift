// ChatFolderIconViewController.swift

import UIKit

// MARK: - ChatFolderIconViewController

/// A folder's icon, Automatic or one of TDLib's, and what its tab shows. Each choice goes to `onChange` at once: the
/// folder editor saves it with the folder, All Chats keeps it on this device.
final class ChatFolderIconViewController: UITableViewController {
    struct Choice: Equatable {
        var icon: FolderIcon?
        var style: FolderTabStyle
    }

    // MARK: Private

    private enum Section: Int, CaseIterable {
        case icon
        case tab
    }

    private var choice: Choice
    private let automaticIcon: FolderIcon
    private let footer: String
    private let onChange: (Choice) -> Void
    private lazy var grid = FolderIconGridView { [weak self] icon in self?.choose(icon) }
    private lazy var gridCell: UITableViewCell = {
        let cell = UITableViewCell()
        cell.selectionStyle = .none
        grid.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(grid)
        let margins = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
        ])
        return cell
    }()

    init(choice: Choice, automaticIcon: FolderIcon, footer: String, onChange: @escaping (Choice) -> Void) {
        self.choice = choice
        self.automaticIcon = automaticIcon
        self.footer = footer
        self.onChange = onChange
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.betterTG("Folders.Icon")
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderIconCell")
        grid.selectedIcon = choice.icon
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func numberOfSections(in _: UITableView) -> Int { Section.allCases.count }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .icon: 2
        case .tab: FolderTabStyle.allCases.count
        case nil: 0
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section) == .tab ? L10n.betterTG("Folders.Icon.TabHeader") : nil
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .icon: footer
        case .tab: L10n.betterTG("Folders.Icon.TabFooter")
        case nil: nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .icon, indexPath.row == 1 { return gridCell }
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderIconCell", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        if Section(rawValue: indexPath.section) == .icon {
            configuration.text = L10n.betterTG("Folders.Icon.Automatic")
            configuration.secondaryText = automaticIcon.title
            configuration.secondaryTextProperties.color = .secondaryLabel
            configuration.image = automaticIcon.image
            configuration.imageProperties.tintColor = .label
            cell.accessoryType = choice.icon == nil ? .checkmark : .none
        } else {
            let style = FolderTabStyle.allCases[indexPath.row]
            configuration.text = style.title
            cell.accessoryType = choice.style == style ? .checkmark : .none
        }
        cell.contentConfiguration = configuration
        return cell
    }

    override func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        !(Section(rawValue: indexPath.section) == .icon && indexPath.row == 1)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .icon {
            choose(nil)
        } else {
            update(Choice(icon: choice.icon, style: FolderTabStyle.allCases[indexPath.row]))
        }
    }

    /// Choosing an icon, or Automatic, brings back the icon of a tab that showed only its name.
    private func choose(_ icon: FolderIcon?) {
        update(Choice(icon: icon, style: choice.style == .nameOnly ? .iconAndName : choice.style))
    }

    private func update(_ choice: Choice) {
        guard choice != self.choice else { return }
        self.choice = choice
        grid.selectedIcon = choice.icon
        onChange(choice)
        let rows = [IndexPath(row: 0, section: Section.icon.rawValue)]
            + FolderTabStyle.allCases.indices.map { IndexPath(row: $0, section: Section.tab.rawValue) }
        tableView.reloadRows(at: rows, with: .none)
    }
}

// MARK: - FolderIconGridView

/// TDLib's icons in rows of six; the chosen one sits on a tinted circle.
private final class FolderIconGridView: UIView {
    // MARK: Private

    private static let columns = 6
    private static let buttonSide: CGFloat = 44
    private static let iconSide: CGFloat = 24

    // MARK: Internal

    var selectedIcon: FolderIcon? {
        didSet { updateSelection() }
    }

    private let onSelect: (FolderIcon) -> Void
    private var buttons = [FolderIcon: UIButton]()

    init(onSelect: @escaping (FolderIcon) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateSelection()
    }

    private func configureViews() {
        let rows = UIStackView()
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical
        rows.spacing = 8
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let icons = FolderIcon.allCases
        for start in stride(from: 0, to: icons.count, by: Self.columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .equalSpacing
            for icon in icons[start..<min(start + Self.columns, icons.count)] {
                let button = UIButton(type: .custom)
                button.configuration = .plain()
                button.configuration?.image = icon.image(side: Self.iconSide)
                button.configuration?.cornerStyle = .capsule
                button.accessibilityLabel = icon.title
                button.addAction(UIAction { [weak self] _ in self?.onSelect(icon) }, for: .primaryActionTriggered)
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: Self.buttonSide),
                    button.heightAnchor.constraint(equalToConstant: Self.buttonSide),
                ])
                buttons[icon] = button
                row.addArrangedSubview(button)
            }
            rows.addArrangedSubview(row)
        }
        updateSelection()
    }

    private func updateSelection() {
        for (icon, button) in buttons {
            let selected = icon == selectedIcon
            button.configuration?.baseForegroundColor = selected ? tintColor : .label
            button.configuration?.background.backgroundColor = selected
                ? tintColor.withAlphaComponent(0.15)
                : .clear
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }
}
