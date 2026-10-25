// SettingsListViewController.swift

import TDLibKit
import UIKit

// MARK: - SettingsRow

/// One row of a settings screen, BetterTG's inset-grouped take on Telegram's ItemListController items.
struct SettingsRow {
    enum Accessory {
        case none
        case disclosure
        case checkmark
        case toggle(isOn: Bool, onChange: (Bool) -> Void)
        case activity
    }

    enum Style {
        /// The title, with `detail` on the right.
        case value
        /// The title, with `detail` on the lines below.
        case subtitle
        /// A tinted action, such as Telegram's "Terminate all other sessions".
        case action(destructive: Bool)
        /// A person or chat with its avatar; `detail` is the line below the name.
        case peer(SettingsPeer)
        /// Text in the row's colour, such as Telegram's username availability status.
        case status(UIColor)
        /// An editable field, such as Telegram's name, bio and username inputs.
        case input(SettingsTextInput)
        /// A sticker or emoji set as ItemListStickerPackItem shows it; `detail` is its count.
        case stickerSet(SettingsStickerSet)
    }

    var title: String
    var detail: String?
    /// The detail's colour instead of the secondary one, such as Telegram's blue "online" under a contact.
    var detailColor: UIColor?
    var style = Style.value
    var symbol: String?
    var symbolTint = UIColor.systemBlue
    var accessory = Accessory.none
    var isEnabled = true
    var action: (() -> Void)?
    /// Telegram's revealed row option, such as Terminate, Unblock or Remove from Exceptions.
    var swipeAction: (title: String, handler: () -> Void)?
    /// ItemListDisclosureItem's `.badge` label: the text on an accent pill before the disclosure arrow.
    var badge: String?
    /// A view before the disclosure arrow in place of the detail, such as ItemListReactionItem's reaction.
    var trailingView: SettingsTrailingView?
}

// MARK: - SettingsTrailingView

/// Makes a row's trailing view each time its cell is configured. A struct, so a row's trailing closure stays its
/// action.
struct SettingsTrailingView {
    let make: () -> UIView
}

// MARK: - SettingsPeer

struct SettingsPeer {
    let id: Int64
    let title: String
    let file: File?
    let minithumbnail: Minithumbnail?
    let placeholder: TelegramAvatarPlaceholder

    init(id: Int64, title: String, file: File?, minithumbnail: Minithumbnail?, placeholder: TelegramAvatarPlaceholder) {
        self.id = id
        self.title = title
        self.file = file
        self.minithumbnail = minithumbnail
        self.placeholder = placeholder
    }

    init(chat: Chat) {
        self.id = chat.id
        self.title = chat.title
        self.file = chat.photo?.small
        self.minithumbnail = chat.photo?.minithumbnail
        self.placeholder = TelegramAvatarPlaceholder(
            peerID: chat.id,
            accentColorID: chat.accentColorId,
            upgradedGiftColors: chat.upgradedGiftColors,
            letters: chat.title.telegramAvatarFirstLetter.map { [$0] } ?? [],
            isDeleted: false,
        )
    }

    /// A person or chat as TDLib reports it now; nil when TDLib doesn't know it.
    @MainActor static func resolve(_ sender: MessageSender, client: TDLibClient) async -> SettingsPeer? {
        switch sender {
        case .messageSenderUser(let value): await user(value.userId, client: client)
        case .messageSenderChat(let value): await chat(value.chatId, client: client)
        }
    }

    @MainActor static func user(_ id: Int64, client: TDLibClient) async -> SettingsPeer? {
        guard let user = try? await client.getUser(userId: id) else { return nil }
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return SettingsPeer(
            id: user.id,
            title: name.isEmpty ? L10n.telegram("User.DeletedAccount") : name,
            file: user.profilePhoto?.small,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
        )
    }

    @MainActor static func chat(_ id: Int64, client: TDLibClient) async -> SettingsPeer? {
        guard let chat = try? await client.getChat(chatId: id) else { return nil }
        return SettingsPeer(chat: chat)
    }
}

// MARK: - SettingsStickerSet

struct SettingsStickerSet {
    let info: TDNativeStickerSetInfo
    /// ItemListStickerPackItem's `.installation(installed: false)` control: Telegram's ADD button.
    var add: (() -> Void)?
}

