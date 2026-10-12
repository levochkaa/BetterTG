// ForumCreateTopicViewController.swift

import TDLibKit
import UIKit

// MARK: - ForumCreateTopicViewController

/// Telegram's ForumCreateTopicScreen: the topic name beside its icon, whose color cycles through
/// `ForumCreateTopicScreen.iconColors` on tap when creating, the topic icon grid, and Done once the name isn't empty.
/// Editing keeps the color, as TDLib can't change it. The grid offers TDLib's free default topic icons; Telegram's
/// Premium emoji packs are not offered.
@MainActor final class ForumCreateTopicViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UITextFieldDelegate
{
    // MARK: Internal

    enum Mode {
        case create
        case edit(name: String, color: Int, customEmojiID: Int64)
    }

    // MARK: Private

    private enum Section: Int, CaseIterable {
        case name
        case icon
    }

    static let iconColors = [0x6FB9F0, 0xFFD67E, 0xCB86DB, 0x8EEE98, 0xFF93B2, 0xFB6F5F]

    /// TDLib's limit for a topic name.
    private static let maximumNameLength = 128

    private let client: TDLibClient
    private let mode: Mode
    private let create: (_ name: String, _ color: Int, _ customEmojiID: Int64) async -> Bool
    private var iconColor = ForumCreateTopicViewController.iconColors.randomElement() ?? 0x6FB9F0
    private var selectedEmojiID: Int64 = 0
    private var defaultIcons = [ForumTopicIconGridView.Icon]()
    private var iconsTask: Task<Void, Never>?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let nameCell = UITableViewCell(style: .default, reuseIdentifier: nil)
    private let iconCell = UITableViewCell(style: .default, reuseIdentifier: nil)
    private let iconButton = UIControl()
    private let iconView = ForumTopicIconView()
    private let nameField = UITextField()
    private let iconGrid = ForumTopicIconGridView()
    private lazy var doneItem = UIBarButtonItem(
        title: L10n.telegram("Common.Done"),
        style: .prominent,
        target: self,
        action: #selector(donePressed),
    )
    private var isCreating = false

