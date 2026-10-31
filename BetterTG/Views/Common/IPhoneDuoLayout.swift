// IPhoneDuoLayout.swift

import UIKit

// MARK: - Wide grids

/// A grid's columns: a phone's up to a phone's width, then as many as keep the tiles a phone's size, on a screen as
/// wide as iPhone Duo's unfolded one.
func telegramGridColumns(phoneColumns: Int, width: CGFloat) -> Int {
    guard width > 480 else { return phoneColumns }
    return max(phoneColumns, Int(width / (440 / CGFloat(phoneColumns))))
}

// MARK: - IPhoneDuoLayout

/// iPhone Duo's layout for a window that fills one of its screens, nil everywhere else, so every other device keeps
/// its plain safe area.
///
/// Most of what the system reserves on the Duo is not an edge but a block in one corner, the status corner: clock,
/// connectivity, camera. UIKit widens that block into a full-edge safe inset. Beside it content keeps to the band
/// between the side insets. In unfolded landscape the rest of the inset is a strip for the vertical bar, which this
/// layout describes for our own bars; folded, our bars keep their buttons in the row. In unfolded portrait the block is
/// an island beside a horizontal bar.
///
/// | posture | window | safe insets (t, l, b, r) | block |
/// |---|---|---|---|
/// | folded portrait | 466x678 | 0, 0, 34, 84 | top right, 84x174 |
/// | folded landscape left | 678x466 | 0, 0, 34, 84 | bottom right, 84x82 |
/// | folded landscape right | 678x466 | 0, 84, 34, 0 | top left, 84x84 |
/// | unfolded portrait | 669x951 | 82, 0, 34, 0 | top right, 144x82 |
/// | unfolded landscape | 951x669 | 0, 0, 34, 84 | top right, 84x124 |
///
/// The block's position comes from this table because the system's regions are transitional for up to 0.6 s after a
/// rotation or fold. Its live region only grows it, as the corner follows what it shows: along the strip beside one,
/// both ways as the island of unfolded portrait.
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
        /// Where a horizontal bar's row starts in every posture: the top inset is 0 beside a side strip and 82 beside
        /// the island, and the system's bar stays at 24 in all of them.
        static let barTop: CGFloat = 24

        /// A capsule of `count` items.
        static func columnLength(count: Int) -> CGFloat {
            CGFloat(count) * columnItemPitch - 4
        }
    }

    /// Nil without a side strip: back and the icon buttons stay in the bar's row.
    private(set) var sideColumn: SideColumn?
    /// How far from the trailing edge a bar's trailing buttons stop beside the island: right at it, as the system's do.
    private(set) var trailingButtonsInset: CGFloat
    /// How far down the island reaches, 0 without one.
    private(set) var islandHeight: CGFloat
    /// The right inset of a panel at the bottom edge, which spans the strip and keeps clear only of a block that
    /// reaches
    /// its row.
    private(set) var bottomEdgeRightInset: CGFloat

    private let windowWidth: CGFloat

    /// The top safe area of a screen under the root beside the island: the search field under a bar's row then starts
    /// below it, and takes the whole width.
    var islandSafeTop: CGFloat {
        max(Metrics.barTop, islandHeight - TelegramGlassPlatter.height - ChatListNavigationSearchView.verticalInset)
    }

    /// Nil for a window that doesn't fill one of the Duo's screens.
    init?(windowSize: CGSize, safeInsets: UIEdgeInsets, reportedBlocks: () -> [CGRect]) {
        self.windowWidth = windowSize.width
        let isLandscape = windowSize.width > windowSize.height
        let portrait = CGSize(
            width: min(windowSize.width, windowSize.height),
            height: max(windowSize.width, windowSize.height),
        )
        func matches(_ size: CGSize) -> Bool {
            abs(portrait.width - size.width) <= 1 && abs(portrait.height - size.height) <= 1
        }
        // The blocks in the top right corner. A frame counts only when it touches the corner and stays under half the
        // window: a report after a rotation or fold can be another posture's shape.
        func topRightBlocks() -> [CGRect] {
            reportedBlocks().filter {
                $0.minY <= 0.5 && $0.maxX >= windowSize.width - 0.5
                    && $0.height < windowSize.height / 2 && $0.width < windowSize.width / 2
            }
        }
        self.islandHeight = 0
        if matches(CGSize(width: 466, height: 678)) {
            self.sideColumn = nil
            self.trailingButtonsInset = 0
            self.bottomEdgeRightInset = isLandscape && safeInsets.left == 0 ? safeInsets.right : 0
        } else if matches(CGSize(width: 669, height: 951)) {
            self.bottomEdgeRightInset = 0
            if isLandscape {
                // The height of a block at least 124 pt tall and as wide as the strip.
                let minY = topRightBlocks()
                    .filter { abs($0.width - safeInsets.right) <= 2 }
                    .reduce(CGFloat(124)) { max($0, $1.height) }
                self.sideColumn = SideColumn(
                    x: windowSize.width - Metrics.columnOuterMargin - Metrics.columnWidth,
                    minY: minY,
                )
                self.trailingButtonsInset = 0
            } else {
                self.sideColumn = nil
                let island = topRightBlocks().reduce(CGSize(width: 144, height: 82)) {
                    CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
                }
                self.trailingButtonsInset = island.width
                self.islandHeight = island.height
            }
        } else {
            return nil
        }
    }

    /// How far a bar's row moves from a top safe area `safeTop` to stand on the system's line beside the island.
    func rowTopOffset(safeTop: CGFloat) -> CGFloat {
        islandHeight > 0 && safeTop > Metrics.barTop && safeTop < islandHeight ? Metrics.barTop - safeTop : 0
    }

    /// `trailingButtonsInset` for a row that starts `rowTop` down: none once it stands below the island.
    func trailingButtonsInset(rowTop: CGFloat) -> CGFloat {
        rowTop >= islandHeight ? 0 : trailingButtonsInset
    }

    /// This layout for a column between `minX` and `maxX` of the window, in the column's coordinates. Only a column
    /// that
    /// reaches the strip has it, and a column that reaches the island keeps clear of it.
    func forPane(minX: CGFloat, maxX: CGFloat) -> IPhoneDuoLayout {
        var layout = self
        let reachesRight = maxX >= windowWidth - 1
        layout.sideColumn = sideColumn.flatMap { column in
            let inPane = column.x >= minX && column.x + Metrics.columnWidth <= maxX
            return inPane ? SideColumn(x: column.x - minX, minY: column.minY) : nil
        }
        layout.trailingButtonsInset = reachesRight ? trailingButtonsInset : 0
        layout.bottomEdgeRightInset = reachesRight ? bottomEdgeRightInset : 0
        return layout
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
        // A screen in a column of the split is measured against the column. It may be sliding in from the side.
        let pane = sequence(first: self as UIView, next: \.superview).first { $0 is TelegramSplitPaneView }
        let paneFrame = pane?.convert(pane?.bounds ?? .zero, to: window) ?? window.bounds
        guard abs(frame.width - paneFrame.width) <= 1, abs(frame.height - window.bounds.height) <= 1,
              abs(frame.minY) <= 1
        else { return nil }
        return window.windowIPhoneDuoLayout?.forPane(minX: paneFrame.minX, maxX: paneFrame.maxX)
    }
}

