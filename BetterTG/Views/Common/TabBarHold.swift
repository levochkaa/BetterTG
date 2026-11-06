// TabBarHold.swift

import UIKit

// MARK: - TabBarHold

/// A standing strip held by a finger, as the system's tab bar on iPhone Duo is held. A touch lifts the lens and
/// grows the capsule along the strip; then the capsule widens, spreads its items and shows their titles under the
/// icons. The numbers are the system's bar on iPhone Duo, measured on iOS 27.2 for Swiftgram's side tab bar and
/// ported from ArtWorkout's `GlassSegmentHold` (branch ios/feature/duo-tab-bar).
///
/// Frames are in the resting capsule's coordinates; item centres are along the strip, in the held capsule's.
struct TabBarHold: Equatable {
    /// The resting strip a hold starts from.
    struct Rest: Equatable {
        let size: CGSize
        /// Each item's centre along the strip, in the capsule's coordinates.
        let itemCenters: [CGFloat]
        /// The lens's size over the selected item at rest.
        let lensSize: CGSize
        /// A circle under the capsule keeps 6 pt of their 12 pt gap while the capsule grows.
        let hasAccessoryBelow: Bool
    }

    /// The items' scale in a lifted strip.
    static let liftedItemScale: CGFloat = 1.16
    /// A title's centre below its item's centre, in the item's unscaled coordinates.
    static let titleOffset: CGFloat = 15.3

    /// How far a pressed capsule grows along the strip, whatever its length.
    private static let pressedGrowth: CGFloat = 16.8
    /// The widened capsule's width for one to five items, and more.
    private static let expandedWidths: [CGFloat] = [79, 79, 77, 76, 75]
    private static let expandedIconScale: CGFloat = 1.09
    private static let expandedIconOffset: CGFloat = -7.5

    /// The held capsule.
    var capsuleFrame: CGRect
    var itemCenters: [CGFloat]
    /// The lifted lens's size. It runs past the capsule's sides.
    var liftedLensSize: CGSize
    /// The icons in their item's unscaled coordinates: grown on top of the item's scale, and moved up.
    var iconScale: CGFloat
    var iconOffset: CGFloat

    /// The strip between its states: `press` runs from the resting strip to the lifted one, `expand` from there to
    /// the widened one. Either can pass 1 or 0, as a spring overshoots.
    init(press: CGFloat, expand: CGFloat, rest: Rest) {
        let pressed = Self.pressed(rest)
        let expanded = Self.expanded(rest)
        let lifted = Self.mix(CGRect(origin: .zero, size: rest.size), pressed.capsuleFrame, press)
        let centers = zip(rest.itemCenters, pressed.itemCenters).map { Self.mix($0, $1, press) }
        self.capsuleFrame = Self.mix(lifted, expanded.capsuleFrame, expand)
        self.itemCenters = zip(centers, expanded.itemCenters).map { Self.mix($0, $1, expand) }
        self.liftedLensSize = CGSize(
            width: Self.mix(
                Self.mix(rest.lensSize.width, pressed.liftedLensSize.width, press),
                expanded.liftedLensSize.width,
                expand,
            ),
            height: Self.mix(
                Self.mix(rest.lensSize.height, pressed.liftedLensSize.height, press),
                expanded.liftedLensSize.height,
                expand,
            ),
        )
        self.iconScale = Self.mix(Self.mix(1, pressed.iconScale, press), expanded.iconScale, expand)
        self.iconOffset = Self.mix(0, expanded.iconOffset, expand)
    }

    private init(
        capsuleFrame: CGRect,
        itemCenters: [CGFloat],
        liftedLensSize: CGSize,
        iconScale: CGFloat,
        iconOffset: CGFloat,
    ) {
        self.capsuleFrame = capsuleFrame
        self.itemCenters = itemCenters
        self.liftedLensSize = liftedLensSize
        self.iconScale = iconScale
        self.iconOffset = iconOffset
    }

    /// Lifted by the touch: 16.8 pt longer, and wider in proportion.
    static func pressed(_ rest: Rest) -> Self {
        let scale = (rest.size.height + pressedGrowth) / max(1, rest.size.height)
        let size = CGSize(width: rest.size.width * scale, height: rest.size.height + pressedGrowth)
        let bottom = rest.size.height + (rest.hasAccessoryBelow ? min(pressedGrowth / 2, 6) : pressedGrowth / 2)
        return TabBarHold(
            capsuleFrame: CGRect(
                x: (rest.size.width - size.width) / 2,
                y: bottom - size.height,
                width: size.width,
                height: size.height,
            ),
            itemCenters: rest.itemCenters.map { $0 * scale },
            liftedLensSize: CGSize(width: size.width + 12, height: 92),
            iconScale: scale,
            iconOffset: 0,
        )
    }

