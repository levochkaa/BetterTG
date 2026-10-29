// TelegramLinkResolutionProbe.swift

#if DEBUG
import UIKit

/// Exercises the production progress owner without TDLib, navigation or URL opening.
@MainActor enum TelegramLinkResolutionProbe {
    private struct Failure: Error, CustomStringConvertible { let description: String }

    private final class Window: UIWindow {
        var attachments = 0

        override func didAddSubview(_ subview: UIView) {
            super.didAddSubview(subview)
            if subview is LinkResolutionProgressView { attachments += 1 }
        }
    }

    /// A noncooperative request: cancellation marks its Task, but the response still arrives later.
    private final class Response {
        private var continuation: CheckedContinuation<Void, Never>?
        private var returned = false

        func wait() async {
            guard !returned else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func finish() {
            returned = true
            continuation?.resume()
            continuation = nil
        }
    }

    private final class Controller: UIViewController {
        private let resolution = TelegramLinkResolution()
        private let status = UILabel()
        private var generation = 0

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemGroupedBackground
            let controls = UIStackView()
            controls.axis = .vertical
            controls.spacing = 16
            controls.translatesAutoresizingMaskIntoConstraints = false
            for title in ["Slow (5s)", "Fast", "Replace with slow", "Replace with direct", "Appearance"] {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    switch title {
                    case "Slow (5s)": start(seconds: 5)
                    case "Fast": start(seconds: 0.02)
                    case "Appearance":
                        guard let window = view.window else { return }
                        window.overrideUserInterfaceStyle = window.traitCollection.userInterfaceStyle == .dark
                            ? .light
                            : .dark
                    default:
                        start(seconds: 2)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            self?.start(seconds: 5, showsProgress: title == "Replace with slow")
                        }
                    }
                }, for: .touchUpInside)
                controls.addArrangedSubview(button)
            }
            view.addSubview(controls)
            status.numberOfLines = 0
            status.textAlignment = .center
            status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            status.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(status)
            NSLayoutConstraint.activate([
                controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
                controls.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                status.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 240),
            ])
            Task { [weak self] in
                let result: String
                do {
                    guard let scene = self?.view.window?.windowScene else {
                        throw Failure(description: "fixture has no window scene")
                    }
                    try await verify(in: scene)
                    result = "Link progress probe passed: fast/no-flash; delayed show; replacement; late result; cancel; cleanup"
                } catch {
                    result = "Link progress probe failed: \(error)"
                }
                self?.status.text = result
                log(result)
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("link-progress-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }

        private func start(seconds: Double, showsProgress: Bool = true) {
            generation += 1
            let current = generation
            status.text = "Operation \(current): waiting"
            let response = Response()
            let task = Task { [weak self] in
                await response.wait()
                guard let self, current == generation else { return }
                status.text = "Operation \(current): \(Task.isCancelled ? "cancelled; response ignored" : "completed locally")"
            }
            resolution.task = task
            if showsProgress { resolution.showProgress(in: view.window) }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { response.finish() }
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-link-progress") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let controller = Controller()
            controller.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(controller, animated: false)
        }
    }

    private static func require(_ value: Bool, _ reason: String) throws {
        guard value else { throw Failure(description: reason) }
    }

    private static func waitUntil(_ check: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !check(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(check(), "timed out waiting for progress lifecycle")
    }

    private static func verify(in scene: UIWindowScene) async throws {
        // Hidden, non-key window: lifecycle assertions don't interrupt the user's visible fixture.
        let window = Window(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let owner = TelegramLinkResolution()
        let first = Response()
        let second = Response()
        defer {
            owner.task = nil
            first.finish()
            second.finish()
        }
        func overlays() -> [LinkResolutionProgressView] { window.subviews
            .compactMap { $0 as? LinkResolutionProgressView }
        }

        owner.task = Task {}
        owner.showProgress(in: window)
        try await Task.sleep(for: .milliseconds(400))
        try require(overlays().isEmpty && window.attachments == 0, "fast operation flashed an overlay")

        let oldTask = Task { await first.wait() }
        owner.task = oldTask
        owner.showProgress(in: window)
        try await waitUntil { overlays().count == 1 }
        weak let oldView = overlays().first
        owner.task = Task { await second.wait() }
        try require(oldTask.isCancelled && oldView?.superview == nil, "replacement retained old overlay or task")
        owner.showProgress(in: window)
        try await waitUntil { overlays().count == 1 }
        let current = overlays().first!
        first.finish()
        await oldTask.value
        try await Task.sleep(for: .milliseconds(400))
        try require(overlays().count == 1 && overlays().first === current, "old completion dismissed replacement")
        try require(oldView == nil, "old overlay retained after delayed callback and completion")

        try require(current.accessibilityActivate(), "accessible cancel not handled")
        try require(owner.task == nil, "cancel retained the operation")
        owner.task = Task {}
        try require(overlays().isEmpty, "replacement during cancel fade retained overlay")
        try await waitUntil { overlays().isEmpty }
        second.finish()

        // Completion and cancel during the scale/fade-in both retire the animation and view.
        let third = Response()
        defer { third.finish() }
        owner.task = Task { await third.wait() }
        owner.showProgress(in: window)
        try await waitUntil { overlays().count == 1 }
        third.finish()
        try await waitUntil { overlays().isEmpty }

        let fourth = Response()
        defer { fourth.finish() }
        let cancelledTask = Task { await fourth.wait() }
        let attachments = window.attachments
        owner.task = cancelledTask
        owner.showProgress(in: window)
        owner.cancel()
        try await Task.sleep(for: .milliseconds(400))
        try require(
            cancelledTask.isCancelled && overlays().isEmpty && window.attachments == attachments,
            "cancel before delay showed progress",
        )
    }
}
#endif
