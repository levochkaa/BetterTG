// AttachmentTransitionProbe.swift

#if DEBUG
import UIKit

/// Exercises live containment and appearance through actual UIKit transitions, without an account or sends.
/// Launch with `-ui-probe-attachment-transition`; results go to Documents/attachment-transition-probe.txt.
@MainActor enum AttachmentTransitionProbe {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private final class Screen: UIViewController {
        var appearances = 0
        var disappearances = 0

        init(_ name: String) {
            super.init(nibName: nil, bundle: nil)
            title = name
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", primaryAction: UIAction { _ in })
        }

        @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            AttachmentPanelView.install(in: self, tabs: [.gallery, .file, .poll], current: .gallery) { _ in }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appearances += 1
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            disappearances += 1
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-attachment-transition") else { return }
        Task { @MainActor in
            let result: String
            do {
                try await verify(in: window)
                result = "Attachment transition probe passed: both screens and chrome live during fade; latest tab "
                    + "wins; gallery alpha, insets and appearance restored; dismissal drops pending tab; "
                    + "switch during presentation completes"
            } catch {
                result = "Attachment transition probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("attachment-transition-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    private static func verify(in window: UIWindow) async throws {
        guard let scene = window.windowScene else { throw Failure(description: "missing scene") }
        let host = UIWindow(windowScene: scene)
        host.frame = window.bounds
        host.windowLevel = .normal + 1
        let presenter = UIViewController()
        host.rootViewController = presenter
        host.isHidden = false
        defer {
            presenter.dismiss(animated: false)
            host.isHidden = true
        }
        host.layoutIfNeeded()
        let gallery = Screen("Gallery")
        let file = Screen("File")
        let unused = Screen("Poll")
        let navigation = TelegramNavigationController(rootViewController: gallery)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        presenter.present(navigation, animated: false)
        try await Task.sleep(for: .milliseconds(150))
        let galleryInsets = gallery.additionalSafeAreaInsets
        let panelFrame = gallery.view.subviews.first { $0 is AttachmentPanelView }?.frame
        let switchStarted = Date.timeIntervalSinceReferenceDate
        navigation.replaceAttachmentSheetContent(with: file)
        // UIKit can register the coordinator before it installs the destination. Observe the fade after it starts,
        // not a fixed delay from setViewControllers (a fresh, unauthenticated Simulator can take longer than 70 ms).
        while file.view.window !== host, Date.timeIntervalSinceReferenceDate - switchStarted < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(70))
        try require(
            gallery.view.window === host && file.view.window === host,
            "live screens missing during fade; elapsed=\(Date.timeIntervalSinceReferenceDate - switchStarted) "
                + "gallery=\(gallery.view.window === host) file=\(file.view.window === host) "
                + "top=\(navigation.topViewController?.title ?? "nil") coordinator=\(navigation.transitionCoordinator != nil) "
                + "animations=\(UIView.areAnimationsEnabled) scene=\(scene.activationState.rawValue)",
        )
        try require(
            gallery.view.subviews.contains { $0 is TelegramClassicNavigationChrome && $0.window === host },
            "outgoing chrome detached before fade completes",
        )
        navigation.replaceAttachmentSheetContent(with: unused)
        navigation.replaceAttachmentSheetContent(with: gallery)
        try await Task.sleep(for: .milliseconds(650))
        try require(
            navigation.topViewController === gallery && navigation.viewControllers.count == 1,
            "latest tab lost",
        )
        try require(gallery.view.alpha == 1 && gallery.view.window === host, "gallery not restored")
        try require(gallery.additionalSafeAreaInsets == galleryInsets, "gallery insets accumulated")
        try require(gallery.view.subviews.first { $0 is AttachmentPanelView }?.frame == panelFrame, "panel moved")
        try require(
            file.view.superview == nil && file.additionalSafeAreaInsets.top == 0,
            "old screen or chrome retained",
        )
        try require(unused.appearances == 0, "superseded tab appeared")
        try require(gallery.appearances == 2 && gallery.disappearances == 1, "gallery appearance unbalanced")
        try require(file.appearances == 1 && file.disappearances == 1, "file appearance unbalanced")

        navigation.replaceAttachmentSheetContent(with: file)
        try await Task.sleep(for: .milliseconds(70))
        navigation.replaceAttachmentSheetContent(with: unused)
        presenter.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(500))
        try require(navigation.view.window == nil && unused.appearances == 0, "pending tab survived dismissal")

        let second = TelegramNavigationController(rootViewController: Screen("Gallery"))
        second.modalPresentationStyle = .pageSheet
        presenter.present(second, animated: true)
        try await Task.sleep(for: .milliseconds(30))
        let early = Screen("File")
        second.replaceAttachmentSheetContent(with: early)
        try await Task.sleep(for: .milliseconds(1000))
        try require(second.topViewController === early && early.appearances == 1, "switch during presentation lost")
        let retainedInsets = early.additionalSafeAreaInsets
        await withCheckedContinuation { continuation in
            presenter.dismiss(animated: false) { continuation.resume() }
        }
        second.releaseChrome(of: early)
        try require(early.additionalSafeAreaInsets.top == 0, "dismissed screen kept old chrome inset")
        let retry = TelegramNavigationController(rootViewController: early)
        retry.modalPresentationStyle = .pageSheet
        await withCheckedContinuation { continuation in
            presenter.present(retry, animated: false) { continuation.resume() }
        }
        try await Task.sleep(for: .milliseconds(150))
        try require(
            early.additionalSafeAreaInsets == retainedInsets,
            "retry accumulated chrome inset: old=\(retainedInsets), new=\(early.additionalSafeAreaInsets)",
        )
    }
}
#endif
