// TelegramGlassNavigationMorph.swift

import UIKit

// MARK: - TelegramGlassPlatterHost

/// A screen whose own navigation bar has glass platters, which a push or pop morphs into the next screen's.
@MainActor protocol TelegramGlassPlatterHost: AnyObject {
    var telegramGlassPlatters: [TelegramGlassPlatter] { get }
}

// MARK: - TelegramGlassNavigationMorph

/// Telegram 13's navigation bar glass transition (NavigationBarPlatterTransitionView, NavigationBarGlassAnimation),
/// which re-creates UIKit's iOS 26 bar: the titles ride their screens while both bars' glass platters are drawn once,
/// standing above both screens, and morph from the outgoing bar's layout into the incoming one's.
///
/// Platters pair by role: the leading one and the right pills counted from the edge. A chat header's title pill is its
/// bar's second right pill (Telegram's `titlePillRole`) while the bar has at most one other, so Chats' compose pill
/// morphs into it; otherwise it pairs only with another title pill. A paired platter is one shape whose frame springs
/// to its new place while each bar's items stay where that bar has them, the old ones shrinking away and the new ones
/// growing in. A right pill only the incoming bar has grows out of the nearest pill nearer the edge; one only the
/// outgoing bar has collapses into it, and UIKit's glass container draws the liquid neck between them. Anything else,
/// a title pill included, materializes or dematerializes in place. An interactive pop keeps the
/// outgoing platters still while the finger drags, and runs the springs once the swipe is released.
///
/// iPhone Duo's side column and the row live apart: a column's shapes pair only with another column's, by position, and
/// a button that changes place between two screens leaves in one and arrives in the other.
@MainActor final class TelegramGlassNavigationMorph {
    // MARK: Private

    private enum Key: Hashable, Comparable {
        case leading
        case leadingSection(Int)
        case title
        case trailing(Int)
        /// A shape of iPhone Duo's side column, counted from the top.
        case column(Int)
    }

    /// One shape of the overlay and the real platters it stands in for.
    private final class Piece {
        // MARK: Internal

        let key: Key
        let glass: UIVisualEffectView
        var source: TelegramGlassPlatter?
        var destination: TelegramGlassPlatter?
        var sourceFrame: CGRect?
        var destinationFrame: CGRect?
        /// Each bar's items, lent live to the overlay while the morph runs.
        var sourceItems: TelegramGlassLoan?
        var destinationItems: TelegramGlassLoan?
        /// The outgoing bar's platter an incoming-only pill grows out of.
        var sourcePartner: TelegramGlassPlatter?
        /// The incoming bar's platter an outgoing-only pill collapses into.
        var destinationPartner: TelegramGlassPlatter?
        /// Where an unpaired platter starts or ends: its partner's frame, or nil to (de)materialize in place.
        var partnerFrame: CGRect?
        var identicalItems = false

        init(key: Key, glass: UIVisualEffectView) {
            self.key = key
            self.glass = glass
        }
    }

    private enum Spring {
        /// NavigationBarGlassAnimation's `transition` spring.
        static let duration: TimeInterval = 0.416
        static let bounce: CGFloat = 0.25
        /// A collapsing platter waits this long before it moves (`matchedMinDelay`).
        static let collapseDelay: TimeInterval = 0.083
        /// Items shrink to and grow from this scale (`matchScale`).
        static let itemScale: CGFloat = 0.2
        /// How long a title pill leaving in place takes to fade.
        static let titleFadeDuration: TimeInterval = 0.18
        /// The most the glass overlay may outlive the screens' transition.
        static let lingerLimit: TimeInterval = 1.5
    }

    /// How long new glass takes to draw: the bars' own glass stays until the overlay's shows, or the bar would flash
    /// empty for its first frames.
    static let glassDrawDelay: TimeInterval = 0.04

    private static var active = [TelegramGlassNavigationMorph]()

    private let navigationView: UIView
    private let overlay = UIView()
    private let container = UIVisualEffectView(effect: {
        let effect = UIGlassContainerEffect()
        effect.spacing = TelegramGlassPlatter.interSectionSpacing
        return effect
    }())
    private var pieces = [Piece]()
    private var lent = [TelegramGlassPlatter]()
    private var resolved = false
    private var animated = false
    private var transitionEnded = false
    private var springsSettled = false
    private var finished = false