    /// Widened, with the titles under the icons: 75–79 pt by 55n + 37 pt. The system's bar grows 10.5 pt down with
    /// nothing below it.
    static func expanded(_ rest: Rest) -> Self {
        let count = rest.itemCenters.count
        let width = expandedWidth(forItems: count)
        let height = 55 * CGFloat(count) + 37
        let bottom = rest.size.height + (rest.hasAccessoryBelow ? 6 : 10.5)
        let endInset: CGFloat = 41
        let centers = (0..<count).map { index -> CGFloat in
            guard count > 1 else { return height / 2 }
            return endInset + (height - 2 * endInset) * CGFloat(index) / CGFloat(count - 1)
        }
        return TabBarHold(
            capsuleFrame: CGRect(x: (rest.size.width - width) / 2, y: bottom - height, width: width, height: height),
            itemCenters: centers,
            liftedLensSize: CGSize(width: width + 13, height: 93),
            iconScale: expandedIconScale,
            iconOffset: expandedIconOffset,
        )
    }

    /// The widened capsule's width, which narrows a little as the items add up.
    static func expandedWidth(forItems count: Int) -> CGFloat {
        expandedWidths[max(0, min(count - 1, expandedWidths.count - 1))]
    }

    private static func mix(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private static func mix(_ start: CGRect, _ end: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: mix(start.minX, end.minX, progress),
            y: mix(start.minY, end.minY, progress),
            width: mix(start.width, end.width, progress),
            height: mix(start.height, end.height, progress),
        )
    }

    /// The lens's frame in the held capsule, around `center`. `liftedOutset` is what lifting adds on each side, so
    /// the lifted lens takes `liftedLensSize`.
    func lensFrame(center: CGFloat, liftedOutset: CGFloat) -> CGRect {
        let size = CGSize(
            width: liftedLensSize.width - 2 * liftedOutset,
            height: liftedLensSize.height - 2 * liftedOutset,
        )
        return CGRect(
            x: (capsuleFrame.width - size.width) / 2,
            y: center - size.height / 2,
            width: size.width,
            height: size.height,
        )
    }

    /// The item under the lens after the finger moved `translation` from the pressed item. It is not the item under
    /// the finger: the held items lie farther apart than the resting ones.
    func itemIndex(startIndex: Int, translation: CGFloat) -> Int {
        guard !itemCenters.isEmpty else { return 0 }
        let center = itemCenters[max(0, min(startIndex, itemCenters.count - 1))] + translation
        return itemCenters.indices.min { abs(itemCenters[$0] - center) < abs(itemCenters[$1] - center) } ?? 0
    }
}

// MARK: - TabBarHoldSpring

/// A spring stepped by hand. UIKit drives the system's bar frame by frame, so its capsule, items and lens stay one
/// motion, and the lens's own stretch reacts to real movement instead of a jump in its coordinates.
struct TabBarHoldSpring: Equatable {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat
    let stiffness: CGFloat
    let damping: CGFloat

    init(value: CGFloat, target: CGFloat? = nil, stiffness: CGFloat, damping: CGFloat) {
        self.value = value
        self.target = target ?? value
        self.stiffness = stiffness
        self.damping = damping
    }

    /// Springs fitted to the frames of the system's tab bar as a finger holds it and widens it.
    static func press(at value: CGFloat = 0) -> Self { Self(value: value, stiffness: 900, damping: 60) }
    static func expand(at value: CGFloat = 0) -> Self { Self(value: value, stiffness: 279, damping: 16.7) }
    static func lens(at value: CGFloat) -> Self { Self(value: value, stiffness: 625, damping: 45) }

    mutating func advance(by time: CGFloat) {
        let step: CGFloat = 1 / 480
        var remaining = time
        while remaining > 0 {
            let interval = min(step, remaining)
            velocity += (-stiffness * (value - target) - damping * velocity) * interval
            value += velocity * interval
            remaining -= interval
        }
    }

    func isSettled(within tolerance: CGFloat) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }
}
