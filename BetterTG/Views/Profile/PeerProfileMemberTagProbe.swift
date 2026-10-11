// PeerProfileMemberTagProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum PeerProfileMemberTagProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?

        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { let value = continuation
        continuation = nil
        value?.resume()
        }
    }

    @MainActor private final class Fixture {
        let first = TdUpdateSource(accountID: UUID(), clientID: 810)
        var current: TdUpdateSource?
        var actor: Int64? = 77
        let ready = CurrentValueSubject<TdUpdateSource?, Never>(nil)
        let clients = PassthroughSubject<TdUpdateSource, Never>()
        let accounts = PassthroughSubject<Void, Never>()
        let parent = UIViewController()
        let members = UIViewController()
        let window: UIWindow
        let navigation: UINavigationController
        let retention = PeerProfileMemberTagRetention()
        var reads = 0
        var terminals = 0
        var saved = 0
        var serverTag = "old"
        var allowed = true
        var actorReturned: Int64 = 77
        var targetReturned: Int64 = 88
        var chatReturned: Int64 = 8
        var activeTarget = true
        var failAcknowledgment = false
        var writes = [(TdUpdateSource, PeerProfileEditSession.Mutation)]()
        var preflights = [Int: Gate]()
        var acknowledgments = [Int: Gate]()
        lazy var session = PeerProfileEditSession(
            accountID: first.accountID, actorID: 77,
            currentSource: { [weak self] in self?.current }, currentActor: { [weak self] in self?.actor },
            readiness: ready.eraseToAnyPublisher(), clientChanges: clients.eraseToAnyPublisher(),
            accountChanges: accounts.eraseToAnyPublisher(), resolve: { [weak self] source in
                guard let self else { return nil }
                return .init(source: source) { [weak self] mutation, dispatch in
                    guard let self, case .memberTag(let chatID, let targetID, let baseline, _) = mutation else {
                        throw CancellationError()
                    }
                    defer { terminals += 1 }
                    let authorization = PeerProfileMemberTagAuthorization(
                        chatID: chatID, actorID: 77, targetID: targetID, source: source,
                        currentSource: { [weak self] in self?.current }, currentActor: { [weak self] in self?.actor },
                        fetch: { [weak self] in
                            guard let self else { throw CancellationError() }
                            reads += 1
                            let index = reads
                            await preflights[index]?.wait()
                            return snapshot()
                        },
                    )
                    try await authorization.perform(baseline: baseline) {
                        try dispatch()
                        self.writes.append((source, mutation))
                        await self.acknowledgments[self.writes.count]?.wait()
                        if self.failAcknowledgment { throw Failure(description: "controlled tag rejection") }
                    }
                }
            },
        )

        init() throws {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                throw Failure(description: "no scene")
            }
            self.window = UIWindow(windowScene: scene)
            self.navigation = ClassicNavigation.controller(rootViewController: UIViewController())
            self.current = first
            ready.send(first)
            window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
            window.rootViewController = navigation
            window.isHidden = false
        }

        func snapshot() -> PeerProfileMemberTagAuthorization.Snapshot {
            let permissions = RootChatInsertionProbe.chat(.init(
                isPinned: false,
                list: .chatListMain,
                order: 1,
                source: nil,
            ))
.chat
.permissions
            return .init(
                chatID: chatReturned,
                chatType: .chatTypeBasicGroup(.init(basicGroupId: 9)),
                permissions: permissions,
                actor: .init(
                    memberId: .messageSenderUser(.init(userId: actorReturned)),
                    tag: "",
                    inviterUserId: 0,
                    joinedChatDate: 0,
                    status: allowed
                                          ? .chatMemberStatusCreator(.init(isAnonymous: false, isMember: true))
                                          : .chatMemberStatusMember(.init(memberUntilDate: 0)),
                ),
                target: .init(
                    memberId: .messageSenderUser(.init(userId: targetReturned)),
                    tag: serverTag,
                    inviterUserId: 0,
                    joinedChatDate: 0,
                    status: activeTarget
                                           ? .chatMemberStatusMember(.init(memberUntilDate: 0))
                                           : .chatMemberStatusLeft,
                ),
            )
        }

        func editor() -> PeerProfileMemberTagViewController {
            let editor = PeerProfileMemberTagViewController(
                session: session,
                chatID: 8,
                initialAuthority: .init(baselineTag: "old", editorTitle: "Edit Member Tag"),
                targetTitle: "Member",
                targetUserID: 88,
            )
            editor.onSaved = { [weak self] in self?.saved += 1 }
            retention.editor = editor
            navigation.setViewControllers([navigation.viewControllers[0], parent, members, editor], animated: false)
            editor.loadViewIfNeeded()
            navigation.view.layoutIfNeeded()
            editor.view.layoutIfNeeded()
            return editor
        }

        func holds() -> Bool {
            retention.shouldRetain(
                parent: parent,
                members: members,
                accountID: first.accountID,
                actorID: 77,
                chatID: 8,
                currentAccountID: current?.accountID,
                currentActorID: actor,
            )
        }

        @discardableResult func replace(_ clientID: Int32) -> TdUpdateSource {
            ready.send(nil)
            let source = TdUpdateSource(accountID: first.accountID, clientID: clientID)
            current = source
            clients.send(source)
            return source
        }

        func close() {
            preflights.values.forEach { $0.release() }
            acknowledgments.values.forEach { $0.release() }
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-member-tag") else { return }
        Task { @MainActor in
            let result: String
            do {
                try await until("scene") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
                try await verifyRetention()
                try await verifyAuthorization()
                try await verifyPredispatch()
                try await verifyUncertain()
                try await verifyNewTyping()
                try await verifyModalOwnership()
                try verifyRevocation()
                result = "Profile member tag probe passed: actual-tag-editor/exact-native-triplet/typed-hold/Back=true; "
                    + "repeated-Ready/raw-text/UTF16-selection/marked-text/errors/zero-auto-writes=true; "
                    + "production-tag-authorization/raw-identities/rights/baseline/empty-removal=true; "
                    + "immutable-endpoint/predispatch-zero/postdispatch-uncertain/no-replay/new-typing-ACK=true; "
                    + "account-actor-ABA/detached/stale-completion=true; "
                    + "modal-draft-hold/covered-Save-completion=true; "
                    + "Profile/Members-parents=value-only; whole-navigation-coordinator/live-TDLib/foreground=unverified; server-writes=0"
            } catch { result = "Profile member tag probe failed: \(error)" }
            log(result)
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("profile-member-tag-probe.txt"),
                    options: .atomic,
                )
            }
        }
    }

    private static func verifyRetention() async throws {
        let f = try Fixture()
        let previousKey = f.window.windowScene?.windows.first(where: \.isKeyWindow)
        defer { f.close()
        previousKey?.makeKey()
        }
        let editor = f.editor(), field = try field(editor)
        f.window.makeKey()
        try require(field.becomeFirstResponder(), "field refused focus")
        change(field, "Тег e\u{301}")
        guard let start = field.position(from: field.beginningOfDocument, offset: 1),
              let end = field.position(from: field.beginningOfDocument, offset: 4)
              else { throw Failure(description: "selection") }
        field.selectedTextRange = field.textRange(from: start, to: end)
        let raw = field.text, selection = offsets(field)
        for id: Int32 in [811, 812] {
            let next = f.replace(id)
            try require(
                f.holds() && f.session.state == .waiting && editor.navigationItem.rightBarButtonItem?
                    .isEnabled == false,
                "pre-Ready lost typed hold or enabled Save",
            )
            f.ready.send(f.first)
            try require(f.session.state == .waiting, "old Ready activated renewed editor")
            f.ready.send(next)
            try require(
                f.holds() && f.session.state == .ready && tryField(editor) === field && field.text == raw
                        && offsets(field) == selection && field.isFirstResponder && f.writes.isEmpty,
                "epoch replacement changed field/selection/focus or auto-wrote",
            )
        }
        field.setMarkedText("в", selectedRange: NSRange(location: 1, length: 0))
        field.sendActions(for: .editingChanged)
        try require(field.markedTextRange != nil, "native marked-text setup failed")
        let markedRaw = field.text
        let next = f.replace(813)
        f.ready.send(next)
        save(editor)
        try require(
            field.markedTextRange != nil && field.text == markedRaw && f.writes.isEmpty,
            "renewal/Save committed or erased marked text",
        )
        field.unmarkText()
        change(field, "new tag")
        f.allowed = false
        save(editor)
        try await until("permission error") { f.terminals == 1 && f.session.state == .ready }
        let error = errors(editor)
        let renewed = f.replace(814)
        f.ready.send(renewed)
        try require(
            !error.isEmpty && errors(editor) == error && field.text == "new tag",
            "waiting cleared local error/draft",
        )
        let cover = UIViewController()
        f.navigation.pushViewController(cover, animated: false)
        try require(!f.holds(), "foreign top borrowed tag hold")
        f.navigation.popViewController(animated: false)
        try await until("uncovered editor") {
            f.navigation.topViewController === editor && f.navigation.transitionCoordinator == nil
        }
        let old = f.navigation.popViewController(animated: false)
        try require(
            old === editor && !f.navigation.viewControllers.contains(where: { $0 === editor }) && !f.holds(),
            "Back did not release exact hold",
        )
        f.ready.send(f.replace(815))
        try require(f.navigation.topViewController === f.members && f.writes.isEmpty, "late Ready reinserted editor")
    }

    private static func verifyAuthorization() async throws {
        for denial in 0..<5 {
            let f = try Fixture()
            defer { f.close() }
            let editor = f.editor(), field = try field(editor)
            change(field, "candidate")
            switch denial {
            case 0: f.actorReturned = 99
            case 1: f.targetReturned = 99
            case 2: f.chatReturned = 99
            case 3: f.serverTag = "changed elsewhere"
            default: f.activeTarget = false
            }
            save(editor)
            try await until("fresh tag denial") { f.terminals == 1 && f.session.state == .ready }
            try require(
                f.writes.isEmpty && f.saved == 0 && field.text == "candidate" && !errors(editor).isEmpty,
                "wrong identity/conflict/inactive target dispatched or lost input",
            )
        }
        let f = try Fixture()
        defer { f.close() }
        let editor = f.editor(), field = try field(editor)
        change(field, "")
        save(editor)
        try await until("empty tag removal") { f.writes.count == 1 && f.saved == 1 }
        try require(
            f.writes[0].1 == .memberTag(chatID: 8, targetID: 88, baseline: "old", tag: ""),
            "empty removal was trimmed/dropped or mutated",
        )
    }

    private static func verifyPredispatch() async throws {
        let f = try Fixture()
        defer { f.close() }
        let editor = f.editor(), field = try field(editor)
        let oldGate = Gate(), newGate = Gate()
        f.preflights[1] = oldGate
        f.preflights[2] = newGate
        change(field, "first")
        save(editor)
        try await until("old preflight") { oldGate.continuation != nil }
        f.ready.send(f.replace(821))
        change(field, "second")
        save(editor)
        try await until("new preflight") { newGate.continuation != nil }
        oldGate.release()
        try await until("old preflight terminal") { f.terminals == 1 }
        try require(f.session.state == .saving && f.writes.isEmpty && f.saved == 0, "old completion consumed successor")
        let popped = f.navigation.popViewController(animated: false)
        try require(popped === editor && !PeerProfileEditSession.isAttached(editor), "pop retained action ownership")
        newGate.release()
        try await until("detached preflight terminal") { f.terminals == 2 }
        try require(
            f.writes.isEmpty && f.saved == 0 && f.navigation.topViewController === f.members,
            "detached preflight wrote or popped replacement",
        )
    }

    private static func verifyUncertain() async throws {
        for fails in [false, true] {
            let f = try Fixture()
            defer { f.close() }
            let editor = f.editor(), field = try field(editor), ack = Gate()
            f.acknowledgments[1] = ack
            f.failAcknowledgment = fails
            change(field, "sent once")
            save(editor)
            try await until("tag dispatched") { f.writes.count == 1 && ack.continuation != nil }
            f.ready.send(f.replace(831))
            try require(f.session.state == .uncertain && f.holds(), "dispatched source loss did not become uncertain")
            save(editor)
            _ = editor.textFieldShouldReturn(field)
            ack.release()
            try await until("uncertain terminal") { f.terminals == 1 }
            f.ready.send(f.current)
            try require(
                f.session.state == .uncertain && f.writes.count == 1 && f.saved == 0
                        && f.navigation.topViewController === editor && field.text == "sent once",
                "late ACK/error replayed, popped, or accepted uncertain mutation",
            )
        }
    }

    private static func verifyNewTyping() async throws {
        let f = try Fixture()
        defer { f.close() }
        let editor = f.editor(), field = try field(editor), ack = Gate()
        f.acknowledgments[1] = ack
        change(field, "first")
        save(editor)
        try await until("first tag dispatched") { ack.continuation != nil }
        change(field, "second")
        ack.release()
        try await until("first tag accepted") { f.saved == 1 && f.session.state == .ready }
        try require(
            f.navigation.topViewController === editor && field.text == "second",
            "ACK popped/rewrote newer typing",
        )
        f.serverTag = "first"
        save(editor)
        try await until("new tag accepted") { f.saved == 2 }
        try require(
            f.writes.count == 2 && f.writes[1].1 == .memberTag(
                chatID: 8,
                targetID: 88,
                baseline: "first",
                tag: "second",
            ),
            "next explicit save did not use accepted baseline",
        )
    }

    private static func verifyRevocation() throws {
        for actorChange in [false, true] {
            let f = try Fixture()
            defer { f.close() }
            let editor = f.editor(), field = try field(editor)
            change(field, "kept")
            if actorChange {
                f.actor = 99
                f.accounts.send(())
                f.actor = 77
                f.accounts.send(())
            } else {
                let foreign = TdUpdateSource(accountID: UUID(), clientID: 850)
                f.current = foreign
                f.clients.send(foreign)
                f.current = f.first
                f.clients.send(f.first)
            }
            f.ready.send(f.first)
            save(editor)
            try require(
                f.session.state == .revoked && !f.holds() && f.writes.isEmpty && field.text == "kept",
                "account/actor ABA revived tag editor",
            )
        }
    }

    private static func verifyModalOwnership() async throws {
        for fails in [false, true] {
            let f = try Fixture()
            defer { f.close() }
            let editor = f.editor(), field = try field(editor)
            change(field, "candidate")
            let modal = UIViewController()
            editor.present(modal, animated: false)
            try await until("actual tag modal") {
                modal.presentingViewController?.presentedViewController === modal && modal.viewIfLoaded?.window === f
                    .window
                    && !modal.isBeingPresented
            }
            let next = f.replace(861)
            try require(f.holds(), "nonmutating hold lost draft behind owned modal")
            f.ready.send(next)
            save(editor)
            try require(
                f.writes.isEmpty && f.reads == 0 && field.text == "candidate",
                "covered Save began an operation",
            )
            modal.dismiss(animated: false)
            try await until("tag modal dismissed") { modal.presentingViewController == nil && !modal.isBeingDismissed }
            let ack = Gate()
            f.acknowledgments[1] = ack
            f.failAcknowledgment = fails
            save(editor)
            try await until("covered completion dispatch") { ack.continuation != nil }
            let cover = UIViewController()
            editor.present(cover, animated: false)
            try await until("cover before ACK") {
                cover.presentingViewController?.presentedViewController === cover && !cover.isBeingPresented
            }
            ack.release()
            try await until("covered terminal") { f.terminals == 1 && f.session.state == .ready }
            try require(
                f.navigation.topViewController === editor && cover.presentingViewController != nil
                        && field.text == "candidate" && errors(editor).isEmpty && f.writes.count == 1,
                "covered ACK/error popped or overlaid unrelated UI",
            )
            cover.dismiss(animated: false)
            try await until("completion cover dismissed") { cover.presentingViewController == nil }
        }
    }

    private static func tryField(_ editor: UIViewController) -> UITextField?
{ descendants(editor.view)
        .compactMap { $0 as? UITextField }
.first
}

    private static func field(_ editor: UIViewController) throws -> UITextField {
        guard let field = tryField(editor) else { throw Failure(description: "missing actual tag field") }
        return field
    }

    private static func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private static func change(_ field: UITextField, _ text: String) { field.text = text
    field.sendActions(for: .editingChanged)
    }

    private static func offsets(_ field: UITextField) -> [Int] {
        guard let range = field.selectedTextRange else { return [] }
        return [
            field.offset(from: field.beginningOfDocument, to: range.start),
            field.offset(from: field.beginningOfDocument, to: range.end),
        ]
    }

    private static func errors(_ editor: UIViewController) -> [String] {
        descendants(editor.view).compactMap { view in
            guard let label = view as? UILabel, !label.isHidden, label.textColor == .systemRed else { return nil }
            return label.text
        }
    }

    private static func save(_ editor: UIViewController) {
        guard let item = editor.navigationItem.rightBarButtonItem, let action = item.action else { return }
        UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil)
    }

    private static func until(_ label: String, _ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(3)
        while !predicate() {
            guard Date() < end else { throw Failure(description: "timeout: \(label)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func require(_ value: Bool, _ message: String) throws {
        guard value else { throw Failure(description: message) }
    }
}
#endif
