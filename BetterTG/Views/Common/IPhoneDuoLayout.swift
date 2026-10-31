// IPhoneDuoLayout.swift

import UIKit

// MARK: - IPhoneDuoLayout

/// iPhone Duo's layout for a window that fills one of its screens, nil everywhere else, so every other device keeps
/// its plain safe area.
///
/// Most of what the system reserves on the Duo is not an edge but a block in one corner, the status corner: clock,
/// connectivity, camera. UIKit widens that block into a full-edge safe inset. Beside it content keeps to the band
/// between the side insets, and the rest of the inset is a strip for the system's vertical bar, which this layout
/// describes for our own bars. In unfolded portrait the block is an island beside a horizontal bar.
///
/// | posture | window | safe insets (t, l, b, r) | block |
/// |---|---|---|---|
/// | folded portrait | 466x678 | 0, 0, 34, 84 | top right, 84x174 |
/// | folded landscape left | 678x466 | 0, 0, 34, 84 | bottom right, 84x82 |
/// | folded landscape right | 678x466 | 0, 84, 34, 0 | top left, 84x84 |
/// | unfolded portrait | 669x951 | 82, 0, 34, 0 | top right, 134x82 |
/// | unfolded landscape | 951x669 | 0, 0, 34, 84 | top right, 84x124 |
///
/// The block's position comes from this table because the system's regions are transitional for up to 0.6 s after a
/// rotation or fold. Its live region only grows it, as the corner's height follows what it shows.
struct IPhoneDuoLayout: Equatable {
    /// Where the vertical bar's shapes go, in the window's coordinates.
    struct SideColumn: Equatable {
        /// The shapes' left edge.
        let x: CGFloat
        /// The first shape's top.
        let minY: CGFloat
    }

    /// The system's vertical bar, measured on iOS 27.2: 48 pt wide, 24 pt from the screen's edge, a capsule's items
    /// 52 pt apart and its shapes 12 pt apart.
    enum Metrics {
        static let columnWidth: CGFloat = 48
        static let columnOuterMargin: CGFloat = 24
        static let columnItemPitch: CGFloat = 52
        static let columnSpacing: CGFloat = 12
        /// Where a horizontal bar starts in every posture: the top inset is 0 beside a side strip and 82 beside the
        /// island, and the system's bar stays at 24 in all of them.
        static let barTop: CGFloat = 24

        /// A capsule of `count` items.
        static func columnLength(count: Int) -> CGFloat {
            CGFloat(count) * columnItemPitch - 4
        }
    }

    /// Nil without a side strip: back and the icon buttons stay in the bar's row.
    let sideColumn: SideColumn?
    /// How much further than the safe area a bar's trailing buttons stay from the trailing edge, clear of the island.
    let trailingButtonsInset: CGFloat
    /// The right inset of a panel at the bottom edge, which spans the strip and keeps clear only of a block that
    /// reaches
    /// its row.
    let bottomEdgeRightInset: CGFloat

    /// Nil for a window that doesn't fill one of the Duo's screens.
    init?(windowSize: CGSize, safeInsets: UIEdgeInsets, reportedBlocks: () -> [CGRect]) {
        let isLandscape = windowSize.width > windowSize.height
        let portrait = CGSize(
            width: min(windowSize.width, windowSize.height),
            height: max(windowSize.width, windowSize.height),
        )
        func matches(_ size: CGSize) -> Bool {
            abs(portrait.width - size.width) <= 1 && abs(portrait.height - size.height) <= 1
        }
        func column(left: Bool, minY: CGFloat) -> SideColumn {
            let x = left
                ? Metrics.columnOuterMargin
                : windowSize.width - Metrics.columnOuterMargin - Metrics.columnWidth
            return SideColumn(x: x, minY: minY)
        }
        // The height of a top right block at least `height` tall and as wide as the strip.
        func topRightHeight(_ height: CGFloat) -> CGFloat {
            reportedBlocks()
                .filter {
                    $0.minY <= 0.5 && $0.maxX >= windowSize.width - 0.5 && $0.height < windowSize.height / 2
                        && abs($0.width - safeInsets.right) <= 2
                }
                .reduce(height) { max($0, $1.height) }
        }
        if matches(CGSize(width: 466, height: 678)) {
            if !isLandscape {
                self.sideColumn = column(left: false, minY: topRightHeight(174))
            } else if safeInsets.left > 0 {
                self.sideColumn = column(left: true, minY: 84)
            } else {
                self.sideColumn = column(left: false, minY: Metrics.barTop)
            }
            self.trailingButtonsInset = 0
            self.bottomEdgeRightInset = isLandscape && safeInsets.left == 0 ? safeInsets.right : 0
        } else if matches(CGSize(width: 669, height: 951)) {
            self.sideColumn = isLandscape ? column(left: false, minY: topRightHeight(124)) : nil
            self.trailingButtonsInset = isLandscape ? 0 : 134
            self.bottomEdgeRightInset = 0
        } else {
            return nil
        }
    }
}

// MARK: - UIWindow + windowIPhoneDuoLayout

private extension UIWindow {
    var windowIPhoneDuoLayout: IPhoneDuoLayout? {
        guard #available(iOS 27.1, *) else { return nil }
        return IPhoneDuoLayout(windowSize: bounds.size, safeInsets: safeAreaInsets) {
            reservedRegions(kind: .occlusion).map(\.frame)
        }
    }
}

// MARK: - UIView + iPhoneDuoLayout

extension UIView {
    /// The Duo's layout for a view that fills its window: not a sheet or a card, which keep their buttons in their bar.
    var iPhoneDuoLayout: IPhoneDuoLayout? {
        guard let window else { return nil }
        let frame = convert(bounds, to: window)
        guard abs(frame.width - window.bounds.width) <= 1, abs(frame.height - window.bounds.height) <= 1,
              abs(frame.minY) <= 1
        else { return nil }
        return window.windowIPhoneDuoLayout
    }
}

// MARK: - UIViewController + iPhoneDuoLayout

extension UIViewController {
    /// Starts the screen's top safe area where the system's bars start on the Duo. Called from
    /// `viewWillLayoutSubviews` of a screen that fills the window; children inherit it.
    func applyIPhoneDuoTopSafeArea() {
        guard let window = view.window else { return }
        let top = view.iPhoneDuoLayout == nil ? 0 : IPhoneDuoLayout.Metrics.barTop - window.safeAreaInsets.top
        if additionalSafeAreaInsets.top != top { additionalSafeAreaInsets.top = top }
    }
}