// MARK: - SettingsSection

struct SettingsSection {
    var header: String?
    var footer: String?
    var rows: [SettingsRow]
}

// MARK: - SettingsTextInput

struct SettingsTextInput {
    var text: String
    var placeholder: String
    /// Text before the field, such as "t.me/".
    var prefix: String?
    /// Telegram's character limit; the remaining count shows beside the text.
    var maxLength: Int?
    var isMultiline = false
    var autocapitalization = UITextAutocapitalizationType.sentences
    var autocorrection = true
    var keyboardType = UIKeyboardType.default
    var onChange: (String) -> Void
}

// MARK: - SettingsListViewController

/// The base of BetterTG's settings screens. A screen keeps its own state, describes it in `makeSections()` and calls
/// `reload()` after a change. Requests run on the account's current client; a screen of another account does
/// nothing.
class SettingsListViewController: UITableViewController {
    private static let cellIdentifier = "SettingsListCell"

    let accountID: UUID?
    private(set) var sections = [SettingsSection]()

    var client: TDLibClient {
        TDLib.shared.activeClient
    }

    var contextIsCurrent: Bool {
        accountID != nil && TDLib.shared.activeAccountID == accountID
    }

    init() {
        self.accountID = TDLib.shared.activeAccountID
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.register(SettingsPeerCell.self, forCellReuseIdentifier: SettingsPeerCell.reuseIdentifier)
        tableView.register(SettingsInputCell.self, forCellReuseIdentifier: SettingsInputCell.reuseIdentifier)
        tableView.register(SettingsStickerSetCell.self, forCellReuseIdentifier: SettingsStickerSetCell.reuseIdentifier)
        tableView.keyboardDismissMode = .interactive
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: Table

    override func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[safe: section]?.rows.count ?? 0
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[safe: section]?.header
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[safe: section]?.footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = settingsRow(at: indexPath) else { return UITableViewCell() }
        if case .input(let input) = row.style {
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsInputCell.reuseIdentifier, for: indexPath)
            (cell as? SettingsInputCell)?.configure(input: input) { [weak tableView] in
                UIView.performWithoutAnimation {
                    tableView?.performBatchUpdates(nil)
                }
            }
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.selectionStyle = .none
            return cell
        }
        if case .peer(let peer) = row.style {
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsPeerCell.reuseIdentifier, for: indexPath)
            (cell as? SettingsPeerCell)?.configure(
                peer: peer,
                detail: row.detail,
                detailColor: row.detailColor,
                client: client,
                accountID: accountID,
            )
            apply(row, to: cell)
            return cell
        }
        if case .stickerSet(let set) = row.style {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsStickerSetCell.reuseIdentifier,
                for: indexPath,
            )
            (cell as? SettingsStickerSetCell)?.configure(set: set, detail: row.detail, client: client)
            apply(row, to: cell)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        var configuration: UIListContentConfiguration =
            switch row.style {
            case .value: .valueCell()
            case .subtitle: .subtitleCell()
            case .action,
                 .input,
                 .peer,
                 .status,
                 .stickerSet: .cell()
            }
        configuration.text = row.title
        configuration.secondaryText = row.detail
        configuration.secondaryTextProperties.color = row.detailColor ?? .secondaryLabel
        if case .subtitle = row.style {
            configuration.secondaryTextProperties.numberOfLines = 0
            configuration.textToSecondaryTextVerticalPadding = 3
        }
        switch row.style {
        case .action(let destructive):
            configuration.textProperties.color = destructive ? .systemRed : .tintColor
        case .status(let color):
            configuration.textProperties.color = color
            configuration.textProperties.font = .preferredFont(forTextStyle: .footnote)
        case .input,
             .peer,
             .stickerSet,
             .subtitle,
             .value:
            break
        }
        if let symbol = row.symbol {
            configuration.image = UIImage(systemName: symbol)
            configuration.imageProperties.tintColor = row.symbolTint
            configuration.imageProperties.maximumSize = CGSize(width: 25, height: 25)
        }
        if !row.isEnabled {
            configuration.textProperties.color = .tertiaryLabel
        }
        cell.contentConfiguration = configuration
        apply(row, to: cell)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = settingsRow(at: indexPath), row.isEnabled else { return }
        row.action?()
    }

    /// Sets play their thumbnails while on screen, as ItemListStickerPackItem does with `playAnimatedStickers`.
    override func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt _: IndexPath) {
        (cell as? SettingsStickerSetCell)?.setPlaybackVisible(true)
    }

    override func tableView(_: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt _: IndexPath) {
        (cell as? SettingsStickerSetCell)?.setPlaybackVisible(false)
    }

    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard let swipe = settingsRow(at: indexPath)?.swipeAction else { return nil }
        let action = UIContextualAction(style: .destructive, title: swipe.title) { _, _, completion in
            swipe.handler()
            completion(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    /// The screen's rows for its current state.
    func makeSections() -> [SettingsSection] {
        []
    }

    func reload() {
        sections = makeSections()
        guard isViewLoaded else { return }
        tableView.reloadData()
    }

    /// Rebuilds the rows without redrawing them, after the table moved a row itself or changed editing.
    final func rebuildSections() {
        sections = makeSections()
    }

    /// Rebuilds the rows but redraws only these sections, so a field being edited keeps its keyboard.
    func reload(sections indexes: IndexSet) {
        let previousCount = sections.count
        sections = makeSections()
        guard isViewLoaded else { return }
        guard sections.count == previousCount else {
            tableView.reloadData()
            return
        }
        UIView.performWithoutAnimation {
            tableView.reloadSections(indexes, with: .none)
        }
    }

    /// Runs a request the user asked for on the account's client. A failure shows Telegram's generic error, or
    /// `failureText` when the caller knows the reason.
    final func perform(
        failureText: ((Error) -> String?)? = nil,
        _ request: @escaping @MainActor (TDLibClient) async throws -> Void,
        completion: (@MainActor () -> Void)? = nil,
    ) {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            do {
                try await request(client)
                guard let self, contextIsCurrent else { return }
                completion?()
            } catch {
                guard let self, contextIsCurrent else { return }
                if let text = failureText?(error) {
                    presentAlert(title: nil, message: text)
                } else {
                    presentChatListActionFailure()
                }
            }
        }
    }

    func presentAlert(title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        chatListTopPresenter.present(alert, animated: true)
    }

    /// Telegram's confirmation before a destructive change.
    func confirm(
        title: String? = nil,
        message: String?,
        actionTitle: String,
        isDestructive: Bool = true,
        perform: @escaping () -> Void,
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: actionTitle, style: isDestructive ? .destructive : .default) { _ in
            perform()
        })
        chatListTopPresenter.present(alert, animated: true)
    }

    func showToast(_ text: String) {
        TelegramUndoToast.show(text: text, in: view, bottomInset: 12, undo: nil)
    }

    func settingsRow(at indexPath: IndexPath) -> SettingsRow? {
        sections[safe: indexPath.section]?.rows[safe: indexPath.row]
    }

    private func apply(_ row: SettingsRow, to cell: UITableViewCell) {
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = row.action != nil && row.isEnabled ? .default : .none
        switch row.accessory {
        case .none:
            break
        case .disclosure:
            cell.accessoryType = .disclosureIndicator
        case .checkmark:
            cell.accessoryType = .checkmark
        case .toggle(let isOn, let onChange):
            let toggle = SettingsSwitch()
            toggle.isOn = isOn
            toggle.isEnabled = row.isEnabled
            toggle.onChange = onChange
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .activity:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            cell.accessoryView = indicator
        }
        // A badge or trailing view takes the accessory's place and draws the disclosure arrow itself.
        let showsDisclosure =
            if case .disclosure = row.accessory {
                true
            } else {
                false
            }
        if let badge = row.badge {
            cell.accessoryType = .none
            cell.accessoryView = SettingsBadgeAccessoryView(text: badge, showsDisclosure: showsDisclosure)
        } else if let trailingView = row.trailingView {
            cell.accessoryType = .none
            cell.accessoryView = SettingsTrailingAccessoryView(
                content: trailingView.make(),
                showsDisclosure: showsDisclosure,
            )
        }
    }
}

