// ChatTimelineValueCostProbe.swift

#if DEBUG
    import Foundation
    import QuartzCore

    /// Measures what every timeline snapshot pays per message: building a ChatMessageRenderValue and comparing it
    /// with the previous one. Equal content in distinct values is the worst case, because the deep comparison of
    /// native TDLib models reads every field. Uses the open Saved Messages history; writes no server state.
    @MainActor enum ChatTimelineValueCostProbe {
        private static var started = false

        static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-probe-timeline-value-cost") }

        static func start(messages: @escaping @MainActor () -> [CustomMessage]) {
            guard enabled, !started else { return }
            started = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                write(measure(messages()))
            }
        }

        private static func measure(_ messages: [CustomMessage]) -> String {
            guard !messages.isEmpty else { return "Timeline value cost probe skipped: no loaded messages" }
            let rounds = 50
            var previous = messages.map(ChatMessageRenderValue.init)
            var buildTime = 0.0
            var compareTime = 0.0
            var unequal = 0
            for _ in 0..<rounds {
                let buildStart = CACurrentMediaTime()
                let values = messages.map(ChatMessageRenderValue.init)
                buildTime += CACurrentMediaTime() - buildStart
                let compareStart = CACurrentMediaTime()
                for (old, new) in zip(previous, values) where old != new {
                    unequal += 1
                }
                compareTime += CACurrentMediaTime() - compareStart
                previous = values
            }
            // The snapshot fast path: an unchanged canonical revision skips building and comparing the value.
            let revisions = messages.map(\.renderRevision)
            var revisionTime = 0.0
            var unchanged = 0
            for _ in 0..<rounds {
                let start = CACurrentMediaTime()
                for (message, revision) in zip(messages, revisions) where message.renderRevision == revision {
                    unchanged += 1
                }
                revisionTime += CACurrentMediaTime() - start
            }
            let count = Double(messages.count)
            let perSnapshotMS = (buildTime + compareTime) / Double(rounds) * 1000
            let perMessageUS = (buildTime + compareTime) / Double(rounds) / count * 1_000_000
            return "Timeline value cost probe: messages=\(messages.count), rounds=\(rounds), "
                + String(
                    format: "build-ms/snapshot=%.3f, compare-ms/snapshot=%.3f, ",
                    buildTime / Double(rounds) * 1000,
                    compareTime / Double(rounds) * 1000,
                )
                + String(format: "total-ms/snapshot=%.3f, us/message=%.2f, ", perSnapshotMS, perMessageUS)
                + String(format: "revision-check-ms/snapshot=%.4f, ", revisionTime / Double(rounds) * 1000)
                + "unchanged-revisions=\(unchanged / rounds)/\(messages.count), "
                + "unequal-pairs=\(unequal), environment=Simulator (Mac CPU; device unmeasured)"
        }

        private static func write(_ result: String) {
            log(result)
            guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            try? Data(result.utf8).write(
                to: root.appendingPathComponent("timeline-value-cost-probe.txt"),
                options: .atomic,
            )
        }
    }
#endif
