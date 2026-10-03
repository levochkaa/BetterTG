// RichNotificationSessionLifetime.swift

import Foundation

/// One notification owns one client and at most one task for each role.
/// The lock also linearizes synchronous publication with retirement. An already
/// entered write can delay retirement; this is not a hard deadline guarantee.
final class RichNotificationSessionLifetime<Value>: @unchecked Sendable {
    enum Role: Hashable { case configure, process, resolve }

    struct Ticket: Equatable {
        let id = UUID()
        let role: Role
        let clientID: Int32
    }

    private struct Job {
        let ticket: Ticket
        var task: Task<Void, Never>?
        var completed = false
    }

    private let lock = NSLock()
    private var started = false
    private var retired = false
    private var clientID: Int32?
    private var completion: ((Value?) -> Void)?
    private var jobs = [Role: Job]()
    private var closeClaimed = false

    /// Registration after cancellation resumes immediately, without client creation.
    func begin(_ completion: @escaping (Value?) -> Void) -> Bool {
        lock.lock()
        guard !started, !retired else {
            lock.unlock()
            completion(nil)
            return false
        }
        started = true
        self.completion = completion
        lock.unlock()
        return true
    }

    /// Client creation and installation cannot straddle retirement/close.
    /// The factory must not synchronously reenter this authority. TDLib dispatches
    /// its update handler asynchronously on a separate client queue.
    func createClient(_ create: () -> Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard started, !retired, clientID == nil else { return false }
        clientID = create()
        return true
    }

    func isCurrent(clientID: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return started && !retired && self.clientID == clientID
    }

    func reserve(_ role: Role, clientID: Int32) -> Ticket? {
        lock.lock()
        defer { lock.unlock() }
        guard started, !retired, self.clientID == clientID, jobs[role] == nil else { return nil }
        let ticket = Ticket(role: role, clientID: clientID)
        jobs[role] = Job(ticket: ticket)
        return ticket
    }

    func install(_ task: Task<Void, Never>, for ticket: Ticket) {
        lock.lock()
        let admitted = isCurrentLocked(ticket) && jobs[ticket.role]?.task == nil
        if admitted { jobs[ticket.role]?.task = task }
        lock.unlock()
        if !admitted { task.cancel() }
    }

    func complete(_ ticket: Ticket) {
        lock.lock()
        if jobs[ticket.role]?.ticket == ticket {
            jobs[ticket.role]?.completed = true
            jobs[ticket.role]?.task = nil
        }
        lock.unlock()
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCurrentLocked(ticket)
    }

    /// Only synchronous effects belong here. Never await, retire, cancel, resume
    /// a continuation, or close TDLib from the publication closure.
    func publish(_ ticket: Ticket, _ effect: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isCurrentLocked(ticket) else { return false }
        effect()
        return true
    }

    @discardableResult func finish(_ value: Value?, ticket: Ticket? = nil) -> Bool {
        lock.lock()
        guard !retired, ticket.map(isCurrentLocked) ?? true else {
            lock.unlock()
            return false
        }
        retired = true
        let completion = completion
        self.completion = nil
        let tasks = jobs.values.compactMap(\.task)
        jobs.removeAll()
        lock.unlock()
        // Cancellation handlers and continuations may reenter the authority.
        tasks.forEach { $0.cancel() }
        completion?(value)
        return true
    }

    /// Must be followed by a utility close, never a join of outstanding RPC tasks.
    func claimClose() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard retired, clientID != nil, !closeClaimed else { return false }
        closeClaimed = true
        return true
    }

    private func isCurrentLocked(_ ticket: Ticket) -> Bool {
        !retired && clientID == ticket.clientID
            && jobs[ticket.role]?.ticket == ticket && jobs[ticket.role]?.completed == false
    }
}
