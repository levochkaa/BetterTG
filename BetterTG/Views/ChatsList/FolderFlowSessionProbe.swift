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

        @MainActor private final class FolderModel: ObservableObject {
            @Published var folders: [CustomFolder]

            init(_ folders: [CustomFolder]) { self.folders = folders }
        }

        @MainActor private final class Fixture {
            let first = TdUpdateSource(accountID: UUID(), clientID: 801)
            let changes = PassthroughSubject<TdUpdateSource, Never>()
            let modelChanges = PassthroughSubject<Void, Never>()
            var ready = CurrentValueSubject<TdUpdateSource?, Never>(nil)
            var current: TdUpdateSource?
            var ownerAccount: UUID?
            let folderModel: FolderModel
            var writes = [(TdUpdateSource, FolderFlowSession.Mutation)]()
            var gate: Gate?
            var fail = false
            let window: UIWindow
            let navigation = UINavigationController(rootViewController: UIViewController())
            lazy var session = FolderFlowSession(
                initialSource: first, currentSource: { [weak self] in self?.current },
                ownerAccount: { [weak self] in self?.ownerAccount },
                readiness: ready.eraseToAnyPublisher(), clientChanges: changes.eraseToAnyPublisher(),
                modelChanges: modelChanges.merge(with: folderModel.objectWillChange.receive(on: DispatchQueue.main))
                    .eraseToAnyPublisher(),
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

            var folders: [CustomFolder] {
                get { folderModel.folders }
                set { folderModel.folders = newValue }
            }

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
                self.folderModel = FolderModel([CustomFolder(chats: [], type: .main), folder])
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
                    try verifySelectorPresentation()
                    try await verifySelectorPresentationUpdates()
                    try await verifySelectorMembershipUpdates()
                    try await verifyListAndOrder()
                    try await verifyMutationBoundaries()
                    try await verifyControllerMembership()
                    try await verifySelectorSubmissionAndDetachment()
                    try await verifyRevocation()
                    result = "Folder flow probe passed: actual-session/list/editor/selector/order=true; "
                        + "same-account-ready/draft/name/rules/selection/query/order-preserved=true; "
                        + "stale-ready/scope/pre-dispatch/late-success-error/duplicate-submit=fenced; "
                        + "root/navigation/page/modal-membership=true; popped-pixels/detached-subtree=denied; "
                        + "selector-order-done-text/plain-style/AX/action/disabled-readiness=true; "
                        + "selector-deleted/unknown/contact/fallback/sort/search/reuse/selection/scoped-updates=true; "
                        + "unread-last-position/shuffled-input=no-presentation-reload; equal-title-order=stable; "
                        + "actual-child-publishers/append/remove/same-ID-replacement/retired-subscriptions=true; "
                        + "child-source/detach-fences=true; membership-manual-wakeup=none; "
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

        private static func verifyDoneItem(_ controller: UIViewController, action: String, enabled: Bool) throws {
            guard let item = controller.navigationItem.rightBarButtonItem else {
                throw Failure(description: "missing Done item")
            }
            try require(
                item.title == "Done" && item.style == .plain && item.image == nil
                    && item.accessibilityLabel == "Done" && (item.target as? UIViewController) === controller
                    && item.action == NSSelectorFromString(action) && item.isEnabled == enabled,
                "Done title/style/AX/target/action/enabled changed",
            )
        }

        private static func pickerUser(
            id: Int64, type: UserType = .userTypeRegular, first: String = "", last: String = "",
            contact: Bool = false, username: String? = nil, phone: String = "",
        ) -> User {
            User(
                accentColorId: -1, activeStoryState: nil, addedToAttachmentMenu: false, backgroundCustomEmojiId: 0,
                emojiStatus: nil, firstName: first, haveAccess: true, id: id, isCloseFriend: false, isContact: contact,
                isMutualContact: false, isPremium: false, isSupport: false, languageCode: "", lastName: last,
                paidMessageStarCount: 0, phoneNumber: phone, profileAccentColorId: -1,
                profileBackgroundCustomEmojiId: 0,
                profilePhoto: nil, restrictionInfo: nil, restrictsNewChats: false, status: .userStatusEmpty, type: type,
                upgradedGiftColors: nil,
                usernames: username.map { .init(
                    activeUsernames: [$0],
                    collectibleUsernames: [],
                    disabledUsernames: [],
                    editableUsername: $0,
                ) },
                verificationStatus: nil,
            )
        }

        private static func pickerChat(id: Int64, title: String = "", user: User? = nil) -> CustomChat {
            RootChatInsertionProbe.chat(
                .init(isPinned: false, list: .chatListMain, order: 1, source: nil), title: title, id: id, user: user,
            )
        }

        private static func rows(_ picker: ChatFolderChatSelectionViewController) -> [UITableViewCell] {
            (0..<picker.tableView(picker.tableView, numberOfRowsInSection: 0)).map {
                picker.tableView(picker.tableView, cellForRowAt: IndexPath(row: $0, section: 0))
            }
        }

        private static func search(_ picker: ChatFolderChatSelectionViewController, _ text: String) {
            let controller = picker.navigationItem.searchController!
            controller.searchBar.text = text
            picker.updateSearchResults(for: controller)
        }

        private static func verifySelectorPresentation() throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let deleted = pickerChat(id: 101, user: pickerUser(id: 101, type: .userTypeDeleted))
            let unknown = pickerChat(id: 102, user: pickerUser(id: 102, type: .userTypeUnknown))
            let botType = UserType.userTypeBot(.init(
                activeUserCount: 0, allowsUsersToCreateTopics: false, canBeAddedToAttachmentMenu: false,
                canBeEdited: false, canConnectToBusiness: false, canJoinGroups: false, canManageBots: false,
                canReadAllGroupMessages: false, hasMainWebApp: false, hasTopics: false, inlineQueryPlaceholder: "",
                isGuard: false, isInline: false, needLocation: false, supportsGuestQueries: false,
            ))
            let channel = pickerChat(id: 113)
            channel.type = .supergroup(.init(
                activeStoryState: nil, boostLevel: 0, date: 0, hasAutomaticTranslation: false,
                hasDirectMessagesGroup: false, hasForumTabs: false, hasLinkedChat: false, hasLocation: false,
                id: 113, isAdministeredDirectMessagesGroup: false, isBroadcastGroup: false, isChannel: true,
                isDirectMessagesGroup: false, isForum: false, isSlowModeEnabled: false, joinByRequest: false,
                joinToSendMessages: false, memberCount: 0, paidMessageStarCount: 0, restrictionInfo: nil,
                showMessageSender: false, signMessages: false,
                status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
                usernames: nil, verificationStatus: nil,
            ))
            let cases: [(CustomChat, String, String?)] = [
                (deleted, "Deleted Account", nil), (unknown, "Unknown User", nil),
                (
                    pickerChat(id: 103, user: pickerUser(id: 103, first: "Alpha", last: "Person")),
                    "Alpha Person",
                    "Non-Contact",
                ),
                (
                    pickerChat(id: 104, title: "Valid Contact", user: pickerUser(id: 104, contact: true)),
                    "Valid Contact",
                    "Contact",
                ),
                (
                    pickerChat(id: 105, title: "Valid Non-Contact", user: pickerUser(id: 105)),
                    "Valid Non-Contact",
                    "Non-Contact",
                ),
                (pickerChat(id: 106, user: pickerUser(id: 106, username: "fixture")), "@fixture", "Non-Contact"),
                (pickerChat(id: 107, user: pickerUser(id: 107, phone: "1234567")), "1234567", "Non-Contact"),
                (pickerChat(id: 108, user: pickerUser(id: 108)), "User", "Non-Contact"),
                (pickerChat(id: 109), "Untitled Group", "Group"),
                (pickerChat(id: 110, title: "Saved Messages"), "Saved Messages", "Group"),
                (pickerChat(id: 111, user: pickerUser(id: 111, type: botType)), "Bot", "Bot"),
                (
                    pickerChat(id: 112, title: " \n", user: pickerUser(id: 112, last: "Surname")),
                    "Surname",
                    "Non-Contact",
                ),
                (channel, "Untitled Channel", "Channel"),
                (pickerChat(id: 114, user: pickerUser(id: 114, type: .userTypeDeleted)), "Deleted Account", nil),
            ]
            fixture.folders[1].chats = cases.reversed().map(\.0)
            var selected: Set<Int64>?
            let picker = ChatFolderChatSelectionViewController(
                session: fixture.session,
                title: "Fixture",
                selectedChatIDs: [101],
            ) {
                _, ids in selected = ids
                return true
            }
            fixture.show(picker)
            let beforeShuffle = picker.candidatePresentationReloadsForProbe
            fixture.folders[1].chats = cases.map(\.0)
            fixture.modelChanges.send(())
            try require(
                picker.candidatePresentationReloadsForProbe == beforeShuffle,
                "unchanged shuffled input reloaded selector",
            )
            let expected = cases.sorted {
                let comparison = $0.1.localizedCaseInsensitiveCompare($1.1)
                return comparison == .orderedSame ? $0.0.id < $1.0.id : comparison == .orderedAscending
            }
            let actual = rows(picker)
            try require(
                actual.map { $0.textLabel?.text } == expected.map { Optional($0.1) },
                "selector fallback/sort mismatch",
            )
            for (row, item) in zip(actual, expected) {
                try require(row.detailTextLabel?.text == item.2, "selector contact/type subtitle mismatch")
                try require(
                    row.accessoryType == (item.0.id == 101 ? .checkmark : .none),
                    "fallback changed selection identity",
                )
            }
            let reused = UITableViewCell(style: .subtitle, reuseIdentifier: "FolderChatCell")
            picker.configurePickerCell(reused, chat: cases[3].0)
            try require(reused.detailTextLabel?.text == "Contact", "reuse fixture did not bind contact")
            picker.configurePickerCell(reused, chat: deleted)
            try require(
                reused.textLabel?.text == "Deleted Account" && reused.detailTextLabel?.text == nil
                && reused.accessoryType == .checkmark,
                "reuse retained subtitle or dropped selection",
            )
            picker.configurePickerCell(reused, chat: unknown)
            try require(
                reused.textLabel?.text == "Unknown User" && reused.detailTextLabel?.text == nil
                && reused.accessoryType == .none,
                "unknown reused deleted selection",
            )
            search(picker, "deleted")
            try require(
                rows(picker).map { $0.textLabel?.text } == ["Deleted Account", "Deleted Account"],
                "fallback title not searchable",
            )
            picker.tableView(picker.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
            search(picker, "unknown")
            try require(
                rows(picker).map { $0.textLabel?.text } == ["Unknown User"],
                "unknown mislabeled or unsearchable",
            )
            picker.tableView(picker.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
            try press(picker)
            try require(selected == [102] && fixture.writes.isEmpty, "fallback changed submitted IDs or sent RPC")
        }

        private static func verifySelectorPresentationUpdates() async throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let chat = pickerChat(id: 201, user: pickerUser(id: 201, type: .userTypeUnknown))
            fixture.folders[1].chats = [chat]
            var completions = 0
            let picker = ChatFolderChatSelectionViewController(
                session: fixture.session,
                title: "Fixture",
                selectedChatIDs: [201],
            ) {
                _, _ in completions += 1
                return true
            }
            fixture.show(picker)
            let initialReloads = picker.candidatePresentationReloadsForProbe
            chat.unreadCount = 7
            chat.lastMessage = nil
            chat.position = .init(isPinned: false, list: .chatListMain, order: 2, source: nil)
            try await Task.sleep(for: .milliseconds(50))
            try require(
                picker.candidatePresentationReloadsForProbe == initialReloads,
                "non-presentation update reloaded selector",
            )
            chat.updatePrivateUser(pickerUser(id: 201, first: "Resolved", contact: true))
            try await until({
                picker.tableView.layoutIfNeeded()
                let row = picker.tableView.cellForRow(at: IndexPath(row: 0, section: 0))
                return row?.textLabel?.text == "Resolved" && row?.detailTextLabel?.text == "Contact"
                    && row?.accessoryType == .checkmark
            }, "accepted user update did not refresh actual selector row")
            search(picker, "Resolved")
            chat.chat = pickerChat(id: 201, title: "Renamed", user: pickerUser(id: 201)).chat
            try await until({ rows(picker).isEmpty }, "accepted title update did not refresh search")
            fixture.navigation.popViewController(animated: false)
            chat.chat = pickerChat(id: 201, title: "Resolved", user: pickerUser(id: 201)).chat
            try await Task.sleep(for: .milliseconds(50))
            fixture.show(picker)
            try require(
                rows(picker).map { $0.textLabel?.text } == ["Resolved"],
                "returning selector kept offscreen presentation",
            )
            chat.chat = pickerChat(id: 201, title: "Renamed", user: pickerUser(id: 201)).chat
            try await until({ rows(picker).isEmpty }, "reopened selector did not observe title")
            fixture.ready.send(nil)
            chat.chat = pickerChat(id: 201, title: "Resolved", user: pickerUser(id: 201)).chat
            try await Task.sleep(for: .milliseconds(50))
            try require(rows(picker).isEmpty, "retired candidate subscription refreshed selector")
            _ = fixture.replace(clientID: 840)
            try require(
                rows(picker).map { $0.textLabel?.text } == ["Resolved"],
                "fresh source did not refresh preserved query",
            )
            fixture.window.rootViewController = UIViewController()
            fixture.window.addSubview(fixture.navigation.view)
            chat.chat = pickerChat(id: 201, title: "Detached", user: pickerUser(id: 201)).chat
            try await Task.sleep(for: .milliseconds(50))
            try require(
                picker.tableView(picker.tableView, numberOfRowsInSection: 0) == 1,
                "detached owner accepted candidate update",
            )
            try press(picker)
            try require(completions == 0 && fixture.writes.isEmpty, "detached updated selector completed")
            fixture.navigation.view.removeFromSuperview()
        }

        private static func verifySelectorMembershipUpdates() async throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let folder = fixture.folders[1]
            let alpha = pickerChat(id: 301, title: "Alpha")
            let beta = pickerChat(id: 302, title: "Beta")
            let charlie = pickerChat(id: 303, title: "Charlie")
            folder.chats = [alpha, charlie]
            var selected: Set<Int64>?
            let picker = ChatFolderChatSelectionViewController(
                session: fixture.session, title: "Membership", selectedChatIDs: [301],
            ) { _, ids in
                selected = ids
                return true
            }
            fixture.show(picker)
            search(picker, "a")
            // No modelChanges.send: these are the same child publishers RootChatInsertion mutates.
            folder.chats.append(beta)
            try await until({
                rows(picker).map { $0.textLabel?.text } == ["Alpha", "Beta", "Charlie"]
            }, "child append did not reach selector")
            picker.tableView(picker.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
            folder.chats.removeAll { $0.id == alpha.id }
            try await until({
                rows(picker).map { $0.textLabel?.text } == ["Beta", "Charlie"]
            }, "child remove did not reach selector")

            let sameID = pickerChat(id: 302, title: "Beta")
            let identityReloads = picker.candidatePresentationReloadsForProbe
            folder.chats = [charlie, sameID]
            try await Task.sleep(for: .milliseconds(50))
            try require(
                picker.candidatePresentationReloadsForProbe == identityReloads,
                "equal presentation identity replacement reloaded table",
            )
            beta.chat = pickerChat(id: 302, title: "Obsolete").chat
            try await Task.sleep(for: .milliseconds(50))
            try require(
                rows(picker).map { $0.textLabel?.text } == ["Beta", "Charlie"],
                "retired same-ID object remained bound",
            )
            sameID.chat = pickerChat(id: 302, title: "Bravo").chat
            try await until({
                picker.tableView.layoutIfNeeded()
                let row = picker.tableView.cellForRow(at: IndexPath(row: 0, section: 0))
                return row?.textLabel?.text == "Bravo" && row?.accessoryType == .checkmark
            }, "replacement object publisher or selected ID was lost")
            let unchangedReloads = picker.candidatePresentationReloadsForProbe
            fixture.folders[0].chats = [sameID]
            folder.chats.reverse()
            try await Task.sleep(for: .milliseconds(50))
            try require(
                picker.candidatePresentationReloadsForProbe == unchangedReloads,
                "duplicate membership or child reorder reloaded table",
            )

            let freshObject = pickerChat(id: 302, title: "Bravo")
            let freshFolder = CustomFolder(chats: [freshObject], type: .main)
            // Real @Published root replacement, not a manual model wakeup.
            fixture.folders = [freshFolder]
            try await until(
                { rows(picker).map { $0.textLabel?.text } == ["Bravo"] },
                "root replacement missed selector",
            )
            let retiredReloads = picker.candidatePresentationReloadsForProbe
            folder.chats.append(pickerChat(id: 306, title: "Retired child"))
            sameID.chat = pickerChat(id: 302, title: "Retired object").chat
            try await Task.sleep(for: .milliseconds(50))
            try require(
                picker.candidatePresentationReloadsForProbe == retiredReloads
                    && rows(picker).map { $0.textLabel?.text } == ["Bravo"],
                "retired folder/object subscription survived root replacement",
            )
            freshFolder.chats.append(pickerChat(id: 304, title: "Delta"))
            try await until({ rows(picker).count == 2 }, "new folder child subscription missing")
            fixture.ready.send(nil)
            freshFolder.chats.append(pickerChat(id: 305, title: "Gamma"))
            try await Task.sleep(for: .milliseconds(50))
            try require(rows(picker).count == 2, "waiting source admitted child membership")
            _ = fixture.replace(clientID: 841)
            try require(
                rows(picker).map { $0.textLabel?.text } == ["Bravo", "Delta", "Gamma"],
                "new source did not reconcile retained membership/query",
            )
            freshFolder.chats.removeAll { $0.id == 304 }
            try await until({ rows(picker).count == 2 }, "new source failed to bind child publisher")
            fixture.window.rootViewController = UIViewController()
            fixture.window.addSubview(fixture.navigation.view)
            freshFolder.chats.removeAll()
            try await Task.sleep(for: .milliseconds(50))
            try require(rows(picker).count == 2, "detached selector accepted child membership")
            try press(picker)
            try require(selected == nil && fixture.writes.isEmpty, "detached selector completed")
            fixture.navigation.view.removeFromSuperview()
            fixture.navigation.setViewControllers([fixture.navigation.viewControllers[0]], animated: false)
            fixture.window.rootViewController = fixture.navigation
            fixture.show(picker)
            try require(rows(picker).isEmpty, "reattached selector kept detached membership")
            try press(picker)
            try require(selected == [301, 302] && fixture.writes.isEmpty, "membership lost selected IDs or wrote RPC")
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
            try verifyDoneItem(picker, action: "done", enabled: true)
            fixture.ready.send(nil)
            try verifyDoneItem(picker, action: "done", enabled: false)
            try press(picker)
            try require(fixture.navigation.topViewController === picker, "disabled Done accepted selector callback")
            fixture.ready.send(fixture.current)
            try verifyDoneItem(picker, action: "done", enabled: true)
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
            try verifyDoneItem(order, action: "saveOrder", enabled: true)
            fixture.ready.send(nil)
            try verifyDoneItem(order, action: "saveOrder", enabled: false)
            try press(order)
            try require(fixture.writes.count == 1, "disabled Done dispatched reorder")
            fixture.ready.send(fixture.current)
            try verifyDoneItem(order, action: "saveOrder", enabled: true)
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

        private static func verifyControllerMembership() async throws {
            let fixture = try Fixture()
            defer { fixture.close() }
            let root = fixture.navigation.viewControllers[0]
            try require(root.chatListActionOwnerIsAttached, "window navigation root denied")

            let owner = UIViewController()
            fixture.show(owner)
            let covered = UIViewController()
            fixture.navigation.pushViewController(covered, animated: false)
            covered.loadViewIfNeeded()
            fixture.navigation.view.layoutIfNeeded()
            try require(
                owner.chatListActionOwnerIsAttached && covered.chatListActionOwnerIsAttached,
                "covered/current navigation entries denied",
            )
            fixture.navigation.popViewController(animated: true)
            try require(!covered.chatListActionOwnerIsAttached, "popping owner kept authority")
            try await until({ fixture.navigation.transitionCoordinator == nil }, "membership pop did not settle")
            fixture.navigation.setViewControllers([root], animated: false)
            // Deterministic residual pixels: neither controller is a root/member,
            // even if UIKit or a transition snapshot keeps its view in the window.
            fixture.window.addSubview(owner.view)
            try require(
                owner.view.window === fixture.window && owner.parent == nil && !owner.chatListActionOwnerIsAttached,
                "detached window pixels granted ownership",
            )
            owner.view.removeFromSuperview()

            let detachedChild = UIViewController()
            let detachedNavigation = UINavigationController(rootViewController: detachedChild)
            fixture.window.rootViewController = detachedNavigation
            detachedNavigation.loadViewIfNeeded()
            detachedChild.loadViewIfNeeded()
            detachedNavigation.view.layoutIfNeeded()
            try require(detachedChild.chatListActionOwnerIsAttached, "alternate navigation root denied")
            fixture.window.rootViewController = fixture.navigation
            fixture.window.addSubview(detachedNavigation.view)
            try require(!detachedChild.chatListActionOwnerIsAttached, "detached navigation subtree kept authority")
            detachedNavigation.view.removeFromSuperview()

            let standalone = UIViewController()
            fixture.window.rootViewController = standalone
            standalone.loadViewIfNeeded()
            fixture.window.layoutIfNeeded()
            try require(standalone.chatListActionOwnerIsAttached, "standalone window root denied")
            let container = UIViewController()
            standalone.addChild(container)
            standalone.view.addSubview(container.view)
            container.didMove(toParent: standalone)
            let page = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
            container.addChild(page)
            container.view.addSubview(page.view)
            page.didMove(toParent: container)
            let pageChild = UIViewController()
            page.setViewControllers([pageChild], direction: .forward, animated: false)
            standalone.view.layoutIfNeeded()
            try require(
                container.chatListActionOwnerIsAttached && pageChild.chatListActionOwnerIsAttached,
                "nested/page containment denied",
            )

            let modalChild = UIViewController()
            let modal = UINavigationController(rootViewController: modalChild)
            modal.modalPresentationStyle = .overFullScreen
            var presentationFinished = false
            standalone.present(modal, animated: false) { presentationFinished = true }
            try await until({
                presentationFinished && modal.viewIfLoaded?.window === fixture.window
            }, "modal presentation did not settle")
            try require(
                modalChild.chatListActionOwnerIsAttached && standalone.chatListActionOwnerIsAttached,
                "presented navigation/root ownership denied",
            )
            modal.dismiss(animated: true)
            try require(!modalChild.chatListActionOwnerIsAttached, "dismissing modal kept authority")
            try await until({ standalone.presentedViewController == nil }, "modal did not detach")
            fixture.window.addSubview(modal.view)
            try require(!modalChild.chatListActionOwnerIsAttached, "dismissed modal pixels granted ownership")
            modal.view.removeFromSuperview()
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
