// FileAttachmentProbe.swift

#if DEBUG
import TDLibKit
import UIKit

/// Local recent documents in the real picker, with controlled receipts. No account reads or TDLib sends.
@MainActor enum FileAttachmentProbe {
    private final class Host: UIViewController {
        private let status = UILabel()
        private var retainedPicker: PollFileAttachmentViewController?
        private var retainedOther: UIViewController?
        private weak var activeNavigation: TelegramNavigationController?
        private var renewOnNextSend = false
        private var renewAfterDelay = false
        private var generation = 0
        private var renewals = 0
        private var failure = 0
        private var destination = 0
        private var sends = 0
        private var picks = 0
        private var records = [String]()
        private var checks = ""

        private var capabilities: AttachmentSendCapabilities {
            AttachmentSendCapabilities(
                isReminders: destination == 1, canSchedule: destination != 2, canSendWhenOnline: destination == 0,
            )
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            title = "File attachment fixture"
            view.backgroundColor = .systemGroupedBackground
            checks = verifyReceipts()
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 18
            stack.translatesAutoresizingMaskIntoConstraints = false
            for title in [
                "Open files",
                "Open poll",
                "Failure",
                "Destination",
                "Appearance",
                "Renew on send",
                "Renew after delay",
            ] {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    switch title {
                    case "Open files": open(poll: false)
                    case "Open poll": open(poll: true)
                    case "Failure": failure = (failure + 1) % 3
                    report()
                    case "Destination": destination = (destination + 1) % 3
                    report()
                    case "Renew on send": renewOnNextSend.toggle()
                    report()
                    case "Renew after delay": renewAfterDelay.toggle()
                    report()
                    default: overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .light : .dark
                    }
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
            status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            status.numberOfLines = 8
            stack.addArrangedSubview(status)
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            report()
        }

        private func open(poll: Bool) {
            guard presentedViewController == nil else { return }
            let initialGeneration = generation
            let capabilities = AttachmentSendCapabilities(
                isReminders: destination == 1, canSchedule: destination != 2, canSendWhenOnline: destination == 0,
            )
            let picker =
 if poll {
                PollFileAttachmentViewController(probeFiles: fixtures)
            } else {
                PollFileAttachmentViewController(probeFiles: fixtures, sendCapabilities: capabilities) {
                    [weak self] request in
                    guard let self else { return AttachmentFileSendResult(error: "fixture closed") }
                    return await handleSend(request, bindingGeneration: initialGeneration)
                }
            }
            retainedPicker = picker
            let navigation = TelegramNavigationController(rootViewController: UIViewController())
            activeNavigation = navigation
            navigation.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
            navigation.modalPresentationStyle = .pageSheet
            navigation.sheetPresentationController?.detents = [.medium(), .large()]
            picker.onPick = { [weak self, weak navigation] document in
                self?.picks += 1
                self?.records.append("poll=\(document.fileName)")
                self?.report()
                navigation?.dismiss(animated: true)
            }
            picker.onDismiss = { [weak self] in
                self?.retainedPicker = nil
                self?.report()
            }
            let other = UIViewController()
            retainedOther = other
            other.title = "Gallery fixture tab"
            other.view.backgroundColor = .systemGroupedBackground
            other.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", primaryAction: UIAction {
                [weak navigation] _ in navigation?.dismiss(animated: true)
            })
            let switchTab: (AttachmentSheetTab) -> Void = { [weak navigation, weak picker, weak other] tab in
                guard let navigation, let picker, let other else { return }
                navigation.replaceAttachmentSheetContent(with: tab == .file ? picker : other)
            }
            AttachmentPanelView.install(in: picker, tabs: [.gallery, .file], current: .file, onSelectTab: switchTab)
            AttachmentPanelView.install(in: other, tabs: [.gallery, .file], current: .gallery, onSelectTab: switchTab)
            // Keep the fixture's other tab alive without retaining its navigation controller.
            picker.onSelectFromGallery = { [weak navigation, other] in
                navigation?.replaceAttachmentSheetContent(with: other)
            }
            picker.onSelectFromFiles = { [weak self] in
                self?.records.append("system files action")
                self?.report()
            }
            navigation.setViewControllers([other], animated: false)
            present(navigation, animated: true) { [self] in
                navigation.replaceAttachmentSheetContent(with: picker)
                if renewAfterDelay {
                    renewAfterDelay = false
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(6))
                        self?.requestRenewal()
                    }
                }
            }
        }

        private func handleSend(
            _ request: AttachmentFileSendRequest,
            bindingGeneration: Int,
        ) async -> AttachmentFileSendResult {
            sends += 1
            if renewOnNextSend {
                renewOnNextSend = false
                requestRenewal()
            }
            let caption = ComposerText.formatted(request.caption)
            let contents = AttachmentFileSendRequest.contents(files: request.files, caption: caption)
            let captionSlots = contents.enumerated().compactMap { index, content -> String? in
                guard case .inputMessageDocument(let input) = content, input.caption != nil else { return nil }
                return String(index)
            }
            let timing =
 switch request.options?.schedulingState {
            case .messageSchedulingStateSendAtDate(let date): "date:\(date.sendDate)"
            case .messageSchedulingStateSendWhenOnline: "online"
            case .messageSchedulingStateSendWhenVideoProcessed: "videoProcessed"
            case nil: "now"
            }
            let record = "generation=\(bindingGeneration); send=\(sends); ids=\(request.files.map(\.id.messageID)); "
                + "caption=\(caption.text); entities=\(caption.entities.map { "\($0.offset):\($0.length):\($0.type)" }); "
                + "captionSlots=\(captionSlots); silent=\(request.options?.disableNotification ?? false); "
                + "schedule=\(timing)"
            records.append(record)
            report()
            try? await Task.sleep(for: .seconds(1))
            let failed = failure
            failure = 0
            if failed == 1 {
                // A receipt for the final file clears its caption; the first file stays selected.
                let accepted = Set(request.files.enumerated().filter { $0.offset != 0 }.map(\.element.id))
                return AttachmentFileSendResult(acceptedIDs: accepted, error: "Fixture partial send")
            }
            if failed == 2 { return AttachmentFileSendResult(error: "Fixture send failed") }
            return AttachmentFileSendResult(acceptedIDs: Set(request.files.map(\.id)))
        }

        private func requestRenewal() {
            guard let picker = retainedPicker, let navigation = activeNavigation else { return }
            records.append("replacement requested; generation=\(generation)")
            report()
            let top = picker.additionalSafeAreaInsets.top
            picker.prepareForClientReplacement { [weak self, weak picker, weak navigation] in
                guard let self, let picker, let navigation else { return }
                records.append("old request settled; generation=\(generation)")
                Task { @MainActor [weak self, picker, navigation] in
                    await self?.performRenewal(picker: picker, navigation: navigation, top: top)
                }
            }
        }

        private func performRenewal(
            picker: PollFileAttachmentViewController, navigation: TelegramNavigationController, top: CGFloat,
        ) async {
            await withCheckedContinuation { continuation in
                navigation.dismiss(animated: true) { continuation.resume() }
            }
            navigation.releaseChrome(of: picker)
            if let retainedOther { navigation.releaseChrome(of: retainedOther) }
            navigation.setViewControllers([], animated: false)
            generation += 1
            let replacementGeneration = generation
            let replacement = TelegramNavigationController(rootViewController: picker)
            replacement.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
            replacement.modalPresentationStyle = .pageSheet
            replacement.sheetPresentationController?.detents = [.medium(), .large()]
            replacement.sheetPresentationController?.selectedDetentIdentifier = .large
            let select: (AttachmentSheetTab) -> Void = { [weak self, weak replacement, weak picker] tab in
                guard let self, let replacement, let picker, let other = retainedOther else { return }
                replacement.replaceAttachmentSheetContent(with: tab == .file ? picker : other)
            }
            picker.resumeAfterClientReplacement(
                client: TDLib.shared.activeClient, capabilities: capabilities, onSelectTab: select,
            ) { [weak self] request in
                guard let self else { return AttachmentFileSendResult(error: "fixture closed") }
                return await handleSend(request, bindingGeneration: replacementGeneration)
            }
            picker.onSelectFromGallery = { select(.gallery) }
            retainedOther?.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Cancel",
                primaryAction: UIAction {
                [weak replacement] _ in replacement?.dismiss(animated: true)
            },
            )
            if let panel = retainedOther?.view
