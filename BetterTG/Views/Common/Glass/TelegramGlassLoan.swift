// TelegramGlassLoan.swift

import UIKit

// MARK: - TelegramGlassLoan

/// Items a morph borrows live from their glass, as Telegram's transitions lend a bar's item containers and its title
/// pill's content (`lendContent`, `lendGlassPillContent`). They keep drawing as they do on screen, their colours and
/// animations included, where a picture of them would not: UIKit tints a one-colour label as it composites, which no
/// drawing of the label reproduces. The items move into `host`, which the morph places where their glass is, and go
/// back
/// with their constraints once the glass is theirs again.
@MainActor final class TelegramGlassLoan {
    /// Stands for the items' glass in the morph: their frames inside it are the ones they have in their glass.
    let host = UIView()

    private let views: [UIView]
    private weak var home: UIView?
    private var constraints = [NSLayoutConstraint]()
    private var autoresizing = [Bool]()
    private var isLent = false

    /// `views` are laid out in `home`, the glass's content view.
    init(views: [UIView], home: UIView) {
        self.views = views
        self.home = home
        host.isUserInteractionEnabled = false
    }

    /// The items of `platter`, which shows them in its glass.
    convenience init(platter: TelegramGlassPlatter) {
        self.init(views: platter.visibleItems, home: platter.glassView.contentView)
    }

    func lend() {
        guard !isLent, let home else { return }
        isLent = true
        home.layoutIfNeeded()
        // Every constraint that holds a lent view, wherever it is installed, waits for the view's return.
        constraints = sequence(first: home, next: \.superview).flatMap { ancestor in
            ancestor.constraints.filter { constraint in
                [constraint.firstItem, constraint.secondItem].contains { item in
                    guard let view = item as? UIView else { return false }
                    return views.contains { view.isDescendant(of: $0) }
                }
            }
        }
        NSLayoutConstraint.deactivate(constraints)
        autoresizing = views.map(\.translatesAutoresizingMaskIntoConstraints)
        for view in views {
            let frame = view.frame
            view.translatesAutoresizingMaskIntoConstraints = true
            host.addSubview(view)
            view.frame = frame
        }
    }

    /// Puts the items back in their glass. One the glass has let go of meanwhile, such as a bar item replaced while the
    /// morph ran, stays out.
    func giveBack() {
        defer { host.removeFromSuperview() }
        guard isLent, let home else { return }
        isLent = false
        for (view, autoresizes) in zip(views, autoresizing) where view.superview === host {
            home.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = autoresizes
        }
        // Only constraints whose views are all back in the glass's hierarchy.
        let root = Array(sequence(first: home, next: \.superview)).last ?? home
        NSLayoutConstraint.activate(constraints.filter { constraint in
            [constraint.firstItem, constraint.secondItem].allSatisfy { item in
                switch item {
                case let view as UIView: view.isDescendant(of: root)
                case let guide as UILayoutGuide: guide.owningView?.isDescendant(of: root) ?? false
                default: item == nil
                }
            }
        })
        constraints = []
        home.setNeedsLayout()
        home.superview?.setNeedsLayout()
    }
}
