// ChatInviteLinkPreviewProbe.swift

#if DEBUG
import TDLibKit
import UIKit

/// Local invite metadata with no photo or member IDs. Join is replaced before presentation.
@MainActor enum ChatInviteLinkPreviewProbe {
    private final class Controller: UIViewController {
        private var openedInitial = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemGroupedBackground
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 20
            stack.translatesAutoresizingMaskIntoConstraints = false
            for title in ["Group", "Request", "Long description", "Appearance"] {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    if title == "Appearance" {
                        overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .light : .dark
                    } else { show(title) }
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
                stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ])
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !openedInitial else { return }
            openedInitial = true
            show("Group")
        }

        private func show(_ mode: String) {
            let request = mode == "Request"
            let info = TDNativeChatInviteLinkInfo(
                chatId: -12345,
                accessibleFor: 0,
                type: request ? .inviteLinkChatTypeChannel : .inviteLinkChatTypeSupergroup,
                title: request ? "Parity approval channel" : "Parity preview group",
                photo: nil,
                accentColorId: 5,
                description: mode == "Long description"
                    ? Array(repeating: "Long local description for scroll and close-button verification.", count: 30)
                        .joined(separator: "\n")
                    : "Local preview. The join button only shows its busy state for three seconds.",
                memberCount: 42,
                memberUserIds: [],
                subscriptionInfo: nil,
                createsJoinRequest: request,
                isPublic: false,
                verificationStatus: nil,
            )
            let preview = ChatInviteLinkPreviewViewController(inviteLink: "tg://isolated", info: info)
            preview.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
            preview.useLocalJoinForProbe()
            present(preview, animated: true)
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-invite-preview") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let controller = Controller()
            controller.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(controller, animated: false)
        }
    }
}
#endif
