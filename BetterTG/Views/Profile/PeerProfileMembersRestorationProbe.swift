// PeerProfileMembersRestorationProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum PeerProfileMembersRestorationProbe {
    struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    private final class Entry: UIViewController, ClientRestorableNavigationEntry {
        let source: TdUpdateSource
        var prepare: ((TdUpdateSource) -> PreparedClientNavigationReplacement?)?

        var navigationClientSource: TdUpdateSource? { source }

        init(_ source: TdUpdateSource) { self.source = source
        super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

        func prepareReplacementForReadyClient(_ next: TdUpdateSource)
            -> PreparedClientNavigationReplacement? { prepare?(next) }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-members-restoration") else { return }
        Task {
            let result: String
            do {
                try verifyValues()
                try await until("window scene") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
                    }
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                    throw Failure(description: "missing window scene")
                }
                try verifyParentHandoff(scene: scene)
                try PeerProfileViewController.verifyUnloadedMembersParent()
                try await PeerProfileMembersViewController.verifyRestorationRendering(scene: scene)
                result = "Profile members restoration probe passed: production-pagination/revision/identity=true; "
                    + "raw-offset/dedup/removed-members/demand/repeated-fullinfo/account/actor/ABA=fenced; "
                    + "actual-Members-controller/UITableView/quarantine/anchor/fresh-page/pop-cancel=true; "
                    + "deep-error/visible-plain-Retry/explicit-only/owner-generation-old-button-fences=true; "
                    + "production-coordinator/exact-parent-child/Back/foreign-replacement=true; "
                    + "actual-unloaded-Profile/init-readiness/epoch-callbacks/retained-state/ABA=true; "
                    + "parent-navigation-entries=value-only; TDLib/real-permission-loss/foreground=unverified; server-reads/writes=0"
            } catch { result = "Profile members restoration probe failed: \(error)" }
            log(result)
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("profile-members-restoration-probe.txt"),
                    options: .atomic,
                )
            }
        }
    }

    static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(description: reason) }
    }

    static func until(_ reason: String, _ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure(description: "timeout: \(reason)")
    }

    private static func verifyValues() throws {
        let ids = (1...250).map { PeerProfileMemberID.user(Int64($0)) }
        var replay = PeerProfileMembersRevalidation()
        replay.begin(ids: ids, rawOffset: 253)
        try require(replay.hasDemand(visibleIDs: [ids[199]]) && replay.cursor == 0, "anchor demand failed")
        let first = Array(ids.prefix(99)) + [ids[0]]
        let partial = replay.admit(ids: first, rawCount: 100, hasMore: true)
        try require(
            replay.cursor == 100 && partial.count == 250 && !replay.hasDemand(visibleIDs: [ids[0]])
            && replay.hasDemand(visibleIDs: [ids[199]]),
            "raw count/dedup/offscreen demand failed",
        )
        let second = Array(ids[100..<200])
        _ = replay.admit(ids: second, rawCount: 100, hasMore: true)
        try require(
            !replay.hasDemand(visibleIDs: [ids[199]]) && replay.quarantined.contains(ids[99]),
            "accepted page revived removed member",
        )
        let final = replay.admit(ids: Array(ids[200..<250]), rawCount: 50, hasMore: false)
        try require(
            !replay.active && replay.cursor == 250 && final.count == 249 && !final.contains(ids[99]),
            "fresh cursor/removal incorrectly inherited retained extent",
        )
        replay.begin(ids: final, rawOffset: replay.cursor)
        let empty = replay.admit(ids: [], rawCount: 0, hasMore: false)
        try require(empty.isEmpty && !replay.active && replay.cursor == 0, "empty membership retained stale rows")

        var revision = PeerProfileMembersRevision<[PeerProfileMemberID]>()
        try require(
            revision.observe(ids) && !revision.observe(ids) && revision.observe(final)
            && !revision.observe(final),
            "self-triggered fullinfo replay keeps invalidating",
        )
        var availability = PeerProfileMembersRevision<Bool>()
        try require(
            availability.observe(true) && !availability.observe(true) && availability.observe(false),
            "availability replay/revocation lost",
        )
        let source = TdUpdateSource(accountID: UUID(), clientID: 1)
        let next = TdUpdateSource(accountID: source.accountID, clientID: 2)
        var identity = PeerProfileRestorationIdentity(origin: source, actorID: 77)
        try require(!identity.accepts(next, current: next, actorID: 77), "pre-ready admitted")
        identity.readySource = next
        try require(
            identity.accepts(next, current: next, actorID: 77)
            && !identity.accepts(next, current: source, actorID: 77),
            "client identity lost",
        )
        identity.observe(source: next, actorID: 78)
        try require(!identity.accepts(next, current: next, actorID: 77), "actor ABA admitted")
        identity = .init(origin: source, actorID: 77)
        identity.observe(source: .init(accountID: UUID(), clientID: 3), actorID: 77)
        identity.observe(source: next, actorID: 77)
        identity.readySource = next
        try require(!identity.accepts(next, current: next, actorID: 77), "account ABA admitted")
    }

    private static func verifyParentHandoff(scene: UIWindowScene) throws {
        let first = TdUpdateSource(accountID: UUID(), clientID: 1)
        let next = TdUpdateSource(accountID: first.accountID, clientID: 2)
        var current = first
        let ready = CurrentValueSubject<TdUpdateSource?, Never>(nil)
        let root = UIViewController(), oldParent = Entry(first), child = Entry(first)
        let freshParent = Entry(next), freshChild = Entry(next)
        let binding = PeerProfileMembersParentBinding(parent: oldParent)
        let navigation = UINavigationController()
        navigation.setViewControllers([root, oldParent, child], animated: false)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil
        }
        navigation.view.layoutIfNeeded()
        oldParent.prepare = { source in
            guard source == next else { return nil }
            return PreparedClientNavigationReplacement(
                preflight: { binding.contains(child, parent: oldParent) },
                commit: {
                guard binding.transfer(child, from: oldParent, to: freshParent) else { return nil }
                return freshParent
            },
            )
        }
        child.prepare = { source in
            guard source == next else { return nil }
            return PreparedClientNavigationReplacement(
                preflight: { binding.contains(child, parent: freshParent) },
                commit: {
                binding.contains(child, parent: freshParent) ? freshChild : nil
            },
            )
        }
        let coordinator = NavigationClientRestoration(
            readiness: ready.eraseToAnyPublisher(),
            currentSource: { current },
            stack: { navigation.viewControllers },
            canReplace: { true },
            replace: { navigation.setViewControllers($0, animated: false) },
        )
        current = next
        try require(
            binding.contains(child, parent: oldParent) && navigation.topViewController === child,
            "pre-ready exact route lost",
        )
        ready.send(next)
        coordinator.retry()
        try require(
            navigation.viewControllers.count == 3 && navigation.viewControllers[0] === root
            && navigation.viewControllers[1] === freshParent && navigation.topViewController === freshChild,
            "coordinator did not replace exact adjacent slots",
        )
        navigation.popViewController(animated: false)
        try require(
            navigation.topViewController === freshParent && !binding.contains(child, parent: freshParent),
            "Back or removed child authority failed",
        )
        let foreign = UIViewController()
        navigation.setViewControllers([root, freshParent, foreign], animated: false)
        try require(
            !binding.transfer(child, from: freshParent, to: UIViewController()),
            "foreign replacement inherited binding",
        )
    }
}
#endif
