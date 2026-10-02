// PeerProfileEditSessionProbe.swift

#if DEBUG
import Combine
import TDLibKitDynamic
import UIKit

@MainActor enum PeerProfileEditSessionProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?

        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() {
            let saved = continuation
            continuation = nil
            saved?.resume()
        }
    }

    @MainActor private final class Fixture {
        let first = TdUpdateSource(accountID: UUID(), clientID: 710)
        var current: TdUpdateSource?
        var actor: Int64? = 77
        let ready = CurrentValueSubject<TdUpdateSource?, Never>(nil)
        let clients = PassthroughSubject<TdUpdateSource, Never>()
        let accounts = PassthroughSubject<Void, Never>()
        let window: UIWindow
        let parent = UIViewController()
        let navigation: UINavigationController
        let retention = PeerProfileEditorRetention()
        var writes = [(TdUpdateSource, PeerProfileEditSession.Mutation)]()
        var authorizationReads = 0
        var allowed = true
        var denyAfterFirst = false
        var failWrites = Set<Int>()
        var authorizationGate: Gate?
        var authorizationGateAt = 1
        var writeGate: Gate?
        var writeGateAt = 1
        lazy var session = PeerProfileEditSession(
            accountID: first.accountID,
            actorID: 77,
            currentSource: { [weak self] in self?.current },
            currentActor: { [weak self] in self?.actor },
            readiness: ready.eraseToAnyPublisher(),
            clientChanges: clients.eraseToAnyPublisher(),
            accountChanges: accounts.eraseToAnyPublisher(),
            resolve: { [weak self] source in
                guard let self else { return nil }
                return .init(source: source) { [weak self] mutation, dispatch in
                    guard let self else { throw CancellationError() }
                    switch mutation {
                    case .description(let chatID, _), .title(let chatID, _):
                        let authorization = PeerProfileInfoEditAuthorization(
                            chatID: chatID,
                            actorUserID: 77,
                            source: source,
                            currentSource: { [weak self] in self?.current },
                            currentActorUserID: { [weak self] in self?.actor },
                            fetchSnapshot: { [weak self] in
                                guard let self else { throw CancellationError() }
                                authorizationReads += 1
                                if authorizationReads == authorizationGateAt { await authorizationGate?.wait() }
                                return .init(
                                    chatID: chatID,
                                    chatType: .chatTypeBasicGroup(.init(basicGroupId: 8)),
                                    permissions: Self.permissions(allowed),
                                    memberID: .messageSenderUser(.init(userId: 77)),
                                    status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
                                )
                            },
                        )
                        _ = try await authorization.perform {
                            try await self.write(mutation, source: source, dispatch: dispatch)
                        }
                    default: try await write(mutation, source: source, dispatch: dispatch)
                    }
                }
            },
        )

        init(classicNavigation: Bool = false) throws {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = classicNavigation
                ? scenes.first(where: { $0.windows.contains(where: \.isKeyWindow) })
                : scenes.first
            else {
                throw Failure(description: "no attached window scene")
            }
            self.window = UIWindow(windowScene: scene)
            self.navigation = classicNavigation
                ? ClassicNavigation.controller(rootViewController: UIViewController())
                : UINavigationController(rootViewController: UIViewController())
            window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
            self.current = first
            ready.send(first)
            window.rootViewController = navigation
            window.isHidden = false
            navigation.loadViewIfNeeded()
            navigation.view.layoutIfNeeded()
        }

        static func permissions(_ allowed: Bool) -> ChatPermissions {
            .init(
                canAddLinkPreviews: false,
                canChangeInfo: allowed,
                canCreateTopics: false,
                canEditTag: false,
                canInviteUsers: false,
                canPinMessages: false,
                canReactToMessages: false,
                canSendAudios: false,
                canSendBasicMessages: false,
                canSendDocuments: false,
                canSendOtherMessages: false,
                canSendPhotos: false,
                canSendPolls: false,
                canSendVideoNotes: false,
                canSendVideos: false,
                canSendVoiceNotes: false,
            )
        }

        func write(
            _ mutation: PeerProfileEditSession.Mutation,
            source: TdUpdateSource,
            dispatch: () throws -> Void,
        ) async throws {
            try dispatch()
            writes.append((source, mutation))
            let index = writes.count
            if index == writeGateAt { await writeGate?.wait() }
            if failWrites.contains(index) { throw Failure(description: "isolated field error") }
            if denyAfterFirst, index == 1 { allowed = false }
        }

        func editor(selfProfile: Bool = false) -> PeerProfileEditViewController {
            let mode: PeerProfileEditViewController.Mode = selfProfile
                ? .selfProfile(userID: 77, firstName: "Original", lastName: "Name", bio: "old bio")
                : .chat(chatID: 8, title: "Original", description: "old description")
            let editor = PeerProfileEditViewController(session: session, mode: mode)
            retention.editor = editor
            navigation.setViewControllers([navigation.viewControllers[0], parent, editor], animated: false)
            editor.loadViewIfNeeded()
            navigation.view.layoutIfNeeded()
            editor.view.layoutIfNeeded()
            return editor
        }

        @discardableResult func replace(_ id: Int32 = 711) -> TdUpdateSource {
            ready.send(nil)
            let next = TdUpdateSource(accountID: first.accountID, clientID: id)
            current = next
            clients.send(next)
            ready.send(next)
            return next
        }

        func close() {
            authorizationGate?.release()
            writeGate?.release()
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private struct PromptGeometry {
        let barMaxY: CGFloat
        let safeMinY: CGFloat
        let fieldMinY: CGFloat

        var summary: String { "bar=\(barMaxY),safe=\(safeMinY),field=\(fieldMinY)" }
    }

    static func runIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("-ui-probe-navigation-prompt") {
            Task { await runFocusedPromptProbe() }
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-edit-session") else { return }
        Task {
            let result: String
            do {
                try await until("window scene did not attach") {
                    UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
                }
                try await verifyRetainedFields()
                try await verifyAttemptBoundaries()
                try await verifyPartialSuccess()
                try await verifyOwnersAndAccounts()
                result = "Profile edit session probe passed: actual-UIKit-editor/production-retention-helper/field-selection=true; "
                    + "same-account-ready/stale-ready/immutable-payload-client/preflight/dispatch/partial-baselines=true; "
                    + "fresh-A27-before-each-write/late-ACK-error/typing-revision/detached-owner/account-actor-revoke=true; "
                    + "server-writes=0; native-foreground/RootVM/actual-profile-parent/keyboard-IME=unverified"
            } catch {
                result = "Profile edit session probe failed: \(error)"
            }
            log(result)
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("profile-edit-session-probe.txt"),
                    options: .atomic,
                )
            }
        }
    }

    private static func runFocusedPromptProbe() async {
        var samples = [String]()
        let result: String
        do {
            try await until("original key window did not attach") {
                UIApplication.shared
.connectedScenes
.compactMap { $0 as? UIWindowScene }
                    .contains { $0.windows.contains(where: \.isKeyWindow) }
            }
            try await verifyFocusedPrompt(samples: &samples)
            result = "Navigation prompt probe passed: actual-classic-navbar/retained-editor/focused-field=true; "
                + "same-client-readiness/client-replacement/retained-stack-replacement/duplicate-ready/three-delayed-samples=true; "
                + "bar-safe-field-nonoverlap/text-selection/stack-owner=true; server-writes=0; "
                + "native-background-foreground/IME/other-sizes=unverified"
        } catch {
            result = "Navigation prompt probe failed: \(error)"
        }
        let report = ([result] + samples).joined(separator: "\n")
        log(report)
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? Data(report.utf8).write(
                to: documents.appendingPathComponent("navigation-prompt-probe.txt"), options: .atomic,
            )
        }
    }

    private static func settledPromptGeometry(
        _ fixture: Fixture, editor: PeerProfileEditViewController, field: UITextField,
        phase: String, samples: inout [String],
    ) async throws -> PromptGeometry {
        // Read after the transition, not only from the editor's last layout callback.
        // Do not mark or force layout here: this baseline must expose missing invalidation.
        try await Task.sleep(for: .milliseconds(500))
        var result: PromptGeometry?
        for index in 0..<3 {
            let bar = fixture.navigation.navigationBar
            let geometry = PromptGeometry(
                barMaxY: bar.convert(bar.bounds, to: fixture.window).maxY,
                safeMinY: editor.view.convert(editor.view.safeAreaLayoutGuide.layoutFrame, to: fixture.window).minY,
                fieldMinY: field.convert(field.bounds, to: fixture.window).minY,
            )
            samples.append("\(phase)[\(index)]: \(geometry.summary); focused=\(field.isFirstResponder)")
            try require(fixture.window.isKeyWindow && field.isFirstResponder, "\(phase): lost actual editor focus")
            try require(
                bar.bounds.width > 0 && abs(geometry.barMaxY - geometry.safeMinY) <= 1
                && geometry.fieldMinY >= geometry.barMaxY,
                "\(phase): settled bar/safe/field overlap",
            )
            if let result {
                try require(
                    abs(result.barMaxY - geometry.barMaxY) <= 1
                    && abs(result.fieldMinY - geometry.fieldMinY) <= 1,
                    "\(phase): geometry did not settle",
                )
            }
            result = geometry
            if index < 2 { try await Task.sleep(for: .milliseconds(50)) }
        }
        guard let result else { throw Failure(description: "missing geometry samples") }
        return result
    }

    private static func verifyFocusedPrompt(samples: inout [String]) async throws {
        let f = try Fixture(classicNavigation: true)
        let previousKey = f.window.windowScene?.windows.first(where: \.isKeyWindow)
        defer {
            f.window.endEditing(true)
            f.close()
            previousKey?.makeKey()
        }
        let editor = f.editor(selfProfile: true), (fields, _) = try fields(editor)
        let field = fields[0]
        guard let scene = f.window.windowScene else { throw Failure(description: "missing fixture scene") }
        f.window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        f.window.makeKeyAndVisible()
        change(field, "")
        try require(field.becomeFirstResponder(), "fixture field rejected focus")
        field.insertText("Kept fixture")
        guard let start = field.position(from: field.beginningOfDocument, offset: 2),
              let end = field.position(from: field.beginningOfDocument, offset: 7)
        else { throw Failure(description: "missing fixture selection positions") }
        field.selectedTextRange = field.textRange(from: start, to: end)
        let baseline = try await settledPromptGeometry(
            f,
            editor: editor,
            field: field,
            phase: "initial",
            samples: &samples,
        )
        for cycle in 0..<3 {
            f.ready.send(nil)
            try require(
                editor.navigationItem.prompt != nil && f.session.state == .waiting,
                "waiting prompt was not installed",
            )
            let waiting = try await settledPromptGeometry(
                f,
                editor: editor,
                field: field,
                phase: "waiting-\(cycle)",
                samples: &samples,
            )
            try require(waiting.barMaxY > baseline.barMaxY + 1, "waiting prompt never expanded actual bar")
            if cycle > 0 {
                let next = TdUpdateSource(accountID: f.first.accountID, clientID: Int32(718 + cycle))
                f.current = next
                f.clients.send(next)
            }
            if cycle == 2 {
                f.navigation.setViewControllers([UIViewController(), f.parent, editor], animated: false)
                try require(
                    f.navigation.viewControllers.count == 3
                    && f.navigation.viewControllers[1] === f.parent
                    && f.navigation.topViewController === editor,
                    "stack replacement lost exact retained owners",
                )
            }
            f.ready.send(f.current)
            try require(
                editor.navigationItem.prompt == nil && f.session.state == .ready,
                "ready prompt was not cleared",
            )
            let ready = try await settledPromptGeometry(
                f,
                editor: editor,
                field: field,
                phase: "ready-\(cycle)",
                samples: &samples,
            )
            try require(
                abs(ready.barMaxY - baseline.barMaxY) <= 1
                && abs(ready.fieldMinY - baseline.fieldMinY) <= 1,
                "ready did not restore baseline geometry",
            )
            try require(
                f.navigation.topViewController === editor && f.writes.isEmpty && field.text == "Kept fixture"
                && field.selectedTextRange.map { field.offset(from: $0.start, to: $0.end) } == 5,
                "prompt transition changed editor/text/selection or dispatched",
            )
        }
        f.ready.send(f.current)
        _ = try await settledPromptGeometry(
            f,
            editor: editor,
            field: field,
            phase: "duplicate-ready",
            samples: &samples,
        )
    }

    private static func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private static func fields(_ editor: PeerProfileEditViewController) throws -> ([UITextField], UITextView) {
        let all = descendants(editor.view)
        guard let detail = all.compactMap({ $0 as? UITextView }).first
            else { throw Failure(description: "missing detail view") }
        let fields = all.compactMap { $0 as? UITextField }
        try require(fields.count == 2, "missing actual fields")
        return (fields, detail)
    }

    private static func change(_ field: UITextField, _ value: String) {
        field.text = value
        field.sendActions(for: .editingChanged)
    }

    private static func change(_ field: UITextView, _ value: String) {
        field.text = value
        field.delegate?.textViewDidChange?(field)
    }

    private static func press(_ editor: PeerProfileEditViewController) throws {
        guard let item = editor.navigationItem.rightBarButtonItem, let action = item.action,
              let target = item.target as? NSObject else { throw Failure(description: "missing Save action") }
        _ = target.perform(action, with: item)
    }

    private static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(description: reason) }
    }

    private static func drain() async {
        for _ in 0..<6 {
            await Task.yield()
        }
    }

    private static func until(_ reason: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(description: "timeout: \(reason)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func verifyRetainedFields() async throws {
        let f = try Fixture()
        defer { f.close() }
        let editor = f.editor(selfProfile: true), (fields, detail) = try fields(editor)
        change(fields[0], " Draft 👋 ")
        change(fields[1], " Last ")
        change(detail, "bio\nkept")
        fields[0].selectedTextRange = fields[0].textRange(
            from: fields[0].beginningOfDocument,
            to: fields[0].endOfDocument,
        )
        detail.selectedRange = NSRange(location: 1, length: 2)
        f.ready.send(nil)
        try require(
            f.session.state == .waiting && editor.navigationItem.rightBarButtonItem?.isEnabled == false,
            "not waiting",
        )
        let next = f.replace()
        f.ready.send(f.first)
        try require(f.session.state == .waiting, "stale Ready admitted")
        f.ready.send(next)
        try require(
            f.navigation.topViewController === editor && fields[0].text == " Draft 👋 "
            && fields[1].text == " Last " && detail.text == "bio\nkept"
            && fields[0].selectedTextRange?.isEmpty == false && detail.selectedRange == NSRange(location: 1, length: 2),
            "rollover lost actual editor fields/selection",
        )
        try require(
            f.retention.shouldRetain(
                parent: f.parent,
                accountID: f.first.accountID,
                currentAccountID: f.current?.accountID,
            ),
            "owned editor did not retain parent stack",
        )
        try press(editor)
        try await until("new-client save") { editor.persistedFieldsForProbe == ["Draft 👋", "Last", "bio kept"] }
        try require(f.writes.map(\.0) == [next, next], "save client changed between fields")
        try await until("save pop") { f.navigation.topViewController === f.parent }
        try require(
            !f.retention.shouldRetain(
                parent: f.parent,
                accountID: f.first.accountID,
                currentAccountID: f.first.accountID,
            ),
            "removed editor retained stale profile",
        )
    }

    private static func verifyAttemptBoundaries() async throws {
        do {
            let f = try Fixture()
            defer { f.close() }
            let editor = f.editor(), (fields, _) = try fields(editor)
            change(fields[0], "queued")
            try press(editor)
            f.replace()
            await drain()
            try require(f.writes.isEmpty && f.session.state == .ready, "pre-dispatch rollover sent or wedged")
        }
        do {
            let f = try Fixture()
            defer { f.close() }
            f.authorizationGate = Gate()
            let editor = f.editor(), (fields, _) = try fields(editor)
            change(fields[0], "old intent")
            try press(editor)
            try await until("permission read") { f.authorizationGate?.continuation != nil }
            let next = f.replace()
            change(fields[0], "replacement")
            try press(editor)
            try await until("new intent saved") { editor.persistedFieldsForProbe[0] == "replacement" }
            f.authorizationGate?.release()
            await drain()
            try require(
                f.writes.count == 1 && f.writes[0].0 == next && editor.persistedFieldsForProbe[0] == "replacement",
                "old permission result wrote or changed baseline",
            )
        }
        for fail in [false, true] {
            let f = try Fixture()
            defer { f.close() }
            f.writeGate = Gate()
            if fail { f.failWrites = [1] }
            let editor = f.editor(), (fields, detail) = try fields(editor)
            change(fields[0], "pending")
            change(detail, "second field")
            try press(editor)
            try await until("native write") { f.writeGate?.continuation != nil }
            try press(editor)
            f.replace()
            f.writeGate?.release()
            await drain()
            try require(
                f.session.state == .uncertain && f.writes.count == 1
                && editor.persistedFieldsForProbe == ["Original", "", "old description"]
                && f.navigation.topViewController === editor && fields[0].text == "pending",
                "retired ACK/error changed draft/baseline",
            )
            try press(editor)
            await drain()
            try require(f.writes.count == 1, "uncertain save automatically retried")
        }
        do {
            let f = try Fixture()
            defer { f.close() }
            f.authorizationGate = Gate()
            f.authorizationGateAt = 2
            let editor = f.editor(), (fields, detail) = try fields(editor)
            change(fields[0], "first saved")
            change(detail, "not sent")
            try press(editor)
            try await until("second authorization") { f.authorizationGate?.continuation != nil }
            try require(editor.persistedFieldsForProbe[0] == "first saved", "accepted first baseline lost")
            f.replace()
            f.authorizationGate?.release()
            await drain()
            try require(
                f.session.state == .uncertain && f.writes.count == 1
                && editor.persistedFieldsForProbe == ["first saved", "", "old description"],
                "rollover after partial save sent field2",
            )
        }
        do {
            let f = try Fixture()
            defer { f.close() }
            f.writeGate = Gate()
            let editor = f.editor(), (fields, _) = try fields(editor)
            change(fields[0], "issued")
            try press(editor)
            try await until("typing write") { f.writeGate?.continuation != nil }
            change(fields[0], "new typing")
            f.writeGate?.release()
            try await until("typing ACK") { f.session.state == .ready }
            try require(
                f.navigation.topViewController === editor && fields[0].text == "new typing"
                && editor.persistedFieldsForProbe[0] == "issued",
                "late success discarded typing",
            )
        }
    }

    private static func verifyPartialSuccess() async throws {
        for selfProfile in [false, true] {
            let f = try Fixture()
            defer { f.close() }
            if selfProfile { f.failWrites = [2] } else { f.denyAfterFirst = true }
            let editor = f.editor(selfProfile: selfProfile), (fields, detail) = try fields(editor)
            change(fields[0], "saved title")
            change(detail, "retry detail")
            try press(editor)
            try await until("partial result") { f.session.state == .ready }
            try require(
                editor.persistedFieldsForProbe[0] == "saved title" && editor.persistedFieldsForProbe[2] != "retry detail"
                && f.navigation.topViewController === editor,
                "partial save lost baseline/editor",
            )
            if !selfProfile {
                try require(f.authorizationReads == 2 && f.writes.count == 1, "missing fresh field2 permission")
            }
            f.failWrites = []
            f.allowed = true
            f.denyAfterFirst = false
            let priorWrites = f.writes.count
            try press(editor)
            try await until("detail retry") { editor.persistedFieldsForProbe[2] == "retry detail" }
            try require(f.writes.count == priorWrites + 1, "retry repeated accepted first field")
        }
    }

    private static func verifyOwnersAndAccounts() async throws {
        for dispatched in [false, true] {
            let f = try Fixture()
            defer { f.close() }
            if dispatched { f.writeGate = Gate() } else { f.authorizationGate = Gate() }
            let editor = f.editor(), (fields, _) = try fields(editor)
            change(fields[0], "detached")
            try press(editor)
            try await until("owner suspension") {
                dispatched ? f.writeGate?.continuation != nil : f.authorizationGate?.continuation != nil
            }
            let replacement = UIViewController()
            f.window.rootViewController = replacement
            f.window.addSubview(f.navigation.view)
            try require(
                editor.view.window != nil && !PeerProfileEditSession.isAttached(editor),
                "retained detached pixels admitted owner",
            )
            try require(
                !f.retention
                    .shouldRetain(parent: f.parent, accountID: f.first.accountID, currentAccountID: f.first.accountID),
                "detached subtree retained profile",
            )
            f.writeGate?.release()
            f.authorizationGate?.release()
            await drain()
            try require(
                f.writes.count == (dispatched ? 1 : 0) && editor.persistedFieldsForProbe[0] == "Original",
                "detached completion changed baseline",
            )
            f.navigation.view.removeFromSuperview()
        }
        for wrongActor in [false, true] {
            let f = try Fixture()
            defer { f.close() }
            let editor = f.editor(), (fields, _) = try fields(editor)
            change(fields[0], "kept")
            if wrongActor {
                f.actor = 88
                f.accounts.send(())
            } else {
                let foreign = TdUpdateSource(accountID: UUID(), clientID: f.first.clientID)
                f.current = foreign
                f.clients.send(foreign)
                try require(
                    !f.retention
                        .shouldRetain(
                            parent: f.parent,
                            accountID: f.first.accountID,
                            currentAccountID: foreign.accountID,
                        ),
                    "foreign account retained editor",
                )
            }
            f.current = f.first
            f.actor = 77
            f.clients.send(f.first)
            f.ready.send(f.first)
            f.accounts.send(())
            try press(editor)
            await drain()
            try require(
                f.session.state == .revoked && f.writes.isEmpty && fields[0].text == "kept",
                "departed identity revived editor",
            )
            try require(
                !f.retention.shouldRetain(
                    parent: f.parent,
                    accountID: f.first.accountID,
                    currentAccountID: f.first.accountID,
                ),
                "revoked editor retained stale profile after returning identity",
            )
        }
    }
}
#endif