    private init(navigationView: UIView) {
        self.navigationView = navigationView
        overlay.frame = navigationView.bounds
        overlay.isUserInteractionEnabled = false
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.frame = overlay.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addSubview(container)
    }

    // MARK: Internal

    /// Starts the morph for the push or pop `coordinator` animates; does nothing when neither bar has platters.
    static func run(
        in navigation: UINavigationController,
        coordinator: UIViewControllerTransitionCoordinator,
        from source: [TelegramGlassPlatter],
        to destination: [TelegramGlassPlatter],
        destinationView: UIView,
    ) {
        guard !source.isEmpty || !destination.isEmpty, let navigationView = navigation.view else { return }
        let morph = TelegramGlassNavigationMorph(navigationView: navigationView)
        morph.begin(source: source, destination: destination)
        guard !morph.pieces.isEmpty else {
            morph.finish()
            return
        }
        active.append(morph)
        let interactive = coordinator.isInteractive
        coordinator.animate(alongsideTransition: { [weak morph] _ in
            guard let morph else { return }
            // The incoming screen is in the window now, with its safe area: its bar can be measured where it comes
            // to rest, filling the navigation view.
            UIView.performWithoutAnimation { morph.resolveDestination(in: destinationView) }
            // One runloop turn: inside the alongside block UIKit's push curve would capture these springs.
            if !interactive { DispatchQueue.main.async { morph.animate() } }
        }, completion: { [weak morph] context in
            guard let morph else { return }
            morph.transitionEnded = true
            if context.isCancelled {
                morph.finish()
            } else {
                morph.finishIfSettled()
            }
        })
        if interactive {
            coordinator.notifyWhenInteractionChanges { [weak morph] context in
                guard let morph, !context.isCancelled else { return }
                morph.animate()
            }
        }
    }

    private static func keys(of platters: [TelegramGlassPlatter]) -> [Key: TelegramGlassPlatter] {
        let shown = platters.filter { platter in
            // A platter whose glass gives way to something else, such as a chat's row to its search, is not there.
            platter.hasVisibleItems && !platter.isHidden && !platter.glassView.isHidden
                && sequence(first: platter, next: \.superview).allSatisfy { $0.alpha > 0.01 && !$0.isHidden }
        }
        var result = [Key: TelegramGlassPlatter]()
        for (index, platter) in shown.filter(\.isInSideColumn).enumerated() {
            result[.column(index)] = platter
        }
        let row = shown.filter { !$0.isInSideColumn }
        // The pills that show, counted from the edge: a hidden one leaves no gap.
        let trailing = row.compactMap { platter -> (Int, TelegramGlassPlatter)? in
            guard case .trailing(let index) = platter.role else { return nil }
            return (index, platter)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
        for (index, platter) in trailing.enumerated() {
            result[.trailing(index)] = platter
        }
        for platter in row {
            switch platter.role {
            case .leading: result[.leading] = platter
            case .leadingSection(let index): result[.leadingSection(index)] = platter
            // The second right slot while it is free (NavigationBarPlatterTransitionView's `titlePill`).
            case .title where trailing.count <= 1: result[.trailing(1)] = platter
            case .title: result[.title] = platter
            case .trailing: break
            }
        }
        return result
    }

    /// The platter of `other` an unpaired right pill `key` grows out of or collapses into: the nearest one nearer the
    /// screen edge.
    private static func partner(of key: Key, in other: [Key: TelegramGlassPlatter]) -> TelegramGlassPlatter? {
        guard case .trailing(let index) = key else { return nil }
        return (0..<index).reversed().lazy.compactMap { other[.trailing($0)] }.first
    }

    private static func signature(of platter: TelegramGlassPlatter) -> String {
        platter.visibleItems
            .map { item in
                [item.accessibilityLabel, (item as? UIButton)?.title(for: .normal)].compactMap(\.self).joined()
            }
            .joined(separator: "|")
    }

    /// UIKit's materialize scale for a platter `size` large: 16 pt beyond it per axis, at most 1.2.
    private static func materializeScale(for size: CGSize) -> CGAffineTransform {
        let x = size.width > 0 ? min(1.2, (size.width + 16) / size.width) : 1.2
        let y = size.height > 0 ? min(1.2, (size.height + 16) / size.height) : 1.2
        return CGAffineTransform(scaleX: x, y: y)
    }

    /// Where items at `frame` stand inside glass whose frame is `glassFrame`.
    private static func center(of frame: CGRect, in glassFrame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX - glassFrame.minX, y: frame.midY - glassFrame.minY)
    }

