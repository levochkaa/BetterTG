// ChecklistMessageContentView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChecklistMessageContentView

/// Telegram's checklist bubble (ChatMessageTodoBubbleContentNode): the bold title, the checklist's kind, one row per
/// task and the completed count. Where the account may mark tasks, each row has a check circle and a tap toggles the
/// task at once; elsewhere a row shows a dot or a check, and a done task is struck through. A group checklist names
/// who completed each task.
final class ChecklistMessageContentView: UIView, MessageSupplementView {
    private let titleLabel = UILabel()
    private let typeLabel = UILabel()
    private let tasksStack = UIStackView()
    private let footerLabel = UILabel()
    private let messageID: Int64
    private let content: MessageContentPresentation.ChecklistContent
    private let client: TDLibClient
    private let interactionStore: MessagePollInteractionStore
    private let onAction: (MessageContentAction) -> Void
    private var rows = [ChecklistTaskRowView]()
    private var storeCancellable: AnyCancellable?
    private var authorName: String?
    private var completerNames = [Int: String]()
    private var isActive = true

    private var checklist: Checklist {
        content.checklist
    }

    /// ChatMessageTodoItemNode.canMark, which TDLib reports as `canMarkTasksAsDone` (Telegram Premium aside).
    private var showsCheckCircles: Bool {
        checklist.canMarkTasksAsDone
    }

    /// Telegram's `othersCanComplete`: a group checklist names who completed each task.
    private var isGroup: Bool {
        checklist.othersCanMarkTasksAsDone
    }

    /// The author when it isn't the account; a checklist built from content alone has none.
    private var foreignAuthor: MessageSender? {
        content.isOutgoing ? nil : content.author
    }

    private var typeText: String {
        if isGroup { return L10n.telegram("Chat.Todo.Message.TitleGroup") }
        if foreignAuthor != nil, let authorName {
            return L10n.telegram("Chat.Todo.Message.TitlePersonal", authorName)
        }
        return L10n.telegram("Chat.Todo.Message.Title")
    }

    init(
        messageID: Int64,
        content: MessageContentPresentation.ChecklistContent,
        client: TDLibClient,
        interactionStore: MessagePollInteractionStore,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.messageID = messageID
        self.content = content
        self.client = client
        self.interactionStore = interactionStore
        self.onAction = onAction
        super.init(frame: .zero)
        configureViews()
        resolveNames()
        self.storeCancellable = interactionStore.changes
            .filter { $0 == messageID }
            .sink { [weak self] _ in self?.render() }
        render()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        isActive = false
        storeCancellable?.cancel()
        storeCancellable = nil
        rows.forEach { $0.prepareForReuse() }
    }

    #if DEBUG
        func debugTapTask(_ index: Int) {
            taskTapped(index)
        }
    #endif

