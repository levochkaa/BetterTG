// ContextPreviewExpansionProbe.swift

#if DEBUG
import UIKit

/// Account-free title geometry and actual context-menu lifecycle checks; leaves the same fixture for visual checks.
/// Launch with `-ui-probe-context-preview-expansion`.
@MainActor enum ContextPreviewExpansionProbe {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private final class Row: UIView, TelegramContextExpansionSource {
        let label = UILabel()
        let mute = UIImageView(image: UIImage(systemName: "speaker.slash.fill"))

        var contextExpansionTitle: UILabel? { label }
        var contextExpansionTitleAccessories: [UIView] { [mute] }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .secondarySystemBackground
            layer.cornerRadius = 12
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.numberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
            addSubview(mute)
        }

        @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = CGRect(x: 70, y: 10, width: bounds.width - 125, height: 44)
            mute.frame = CGRect(x: label.frame.maxX + 5, y: 25, width: 12, height: 12)
        }
    }

    private final class Preview: UIViewController, TelegramContextExpansionTarget, TelegramTransitionReadiness {
        let bar = TelegramChatNavigationBar()
        var readinessDelay = TimeInterval.zero

        var contextExpansionHeader: TelegramContextExpansionHeader? { bar }

        init(text: String, rtl: Bool) {
            super.init(nibName: nil, bundle: nil)
            bar.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            bar.configure(title: text, status: "Preview fixture", statusColor: .secondaryLabel)
        }

        @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemIndigo
            view.addSubview(bar)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            bar.frame = CGRect(x: 0, y: 16, width: view.bounds.width, height: TelegramChatNavigationBar.contentHeight)
        }

        func whenReadyForTransition(_ ready: @escaping () -> Void) {
            if readinessDelay == 0 { ready() }
            else {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(readinessDelay))
                    ready()
                }
            }
        }
    }

    private final class Controller: UIViewController {
        let row = Row()
        let modes = UISegmentedControl(items: ["LTR", "Multiline", "RTL"])
        let status = UILabel()
        var dismissals = 0

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            modes.selectedSegmentIndex = 0
            modes.addTarget(self, action: #selector(changeMode), for: .valueChanged)
            view.addSubview(modes)
            view.addSubview(row)
            row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
            status.numberOfLines = 0
            status.font = .systemFont(ofSize: 14)
            status.text = "Checking title geometry and interruption…"
            view.addSubview(status)
            changeMode()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            modes.frame = CGRect(x: 16, y: 90, width: view.bounds.width - 32, height: 36)
            row.frame = CGRect(x: 12, y: 180, width: view.bounds.width - 24, height: 76)
            status.frame = CGRect(x: 20, y: 285, width: view.bounds.width - 40, height: 180)
        }

        @objc func changeMode() {
            let rtl = modes.selectedSegmentIndex == 2
            // Model an RTL system's inherited trait, without changing the user's language. Forcing only the bar's
            // semantic attribute leaves its glass children LTR and creates a mixed-direction layout fixture.
            view.window?.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
            view.window?.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            row.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            row.label.textAlignment = rtl ? .right : .left
            row.label.text = [
                "Preview title",
                "Announcements and release notes for the next version",
                "إعلانات وملاحظات الإصدار القادم في مجموعة الاختبار",
            ][modes.selectedSegmentIndex]
        }

        @objc func open() { _ = show() }

        @discardableResult func show(readinessDelay: TimeInterval = 0) -> Preview? {
            let preview = Preview(text: row.label.text ?? "", rtl: modes.selectedSegmentIndex == 2)
            preview.readinessDelay = readinessDelay
            let presented = presentTelegramContextMenu(
                sourceView: row,
                actions: [TelegramContextMenuAction(title: "Close fixture", image: nil) {}],
                presentationStyle: .chatPreview,
                previewController: preview,
                onDismiss: { [weak self] in self?.dismissals += 1 },
            )
            return presented ? preview : nil
        }
    }

    private static var host: UIWindow?

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-context-preview-expansion"),
              let scene = window.windowScene
        else { return }
        let fixtureWindow = UIWindow(windowScene: scene)
        fixtureWindow.frame = window.bounds
        fixtureWindow.windowLevel = .normal + 1
        let controller = Controller()
        fixtureWindow.rootViewController = controller
        fixtureWindow.isHidden = false
        host = fixtureWindow
        fixtureWindow.layoutIfNeeded()
        Task { @MainActor in
            let result: String
            do {
                try await checkGeometry(controller)
                try await checkLifecycle(controller, window: fixtureWindow)
                result = "Context preview probe passed: RTL reading edge; multiline first-line anchor; "
                    + "normal close, interruption at 0.04/0.18 s and before readiness restore source, "
                    + "detach preview and release overlay once; late readiness does not reopen"
            } catch {
                result = "Context preview probe failed: \(error)"
            }
            controller.status.text = result
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("context-preview-expansion-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    private static func checkGeometry(_ controller: Controller) async throws {
        for mode in 0...2 {
            controller.modes.selectedSegmentIndex = mode
            controller.changeMode()
            try await Task.sleep(for: .milliseconds(50))
            controller.view.layoutIfNeeded()
            controller.row.layoutIfNeeded()
            let label = controller.row.label
            try require(
                label.effectiveUserInterfaceLayoutDirection == (mode == 2 ? .rightToLeft : .leftToRight),
                "fixture reading direction did not reach the label",
            )
            let anchor = TelegramContextExpansionGeometry.textAnchor(of: label, trailing: mode == 2)
            if mode == 0 {
                try require(abs(anchor.x) < 0.01 && abs(anchor.y - label.bounds.midY) < 0.5, "single-line anchor")
            } else {
                let block = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: 2)
                try require(block.height > label.font.lineHeight * 1.5, "fixture title did not wrap")
                try require(anchor.y < label.bounds.midY - label.font.lineHeight * 0.4, "anchor between lines")
                if mode == 2 {
                    try require(abs(anchor.x - label.bounds.maxX) < 0.01, "RTL anchor on wrong edge")
                }
            }
        }
    }

    private static func checkLifecycle(_ controller: Controller, window: UIWindow) async throws {
        let subviewCount = window.subviews.count
        for mode in 0...2 {
            controller.modes.selectedSegmentIndex = mode
            controller.changeMode()
            try await Task.sleep(for: .milliseconds(50))
            guard let preview = controller.show() else { throw Failure(description: "preview refused") }
            try await Task.sleep(for: .milliseconds(700))
            let label = preview.bar.contextExpansionTitleLabel
            let frame = label.convert(label.bounds, to: preview.bar)
            let diagnostics = "mode=\(mode), title=\(frame), bar=\(preview.bar.bounds), "
                + "platters=\(preview.bar.glassPlatters.map(\.frame)), "
                + "directions bar/title/platters=\(preview.bar.effectiveUserInterfaceLayoutDirection.rawValue)/"
                + "\(label.effectiveUserInterfaceLayoutDirection.rawValue)/"
                + "\(preview.bar.glassPlatters.map(\.effectiveUserInterfaceLayoutDirection.rawValue))"
            let visible = frame.width > 30 && frame.height > 10 && frame.intersects(preview.bar.bounds)
            _ = preview.parent?.view.accessibilityPerformEscape()
            try await Task.sleep(for: .milliseconds(400))
            try require(visible, "title outside header: \(diagnostics)")
        }
        for (delay, readiness) in [(0.65, 0.0), (0.04, 0.0), (0.18, 0.0), (0.04, 0.3)] {
            guard let preview = controller.show(readinessDelay: readiness) else {
                throw Failure(description: "next preview refused after dismissal")
            }
            let before = controller.dismissals
            try await Task.sleep(for: .seconds(delay))
            try require(preview.parent?.view.accessibilityPerformEscape() == true, "escape did not dismiss")
            try await Task.sleep(for: .milliseconds(700))
            try require(controller.dismissals == before + 1, "dismissal count")
            try require(controller.row.alpha == 1 && controller.row.transform == .identity, "row not restored")
            try require(controller.row.label.alpha == 1 && controller.row.mute.alpha == 1, "title not restored")
            try require(preview.parent == nil && preview.view.window == nil, "preview retained containment")
            try require(window.subviews.count == subviewCount, "overlay remained attached")
            try require(!controller.isPresentingTelegramContextMenu, "menu still active")
        }
    }
}
#endif
