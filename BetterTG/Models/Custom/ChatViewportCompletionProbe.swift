// ChatViewportCompletionProbe.swift

#if DEBUG
    import Foundation
    import UIKit

    /// Uses an already open Saved Messages controller and its unchanged real snapshot.
    /// The drag is a production delegate invocation, not a physical touch gesture.
    @MainActor final class ChatViewportCompletionProbe {
        struct Sample {
            let source: TdUpdateSource
            let ownerCurrent: Bool
            let ready: Bool
            let scrolling: Bool
            let layoutDepth: Int
            let ids: [ChatTimelineItemID]
            let anchor: ChatTimelineItemID
            let anchorFrame: CGRect
            let offset: CGPoint
            let size: CGSize
            let contentSize: CGSize
            let insets: UIEdgeInsets
            let minimumOffset: CGFloat
            let maximumOffset: CGFloat

            var pixelOffset: CGFloat { anchorFrame.minY - offset.y }
            var canStart: Bool {
                ownerCurrent && ready && !scrolling && layoutDepth == 0
                    && offset.y > minimumOffset + 128 && offset.y < maximumOffset - 128
            }

            func matchesGeometry(_ other: Self) -> Bool {
                source == other.source && ids == other.ids && anchor == other.anchor
                    && anchorFrame == other.anchorFrame && size == other.size
                    && contentSize == other.contentSize && insets == other.insets
            }
        }

        private enum Failure: Swift.Error {
            case skipped(String)
            case assertion(String)
        }

        static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-probe-viewport-completion") }

        private(set) var isExercising = false

        private weak var controller: ChatViewController?
        private var snapshotSequence = 0
        private var captureCount = 0
        private var restoreCount = 0
        private var nativeCount = 0
        private var releaseCount = 0
        private var expectedSnapshot: Int?
        private var heldCompletion: (() -> Void)?
        private var retireRestoration: (() -> Void)?
        private var interruption: String?
        private var syntheticDrag = false
        private var syntheticDragCount = 0
        private var receipts = [String]()
        private let runID = UUID()

        init(controller: ChatViewController) { self.controller = controller }

        func start() {
            write("WAITING: open Saved Messages, scroll away from both history edges, then stop scrolling")
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await write(exercise())
                } catch Failure.skipped(let reason) {
                    write("SKIP: \(reason)")
                } catch Failure.assertion(let reason) {
                    write("FAIL: \(reason)")
                } catch {
                    write("SKIP: cancelled or interrupted: \(error)")
                }
            }
        }

        func snapshotWillApply() -> Int {
            snapshotSequence += 1
            if isExercising, expectedSnapshot != snapshotSequence {
                interrupt("another structural snapshot started")
            }
            return snapshotSequence
        }

        func holdNativeCompletion(sequence: Int?, completion: @escaping () -> Void) -> Bool {
            guard isExercising, sequence == expectedSnapshot else { return false }
            guard heldCompletion == nil else {
                interrupt("duplicate native completion")
                return false
            }
            nativeCount += 1
            heldCompletion = completion
            return true
        }

        func ownRestoration(sequence: Int?, retire: @escaping () -> Void) {
            guard isExercising, let sequence, sequence == expectedSnapshot else { return }
            retireRestoration = retire
        }

        func automaticCapture() { captureCount += 1 }
        func automaticRestore() { restoreCount += 1 }

        func dragBegan() {
            if syntheticDrag { syntheticDragCount += 1 }
            else { interrupt("a physical drag overlapped the controlled schedule") }
        }

        func interrupt(_ reason: String) {
            guard isExercising else { return }
            if interruption == nil { interruption = reason }
        }

        private func exercise() async throws -> String {
            let initial = try await waitForEntry()
            isExercising = true
            defer {
                // A real update may already own a newer ticket. Retire only ours.
                let retire = retireRestoration
                retireRestoration = nil
                retire?()
                releaseHeldCompletion()
                expectedSnapshot = nil
                isExercising = false
                receipts
                    .append("cleanup: held=\(heldCompletion != nil), native=\(nativeCount), released=\(releaseCount), "
                        + "exactTicketRetirementAttempted=\(retire != nil)")
            }
            try await verify(baseline: initial, invalidatingByDrag: false)
            try await verify(baseline: initial, invalidatingByDrag: true)
            guard let final = controller?.viewportProbeSample(anchor: initial.anchor),
                  final.ownerCurrent, final.matchesGeometry(initial)
            else {
                throw Failure.skipped("source or geometry changed before cleanup")
            }
            controller?.viewportProbeMove(to: initial.offset, invalidatingByDrag: false)
            guard let reset = controller?.viewportProbeSample(anchor: initial.anchor) else {
                throw Failure.skipped("anchor disappeared during cleanup")
            }
            try require(
                reset.layoutDepth == 0 && heldCompletion == nil && nativeCount == 2 && releaseCount == 2
                && abs(reset.offset.y - initial.offset.y) <= 0.5
                && abs(reset.pixelOffset - initial.pixelOffset) <= 0.5,
                "cleanup did not settle at original anchor",
            )
            return "PASS: real ChatView/UICollectionView; unchanged snapshot IDs; exact native completion; "
                + "control restored stable-ID pixel offset; ended synthetic delegate drag rejected old restoration; "
                + "physical gesture/history insertion/media resize/keyboard overlap unverified"
        }

        private func waitForEntry() async throws -> Sample {
            let deadline = ProcessInfo.processInfo.systemUptime + 60
            var previous: Sample?
            var stableSince = ProcessInfo.processInfo.systemUptime
            while ProcessInfo.processInfo.systemUptime < deadline {
                try Task.checkCancellation()
                guard let controller else { throw Failure.skipped("controller released before entry") }
                if let sample = controller.viewportProbeSample(anchor: previous?.anchor), sample.canStart {
                    if let previous, previous.matchesGeometry(sample), previous.offset == sample.offset {
                        if ProcessInfo.processInfo.systemUptime - stableSince >= 0.25 { return sample }
                    } else { stableSince = ProcessInfo.processInfo.systemUptime }
                    previous = sample
                } else {
                    previous = nil
                    stableSince = ProcessInfo.processInfo.systemUptime
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw Failure.skipped("no settled non-latest Saved Messages viewport within 60 seconds")
        }

        private func verify(baseline: Sample, invalidatingByDrag: Bool) async throws {
            let label = invalidatingByDrag ? "drag" : "control"
            guard let controller, let before = controller.viewportProbeSample(anchor: baseline.anchor), before.canStart,
                  before.matchesGeometry(baseline), abs(before.offset.y - baseline.offset.y) <= 0.5
            else {
                throw Failure.skipped("\(label): entry no longer matches original baseline")
            }
            let capturesBefore = captureCount
            let restoresBefore = restoreCount
            let nativeBefore = nativeCount
            let releasesBefore = releaseCount
            let dragsBefore = syntheticDragCount
            expectedSnapshot = snapshotSequence + 1
            controller.viewportProbeApplySnapshot()
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while heldCompletion == nil, ProcessInfo.processInfo.systemUptime < deadline {
                try checkInterruption()
                try await Task.sleep(for: .milliseconds(10))
            }
            try checkInterruption()
            guard heldCompletion != nil else { throw Failure.skipped("\(label): native completion timed out") }
            try require(nativeCount == nativeBefore + 1, "\(label): exact native completion receipt missing")
            let native = try current(matching: before, captures: capturesBefore + 1, depth: 1)
            try require(abs(native.offset.y - before.offset.y) <= 0.5, "\(label): unchanged apply shifted offset")
            receipts.append(
                "\(label)-held: native=\(nativeCount), released=\(releaseCount), depth=\(native.layoutDepth), "
                + "sameIDs=true, sameAnchor=true, offset=\(native.offset.y), pixel=\(native.pixelOffset)",
            )

            let movedOffset = CGPoint(x: before.offset.x, y: before.offset.y + 64)
            syntheticDrag = invalidatingByDrag
            controller.viewportProbeMove(to: movedOffset, invalidatingByDrag: invalidatingByDrag)
            syntheticDrag = false
            let moved = try current(matching: before, captures: capturesBefore + 1, depth: 1)
            try require(abs(moved.offset.y - movedOffset.y) <= 0.5, "\(label): diagnostic displacement was not applied")
            try require(abs(moved.pixelOffset - before.pixelOffset) >= 63, "\(label): anchor did not actually move")
            try require(
                syntheticDragCount == dragsBefore + (invalidatingByDrag ? 1 : 0),
                "\(label): production drag delegate receipt missing",
            )
            // Release after the delegate ended and a separate main-actor turn ran.
            try await Task.sleep(for: .milliseconds(40))
            let ended = try current(matching: before, captures: capturesBefore + 1, depth: 1)
            try require(abs(ended.offset.y - moved.offset.y) <= 0.5, "\(label): viewport moved before release")
            releaseHeldCompletion()
            let after = try current(matching: before, captures: capturesBefore + 1, depth: 0)
            let expected = invalidatingByDrag ? moved : before
            try require(
                restoreCount == restoresBefore + (invalidatingByDrag ? 0 : 1),
                "\(label): incorrect automatic restoration count",
            )
            try require(
                abs(after.offset.y - expected.offset.y) <= 0.5
                && abs(after.pixelOffset - expected.pixelOffset) <= 0.5,
                "\(label): stale completion changed stable-ID pixel offset",
            )
            try require(
                releaseCount == releasesBefore + 1 && heldCompletion == nil,
                "\(label): native completion was not released exactly once",
            )
            receipts.append("\(label): snapshot=\(snapshotSequence), native=\(nativeCount), released=\(releaseCount), "
                + "capture=\(captureCount), restore=\(restoreCount), syntheticDrags=\(syntheticDragCount), "
                + "sameIDs=true, sameAnchor=true, scrolling=false, depth=\(after.layoutDepth), "
                + "offset=\(before.offset.y)/\(moved.offset.y)/\(after.offset.y), "
                + "pixel=\(before.pixelOffset)/\(moved.pixelOffset)/\(after.pixelOffset)")
        }

        private func current(matching baseline: Sample, captures: Int, depth: Int) throws -> Sample {
            try checkInterruption()
            guard let sample = controller?.viewportProbeSample(anchor: baseline.anchor),
                  sample.ownerCurrent, sample.ready, !sample.scrolling,
                  sample.matchesGeometry(baseline), snapshotSequence == expectedSnapshot,
                  captureCount == captures
            else {
                throw Failure.skipped("source, snapshot, layout, navigation, or scroll overlapped the schedule")
            }
            try require(
                sample.layoutDepth == depth,
                "unbalanced production layout depth: \(sample.layoutDepth)/\(depth)",
            )
            return sample
        }

        private func checkInterruption() throws {
            try Task.checkCancellation()
            if let interruption { throw Failure.skipped(interruption) }
        }

        private func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw Failure.assertion(message) }
        }

        private func releaseHeldCompletion() {
            let completion = heldCompletion
            heldCompletion = nil
            if let completion {
                releaseCount += 1
                completion()
            }
        }

        private func write(_ result: String) {
            guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            let text = (["run=\(runID), pid=\(ProcessInfo.processInfo.processIdentifier)", result] + receipts)
                .joined(separator: "\n")
            try? Data(text.utf8).write(
                to: root.appendingPathComponent("viewport-completion-probe.txt"),
                options: .atomic,
            )
        }
    }
#endif
