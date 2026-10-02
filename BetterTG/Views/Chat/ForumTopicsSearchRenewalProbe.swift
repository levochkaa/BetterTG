// ForumTopicsSearchRenewalProbe.swift

#if DEBUG
import Combine
import TDLibKitDynamic
import UIKit

/// The production controller and UIKit field/snapshot run against isolated VMs.
/// No TDLib lease, RPC, global account mutation or navigation write is issued.
@MainActor enum ForumTopicsSearchRenewalProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        @MainActor private final class Owner
    {
        let account = UUID()
        var actor: Int64? = 70
        var accountID: UUID?
        var source: TdUpdateSource!
        let active = PassthroughSubject<TdUpdateSource, Never>()
        let ready = CurrentValueSubject<TdUpdateSource?, Never>(nil)
        let accounts = PassthroughSubject<Void, Never>()
        let client = TDLib.shared.activeClient
        let chat: CustomChat
        var reads = [TdUpdateSource]()
        var pending = [Int32: CheckedContinuation<ForumTopicsClientEnvironment.Metadata?, Never>]()
        var models = [ForumTopicsVM]()
        var seeds = [ForumTopicsRestorationState?]()

        var environment: ForumTopicsClientEnvironment {
            .init(
                currentSource: { [self] in source },
                currentAccount: { [self] in accountID },
                currentActor: { [self] in actor },
                activeChanges: active.eraseToAnyPublisher(),
                readyChanges: ready.eraseToAnyPublisher(),
                accountChanges: accounts.eraseToAnyPublisher(),
                metadata: { [self] source, _ in
                      reads.append(source)
                      return await withCheckedContinuation { pending[source.clientID] = $0 }
                  },
                model: { [self] chat, location, client, seed in
                      let model = ForumTopicsVM.isolated(
                          customChat: chat,
                          location: location,
                          client: client,
                          restoration: seed,
                      )
                      models.append(model)
                      seeds.append(seed)
                      return model
                  },
                retryNavigation: {},
            )
        }

        init() throws {
            self.accountID = account
            self.source = .init(accountID: account, clientID: 101)
            ready.send(source)
            self.chat = RootChatInsertionProbe.chat(.init(isPinned: false, list: .chatListMain, order: 1, source: nil))
            // Generated TD models are immutable. Change only this fixture's flag.
            let data = try JSONEncoder().encode(chat.chat)
            var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            json["view_as_topics"] = true
            json["viewAsTopics"] = true
            chat.chat = try JSONDecoder().decode(Chat.self, from: JSONSerialization.data(withJSONObject: json))
        }

        func move(_ id: Int32) {
            ready.send(nil)
            source = .init(accountID: account, clientID: id)
            active.send(source)
            ready.send(source)
        }

        func finish(_ id: Int32, success: Bool = true) {
            let source = TdUpdateSource(accountID: account, clientID: id)
            pending.removeValue(forKey: id)?.resume(returning: success
                ? .init(source: source, client: client, chat: chat)
                : nil)
        }

        func finishAll() { Array(pending.keys).forEach { finish($0, success: false) } }
    }

        @MainActor private final class Fixture
    {
        let owner: Owner
        let controller: ForumTopicsViewController
        let navigation: UINavigationController
        let window: UIWindow
        weak var previousKey: UIWindow?

        init() throws {
            self.owner = try Owner()
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else { throw Failure(description: "missing window scene") }
            self.previousKey = scene.windows.first(where: \.isKeyWindow)
            self.controller = ForumTopicsViewController(
                customChat: owner.chat,
                location: .init(accountID: owner.account, chatID: 7, clientID: 101, topic: nil),
                client: owner.client,
                environment: owner.environment,
            )
            self.navigation = UINavigationController(rootViewController: UIViewController())
            navigation.setViewControllers([navigation.viewControllers[0], controller], animated: false)
            self.window = UIWindow(windowScene: scene)
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            navigation.view.layoutIfNeeded()
        }

        func activate() async throws {
            controller.probeSearch.isActive = true
            controller.probeSearch.searchBar.searchTextField.becomeFirstResponder()
            try await until("active search presentation") {
                self.controller.probeSearch.isActive && !self.controller.probeSearch.isBeingPresented
                    && self.controller.probeSearch.transitionCoordinator == nil && !self.controller.probeSnapshotBusy
                    && self.controller.probeSearch.searchBar.searchTextField.isFirstResponder
            }
        }

        func close() {
            owner.finishAll()
            controller.probeSearch.isActive = false
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKey()
        }

        func text(_ text: String) {
            controller.probeSearch.searchBar.text = text
            controller.updateSearchResults(for: controller.probeSearch)
        }

        func settle(_ id: Int32) async throws {
            try await until("metadata request \(id)") { self.owner.pending[id] != nil }
            owner.finish(id)
            try await until("binding \(id)") {
                self.controller.navigationClientSource?.clientID == id && !self.controller.probeSnapshotBusy
            }
        }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forum-active-search") else { return }
        Task { @MainActor in
            let result: String
            do {
                try await verifyRenewal()
                try await verifyRevocation(actor: false)
                try await verifyRevocation(actor: true)
                result = "Forum active search probe passed: actual-controller/field/table/native-snapshot=true; "
                    + "binding-renewal/latest-query/UTF16-selection/focus/active-unfocused=true; "
                    + "snapshot-lifetime/queued-old-publishers/second-epoch/late-metadata/Ready-gap=true; "
                    + "IME/foreign-modal/explicit-Retry/stale-control/pop/account-actor-ABA=true; "
                    + "transport/server-filter/keyboard-animation/foreground=unverified; RPC/global-account-writes=0"
            } catch { result = "Forum active search probe failed: \(error)" }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("forum-active-search-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func verifyRenewal() async throws {
        let f = try Fixture()
        defer { f.close() }
        try require(f.owner.chat.chat.viewAsTopics, "fixture did not enable topic metadata")
        try await f.activate()
        let controller = f.controller
        let search = controller.probeSearch
        let field = search.searchBar.searchTextField
        let table = controller.probeTable
        let old = controller.probeModel
        var held: (() -> Void)?
        controller.probeSnapshotCompletion = { held = $0 }
        old.publishProbe(topics: [ForumTopicsRestorationProbe.topic(id: 1)])
        try await until("held real native completion") { held != nil }
        // These receive(on:) events were enqueued under the old binding.
        old.publishProbe(topics: [ForumTopicsRestorationProbe.topic(id: 2)], loading: true, error: "old error")
        f.owner.move(102)
        await events()
        try require(
            controller.probeModel === old && f.owner.reads.isEmpty && controller.probeSnapshotBusy,
            "renewed while outgoing native batch still owned its models",
        )
        controller.probeSnapshotCompletion = nil
        held?()
        held = nil
        try await until("metadata after native drain") { f.owner.pending[102] != nil }
        let raw = "  swift 👩‍💻 é  "
        f.text(raw)
        let selection = NSRange(location: 8, length: 5)
        try select(field, range: selection)
        f.owner.finish(102)
        try await until("first in-place binding") {
            controller.navigationClientSource?.clientID == 102 && !controller.probeSnapshotBusy
        }
        try require(
            controller.probeSearch === search && search.searchBar.searchTextField === field
                    && controller.probeTable === table && f.navigation.topViewController === controller,
            "renewal replaced the UIKit search owner",
        )
        try require(
            field.text == raw && range(field) == selection && field.isFirstResponder,
            "renewal changed raw text, UTF16 selection or focus",
        )
        try require(
            f.owner.seeds.last.flatMap(\.self)?.query == raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    && controller.probeIDs.isEmpty && !controller.probeFailure,
            "commit used early query or stale queued rows/error",
        )

        let same = controller.probeModel
        f.owner.ready.send(nil)
        f.text("same epoch gap")
        f.owner.ready.send(f.owner.source)
        try await until("same-source Ready replay") { same.probeQueries.contains("same epoch gap") }
        try require(controller.probeModel === same, "Ready nil retired a returning identical binding")

        f.owner.move(103)
        try await until("superseded metadata") { f.owner.pending[103] != nil }
        f.owner.move(104)
        try await until("newer metadata") { f.owner.pending[104] != nil }
        f.owner.finish(103, success: false)
        field.setMarkedText("入力", selectedRange: NSRange(location: 2, length: 0))
        try require(field.markedTextRange != nil, "UIKit did not establish marked text")
        f.owner.finish(104)
        try await until("prepared IME deferred binding") { controller.probePrepared }
        try require(controller.probeModel === same && !controller.probeFailure, "IME or late error changed owner")
        field.unmarkText()
        f.text("new query after IME")
        try await until("IME commit event") {
            controller.navigationClientSource?.clientID == 104 && !controller.probeSnapshotBusy
        }
        field.resignFirstResponder()
        try require(search.isActive && !field.isFirstResponder, "fixture failed active-unfocused state")
        f.owner.move(105)
        try await f.settle(105)
        try require(search.isActive && !field.isFirstResponder, "active-unfocused renewal opened keyboard")

        f.owner.move(106)
        try await until("failing metadata") { f.owner.pending[106] != nil }
        f.owner.finish(106, success: false)
        try await until("visible explicit Retry") {
            controller.probeFailure && !controller.probeSnapshotBusy && table.backgroundView is UIButton
        }
        guard let staleRetry = table.backgroundView as? UIButton else { throw Failure(description: "missing Retry") }
        let count = f.owner.reads.count
        f.text("typing after failure")
        same.publishProbe(topics: [ForumTopicsRestorationProbe.topic(id: 99)], error: "late error")
        controller.probeRetryEvent()
        await events()
        try require(
            f.owner.reads.count == count && table.backgroundView === staleRetry && controller.probeIDs.isEmpty,
            "failure retried automatically or stale data hid Retry",
        )
        staleRetry.sendActions(for: .touchUpInside)
        try await until("explicit Retry read") { f.owner.pending[106] != nil }
        f.owner.finish(106, success: false)
        try await until("second explicit failure") { controller.probeFailure && !controller.probeSnapshotBusy }
        let secondCount = f.owner.reads.count
        staleRetry.sendActions(for: .touchUpInside)
        await events()
        try require(f.owner.reads.count == secondCount, "stale Retry accepted newer failure authority")
        (table.backgroundView as? UIButton)?.sendActions(for: .touchUpInside)
        try await f.settle(106)

        let modal = UIViewController()
        search.present(modal, animated: false)
        try await until("foreign modal") { search.presentedViewController === modal }
        let current = controller.probeModel
        f.owner.move(107)
        await events()
        try require(f.owner.pending[107] == nil && controller.probeModel === current, "foreign modal admitted renewal")
        search.dismiss(animated: false)
        try await until("foreign modal dismissal") { search.presentedViewController == nil }
        // A user input/layout event, not a timer, retries the deferred owner.
        f.text("event after modal")
        try await f.settle(107)

        f.owner.move(108)
        try await until("metadata before pop") { f.owner.pending[108] != nil }
        search.isActive = false
        f.navigation.popViewController(animated: false)
        try require(!controller.probeCurrent, "actual pop retained action authority")
        f.owner.finish(108)
        try await until("actual pop lifecycle retirement") { controller.probeRetired }
        try require(controller.navigationClientSource?.clientID == 107, "late metadata renewed popped controller")
    }

    private static func verifyRevocation(actor: Bool) async throws {
        let f = try Fixture()
        defer { f.close() }
        try await f.activate()
        let model = f.controller.probeModel
        if actor { f.owner.actor = 71 } else { f.owner.accountID = UUID() }
        f.owner.accounts.send(())
        f.owner.actor = 70
        f.owner.accountID = f.owner.account
        f.owner.accounts.send(())
        f.owner.move(102)
        await events()
        try require(
            f.owner.reads.isEmpty && f.controller.probeModel === model && !f.controller.probeCurrent,
            "\(actor ? "actor" : "account") ABA resurrected the route",
        )
    }

    private static func select(_ field: UITextField, range: NSRange) throws {
        guard let start = field.position(from: field.beginningOfDocument, offset: range.location),
              let end = field.position(from: start, offset: range.length), let selection = field.textRange(
                  from: start,
                  to: end,
              )
        else { throw Failure(description: "UTF16 selection unavailable") }
        field.selectedTextRange = selection
    }

    private static func range(_ field: UITextField) -> NSRange? {
        guard let selection = field.selectedTextRange else { return nil }
        return NSRange(
            location: field.offset(from: field.beginningOfDocument, to: selection.start),
            length: field.offset(from: selection.start, to: selection.end),
        )
    }

    private static func require(_ value: Bool, _ description: String) throws {
        if !value { throw Failure(description: description) }
    }

    private static func events() async {
        for _ in 0..<5 {
            await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private static func until(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(condition(), "timed out: \(label)")
    }
}
#endif
