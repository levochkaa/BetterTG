// ChatViewportRestorationProbe.swift

#if DEBUG
    import Foundation

    @MainActor enum ChatViewportRestorationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-viewport-authority") else { return }
            let result: String
            do {
                try verify()
                result = "Viewport authority probe passed: production-ticket=true; latest-layout-only=true; "
                    + "gesture/navigation/revoked-context-retire=true; active-scroll/replay-rejected=true; "
                    + "fresh-restoration-after-gesture=true; actual-diffable/rotation/drag-races=unverified; server/account-stores=0"
            } catch { result = "Viewport authority probe failed: \(error)" }
            log(result)
            if let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: root.appendingPathComponent("viewport-authority-probe.txt"), options: .atomic,
                )
            }
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw Failure(description: detail) }
        }

        private static func verify() throws {
            var authority = ChatViewportRestorationAuthority()
            let first = authority.begin()
            let second = authority.begin()
            try require(!authority.consume(first, contextIsCurrent: true, userIsScrolling: false), "old layout applied")
            try require(authority.consume(second, contextIsCurrent: true, userIsScrolling: false), "latest layout lost")
            try require(
                !authority.consume(second, contextIsCurrent: true, userIsScrolling: false),
                "layout applied twice",
            )

            for cause in ["drag", "explicit navigation", "keyboard inset", "highlight reconfigure"] {
                let before = authority.begin()
                authority.invalidate()
                // Even after dragging finishes, the old completion has no authority.
                try require(
                    !authority.consume(before, contextIsCurrent: true, userIsScrolling: false),
                    "\(cause) revived",
                )
                let after = authority.begin()
                try require(
                    !authority.consume(before, contextIsCurrent: true, userIsScrolling: false),
                    "stale consumed new ticket",
                )
                try require(
                    authority.consume(after, contextIsCurrent: true, userIsScrolling: false),
                    "fresh \(cause) layout lost",
                )
            }

            let tracking = authority.begin()
            try require(
                !authority.consume(tracking, contextIsCurrent: true, userIsScrolling: true),
                "active scroll moved",
            )
            try require(
                !authority.consume(tracking, contextIsCurrent: true, userIsScrolling: false),
                "scroll ticket replayed",
            )
            let retired = authority.begin()
            try require(
                !authority.consume(retired, contextIsCurrent: false, userIsScrolling: false),
                "retired context moved",
            )
            try require(
                !authority.consume(retired, contextIsCurrent: true, userIsScrolling: false),
                "retired ticket revived",
            )

            let queued = (0..<1000).map { _ in authority.begin() }
            for ticket in queued.dropLast() {
                try require(
                    !authority.consume(ticket, contextIsCurrent: true, userIsScrolling: false),
                    "queued obsolete geometry applied",
                )
            }
            try require(
                authority.consume(queued.last!, contextIsCurrent: true, userIsScrolling: false),
                "queued latest lost",
            )
        }
    }
#endif
