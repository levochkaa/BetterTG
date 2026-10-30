// TelegramBarBackgroundView.swift

import UIKit

// MARK: - TelegramBarBackgroundView

/// iOS 27.2's hard scroll edge effect (`ScrollEdgeEffectView`, `thinFilm(floating)`, read from a live bar), drawn the
/// same way on iOS 26, whose own effect differs. A wash of the system background lies behind a half-scale backdrop,
/// which blurs it with the content and lifts its saturation. The whole bar looks the same up to its inner edge, where
/// the effect stops sharply on a hairline.
final class TelegramBarBackgroundView: UIView {
    // MARK: Internal

    enum Edge {
        /// Under a navigation bar.
        case top
        /// Under a bottom bar.
        case bottom
    }

    // MARK: Private

    /// The `Pocket` layer's radius, at its half scale.
    private static let blurRadius: CGFloat = 2
    /// The strength in the red channel of the `Pocket` layer's `inputMaskImage`, every 16 of its 384 rows: the fine
    /// blur
    /// eases to a quarter toward the inner edge.
    private static let topMaskSamples: [CGFloat] = [
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        254, 251, 240, 223, 199, 172, 142, 115, 92, 76, 66, 63,
    ]
    private static let bottomMaskSamples: [CGFloat] = [
        63, 64, 68, 74, 82, 94, 108, 124, 141, 159, 178, 195, 211,
        225, 236, 244, 250, 254, 255, 255, 255, 255, 255, 255, 255,
    ]
    /// The `Pocket` layer's `colorMatrix`, in rows of red, green, blue and alpha.
    private static let saturationMatrix: [Float] = [
        1.1969, -0.1789, -0.0180, 0, 0.03,
        -0.0531, 1.0712, -0.0181, 0, 0.03,
        -0.0532, -0.1787, 1.2320, 0, 0.03,
        0, 0, 0, 1, 0,
    ]
    private static let colorMatrixType = "{CAColorMatrix=ffffffffffffffffffff}"
    /// iOS 26's variable blur has no blur fill. A wide blur over the fine one, fitted to iOS 27.2's bar over the same
    /// content, mixes the colours the same way.
    private static let backportFillRadius: CGFloat = 32

    private static let topMask = maskImage(samples: topMaskSamples)
    private static let bottomMask = maskImage(samples: bottomMaskSamples)

    let edge: Edge

    /// Whether the hairline at the inner edge shows.
    var showsHairline = true {
        didSet { hairlineLayer.isHidden = !showsHairline }
    }

    private let backdropLayer: CALayer?
    private let backportFillLayer: CALayer?
    private let washLayer = CALayer()
    private let hairlineLayer = CALayer()
    private let fallbackView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let actionsDisabled = TelegramBarBackgroundLayerDelegate()

    init(edge: Edge) {
        self.edge = edge
        self.backdropLayer = Self.makeBackdropLayer()
        self.backportFillLayer =
            if #available(iOS 27, *) {
                nil
            } else {
                backdropLayer == nil ? nil : Self.makeBackdropLayer()
            }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        washLayer.delegate = actionsDisabled
        if let backdrop = backdropLayer {
            layer.addSublayer(washLayer)
            backdrop.setValue(0.5, forKey: "scale")
            backdrop.masksToBounds = true
            backdrop.delegate = actionsDisabled
            layer.addSublayer(backdrop)
        } else {
            fallbackView.isUserInteractionEnabled = false
            addSubview(fallbackView)
            layer.addSublayer(washLayer)
        }
        if let fill = backportFillLayer {
            fill.setValue(0.5, forKey: "scale")
            fill.masksToBounds = true
            fill.delegate = actionsDisabled
            fill.filters = [Self.makeFilter("gaussianBlur", [
                "inputRadius": Self.backportFillRadius,
                "inputNormalizeEdges": true,
            ])].compactMap(\.self)
            layer.addSublayer(fill)
        }
        hairlineLayer.delegate = actionsDisabled
        layer.addSublayer(hairlineLayer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.updateAppearance() }
        updateAppearance()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        backdropLayer?.frame = bounds
        backportFillLayer?.frame = bounds
        fallbackView.frame = bounds
        washLayer.frame = bounds
        let hairline = 1 / max(1, traitCollection.displayScale)
        hairlineLayer.frame = CGRect(
            x: 0,
            y: edge == .top ? size.height - hairline : 0,
            width: size.width,
            height: hairline,
        )
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

    /// Red carries the fine blur's strength; green, always full, carries the blur fill's. The image is what the system
    /// passes: sRGB in little-endian xRGB.
    private static func maskImage(samples: [CGFloat]) -> CGImage? {
        let rows = 384
        var bytes = [UInt8](repeating: 255, count: rows * 4)
        for row in 0..<rows {
            let position = CGFloat(row) / CGFloat(rows - 1) * CGFloat(samples.count - 1)
            let index = min(Int(position), samples.count - 2)
            let value = samples[index] + (samples[index + 1] - samples[index]) * (position - CGFloat(index))
            bytes[row * 4] = 0
            bytes[row * 4 + 2] = UInt8(value)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: 1,
            height: rows,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent,
        )
    }

    private func makeBlurFilter(dark: Bool) -> NSObject? {
        var values: [String: Any] = [
            "inputRadius": Self.blurRadius,
            "inputNormalizeEdges": true,
            "inputDither": true,
            "inputFade": 0,
        ]
        if let mask = edge == .top ? Self.topMask : Self.bottomMask {
            values["inputMaskImage"] = mask
        }
        if #available(iOS 27, *) {
            values["inputBlurFillBlurRadius"] = 16
            values["inputBlurFillNormalOpacity"] = dark ? 0 : 0.25
            values["inputBlurFillDarkenOpacity"] = dark ? 0.6 : 0.4
            values["inputBlurFillLightenOpacity"] = dark ? 0.4 : 0.6
        }
        return Self.makeFilter("variableBlur", values)
    }

    private func updateAppearance() {
        let dark = traitCollection.userInterfaceStyle == .dark
        // `Replay Alpha (Light)` and `Replay Alpha (Dark)`.
        washLayer.backgroundColor = (dark ? UIColor(white: 0, alpha: 0.6) : UIColor(white: 1, alpha: 0.5)).cgColor
        hairlineLayer.backgroundColor = (dark ? UIColor(white: 1, alpha: 0.1) : UIColor(white: 0, alpha: 0.1)).cgColor
        backportFillLayer?.opacity = dark ? 0.5 : 0.55
        let matrix = Self.saturationMatrix.withUnsafeBytes {
            NSValue(bytes: $0.baseAddress!, objCType: Self.colorMatrixType)
        }
        backdropLayer?.filters = [
            makeBlurFilter(dark: dark),
            Self.makeFilter("colorMatrix", ["inputColorMatrix": matrix]),
            Self.makeFilter("sdrNormalize", ["inputClamp": true, "inputClampPreserveHue": true]),
        ].compactMap(\.self)
    }
}

// MARK: - TelegramBarBackgroundLayerDelegate

/// Keeps the backdrop's layers from animating their frames implicitly.
private final class TelegramBarBackgroundLayerDelegate: NSObject, CALayerDelegate {
    func action(for _: CALayer, forKey _: String) -> CAAction? { NSNull() }
}