// MARK: - SettingsBadgeAccessoryView

/// ItemListDisclosureItem's badge: the text in 15 pt white on a 20 pt accent pill, 6 pt before the arrow.
private final class SettingsBadgeAccessoryView: UIView {
    init(text: String, showsDisclosure: Bool) {
        super.init(frame: .zero)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .white
        label.textAlignment = .center
        let pill = UIView()
        pill.backgroundColor = .tintColor
        pill.layer.cornerRadius = 10
        pill.addSubview(label)
        let labelSize = label.intrinsicContentSize
        let pillWidth = max(20, ceil(labelSize.width) + 12)
        pill.frame = CGRect(x: 0, y: 0, width: pillWidth, height: 20)
        label.frame = pill.bounds
        addSubview(pill)
        var width = pillWidth
        if showsDisclosure {
            let arrow = UIImageView(image: UIImage(
                systemName: "chevron.forward",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
            ))
            arrow.tintColor = .tertiaryLabel
            arrow.sizeToFit()
            arrow.frame.origin = CGPoint(x: pillWidth + 6, y: (20 - arrow.bounds.height) / 2)
            addSubview(arrow)
            width = arrow.frame.maxX
        }
        frame = CGRect(x: 0, y: 0, width: width, height: 20)
        isAccessibilityElement = true
        accessibilityLabel = text
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - SettingsTrailingAccessoryView

/// A row's own view, its intrinsic size centred in a 28 pt column, 6 pt before the disclosure arrow.
private final class SettingsTrailingAccessoryView: UIView {
    init(content: UIView, showsDisclosure: Bool) {
        super.init(frame: .zero)
        let size = content.intrinsicContentSize
        let side = CGSize(width: max(28, size.width), height: 28)
        content.frame = CGRect(
            x: (side.width - max(size.width, 0)) / 2,
            y: (side.height - max(size.height, 0)) / 2,
            width: max(size.width, 0),
            height: max(size.height, 0),
        )
        addSubview(content)
        var width = side.width
        if showsDisclosure {
            let arrow = UIImageView(image: UIImage(
                systemName: "chevron.forward",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
            ))
            arrow.tintColor = .tertiaryLabel
            arrow.sizeToFit()
            arrow.frame.origin = CGPoint(x: width + 6, y: (side.height - arrow.bounds.height) / 2)
            addSubview(arrow)
            width = arrow.frame.maxX
        }
        frame = CGRect(x: 0, y: 0, width: width, height: side.height)
        isAccessibilityElement = content.isAccessibilityElement
        accessibilityLabel = content.accessibilityLabel
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - SettingsSwitch

private final class SettingsSwitch: UISwitch {
    var onChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(valueChanged), for: .valueChanged)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func valueChanged() {
        onChange?(isOn)
    }
}

// MARK: - SettingsPeerCell

final class SettingsPeerCell: UITableViewCell {
    static let reuseIdentifier = "SettingsPeerCell"

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let stack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 2
        for subview in [avatarView, stack] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),
            stack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
        ])
        separatorInset.left = 64
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(
        peer: SettingsPeer,
        detail: String?,
        detailColor: UIColor? = nil,
        client: TDLibClient,
        accountID: UUID?,
    ) {
        nameLabel.text = peer.title
        detailLabel.text = detail
        detailLabel.textColor = detailColor ?? .secondaryLabel
        detailLabel.isHidden = detail?.isEmpty != false
        accessibilityLabel = [peer.title, detail].compactMap(\.self).joined(separator: ", ")
        avatarView.configure(
            file: peer.file,
            minithumbnail: peer.minithumbnail,
            placeholder: peer.placeholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
    }
}

// MARK: - SettingsInputCell

/// Telegram's ItemListSingleLineInputItem and ItemListMultilineInputItem: a field with an optional prefix and, with a
/// limit, the remaining character count.
final class SettingsInputCell: UITableViewCell, UITextFieldDelegate, UITextViewDelegate {
    static let reuseIdentifier = "SettingsInputCell"

