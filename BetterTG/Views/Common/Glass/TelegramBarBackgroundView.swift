// TelegramBarBackgroundView.swift

import UIKit

// MARK: - TelegramBarBackgroundView

/// The light blur iOS 27 draws under a navigation bar (its scroll edge effect: a blurred backdrop under a 50% white
/// layer), drawn the same way on iOS 26: the content behind the bar blurred and washed with the system background,
/// both fading out over the bar's inner edge, with a 0.1 hairline at the edge. A bar at the bottom mirrors it.
final class TelegramBarBackgroundView: UIView {
    // MARK: Internal

    enum Edge {
        /// Under a navigation bar: the effect fades out toward its bottom.
        case top
        /// Under a bottom bar: the effect fades out toward its top.
        case bottom
    }

    /// How far before the inner edge the blur and the wash start to fade.
    static let fadeHeight: CGFloat = 16

    // MARK: Private

    private static let maskSourceName = "bettertg_bar_mask_source"
    /// The blur's radius at full strength on the half-scale backdrop, fitted to iOS 27.2's bar over the same content.
    private static let blurRadius: CGFloat = 4

    let edge: Edge

    /// Whether the hairline at the inner edge shows.
    var showsHairline = true {
        didSet { hairlineLayer.isHidden = !showsHairline }
    }

    private let backdropLayer: CALayer?
    private let maskSourceLayer = CALayer()
    private let veilLayer = CAGradientLayer()
    private let hairlineLayer = CALayer()
    private let fallbackView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let actionsDisabled = TelegramBarBackgroundLayerDelegate()
    private var appliedHeight: CGFloat = -1

    init(edge: Edge) {
        self.edge = edge
        self.backdropLayer = Self.makeBackdropLayer()
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        if let backdrop = backdropLayer {
            backdrop.setValue(0.5, forKey: "scale")
            backdrop.delegate = actionsDisabled
            layer.addSublayer(backdrop)
            maskSourceLayer.name = Self.maskSourceName
            maskSourceLayer.delegate = actionsDisabled
            backdrop.addSublayer(maskSourceLayer)
            backdrop.filters = [Self.makeVariableBlur()].compactMap(\.self)
        } else {
            fallbackView.isUserInteractionEnabled = false
            addSubview(fallbackView)
        }
        veilLayer.delegate = actionsDisabled
        layer.addSublayer(veilLayer)
        hairlineLayer.delegate = actionsDisabled
        layer.addSublayer(hairlineLayer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.updateColors() }
        updateColors()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        backdropLayer?.frame = bounds
        maskSourceLayer.frame = bounds
        fallbackView.frame = bounds
        veilLayer.frame = bounds
        let hairline = 1 / max(1, traitCollection.displayScale)
        hairlineLayer.frame = CGRect(
            x: 0,
            y: edge == .top ? size.height - hairline : 0,
            width: size.width,
            height: hairline,
        )
        if appliedHeight != size.height {
            appliedHeight = size.height
            let fade = min(Self.fadeHeight, size.height) / size.height
            let solid = NSNumber(value: Double(1 - fade))
            veilLayer.locations = edge == .top ? [0, solid, 1] : [0, NSNumber(value: Double(fade)), 1]
            maskSourceLayer.contents = Self.maskImage(height: size.height, edge: edge)
            updateColors()
        }
    }

    private static func makeBackdropLayer() -> CALayer? {
        let name = ["CA", "Backdrop", "Layer"].joined()
        guard let type = NSClassFromString(name) as? CALayer.Type else { return nil }
        return type.init()
    }

    private static func makeFilter(_ type: String, _ values: [String: Any]) -> NSObject? {
        let name = ["CA", "Filter"].joined()
        guard let filterClass = NSClassFromString(name) as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
              let filter = filterClass.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
        else { return nil }
        for (key, value) in values {
            filter.setValue(value, forKey: key)
        }
        return filter
    }

    /// The variable blur reads its strength from the sublayer named by `inputSourceSublayerName`, as Telegram's
    /// VariableBlurEffect does on iOS 26.
    private static func makeVariableBlur() -> NSObject? {
        makeFilter("variableBlur", [
            "inputRadius": blurRadius,
            "inputSourceSublayerName": maskSourceName,
            "inputNormalizeEdges": true,
        ])
    }

    /// Opaque where the blur is full, clear at the inner edge.
    private static func maskImage(height: CGFloat, edge: Edge) -> CGImage? {
        let size = CGSize(width: 1, height: max(1, ceil(height)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let fade = min(fadeHeight, size.height)
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1],
            ) else { return }
            switch edge {
            case .top:
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1, height: size.height - fade))
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: size.height - fade),
                    end: CGPoint(x: 0, y: size.height),
                    options: [],
                )
            case .bottom:
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: fade, width: 1, height: size.height - fade))
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: fade),
                    end: CGPoint(x: 0, y: 0),
                    options: [],
                )
            }
        }
        return image.cgImage
    }

    private func updateColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        // Fitted to iOS 27.2's bar over the same stripes: 0.56 white, 0.58 black in dark mode.
        let wash = dark ? UIColor(white: 0, alpha: 0.58) : UIColor(white: 1, alpha: 0.56)
        let clear = wash.withAlphaComponent(0)
        veilLayer.colors = edge == .top
            ? [wash.cgColor, wash.cgColor, clear.cgColor]
            : [clear.cgColor, wash.cgColor, wash.cgColor]
        hairlineLayer.backgroundColor = (dark ? UIColor(white: 1, alpha: 0.1) : UIColor(white: 0, alpha: 0.1)).cgColor
    }
}

// MARK: - TelegramBarBackgroundLayerDelegate

/// Keeps the backdrop's layers from animating their frames implicitly.
private final class TelegramBarBackgroundLayerDelegate: NSObject, CALayerDelegate {
    func action(for _: CALayer, forKey _: String) -> CAAction? { NSNull() }
}
