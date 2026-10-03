// ClassicNavigation.swift

import UIKit

// MARK: - ClassicNavigation

@MainActor enum ClassicNavigation {
    static func controller(rootViewController: UIViewController? = nil) -> UINavigationController {
        let controller = UINavigationController(navigationBarClass: ClassicNavigationBar.self, toolbarClass: nil)
        if let rootViewController { controller.setViewControllers([rootViewController], animated: false) }
        return controller
    }

    static func applyAppearance(to bar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.18)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.35)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.tintColor = .systemBlue
        bar.isTranslucent = true
    }
}

// MARK: - ClassicNavigationBar

/// Only app-owned navigation bars opt in. UIKit still owns layout, back actions,
/// history menus and transitions; no private subview or delegate replacement.
final class ClassicNavigationBar: UINavigationBar {
    override var items: [UINavigationItem]? {
        didSet { applyPolicy(to: items ?? []) }
    }

    private var applyingPolicy = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        ClassicNavigation.applyAppearance(to: self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        ClassicNavigation.applyAppearance(to: self)
    }

    override func setItems(_ items: [UINavigationItem]?, animated: Bool) {
        applyPolicy(to: items ?? [])
        super.setItems(items, animated: animated)
    }

    override func pushItem(_ item: UINavigationItem, animated: Bool) {
        applyPolicy(to: (items ?? []) + [item])
        super.pushItem(item, animated: animated)
    }

    override func layoutSubviews() {
        // UIKit invalidates bar layout when an already-displayed item's buttons
        // change. Reconcile before that layout, including items loaded after push.
        applyPolicy(to: items ?? [])
        super.layoutSubviews()
    }

    private func applyPolicy(to items: [UINavigationItem]) {
        guard !applyingPolicy else { return }
        applyingPolicy = true
        defer { applyingPolicy = false }
        for item in items {
            if item.searchController != nil {
                if item.preferredSearchBarPlacement != .stacked { item.preferredSearchBarPlacement = .stacked }
                if item
                    .searchBarPlacementAllowsToolbarIntegration
                {
                    item.searchBarPlacementAllowsToolbarIntegration = false
                }
            }
            for button in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) {
                hideSharedBackground(button)
            }
            // Leave an implicit Back and its adaptive title entirely to UIKit.
            if let back = item.backBarButtonItem { hideSharedBackground(back) }
        }
    }

    private func hideSharedBackground(_ item: UIBarButtonItem) {
        // This iOS 26 instance property is not a UIAppearance selector. It does
        // not alter the item's target/action, menu, custom view or enabled state.
        if !item.hidesSharedBackground { item.hidesSharedBackground = true }
    }
}
