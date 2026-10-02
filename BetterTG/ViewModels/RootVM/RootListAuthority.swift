// RootListAuthority.swift

import Foundation

/// Main-thread list ownership, including a return to the same account/client.
/// A request keeps this ticket and its original client across every await.
@MainActor final class RootListAuthority {
    struct Ticket {
        let source: TdUpdateSource

        fileprivate let epoch: UInt64
    }

    private var epoch = UInt64.zero

    func invalidate() { epoch &+= 1 }

    func accepts(_ source: TdUpdateSource, ownerAccountID: UUID?, activeSource: TdUpdateSource?) -> Bool {
        source.accountID == ownerAccountID && source == activeSource
    }

    func capture(ownerAccountID: UUID?, activeSource: TdUpdateSource?) -> Ticket? {
        guard let activeSource, accepts(activeSource, ownerAccountID: ownerAccountID, activeSource: activeSource)
        else { return nil }
        return Ticket(source: activeSource, epoch: epoch)
    }

    func accepts(_ ticket: Ticket, ownerAccountID: UUID?, activeSource: TdUpdateSource?) -> Bool {
        ticket.epoch == epoch && accepts(ticket.source, ownerAccountID: ownerAccountID, activeSource: activeSource)
    }
}
