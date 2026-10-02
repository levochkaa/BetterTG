// FolderFlowSessionProbe.swift

#if DEBUG
    import Combine
    import TDLibKitDynamic
    import UIKit

    @MainActor enum FolderFlowSessionProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Gate {
            var continuation: CheckedContinuation<Void, Never>?

            func wait() async { await withCheckedContinuation { continuation = $0 } }
            func release() {
                let value = continuation
                continuation = nil
                value?.resume()
            }
        }

        @MainActor private final class Fixture {
            let first = TdUpdateSource(accountID: UUID(), clientID: 801)
            let changes = PassthroughSubject<TdUpdateSource, Never>()
            let modelChanges = PassthroughSubject<Void, Never>()
            var ready = CurrentValueSubject<TdUpdateSource?, Never>(nil)
            var current: TdUpdateSource?
            var ownerAccount: UUID?
            var folders: [CustomFolder]
            var writes = [(TdUpdateSource, FolderFlowSession.Mutation)]()
            var gate: Gate?
            var fail = false
            let window: UIWindow
            let navigation = UINavigationController(rootViewController: UIViewController())
            lazy var session = FolderFlowSession(
                initialSource: first, currentSource: { [weak self] in self?.current },
                ownerAccount: { [weak self] in self?.ownerAccount },
                readiness: ready.eraseToAnyPublisher(), clientChanges: changes.eraseToAnyPublisher(),
                modelChanges: modelChanges.eraseToAnyPublisher(),
                folders: { [weak self] in self?.folders ?? [] },
                allFolders: { [weak self] in self?.folders ?? [] },
                resolve: { [weak self] source in
                    guard self != nil else { return nil }
                    return FolderFlowSession.Endpoint(source: source) { [weak self] mutation in
                        guard let self else { throw CancellationError() }
                        writes.append((source, mutation))
                        await gate?.wait()
                        if fail { throw Failure(description: "injected write error") }
                    }
                },
            )

            init() throws {
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                    throw Failure(description: "no attached window scene")
                }
                self.window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
                let folder = RootChatInsertionProbe.folder()
                folder.chats = [RootChatInsertionProbe.chat(
                    .init(isPinned: false, list: .chatListMain, order: .init(1), source: nil),
                    title: "Fixture Chat",
                )]
                self.folders = [CustomFolder(chats: [], type: .main), folder]
                self.current = first
                self.ownerAccount = first.accountID
                ready.send(first)
                window.rootViewController = navigation
                window.isHidden = false
                navigation.loadViewIfNeeded()
                navigation.view.layoutIfNeeded()
            }

            func show(_ controller: UIViewController) {
                navigation.setViewControllers([navigation.viewControllers[0], controller], animated: false)
                controller.loadViewIfNeeded()
                navigation.view.layoutIfNeeded()
                controller.view.layoutIfNeeded()
            }

            func replace(clientID: Int32) -> TdUpdateSource {
                let next = TdUpdateSource(accountID: first.accountID, clientID: clientID)
                ready.send(nil)
                current = next
                changes.send(next)
                ready.send(next)
                return next
            }

            func close() {
                gate?.release()
                window.isHidden = true
                window.rootViewController = nil
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-folder-flow") else { return }
            Task {
                let result: String
                do {
                    try await until(
                        { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } },
                        "window scene did not attach",
                    )
                    try await verifyEditorAndSelector()
                    try await verifyListAndOrder()
                    try await verifyMutationBoundaries()
                    try await verifySelectorSubmissionAndDetachment()
                    try await verifyRevocation()
                    result = "Folder flow probe passed: actual-session/list/editor/selector/order=true; "
                        + "same-account-ready/draft/name/rules/selection/query/order-preserved=true; "
                        + "stale-ready/scope/pre-dispatch/late-success-error/duplicate-submit=fenced; "
                        + "dispatched-create-edit-reorder-delete=uncertain; account-A-B-A=revoked; "
                        + "RootVM/native-client/real-foreground/keyboard=unverified; server-calls=0"
                } catch {
                    result = "Folder flow probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("folder-flow-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ value: Bool, _ message: String) throws {
            if !value { throw Failure(description: message) }
        }

        private static func until(_ condition: () -> Bool, _ message: String) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            while !condition() {
                guard ContinuousClock.now < deadline else { throw Failure(description: message) }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        private static func press(_ controller: UIViewController) throws {
            guard let button = controller.navigationItem.rightBarButtonItem,
                  let action = button.action, let target = button.target as? NSObject
            else {
                throw Failure(description: "missing actual bar action")
            }
            _ = target.perform(action, with: button)
        }

        private static func nameField(_ editor: ChatFolderEditorViewController) throws -> UITextField {
            guard let field = editor.tableView(editor.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
                .accessoryView as? UITextField else { throw Failure(description: "missing name field") }
            return field
        }

        private static func verifyEditorAndSelector() async throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let editor = ChatFolderEditorViewController(session: fixture.session)
            fixture.show(editor)
            let name = try nameField(editor)
            name.text = "kept draft"
            name.selectedTextRange = name.textRange(from: name.beginningOfDocument, to: name.endOfDocument)
            editor.tableView(editor.tableView, didSelectRowAt: IndexPath(row: 2, section: 1))
            let before = fixture.session.scope(owner: editor)
            try require(before.isCurrent, "initial scope denied")
            let replacement = fixture.replace(clientID: 802)
            fixture.ready.send(fixture.first)
            try require(!fixture.session.isCurrent && !before.isCurrent, "stale Ready admitted")
            fixture.ready.send(replacement)
            fixture.ready.send(replacement)
            try require(
                fixture.navigation.topViewController === editor && name.text == "kept draft"
                    && name.selectedTextRange.map { name.offset(from: $0.start, to: $0.end) } == 10
                    && !before.isCurrent && fixture.session.scope(owner: editor).isCurrent,
                "editor/name/selection lost or old scope rebound",
            )
            editor.tableView(editor.tableView, didSelectRowAt: IndexPath(row: 0, section: 2))
            try await until({ fixture.navigation.transitionCoordinator == nil }, "selector push did not settle")
            guard let picker = fixture.navigation.topViewController as? ChatFolderChatSelectionViewController else {
                throw Failure(description: "actual editor did not open selector")
            }
            picker.loadViewIfNeeded()
            picker.tableView(picker.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
            let search = picker.navigationItem.searchController!
            search.searchBar.text = "Fixture"
            picker.updateSearchResults(for: search)
            _ = fixture.replace(clientID: 803)
            try require(
                fixture.navigation.topViewController === picker && search.searchBar.text == "Fixture"
                    && picker.tableView(picker.tableView, numberOfRowsInSection: 0) == 1,
                "selector/query/candidates lost",
            )
            try press(picker)
            try await until({ fixture.navigation.transitionCoordinator == nil }, "selector pop did not settle")
            try require(
                fixture.navigation.topViewController === editor && name.text == "kept draft",
                "picker callback lost owner",
            )
            try press(editor)
            try await until({ fixture.writes.count == 1 }, "fresh editor did not dispatch")
            guard case .create(let draft) = fixture.writes[0].1 else {
                throw Failure(description: "wrong editor mutation")
            }
            try require(
                fixture.writes[0].0.clientID == 803 && draft.name.text.text == "kept draft"
                    && draft.includeGroups && draft.includedChatIds == [7],
                "draft/name/rules/selection changed during rollover",
            )
        }

        private static func verifyListAndOrder() async throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let list = ChatFoldersViewController(session: fixture.session)
            fixture.show(list)
            _ = fixture.replace(clientID: 804)
            try require(list.tableView(list.tableView, numberOfRowsInSection: 0) == 1, "folder list lost rows")
            list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
            try await until({ fixture.navigation.transitionCoordinator == nil }, "list editor push did not settle")
            guard let edit = fixture.navigation.topViewController as? ChatFolderEditorViewController else {
                throw Failure(description: "fresh list cannot open editor")
            }
            let editName = try nameField(edit)
            editName.text = "edited"
            _ = fixture.replace(clientID: 805)
            try press(edit)
            try await until({ fixture.writes.count == 1 }, "edit did not dispatch")
            guard case .edit(7, let draft) = fixture.writes[0].1
                else { throw Failure(description: "edit identity lost") }
            try require(draft.name.text.text == "edited", "edit text lost")
            try await until({ fixture.navigation.transitionCoordinator == nil }, "edit completion did not settle")

            let order = ChatFolderOrderViewController(session: fixture.session)
            fixture.show(order)
            order.tableView(
                order.tableView,
                moveRowAt: IndexPath(row: 1, section: 0),
                to: IndexPath(row: 0, section: 0),
            )
            _ = fixture.replace(clientID: 806)
            try press(order)
            try await until({ fixture.writes.count == 2 }, "order did not dispatch")
            guard case .reorder(let ids, let mainPosition) = fixture.writes[1].1 else {
                throw Failure(description: "wrong reorder mutation")
            }
            try require(
                ids == [7] && mainPosition == 1 && fixture.writes[1].0.clientID == 806,
                "order lost at rollover",
            )
        }

        private static func verifyMutationBoundaries() async throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let editor = ChatFolderEditorViewController(session: fixture.session)
            fixture.show(editor)
            var completions = 0
            fixture.session.mutate(.delete(7), owner: editor) { _ in completions += 1 }
            _ = fixture.replace(clientID: 807)
            await Task.yield()
            await Task.yield()
            try require(
                fixture.writes.isEmpty && completions == 0 && fixture.session.isCurrent,
                "pre-dispatch rollover sent or wedged",
            )

            let folder = RootChatInsertionProbe.folder()
            guard case .folder(_, let definition) = folder.type
                else { throw Failure(description: "bad folder fixture") }
            let mutations: [FolderFlowSession.Mutation] = [
                .create(definition),
                .edit(7, definition),
                .reorder([7], 0),
                .delete(7),
            ]
            for (index, mutation) in mutations.enumerated() {
                for fails in [false, true] {
                    let current = try Fixture()
                    defer { current.close() }
                    current.gate = Gate()
                    current.fail = fails
                    let owner = ChatFolderEditorViewController(session: current.session)
                    current.show(owner)
                    let text = try nameField(owner)
                    text.text = "unsent kept"
                    var delivered = 0
                    current.session.mutate(mutation, owner: owner) { _ in delivered += 1 }
                    try await until({ current.gate?.continuation != nil }, "write did not suspend")
                    current.session.mutate(mutation, owner: owner) { _ in delivered += 1 }
                    let next: TdUpdateSource
                    if fails {
                        current.ready.send(nil)
                        next = current.first
                        current.ready.send(next)
                    } else {
                        next = current.replace(clientID: Int32(810 + index))
                    }
                    current.ready.send(next)
                    current.modelChanges.send(())
                    try require(
                        current.session.state == .uncertain && owner.navigationItem.rightBarButtonItem?
                            .isEnabled == false
                            && owner.navigationItem.prompt?.contains("unknown") == true && text.text == "unsent kept",
                        "dispatched rollover did not retain explicit uncertainty",
                    )
                    current.gate?.release()
                    for _ in 0..<12 {
                        await Task.yield()
                    }
                    current.session.mutate(mutation, owner: owner) { _ in delivered += 1 }
                    try require(
                        current.writes.count == 1 && delivered == 0 && current.session.state == .uncertain,
                        "late ACK/error enabled duplicate mutation",
                    )
                }
            }
        }

        private static func verifySelectorSubmissionAndDetachment() async throws {
            for fails in [false, true] {
                let fixture = try Fixture()
                defer { fixture.close() }
                guard case .folder(_, let definition) = fixture.folders[1].type else {
                    throw Failure(description: "bad edit fixture")
                }
                let selector = ChatFolderChatSelectionViewController(
                    session: fixture.session, title: "Add Chats", selectedChatIDs: [7],
                ) { selector, ids in
                    selector.submitFolderEdit(id: 7, folder: definition.replacingIncludedChatIDs(ids))
                    return false
                }
                fixture.show(selector)
                fixture.gate = Gate()
                fixture.fail = fails
                _ = fixture.replace(clientID: 825)
                try press(selector)
                try press(selector)
                try await until({ fixture.gate?.continuation != nil }, "selector edit not dispatched")
                try require(
                    fixture.navigation.topViewController === selector && fixture.writes.count == 1,
                    "selector popped before ACK or double submitted",
                )
                if fails {
                    _ = fixture.replace(clientID: 826)
                    fixture.gate?.release()
                    for _ in 0..<12 {
                        await Task.yield()
                    }
                    try require(
                        fixture.navigation.topViewController === selector && fixture.session.state == .uncertain
                            && selector.presentedViewController == nil,
                        "late failed selector write popped/resumed/presented",
                    )
                } else {
                    fixture.gate?.release()
                    try await until(
                        { fixture.navigation.topViewController !== selector },
                        "accepted selector write did not pop",
                    )
                }
            }

            let detached = try Fixture()
            defer { detached.close() }
            let editor = ChatFolderEditorViewController(session: detached.session)
            detached.show(editor)
            detached.gate = Gate()
            var completions = 0
            detached.session.mutate(.delete(7), owner: editor) { _ in completions += 1 }
            try await until({ detached.gate?.continuation != nil }, "detached write not dispatched")
            detached.navigation.setViewControllers([detached.navigation.viewControllers[0]], animated: false)
            detached.gate?.release()
            try await until({ detached.session.state == .ready }, "detached terminal did not settle")
            detached.session.mutate(.delete(7), owner: editor) { _ in completions += 1 }
            await Task.yield()
            try require(
                completions == 0 && detached.writes.count == 1,
                "detached owner received completion or resubmitted",
            )
        }

        private static func verifyRevocation() async throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let editor = ChatFolderEditorViewController(session: fixture.session)
            fixture.show(editor)
            let original = fixture.session.scope(owner: editor)
            let other = TdUpdateSource(accountID: UUID(), clientID: fixture.first.clientID)
            fixture.current = other
            fixture.ownerAccount = other.accountID
            fixture.changes.send(other)
            fixture.current = fixture.first
            fixture.ownerAccount = fixture.first.accountID
            fixture.changes.send(fixture.first)
            fixture.ready.send(fixture.first)
            try require(
                fixture.session.state == .revoked && !original.isCurrent && fixture.navigation.viewControllers
                    .count == 1,
                "A-B-A revived or retained editor",
            )
            fixture.session.mutate(.delete(7), owner: editor) { _ in }
            await Task.yield()
            try require(fixture.writes.isEmpty, "revoked owner dispatched")

            let ownerMismatch = try Fixture()
            defer { ownerMismatch.close() }
            ownerMismatch.ownerAccount = UUID()
            ownerMismatch.modelChanges.send(())
            try require(!ownerMismatch.session.isCurrent, "Root account mismatch admitted")
            ownerMismatch.ownerAccount = ownerMismatch.first.accountID
            ownerMismatch.modelChanges.send(())
            try require(ownerMismatch.session.isCurrent, "matching Root model did not resume readiness")
        }
    }
#endif
