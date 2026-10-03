// RichNotificationRequestCoordinator.swift

import Foundation

/// Owns one service request. Callback and task cancellation are deliberately
/// outside the lock: both may reenter and replace the current request.
final class RichNotificationRequestCoordinator<Content>: @unchecked Sendable {
    struct Ticket: Equatable { let id = UUID() }

    private struct Request {
        let ticket: Ticket
        let original: Content
        let handler: (Content) -> Void
        var task: Task<Void, Never>?
    }

    private let lock = NSLock()
    private var current: Request?

    func begin(original: Content, handler: @escaping (Content) -> Void) -> Ticket {
        let ticket = Ticket()
        lock.lock()
        let previous = current
        current = Request(ticket: ticket, original: original, handler: handler)
        lock.unlock()
        if let previous { deliver(previous.original, to: previous) }
        // A previous cancellation/handler may already have replaced this ticket.
        return ticket
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return current?.ticket == ticket
    }

    func install(_ task: Task<Void, Never>, for ticket: Ticket) {
        lock.lock()
        let admitted = current?.ticket == ticket && current?.task == nil
        if admitted { current?.task = task }
        lock.unlock()
        if !admitted { task.cancel() }
    }

    /// Only synchronous content construction belongs here. It must not reenter
    /// the coordinator. An entered builder can delay expiry; donation invocation
    /// is fenced, but an already-started system donation cannot be revoked.
    @discardableResult func finish(_ ticket: Ticket, producing content: () -> Content) -> Bool {
        lock.lock()
        guard let request = current, request.ticket == ticket else {
            lock.unlock()
            return false
        }
        let result = content()
        current = nil
        lock.unlock()
        deliver(result, to: request)
        return true
    }

    @discardableResult func expire() -> Bool {
        lock.lock()
        let request = current
        current = nil
        lock.unlock()
        guard let request else { return false }
        deliver(request.original, to: request)
        return true
    }

    private func deliver(_ content: Content, to request: Request) {
        request.task?.cancel()
        request.handler(content)
    }
}
