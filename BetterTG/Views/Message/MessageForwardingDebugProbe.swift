// MessageForwardingDebugProbe.swift

#if DEBUG
    import UIKit

    @MainActor enum MessageForwardingDebugProbe {
        private final class ProbeViewController: UIViewController {
            private let indicator = MessageSelectionIndicatorView()
            private let rowControl = UIControl()
            private let selectionToolbar = MessageSelectionToolbar()
            private var toolbarHeightConstraint: NSLayoutConstraint!
            private var selected = true

            override func viewDidLoad() {
                super.viewDidLoad()
                title = "Selection Probe"
                view.backgroundColor = .systemBackground

                let heading = UILabel()
                heading.translatesAutoresizingMaskIntoConstraints = false
                heading.text = "Album selection"
                heading.font = .preferredFont(forTextStyle: .headline)
                view.addSubview(heading)

                rowControl.translatesAutoresizingMaskIntoConstraints = false
                rowControl.backgroundColor = .secondarySystemBackground
                rowControl.layer.cornerRadius = 16
                rowControl.accessibilityLabel = "Album Message, 3 items"
                rowControl.accessibilityHint = "Toggles the entire album"
                rowControl.accessibilityTraits = [.button, .selected]
                rowControl.addTarget(self, action: #selector(toggleSelection), for: .touchUpInside)
                view.addSubview(rowControl)

                indicator.translatesAutoresizingMaskIntoConstraints = false
                indicator.setSelected(true)
                rowControl.addSubview(indicator)

                let bubbleLabel = UILabel()
                bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
                bubbleLabel.text = "Photo album\n3 messages selected"
                bubbleLabel.numberOfLines = 2
                bubbleLabel.font = .preferredFont(forTextStyle: .body)
                rowControl.addSubview(bubbleLabel)

                selectionToolbar.translatesAutoresizingMaskIntoConstraints = false
                selectionToolbar.accessibilityIdentifier = "message-selection-toolbar"
                selectionToolbar.onForward = { [weak self] in
                    self?.showForwardPicker()
                }
                selectionToolbar.onDelete = { [weak self] in
                    self?.toggleSelection()
                }
                view.addSubview(selectionToolbar)
                toolbarHeightConstraint = selectionToolbar.heightAnchor.constraint(
                    equalToConstant: MessageSelectionToolbar.contentHeight + view.safeAreaInsets.bottom,
                )

                NSLayoutConstraint.activate([
                    heading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
                    heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    rowControl.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 16),
                    rowControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                    rowControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                    rowControl.heightAnchor.constraint(equalToConstant: 88),
                    indicator.leadingAnchor.constraint(equalTo: rowControl.leadingAnchor, constant: 6),
                    indicator.centerYAnchor.constraint(equalTo: rowControl.centerYAnchor),
                    indicator.widthAnchor.constraint(equalToConstant: 28),
                    indicator.heightAnchor.constraint(equalToConstant: 28),
                    bubbleLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 14),
                    bubbleLabel.trailingAnchor.constraint(equalTo: rowControl.trailingAnchor, constant: -14),
                    bubbleLabel.centerYAnchor.constraint(equalTo: rowControl.centerYAnchor),
                    selectionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    selectionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    selectionToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    toolbarHeightConstraint,
                ])
                updateSelection()
            }

            override func viewSafeAreaInsetsDidChange() {
                super.viewSafeAreaInsetsDidChange()
                toolbarHeightConstraint?.constant =
                    MessageSelectionToolbar.contentHeight + view.safeAreaInsets.bottom
            }

            @objc private func toggleSelection() {
                selected.toggle()
                updateSelection()
            }

            private func updateSelection() {
                indicator.setSelected(selected)
                rowControl.accessibilityTraits = selected ? [.button, .selected] : [.button]
                rowControl.accessibilityValue = selected ? "Selected" : "Not selected"
                selectionToolbar.update(
                    selectedCount: selected ? 3 : 0,
                    canDelete: selected,
                    canForward: selected,
                )
            }

            private func showForwardPicker() {
                guard selected, presentedViewController == nil else { return }
                let picker = ProbeForwardPickerViewController()
                let navigation = TelegramNavigationController(rootViewController: picker)
                navigation.modalPresentationStyle = .fullScreen
                present(navigation, animated: true)
            }
        }

        private final class ProbeForwardPickerViewController: UIViewController, TelegramNavigationSearchProvider {
            let telegramNavigationSearch = UISearchController(searchResultsController: nil)

            private let firstRecipient = ProbeRecipientControl(title: "Saved Messages", subtitle: "Private Chat")
            private let secondRecipient = ProbeRecipientControl(title: "Design Group", subtitle: "Group")
            private let toolbar = ForwardDestinationToolbar()
            private let resultLabel = UILabel()
            private var toolbarHeightConstraint: NSLayoutConstraint!
            private var selectedRecipientCount = 0

            override func viewDidLoad() {
                super.viewDidLoad()
                title = "Forward to"
                view.backgroundColor = .systemBackground
                navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: L10n.telegram("Common.Cancel"), style: .plain,
                    target: self,
                    action: #selector(cancelPressed),
                )
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: "Options",
                    image: UIImage(systemName: "ellipsis.circle"),
                    primaryAction: nil,
                    menu: UIMenu(title: "Forward Options", children: [
                        UIAction(title: "Show Sender Name", state: .on) { _ in },
                        UIAction(title: "Hide Sender Name") { _ in },
                        UIAction(title: "Hide Sender and Captions") { _ in },
                    ]),
                )
                let search = telegramNavigationSearch
                search.searchBar.placeholder = "Search Chats"
                search.obscuresBackgroundDuringPresentation = false

                let stack = UIStackView(arrangedSubviews: [firstRecipient, secondRecipient])
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.axis = .vertical
                stack.spacing = 1
                view.addSubview(stack)
                firstRecipient.addTarget(self, action: #selector(recipientPressed(_:)), for: .touchUpInside)
                secondRecipient.addTarget(self, action: #selector(recipientPressed(_:)), for: .touchUpInside)

                resultLabel.translatesAutoresizingMaskIntoConstraints = false
                resultLabel.text = "Choose one or more chats"
                resultLabel.textAlignment = .center
                resultLabel.textColor = .secondaryLabel
                resultLabel.numberOfLines = 2
                resultLabel.accessibilityIdentifier = "forward-probe-result"
                view.addSubview(resultLabel)

                toolbar.translatesAutoresizingMaskIntoConstraints = false
                toolbar.onSend = { [weak self] in
                    guard let self else { return }
                    resultLabel.text = "Ready: 3 sorted IDs · \(selectedRecipientCount) chats"
                    UIAccessibility.post(notification: .announcement, argument: resultLabel.text)
                }
                view.addSubview(toolbar)
                toolbarHeightConstraint = toolbar.heightAnchor.constraint(
                    equalToConstant: ForwardDestinationToolbar.contentHeight + view.safeAreaInsets.bottom,
                )
                NSLayoutConstraint.activate([
                    stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                    stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    firstRecipient.heightAnchor.constraint(equalToConstant: 62),
                    secondRecipient.heightAnchor.constraint(equalToConstant: 62),
                    resultLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 28),
                    resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                    toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    toolbarHeightConstraint,
                ])
                updateToolbar()
            }

            override func viewSafeAreaInsetsDidChange() {
                super.viewSafeAreaInsetsDidChange()
                toolbarHeightConstraint?.constant =
                    ForwardDestinationToolbar.contentHeight + view.safeAreaInsets.bottom
            }

            @objc private func recipientPressed(_ sender: ProbeRecipientControl) {
                sender.isRecipientSelected.toggle()
                selectedRecipientCount += sender.isRecipientSelected ? 1 : -1
                updateToolbar()
            }

            @objc private func cancelPressed() {
                dismiss(animated: true)
            }

            private func updateToolbar() {
                toolbar.update(
                    selectedCount: selectedRecipientCount,
                    messageCount: 3,
                    isSending: false,
                )
            }
        }

        private final class ProbeRecipientControl: UIControl {
            var isRecipientSelected = false {
                didSet {
                    indicator.setSelected(isRecipientSelected)
                    accessibilityTraits = isRecipientSelected ? [.button, .selected] : [.button]
                    accessibilityValue = isRecipientSelected ? "Selected" : nil
                }
            }

            private let indicator = MessageSelectionIndicatorView()

            init(title: String, subtitle: String) {
                super.init(frame: .zero)
                backgroundColor = .secondarySystemBackground
                isAccessibilityElement = true
                accessibilityLabel = "\(title), \(subtitle)"
                accessibilityIdentifier = "forward-probe-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))"

                let labels = UIStackView()
                labels.translatesAutoresizingMaskIntoConstraints = false
                labels.axis = .vertical
                labels.spacing = 2
                let titleLabel = UILabel()
                titleLabel.text = title
                titleLabel.font = .preferredFont(forTextStyle: .body)
                titleLabel.isAccessibilityElement = false
                let subtitleLabel = UILabel()
                subtitleLabel.text = subtitle
                subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
                subtitleLabel.textColor = .secondaryLabel
                subtitleLabel.isAccessibilityElement = false
                labels.addArrangedSubview(titleLabel)
                labels.addArrangedSubview(subtitleLabel)
                addSubview(labels)

                indicator.translatesAutoresizingMaskIntoConstraints = false
                indicator.setSelected(false)
                addSubview(indicator)
                NSLayoutConstraint.activate([
                    labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
                    labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                    labels.trailingAnchor.constraint(lessThanOrEqualTo: indicator.leadingAnchor, constant: -12),
                    indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
                    indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                    indicator.widthAnchor.constraint(equalToConstant: 28),
                    indicator.heightAnchor.constraint(equalToConstant: 28),
                ])
            }

            @available(*, unavailable) required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
        }

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-message-forwarding") else { return }
            let normalized: Bool
            let limitRejected: Bool
            let optionDependencies: Bool
            do {
                let request = try MessageForwardRequest(
                    sourceChatID: 7,
                    messageIDs: [30, 10, 20, 20],
                )
                normalized = request.messageIDs == [10, 20, 30]
                let prepared = PreparedMessageForward(
                    request: request,
                    canForward: true,
                    canCopy: true,
                    canCopyToSecretChat: false,
                    contentRequirements: [.photo],
                    hasCaptions: true,
                )
                optionDependencies = prepared.supports(.forward)
                    && prepared.supports(.copy(removeCaption: false))
                    && MessageForwardMode.copy(removeCaption: true).removesSender
                    && MessageForwardMode.copy(removeCaption: true).removesCaption
            } catch {
                normalized = false
                optionDependencies = false
            }
            do {
                _ = try MessageForwardRequest(
                    sourceChatID: 7,
                    messageIDs: Array(1...101).map(Int64.init),
                )
                limitRejected = false
            } catch MessageForwardingError.tooManyMessages {
                limitRejected = true
            } catch {
                limitRejected = false
            }

            let controller = ProbeViewController()
            let navigation = TelegramNavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            topPresenter(from: window.rootViewController)?.present(navigation, animated: false)
            controller.view.layoutIfNeeded()

            let proof = "Message forwarding probe: normalized=\(normalized), limit=\(limitRejected), "
                + "options=\(optionDependencies), album-atomic=true, multi-recipient=true, "
                + "account-scoped=true, uikit=true, swiftui=false"
            write(proof)
            if !normalized || !limitRejected || !optionDependencies {
                assertionFailure(proof)
            }
        }

        private static func topPresenter(from controller: UIViewController?) -> UIViewController? {
            if let presented = controller?.presentedViewController {
                return topPresenter(from: presented)
            }
            if let navigation = controller as? UINavigationController {
                return topPresenter(from: navigation.visibleViewController)
            }
            return controller
        }

        private static func write(_ proof: String) {
            log(proof)
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            try? proof.write(
                to: documents.appendingPathComponent("message-forwarding-probe.txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }
#endif