extension UIView {
    /// How much of its right safe inset a panel at the bottom edge gives up on iPhone Duo, where it spans the strip,
    /// a sheet's too.
    var iPhoneDuoBottomEdgeRightOutset: CGFloat {
        guard let duoLayout = window?.windowIPhoneDuoLayout else { return 0 }
        return max(0, safeAreaInsets.right - duoLayout.bottomEdgeRightInset)
    }
}

extension UIView {
    /// The status corner changes with what it shows, without a size change, and the bars read it as they lay out.
    func setIPhoneDuoBarsNeedLayout() {
        if self is TelegramListNavigationBar || self is TelegramChatNavigationBar
            || self is TelegramClassicNavigationChrome || next is TelegramNavigationController
        {
            setNeedsLayout()
        }
        for subview in subviews {
            subview.setIPhoneDuoBarsNeedLayout()
        }
    }
}

// MARK: - UIViewController + applyBarTopSafeArea

extension UIViewController {
    /// Starts the top safe area where the system's bars start: 24 pt from the top in every iPhone Duo posture and on a
    /// phone in landscape, which has no top inset of its own. Called from `viewWillLayoutSubviews` of a screen that
    /// fills the window; children inherit it.
    func applyBarTopSafeArea() {
        guard let window = view.window else { return }
        let fillsWindow = abs(view.bounds.width - window.bounds.width) <= 1
            && abs(view.bounds.height - window.bounds.height) <= 1
        let isLandscape = window.bounds.width > window.bounds.height
        let top: CGFloat =
            if let layout = view.iPhoneDuoLayout {
                // A full-screen modal's controls don't all know the island: it stays under it.
                if layout.islandHeight > 0 {
                    presentingViewController != nil ? 0 : layout.islandSafeTop - window.safeAreaInsets.top
                } else {
                    IPhoneDuoLayout.Metrics.barTop - window.safeAreaInsets.top
                }
            } else if fillsWindow, isLandscape, window.safeAreaInsets.top == 0 {
                IPhoneDuoLayout.Metrics.barTop
            } else {
                0
            }
        if additionalSafeAreaInsets.top != top { additionalSafeAreaInsets.top = top }
    }
}