    private let prefixLabel = UILabel()
    private let textField = UITextField()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let counterLabel = UILabel()
    private let stack = UIStackView()
    private var input: SettingsTextInput?
    private var onHeightChange: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        prefixLabel.font = .preferredFont(forTextStyle: .body)
        prefixLabel.adjustsFontForContentSizeCategory = true
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.clearButtonMode = .whileEditing
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        counterLabel.font = .preferredFont(forTextStyle: .footnote)
        counterLabel.adjustsFontForContentSizeCategory = true
        counterLabel.textColor = .secondaryLabel
        counterLabel.setContentHuggingPriority(.required, for: .horizontal)
        counterLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        for subview in [prefixLabel, textField, textView, counterLabel] as [UIView] {
            stack.addArrangedSubview(subview)
        }
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(input: SettingsTextInput, onHeightChange: @escaping () -> Void) {
        self.input = input
        self.onHeightChange = onHeightChange
        prefixLabel.text = input.prefix
        prefixLabel.isHidden = input.prefix == nil
        textField.isHidden = input.isMultiline
        textView.isHidden = !input.isMultiline
        stack.alignment = input.isMultiline ? .top : .center
        textField.autocapitalizationType = input.autocapitalization
        textField.autocorrectionType = input.autocorrection ? .default : .no
        textField.keyboardType = input.keyboardType
        textView.autocapitalizationType = input.autocapitalization
        textView.autocorrectionType = input.autocorrection ? .default : .no
        if input.isMultiline {
            if textView.text != input.text { textView.text = input.text }
            placeholderLabel.text = input.placeholder
        } else {
            if textField.text != input.text { textField.text = input.text }
            textField.placeholder = input.placeholder
            placeholderLabel.text = nil
        }
        updateDecorations()
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        allows(current: textField.text ?? "", range: range, replacement: string)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        allows(current: textView.text ?? "", range: range, replacement: text)
    }

