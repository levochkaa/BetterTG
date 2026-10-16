// ChecklistTaskMenuProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    /// Launch with `-ui-probe-checklist-menu`. Once an account is active it shows a checklist bubble built from a
    /// fixture; a long press on a task opens Telegram's task menu with its Task and List tabs, and a long press
    /// elsewhere opens the List actions alone. Every action only records itself in the log above the bubble, so
    /// nothing is sent or edited.
    @MainActor enum ChecklistTaskMenuProbe {
        private final class ProbeViewController: UIViewController {
            private let bubble = UIView()
            private let contentView = MessageStructuredContentView()
            private let logLabel = UILabel()
            private let interactionStore = MessagePollInteractionStore()
            private let checklist: Checklist
            private var log = [String]()

            init(checklist: Checklist) {
                self.checklist = checklist
                super.init(nibName: nil, bundle: nil)
                modalPresentationStyle = .fullScreen
            }

            @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .systemBackground
                logLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                logLabel.numberOfLines = 0
                logLabel.text = "checklist menu probe"
                logLabel.accessibilityIdentifier = "checklist-menu-log"
                bubble.backgroundColor = .secondarySystemBackground
                bubble.layer.cornerRadius = 18
                bubble.layer.cornerCurve = .continuous
                let close = UIButton(type: .system, primaryAction: UIAction(title: "Close") { [weak self] _ in
                    self?.dismiss(animated: true)
                })
                for subview in [close, logLabel, bubble] as [UIView] {
                    subview.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(subview)
                }
                contentView.translatesAutoresizingMaskIntoConstraints = false
                bubble.addSubview(contentView)
                contentView.configure(
                    presentation: MessageContentPresentation.make(.messageChecklist(MessageChecklist(list: checklist))),
                    messageID: 4242,
                    album: [],
                    client: TDLib.shared.activeClient,
                    pollInteractionStore: interactionStore,
                ) { [weak self] action in
                    if case .toggleChecklistTask(let toggle) = action {
                        self?.record("tap-toggle \(toggle.taskID) done=\(toggle.isDone)")
                    }
                }
                let guide = view.safeAreaLayoutGuide
                NSLayoutConstraint.activate([
                    close.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
                    close.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    logLabel.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 8),
                    logLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    logLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
                    bubble.topAnchor.constraint(equalTo: logLabel.bottomAnchor, constant: 24),
                    bubble.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
                    bubble.widthAnchor.constraint(equalToConstant: 300),
                    contentView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
                    contentView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
                    contentView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
                    contentView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
                ])
                let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
                bubble.addGestureRecognizer(press)
            }

            @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
                guard gesture.state == .began else { return }
                let taskID = contentView.checklistTaskID(at: gesture.location(in: bubble), in: bubble)
                record("menu task=\(taskID.map(String.init) ?? "none")")
                let listActions = [
                    action("Reply", "arrowshape.turn.up.left"),
                    action("Add a Task", "plus.circle"),
                    action("Copy", "rectangle.portrait.on.rectangle.portrait"),
                ]
                let sources = taskID.flatMap { menu(taskID: $0) }?.sources(messageActions: listActions) ?? []
                presentTelegramContextMenu(
                    sourceView: bubble,
                    actions: listActions,
                    tracking: gesture,
                    sources: sources,
                )
            }

            private func menu(taskID: Int) -> ChecklistTaskMenu? {
                guard let task = checklist.tasks.first(where: { $0.id == taskID }) else { return nil }
                return ChecklistTaskMenu(
                    task: task,
                    isDone: interactionStore.checklistTaskIsDone(
                        messageID: 4242,
                        taskID: taskID,
                        sourceIsDone: task.completedBy != nil,
                    ),
                    taskCount: checklist.tasks.count,
                    permissions: .init(canMark: true, canReply: true, canCopy: true, canCopyLink: true, canEdit: true),
                    handlers: .init(
                        toggle: { [weak self] in self?.record("toggle \(taskID)") },
                        reply: { [weak self] in self?.record("reply \(taskID)") },
                        copy: { [weak self] in self?.record("copy \(taskID)") },
                        copyLink: { [weak self] in self?.record("copy-link \(taskID)") },
                        edit: { [weak self] in self?.record("edit \(taskID)") },
                        delete: { [weak self] in self?.record("delete \(taskID)") },
                    ),
                )
            }

            private func action(_ title: String, _ symbol: String) -> TelegramContextMenuAction {
                TelegramContextMenuAction(title: title, image: UIImage(systemName: symbol)) { [weak self] in
                    self?.record("list \(title)")
                }
            }

            private func record(_ event: String) {
                log.append(event)
                logLabel.text = log.suffix(6).joined(separator: "\n")
                NSLog("ChecklistTaskMenuProbe: %@", event)
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-checklist-menu") else { return }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard TDLib.shared.activeAccountID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                presenter?.present(ProbeViewController(checklist: makeChecklist()), animated: true)
            }
        }

        /// A group checklist the account may mark: the first task was completed an hour ago.
        private static func makeChecklist() -> Checklist {
            func task(_ id: Int, _ text: String, done: Bool) -> ChecklistTask {
                ChecklistTask(
                    completedBy: done ? .messageSenderUser(MessageSenderUser(userId: 777_000)) : nil,
                    completionDate: done ? Int(Date().timeIntervalSince1970) - 3600 : 0,
                    id: id,
                    text: FormattedText(entities: [], text: text),
                )
            }
            return Checklist(
                canAddTasks: true,
                canMarkTasksAsDone: true,
                othersCanAddTasks: true,
                othersCanMarkTasksAsDone: true,
                tasks: [
                    task(1, "Port the task menu", done: true),
                    task(2, "Show Task and List tabs", done: false),
                    task(3, "Reply to one task", done: false),
                ],
                title: FormattedText(entities: [], text: "Parity checklist"),
            )
        }
    }
#endif
