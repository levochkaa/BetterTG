// ChatViewportRestorationAuthority.swift

import Foundation

/// Automatic layout compensation belongs to one geometry revision. A gesture,
/// explicit navigation or newer mutation permanently retires that revision.
struct ChatViewportRestorationAuthority {
    struct Ticket: Equatable { fileprivate let id = UUID() }

    private var current: Ticket?

    mutating func begin() -> Ticket {
        let ticket = Ticket()
        current = ticket
        return ticket
    }

    mutating func invalidate() { current = nil }

    mutating func consume(_ ticket: Ticket, contextIsCurrent: Bool, userIsScrolling: Bool) -> Bool {
        guard current == ticket else { return false }
        current = nil
        return contextIsCurrent && !userIsScrolling
    }
}
