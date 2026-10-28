// TelegramGrowingPresentation.swift

import ObjectiveC
import UIKit

// MARK: - UIViewController + growing presentation

extension UIViewController {
    /// Presents `controller` growing out of `source` and shrinking back into it on dismissal: UIKit's zoom transition,
    /// which on iOS 26 morphs a sheet out of the glass button that opened it, as Telegram's glass buttons grow into
    /// what they open (AttachmentController's paperclip morph). A source off screen, or the screen's own view,
    /// presents as usual.
    func presentGrowing(
        _ controller: UIViewController,
        from source: UIView?,
        animated: Bool = true,
        completion: (() -> Void)? = nil,
    ) {
        if let source, source.window != nil, source !== view {
            controller.preferredTransition = .zoom { [weak source] _ in source?.window == nil ? nil : source }
            if let popover = controller.popoverPresentationController, popover.sourceView == nil,
               popover.barButtonItem == nil, popover.sourceItem == nil
            {
                popover.sourceView = source
                popover.sourceRect = source.bounds
            }
        }
        present(controller, animated: animated, completion: completion)
    }
}

// MARK: - UIBarButtonItem + telegramChromeView

extension UIBarButtonItem {
    private static var chromeViewKey: UInt8 = 0

    /// The glass button the classic navigation chrome draws for this item, for a sheet to grow out of.
    var telegramChromeView: UIView? {
        get { (objc_getAssociatedObject(self, &Self.chromeViewKey) as? WeakViewBox)?.view }
        set { objc_setAssociatedObject(self, &Self.chromeViewKey, WeakViewBox(newValue), .OBJC_ASSOCIATION_RETAIN) }
    }
}

// MARK: - WeakViewBox

private final class WeakViewBox {
    // MARK: Internal

    weak var view: UIView?

    init(_ view: UIView?) {
        self.view = view
    }
}
