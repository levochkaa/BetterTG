// ContextMenuInteractionProbe.swift

#if DEBUG
import UIKit

/// Deterministic checks from CustomContextMenu Tests/InteractionChecks.swift, run over the ported motion model
/// that TelegramContextMenu uses. Launch with `-ui-probe-context-menu-interaction`.
@MainActor enum ContextMenuInteractionProbe {
    // MARK: Private

    private typealias Release = ContextMenuTouchSession.Release

    private struct ReleaseCase {
        let name: String
        let origin: ContextMenuTouchSession.Origin
        let points: [CGPoint]
        let duration: TimeInterval
        let rows: [Int?]
        let expected: Release
    }

    /// Release outcomes the system menu showed on the simulator (Research/Interaction/README.md, A–M).
    private static let releaseCases: [ReleaseCase] = {
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: x, y: y) }
        return [
            ReleaseCase(
                name: "A initial drag inside preview", origin: .initiatingPreview,
                points: [p(201, 437), p(300, 437)], duration: 1, rows: [nil, nil], expected: .keepOpen,
            ),
            ReleaseCase(
                name: "B initial drag through menu, release outside", origin: .initiatingPreview,
                points: [p(201, 437), p(280, 600), p(360, 800)], duration: 1, rows: [nil, 1, nil],
                expected: .keepOpen,
            ),
            ReleaseCase(
                name: "C initial drag above preview", origin: .initiatingPreview,
                points: [p(201, 437), p(201, 250)], duration: 1, rows: [nil, nil], expected: .keepOpen,
            ),
            ReleaseCase(
                name: "D initial drag into menu and back", origin: .initiatingPreview,
                points: [p(201, 437), p(201, 580), p(201, 437)], duration: 1, rows: [nil, 1, nil],
                expected: .keepOpen,
            ),
            ReleaseCase(
                name: "G initial release on row", origin: .initiatingPreview,
                points: [p(201, 437), p(201, 622)], duration: 1, rows: [nil, 2], expected: .select(2),
            ),
            ReleaseCase(
                name: "E tap preview", origin: .preview,
                points: [p(201, 437)], duration: 0.05, rows: [nil], expected: .dismiss,
            ),
            ReleaseCase(
                name: "F row drag outside", origin: .menu,
                points: [p(201, 580), p(360, 800)], duration: 0.7, rows: [1, nil], expected: .keepOpen,
            ),
            ReleaseCase(
                name: "H outside drag into row", origin: .outside,
                points: [p(201, 800), p(201, 622)], duration: 0.7, rows: [nil, 2], expected: .select(2),
            ),
            ReleaseCase(
                name: "I preview drag into row", origin: .preview,
                points: [p(201, 437), p(201, 622)], duration: 0.7, rows: [nil, 2], expected: .select(2),
            ),
            ReleaseCase(
                name: "J outside drag outside", origin: .outside,
                points: [p(201, 800), p(330, 760)], duration: 0.6, rows: [nil, nil], expected: .keepOpen,
            ),
            ReleaseCase(
                name: "K preview move 30", origin: .preview,
                points: [p(201, 437), p(231, 437)], duration: 0.35, rows: [nil, nil], expected: .keepOpen,
            ),
            ReleaseCase(
                name: "M outside move 30", origin: .outside,
                points: [p(201, 800), p(231, 800)], duration: 0.35, rows: [nil, nil], expected: .dismiss,
            ),
        ]
    }()

    // MARK: Internal

    static func runDebugProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-context-menu-interaction") else { return }
        let failures = verify()
        let springs = ContextMenuNativeAnimation.usesNativeSprings ? "UIKit spring behavior" : "public fallback"
        let result = failures.isEmpty
            ? "Context menu interaction probe passed: 10,201 rubber-band vectors; native pan trace; native press "
            + "samples; hold 0.4/0.325 s; 60/120 Hz springs; \(releaseCases.count) native release cases; selection "
            + "delay; pan springs=\(springs)"
            : "Context menu interaction probe failed: " + failures.joined(separator: "; ")
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? Data(result.utf8).write(
                to: directory.appendingPathComponent("context-menu-interaction-probe.txt"),
                options: .atomic,
            )
        }
        log(result)
    }

    private static func verify() -> [String] {
        var failures = [String]()
        func check(_ condition: Bool, _ name: String) {
            if !condition { failures.append(name) }
        }
        func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.01) -> Bool {
            abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
        }

        check(ContextMenuMotion.pressProgress(elapsed: 0.14, duration: 0.4) == 0, "press progress before delay")
        check(
            abs(ContextMenuMotion.pressProgress(elapsed: 0.275, duration: 0.4) - 0.5) < 1e-8,
            "press progress midpoint",
        )
        check(
            abs(ContextMenuMotion.pressScale(size: CGSize(width: 280, height: 100), progress: 1) - 288.0 / 280) < 1e-8,
            "press scale",
        )
        check(
            ContextMenuMotion.holdDuration(isPad: false) == 0.4 && ContextMenuMotion.holdDuration(isPad: true) == 0.325,
            "hold durations",
        )

        var vectors = 0
        for x in stride(from: -500.0, through: 500, by: 10) {
            for y in stride(from: -500.0, through: 500, by: 10) {
                let point = CGPoint(x: x, y: y)
                let a = ContextMenuMotion.rubberBand(point)
                let b = ContextMenuMotion.rubberBand(CGPoint(x: -x, y: -y))
                guard hypot(a.x, a.y) < 15,
                      abs(a.x + b.x) < 1e-8, abs(a.y + b.y) < 1e-8,
                      abs(a.x * point.y - a.y * point.x) < 1e-8
                else { continue }
                vectors += 1
            }
        }
        check(vectors == 10201, "rubber band vectors \(vectors)/10201")

        // Register trace of the native _rubberBandedTranslationForGestureTranslation:.
        check(
            close(ContextMenuMotion.rubberBand(CGPoint(x: -37.33, y: -22.67)), CGPoint(x: -4.72, y: -2.86)),
            "native rubber band trace 1",
        )
        check(
            close(ContextMenuMotion.rubberBand(CGPoint(x: 23.67, y: 14.33)), CGPoint(x: 3.46, y: 2.09)),
            "native rubber band trace 2",
        )
        // Native preview centers: original (201, 437), pan anchor (186.67, 428.33).
        let anchor = CGPoint(x: 186.67, y: 428.33)
        for (location, center) in [
            (CGPoint(x: 179, y: 423.67), CGPoint(x: 199.63, y: 436.17)),
            (CGPoint(x: 167.67, y: 416.67), CGPoint(x: 198.07, y: 435.20)),
            (CGPoint(x: 140, y: 400), CGPoint(x: 195.60, y: 433.72)),
        ] {
            let offset = ContextMenuMotion.platterOffset(location: location, anchor: anchor)
            check(close(CGPoint(x: 201 + offset.x, y: 437 + offset.y), center), "native pan center \(location)")
        }
        // Moving toward the menu is clamped: native center (204.46, 437.00).
        let down = ContextMenuMotion.platterOffset(
            location: CGPoint(x: 201, y: 437),
            anchor: CGPoint(x: 177.33, y: 422.67),
        )
        check(close(CGPoint(x: 201 + down.x, y: 437 + down.y), CGPoint(x: 204.46, y: 437)), "pan toward menu clamp")
        let up = ContextMenuMotion.platterOffset(
            location: CGPoint(x: 201, y: 437),
            anchor: CGPoint(x: 177.33, y: 452.67),
            menuIsBelow: false,
        )
        check(up.y == 0, "pan toward a menu above clamp")

        for damping in [0.6, 0.8, 0.85, 1] {
            var slow = ContextMenuSpring(0)
            var fast = ContextMenuSpring(0)
            slow.target = 80
            fast.target = 80
            for _ in 0..<30 {
                slow.step(1.0 / 60, response: 0.4, damping: damping)
            }
            for _ in 0..<60 {
                fast.step(1.0 / 120, response: 0.4, damping: damping)
            }
            check(abs(slow.value - fast.value) < 1e-6, "refresh-rate independence \(damping)")
            let before = (slow.value, slow.velocity)
            slow.target = -40
            check(slow.value == before.0 && slow.velocity == before.1, "retarget keeps momentum \(damping)")
            for _ in 0..<360 {
                slow.step(1.0 / 120, response: 0.5, damping: damping)
            }
            check(slow.isSettled && abs(slow.value + 40) < 1e-4, "spring settles \(damping)")
        }

        let preview = CGRect(x: 48, y: 382.33, width: 306, height: 109.33)
        for item in releaseCases {
            var session = ContextMenuTouchSession(origin: item.origin, start: item.points[0], time: 0)
            for (index, point) in item.points.enumerated() {
                session.move(to: point, insidePreview: preview.contains(point))
                session.highlighted = item.rows[index]
            }
            let result = session.release(at: item.duration)
            check(result == item.expected, "\(item.name): \(result)")
        }

        var menuTouch = ContextMenuTouchSession(origin: .menu, start: CGPoint(x: 201, y: 580), time: 10)
        check(
            !menuTouch.allowsHighlight(at: 10.149) && menuTouch.allowsHighlight(at: 10.15),
            "menu selection delay",
        )
        menuTouch.move(to: CGPoint(x: 201, y: 585), insidePreview: false)
        check(!menuTouch.panning && menuTouch.panAnchor == nil, "menu touch below pan hysteresis")
        // A lifted preview can put the menu under the finger that opened it; resting there selects nothing.
        var resting = ContextMenuTouchSession(origin: .initiatingPreview, start: CGPoint(x: 201, y: 622), time: 0)
        resting.move(to: CGPoint(x: 203, y: 624), insidePreview: false)
        check(
            !resting.allowsHighlight(at: 1) && !resting.selectsOnRelease && resting.release(at: 1) == .keepOpen,
            "resting opening finger selects nothing",
        )
        resting.move(to: CGPoint(x: 201, y: 640), insidePreview: false)
        check(resting.allowsHighlight(at: 1) && resting.selectsOnRelease, "moved opening finger scrubs")
        return failures
    }
}
#endif
