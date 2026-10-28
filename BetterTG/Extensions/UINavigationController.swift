// UINavigationController.swift

import UIKit

final class TelegramNavigationController: UINavigationController, UIGestureRecognizerDelegate,
UINavigationControllerDelegate {
    /// Called after every completed push, pop or replacement, once classic chrome is settled.
    var onDidShow: ((UIViewController) -> Void)?

    private var chromeStates = [ObjectIdentifier: TelegramNavigationChromeState]()

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        super.setNavigationBarHidden(true, animated: false)

        let panGesture = UIPanGestureRecognizer(
            target: interactivePopGestureRecognizer?.delegate,
            action: Selector(("handleNavigationTransition:")),
        )
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
        interactivePopGestureRecognizer?.isEnabled = false
    }

    override func setNavigationBarHidden(_: Bool, animated _: Bool) {
        // Native iOS 26 navigation stays out of every transition, including its
        // first frame. Each screen either owns chrome or uses the 44pt host below.
        super.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        for state in chromeStates.values {
            state.layout()
        }
    }

    /// Re-reads a screen's navigation item and search for a change KVO doesn't report, such as a conditional search.
    func refreshChrome(of controller: UIViewController) {
        chromeStates[ObjectIdentifier(controller)]?.refresh()
    }

    func navigationController(
        _: UINavigationController, willShow controller: UIViewController, animated: Bool,
    ) {
        controller.loadViewIfNeeded()
        if !(controller is TelegramEmbeddedNavigationChrome) {
            let key = ObjectIdentifier(controller)
            let state = chromeStates[key] ?? TelegramNavigationChromeState(controller: controller, navigation: self)
            chromeStates[key] = state
            state.refresh()
        }
        // The bars' glass platters morph into the incoming screen's, as UIKit's iOS 26 bar does.
        if animated, let coordinator = transitionCoordinator,
           let source = coordinator.viewController(forKey: .from),
           coordinator.viewController(forKey: .to) === controller
        {
            if controller.view.bounds.size != view.bounds.size {
                controller.view.frame = view.bounds
            }
            TelegramGlassNavigationMorph.run(
                in: self,
                coordinator: coordinator,
                from: glassPlatters(of: source),
                to: glassPlatters(of: controller),
                destinationView: controller.view,
            )
        }
    }

    func navigationController(
        _: UINavigationController, didShow controller: UIViewController, animated _: Bool,
    ) {
        defer { onDidShow?(controller) }
        // Headers travel inside the same view as their content, so UIKit also
        // owns their exact push/pop and interactive-cancellation geometry.
        let retained = Set(viewControllers.map(ObjectIdentifier.init))
        for (key, state) in chromeStates where !retained.contains(key) {
            state.detach()
        }
        chromeStates = chromeStates.filter { retained.contains($0.key) }
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A trim/scrub drag belongs to its editor even when it moves toward Back.
        var touchedView = touch.view
        while let candidate = touchedView, candidate !== view {
            if candidate is VoiceRecordingTrimView || candidate is UISlider { return false }
            touchedView = candidate.superview
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1,
              transitionCoordinator == nil,
              let panGesture = gestureRecognizer as? UIPanGestureRecognizer
        else { return false }

        let velocity = panGesture.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) else { return false }
        let movesBack =
            switch view.effectiveUserInterfaceLayoutDirection {
            case .leftToRight:
                velocity.x > 0
            case .rightToLeft:
                velocity.x < 0
            @unknown default:
                velocity.x > 0
            }
        guard movesBack else { return false }
        // The swipe asks the screen as Back does (Telegram's NavigationController checks attemptNavigation).
        if let handler = topViewController as? TelegramNavigationAttemptHandling { return handler.attemptNavigation() }
        return true
    }

    private func glassPlatters(of controller: UIViewController) -> [TelegramGlassPlatter] {
        if let host = controller as? TelegramGlassPlatterHost { return host.telegramGlassPlatters }
        return chromeStates[ObjectIdentifier(controller)]?.bar.glassPlatters ?? []
    }
}
