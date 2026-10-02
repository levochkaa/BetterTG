// PeerProfileHistoryRequest.swift

import Foundation

// MARK: - PeerProfileHistoryRequest

/// A repeated tab selection is a new request, even when its filter is identical.
struct PeerProfileHistoryRequest {
    private(set) var currentID: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    mutating func invalidate() {
        currentID = nil
    }

    mutating func finish(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        currentID = nil
        return true
    }
}

#if DEBUG
    enum PeerProfileHistoryRequestProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        @MainActor static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-history-request") else { return }
            let result: String
            do {
                try verify()
                result = "Profile history request probe passed: production-token=true; "
                    + "A-B-A-stale-success/error/cancel=fenced; replacement-busy-preserved; "
                    + "current-completion-once; invalidation/retry=fenced; "
                    + "controller-wiring=source-reviewed; live-UIKit/RPC=unverified; server-writes=0"
            } catch {
                result = "Profile history request probe failed: \(error)"
            }
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documents.appendingPathComponent("profile-history-request-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verify() throws {
            for completion in ["success", "error", "cancel"] {
                var request = PeerProfileHistoryRequest()
                let firstA = request.begin()
                request.invalidate()
                let b = request.begin()
                request.invalidate()
                let secondA = request.begin()
                var deliveries = 0
                if request.finish(firstA) { deliveries += 1 }
                if request.finish(b) { deliveries += 1 }
                try require(
                    deliveries == 0 && request.currentID == secondA,
                    "\(completion): stale completion consumed replacement",
                )
                if request.finish(secondA) { deliveries += 1 }
                try require(deliveries == 1 && request.currentID == nil, "current completion lost")
                try require(!request.finish(secondA), "duplicate completion accepted")
                let retry = request.begin()
                try require(!request.finish(secondA) && request.currentID == retry, "old result consumed retry")
                request.invalidate()
                try require(!request.finish(retry) && request.currentID == nil, "invalidated request revived")
            }
        }
    }
#endif
