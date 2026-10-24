// ForumTopicsSearchRenewalProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

/// The production controller, its classic navigation search field and its table run against isolated view models.
/// No TDLib lease, RPC, global account mutation or navigation write is issued. Ported from the astra probe
/// (2787f32), which drove a UISearchController: the classic field is active exactly while it is focused, so an
/// unfocused search renews through the navigation replacement path instead of in place.
@MainActor enum ForumTopicsSearchRenewalProbe {
    // MARK: Private

    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Owner {
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

        init(actor: Int64? = 70) {
            self.actor = actor
            self.accountID = account
            self.source = .init(accountID: account, clientID: 101)
            ready.send(source)
            self.chat = ProbeFixtures.chat(
                .init(isPinned: false, list: .chatListMain, order: 1, source: nil),
                viewAsTopics: true,
            )
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

    @MainActor private final class Fixture {
        let owner: Owner
        let controller: ForumTopicsViewController
        let navigation: UINavigationController
        let window: UIWindow
        weak var previousKey: UIWindow?

        var field: UISearchTextField { controller.probeSearchField }

        init(actor: Int64? = 70, covered: Bool = false) throws {
            self.owner = Owner(actor: actor)
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
            var stack = [navigation.viewControllers[0], controller]
            if covered { stack.append(UIViewController()) }
            navigation.setViewControllers(stack, animated: false)
            self.window = UIWindow(windowScene: scene)
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            navigation.view.layoutIfNeeded()
        }

        func activate() async throws {
            field.becomeFirstResponder()
            try await until("active classic search") {
                self.controller.probeSearchField.isFirstResponder && !self.controller.probeSnapshotBusy
            }
        }

        func close() {
            owner.finishAll()
            field.resignFirstResponder()
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKey()
        }

        func text(_ text: String) {
            field.text = text
            field.sendActions(for: .editingChanged)
        }

        func settle(_ id: Int32) async throws {
            try await until("metadata request \(id)") { self.owner.pending[id] != nil }
            owner.finish(id)
            try await until("binding \(id)") {
                self.controller.navigationClientSource?.clientID == id && !self.controller.probeSnapshotBusy
            }
        }
    }

    // MARK: Internal

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forum-active-search") else { return }
        Task { @MainActor in
            let result: String
            do {
                // The fixtures borrow the active client object (no RPC); it exists once the account is ready.
                try await ProbeFixtures.waitForActiveAccount()
                try await verifyRenewal()
                try await verifyUnknownActor(departFirst: false)
                try await verifyUnknownActor(departFirst: true)
                try await verifyUnloadedFailure()
                try await verifyRevocation(actor: false)
                try await verifyRevocation(actor: true)
                result = "Forum active search probe passed: actual-controller/classic-field/table/native-snapshot=true; "
                    + "in-place-renewal/latest-query/UTF16-selection/focus=true; "
                    + "unfocused-search-prepares-without-renewal/refocus-commits-prepared-client=true; "
                    + "snapshot-lifetime/queued-old-publishers/second-epoch/late-metadata/Ready-gap=true; "
                    + "IME/foreign-modal/explicit-Retry/stale-control/pop/account-actor-ABA/initial-unknown-actor=true; "
                    + "unloaded-failure-visible-Retry=true; "
                    + "transport/server-filter/keyboard-animation/foreground=unverified; RPC/global-account-writes=0"
            } catch {
                result = "Forum active search probe failed: \(error)"
            }
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
        let field = f.field
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
        let raw = "  swift 👩‍💻 é  "
        f.text(raw)
        let selection = NSRange(location: 8, length: 5)
        try select(field, range: selection)
        f.owner.finish(102)
        try await until("first in-place binding") {
            controller.navigationClientSource?.clientID == 102 && !controller.probeSnapshotBusy
        }
        try require(
            controller.probeSearchField === field && controller.probeTable === table
                && f.navigation.topViewController === controller,
            "renewal replaced the search field or table",
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

        // The classic field is active only while focused: an unfocused search prepares for the navigation
        // replacement, keeps its query and never reopens the keyboard; focusing it again commits in place.
        field.resignFirstResponder()
        let unfocused = controller.probeModel
        f.owner.move(105)
        // As the production navigation coordinator does for a quiescent entry.
        _ = controller.prepareReplacementForReadyClient(f.owner.source)
        try await until("unfocused metadata") { f.owner.pending[105] != nil }
        f.owner.finish(105)
        try await until("unfocused preparation") { controller.probePrepared }
        try require(
            !field.isFirstResponder && controller.probeModel === unfocused
                && controller.navigationClientSource?.clientID == 104 && field.text == "new query after IME",
            "unfocused search renewed in place, lost its query or opened the keyboard",
        )
        try await f.activate()
        f.text("refocused")
        try await until("refocused in-place binding") {
            controller.navigationClientSource?.clientID == 105 && !controller.probeSnapshotBusy
        }

        f.owner.move(106)
        try await until("failing metadata") { f.owner.pending[106] != nil }
        f.owner.finish(106, success: false)
        try await until("visible explicit Retry") {
            controller.probeFailure && !controller.probeSnapshotBusy && table.backgroundView is UIButton
        }
        guard let staleRetry = table.backgroundView as? UIButton else { throw Failure(description: "missing Retry") }
        let count = f.owner.reads.count
        f.text("typing after failure")
        controller.probeModel.publishProbe(topics: [ForumTopicsRestorationProbe.topic(id: 99)], error: "late error")
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
        controller.present(modal, animated: false)
        try await until("foreign modal attached") {
            modal.presentingViewController != nil && modal.viewIfLoaded?.window === f.window
                && !modal.isBeingPresented && modal.transitionCoordinator == nil
        }
        let current = controller.probeModel
        f.owner.move(107)
        await events()
        try require(f.owner.pending[107] == nil && controller.probeModel === current, "foreign modal admitted renewal")
        modal.presentingViewController?.dismiss(animated: false)
        try await until("foreign modal dismissal") {
            modal.presentingViewController == nil && modal.viewIfLoaded?.window == nil
        }
        try require(controller.probeSearchField === field, "foreign modal replaced the search field")
        // A user input event, not a timer, retries the deferred owner.
        if !field.isFirstResponder { try await f.activate() }
        f.text("event after modal")
        try await f.settle(107)

        f.owner.move(108)
        try await until("metadata before pop") { f.owner.pending[108] != nil }
        guard let preparation = controller.probePreparationTask
        else { throw Failure(description: "missing held preparation task") }
        let dismissals = controller.probeSearchDismissals
        field.resignFirstResponder()
        try await until("search dismissal before pop") {
            controller.probeSearchDismissals > dismissals && !field.isFirstResponder
                && f.navigation.transitionCoordinator == nil
        }
        try require(
            f.navigation.topViewController === controller && f.owner.pending[108] != nil,
            "search dismissal lost the pending owner before explicit pop",
        )
        let popped = f.navigation.popViewController(animated: false)
        try require(
            popped === controller && !f.navigation.viewControllers.contains(where: { $0 === controller })
                && !controller.chatListActionOwnerIsAttached && !controller.probeCurrent,
            "actual pop retained navigation or action authority",
        )
        f.owner.finish(108)
        try await until("actual pop lifecycle retirement") { controller.parent == nil && controller.probeRetired }
        var preparationFinished = false
        let observer = Task {
            await preparation.value
            preparationFinished = true
        }
        defer { observer.cancel() }
        try await until("late popped-owner metadata terminal guard") { preparationFinished }
        try require(
            controller.navigationClientSource?.clientID == 107 && !controller.probePrepared,
            "late metadata renewed or prepared popped controller",
        )
    }

    private static func verifyUnloadedFailure() async throws {
        let f = try Fixture(covered: true)
        defer { f.close() }
        let controller = f.controller
        try require(!controller.isViewLoaded, "retained parent unexpectedly loaded its view")
        f.owner.move(102)
        // The production coordinator prepares retained entries even below a child.
        _ = controller.prepareReplacementForReadyClient(f.owner.source)
        try await until("unloaded parent metadata") { f.owner.pending[102] != nil }
        f.owner.finish(102, success: false)
        try await until("unloaded parent failure") { controller.probeFailure }
        try require(!controller.isViewLoaded, "metadata failure forced hidden parent view loading")
        f.navigation.popViewController(animated: false)
        try await until("Back exposes retained failure") {
            controller.isViewLoaded && controller.probeTable.backgroundView is UIButton
        }
        let count = f.owner.reads.count
        controller.probeRetryEvent()
        await events()
        try require(
            f.owner.reads.count == count && controller.probeFailure,
            "unloaded failure replayed without explicit Retry",
        )
        (controller.probeTable.backgroundView as? UIButton)?.sendActions(for: .touchUpInside)
        try require(!controller.probeFailure, "visible unloaded-owner Retry did not clear matching failure")
        _ = controller.prepareReplacementForReadyClient(f.owner.source)
        try await until("explicit unloaded-owner retry") { f.owner.pending[102] != nil }
        f.owner.finish(102)
        try await until("unloaded-owner fresh preparation") { controller.probePrepared }
        let coordinator = NavigationClientRestoration(
            readiness: f.owner.ready.eraseToAnyPublisher(), currentSource: { f.owner.source },
            stack: { f.navigation.viewControllers }, canReplace: { true },
            replace: { f.navigation.setViewControllers($0, animated: false) },
        )
        coordinator.retry()
        guard let replacement = f.navigation.topViewController as? ForumTopicsViewController,
              replacement !== controller
        else { throw Failure(description: "explicit retry failed quiescent replacement plan") }
        try require(
            replacement.navigationClientSource?.clientID == 102 && controller.probeRetired,
            "quiescent retry returned stale owner",
        )
    }

    private static func verifyUnknownActor(departFirst: Bool) async throws {
        let f = try Fixture(actor: nil)
        defer { f.close() }
        try await f.activate()
        let model = f.controller.probeModel
        model.publishProbe(topics: [ForumTopicsRestorationProbe.topic(id: 1)])
        try await until("unknown actor current-source rows") {
            f.controller.probeIDs == [1] && !f.controller.probeSnapshotBusy
        }
        try require(
            f.controller.probeCurrent && f.controller.probeActor == nil,
            "unknown actor blocked ordinary bound-source rendering",
        )
        f.owner.ready.send(nil)
        f.owner.ready.send(f.owner.source)
        try await until("unknown actor returning Ready") { !f.controller.probeSnapshotBusy }
        try require(
            f.controller.probeModel === model && f.controller.probeCurrent,
            "unknown actor Ready gap retired the original binding",
        )
        if departFirst {
            f.owner.move(102)
            f.owner.actor = 70
            f.owner.accounts.send(())
            f.owner.move(101)
            f.owner.accounts.send(())
            await events()
            try require(
                f.controller.probeActor == nil && f.owner.reads.isEmpty && !f.controller.probeCurrent,
                "departed unknown identity latched replacement actor or revived after ABA",
            )
        } else {
            f.owner.actor = 70
            f.owner.accounts.send(())
            try require(
                f.controller.probeActor == 70 && f.controller.probeCurrent,
                "same-source Ready actor metadata failed to latch",
            )
            f.owner.move(102)
            try await f.settle(102)
            try require(f.controller.probeModel !== model, "latched actor failed eligible later renewal")
        }
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
              let end = field.position(from: start, offset: range.length),
              let selection = field.textRange(from: start, to: end)
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