    func textViewDidChange(_ textView: UITextView) {
        input?.text = textView.text
        input?.onChange(textView.text)
        updateDecorations()
        onHeightChange?()
    }

    @objc private func textFieldChanged() {
        let text = textField.text ?? ""
        input?.text = text
        input?.onChange(text)
        updateDecorations()
    }

    private func allows(current: String, range: NSRange, replacement: String) -> Bool {
        guard let maxLength = input?.maxLength, let range = Range(range, in: current) else { return true }
        return current.replacingCharacters(in: range, with: replacement).count <= maxLength
    }

    private func updateDecorations() {
        guard let input else { return }
        placeholderLabel.isHidden = !input.isMultiline || !input.text.isEmpty
        if let maxLength = input.maxLength {
            counterLabel.isHidden = false
            counterLabel.text = String(maxLength - input.text.count)
        } else {
            counterLabel.isHidden = true
        }
    }
}

// MARK: - SettingsFormatting

enum SettingsFormatting {
    /// Telegram's timeIntervalString for whole days, weeks, months and years.
    static func timeInterval(seconds: Int) -> String {
        let day = 24 * 60 * 60
        let (key, count): (String, Int) =
            if seconds < 60 * 60 {
                ("MessageTimer.Minutes", max(1, seconds / 60))
            } else if seconds < day {
                ("MessageTimer.Hours", seconds / (60 * 60))
            } else if seconds < day * 7 {
                ("MessageTimer.Days", seconds / day)
            } else if seconds < day * 30 {
                ("MessageTimer.Weeks", seconds / (day * 7))
            } else if seconds < day * 365 {
                ("MessageTimer.Months", seconds / (day * 30))
            } else {
                ("MessageTimer.Years", seconds / (day * 365))
            }
        return L10n.telegramPlural(key, count: max(1, count))
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Telegram's stringForRelativeActivityTimestamp: the time today, otherwise the date.
    static func activityDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .numeric, time: .omitted)
    }
}

extension String {
    /// A Telegram string without its Markdown: `**bold**` becomes plain and `[text](link)` keeps the text.
    var withoutTelegramLinks: String {
        var result = withoutTelegramMarkup
        while let open = result.range(of: "["),
              let close = result.range(of: "](", range: open.upperBound..<result.endIndex),
              let end = result.range(of: ")", range: close.upperBound..<result.endIndex)
        {
            let text = String(result[open.upperBound..<close.lowerBound])
            result.replaceSubrange(open.lowerBound..<end.upperBound, with: text)
        }
        return result
    }
}
