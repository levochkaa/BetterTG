// ComposerKeyboardEdgeView.swift

import UIKit

/// Telegram's wallpaper edge treatment, applied to BetterTG's solid chat background.
final class ComposerKeyboardEdgeView: UIView {
    // EdgeEffectView.generateEdgeGradient: positions /287, alpha normalized by216.
    // Keep its sampled curve rather than substituting a linear material/blur mask.
    private static let edgeStops: [(position: CGFloat, alpha: CGFloat)] = [
        (0, 216), (6, 215), (17, 214), (25, 213), (31, 212), (35, 211),
        (38, 210), (41, 209), (44, 208), (46, 207), (49, 206), (52, 205),
        (55, 204), (58, 203), (60, 202), (61, 201), (63, 200), (65, 199),
        (67, 198), (68, 197), (70, 196), (71, 195), (73, 194), (74, 193),
        (75, 192), (77, 191), (78, 190), (79, 189), (81, 188), (82, 187),
        (83, 186), (84, 185), (85, 184), (86, 183), (87, 182), (88, 181),
        (90, 179), (92, 177), (94, 175), (96, 173), (98, 171), (100, 168),
        (102, 166), (104, 164), (106, 161), (108, 159), (109, 157), (111, 154),
        (113, 152), (114, 150), (116, 147), (118, 144), (120, 141), (122, 138),
        (124, 135), (126, 132), (128, 129), (130, 126), (131, 124), (133, 121),
        (135, 118), (136, 116), (138, 113), (140, 110), (142, 107), (143, 105),
        (145, 102), (147, 99), (149, 96), (151, 93), (153, 90), (155, 87),
        (157, 84), (159, 81), (161, 78), (163, 75), (165, 72), (167, 69),
        (169, 66), (172, 62), (174, 59), (177, 55), (180, 51), (184, 46),
        (189, 41), (194, 36), (200, 30), (209, 23), (227, 12), (287, 0),
    ]

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var visible = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        isHidden = true
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 20)
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitAccessibilityContrast.self,
        ]) { (view: ComposerKeyboardEdgeView, _: UITraitCollection) in
            view.updateGradient()
        }
        updateGradient()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGradient()
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        isHidden = false
        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 20)
        }
        guard animated else {
            changes()
            isHidden = !visible
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: changes,
        ) { [weak self] _ in
            guard let self, self.visible == visible else { return }
            isHidden = !visible
        }
    }

    private func updateGradient() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let color = UIColor.systemBackground.resolvedColor(with: traitCollection)
        let fadeFraction = min(1, 60 / max(1, bounds.height))
        let stops = Self.edgeStops.reversed()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // ChatControllerNode uses85% for a solid wallpaper, with no extra blur.
        gradient.colors = stops.map { color.withAlphaComponent(0.85 * $0.alpha / 216).cgColor }
            + [color.withAlphaComponent(0.85).cgColor]
        gradient.locations = stops.map { NSNumber(value: (1 - $0.position / 287) * fadeFraction) } + [1]
        CATransaction.commit()
    }
}
