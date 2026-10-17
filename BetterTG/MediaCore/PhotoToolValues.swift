// PhotoToolValues.swift

import UIKit

// MARK: - PhotoTool

/// The photo editor's slider tools (PGPhotoTool's `isSimple` tools) in TGPhotoToolsController's list order. Soften
/// Skin (PGSkinTool) leads it and shows only for a photo with a face.
enum PhotoTool: CaseIterable {
    case skin
    case enhance
    case exposure
    case contrast
    case saturation
    case warmth
    case fade
    case highlights
    case shadows
    case vignette
    case grain
    case sharpen

    var titleKey: String {
        switch self {
        case .skin: "PhotoEditor.SkinTool"
        case .enhance: "PhotoEditor.EnhanceTool"
        case .exposure: "PhotoEditor.ExposureTool"
        case .contrast: "PhotoEditor.ContrastTool"
        case .saturation: "PhotoEditor.SaturationTool"
        case .warmth: "PhotoEditor.WarmthTool"
        case .fade: "PhotoEditor.FadeTool"
        case .highlights: "PhotoEditor.HighlightsTool"
        case .shadows: "PhotoEditor.ShadowsTool"
        case .vignette: "PhotoEditor.VignetteTool"
        case .grain: "PhotoEditor.GrainTool"
        case .sharpen: "PhotoEditor.SharpenTool"
        }
    }

    /// The tool's `minimumValue`: the one-sided tools start at zero.
    var minimumValue: Int {
        switch self {
        case .enhance, .fade, .grain, .sharpen, .skin, .vignette: 0
        case .contrast, .exposure, .highlights, .saturation, .shadows, .warmth: -100
        }
    }

    /// PGPhotoTool's `requiresFaces`: TGPhotoToolsController leaves the tool out when no face was found.
    var requiresFaces: Bool {
        self == .skin
    }

    var maximumValue: Int {
        100
    }

    /// PGPhotoTool's `stringValue`: the value over the range's end with two decimals, or nothing at zero.
    static func stringValue(_ value: Int, maximumValue: Int = 100) -> String? {
        guard value != 0 else { return nil }
        let fraction = Double(value) / Double(abs(maximumValue))
        return fraction > 0 ? String(format: "+%0.2f", fraction) : String(format: "%0.2f", fraction)
    }
}

// MARK: - PhotoTintValue

/// PGTintToolValue: a color for the shadows and one for the highlights, each with its intensity. A `nil` color is
/// Telegram's clear swatch, which leaves that half alone.
struct PhotoTintValue: Equatable {
    /// TGPhotoEditorTintToolView's `shadowsColors` after the clear swatch.
    static let shadowsColors: [UInt32] = [0xFF4D4D, 0xF48022, 0xFFCD00, 0x81D281, 0x71C5D6, 0x0072BC, 0x662D91]
    /// TGPhotoEditorTintToolView's `highlightsColors` after the clear swatch.
    static let highlightsColors: [UInt32] = [0xEF9286, 0xEACEA2, 0xF2E17C, 0xA4EDAE, 0x89DCE5, 0x2E8BC8, 0xCD98E5]

    var shadowsColor: UInt32?
    var highlightsColor: UInt32?
    var shadowsIntensity = 50
    var highlightsIntensity = 50

    /// PGTintTool's `shouldBeSkipped`.
    var isDefault: Bool {
        (highlightsIntensity <= 0 && shadowsIntensity <= 0) || (shadowsColor == nil && highlightsColor == nil)
    }

    static func components(of color: UInt32?) -> SIMD3<Float> {
        guard let color else { return .zero }
        return SIMD3(
            Float((color >> 16) & 0xFF) / 255,
            Float((color >> 8) & 0xFF) / 255,
            Float(color & 0xFF) / 255,
        )
    }

    static func uiColor(of color: UInt32) -> UIColor {
        let components = components(of: color)
        return UIColor(
            red: CGFloat(components.x),
            green: CGFloat(components.y),
            blue: CGFloat(components.z),
            alpha: 1,
        )
    }
}

// MARK: - PhotoCurve

/// PGCurvesValue: the curve through five levels, from the blacks to the whites, in percent.
struct PhotoCurve: Equatable {
    /// `PGCurveGranularity`.
    private static let granularity = 100
    /// `PGCurveDataStep`.
    private static let dataStep = 2
    private static let defaultLevels: [CGFloat] = [0, 25, 50, 75, 100]

    /// Blacks, shadows, midtones, highlights and whites.
    var levels = defaultLevels

    var isDefault: Bool {
        zip(levels, Self.defaultLevels).allSatisfy { abs($0 - $1) < .ulpOfOne }
    }

    /// The Catmull-Rom spline through `value1` and `value2` at `t`, which the curves and the histogram draw with.
    static func catmullRom(
        _ value0: CGFloat,
        _ value1: CGFloat,
        _ value2: CGFloat,
        _ value3: CGFloat,
        t: CGFloat,
        tt: CGFloat,
        ttt: CGFloat,
    ) -> CGFloat {
        let linear = (value2 - value0) * t
        let quadratic = (2 * value0 - 5 * value1 + 4 * value2 - value3) * tt
        let cubic = (3 * value1 - value0 - 3 * value2 + value3) * ttt
        return 0.5 * (2 * value1 + linear + quadratic + cubic)
    }

