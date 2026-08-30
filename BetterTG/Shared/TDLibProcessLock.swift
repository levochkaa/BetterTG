// TDLibProcessLock.swift

import Darwin
import Foundation

final class TDLibProcessLock: @unchecked Sendable {
    // MARK: Internal

    enum LockError: LocalizedError {
        case appGroupUnavailable
        case openFailed(Int32)
        case acquireFailed(Int32)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                "The BetterTG App Group container is unavailable."
            case .openFailed(let code):
                "Unable to open the TDLib process lock (errno \(code))."
            case .acquireFailed(let code):
                "Unable to acquire the TDLib process lock (errno \(code))."
            }
        }
    }

    // MARK: Private

    private var descriptor: Int32

    deinit {
        unlock()
    }

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(wait: Bool) throws -> TDLibProcessLock? {
        guard let containerURL = BetterTGAppGroup.containerURL() else {
            throw LockError.appGroupUnavailable
        }
        let lockURL = containerURL.appendingPathComponent("tdlib-owner.lock", isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LockError.openFailed(errno) }

        let operation = LOCK_EX | (wait ? 0 : LOCK_NB)
        guard flock(descriptor, operation) == 0 else {
            let code = errno
            close(descriptor)
            if !wait, code == EWOULDBLOCK {
                return nil
            }
            throw LockError.acquireFailed(code)
        }
        return TDLibProcessLock(descriptor: descriptor)
    }

    static func acquire(waitingUpTo timeout: TimeInterval) throws -> TDLibProcessLock? {
        guard let containerURL = BetterTGAppGroup.containerURL() else {
            throw LockError.appGroupUnavailable
        }
        let lockURL = containerURL.appendingPathComponent("tdlib-owner.lock", isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LockError.openFailed(errno) }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return TDLibProcessLock(descriptor: descriptor)
            }
            let code = errno
            guard code == EWOULDBLOCK else {
                close(descriptor)
                throw LockError.acquireFailed(code)
            }
            if Date() >= deadline {
                close(descriptor)
                return nil
            }
            usleep(50000)
        } while true
    }

    func unlock() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