.subviews
                .first(where: { $0 is AttachmentPanelView }) as? AttachmentPanelView
            {
                panel.onSelectTab = select
            }
            activeNavigation = replacement
            await withCheckedContinuation { continuation in
                present(replacement, animated: true) { continuation.resume() }
            }
            picker.view.layoutIfNeeded()
            renewals += 1
            let panels = picker.view.subviews.count(where: { $0 is AttachmentPanelView })
            records
                .append(
                    "restored=\(renewals); top=\(picker.additionalSafeAreaInsets.top)/\(top); bottom=\(picker.additionalSafeAreaInsets.bottom); panels=\(panels)",
                )
            report()
        }

        private func report() {
            let text = "File fixture: sends=\(sends); picks=\(picks); failure=\(failure); destination=\(destination); renewOnSend=\(renewOnNextSend); delayed=\(renewAfterDelay); restored=\(renewals)\n"
                + checks + "\n" + records.joined(separator: "\n")
            status.text = text
            status.accessibilityLabel = text
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(text.utf8).write(
                    to: directory.appendingPathComponent("file-attachment-probe.txt"),
                    options: .atomic,
                )
            }
        }
    }

    private static var fixtures: [AttachmentRecentFile] {
        (1...12).map { index in
            let file = File(
                id: index, size: 1024, expectedSize: 1024,
                local: LocalFile(
                    path: "", canBeDownloaded: false, canBeDeleted: false, isDownloadingActive: false,
                    isDownloadingCompleted: false, downloadOffset: 0, downloadedPrefixSize: 0, downloadedSize: 0,
                ),
                remote: RemoteFile(
                    id: "", uniqueId: "file-fixture-\(index)", isUploadingActive: false,
                    isUploadingCompleted: true, uploadedSize: 1024,
                ),
            )
            return AttachmentRecentFile(
                id: .init(chatID: 1, messageID: Int64(index)), date: 1_793_310_000,
                document: Document(
                    fileName: String(format: "File %02d.pdf", index), mimeType: "application/pdf",
                    minithumbnail: nil, thumbnail: nil, document: file,
                ),
            )
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-file-attachment") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let navigation = TelegramNavigationController(rootViewController: Host())
            navigation.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(navigation, animated: false)
        }
    }

    private static func verifyReceipts() -> String {
        let files = Array(fixtures.prefix(3))
        let caption = FormattedText(
            entities: [TextEntity(offset: 0, length: 4, type: .textEntityTypeBold)],
            text: "bold",
        )
        let contents = AttachmentFileSendRequest.contents(files: files, caption: caption)
        guard case .inputMessageDocument(let first) = contents[0], first.caption == nil,
              case .inputMessageDocument(let last) = contents[2], last.caption == caption
        else {
            return "checks=FAILED caption"
        }
        let middle = message(file: files[1], caption: FormattedText(entities: [], text: ""))
        let final = message(file: files[2], caption: caption)
        guard AttachmentFileSendRequest.acceptedIDs(files: files, contents: contents, messages: [middle, final])
            == Set([files[1].id, files[2].id]) else { return "checks=FAILED partial receipts" }
        let duplicate = AttachmentRecentFile(
            id: .init(chatID: 2, messageID: 1),
            date: files[0].date,
            document: files[0].document,
        )
        let duplicates = [files[0], duplicate]
        let duplicateContents = AttachmentFileSendRequest.contents(files: duplicates, caption: caption)
        guard AttachmentFileSendRequest.acceptedIDs(
            files: duplicates, contents: duplicateContents, messages: [message(file: duplicate, caption: caption)],
        ) == Set([duplicate.id]) else { return "checks=FAILED duplicate file caption" }
        guard AttachmentFileSendRequest.acceptedIDs(
            files: files, contents: contents, messages: [message(file: fixtures[9], caption: caption)],
        ) == nil else { return "checks=FAILED unknown receipt" }
        let session = AttachmentFileSendSession()
        let context = ResolvedSendContext(
            accountID: UUID(), chatID: 44, clientID: 99,
            destinationTopic: .messageTopicForum(MessageTopicForum(forumTopicId: 12)), draftTopic: nil, replyTo: nil,
        )
        _ = session.capture { .init(context: context, reply: nil, defaultOptions: ChatVM.sendOptions(silent: true)) }
        var recaptured = false
        let retained = session.capture {
            recaptured = true
            return .init(context: context, reply: nil, defaultOptions: nil)
        }
        guard !recaptured, retained.context.destinationTopic == context.destinationTopic, retained.reply == nil,
              retained.defaultOptions?.disableNotification == true else { return "checks=FAILED retry context" }
        let old = ChatLocation(accountID: context.accountID, chatID: 44, clientID: 99, topic: nil)
        let next = ChatLocation(accountID: context.accountID, chatID: 44, clientID: 100, topic: nil)
        let third = ChatLocation(accountID: context.accountID, chatID: 44, clientID: 101, topic: nil)
        guard let moved = session.replacingClient(from: old, with: next),
              let movedAgain = moved.replacingClient(from: next, with: third)
        else {
            return "checks=FAILED repeated client replacement"
        }
        let newest = movedAgain.capture { retained }
        guard newest.context.clientID == 101, newest.context.destinationTopic == context.destinationTopic,
              newest.reply == nil, newest.defaultOptions?.disableNotification == true,
              session.capture({ retained }).context.clientID == 99 else { return "checks=FAILED detached context" }
        for invalid in [
            ChatLocation(accountID: UUID(), chatID: 44, clientID: 100, topic: nil),
            ChatLocation(accountID: context.accountID, chatID: 45, clientID: 100, topic: nil),
            ChatLocation(accountID: context.accountID, chatID: 44, clientID: 100, topic: context.destinationTopic),
            old,
        ] {
            guard session.replacingClient(from: old, with: invalid) == nil else {
                return "checks=FAILED replacement boundary"
            }
        }
        guard session.replacingClient(from: next, with: third) == nil else { return "checks=FAILED wrong source" }
        let reply = CustomMessage(message: message(file: files[0], caption: caption), properties: .default)
        let quote = InputMessageReplyTo.inputMessageReplyToMessage(TDNativeInputMessageReplyToMessage(
            messageId: reply.id, quote: TDNativeInputTextQuote(text: caption, richTexts: [], position: 2),
            checklistTaskId: 0, pollOptionId: "",
        ))
        let quotedContext = ResolvedSendContext(
            accountID: context.accountID, chatID: 44, clientID: 99, destinationTopic: context.destinationTopic,
            draftTopic: nil, replyTo: quote,
        )
        let quotedSession = AttachmentFileSendSession()
        let quotedSnapshot = quotedSession.capture { .init(context: quotedContext, reply: reply, defaultOptions: nil) }
        guard let quotedTransfer = quotedSession.replacingClient(from: old, with: next) else {
            return "checks=FAILED quote replacement"
        }
        let quotedResult = quotedTransfer.capture { quotedSnapshot }
        guard quotedResult.context.replyTo == quote, quotedResult.reply?.id == reply.id,
              quotedResult.context.clientID == 100 else { return "checks=FAILED quote ownership" }
        return "checks=passed: last-caption, entities, nonprefix/duplicate/unknown receipts, retry context, repeated replacement, account/chat/topic/client fences, reply/quote/nil"
    }

    private static func message(file: AttachmentRecentFile, caption: FormattedText) -> Message {
            Message(
                id: file.id.messageID,
                senderId: .messageSenderUser(MessageSenderUser(userId: 777_000)),
                receiverId: nil,
                chatId: file.id.chatID,
                sendingState: nil,
                schedulingState: nil,
                isOutgoing: false,
                isPinned: false,
                isFromOffline: false,
                canBeSaved: true,
                hasTimestampedMedia: false,
                isChannelPost: false,
                isPaidStarSuggestedPost: false,
                isPaidGramSuggestedPost: false,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                date: Int(Date().timeIntervalSince1970),
                editDate: 0,
                forwardInfo: nil,
                importInfo: nil,
                interactionInfo: nil,
                unreadReactions: [],
                factCheck: nil,
                suggestedPostInfo: nil,
                replyTo: nil,
                topicId: nil,
                selfDestructType: nil,
                selfDestructIn: 0,
                autoDeleteIn: 0,
                viaBotUserId: 0,
                guestBotCallerId: nil,
                senderBusinessBotUserId: 0,
                senderBoostCount: 0,
                senderTag: "",
                paidMessageStarCount: 0,
                authorSignature: "",
                mediaAlbumId: 0,
                effectId: 0,
                restrictionInfo: nil,
                summaryLanguageCode: "",
                content: .messageDocument(MessageDocument(document: file.document, caption: caption)),
                ephemeralContent: nil,
                replyMarkup: nil,
                ephemeralMessageId: 0,
                chatInstance: 0,
            )
    }
}
#endif
