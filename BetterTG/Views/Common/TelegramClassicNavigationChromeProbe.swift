// TelegramClassicNavigationChromeProbe.swift

#if DEBUG
import UIKit

/// Checks that the classic chrome renders `UINavigationItem.prompt` and reserves its height, through the same KVO
/// path that pushed screens use. Launch with `-ui-probe-navigation-chrome-prompt`.
@MainActor enum TelegramClassicNavigationChromeProbe {
    // MARK: Private

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: Internal

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-navigation-chrome-prompt") else { return }
        Task { @MainActor in
            let result: String
            do {
                try verifyBar()
                try await verifyState(window: window)
                result = "Navigation chrome prompt probe passed: prompt row 30 pt above the title row, height and "
                    + "title offset restored without it, KVO reserves and releases the safe-area inset"
            } catch {
                result = "Navigation chrome prompt probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("navigation-chrome-prompt-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    private static func label(_ text: String, in view: UIView) -> UILabel? {
        view.subviews.compactMap { $0 as? UILabel }.first { $0.text == text }
    }

    private static func verifyBar() throws {
        let bar = TelegramClassicNavigationChrome()
        bar.topInset = 50
        let item = UINavigationItem(title: "Title")
        item.prompt = "Saving…"
        bar.configure(item: item, fallbackTitle: nil, showsBack: true, searchController: nil)
        bar.frame = CGRect(x: 0, y: 0, width: 402, height: bar.topInset + bar.contentHeight)
        bar.layoutIfNeeded()
        try require(bar.contentHeight == 74, "prompt height \(bar.contentHeight)")
        let prompt = label("Saving…", in: bar)
        let title = label("Title", in: bar)
        try require(prompt?.frame == CGRect(x: 16, y: 50, width: 370, height: 30), "prompt frame")
        try require(title?.frame.minY == 80, "title row below the prompt")
        item.prompt = nil
        bar.configure(item: item, fallbackTitle: nil, showsBack: true, searchController: nil)
        bar.layoutIfNeeded()
        try require(bar.contentHeight == 44 && title?.frame.minY == 50, "height without prompt")
    }

    private static func verifyState(window: UIWindow) async throws {
        guard let scene = window.windowScene else { throw Failure(description: "missing scene") }
        let host = UIWindow(windowScene: scene)
        host.frame = CGRect(x: -10000, y: 0, width: 402, height: 874)
        let controller = UIViewController()
        let navigation = UINavigationController(rootViewController: controller)
        host.rootViewController = navigation
        host.isHidden = false
        defer { host.isHidden = true }
        host.layoutIfNeeded()
        let state = TelegramNavigationChromeState(controller: controller, navigation: navigation)
        state.refresh()
        let base = controller.additionalSafeAreaInsets.top
        controller.navigationItem.prompt = "Reconnecting…"
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(controller.additionalSafeAreaInsets.top == base + 30, "prompt inset not reserved")
        controller.navigationItem.prompt = nil
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(controller.additionalSafeAreaInsets.top == base, "prompt inset not released")
        state.detach()
    }
}
#endif
