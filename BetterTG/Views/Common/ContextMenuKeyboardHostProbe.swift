// ContextMenuKeyboardHostProbe.swift

#if DEBUG
import UIKit

/// Exercises the real keyboard with screen insets like search results, without account data or sends.
/// Launch with `-ui-probe-context-menu-keyboard-host`.
@MainActor enum ContextMenuKeyboardHostProbe {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-context-menu-keyboard-host") else { return }
        Task { @MainActor in
            let result: String
            do {
                let measurements = try await verify(in: window)
                result = "Context menu keyboard host probe passed: hidden keyboard uses source window; "
                    + "visible keyboard uses keyboard window before and after search insets; focus retained; "
                    + "dismissal and reopening refresh host; \(measurements)"
            } catch {
                result = "Context menu keyboard host probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("context-menu-keyboard-host-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    private static func wait(until condition: () -> Bool) async throws {
        let deadline = CACurrentMediaTime() + 5
        while !condition() {
            guard CACurrentMediaTime() < deadline else { throw Failure(description: "keyboard layout timed out") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func verify(in window: UIWindow) async throws -> String {
        guard let scene = window.windowScene else { throw Failure(description: "missing scene") }
        let host = UIWindow(windowScene: scene)
        host.frame = window.bounds
        host.windowLevel = .normal + 1
        let presenter = UIViewController()
        host.rootViewController = presenter
        host.makeKeyAndVisible()
        let field = UITextField(frame: CGRect(x: 20, y: 100, width: 240, height: 44))
        field.borderStyle = .roundedRect
        field.placeholder = "Keyboard host probe"
        presenter.view.backgroundColor = .systemBackground
        presenter.view.addSubview(field)
        // Search results opt out of the bottom safe area in their keyboard guide and add the filter strip to it.
        presenter.view.keyboardLayoutGuide.usesBottomSafeArea = false
        defer {
            field.resignFirstResponder()
            host.isHidden = true
            window.makeKey()
        }
        host.layoutIfNeeded()
        try require(
            TelegramContextMenuKeyboardHost.visibleKeyboardWindow(for: host) == nil,
            "hidden keyboard selected a keyboard window",
        )
        field.becomeFirstResponder()
        try await wait { presenter.view.keyboardLayoutGuide.layoutFrame.height > 100 }
        let normalHost = TelegramContextMenuKeyboardHost.visibleKeyboardWindow(for: host)
        try require(
            normalHost != nil && normalHost !== host,
            "visible keyboard did not select its window: root=\(presenter.view.keyboardLayoutGuide.layoutFrame)",
        )

        let height = presenter.view.keyboardLayoutGuide.layoutFrame.height
        presenter.additionalSafeAreaInsets.bottom = height + 52
        host.layoutIfNeeded()
        try require(
            presenter.view.safeAreaInsets.bottom > presenter.view.keyboardLayoutGuide.layoutFrame.height,
            "fixture did not reproduce search safe area exceeding the keyboard",
        )
        try require(
            TelegramContextMenuKeyboardHost.visibleKeyboardWindow(for: host) === normalHost,
            "search insets changed the keyboard host",
        )
        try require(field.isFirstResponder && host.isKeyWindow, "host lookup moved focus")
        let measurements = "keyboard=\(height), screenSafeArea=\(presenter.view.safeAreaInsets.bottom), "
            + "windowSafeArea=\(host.safeAreaInsets.bottom), iOS \(UIDevice.current.systemVersion)"

        field.resignFirstResponder()
        try await wait { presenter.view.keyboardLayoutGuide.layoutFrame.height < 1 }
        try require(
            TelegramContextMenuKeyboardHost.visibleKeyboardWindow(for: host) == nil,
            "dismissed keyboard retained its host with large screen insets",
        )
        field.becomeFirstResponder()
        try await wait { presenter.view.keyboardLayoutGuide.layoutFrame.height > 100 }
        try require(
            TelegramContextMenuKeyboardHost.visibleKeyboardWindow(for: host) != nil,
            "reopened keyboard did not restore its host",
        )
        return measurements
    }
}
#endif
