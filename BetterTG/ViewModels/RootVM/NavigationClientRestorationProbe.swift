// NavigationClientRestorationProbe.swift

#if DEBUG
    import Combine
    import UIKit

    @MainActor enum NavigationClientRestorationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private final class Entry: UIViewController, ClientRestorableNavigationEntry {
            let navigationClientSource: TdUpdateSource?
            let payload: MainViewController.ClientRestorationState
            var beforeReplacement: (() -> Void)?
            var replacementCount = 0

            init(source: TdUpdateSource, payload: MainViewController.ClientRestorationState) {
                self.navigationClientSource = source
                self.payload = payload
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable) required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            func replacementForReadyClient(_ source: TdUpdateSource) -> UIViewController? {
                replacementCount += 1
                beforeReplacement?()
                return Entry(source: source, payload: payload)
            }
        }

        private final class Rows: NSObject, UITableViewDataSource {
            var ids = Array(Int64(1)...100)

            func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { ids.count }

            func tableView(_: UITableView, cellForRowAt _: IndexPath) -> UITableViewCell {
                UITableViewCell(style: .default, reuseIdentifier: nil)
            }

            func indexPath(for id: Int64) -> IndexPath? {
                ids.firstIndex(of: id).map { IndexPath(row: $0, section: 0) }
            }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-client-restoration") else { return }
            let result: String
            do {
                try verifyCoordinator()
                try verifyViewport()
                try verifyViewportOrdering()
                try verifySearchQuery()
                result = "Client restoration probe passed: production-readiness/coordinator=true; "
                    + "cold/duplicate/stale-ready=true; A1-A2-A3=true; other-account-untouched=true; "
                    + "changed-stack/newer-epoch-fenced=true; deferred-retry=true; retained-chat-identity=true; "
                    + "production-UIKit-viewport-capture/restore=true; prepend/missing/clamp=true; "
                    + "delayed-diffable-gate/layout/query/drag=true; "
                    + "query-restoration=true; real-Main/foreground/keyboard-runtime=unverified; server-writes=0"
            } catch {
                result = "Client restoration probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("client-restoration-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(description: message) }
        }

        private static func verifyCoordinator() throws {
            let account = UUID()
            let a1 = TdUpdateSource(accountID: account, clientID: 701)
            let a2 = TdUpdateSource(accountID: account, clientID: 702)
            let a3 = TdUpdateSource(accountID: account, clientID: 703)
            let a4 = TdUpdateSource(accountID: account, clientID: 704)
            let other = TdUpdateSource(accountID: UUID(), clientID: 704)
            let payload = MainViewController.ClientRestorationState(
                searchQuery: "saved media",
                searchWasFocused: true,
                folderViewports: [4: .init(chatID: 80, rowMinYRelativeToViewport: 23, offsetFromTop: 540)],
            )
            let original = Entry(source: a1, payload: payload)
            let retainedChat = UIViewController()
            var controllers: [UIViewController] = [original, retainedChat]
            var current = a1
            var canReplace = true
            var replacements = 0
            let readiness = TDLibClientReadiness()
            readiness.activate(a1)
            let coordinator = NavigationClientRestoration(
                readiness: readiness.publisher,
                currentSource: { current },
                stack: { controllers },
                canReplace: { canReplace },
                replace: { controllers = $0
                replacements += 1
                },
            )
            readiness.update(ready: true, source: a1)
            coordinator.retry()
            try require(replacements == 0 && controllers[0] === original, "cold start replaced current Main")

            current = a2
            readiness.activate(a2)
            readiness.update(ready: true, source: a1)
            try require(replacements == 0, "stale Ready restored a closed client")
            readiness.update(ready: true, source: a2)
            readiness.update(ready: true, source: a2)
            coordinator.retry()
            guard let restored = controllers.first as? Entry
                else { throw Failure(description: "missing restored Main") }
            try require(replacements == 1 && restored.navigationClientSource == a2, "A1 to A2 was not exactly once")
            try require(controllers[1] === retainedChat, "chat/composer owner was replaced")
            try require(
                restored.payload.searchQuery == payload.searchQuery
                && restored.payload.searchWasFocused
                && restored.payload.folderViewports[4]?.chatID == 80,
                "restoration payload changed",
            )

            current = a3
            readiness.activate(a3)
            canReplace = false
            readiness.update(ready: true, source: a3)
            try require(replacements == 1, "transition/modal gate ignored")
            canReplace = true
            coordinator.retry()
            try require(
                replacements == 2 && (controllers[0] as? Entry)?.navigationClientSource == a3,
                "deferred A3 did not resume",
            )
            readiness.update(ready: true, source: a2)
            try require(replacements == 2, "delayed A2 replaced A3")

            current = other
            readiness.activate(other)
            readiness.update(ready: true, source: other)
            try require(replacements == 2, "cross-account Main rebound")

            current = a4
            readiness.activate(a4)
            let oldEntry = controllers[0] as! Entry
            let pushed = UIViewController()
            oldEntry.beforeReplacement = { controllers.append(pushed) }
            readiness.update(ready: true, source: a4)
            try require(replacements == 2 && controllers.last === pushed, "changed stack overwritten")
            oldEntry.beforeReplacement = nil
            coordinator.retry()
            try require(
                replacements == 3 && controllers[1] === retainedChat && controllers[2] === pushed,
                "retry lost the changed stack",
            )

            let a5 = TdUpdateSource(accountID: account, clientID: 705)
            let a6 = TdUpdateSource(accountID: account, clientID: 706)
            let a4Entry = controllers[0] as! Entry
            a4Entry.beforeReplacement = {
                current = a6
                readiness.activate(a6)
                readiness.update(ready: true, source: a6)
            }
            current = a5
            readiness.activate(a5)
            readiness.update(ready: true, source: a5)
            try require(replacements == 3, "newer epoch during preparation was overwritten")
            a4Entry.beforeReplacement = nil
            coordinator.retry()
            try require(
                replacements == 4 && (controllers[0] as? Entry)?.navigationClientSource == a6,
                "newest epoch did not resume",
            )
            readiness.update(ready: false, source: a6)
            current = TdUpdateSource(accountID: account, clientID: 707)
            coordinator.retry()
            try require(replacements == 4, "suspended readiness reused")
            readiness.activate(current)
            controllers = [retainedChat]
            readiness.update(ready: true, source: current)
            try require(replacements == 4 && controllers[0] === retainedChat, "removed Main resurrected")

            // A subscriber installed after Ready must see the current source.
            var replayed: TdUpdateSource?
            let replay = readiness.publisher.sink { replayed = $0 }
            try require(replayed == current, "late subscriber missed Ready")
            withExtendedLifetime(replay) {}
        }

        private static func verifyViewport() throws {
            let rows = Rows()
            let table = UITableView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), style: .plain)
            table.dataSource = rows
            table.rowHeight = 76
            table.estimatedRowHeight = 0
            table.contentInset.top = 96
            table.contentInset.bottom = 58
            table.reloadData()
            table.layoutIfNeeded()
            table.setContentOffset(CGPoint(x: 0, y: 540), animated: false)
            table.layoutIfNeeded()
            let snapshot = ChatListViewportSnapshot.capture(tableView: table) { rows.ids[$0.row] }
            guard let anchorID = snapshot.chatID else { throw Failure(description: "no visible viewport anchor") }
            rows.ids.insert(contentsOf: [-3, -2, -1], at: 0)
            table.reloadData()
            snapshot.restore(tableView: table, indexPath: rows.indexPath)
            guard let anchorPath = rows.indexPath(for: anchorID)
                else { throw Failure(description: "lost fixture anchor") }
            try require(abs(table.rectForRow(at: anchorPath).minY - table.contentOffset.y
                    - snapshot.rowMinYRelativeToViewport) < 1, "prepend changed pixel anchor")
            table.contentInset.top = 44
            snapshot.restore(tableView: table, indexPath: rows.indexPath)
            try require(abs(table.rectForRow(at: anchorPath).minY - table.contentOffset.y
                    - snapshot.rowMinYRelativeToViewport) < 1, "search inset changed pixel anchor")
            rows.ids.removeAll { $0 == anchorID }
            table.reloadData()
            snapshot.restore(tableView: table, indexPath: rows.indexPath)
            try require(
                abs(table.contentOffset.y + table.adjustedContentInset.top - snapshot.offsetFromTop) < 1,
                "missing row lost fallback offset",
            )
            rows.ids = []
            table.reloadData()
            snapshot.restore(tableView: table, indexPath: rows.indexPath)
            try require(
                abs(table.contentOffset.y + table.adjustedContentInset.top) < 1,
                "empty list offset not clamped",
            )
        }

        private static func verifySearchQuery() throws {
            let search = ChatListNavigationSearchView()
            search.restoreQuery("restored query")
            let field = search.subviews.compactMap { $0 as? UISearchTextField }.first
            try require(field?.text == "restored query", "production search field lost query")
            search.restoreQuery("")
            try require(field?.text == "", "empty query was not restored")
        }

        private static func verifyViewportOrdering() throws {
            let snapshot = ChatListViewportSnapshot(chatID: 42, rowMinYRelativeToViewport: 23, offsetFromTop: 400)
            var restoration = ChatListViewportRestoration(snapshot)
            let oldApply = restoration.beginApply()
            try require(
                restoration.takeForLayout(usable: true) == nil && restoration.pending != nil,
                "layout before diffable completion consumed anchor",
            )
            let currentApply = restoration.beginApply()
            restoration.completeApply(oldApply)
            try require(restoration.takeForLayout(usable: true) == nil, "old diffable completion consumed anchor")
            restoration.completeApply(currentApply)
            try require(
                restoration.takeForLayout(usable: false) == nil && restoration.pending != nil,
                "zero-size layout consumed anchor",
            )
            try require(
                restoration.takeForLayout(usable: true)?.chatID == 42 && restoration.pending == nil,
                "completed snapshot did not restore anchor",
            )
            try require(restoration.takeForLayout(usable: true) == nil, "anchor restored twice")
            for interaction in ["query", "drag"] {
                restoration = ChatListViewportRestoration(snapshot)
                let pendingApply = restoration.beginApply()
                restoration.cancel()
                restoration.completeApply(pendingApply)
                try require(
                    restoration.takeForLayout(usable: true) == nil,
                    "late apply reset user \(interaction)",
                )
            }
        }
    }
#endif
