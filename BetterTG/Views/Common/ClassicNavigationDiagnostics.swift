// ClassicNavigationDiagnostics.swift

#if DEBUG
    import UIKit

    /// Public UIKit values only; no titles, identifiers, peer data or subview inspection.
    @MainActor enum ClassicNavigationDiagnostics {
        private static var samples = [[String: Any]]()
        private static var editorSamples = [[String: Any]]()

        static func editorLayout(_ controller: UIViewController, fields: [UITextField], phase: String) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-diagnose-profile-editor-layout"),
                  let view = controller.viewIfLoaded, let window = view.window,
                  let navigation = controller.navigationController else { return }
            let bar = navigation.navigationBar
            let barFrame = bar.convert(bar.bounds, to: window)
            let safeFrame = view.convert(view.safeAreaLayoutGuide.layoutFrame, to: window)
            let sample: [String: Any] = [
                "phase": phase,
                "process": ProcessInfo.processInfo.processIdentifier,
                "isTop": navigation.topViewController === controller,
                "topItemMatches": bar.topItem === controller.navigationItem,
                "hasPrompt": controller.navigationItem.prompt != nil,
                "barHidden": navigation.isNavigationBarHidden,
                "barMinY": barFrame.minY,
                "barMaxY": barFrame.maxY,
                "safeMinY": safeFrame.minY,
                "safeMaxY": safeFrame.maxY,
                "additionalSafeTop": controller.additionalSafeAreaInsets.top,
                "fields": fields.map { field in
                    let frame = field.convert(field.bounds, to: window)
                    return ["minY": frame.minY, "maxY": frame.maxY, "focused": field.isFirstResponder] as [String: Any]
                },
            ]
            editorSamples.append(sample)
            editorSamples = Array(editorSamples.suffix(32))
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                  let data = try? JSONSerialization.data(
                      withJSONObject: editorSamples,
                      options: [.prettyPrinted, .sortedKeys],
                  )
            else { return }
            try? data.write(
                to: directory.appendingPathComponent("profile-editor-layout-diagnostics.json"),
                options: .atomic,
            )
        }

        static func didShow(_ navigation: UINavigationController) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-diagnose-classic-navigation") else { return }
            capture(navigation, phase: "did-show")
            DispatchQueue.main.async { [weak navigation] in
                guard let navigation else { return }
                navigation.viewIfLoaded?.layoutIfNeeded()
                capture(navigation, phase: "after-layout")
            }
        }

        private static func capture(_ navigation: UINavigationController, phase: String) {
            let bar = navigation.navigationBar
            let stack = navigation.viewControllers
            let items = bar.items ?? []
            let expectedBack = stack.dropLast().last?.navigationItem
            let sample: [String: Any] = [
                "phase": phase,
                "process": ProcessInfo.processInfo.processIdentifier,
                "classicBar": bar is ClassicNavigationBar,
                "barInWindow": bar.window != nil,
                "barHidden": navigation.isNavigationBarHidden,
                "stackCount": stack.count,
                "barItemCount": items.count,
                "topIsStackTop": bar.topItem === stack.last?.navigationItem,
                "backIsPreviousStackItem": bar.backItem === expectedBack,
                "backLocalIndex": bar.backItem.flatMap { back in items.firstIndex { $0 === back } } ?? -1,
                "expectedBackLocalIndex": expectedBack.flatMap { back in items.firstIndex { $0 === back } } ?? -1,
                "standardBlur": bar.standardAppearance.backgroundEffect != nil,
                "scrollBlur": bar.scrollEdgeAppearance?.backgroundEffect != nil,
                "compactBlur": bar.compactAppearance?.backgroundEffect != nil,
                "compactScrollBlur": bar.compactScrollEdgeAppearance?.backgroundEffect != nil,
                "items": items.enumerated().map { index, item in
                    [
                        "localIndex": index,
                        "isTop": bar.topItem === item,
                        "isBack": bar.backItem === item,
                        "mode": item.backButtonDisplayMode.rawValue,
                        "hasTitle": item.title != nil,
                        "hasBackTitle": item.backButtonTitle != nil,
                        "hidesBack": item.hidesBackButton,
                        "hasBackAction": item.backAction != nil,
                        "searchActive": item.searchController?.isActive == true,
                        "back": item.backBarButtonItem.map(button) ?? [:],
                        "left": (item.leftBarButtonItems ?? []).map(button),
                        "right": (item.rightBarButtonItems ?? []).map(button),
                    ] as [String: Any]
                },
            ]
            samples.append(sample)
            samples = Array(samples.suffix(16))
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                  let data = try? JSONSerialization.data(
                      withJSONObject: samples,
                      options: [.prettyPrinted, .sortedKeys],
                  )
            else { return }
            try? data.write(
                to: directory.appendingPathComponent("classic-navigation-diagnostics.json"),
                options: .atomic,
            )
        }

        private static func button(_ item: UIBarButtonItem) -> [String: Any] {
            [
                "hidesSharedBackground": item.hidesSharedBackground,
                "sharesBackground": item.sharesBackground,
                "groupItemCount": item.buttonGroup?.barButtonItems.count ?? 0,
                "style": item.style.rawValue,
                "hasTitle": item.title != nil,
                "hasImage": item.image != nil,
                "hasCustomView": item.customView != nil,
                "hasTarget": item.target != nil,
                "hasAction": item.action != nil,
                "hasMenu": item.menu != nil,
                "enabled": item.isEnabled,
            ]
        }
    }
#endif
