// TDLibAuthorizationState.swift

import Combine
import TDLibKitDynamic

/// Synchronous, replaying delivery on TDLib's main-queue admission path.
/// A nil state waits for this client's first update; nil snapshot revokes ownership.
final class TDLibAuthorizationState {
    struct Snapshot: Equatable {
        let source: TdUpdateSource
        let state: AuthorizationState?
    }

    private let subject = CurrentValueSubject<Snapshot?, Never>(nil)

    var current: Snapshot? { subject.value }
    var publisher: AnyPublisher<Snapshot?, Never> { subject.eraseToAnyPublisher() }

    func activate(_ source: TdUpdateSource) { subject.send(Snapshot(source: source, state: nil)) }
    func invalidate() { subject.send(nil) }

    func update(_ state: AuthorizationState, source: TdUpdateSource) {
        guard current?.source == source else { return }
        let next = Snapshot(source: source, state: state)
        guard next != current else { return }
        subject.send(next)
    }
}
