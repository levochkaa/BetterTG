// NavigationClientRestoration.swift

import Combine
import UIKit

// MARK: - ClientRestorableNavigationEntry

@MainActor protocol ClientRestorableNavigationEntry: AnyObject {
    var navigationClientSource: TdUpdateSource? { get }
    func replacementForReadyClient(_ source: TdUpdateSource) -> UIViewController?
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
        let original = stack()
        guard let index = original.firstIndex(where: { controller in
            guard let entry = controller as? any ClientRestorableNavigationEntry,
                  let previous = entry.navigationClientSource
            else { return false }
            return previous.accountID == source.accountID && previous.clientID != source.clientID
        }), let entry = original[index] as? any ClientRestorableNavigationEntry
        else { return }
        let expectedGeneration = generation
        isReplacing = true
        defer { isReplacing = false }
        guard let replacement = entry.replacementForReadyClient(source),
              generation == expectedGeneration,
              readySource == source,
              currentSource() == source,
              canReplace(),
              original.elementsEqual(stack(), by: { $0 === $1 })
        else { return }
        var updated = original
        updated[index] = replacement
        replace(updated)
    }

    private func receiveReadiness(_ source: TdUpdateSource?) {
        if readySource != source { generation &+= 1 }
        readySource = source
        retry()
    }
}
