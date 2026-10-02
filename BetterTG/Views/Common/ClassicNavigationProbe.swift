// ClassicNavigationProbe.swift

#if DEBUG
    import UIKit

    @MainActor enum ClassicNavigationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        private final class Receiver: NSObject {
            var count = 0

            @objc func pressed() { count += 1 }
        }

        private final class Delegate: NSObject, UINavigationControllerDelegate {}

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-classic-navigation") else { return }
            let result: String
            do {
                try verifyPolicy()
                result = "Classic navigation probe passed: actual-owned-UINavigationBar/controller=true; "
                    + "initial/late/replaced-items/idempotence=true; native-push/pop/set-stack=true; "
                    + "previous-item-back/generated-title/explicit-back/display-mode=true; "
                    + "target/action/menu/customView/enabled/delegate-preserved=true; "
                    + "standard/scroll/compact/compact-scroll-blur=true; "
                    + "visible-pixels/back-tap/history/interactive-pop/RTL/safe-area/search=unverified; server-writes=0"
            } catch { result = "Classic navigation probe failed: \(error)" }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("classic-navigation-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(description: message) }
        }

        private static func verifyPolicy() throws {
            let receiver = Receiver()
            let action = #selector(Receiver.pressed)
            let root = UIViewController()
            root.title = "Root"
            let initial = UIBarButtonItem(title: "Save", style: .plain, target: receiver, action: action)
            initial.isEnabled = false
            root.navigationItem.rightBarButtonItem = initial
            let navigation = ClassicNavigation.controller(rootViewController: root)
            guard let bar = navigation.navigationBar as? ClassicNavigationBar else {
                throw Failure(description: "factory did not create owned bar")
            }
            let delegate = Delegate()
            navigation.delegate = delegate
            navigation.loadViewIfNeeded()
            navigation.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            navigation.view.setNeedsLayout()
            navigation.view.layoutIfNeeded()
            layout(bar)
            try require(
                initial.hidesSharedBackground && !initial.isEnabled
                        && initial.target === receiver && initial.action == action,
                "initial policy changed action or disabled state",
            )
            guard let generatedBack = root.navigationItem.backBarButtonItem else {
                throw Failure(description: "missing native previous-item back")
            }
            try require(
                generatedBack.hidesSharedBackground && generatedBack.title == "Root"
                        && generatedBack.target == nil && generatedBack.action == nil
                        && root.navigationItem.leftBarButtonItem == nil,
                "back was replaced with custom pop action",
            )
            let child = UIViewController()
            child.title = "Child"
            navigation.pushViewController(child, animated: false)
            layout(bar)
            try require(
                navigation.topViewController === child && bar.backItem === root.navigationItem
                        && navigation.delegate === delegate,
                "push/delegate/native back source changed",
            )
            let customView = UIButton(type: .system)
            customView.configuration = .plain()
            customView.accessibilityLabel = "Cancel fixture"
            let customItem = UIBarButtonItem(customView: customView)
            let late = UIBarButtonItem(title: "More", style: .plain, target: receiver, action: action)
            let menu = UIMenu(children: [UIAction(title: "Fixture", handler: { _ in })])
            late.menu = menu
            let installedMenu = late.menu
            child.navigationItem.leftBarButtonItem = customItem
            child.navigationItem.rightBarButtonItems = [late, UIBarButtonItem(systemItem: .add)]
            layout(bar)
            try require(
                customItem.hidesSharedBackground && customItem.customView === customView
                        && customView.accessibilityLabel == "Cancel fixture"
                        && late.hidesSharedBackground && late.target === receiver && late.action == action
                        && late.menu === installedMenu && child.navigationItem.rightBarButtonItems?.last?
                            .hidesSharedBackground == true,
                "late items lost identity/menu/custom view",
            )
            initial.isEnabled = true
            layout(bar)
            _ = UIApplication.shared.sendAction(action, to: initial.target, from: initial, for: nil)
            try require(initial.isEnabled && receiver.count == 1, "action routing or enabled state changed")
            root.navigationItem.backButtonTitle = "Origin"
            layout(bar)
            try require(
                root.navigationItem.backBarButtonItem === generatedBack && generatedBack.title == "Origin",
                "generated back title did not track source",
            )
            root.navigationItem.backButtonDisplayMode = .generic
            layout(bar)
            try require(
                generatedBack.title == nil && root.navigationItem.backButtonDisplayMode == .generic,
                "generated title overrode native generic mode",
            )
            root.navigationItem.backButtonDisplayMode = .minimal
            layout(bar)
            try require(
                generatedBack.title == nil && root.navigationItem.backButtonDisplayMode == .minimal,
                "minimal display mode changed",
            )
            let explicitBack = UIBarButtonItem(title: "Custom", style: .plain, target: receiver, action: action)
            explicitBack.isEnabled = false
            root.navigationItem.backBarButtonItem = explicitBack
            layout(bar)
            root.title = "Changed root"
            layout(bar)
            try require(
                root.navigationItem.backBarButtonItem === explicitBack && explicitBack.title == "Custom"
                        && explicitBack.hidesSharedBackground && !explicitBack.isEnabled
                        && explicitBack.target === receiver && explicitBack.action == action,
                "explicit back item was replaced or rewritten",
            )
            let replacement = UIBarButtonItem(systemItem: .close)
            child.navigationItem.rightBarButtonItems = [replacement]
            layout(bar)
            for _ in 0..<3 {
                layout(bar)
            }
            try require(
                child.navigationItem.rightBarButtonItem === replacement && replacement.hidesSharedBackground
                        && child.navigationItem.leftBarButtonItem === customItem
                        && root.navigationItem.backBarButtonItem === explicitBack,
                "replacement or repeated layout changed item ownership",
            )
            let popped = navigation.popViewController(animated: false)
            layout(bar)
            try require(popped === child && navigation.topViewController === root, "native pop failed")
            let final = UIViewController()
            final.title = "Replacement"
            final.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done)
            navigation.setViewControllers([root, final], animated: false)
            layout(bar)
            try require(
                navigation.topViewController === final && bar.backItem === root.navigationItem
                        && final.navigationItem.rightBarButtonItem?.hidesSharedBackground == true
                        && navigation.delegate === delegate,
                "set-stack replacement bypassed policy",
            )
            try require(
                bar.standardAppearance.backgroundEffect != nil
                        && bar.scrollEdgeAppearance?.backgroundEffect != nil
                        && bar.compactAppearance?.backgroundEffect != nil
                        && bar.compactScrollEdgeAppearance?.backgroundEffect != nil
                        && bar.isTranslucent,
                "full-width blur appearance missing a metrics state",
            )
            let systemBar = UINavigationBar()
            let unownedItem = UINavigationItem(title: "Unowned")
            let unownedButton = UIBarButtonItem(systemItem: .add)
            unownedItem.rightBarButtonItem = unownedButton
            systemBar.setItems([unownedItem], animated: false)
            systemBar.setNeedsLayout()
            systemBar.layoutIfNeeded()
            try require(!unownedButton.hidesSharedBackground, "item policy leaked into unowned UIKit bar")
        }

        private static func layout(_ bar: UINavigationBar) {
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
        }
    }
#endif