    private func configureViews() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.attributedText = NSAttributedString(getAttributedString(from: checklist.title))
        titleLabel.font = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .semibold,
        )
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        addSubview(titleLabel)

        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.font = .preferredFont(forTextStyle: .footnote)
        typeLabel.textColor = .secondaryLabel
        typeLabel.adjustsFontForContentSizeCategory = true
        addSubview(typeLabel)

        tasksStack.translatesAutoresizingMaskIntoConstraints = false
        tasksStack.axis = .vertical
        addSubview(tasksStack)
        for (index, task) in checklist.tasks.enumerated() {
            let row = ChecklistTaskRowView(text: task.text, showsCheckCircle: showsCheckCircles)
            row.onTap = { [weak self] in self?.taskTapped(index) }
            rows.append(row)
            tasksStack.addArrangedSubview(row)
        }

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .preferredFont(forTextStyle: .footnote)
        footerLabel.textColor = .secondaryLabel
        footerLabel.textAlignment = .center
        footerLabel.adjustsFontForContentSizeCategory = true
        addSubview(footerLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            typeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            typeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            typeLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleLabel.trailingAnchor),
            tasksStack.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 6),
            tasksStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            tasksStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerLabel.topAnchor.constraint(equalTo: tasksStack.bottomAnchor, constant: 8),
            footerLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
    }

    /// The author's compact name titles a personal checklist and its count; a group checklist names its completers
    /// in full.
    private func resolveNames() {
        if let author = foreignAuthor {
            authorName = MessagePeerNames.name(of: author, compact: true, client: client) { [weak self] name in
                guard let self, isActive else { return }
                authorName = name
                render()
            }
        }
        guard isGroup else { return }
        for task in checklist.tasks {
            guard let completer = task.completedBy else { continue }
            let taskID = task.id
            completerNames[taskID] = MessagePeerNames.name(of: completer, compact: false, client: client) {
                [weak self] name in
                guard let self, isActive else { return }
                completerNames[taskID] = name
                render()
            }
        }
    }

    private func render() {
        var completedCount = 0
        for (task, row) in zip(checklist.tasks, rows) {
            let sourceIsDone = task.completedBy != nil
            let isDone = interactionStore.checklistTaskIsDone(
                messageID: messageID,
                taskID: task.id,
                sourceIsDone: sourceIsDone,
            )
            if isDone { completedCount += 1 }
            // A pending check has no completer yet; Telegram's row keeps its height either way.
            let showsCompleter = isGroup && isDone && sourceIsDone
            row.render(
                isDone: isDone,
                isStruckThrough: !showsCheckCircles && isDone,
                completerName: showsCompleter ? (completerNames[task.id] ?? "") : nil,
                completerUser: showsCompleter && showsCheckCircles ? completerUser(task.completedBy) : nil,
                client: client,
            )
        }
        typeLabel.text = typeText
        footerLabel.text = footerText(completedCount: completedCount)
    }

    /// "N of M completed", naming the author of a personal checklist the account can't complete.
    private func footerText(completedCount: Int) -> String {
        let total = String(checklist.tasks.count)
        if !isGroup, foreignAuthor != nil, let authorName {
            return L10n.telegramPlural("Chat.Todo.Message.CompletedBy", count: completedCount)
                .replacingOccurrences(of: "{count}", with: total)
                .replacingOccurrences(of: "{name}", with: authorName)
        }
        return L10n.telegramPlural("Chat.Todo.Message.Completed", count: completedCount)
            .replacingOccurrences(of: "{count}", with: total)
    }

    private func completerUser(_ sender: MessageSender?) -> User? {
        guard case .messageSenderUser(let value) = sender else { return nil }
        return ChatListSenderNames.shared.user(userID: value.userId, client: client)
    }

    /// ChatMessageTodoItemNode.buttonPressed toggles a task where the account may mark it and the message is
    /// published; the chat checks Telegram Premium before it sends. Any other tap explains why the task can't change.
    private func taskTapped(_ index: Int) {
        guard checklist.tasks.indices.contains(index) else { return }
        guard showsCheckCircles, !content.isScheduled else {
            onAction(.checklistToggleUnavailable(messageID: messageID))
            return
        }
        let task = checklist.tasks[index]
        guard let toggle = interactionStore.beginChecklistToggle(
            messageID: messageID,
            taskID: task.id,
            sourceIsDone: task.completedBy != nil,
        ) else { return }
        // ChatController.requestToggleTodoMessageItem: success feedback for a check, a medium impact otherwise.
        if toggle.isDone {
            UINotificationFeedbackGenerator(view: self).notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .medium, view: self).impactOccurred()
        }
        onAction(.toggleChecklistTask(toggle))
    }
}

// MARK: - ChecklistTaskRowView