    /// Lends `platter`'s items to `piece`'s glass, standing at `frame` while the glass is at `glassFrame`: inside the
    /// glass, which draws its content as the bar's glass does, rather than above it.
    private func lendItems(
        of platter: TelegramGlassPlatter,
        frame: CGRect,
        to piece: Piece,
        glassFrame: CGRect,
    ) -> TelegramGlassLoan {
        let loan = TelegramGlassLoan(platter: platter)
        loan.host.bounds = CGRect(origin: .zero, size: frame.size)
        loan.host.center = Self.center(of: frame, in: glassFrame)
        piece.glass.contentView.addSubview(loan.host)
        loan.lend()
        return loan
    }

    /// Pairs the platters, draws the outgoing ones in the overlay and takes every platter from its bar.
    private func begin(source: [TelegramGlassPlatter], destination: [TelegramGlassPlatter]) {
        let from = Self.keys(of: source)
        let to = Self.keys(of: destination)
        for key in Set(from.keys).union(to.keys).sorted() {
            let outgoing = from[key]
            let incoming = to[key]
            let piece = Piece(key: key, glass: UIVisualEffectView(effect: (outgoing ?? incoming)?.glassView.effect))
            piece.glass.cornerConfiguration = .capsule()
            piece.glass.clipsToBounds = false
            piece.glass.contentView.clipsToBounds = false
            piece.source = outgoing
            piece.destination = incoming
            if let outgoing, let incoming {
                piece.identicalItems = Self.signature(of: outgoing) == Self.signature(of: incoming)
            } else if let incoming {
                // A title pill with no platter in its slot on the other bar shows in place, never out of a neighbour.
                if incoming.role != .title { piece.sourcePartner = Self.partner(of: key, in: from) }
            } else if outgoing?.role != .title {
                piece.destinationPartner = Self.partner(of: key, in: to)
            }
            if let outgoing {
                let frame = outgoing.convert(outgoing.bounds, to: navigationView)
                piece.sourceFrame = frame
            } else if let partner = piece.sourcePartner {
                piece.partnerFrame = partner.convert(partner.bounds, to: navigationView)
            }
            pieces.append(piece)
        }
        for piece in pieces {
            if let start = piece.sourceFrame ?? piece.partnerFrame {
                piece.glass.frame = start
            } else {
                // Glass materializes from no effect; animating a glass view's opacity breaks its rendering.
                piece.glass.effect = nil
            }
            container.contentView.addSubview(piece.glass)
        }
        // The overlay is in the window before the items move into it, so that they never leave it.
        navigationView.addSubview(overlay)
        for piece in pieces {
            if let outgoing = piece.source, let frame = piece.sourceFrame {
                piece.sourceItems = lendItems(of: outgoing, frame: frame, to: piece, glassFrame: frame)
            }
        }
        lent = pieces.flatMap { [$0.source, $0.destination].compactMap(\.self) }
        // The incoming bar is off screen and gives its glass up at once; the outgoing one once the overlay draws.
        for platter in lent where pieces.contains(where: { $0.destination === platter }) {
            platter.glassView.isHidden = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.glassDrawDelay) { [weak self] in
            guard let self, !finished else { return }
            for platter in lent {
                platter.glassView.isHidden = true
            }
        }
    }

