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
        /// ItemListExpandableSwitchItem's head: the title, how many of its options are on out of all in bold, and an
        /// arrow that points down while the options are hidden and up while they show. Its action opens or closes them.
        case expandable(count: String, isExpanded: Bool)
        /// One of an expandable group's options (ItemListExpandableSwitchItem's SubItem): indented under the head, a
        /// check before the title. Its action flips it.
        case option(isSelected: Bool)
    }

    var title: String
    /// Secondary text right after the title, such as DataCategoryItemComponent's share.
    var titleSuffix: String?
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
    /// ItemListTextItem's `.markdown` footer with `linkAction`: each `[text](id)` in `footer` is a link that runs the
    /// action stored under its id.
    var footerLinks = [String: () -> Void]()
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
    /// ItemListSingleLineInputItem's `.password` type: the text stays hidden.
    var isSecure = false
    var textContentType: UITextContentType?
    var returnKeyType = UIReturnKeyType.default
    var onChange: (String) -> Void
    /// The return key's action, such as checking a password.
    var onReturn: (() -> Void)?
}

// MARK: - SettingsListViewController

/// The base of BetterTG's settings screens. A screen keeps its own state, describes it in `makeSections()` and calls
/// `reload()` after a change. Requests run on the account's current client; a screen of another account does
/// nothing.
class SettingsListViewController: UITableViewController {
    private static let cellIdentifier = "SettingsListCell"

    private static let expandArrowTag = 0x6578_7061

    let accountID: UUID?
    private(set) var sections = [SettingsSection]()
    /// focusOnItemTag: the row with this title, once the list has it on screen, comes into view and shows its
    /// highlight (displayHighlight), as a setting found by the settings search does.
    var focusedRowTitle: String?

    private var highlightedRow: (title: String, until: Date)?

