// ContextMenuScreenProbe.swift

#if DEBUG
import UIKit

/// A screen with a message-like source and a button, without account data, for driving the menu with real gestures on
/// any runtime. Launch with `-ui-probe-context-menu-screen`. With `-ui-probe-context-menu-keys` it also opens the menu
/// and goes through the keyboard paths by itself. Every step logs with the `MENUPROBE` prefix.
@MainActor enum ContextMenuScreenProbe {
    private static var hostWindow: UIWindow?

    static func runIfRequested(in window: UIWindow) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-probe-context-menu-screen"), let scene = window.windowScene else { return }
        let host = UIWindow(windowScene: scene)
        host.frame = window.bounds
        host.windowLevel = .normal + 1
        let controller = ContextMenuScreenProbeController()
        host.rootViewController = controller
        host.makeKeyAndVisible()
        hostWindow = host
        if arguments.contains("-ui-probe-context-menu-keys") {
            Task { await controller.runKeyboardPaths() }
        }
    }
}

@MainActor private final class ContextMenuScreenProbeController: UIViewController {
    private let source = UILabel()
    private let button = UILabel()
    private let hint = UILabel()
    private var actionTime: TimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        source.text = "Probe message to hold"
        source.textAlignment = .center
        source.backgroundColor = .secondarySystemBackground
        source.layer.cornerRadius = 20
        source.clipsToBounds = true
        source.isUserInteractionEnabled = true
        source.accessibilityIdentifier = "probe.source"
        source.isAccessibilityElement = true
        source.accessibilityLabel = "Probe message to hold"
        source.frame = CGRect(x: 60, y: 300, width: view.bounds.width - 120, height: 90)
        source.autoresizingMask = [.flexibleWidth]
        view.addSubview(source)
        addPress(to: source, action: #selector(sourcePressed(_:)))

        button.text = "Menu"
        button.textAlignment = .center
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
        button.isUserInteractionEnabled = true
        button.accessibilityIdentifier = "probe.button"
        button.isAccessibilityElement = true
        button.accessibilityLabel = "Probe button"
        button.frame = CGRect(x: view.bounds.width - 96, y: 70, width: 80, height: 44)
        button.autoresizingMask = [.flexibleLeftMargin]
        view.addSubview(button)
        addPress(to: button, action: #selector(buttonPressed(_:)))

        hint.text = "Bottom of the probe"
        hint.textAlignment = .center
        hint.accessibilityIdentifier = "probe.hint"
        hint.isAccessibilityElement = true
        hint.accessibilityLabel = "Bottom of the probe"
        hint.frame = CGRect(x: 0, y: view.bounds.height - 70, width: view.bounds.width, height: 30)
        hint.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        view.addSubview(hint)
    }

    func runKeyboardPaths() async {
        try? await Task.sleep(for: .seconds(1))
        presentTelegramContextMenu(
            sourceView: source,
            actions: actions(),
            presentationStyle: .message,
            onDismiss: { [weak self] in self?.record("dismissed") },
        )
        try? await Task.sleep(for: .seconds(1))
        for input in [
            UIKeyCommand.inputDownArrow, UIKeyCommand.inputDownArrow, UIKeyCommand.inputDownArrow,
            UIKeyCommand.inputDownArrow, UIKeyCommand.inputRightArrow, UIKeyCommand.inputDownArrow,
            UIKeyCommand.inputLeftArrow, UIKeyCommand.inputUpArrow, "\r",
        ] {
            debugTelegramContextMenuPressKey(input)
            NSLog("MENUPROBE key \(input.debugDescription) -> \(debugTelegramContextMenuHighlightedTitle ?? "none")")
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    private func addPress(to view: UIView, action: Selector) {
        let press = ContextMenuPressGestureRecognizer(target: self, action: action)
        view.addGestureRecognizer(press)
    }

    private func actions() -> [TelegramContextMenuAction] {
        let run = { [weak self] (title: String) in
            self?.actionTime = CACurrentMediaTime()
            self?.record("action \(title)")
        }
        return [
            TelegramContextMenuAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) {
                run("Reply")
            },
            TelegramContextMenuAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { run("Copy") },
            TelegramContextMenuAction(
                title: "A very long action title that needs more than two lines of this menu to fit in whole",
                image: UIImage(systemName: "text.alignleft"),
            ) { run("Long") },
            TelegramContextMenuAction(
                title: "Pin",
                image: UIImage(systemName: "pin"),
                children: [
                    TelegramContextMenuAction(title: "Pin and notify") { run("Pin and notify") },
                    TelegramContextMenuAction(title: "Only pin") { run("Only pin") },
                ],
            ),
            TelegramContextMenuAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                isDestructive: true,
                startsNewSection: true,
            ) { run("Delete") },
        ]
    }

    private func record(_ event: String) {
        let time = CACurrentMediaTime()
        let sinceAction = actionTime > 0 ? String(format: " +%.3f s after the action", time - actionTime) : ""
        NSLog("MENUPROBE \(event)\(sinceAction)")
    }

    @objc private func sourcePressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        actionTime = 0
        presentTelegramContextMenu(
            sourceView: source,
            actions: actions(),
            tracking: gesture,
            presentationStyle: .message,
            onDismiss: { [weak self] in self?.record("dismissed") },
        )
    }

    @objc private func buttonPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        actionTime = 0
        presentTelegramContextMenu(
            sourceView: button,
            actions: actions(),
            tracking: gesture,
            presentationStyle: .sourceMorph,
            onDismiss: { [weak self] in self?.record("dismissed") },
        )
    }
}
#endif