    private var trimmedName: String {
        (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        client: TDLibClient,
        mode: Mode = .create,
        create: @escaping (_ name: String, _ color: Int, _ customEmojiID: Int64) async -> Bool,
    ) {
        self.client = client
        self.mode = mode
        self.create = create
        super.init(nibName: nil, bundle: nil)
        if case .edit(_, let color, let customEmojiID) = mode {
            self.iconColor = color
            self.selectedEmojiID = customEmojiID
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        iconsTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch mode {
        case .create:
            title = L10n.telegram("CreateTopic.CreateTitle")
        case .edit(let name, _, _):
            title = L10n.telegram("CreateTopic.EditTitle")
            nameField.text = name
            // Telegram's edit screen doesn't recolor the icon.
            iconButton.isUserInteractionEnabled = false
            iconButton.isAccessibilityElement = false
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        navigationItem.rightBarButtonItem = doneItem
        doneItem.isEnabled = !trimmedName.isEmpty
        configureNameCell()
        configureIconCell()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateIcons()
        loadDefaultIcons()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isCreating { nameField.becomeFirstResponder() }
    }

    func numberOfSections(in _: UITableView) -> Int { Section.allCases.count }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { 1 }

    func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        Section(rawValue: indexPath.section) == .icon ? iconCell : nameCell
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .name: L10n.telegram("CreateTopic.EnterTopicTitle")
        case .icon: L10n.telegram("CreateTopic.SelectTopicIcon")
        case nil: nil
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard Section(rawValue: indexPath.section) == .icon else { return UITableView.automaticDimension }
        let width = tableView.bounds.width - tableView.layoutMargins.left - tableView.layoutMargins.right
        return ForumTopicIconGridView.height(forWidth: width, count: defaultIcons.count + 1)
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        let current = (textField.text ?? "") as NSString
        return current.replacingCharacters(in: range, with: string).count <= Self.maximumNameLength
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        donePressed()
        return false
    }

    private func configureNameCell() {
        nameCell.selectionStyle = .none
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconButton.translatesAutoresizingMaskIntoConstraints = false
        iconButton.isAccessibilityElement = true
        iconButton.accessibilityTraits = .button
        iconButton.accessibilityLabel = L10n.betterTG("Forum.TopicIconColor")
        iconButton.addTarget(self, action: #selector(iconPressed), for: .touchUpInside)
        iconButton.addSubview(iconView)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.placeholder = L10n.telegram("CreateTopic.EnterTopicTitlePlaceholder")
        nameField.font = .preferredFont(forTextStyle: .body)
        nameField.adjustsFontForContentSizeCategory = true
        nameField.returnKeyType = .done
        nameField.clearButtonMode = .whileEditing
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameCell.contentView.addSubview(iconButton)
        nameCell.contentView.addSubview(nameField)
        NSLayoutConstraint.activate([
            iconButton.leadingAnchor.constraint(equalTo: nameCell.contentView.leadingAnchor, constant: 6),
            iconButton.centerYAnchor.constraint(equalTo: nameCell.contentView.centerYAnchor),
            iconButton.widthAnchor.constraint(equalToConstant: 44),
            iconButton.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconButton.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconButton.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            nameField.leadingAnchor.constraint(equalTo: iconButton.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: nameCell.contentView.trailingAnchor, constant: -12),
            nameField.topAnchor.constraint(equalTo: nameCell.contentView.topAnchor),
            nameField.bottomAnchor.constraint(equalTo: nameCell.contentView.bottomAnchor),
            nameField.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    private func configureIconCell() {
        iconCell.selectionStyle = .none
        iconGrid.translatesAutoresizingMaskIntoConstraints = false
        iconGrid.onSelect = { [weak self] id in
            guard let self, !isCreating else { return }
            selectedEmojiID = id
            updateIcons()
        }
        iconCell.contentView.addSubview(iconGrid)
        NSLayoutConstraint.activate([
            iconGrid.topAnchor.constraint(equalTo: iconCell.contentView.topAnchor),
            iconGrid.leadingAnchor.constraint(equalTo: iconCell.contentView.leadingAnchor),
            iconGrid.trailingAnchor.constraint(equalTo: iconCell.contentView.trailingAnchor),
            iconGrid.bottomAnchor.constraint(equalTo: iconCell.contentView.bottomAnchor),
        ])
    }

    private func loadDefaultIcons() {
        let client = client
        iconsTask = Task { [weak self] in
            guard let stickers = try? await client.send(TDNativeRequests.getForumTopicDefaultIcons()),
                  !Task.isCancelled, let self else { return }
            defaultIcons = stickers.stickers.compactMap { sticker in
                guard case .stickerFullTypeCustomEmoji(let emoji) = sticker.fullType else { return nil }
                return ForumTopicIconGridView.Icon(id: emoji.customEmojiId, label: sticker.emoji)
            }
            updateIcons()
            tableView.reloadSections(IndexSet(integer: Section.icon.rawValue), with: .none)
        }
    }

    private func updateIcons() {
        let name = trimmedName
        iconView.configureDraft(name: name, color: iconColor, customEmojiID: selectedEmojiID, client: client)
        iconGrid.configure(
            icons: defaultIcons,
            name: name,
            color: iconColor,
            selectedID: selectedEmojiID,
            client: client,
        )
    }

    @objc private func nameChanged() {
        doneItem.isEnabled = !isCreating && !trimmedName.isEmpty
        updateIcons()
    }

    /// Telegram's `switchIcon`: tapping the icon steps to the next color.
    @objc private func iconPressed() {
        let colors = Self.iconColors
        let index = colors.firstIndex(of: iconColor).map { ($0 + 1) % colors.count } ?? 0
        iconColor = colors[index]
        updateIcons()
    }

    @objc private func cancelPressed() {
        guard !isCreating else { return }
        view.endEditing(true)
        dismiss(animated: true)
    }

    @objc private func donePressed() {
        let name = trimmedName
        guard !isCreating, !name.isEmpty else { return }
        setCreating(true)
        Task { [weak self] in
            guard let self else { return }
            let created = await create(name, iconColor, selectedEmojiID)
            // Telegram keeps the screen open and editable when creation fails.
            if !created { setCreating(false) }
        }
    }

    private func setCreating(_ creating: Bool) {
        isCreating = creating
        nameField.isEnabled = !creating
        iconButton.isEnabled = !creating
        iconGrid.isUserInteractionEnabled = !creating
        navigationItem.leftBarButtonItem?.isEnabled = !creating
        if creating {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            navigationItem.rightBarButtonItem = doneItem
            doneItem.isEnabled = !trimmedName.isEmpty
        }
    }
}

extension ForumCreateTopicViewController {
    /// Presents the screen; on Done creates the topic and opens it, as Telegram's `createForumChannelTopic` then
    /// `navigateToForumThread`.
    static func present(
        from presenter: UIViewController,
        customChat: CustomChat,
        location: ChatLocation,
        client: TDLibClient,
        canOpen: @escaping @MainActor () -> Bool,
    ) {
        let chatID = location.chatID
        let controller = ForumCreateTopicViewController(client: client) { [weak presenter] name, color, emojiID in
            guard let info = try? await client.send(TDNativeRequests.createForumTopic(
                chatId: chatID,
                name: name,
                isNameImplicit: false,
                icon: ForumTopicIcon(color: color, customEmojiId: emojiID),
            )) else { return false }
            let topic = try? await client.getForumTopic(chatId: chatID, forumTopicId: info.forumTopicId)
            presenter?.dismiss(animated: true) {
                guard let topic, canOpen() else { return }
                NavigationStorage.shared.push(.customChat(
                    customChat,
                    location: location.withForumTopic(id: info.forumTopicId),
                    forumTopic: topic,
                    targetMessageID: nil,
                    targetQuote: nil,
                ))
            }
            return true
        }
        presenter.present(UINavigationController(rootViewController: controller), animated: true)
    }

    /// Telegram's Edit topic action: rename and change the icon through `editForumTopic`, then close.
    static func presentEdit(from presenter: UIViewController, topic: ForumTopic, chatID: Int64, client: TDLibClient) {
        let topicID = topic.info.forumTopicId
        let mode = Mode.edit(
            name: topic.info.name,
            color: topic.info.icon.color,
            customEmojiID: topic.info.icon.customEmojiId,
        )
        let controller = ForumCreateTopicViewController(
            client: client,
            mode: mode,
        ) { [weak presenter] name, _, emojiID in
            guard await (try? client.send(TDNativeRequests.editForumTopic(
                chatId: chatID,
                forumTopicId: topicID,
                name: name,
                editIconCustomEmoji: true,
                iconCustomEmojiId: emojiID,
            ))) != nil else { return false }
            presenter?.dismiss(animated: true)
            return true
        }
        presenter.present(UINavigationController(rootViewController: controller), animated: true)
    }
}

// MARK: - ForumTopicIconGridView

/// Telegram's topic icon grid (EmojiPagerContentComponent for topic icons): the default colored icon first, then
/// the free topic icons, with the choice highlighted.
private final class ForumTopicIconGridView: UIView {
    struct Icon: Equatable {
        let id: Int64
        let label: String
    }

    private static let columns = 8
    private static let verticalInset: CGFloat = 8

    var onSelect: ((Int64) -> Void)?

    private var items = [(id: Int64, control: UIControl, icon: ForumTopicIconView)]()

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = bounds.width / CGFloat(Self.columns)
        for (index, item) in items.enumerated() {
            let frame = CGRect(
                x: CGFloat(index % Self.columns) * side,
                y: Self.verticalInset + CGFloat(index / Self.columns) * side,
                width: side,
                height: side,
            )
            item.control.frame = frame.insetBy(dx: 2, dy: 2)
            item.control.layer.cornerRadius = min(12, item.control.bounds.height / 2)
            item.icon.frame = item.control.bounds
        }
    }

    static func height(forWidth width: CGFloat, count: Int) -> CGFloat {
        let side = max(1, width) / CGFloat(columns)
        let rows = (max(1, count) + columns - 1) / columns
        return CGFloat(rows) * side + verticalInset * 2
    }

    func configure(icons: [Icon], name: String, color: Int, selectedID: Int64, client: TDLibClient) {
        let ids = [Int64(0)] + icons.map(\.id)
        if items.map(\.id) != ids { rebuild(ids: ids) }
        let labels = Dictionary(icons.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        for item in items {
            if item.id == 0 {
                item.icon.configureDraft(name: name, color: color)
                item.control.accessibilityLabel = L10n.betterTG("Forum.TopicIconDefault")
            } else {
                item.icon.configureDraft(name: "", color: color, customEmojiID: item.id, client: client)
                item.control.accessibilityLabel = labels[item.id]
            }
            let selected = item.id == selectedID
            item.control.backgroundColor = selected ? .tertiarySystemFill : .clear
            item.control.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    private func rebuild(ids: [Int64]) {
        items.forEach { $0.control.removeFromSuperview() }
        items = ids.map { id in
            let control = UIControl()
            control.isAccessibilityElement = true
            control.layer.cornerCurve = .continuous
            let icon = ForumTopicIconView()
            icon.isUserInteractionEnabled = false
            control.addSubview(icon)
            control.addAction(UIAction { [weak self] _ in self?.onSelect?(id) }, for: .touchUpInside)
            addSubview(control)
            return (id, control, icon)
        }
        setNeedsLayout()
    }
}