    private var isRefreshingInPlace = false

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
        tableView.register(
            SettingsMarkdownFooterView.self,
            forHeaderFooterViewReuseIdentifier: SettingsMarkdownFooterView.reuseIdentifier,
        )
        tableView.keyboardDismissMode = .interactive
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focusRowIfNeeded()
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
        guard let section = sections[safe: section], section.footerLinks.isEmpty else { return nil }
        return section.footer
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let section = sections[safe: section], !section.footerLinks.isEmpty, let footer = section.footer,
              let view = tableView.dequeueReusableHeaderFooterView(
                  withIdentifier: SettingsMarkdownFooterView.reuseIdentifier,
              ) as? SettingsMarkdownFooterView
        else { return nil }
        view.configure(markdown: footer, links: section.footerLinks)
        return view
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
                 .expandable,
                 .input,
                 .option,
                 .peer,
                 .status,
                 .stickerSet: .cell()
            }
        configuration.text = row.title
        if let suffix = row.titleSuffix, !suffix.isEmpty {
            let font = configuration.textProperties.font
            let title = NSMutableAttributedString(
                string: row.title,
                attributes: [.font: font, .foregroundColor: UIColor.label],
            )
            title.append(NSAttributedString(
                string: " " + suffix, attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel],
            ))
            configuration.attributedText = title
        }
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
        case .expandable(let count, _):
            let font = configuration.textProperties.font
            let title = NSMutableAttributedString(
                string: row.title,
                attributes: [.font: font, .foregroundColor: row.isEnabled ? UIColor.label : UIColor.tertiaryLabel],
            )
            title.append(NSAttributedString(
                string: " " + count,
                attributes: [
                    .font: UIFontMetrics(forTextStyle: .subheadline)
                        .scaledFont(for: .systemFont(ofSize: 14, weight: .bold)),
                    .foregroundColor: row.isEnabled ? UIColor.label : UIColor.tertiaryLabel,
                ],
            ))
            configuration.attributedText = title
        case .option(let isSelected):
            // The check sits in the indent the head's title starts at, as SubItem's CheckNode does.
            configuration.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            configuration.imageProperties.tintColor = isSelected ? .tintColor : .tertiaryLabel
            configuration.imageProperties.maximumSize = CGSize(width: 22, height: 22)
            configuration.imageToTextPadding = 14
            configuration.directionalLayoutMargins.leading += 16
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
        if case .expandable(_, let isExpanded) = row.style {
            Self.addExpandArrow(to: cell, isExpanded: isExpanded, title: configuration)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = settingsRow(at: indexPath), row.isEnabled else { return }
        row.action?()
    }

    /// Sets play their thumbnails while on screen, as ItemListStickerPackItem does with `playAnimatedStickers`.
    override func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? SettingsStickerSetCell)?.setPlaybackVisible(true)
        // The focused row keeps its highlight on whatever cell a reload gives it.
        if let highlightedRow, highlightedRow.until > Date(),
           settingsRow(at: indexPath)?.title.caseInsensitiveCompare(highlightedRow.title) == .orderedSame
        {
            cell.selectionStyle = .default
            cell.setHighlighted(true, animated: false)
        }
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

    /// ItemListExpandableSwitchItem's arrow 9 pt after the count, turned down while closed and up while open.
    private static func addExpandArrow(
        to cell: UITableViewCell,
        isExpanded: Bool,
        title configuration: UIListContentConfiguration,
    ) {
        let arrow = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold),
        ))
        arrow.tintColor = .label
        arrow.tag = expandArrowTag
        arrow.transform = CGAffineTransform(rotationAngle: isExpanded ? -.pi / 2 : .pi / 2)
        cell.contentView.addSubview(arrow)
        let text = configuration.attributedText ?? NSAttributedString(string: configuration.text ?? "")
        let width = ceil(text.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil,
        )
        .width)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arrow.leadingAnchor.constraint(
                equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor,
                constant: width + 9,
            ),
            arrow.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
        ])
    }

    /// Puts the cursor in the input row at `indexPath`, as ItemListController's `focusItemTag` does.
    func focusInput(at indexPath: IndexPath) {
        tableView.layoutIfNeeded()
        (tableView.cellForRow(at: indexPath) as? SettingsInputCell)?.focus()
    }

    /// The screen's rows for its current state.
    func makeSections() -> [SettingsSection] {
        []
    }

    func reload() {
        sections = makeSections()
        guard isViewLoaded else { return }
        tableView.reloadData()
        focusRowIfNeeded()
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

    /// Rebuilds the rows and redraws the visible ones in place, as a group's count and checks follow one of its
    /// switches; switches keep their animation and a field keeps its keyboard. A change in the rows' count reloads.
    func refreshRowsInPlace() {
        let previousCounts = sections.map(\.rows.count)
        sections = makeSections()
        guard isViewLoaded else { return }
        guard previousCounts == sections.map(\.rows.count) else {
            tableView.reloadData()
            return
        }
        let visible = (tableView.indexPathsForVisibleRows ?? []).filter { indexPath in
            if case .input = settingsRow(at: indexPath)?.style { return false }
            return true
        }
        isRefreshingInPlace = true
        tableView.reconfigureRows(at: visible)
        isRefreshingInPlace = false
    }

    /// Rebuilds the rows and animates the section holding a row with this title, for an expandable group opening or
    /// closing.
    func reloadAnimating(sectionWithRowTitled title: String) {
        let previousCounts = sections.map(\.rows.count)
        sections = makeSections()
        guard isViewLoaded else { return }
        guard sections.count == previousCounts.count, let indexPath = indexPath(titled: title) else {
            tableView.reloadData()
            return
        }
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .fade)
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
        cancel: (() -> Void)? = nil,
        perform: @escaping () -> Void,
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { _ in cancel?() })
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

    /// ItemListDisclosureItem's displayHighlight: the highlight for 1.2 s, then a 0.3 s fade. A list that loads its
    /// rows later focuses once the row is there.
    private func focusRowIfNeeded() {
        guard let title = focusedRowTitle, viewIfLoaded?.window != nil, let indexPath = indexPath(titled: title)
        else { return }
        focusedRowTitle = nil
        tableView.layoutIfNeeded()
        // Rows under the bars or the tab bar count as hidden.
        let visible = tableView.bounds.inset(by: tableView.adjustedContentInset)
        if !visible.contains(tableView.rectForRow(at: indexPath)) {
            tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
            tableView.layoutIfNeeded()
        }
        highlightedRow = (title, Date().addingTimeInterval(1.2))
        showHighlight()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let highlightedRow, highlightedRow.title == title else { return }
            self.highlightedRow = nil
            guard let current = self.indexPath(titled: title), let cell = tableView.cellForRow(at: current)
            else { return }
            UIView.animate(withDuration: 0.3) {
                cell.setHighlighted(false, animated: false)
            } completion: { [weak self] _ in
                guard let self, let row = settingsRow(at: current) else { return }
                apply(row, to: cell)
            }
        }
    }

    /// The focused row's highlight, again on the cell a reload put in its place. A row that doesn't select, such as a
    /// switch, shows it too.
    private func showHighlight() {
        guard let highlightedRow, highlightedRow.until > Date(),
              let indexPath = indexPath(titled: highlightedRow.title),
              let cell = tableView.cellForRow(at: indexPath) else { return }
        cell.selectionStyle = .default
        cell.setHighlighted(true, animated: false)
    }

    private func indexPath(titled title: String) -> IndexPath? {
        for (sectionIndex, section) in sections.enumerated() {
            if let row = section.rows.firstIndex(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                return IndexPath(row: row, section: sectionIndex)
            }
        }
        return nil
    }

    private func apply(_ row: SettingsRow, to cell: UITableViewCell) {
        cell.contentView.viewWithTag(Self.expandArrowTag)?.removeFromSuperview()
        // A row redrawn in place keeps its switch, so a flip in progress finishes its animation.
        let currentSwitch = cell.accessoryView as? SettingsSwitch
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
            let toggle = currentSwitch ?? SettingsSwitch()
            if toggle.isOn != isOn { toggle.setOn(isOn, animated: isRefreshingInPlace) }
            toggle.isEnabled = row.isEnabled
            toggle.onChange = onChange
            cell.accessoryView = toggle
            // An expandable head opens from its title while the switch takes the whole group.
            if case .expandable = row.style, row.action != nil {
                cell.selectionStyle = .default
            } else {
                cell.selectionStyle = .none
            }
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
        detailLabel.numberOfLines = 0
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
        textField.isSecureTextEntry = input.isSecure
        textField.textContentType = input.textContentType
        textField.returnKeyType = input.returnKeyType
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

    func focus() {
        if input?.isMultiline == true {
            textView.becomeFirstResponder()
        } else {
            textField.becomeFirstResponder()
        }
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        guard let onReturn = input?.onReturn else { return true }
        onReturn()
        return false
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

// MARK: - SettingsMarkdownFooterView

/// ItemListTextItem with `.markdown` text under a section: the footnote in the secondary colour, its `[text](id)`
/// parts in the accent colour, each running its link action.
final class SettingsMarkdownFooterView: UITableViewHeaderFooterView, UITextViewDelegate {
    static let reuseIdentifier = "SettingsMarkdownFooterView"

    private static let scheme = "bettertg-footer"

    private let textView = UITextView()
    private var links = [String: () -> Void]()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            textView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The footnote with each `[text](id)` turned into a link to `bettertg-footer://id`; an empty id is `default`.
    static func attributedText(_ markdown: String) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let result = NSMutableAttributedString()
        var rest = Substring(markdown)
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.secondaryLabel]
        while let match = rest.firstMatch(of: /\[([^\]]*)\]\(([^)]*)\)/) {
            result.append(NSAttributedString(
                string: String(rest[rest.startIndex..<match.range.lowerBound]),
                attributes: plain,
            ))
            let id = match.output.2.isEmpty ? "default" : String(match.output.2)
            var attributes = plain
            attributes[.link] = URL(string: "\(scheme)://\(id)")
            result.append(NSAttributedString(string: String(match.output.1), attributes: attributes))
            rest = rest[match.range.upperBound...]
        }
        result.append(NSAttributedString(string: String(rest), attributes: plain))
        return result
    }

    func configure(markdown: String, links: [String: () -> Void]) {
        self.links = links
        textView.attributedText = Self.attributedText(markdown)
    }

    func textView(
        _: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction _: UIAction,
    ) -> UIAction? {
        guard case .link(let url) = textItem.content, url.scheme == Self.scheme else { return nil }
        let id = url.host() ?? ""
        return UIAction { [weak self] _ in self?.links[id]?() }
    }

    func textView(_: UITextView, menuConfigurationFor _: UITextItem, defaultMenu _: UIMenu) -> UITextItem
        .MenuConfiguration?
    {
        nil
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

    /// Telegram's dataSizeString.
    static func byteCount(_ bytes: Int64) -> String {
        DataSize.string(bytes)
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