/// Telegram's ChatMessageTodoItemNode, with its insets measured from the bubble's content edge: the check circle, or
/// a dot or check for a read-only checklist, the task text, the completer's avatar and name, and a separator.
private final class ChecklistTaskRowView: UIControl {
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.06) : .clear }
    }

    var onTap: (() -> Void)?

    private let checkBackgroundView = UIView()
    private let checkView = UIImageView()
    private let markerView = UIImageView()
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let nameLabel = UILabel()
    private let separatorView = UIView()
    private let text: FormattedText
    private let showsCheckCircle: Bool
    private var titleTop: NSLayoutConstraint!
    private var titleBottom: NSLayoutConstraint!
    private var separatorHeight: NSLayoutConstraint!
    private var representedAvatarUserID: Int64?

    init(text: FormattedText, showsCheckCircle: Bool) {
        self.text = text
        self.showsCheckCircle = showsCheckCircle
        super.init(frame: .zero)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        avatarView.isHidden = true
        addSubview(avatarView)

        // The bubble-colored disc stands for Telegram's avatar cutout around the circle.
        checkBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        checkBackgroundView.backgroundColor = .secondarySystemBackground
        checkBackgroundView.layer.cornerRadius = 12
        checkBackgroundView.isUserInteractionEnabled = false
        checkBackgroundView.isHidden = !showsCheckCircle
        addSubview(checkBackgroundView)

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.contentMode = .scaleAspectFit
        checkBackgroundView.addSubview(checkView)

        markerView.translatesAutoresizingMaskIntoConstraints = false
        markerView.contentMode = .scaleAspectFit
        markerView.isHidden = showsCheckCircle
        addSubview(markerView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 0
        addSubview(titleLabel)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabel
        nameLabel.isHidden = true
        addSubview(nameLabel)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator
        separatorView.isUserInteractionEnabled = false
        addSubview(separatorView)

        let textLeading: CGFloat = showsCheckCircle ? 49 : 21
        self.titleTop = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        self.titleBottom = bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10)
        titleBottom.priority = UILayoutPriority(999)
        self.separatorHeight = separatorView.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            checkBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            checkBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            checkBackgroundView.widthAnchor.constraint(equalToConstant: 24),
            checkBackgroundView.heightAnchor.constraint(equalToConstant: 24),
            checkView.centerXAnchor.constraint(equalTo: checkBackgroundView.centerXAnchor),
            checkView.centerYAnchor.constraint(equalTo: checkBackgroundView.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            avatarView.widthAnchor.constraint(equalToConstant: 22),
            avatarView.heightAnchor.constraint(equalToConstant: 22),
            markerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            markerView.topAnchor.constraint(equalTo: topAnchor, constant: 19),
            markerView.widthAnchor.constraint(equalToConstant: 10),
            markerView.heightAnchor.constraint(equalToConstant: 10),
            titleTop,
            titleBottom,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: -1),
            nameLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            separatorView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorHeight,
            heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        separatorHeight.constant = 1 / max(1, traitCollection.displayScale)
    }

    func prepareForReuse() {
        onTap = nil
        avatarView.prepareForReuse()
        representedAvatarUserID = nil
    }

    /// A completer's line lifts the text by 6 points into the same row height, as in Telegram.
    func render(
        isDone: Bool,
        isStruckThrough: Bool,
        completerName: String?,
        completerUser: User?,
        client: TDLibClient,
    ) {
        let attributed = NSMutableAttributedString(getAttributedString(from: text))
        if isStruckThrough {
            attributed.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: NSRange(location: 0, length: attributed.length),
            )
        }
        titleLabel.attributedText = attributed

        if showsCheckCircle {
            checkView.image = UIImage(systemName: isDone ? "checkmark.circle.fill" : "circle")
            checkView.tintColor = isDone ? .systemBlue : .tertiaryLabel
        } else {
            let configuration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            markerView.image = isDone
                ? UIImage(systemName: "checkmark", withConfiguration: configuration)
                : UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 5))
            markerView.tintColor = isDone ? .systemBlue : .secondaryLabel
        }

        let showsName = completerName != nil
        nameLabel.isHidden = !showsName
        // A blank name keeps the line until TDLib returns it.
        nameLabel.text = completerName.map { $0.isEmpty ? " " : $0 }
        titleTop.constant = showsName ? 6 : 12
        titleBottom.constant = showsName ? 16 : 10

        if let completerUser {
            avatarView.isHidden = false
            if representedAvatarUserID != completerUser.id {
                representedAvatarUserID = completerUser.id
                avatarView.configure(
                    file: completerUser.profilePhoto?.small,
                    minithumbnail: completerUser.profilePhoto?.minithumbnail,
                    placeholder: completerUser.telegramAvatarPlaceholder,
                    client: client,
                )
            }
        } else {
            avatarView.isHidden = true
        }

        var accessibilityParts = [text.text]
        if let completerName, !completerName.isEmpty { accessibilityParts.append(completerName) }
        accessibilityLabel = accessibilityParts.joined(separator: ", ")
        accessibilityTraits = showsCheckCircle
            ? (isDone ? [.button, .selected] : [.button])
            : (isDone ? [.staticText, .selected] : [.staticText])
    }

    @objc private func tapped() {
        onTap?()
    }
}