    /// `interpolateCurve`: the Catmull-Rom curve through the levels, for drawing, and every second of its points'
    /// heights, the 200 values the shader looks up.
    func interpolated() -> (points: [CGPoint], data: [Float]) {
        let edges = levels.map { $0 / 100 }
        let points = [
            CGPoint(x: -0.001, y: edges[0]),
            CGPoint(x: 0, y: edges[0]),
            CGPoint(x: 0.25, y: edges[1]),
            CGPoint(x: 0.5, y: edges[2]),
            CGPoint(x: 0.75, y: edges[3]),
            CGPoint(x: 1, y: edges[4]),
            CGPoint(x: 1.001, y: edges[4]),
        ]
        var data = [Float]()
        var interpolated = [points[0]]
        for index in 1..<(points.count - 2) {
            let point0 = points[index - 1]
            let point1 = points[index]
            let point2 = points[index + 1]
            let point3 = points[index + 2]
            for step in 1..<Self.granularity {
                let t = CGFloat(step) / CGFloat(Self.granularity)
                let tt = t * t
                let ttt = tt * t
                let x = Self.catmullRom(point0.x, point1.x, point2.x, point3.x, t: t, tt: tt, ttt: ttt)
                let y = max(0, min(1, Self.catmullRom(point0.y, point1.y, point2.y, point3.y, t: t, tt: tt, ttt: ttt)))
                if x > point0.x {
                    interpolated.append(CGPoint(x: x, y: y))
                }
                if (step - 1) % Self.dataStep == 0 {
                    data.append(Float(y))
                }
            }
            interpolated.append(point2)
        }
        interpolated.append(points[points.count - 1])
        return (interpolated, data)
    }
}

// MARK: - PhotoCurvesChannel

/// PGCurvesType.
enum PhotoCurvesChannel: CaseIterable {
    case luminance
    case red
    case green
    case blue

    var titleKey: String {
        switch self {
        case .luminance: "PhotoEditor.CurvesAll"
        case .red: "PhotoEditor.CurvesRed"
        case .green: "PhotoEditor.CurvesGreen"
        case .blue: "PhotoEditor.CurvesBlue"
        }
    }

    /// TGPhotoEditorCurvesToolView's `colorForCurveType`.
    var color: UIColor {
        switch self {
        case .luminance: .white
        case .red: UIColor(red: 0xED / 255, green: 0x3D / 255, blue: 0x4C / 255, alpha: 1)
        case .green: UIColor(red: 0x10 / 255, green: 0xEE / 255, blue: 0x9D / 255, alpha: 1)
        case .blue: UIColor(red: 0x33 / 255, green: 0x77 / 255, blue: 0xFB / 255, alpha: 1)
        }
    }
}

// MARK: - PhotoCurvesValue

/// PGCurvesToolValue: a luminance curve and one per color channel.
struct PhotoCurvesValue: Equatable {
    var luminance = PhotoCurve()
    var red = PhotoCurve()
    var green = PhotoCurve()
    var blue = PhotoCurve()

    /// PGCurvesTool's `shouldBeSkipped`.
    var isDefault: Bool {
        luminance.isDefault && red.isDefault && green.isDefault && blue.isDefault
    }

    subscript(channel: PhotoCurvesChannel) -> PhotoCurve {
        get {
            switch channel {
            case .luminance: luminance
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch channel {
            case .luminance: luminance = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }
}

// MARK: - PhotoBlurType

/// PGBlurToolType without Portrait, whose button TGPhotoEditorBlurToolView leaves out.
enum PhotoBlurType: CaseIterable {
    case off
    case radial
    case linear

    var titleKey: String {
        switch self {
        case .off: "PhotoEditor.BlurToolOff"
        case .radial: "PhotoEditor.BlurToolRadial"
        case .linear: "PhotoEditor.BlurToolLinear"
        }
    }
}

// MARK: - PhotoBlurValue

/// PGBlurToolValue: the blur's shape and the sharp part it leaves. `point` is the sharp part's center over the
/// photo's width from its left, and from the top of a square on the width centered on the photo. `falloff` and
/// `size` are where the blur starts and where it is full, from the center for Radial and from the line through it
/// for Linear, over the photo's width; the controls on screen measure them over the shorter side, as Telegram does.
/// `angle` turns Linear's band, in radians.
struct PhotoBlurValue: Equatable {
    /// TGPhotoEditorRadialBlurView's `TGRadialBlurMinimumFalloff`.
    static let minimumFalloff: CGFloat = 0.1
    /// `TGRadialBlurMinimumDifference`: how much larger the full blur's edge stays than its start.
    static let minimumDifference: CGFloat = 0.02

    var type = PhotoBlurType.off
    var point = CGPoint(x: 0.5, y: 0.5)
    var falloff: CGFloat = 0.12
    var size: CGFloat = 0.24
    var angle: CGFloat = 0

    /// PGBlurTool's `shouldBeSkipped`.
    var isDefault: Bool {
        type == .off
    }
}

// MARK: - PhotoToolValues

/// The tool values PGPhotoEditorValues keeps for an edited photo (`toolValues`): the sliders, Tint, Blur and Curves.
struct PhotoToolValues: Equatable {
    var tint = PhotoTintValue()
    var blur = PhotoBlurValue()
    var curves = PhotoCurvesValue()

    /// Only the sliders off zero, so equal edits compare equal.
    private var sliders = [PhotoTool: Int]()

    /// PGPhotoEditorValues' `toolsApplied` negated: no tool would change the photo.
    var isDefault: Bool {
        sliders.isEmpty && tint.isDefault && blur.isDefault && curves.isDefault
    }

    subscript(tool: PhotoTool) -> Int {
        get { sliders[tool] ?? 0 }
        set {
            let clamped = min(max(newValue, tool.minimumValue), tool.maximumValue)
            sliders[tool] = clamped == 0 ? nil : clamped
        }
    }
}
