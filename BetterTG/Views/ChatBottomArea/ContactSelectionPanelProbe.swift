// ContactSelectionPanelProbe.swift

#if DEBUG
import Contacts
import TDLibKit
import UIKit

/// The real picker with local contacts and an intercepted send callback. No phonebook reads or message sends.
@MainActor enum ContactSelectionPanelProbe {
    private final class Host: UIViewController {
        private let status = UILabel()
        private var opened = false
        private var sends = 0
        private var dismissals = 0
        private var sentNames = [String]()
        private var layoutRecords = [String]()
        private var destination = 0
        private var sentOptions = "none"
        private var sentVCards = 0

        private var sendCapabilities: AttachmentSendCapabilities {
            AttachmentSendCapabilities(
                isReminders: destination == 1,
                canSchedule: destination != 2,
                canSendWhenOnline: destination == 0,
            )
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            title = "Contact panel fixture"
            view.backgroundColor = .systemGroupedBackground
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 18
            stack.translatesAutoresizingMaskIntoConstraints = false
            for title in ["Open picker", "Appearance", "Destination"] {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    if title == "Open picker" { openPicker() }
                    else if title == "Destination" {
                        destination = (destination + 1) % 3
                        report()
                    } else {
                        overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .light : .dark
                    }
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
            status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            status.numberOfLines = 0
            status.textAlignment = .center
            stack.addArrangedSubview(status)
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
            report()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !opened else { return }
            opened = true
            openPicker()
        }

        private func openPicker() {
            let navigation = TelegramNavigationController()
            navigation.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
            navigation.modalPresentationStyle = .pageSheet
            navigation.sheetPresentationController?.detents = [.medium(), .large()]
            let gallery = makeOtherTab(.gallery, navigation: navigation)
            navigation.setViewControllers([gallery], animated: false)
            present(navigation, animated: true) {
                // The production route opens Gallery first, then replaces its content with Contact.
                navigation.replaceAttachmentSheetContent(with: self.makePicker(navigation: navigation))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.recordLayout(navigation, phase: "presented contact")
                }
            }
        }

        private func makePicker(navigation: TelegramNavigationController) -> UIViewController {
            let picker = ContactSelectionViewController(
                probeContacts: contacts, probeContactCards: contactCards, sendCapabilities: sendCapabilities,
            ) { [weak self] contents, options in
                guard let self else { return }
                sends += 1
                var timing = "now"
                switch options?.schedulingState {
                case .messageSchedulingStateSendWhenOnline: timing = "online"
                case .messageSchedulingStateSendAtDate(let value): timing = "date:\(value.sendDate)"
                case .messageSchedulingStateSendWhenVideoProcessed: timing = "videoProcessed"
                case nil: break
                }
                sentOptions = "\(timing),silent:\(options?.disableNotification ?? false),id:\(options?.sendingId ?? 0)"
                sentNames = contents.compactMap {
                    guard case .inputMessageContact(let input) = $0 else { return nil }
                    return input.contact.firstName
                }
                sentVCards = contents.count(where: {
                    guard case .inputMessageContact(let input) = $0 else { return false }
                    return !input.contact.vcard.isEmpty
                })
                report()
            }
            picker.onDismiss = { [weak self] in
                guard let self else { return }
                dismissals += 1
                report()
            }
            installPanel(in: picker, current: .contact, navigation: navigation)
            return picker
        }

        private func installPanel(
            in controller: UIViewController, current: AttachmentSheetTab, navigation: TelegramNavigationController,
        ) {
            AttachmentPanelView
                .install(
                    in: controller,
                    tabs: [.gallery, .file, .location, .poll, .checklist, .sticker, .contact],
                    current: current,
                ) {
                [weak self, weak navigation] tab in
                guard let self, let navigation else { return }
                recordLayout(navigation, phase: "before tab")
                if tab == .contact {
                    navigation.replaceAttachmentSheetContent(with: makePicker(navigation: navigation))
                } else {
                    navigation.replaceAttachmentSheetContent(with: makeOtherTab(tab, navigation: navigation))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak navigation] in
                    if let navigation { self?.recordLayout(navigation, phase: "after tab") }
                }
            }
        }

        private func makeOtherTab(
            _ tab: AttachmentSheetTab,
            navigation: TelegramNavigationController,
        ) -> UIViewController {
            let other = UIViewController()
            other.title = "Fixture tab"
            other.view.backgroundColor = .systemGroupedBackground
            other.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Close", primaryAction: UIAction { [weak navigation] _ in navigation?.dismiss(animated: true) },
            )
            installPanel(in: other, current: tab, navigation: navigation)
            return other
        }

        private func recordLayout(_ navigation: TelegramNavigationController, phase: String) {
            guard let screen = navigation.topViewController,
                  let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            let panel = screen.view.subviews.first { $0 is AttachmentPanelView }
            let text = "\(phase) view=\(screen.view.frame) safe=\(screen.view.safeAreaInsets) additional=\(screen.additionalSafeAreaInsets) nav=\(navigation.view.frame) navSafe=\(navigation.view.safeAreaInsets) panel=\(String(describing: panel?.frame))\n"
            let url = directory.appendingPathComponent("contact-selection-layout.txt")
            layoutRecords.append(text)
            try? Data(layoutRecords.joined().utf8).write(to: url, options: .atomic)
        }

        private func report() {
            let mode = ["regular", "reminders", "no-schedule"][destination]
            let result = "Contact panel fixture: sends=\(sends); dismissals=\(dismissals); names=\(sentNames.joined(separator: ",")); vcards=\(sentVCards); options=\(sentOptions); mode=\(mode)"
            status.text = result
            log(result)
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("contact-selection-panel-probe.txt"), options: .atomic,
                )
            }
        }
    }

    private static var contactCards: [Int64: CNContact] {
        let card = CNMutableContact()
        card.givenName = "Cora 08"
        card.familyName = "Fixture"
        card.phoneNumbers = [CNLabeledValue(
            label: CNLabelPhoneNumberMobile,
            value: CNPhoneNumber(stringValue: "155501023"),
        )]
        card.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "fixture@example.invalid" as NSString)]
        return [9_000_023: card]
    }

    private static var contacts: [ComposeContact] {
        (0..<24).map { index in
            let name = ["Ada", "Bruno", "Cora"][index % 3] + String(format: " %02d", index / 3 + 1)
            return ComposeContact(user: User(
                accentColorId: -1, activeStoryState: nil, addedToAttachmentMenu: false, backgroundCustomEmojiId: 0,
                emojiStatus: nil, firstName: name, haveAccess: true, id: 9_000_000 + Int64(index),
                isCloseFriend: false, isContact: true, isMutualContact: false, isPremium: false, isSupport: false,
                languageCode: "", lastName: "Fixture", paidMessageStarCount: 0, phoneNumber: "1555010\(index)",
                profileAccentColorId: -1, profileBackgroundCustomEmojiId: 0, profilePhoto: nil, restrictionInfo: nil,
                restrictsNewChats: false, status: .userStatusEmpty, type: .userTypeRegular, upgradedGiftColors: nil,
                usernames: nil, verificationStatus: nil,
            ))
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-contact-panel") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let navigation = TelegramNavigationController(rootViewController: Host())
            navigation.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(navigation, animated: false)
        }
    }
}
#endif
