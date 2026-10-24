// NavigationClientRestoration.swift

import Combine
import UIKit

// MARK: - ClientRestorableNavigationEntry

@MainActor protocol ClientRestorableNavigationEntry: AnyObject {
    var navigationClientSource: TdUpdateSource? { get }
    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement?
}

// MARK: - PreparedClientNavigationReplacement

/// Preparation owns no transferred files or media. Preflight must be read-only;
/// commit is synchronous and may return nil only before transferring ownership.
/// Its production constructor must not call navigation or replace the client.
/// Only the coordinator consumes plans, after every rejection gate has passed.
@MainActor final class PreparedClientNavigationReplacement {
    private let preflight: () -> Bool
    private var commitAction: (() -> UIViewController?)?

    init(preflight: @escaping () -> Bool, commit: @escaping () -> UIViewController?) {
        self.preflight = preflight
        self.commitAction = commit
    }

    fileprivate func canCommit() -> Bool {
        commitAction != nil && preflight()
    }

    fileprivate func commit() -> UIViewController? {
        guard let commitAction else { return nil }
        self.commitAction = nil
        return commitAction()
    }
}

// MARK: - NavigationClientRestoration

/// Replaces only opted-in entries. Unrelated routes and their owned state remain
/// the same objects in the same slots; account changes are handled by RootView.
@MainActor final class NavigationClientRestoration {
    private let currentSource: () -> TdUpdateSource?
    private let stack: () -> [UIViewController]
    private let canReplace: () -> Bool
    private let replace: ([UIViewController]) -> Void
    private var subscription: AnyCancellable?
    private var readySource: TdUpdateSource?
    private var generation = UInt64.zero
    private var isReplacing = false
    private var retryScheduled = false

    init(
        readiness: AnyPublisher<TdUpdateSource?, Never>,
        currentSource: @escaping () -> TdUpdateSource?,
        stack: @escaping () -> [UIViewController],
        canReplace: @escaping () -> Bool,
        replace: @escaping ([UIViewController]) -> Void,
    ) {
        self.currentSource = currentSource
        self.stack = stack
        self.canReplace = canReplace
        self.replace = replace
        self.subscription = readiness.sink { [weak self] source in
            MainActor.assumeIsolated { self?.receiveReadiness(source) }
        }
    }

    func retry() {
        guard !isReplacing,
              let source = readySource,
              source == currentSource(),
              canReplace()
        else { return }
        // A bounded identity snapshot: newly pushed or replacement entries are
        // never revisited in this pass, and a deferred entry does not block peers.
        let candidates = stack().filter { controller in
            guard let entry = controller as? any ClientRestorableNavigationEntry,
                  let previous = entry.navigationClientSource
            else { return false }
            return previous.accountID == source.accountID && previous.clientID != source.clientID
        }
        let expectedGeneration = generation
        isReplacing = true
        defer { isReplacing = false }
        for candidate in candidates {
            guard generation == expectedGeneration, readySource == source,
                  currentSource() == source, canReplace()
            else { return }
            let original = stack()
            guard let index = original.firstIndex(where: { $0 === candidate }),
                  let entry = candidate as? any ClientRestorableNavigationEntry,
                  let previous = entry.navigationClientSource,
                  previous.accountID == source.accountID, previous.clientID != source.clientID,
                  let plan = entry.prepareReplacementForReadyClient(source), plan.canCommit() else { continue }
            guard generation == expectedGeneration, readySource == source,
                  currentSource() == source, canReplace(),
                  original.elementsEqual(stack(), by: { $0 === $1 })
            else { return }
            guard let replacement = plan.commit() else { continue }
            // Terminal acceptance: a successful commit may have retired an old
            // owner. Never abandon its replacement through a later guard.
            var updated = original
            updated[index] = replacement
            replace(updated)
        }
    }

    private func receiveReadiness(_ source: TdUpdateSource?) {
        let changed = readySource != source
        if changed { generation &+= 1 }
        readySource = source
        if isReplacing {
            if changed { scheduleRetry() }
            return
        }
        retry()
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            retryScheduled = false
            retry()
        }
    }
}
