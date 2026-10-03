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

        private final class SearchObserver: NSObject, UISearchResultsUpdating, UISearchControllerDelegate,
            UISearchBarDelegate
        {
            func updateSearchResults(for _: UISearchController) {}
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-classic-navigation") else { return }
            let result: String
            do {
                try verifyPolicy()
                try verifySearchPolicy()
                result = "Classic navigation probe passed: actual-owned-UINavigationBar/controller=true; "
                    + "initial/late/replaced-items/idempotence=true; native-push/pop/set-stack=true; "
                    + "nil-back/native-title-policy/explicit-back/display-mode-preserved=true; "
                    + "target/action/menu/customView/enabled/delegate-preserved=true; "
                    + "standard/scroll/compact/compact-scroll-blur=true; "
                    + "owned-search-stacked/no-toolbar/initial/late/replaced/removed/idempotence=true; "
                    + "search-identities/text/selection/delegates/scroll-policy/unowned-preserved=true; "
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
            try require(
                root.navigationItem.backBarButtonItem == nil && root.navigationItem.title == "Root"
                        && root.navigationItem.backButtonTitle == nil
                        && root.navigationItem.backButtonDisplayMode == .default
                        && root.navigationItem.leftBarButtonItem == nil,
                "implicit back or native title policy was replaced",
            )
            let child = UIViewController()
            child.title = "Child"
            navigation.pushViewController(child, animated: false)
            layout(bar)
            try require(
                navigation.topViewController === child && bar.backItem === root.navigationItem
                        && navigation.delegate === delegate
                        && root.navigationItem.backBarButtonItem == nil
                        && child.navigationItem.backBarButtonItem == nil,
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
            root.title = "Renamed root"
            root.navigationItem.backButtonTitle = "Origin"
            layout(bar)
            try require(
                root.navigationItem.backBarButtonItem == nil && root.navigationItem.title == "Renamed root"
                        && root.navigationItem.backButtonTitle == "Origin"
                        && root.navigationItem.backButtonDisplayMode == .default,
                "title change installed an explicit back override",
            )
            root.navigationItem.backButtonDisplayMode = .generic
            layout(bar)
            try require(
                root.navigationItem.backBarButtonItem == nil && root.navigationItem.backButtonTitle == "Origin"
                        && root.navigationItem.backButtonDisplayMode == .generic,
                "native generic title policy changed",
            )
            root.navigationItem.backButtonDisplayMode = .minimal
            layout(bar)
            try require(
                root.navigationItem.backBarButtonItem == nil && root.navigationItem.backButtonTitle == "Origin"
                        && root.navigationItem.backButtonDisplayMode == .minimal,
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
            root.navigationItem.backBarButtonItem = nil
            root.navigationItem.backButtonDisplayMode = .default
            layout(bar)
            try require(
                root.navigationItem.backBarButtonItem == nil && root.navigationItem.backButtonTitle == "Origin"
                        && root.navigationItem.title == "Changed root"
                        && root.navigationItem.backButtonDisplayMode == .default,
                "cleared explicit back was synthesized again",
            )
            let popped = navigation.popViewController(animated: false)
            layout(bar)
            try require(
                popped === child && navigation.topViewController === root
                        && root.navigationItem.backBarButtonItem == nil,
                "native pop or implicit back changed",
            )
            let final = UIViewController()
            final.title = "Replacement"
            final.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done)
            navigation.setViewControllers([root, final], animated: false)
            layout(bar)
            try require(
                navigation.topViewController === final && bar.backItem === root.navigationItem
                        && final.navigationItem.rightBarButtonItem?.hidesSharedBackground == true
                        && navigation.delegate === delegate
                        && root.navigationItem.backBarButtonItem == nil
                        && final.navigationItem.backBarButtonItem == nil,
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

        private static func verifySearchPolicy() throws {
            let observer = SearchObserver()
            let root = UIViewController()
            let initial = UISearchController(searchResultsController: nil)
            root.navigationItem.searchController = initial
            root.navigationItem.hidesSearchBarWhenScrolling = false
            let navigation = ClassicNavigation.controller(rootViewController: root)
            navigation.loadViewIfNeeded()
            navigation.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            navigation.view.setNeedsLayout()
            navigation.view.layoutIfNeeded()
            let bar = navigation.navigationBar
            layout(bar)
            try requireSearchPolicy(root.navigationItem, initial)
            try require(!root.navigationItem.hidesSearchBarWhenScrolling, "initial search scrolling policy changed")

            let child = UIViewController()
            child.navigationItem.preferredSearchBarPlacement = .integrated
            child.navigationItem.searchBarPlacementAllowsToolbarIntegration = true
            navigation.pushViewController(child, animated: false)
            layout(bar)
            try require(
                child.navigationItem.searchController == nil
                    && child.navigationItem.preferredSearchBarPlacement == .integrated
                    && child.navigationItem.searchBarPlacementAllowsToolbarIntegration,
                "nil-search item preferences were mutated",
            )
            let late = UISearchController(searchResultsController: nil)
            late.searchResultsUpdater = observer
            late.delegate = observer
            late.searchBar.delegate = observer
            late.searchBar.text = "search fixture"
            let field = late.searchBar.searchTextField
            if let start = field.position(from: field.beginningOfDocument, offset: 2),
               let end = field.position(from: field.beginningOfDocument, offset: 5)
            {
                field.selectedTextRange = field.textRange(from: start, to: end)
            }
            let selection = selectionOffsets(field)
            try require(selection == [2, 5], "search selection fixture was not established")
            let scrolling = child.navigationItem.hidesSearchBarWhenScrolling
            child.navigationItem.searchController = late
            for _ in 0..<3 {
                layout(bar)
            }
            try requireSearchPolicy(child.navigationItem, late)
            try require(
                late.searchResultsUpdater === observer && late.delegate === observer
                    && late.searchBar.delegate === observer && late.searchBar.searchTextField === field
                    && late.searchBar.text == "search fixture" && selectionOffsets(field) == selection
                    && child.navigationItem.hidesSearchBarWhenScrolling == scrolling && !late.isActive,
                "search identity/content/selection/delegate/scrolling state changed",
            )
            let replacement = UISearchController(searchResultsController: nil)
            child.navigationItem.preferredSearchBarPlacement = .automatic
            child.navigationItem.searchBarPlacementAllowsToolbarIntegration = true
            child.navigationItem.searchController = replacement
            layout(bar)
            try requireSearchPolicy(child.navigationItem, replacement)
            child.navigationItem.searchController = nil
            child.navigationItem.preferredSearchBarPlacement = .integrated
            child.navigationItem.searchBarPlacementAllowsToolbarIntegration = true
            layout(bar)
            try require(
                child.navigationItem.searchController == nil
                    && child.navigationItem.preferredSearchBarPlacement == .integrated
                    && child.navigationItem.searchBarPlacementAllowsToolbarIntegration,
                "removed search was recreated or its preferences overwritten",
            )
            let systemBar = UINavigationBar()
            let unownedItem = UINavigationItem(title: "Unowned search")
            let unownedSearch = UISearchController(searchResultsController: nil)
            unownedItem.searchController = unownedSearch
            unownedItem.preferredSearchBarPlacement = .integrated
            unownedItem.searchBarPlacementAllowsToolbarIntegration = true
            systemBar.setItems([unownedItem], animated: false)
            layout(systemBar)
            try require(
                unownedItem.searchController === unownedSearch
                    && unownedItem.preferredSearchBarPlacement == .integrated
                    && unownedItem.searchBarPlacementAllowsToolbarIntegration,
                "search policy leaked to an unowned UIKit bar",
            )
        }

        private static func requireSearchPolicy(_ item: UINavigationItem, _ search: UISearchController) throws {
            try require(
                item.searchController === search && item.preferredSearchBarPlacement == .stacked
                    && !item.searchBarPlacementAllowsToolbarIntegration,
                "owned search is not stacked or still allows toolbar integration",
            )
        }

        private static func selectionOffsets(_ field: UITextField) -> [Int]? {
            guard let selection = field.selectedTextRange else { return nil }
            return [
                field.offset(from: field.beginningOfDocument, to: selection.start),
                field.offset(from: field.beginningOfDocument, to: selection.end),
            ]
        }

        private static func layout(_ bar: UINavigationBar) {
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
        }
    }
#endif
