// ChatMessageNavigationGeometry.swift

#if DEBUG
    import Foundation

    /// Opt-in observation only. Identifiers stay in memory and never enter the report.
    @MainActor final class ChatMessageNavigationGeometry {
        enum Lane { case event, command, settled }

        private struct Sample: Encodable {
            let sequence: Int
            let milliseconds: Double
            let event: String
            let lastWriter: String
            let writerSequence: Int
            let values: [String: Double]
        }

        private struct Report: Encodable {
            let version = 1
            let process: Int32
            let eventsObserved: [String: Int]
            let samples: [Sample]
        }

        private static var activeID: UUID?
        private static let outputQueue = DispatchQueue(label: "BetterTG.message-navigation-geometry")

        static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-probe-message-navigation") }

        let messageID: Int64
        let source: TdUpdateSource
        var commandTarget: DisplayedMessageID?

        private let id = UUID()
        private let started = ProcessInfo.processInfo.systemUptime
        private var finished = false
        private var samples = [Sample]()
        private var eventCount = 0
        private var commandCount = 0
        private var settledCount = 0
        private var eventCounts = [String: Int]()
        private var lastWriter = "none"
        private var writerSequence = 0
        private var checksScheduled = false
        private var deadline = ProcessInfo.processInfo.systemUptime + 120

        var isRecording: Bool { !finished && Self.activeID == id && ProcessInfo.processInfo.systemUptime <= deadline }

        init(messageID: Int64, source: TdUpdateSource) {
            self.messageID = messageID
            self.source = source
            Self.activeID = id
        }

        func record(
            _ event: StaticString,
            writer: StaticString? = nil,
            lane: Lane = .event,
            values: () -> [String: Double],
        ) {
            guard isRecording else { return }
            if let writer {
                lastWriter = String(describing: writer)
                writerSequence += 1
            }
            let name = String(describing: event)
            eventCounts[name, default: 0] += 1
            switch lane {
            case .event:
                // Reserve command and settled/end records even during a busy scroll.
                let limit = name == "scroll" ? 12 : 4
                guard eventCount < 36, eventCounts[name, default: 0] <= limit else { return }
                eventCount += 1
            case .command:
                guard commandCount < 12 else { return }
                commandCount += 1
            case .settled:
                guard settledCount < 16 else { return }
                settledCount += 1
            }
            samples.append(.init(
                sequence: samples.count,
                milliseconds: ((ProcessInfo.processInfo.systemUptime - started) * 1000).rounded(),
                event: name,
                lastWriter: lastWriter,
                writerSequence: writerSequence,
                values: values().filter(\.value.isFinite),
            ))
            guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            let url = root.appendingPathComponent("message-navigation-geometry.json")
            let report = Report(
                process: ProcessInfo.processInfo.processIdentifier, eventsObserved: eventCounts, samples: samples,
            )
            Self.outputQueue.async {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                guard let data = try? encoder.encode(report) else { return }
                try? data.write(to: url, options: .atomic)
            }
        }

        func beginSettledChecks() -> Bool {
            guard isRecording, !checksScheduled else { return false }
            checksScheduled = true
            deadline = ProcessInfo.processInfo.systemUptime + 26
            return true
        }

        func finish() { finished = true }
    }
#endif