    /// Measures the incoming bar where it comes to rest and sets the incoming items up to grow in.
    private func resolveDestination(in destinationView: UIView) {
        guard !resolved, !finished else { return }
        resolved = true
        destinationView.layoutIfNeeded()
        // The incoming screen's frame where it rests: the navigation view's bounds. A scroll view's bounds start at its
        // content offset, where the classic chrome stands.
        func restingFrame(of platter: TelegramGlassPlatter) -> CGRect {
            platter.convert(platter.bounds, to: destinationView)
                .offsetBy(dx: -destinationView.bounds.minX, dy: -destinationView.bounds.minY)
        }
        for piece in pieces {
            if let incoming = piece.destination {
                let frame = restingFrame(of: incoming)
                piece.destinationFrame = frame
                if piece.sourceFrame == nil, piece.partnerFrame == nil {
                    piece.glass.frame = frame
                    piece.glass.transform = Self.materializeScale(for: frame.size)
                }
                let glassFrame = piece.sourceFrame ?? piece.partnerFrame ?? frame
                let items = lendItems(of: incoming, frame: frame, to: piece, glassFrame: glassFrame)
                items.host.alpha = 0
                if !piece.identicalItems || piece.sourceItems == nil {
                    items.host.transform = CGAffineTransform(scaleX: Spring.itemScale, y: Spring.itemScale)
                }
                piece.destinationItems = items
            } else if let partner = piece.destinationPartner {
                piece.partnerFrame = restingFrame(of: partner)
            }
        }
    }

    private func animate() {
        guard !finished, !animated else { return }
        animated = true
        let group = DispatchGroup()
        for piece in pieces {
            let collapses = piece.destination == nil && piece.partnerFrame != nil
            // A chat's title pill leaving in place stands where the incoming screen's title arrives: grown and slow,
            // its glass edge would bend that title as it passes under it, so it fades at once where it is.
            let fadesTitle = piece.destination == nil && piece.partnerFrame == nil && piece.source?.role == .title
            let delay = collapses ? Spring.collapseDelay : 0
            group.enter()
            UIView.animate(
                springDuration: Spring.duration,
                bounce: Spring.bounce,
                delay: delay,
                options: [.beginFromCurrentState],
            ) {
                if let target = piece.destinationFrame {
                    piece.glass.transform = .identity
                    piece.glass.frame = target
                    piece.glass.effect = piece.destination?.glassView.effect
                } else if let partner = piece.partnerFrame {
                    piece.glass.frame = partner
                } else if !fadesTitle {
                    piece.glass.transform = Self.materializeScale(for: piece.glass.bounds.size)
                    piece.glass.effect = nil
                }
                // On the glass's spring, against it: each bar's items keep their place on screen.
                if let glassTarget = piece.destinationFrame ?? piece.partnerFrame {
                    if let host = piece.sourceItems?.host, let source = piece.sourceFrame {
                        host.center = Self.center(of: source, in: glassTarget)
                    }
                    if let host = piece.destinationItems?.host, let destination = piece.destinationFrame {
                        host.center = Self.center(of: destination, in: glassTarget)
                    }
                }
                if let items = piece.sourceItems?.host {
                    if !piece.identicalItems {
                        items.transform = CGAffineTransform(scaleX: Spring.itemScale, y: Spring.itemScale)
                    }
                    items.alpha = 0
                }
                if let items = piece.destinationItems?.host {
                    items.transform = .identity
                    items.alpha = 1
                }
            } completion: { _ in
                group.leave()
            }
            if fadesTitle {
                UIView.animate(withDuration: Spring.titleFadeDuration, delay: 0, options: [.curveEaseOut]) {
                    piece.glass.effect = nil
                }
            }
            // A collapsing pill has merged into its partner by the end of its spring; its glass then leaves.
            if collapses {
                UIView.animate(withDuration: 0.15, delay: delay + Spring.duration * 0.6) {
                    piece.glass.effect = nil
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            springsSettled = true
            finishIfSettled()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Spring.lingerLimit) { [weak self] in
            self?.finish()
        }
    }

    private func finishIfSettled() {
        if transitionEnded, springsSettled || !animated { finish() }
    }

    /// Hands the platters back to their bars and removes the overlay.
    private func finish() {
        guard !finished else { return }
        finished = true
        for platter in lent {
            platter.glassView.isHidden = false
        }
        // The items go home in the frame their glass comes back in.
        for piece in pieces {
            piece.sourceItems?.giveBack()
            piece.destinationItems?.giveBack()
        }
        overlay.removeFromSuperview()
        Self.active.removeAll { $0 === self }
    }
}
