// ContextMenuLiquidMorphProbe.swift

#if DEBUG
import UIKit

/// The checks of Telegram iOS 7c2cfd6a1f prototypes/ContextMenuMorph/Tests/LiquidMorphTests.swift that apply to the
/// ported driver, run on the device runtime. Launch with `-ui-probe-context-menu-liquid-morph`.
@MainActor enum ContextMenuLiquidMorphProbe {
    // MARK: Private

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: Internal

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-context-menu-liquid-morph"),
              let scene = window.windowScene
        else { return }
        Task { @MainActor in
            var failures = [String]()
            let supported = ContextMenuLiquidMorph.isSupported
            if supported {
                for check in [
                    ("disabled animations", checkDisabledAnimations),
                    ("round trip", checkRoundTrip),
                    ("close at open start", { try await checkCloseTakesOverOpen(after: 0, in: $0) }),
                    ("close 0.3 s into open", { try await checkCloseTakesOverOpen(after: 0.3, in: $0) }),
                    ("visibility assertions", checkVisibilityAssertions),
                ] as [(String, (UIView) async throws -> Void)] {
                    let host = makeHost(scene: scene, bounds: window.bounds)
                    do {
                        try await check.1(host.view)
                    } catch {
                        failures.append("\(check.0): \(error)")
                    }
                    host.window.isHidden = true
                }
            } else {
                failures.append("runtime unsupported")
            }
            let result = failures.isEmpty
                ? "Context menu liquid morph probe passed: supported; disabled-animation completion releases the native "
                + "coordinator and context; round trip restores hierarchy and rejects a concurrent morph; a close at 0 "
                + "and 0.3 s takes over the opening with one completion each; overlapping visibility assertions keep "
                + "the model alpha; iOS \(UIDevice.current.systemVersion)"
                : "Context menu liquid morph probe failed: " + failures.joined(separator: "; ")
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("context-menu-liquid-morph-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    private static func makeHost(scene: UIWindowScene, bounds: CGRect) -> (window: UIWindow, view: UIView) {
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.windowLevel = .normal + 1
        window.rootViewController = UIViewController()
        window.isHidden = false
        let view = window.rootViewController!.view!
        view.backgroundColor = .systemBackground
        window.layoutIfNeeded()
        return (window, view)
    }

    private static func wait(_ timeout: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        while !condition() {
            if CACurrentMediaTime() > deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    private static func pause(_ duration: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    /// testDisabledAnimationsCompleteAndReleaseNativeCoordinator.
    private static func checkDisabledAnimations(_ host: UIView) async throws {
        let source = UIView(frame: CGRect(x: 20, y: 80, width: 40, height: 40))
        let destination = UIView(frame: CGRect(x: 20, y: 140, width: 260, height: 200))
        host.addSubview(source)
        host.addSubview(destination)
        let pivot = UITargetedPreview(
            view: UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            parameters: UIPreviewParameters(),
            target: UIPreviewTarget(container: host, center: source.center),
        )
        var driver = BTLiquidMorphDriver(
            source: UITargetedPreview(view: source),
            destination: UITargetedPreview(view: destination),
            pivot: pivot,
            container: host,
            sourceIdentity: nil,
            alongside: nil,
        )
        weak let native = driver?.value(forKey: "_native") as AnyObject?
        weak let context = driver?.value(forKey: "_context") as AnyObject?
        try require(driver != nil && native != nil, "driver was not created")
        var completed = false
        let enabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        driver?.start { completed = true }
        UIView.setAnimationsEnabled(enabled)
        try await require(wait(5) { completed }, "no completion without UIView animations")
        await pause(0.05)
        driver = nil
        await pause(0.05)
        try require(native == nil, "native coordinator leaked")
        try require(context == nil, "adapter context leaked")
        try require(source.superview === host && destination.superview === host, "hierarchy not restored")
    }

    /// testRoundTripRestoresHierarchyAndRejectsConcurrentMutation.
    private static func checkRoundTrip(_ container: UIView) async throws {
        let source = UIView(frame: CGRect(x: 20, y: 100, width: 180, height: 48))
        source.backgroundColor = .systemBlue
        source.layer.cornerRadius = 24
        let menu = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        menu.frame = CGRect(x: 20, y: 160, width: 280, height: 240)
        container.addSubview(source)
        container.addSubview(menu)
        let accessory = UIView(frame: CGRect(x: 20, y: 410, width: 280, height: 30))
        accessory.alpha = 0
        container.addSubview(accessory)
        let originalFrame = source.frame
        let morph = ContextMenuLiquidMorph()
        let from = UITargetedPreview(view: source)
        let to = UITargetedPreview(view: menu)
        var opened = false
        try require(morph.animate(
            from: from, to: to, attachment: source.center, in: container,
            alongsideAnimations: { accessory.alpha = 1 },
        ) { opened = true }, "opening did not start")
        try require(morph.isAnimating, "opening is not animating")
        try require(
            !morph.animate(from: from, to: to, attachment: source.center, in: container) {},
            "concurrent transition accepted",
        )
        try await require(wait(10) { opened }, "opening did not complete")
        try require(accessory.alpha == 1 && !morph.isAnimating, "opening state")
        try require(source.superview === container && menu.superview === container, "opening hierarchy")
        var closed = false
        try require(morph.animate(
            from: to, to: from, attachment: source.center, in: container,
            alongsideAnimations: { accessory.alpha = 0 },
        ) { closed = true }, "close did not start")
        try await require(wait(10) { closed }, "close did not complete")
        try require(accessory.alpha == 0 && source.frame == originalFrame, "close geometry")
        try require(source.superview === container && menu.superview === container, "close hierarchy")
        try require(source.alpha == 1 && !source.isHidden && !morph.isAnimating, "close visibility")
    }

    /// testCloseRequestedDuringOpenTakesOverImmediately and testCloseRequestedAsOpenStartsTakesOverImmediately.
    private static func checkCloseTakesOverOpen(after delay: TimeInterval, in container: UIView) async throws {
        let source = UIView(frame: CGRect(x: 20, y: 100, width: 44, height: 44))
        source.backgroundColor = .systemBlue
        source.layer.cornerRadius = 22
        let menu = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        menu.frame = CGRect(x: 20, y: 100, width: 250, height: 240)
        container.addSubview(menu)
        container.addSubview(source)
        let originalFrame = source.frame
        let from = UITargetedPreview(view: source)
        let to = UITargetedPreview(view: menu)
        let morph = ContextMenuLiquidMorph()
        var openCompletions = 0
        var closeCompletions = 0
        var supersededOpeningReportedClose = false
        try require(
            morph.animate(from: from, to: to, attachment: source.center, in: container, sourceIdentity: source) {
            openCompletions += 1
            if morph.isAnimating != (closeCompletions == 0) { supersededOpeningReportedClose = true }
        },
            "opening did not start",
        )
        if delay > 0 { await pause(delay) }
        try require(morph.isAnimating && openCompletions == 0, "opening finished before the close")
        try require(
            !morph.animate(from: to, to: from, attachment: source.center, in: container, sourceIdentity: source) {},
            "concurrent transition accepted",
        )
        var closeStarted = false
        try require(morph.animate(
            from: to, to: from, attachment: source.center, in: container, sourceIdentity: source,
            interruptingCurrent: true, alongsideAnimations: { closeStarted = true },
        ) { closeCompletions += 1 }, "close did not start")
        try require(closeStarted && morph.isAnimating, "close did not start at once")
        try await require(wait(10) { openCompletions > 0 && closeCompletions > 0 }, "completions missing")
        await pause(0.3)
        try require(openCompletions == 1 && closeCompletions == 1, "completions \(openCompletions)/\(closeCompletions)")
        try require(!supersededOpeningReportedClose && !morph.isAnimating, "superseded opening cleared the close")
        try require(source.frame == originalFrame && source.superview === container, "source geometry")
        try require(menu.superview === container && source.alpha == 1 && !source.isHidden, "restored state")
    }

    /// testSourceVisibilityAssertionsOutliveMorphAndOverlap.
    private static func checkVisibilityAssertions(_ container: UIView) async throws {
        let source = UIView(frame: CGRect(x: 20, y: 100, width: 60, height: 40))
        source.backgroundColor = .red
        source.alpha = 0.8
        container.addSubview(source)
        let menu = UIView(frame: CGRect(x: 120, y: 200, width: 200, height: 180))
        menu.backgroundColor = .blue
        container.addSubview(menu)
        var first: AnyObject?
        var second: AnyObject?
        var done = false
        let morph = ContextMenuLiquidMorph()
        try require(morph.animate(
            from: UITargetedPreview(view: source), to: UITargetedPreview(view: menu),
            attachment: source.center, in: container,
            alongsideAnimations: { first = ContextMenuLiquidMorph.sourceVisibilityAssertion(for: source) },
        ) { done = true }, "opening did not start")
        try await require(wait(10) { done }, "opening did not complete")
        try require(first != nil, "assertion missing after native cleanup")
        second = ContextMenuLiquidMorph.sourceVisibilityAssertion(for: source)
        first = nil
        let overrideAlpha = (second as? NSObject)?.value(forKey: "alpha") as? CGFloat
        try require(overrideAlpha == 0, "older release revealed the newer claim")
        try require(abs(source.alpha - 0.8) < 0.001 && !source.isHidden, "model visibility changed")
        second = nil
        try require(abs(source.alpha - 0.8) < 0.001, "model alpha changed on release")
    }
}
#endif
