// PhotoToolsRenderer.swift

import CoreGraphics
import Foundation
import Metal

// MARK: - PhotoToolsSource

/// A picture's pixels prepared for PhotoToolsRenderer, kept so the editor's preview re-renders without drawing the
/// picture again. Holds Enhance's tile histograms once a render needs them.
final class PhotoToolsSource: @unchecked Sendable {
    let width: Int
    let height: Int

    /// Opaque 8-bit sRGB pixels, top row first, as GPUImage's framebuffers hold them.
    fileprivate let pixels: Data

    private let lock = NSLock()
    private var pixelBuffer: MTLBuffer?
    private var enhanceTableBuffer: MTLBuffer?

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let isDrawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard isDrawn else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// PGPhotoEnhanceLUTGenerator: contrast-limited histogram equalization of the HSV value over 4×4 tiles. Each
    /// tile's 256 bins hold its cumulative distribution with the distribution's first and last values, as the GL
    /// lookup texture stores them in bytes.
    private static func enhanceTable(pixels: Data, width: Int, height: Int) -> [Float]? {
        let segments = 4
        let bins = 256
        let tileArea = Int((Double(width) / Double(segments)).rounded(.down))
            * Int((Double(height) / Double(segments)).rounded(.down))
        guard tileArea > 0 else { return nil }
        let clipLimit = Int(max(1, 1.25 * Double(tileArea) / Double(bins)))
        let scale = 255 / Double(tileArea)
        var histograms = [Int](repeating: 0, count: segments * segments * bins)
        let tileColumns = (0..<width).map { Int(Double($0) * Double(segments) / Double(width)) }
        pixels.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            histograms.withUnsafeMutableBufferPointer { histogram in
                for y in 0..<height {
                    let tileRow = Int(Double(y) * Double(segments) / Double(height)) * segments
                    let rowStart = y * width * 4
                    for x in 0..<width {
                        let index = rowStart + x * 4
                        // The HSV value: the largest channel.
                        let value = Int(max(bytes[index], bytes[index + 1], bytes[index + 2]))
                        histogram[(tileRow + tileColumns[x]) * bins + value] += 1
                    }
                }
            }
        }
        var table = [Float](repeating: 0, count: segments * segments * bins * 3)
        for tile in 0..<(segments * segments) {
            var histogram = Array(histograms[(tile * bins)..<((tile + 1) * bins)])
            var clipped = 0
            for bin in 0..<bins where histogram[bin] > clipLimit {
                clipped += histogram[bin] - clipLimit
                histogram[bin] = clipLimit
            }
            let redistributed = clipped / bins
            let residual = clipped - redistributed * bins
            for bin in 0..<bins {
                histogram[bin] += redistributed + (bin < residual ? 1 : 0)
            }
            let firstFilled = histogram[0..<(bins - 1)].firstIndex { $0 != 0 } ?? bins - 1
            var cdfs = [Int](repeating: 0, count: bins)
            var cdf = 0
            for bin in firstFilled..<bins {
                cdf += histogram[bin]
                cdfs[bin] = Int(min(255, Double(cdf) * scale))
            }
            let cdfMin = Float(cdfs[firstFilled]) / 255
            let cdfMax = Float(cdfs[bins - 1]) / 255
            for bin in 0..<bins {
                let index = (tile * bins + bin) * 3
                table[index] = Float(cdfs[bin]) / 255
                table[index + 1] = cdfMin
                table[index + 2] = cdfMax
            }
        }
        return table
    }

    fileprivate func buffer(on device: MTLDevice) -> MTLBuffer? {
        lock.withLock {
            if let pixelBuffer { return pixelBuffer }
            let buffer = pixels.withUnsafeBytes { bytes -> MTLBuffer? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            pixelBuffer = buffer
            return buffer
        }
    }

    fileprivate func enhanceTable(on device: MTLDevice) -> MTLBuffer? {
        lock.withLock {
            if let enhanceTableBuffer { return enhanceTableBuffer }
            guard let table = Self.enhanceTable(pixels: pixels, width: width, height: height) else { return nil }
            let buffer = table.withUnsafeBytes { bytes -> MTLBuffer? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            enhanceTableBuffer = buffer
            return buffer
        }
    }
}

// MARK: - PhotoToolsRenderer

/// PGPhotoEditor's tool processing on Metal: the Soften Skin, Enhance, Sharpen and Blur passes, then
/// PGPhotoToolComposer's shader with the rest of the tools in their order. The kernels port the tools' GLSL and keep
/// 8 bits per channel between passes like GPUImage's framebuffers.
final class PhotoToolsRenderer: @unchecked Sendable {
    private struct Pipelines {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let skinOverlay: MTLComputePipelineState
        let skinMask: MTLComputePipelineState
        let skinCompose: MTLComputePipelineState
        let enhance: MTLComputePipelineState
        let sharpen: MTLComputePipelineState
        let blurVertical: MTLComputePipelineState
        let blurFocus: MTLComputePipelineState
        let compose: MTLComputePipelineState
    }

    /// The shader's `PhotoBlurParameters`: PGPhotoBlurPass's uniforms and the Gaussian's sampling radius, all floats.
    private struct BlurParameters {
        var type: Float = 0
        var pointX: Float = 0.5
        var pointY: Float = 0.5
        var size: Float = 0
        var falloff: Float = 0
        var angle: Float = 0
        var aspectRatio: Float = 1
        var sampleRadius: Float = 0

        /// A plain Gaussian's, for Soften Skin's high pass.
        init(sampleRadius: Int) {
            self.sampleRadius = Float(sampleRadius)
        }

        init(blur: PhotoBlurValue, width: Int, height: Int, sampleRadius: Int) {
            self.type = blur.type == .linear ? 2 : 1
            self.pointX = Float(blur.point.x)
            self.pointY = Float(blur.point.y)
            self.size = Float(blur.size)
            self.falloff = Float(blur.falloff)
            // PGPhotoBlurPass turns the angle a quarter for the shader.
            self.angle = Float(blur.angle + .pi / 2)
            self.aspectRatio = Float(height) / Float(width)
            self.sampleRadius = Float(sampleRadius)
        }
    }

    /// The shader's `PhotoToolParameters`: the tools' `updateParameters` values, all floats.
    private struct Parameters {
        var width: Float = 0
        var height: Float = 0
        var enhance: Float = 0
        var sharpness: Float = 0
        var highlights: Float = 1
        var shadows: Float = 1
        var contrast: Float = 1
        var fadeAmount: Float = 0
        var saturation: Float = 1
        var shadowsTintIntensity: Float = 0
        var highlightsTintIntensity: Float = 0
        var shadowsTintRed: Float = 0
        var shadowsTintGreen: Float = 0
        var shadowsTintBlue: Float = 0
        var highlightsTintRed: Float = 0
        var highlightsTintGreen: Float = 0
        var highlightsTintBlue: Float = 0
        var exposure: Float = 0
        var warmth: Float = 0
        var grain: Float = 0
        var vignette: Float = 0
        var skipTone: Float = 1
        /// PGPhotoSkinPass's amount.
        var skin: Float = 0

        init(tools: PhotoToolValues, grainSize: CGSize) {
            self.width = Float(grainSize.width)
            self.height = Float(grainSize.height)
            self.enhance = Float(tools[.enhance]) / 100
            self.sharpness = 0.125 + Float(tools[.sharpen]) / 100 * 0.6
            self.highlights = (Float(tools[.highlights]) * 0.75 + 100) / 100
            self.shadows = (Float(tools[.shadows]) * 0.55 + 100) / 100
            self.contrast = Float(tools[.contrast]) / 100 * 0.3 + 1
            self.fadeAmount = Float(tools[.fade]) / 100
            var saturationValue = Float(tools[.saturation]) / 100
            if saturationValue > 0 {
                saturationValue *= 1.05
            }
            self.saturation = saturationValue + 1
            let tint = tools.tint
            self.shadowsTintIntensity = tint.shadowsColor == nil ? 0 : Float(tint.shadowsIntensity) / 100
            self.highlightsTintIntensity = tint.highlightsColor == nil ? 0 : Float(tint.highlightsIntensity) / 100
            let shadowsColor = PhotoTintValue.components(of: tint.shadowsColor)
            self.shadowsTintRed = shadowsColor.x
            self.shadowsTintGreen = shadowsColor.y
            self.shadowsTintBlue = shadowsColor.z
            let highlightsColor = PhotoTintValue.components(of: tint.highlightsColor)
            self.highlightsTintRed = highlightsColor.x
            self.highlightsTintGreen = highlightsColor.y
            self.highlightsTintBlue = highlightsColor.z
            self.exposure = Float(tools[.exposure]) / 100
            self.warmth = Float(tools[.warmth]) / 100
            self.grain = Float(tools[.grain]) / 100 * 0.04
            self.vignette = Float(tools[.vignette]) / 100
            self.skipTone = tools.curves.isDefault ? 1 : 0
            self.skin = 0.75 * Float(tools[.skin]) / 100
        }
    }

    static let shared = PhotoToolsRenderer()

    /// GPUImageToneCurveFilter's table for YUGPUImageHighPassSkinSmoothingFilter's curve through (0, 0),
    /// (0.47, 0.57) and (1, 1): `splineCurve` over the 256 levels with `secondDerivative`'s natural spline, kept in
    /// bytes like the filter's texture.
    private static let skinToneCurve: [Float] = {
        let points: [(x: Double, y: Double)] = [(0, 0), (0.47 * 255, 0.57 * 255), (255, 255)]
        let count = points.count
        var matrix = [[Double]](repeating: [0, 0, 0], count: count)
        var result = [Double](repeating: 0, count: count)
        matrix[0][1] = 1
        matrix[count - 1][1] = 1
        for index in 1..<(count - 1) {
            let previous = points[index - 1]
            let point = points[index]
            let next = points[index + 1]
            matrix[index][0] = (point.x - previous.x) / 6
            matrix[index][1] = (next.x - previous.x) / 3
            matrix[index][2] = (next.x - point.x) / 6
            result[index] = (next.y - point.y) / (next.x - point.x) - (point.y - previous.y) / (point.x - previous.x)
        }
        for index in 1..<count {
            let factor = matrix[index][0] / matrix[index - 1][1]
            matrix[index][1] -= factor * matrix[index - 1][2]
            matrix[index][0] = 0
            result[index] -= factor * result[index - 1]
        }
        for index in stride(from: count - 2, through: 0, by: -1) {
            let factor = matrix[index][2] / matrix[index + 1][1]
            matrix[index][1] -= factor * matrix[index + 1][0]
            matrix[index][2] = 0
            result[index] -= factor * result[index + 1]
        }
        let secondDerivatives = (0..<count).map { result[$0] / matrix[$0][1] }
        var levels = [Double]()
        for index in 0..<(count - 1) {
            let point = points[index]
            let next = points[index + 1]
            let width = next.x - point.x
            // The C loop starts and ends on the points' truncated levels.
            for x in Int(point.x)..<Int(next.x) {
                let b = (Double(x) - point.x) / width
                let a = 1 - b
                let curve = (a * a * a - a) * secondDerivatives[index] + (b * b * b - b) * secondDerivatives[index + 1]
                levels.append(min(255, max(0, a * point.y + b * next.y + width * width / 6 * curve)))
            }
        }
        levels.append(points[count - 1].y)
        return (0..<256).map { level in
            let value = levels[min(level, levels.count - 1)]
            // The texture's bytes take the level plus the curve's offset from it, truncated.
            let byte = min(255, max(0, Float(level) + Float(value - Double(level))))
            return Float(UInt8(byte)) / 255
        }
    }()

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    
    struct PhotoToolParameters {
        float width;
        float height;
        float enhance;
        float sharpness;
        float highlights;
        float shadows;
        float contrast;
        float fadeAmount;
        float saturation;
        float shadowsTintIntensity;
        float highlightsTintIntensity;
        float shadowsTintRed;
        float shadowsTintGreen;
        float shadowsTintBlue;
        float highlightsTintRed;
        float highlightsTintGreen;
        float highlightsTintBlue;
        float exposure;
        float warmth;
        float grain;
        float vignette;
        float skipTone;
        float skin;
    };
    
    struct PhotoBlurParameters {
        float type;
        float pointX;
        float pointY;
        float size;
        float falloff;
        float angle;
        float aspectRatio;
        float sampleRadius;
    };
    
    constant float toolEpsilon = 0.005;
    constant float permTexUnit = 1.0 / 256.0;
    constant float permTexUnitHalf = 0.5 / 256.0;
    constant float grainsize = 2.3;
    
    static float4 loadPixel(device const uchar4 *pixels, uint2 size, int x, int y) {
        int clampedX = clamp(x, 0, int(size.x) - 1);
        int clampedY = clamp(y, 0, int(size.y) - 1);
        return float4(pixels[uint(clampedY) * size.x + uint(clampedX)]) / 255.0;
    }
    
    static uchar4 storePixel(float3 color) {
        float3 scaled = clamp(color, float3(0.0), float3(1.0)) * 255.0 + 0.5;
        return uchar4(uchar(scaled.r), uchar(scaled.g), uchar(scaled.b), uchar(255));
    }
    
    static float3 rgbToHsv(float3 c) {
        float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p = c.g < c.b ? float4(c.bg, K.wz) : float4(c.gb, K.xy);
        float4 q = c.r < p.x ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
        float d = q.x - min(q.w, q.y);
        float e = 1.0e-10;
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
    }
    
    static float3 hsvToRgb(float3 c) {
        float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, float3(0.0), float3(1.0)), float3(c.y));
    }
    
    // YUGPUImageGreenAndBlueChannelOverlayFragmentShaderString: the halved blue laid over the halved green.
    kernel void photoToolsSkinOverlay(
        device const uchar4 *source [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        constant uint2 &size [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        float3 image = loadPixel(source, size, int(gid.x), int(gid.y)).rgb * 0.5;
        float overlay = 2.0 * image.b * image.g;
        destination[gid.y * size.x + gid.x] = storePixel(float3(overlay));
    }
    
    // YUGPUImageStillImageHighPassFilter: the overlay's Gaussian across the rows after the pass down the columns, and
    // the overlay's difference from it; then YUCIHighPassSkinSmoothingMaskBoostFilterFragmentShaderString.
    kernel void photoToolsSkinMask(
        device const uchar4 *overlay [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        constant float *weights [[buffer(2)]],
        constant uint2 &size [[buffer(4)]],
        constant PhotoBlurParameters &blur [[buffer(5)]],
        device const uchar4 *vertical [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        int x = int(gid.x);
        int y = int(gid.y);
        int radius = int(blur.sampleRadius);
        float3 sum = loadPixel(vertical, size, x, y).rgb * weights[0];
        for (int offset = 1; offset <= radius; offset++) {
            float3 pair = loadPixel(vertical, size, x + offset, y).rgb + loadPixel(vertical, size, x - offset, y).rgb;
            sum += pair * weights[offset];
        }
        float blurred = round(clamp(sum.b, 0.0, 1.0) * 255.0) / 255.0;
        float highPass = clamp(loadPixel(overlay, size, x, y).b - blurred + 0.5, 0.0, 1.0);
        float hardLightColor = round(highPass * 255.0) / 255.0;
        for (int i = 0; i < 3; ++i) {
            if (hardLightColor < 0.5) {
                hardLightColor = hardLightColor * hardLightColor * 2.0;
            } else {
                hardLightColor = 1.0 - (1.0 - hardLightColor) * (1.0 - hardLightColor) * 2.0;
            }
        }
        float k = 255.0 / (164.0 - 75.0);
        hardLightColor = (hardLightColor - 75.0 / 255.0) * k;
        destination[gid.y * size.x + gid.x] = storePixel(float3(hardLightColor));
    }
    
    // GPUImageToneCurveFilter's lookup with the texture's linear filtering.
    static float skinToneCurve(constant float *curve, float value) {
        float position = value * 256.0 - 0.5;
        float lower = floor(position);
        int index = int(lower);
        float first = curve[clamp(index, 0, 255)];
        float second = curve[clamp(index + 1, 0, 255)];
        return mix(first, second, position - lower);
    }
    
    // The skin tone curve dissolved in by the amount (GPUImageDissolveBlendFilter), then
    // YUGPUImageHighpassSkinSmoothingCompositingFilterFragmentShaderString keeping the photo where the mask is light.
    kernel void photoToolsSkinCompose(
        device const uchar4 *source [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        constant float *curve [[buffer(2)]],
        constant PhotoToolParameters &parameters [[buffer(3)]],
        constant uint2 &size [[buffer(4)]],
        device const uchar4 *mask [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        int x = int(gid.x);
        int y = int(gid.y);
        float3 image = loadPixel(source, size, x, y).rgb;
        float3 toneCurved = float3(
            skinToneCurve(curve, image.r), skinToneCurve(curve, image.g), skinToneCurve(curve, image.b));
        toneCurved = round(clamp(toneCurved, float3(0.0), float3(1.0)) * 255.0) / 255.0;
        float3 dissolved = mix(image, toneCurved, float3(parameters.skin));
        dissolved = round(clamp(dissolved, float3(0.0), float3(1.0)) * 255.0) / 255.0;
        float maskValue = loadPixel(mask, size, x, y).b;
        destination[gid.y * size.x + gid.x] = storePixel(mix(image, dissolved, float3(1.0 - maskValue)));
    }
    
    // PGPhotoEnhanceInterpolationFilter: the tile's equalized value, read from the 256-bin table with the linear
    // filtering of the GL lookup texture.
    static float enhanceCurve(device const float *table, int tile, float value) {
        float position = value * 256.0;
        float start = floor(position);
        float fraction = position - start;
        int lower = clamp(int(start), 0, 255);
        int upper = clamp(int(start) + 1, 0, 255);
        int base = tile * 256 * 3;
        float cdf = mix(table[base + lower * 3], table[base + upper * 3], fraction);
        float cdfMin = mix(table[base + lower * 3 + 1], table[base + upper * 3 + 1], fraction);
        float cdfMax = mix(table[base + lower * 3 + 2], table[base + upper * 3 + 2], fraction);
        float range = cdfMax - cdfMin;
        return range > 0.0 ? (cdf - cdfMin) / range : 0.0;
    }
    
    static float enhanceValue(device const float *table, float2 texCoord, float value) {
        float2 coord = (clamp(texCoord, float2(0.125), float2(1.0 - 0.125001)) - 0.125) * 4.0;
        float2 frac = fract(coord);
        coord = floor(coord);
        int x = int(coord.x);
        int y = int(coord.y);
        float c1 = enhanceCurve(table, y * 4 + x, value);
        float c2 = enhanceCurve(table, y * 4 + x + 1, value);
        float c3 = enhanceCurve(table, (y + 1) * 4 + x, value);
        float c4 = enhanceCurve(table, (y + 1) * 4 + x + 1, value);
        float c12 = mix(c1, c2, frac.x);
        float c34 = mix(c3, c4, frac.x);
        return mix(c12, c34, frac.y);
    }
    
    kernel void photoToolsEnhance(
        device const uchar4 *source [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        device const float *table [[buffer(2)]],
        constant PhotoToolParameters &parameters [[buffer(3)]],
        constant uint2 &size [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        float2 texCoord = (float2(gid) + 0.5) / float2(size);
        float4 texel = loadPixel(source, size, int(gid.x), int(gid.y));
        // The RGB to HSV pass renders into an 8-bit framebuffer.
        float3 original = round(rgbToHsv(texel.rgb) * 255.0) / 255.0;
        float3 hsv = original;
        hsv.y = min(1.0, hsv.y * 1.2);
        hsv.z = min(1.0, enhanceValue(table, texCoord, hsv.z) * 1.1);
        destination[gid.y * size.x + gid.x] = storePixel(hsvToRgb(mix(original, hsv, float3(parameters.enhance))));
    }
    
    // PGPhotoSharpenPass.
    kernel void photoToolsSharpen(
        device const uchar4 *source [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        constant PhotoToolParameters &parameters [[buffer(3)]],
        constant uint2 &size [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        int x = int(gid.x);
        int y = int(gid.y);
        float3 textureColor = loadPixel(source, size, x, y).rgb;
        float3 leftTextureColor = loadPixel(source, size, x - 1, y).rgb;
        float3 rightTextureColor = loadPixel(source, size, x + 1, y).rgb;
        float3 topTextureColor = loadPixel(source, size, x, y + 1).rgb;
        float3 bottomTextureColor = loadPixel(source, size, x, y - 1).rgb;
        float centerMultiplier = 1.0 + 4.0 * parameters.sharpness;
        float edgeMultiplier = parameters.sharpness;
        float3 edges = leftTextureColor * edgeMultiplier + rightTextureColor * edgeMultiplier
            + topTextureColor * edgeMultiplier + bottomTextureColor * edgeMultiplier;
        destination[gid.y * size.x + gid.x] = storePixel(textureColor * centerMultiplier - edges);
    }
    
    // PGPhotoGaussianBlurFilter's first pass, down the columns.
    kernel void photoToolsBlurVertical(
        device const uchar4 *source [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        constant float *weights [[buffer(2)]],
        constant uint2 &size [[buffer(4)]],
        constant PhotoBlurParameters &blur [[buffer(5)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        int x = int(gid.x);
        int y = int(gid.y);
        int radius = int(blur.sampleRadius);
        float3 sum = loadPixel(source, size, x, y).rgb * weights[0];
        for (int offset = 1; offset <= radius; offset++) {
            float3 pair = loadPixel(source, size, x, y + offset).rgb + loadPixel(source, size, x, y - offset).rgb;
            sum += pair * weights[offset];
        }
        destination[gid.y * size.x + gid.x] = storePixel(sum);
    }
    
    // PGPhotoGaussianBlurFilter's second pass across the rows, then PGPhotoRadialBlurShaderString or
    // PGPhotoLinearBlurShaderString keeping the photo sharp around the point.
    kernel void photoToolsBlurFocus(
        device const uchar4 *source [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        constant float *weights [[buffer(2)]],
        constant uint2 &size [[buffer(4)]],
        constant PhotoBlurParameters &blur [[buffer(5)]],
        device const uchar4 *vertical [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        int x = int(gid.x);
        int y = int(gid.y);
        int radius = int(blur.sampleRadius);
        float3 sum = loadPixel(vertical, size, x, y).rgb * weights[0];
        for (int offset = 1; offset <= radius; offset++) {
            float3 pair = loadPixel(vertical, size, x + offset, y).rgb + loadPixel(vertical, size, x - offset, y).rgb;
            sum += pair * weights[offset];
        }
        // The blurred photo is kept in 8 bits like the filter's framebuffer.
        float3 blurredColor = round(clamp(sum, float3(0.0), float3(1.0)) * 255.0) / 255.0;
        float3 sharpColor = loadPixel(source, size, x, y).rgb;
        float2 texCoord = (float2(gid) + 0.5) / float2(size);
        float2 texCoordToUse = float2(texCoord.x, texCoord.y * blur.aspectRatio + 0.5 - 0.5 * blur.aspectRatio);
        float2 excludePoint = float2(blur.pointX, blur.pointY);
        float distanceFromCenter;
        if (blur.type > 1.5) {
            distanceFromCenter = abs((texCoordToUse.x - excludePoint.x) * cos(blur.angle)
                + (texCoordToUse.y - excludePoint.y) * sin(blur.angle));
        } else {
            distanceFromCenter = distance(excludePoint, texCoordToUse);
        }
        float value = clamp(distanceFromCenter / blur.size, 0.0, 1.0);
        // smoothstep(1.0, excludeFalloff, value) as GLSL computes it with reversed edges.
        float span = blur.falloff - 1.0;
        float ramp = span == 0.0 ? 0.0 : clamp((value - 1.0) / span, 0.0, 1.0);
        float sharpness = ramp * ramp * (3.0 - 2.0 * ramp);
        destination[gid.y * size.x + gid.x] = storePixel(mix(blurredColor, sharpColor, float3(sharpness)));
    }
    
    // PGPhotoToolAncillaryShaderString.
    static float getLuma(float3 rgbP) {
        return (0.299 * rgbP.r) + (0.587 * rgbP.g) + (0.114 * rgbP.b);
    }
    
    static float3 rgbToHsl(float3 color) {
        float3 hsl = float3(0.0);
        float minimum = min(min(color.r, color.g), color.b);
        float maximum = max(max(color.r, color.g), color.b);
        float delta = maximum - minimum;
        hsl.z = (maximum + minimum) / 2.0;
        if (delta == 0.0) {
            hsl.x = 0.0;
            hsl.y = 0.0;
        } else {
            if (hsl.z < 0.5) {
                hsl.y = delta / (maximum + minimum);
            } else {
                hsl.y = delta / (2.0 - maximum - minimum);
            }
            float deltaR = (((maximum - color.r) / 6.0) + (delta / 2.0)) / delta;
            float deltaG = (((maximum - color.g) / 6.0) + (delta / 2.0)) / delta;
            float deltaB = (((maximum - color.b) / 6.0) + (delta / 2.0)) / delta;
            if (color.r == maximum) {
                hsl.x = deltaB - deltaG;
            } else if (color.g == maximum) {
                hsl.x = (1.0 / 3.0) + deltaR - deltaB;
            } else if (color.b == maximum) {
                hsl.x = (2.0 / 3.0) + deltaG - deltaR;
            }
            if (hsl.x < 0.0) {
                hsl.x += 1.0;
            } else if (hsl.x > 1.0) {
                hsl.x -= 1.0;
            }
        }
        return hsl;
    }
    
    static float hueToRgb(float f1, float f2, float hue) {
        if (hue < 0.0) {
            hue += 1.0;
        } else if (hue > 1.0) {
            hue -= 1.0;
        }
        float res;
        if ((6.0 * hue) < 1.0) {
            res = f1 + (f2 - f1) * 6.0 * hue;
        } else if ((2.0 * hue) < 1.0) {
            res = f2;
        } else if ((3.0 * hue) < 2.0) {
            res = f1 + (f2 - f1) * ((2.0 / 3.0) - hue) * 6.0;
        } else {
            res = f1;
        }
        return res;
    }
    
    static float3 hslToRgb(float3 hsl) {
        float3 rgb;
        if (hsl.y == 0.0) {
            rgb = float3(hsl.z);
        } else {
            float f2;
            if (hsl.z < 0.5) {
                f2 = hsl.z * (1.0 + hsl.y);
            } else {
                f2 = (hsl.z + hsl.y) - (hsl.y * hsl.z);
            }
            float f1 = 2.0 * hsl.z - f2;
            rgb.r = hueToRgb(f1, f2, hsl.x + (1.0 / 3.0));
            rgb.g = hueToRgb(f1, f2, hsl.x);
            rgb.b = hueToRgb(f1, f2, hsl.x - (1.0 / 3.0));
        }
        return rgb;
    }
    
    static float3 rgbToYuv(float3 inP) {
        float3 outP;
        outP.r = getLuma(inP);
        outP.g = (1.0 / 1.772) * (inP.b - outP.r);
        outP.b = (1.0 / 1.402) * (inP.r - outP.r);
        return outP;
    }
    
    static float3 yuvToRgb(float3 inP) {
        float y = inP.r;
        float u = inP.g;
        float v = inP.b;
        float3 outP;
        outP.r = 1.402 * v + y;
        outP.g = (y - (0.299 * 1.402 / 0.587) * v - (0.114 * 1.772 / 0.587) * u);
        outP.b = 1.772 * u + y;
        return outP;
    }
    
    static float easeInOutSigmoid(float value, float strength) {
        float t = 1.0 / (1.0 - strength);
        if (value > 0.5) {
            return 1.0 - pow(2.0 - 2.0 * value, t) * 0.5;
        } else {
            return pow(2.0 * value, t) * 0.5;
        }
    }
    
    // PGCurvesTool.
    static float3 applyLuminanceCurve(float3 pixel, constant float *curves) {
        int index = int(clamp(pixel.z / (1.0 / 200.0), 0.0, 199.0));
        float value = curves[index];
        float grayscale = (smoothstep(0.0, 0.1, pixel.z) * (1.0 - smoothstep(0.8, 1.0, pixel.z)));
        float saturation = mix(0.0, pixel.y, grayscale);
        pixel.y = saturation;
        pixel.z = value;
        return pixel;
    }
    
    static float3 applyRGBCurve(float3 pixel, constant float *curves) {
        int index = int(clamp(pixel.r / (1.0 / 200.0), 0.0, 199.0));
        float value = curves[200 + index];
        pixel.r = value;
        index = int(clamp(pixel.g / (1.0 / 200.0), 0.0, 199.0));
        value = curves[400 + index];
        pixel.g = clamp(value, 0.0, 1.0);
        index = int(clamp(pixel.b / (1.0 / 200.0), 0.0, 199.0));
        value = curves[600 + index];
        pixel.b = clamp(value, 0.0, 1.0);
        return pixel;
    }
    
    // PGFadeTool.
    static float3 fadeAdjust(float3 color, float fadeVal) {
        float3 co1 = float3(-0.9772);
        float3 co2 = float3(1.708);
        float3 co3 = float3(-0.1603);
        float3 co4 = float3(0.2878);
        float3 comp1 = co1 * (color * color * color);
        float3 comp2 = co2 * (color * color);
        float3 comp3 = co3 * color;
        float3 comp4 = co4;
        float3 finalComponent = comp1 + comp2 + comp3 + comp4;
        float3 difference = finalComponent - color;
        float3 scalingValue = float3(0.9);
        float3 faded = color + (difference * scalingValue);
        return (color * (1.0 - fadeVal)) + (faded * fadeVal);
    }
    
    // PGTintTool.
    static float3 tintRaiseShadowsCurve(float3 color) {
        float3 co1 = float3(-0.003671);
        float3 co2 = float3(0.3842);
        float3 co3 = float3(0.3764);
        float3 co4 = float3(0.2515);
        float3 comp1 = co1 * (color * color * color);
        float3 comp2 = co2 * (color * color);
        float3 comp3 = co3 * color;
        float3 comp4 = co4;
        return comp1 + comp2 + comp3 + comp4;
    }
    
    static float3 tintShadows(float3 texel, float3 tintColor, float tintAmount) {
        float3 raisedShadows = tintRaiseShadowsCurve(texel);
        float3 tintedShadows = mix(texel, raisedShadows, tintColor);
        float3 tintedShadowsWithAmount = mix(texel, tintedShadows, float3(tintAmount));
        return clamp(tintedShadowsWithAmount, float3(0.0), float3(1.0));
    }
    
    static float3 tintHighlights(float3 texel, float3 tintColor, float tintAmount) {
        float3 loweredHighlights = float3(1.0) - tintRaiseShadowsCurve(float3(1.0) - texel);
        float3 tintedHighlights = mix(texel, loweredHighlights, (float3(1.0) - tintColor));
        float3 tintedHighlightsWithAmount = mix(texel, tintedHighlights, float3(tintAmount));
        return clamp(tintedHighlightsWithAmount, float3(0.0), float3(1.0));
    }
    
    // PGGrainTool.
    static float4 rnm(float2 tc) {
        float noise = sin(dot(tc, float2(12.9898, 78.233))) * 43758.5453;
        float noiseR = fract(noise) * 2.0 - 1.0;
        float noiseG = fract(noise * 1.2154) * 2.0 - 1.0;
        float noiseB = fract(noise * 1.3453) * 2.0 - 1.0;
        float noiseA = fract(noise * 1.3647) * 2.0 - 1.0;
        return float4(noiseR, noiseG, noiseB, noiseA);
    }
    
    static float fadeCurve(float t) {
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
    }
    
    static float pnoise3D(float3 p) {
        float3 cell = permTexUnit * floor(p) + permTexUnitHalf;
        float3 pf = fract(p);
    
        float perm00 = rnm(cell.xy).a;
        float3 grad000 = rnm(float2(perm00, cell.z)).rgb * 4.0 - 1.0;
        float n000 = dot(grad000, pf);
        float3 grad001 = rnm(float2(perm00, cell.z + permTexUnit)).rgb * 4.0 - 1.0;
        float n001 = dot(grad001, pf - float3(0.0, 0.0, 1.0));
    
        float perm01 = rnm(cell.xy + float2(0.0, permTexUnit)).a;
        float3 grad010 = rnm(float2(perm01, cell.z)).rgb * 4.0 - 1.0;
        float n010 = dot(grad010, pf - float3(0.0, 1.0, 0.0));
        float3 grad011 = rnm(float2(perm01, cell.z + permTexUnit)).rgb * 4.0 - 1.0;
        float n011 = dot(grad011, pf - float3(0.0, 1.0, 1.0));
    
        float perm10 = rnm(cell.xy + float2(permTexUnit, 0.0)).a;
        float3 grad100 = rnm(float2(perm10, cell.z)).rgb * 4.0 - 1.0;
        float n100 = dot(grad100, pf - float3(1.0, 0.0, 0.0));
        float3 grad101 = rnm(float2(perm10, cell.z + permTexUnit)).rgb * 4.0 - 1.0;
        float n101 = dot(grad101, pf - float3(1.0, 0.0, 1.0));
    
        float perm11 = rnm(cell.xy + float2(permTexUnit, permTexUnit)).a;
        float3 grad110 = rnm(float2(perm11, cell.z)).rgb * 4.0 - 1.0;
        float n110 = dot(grad110, pf - float3(1.0, 1.0, 0.0));
        float3 grad111 = rnm(float2(perm11, cell.z + permTexUnit)).rgb * 4.0 - 1.0;
        float n111 = dot(grad111, pf - float3(1.0, 1.0, 1.0));
    
        float4 n_x = mix(float4(n000, n001, n010, n011), float4(n100, n101, n110, n111), float4(fadeCurve(pf.x)));
        float2 n_xy = mix(n_x.xy, n_x.zw, float2(fadeCurve(pf.y)));
        float n_xyz = mix(n_xy.x, n_xy.y, fadeCurve(pf.z));
        return n_xyz;
    }
    
    static float2 coordRot(float2 tc, float angle) {
        float rotX = ((tc.x * 2.0 - 1.0) * cos(angle)) - ((tc.y * 2.0 - 1.0) * sin(angle));
        float rotY = ((tc.y * 2.0 - 1.0) * cos(angle)) + ((tc.x * 2.0 - 1.0) * sin(angle));
        rotX = rotX * 0.5 + 0.5;
        rotY = rotY * 0.5 + 0.5;
        return float2(rotX, rotY);
    }
    
    // PGPhotoToolComposer: the shader tools in their order.
    kernel void photoToolsCompose(
        device const uchar4 *source [[buffer(0)]],
        device uchar4 *destination [[buffer(1)]],
        constant float *curves [[buffer(2)]],
        constant PhotoToolParameters &parameters [[buffer(3)]],
        constant uint2 &size [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= size.x || gid.y >= size.y) {
            return;
        }
        float2 texCoord = (float2(gid) + 0.5) / float2(size);
        float3 result = loadPixel(source, size, int(gid.x), int(gid.y)).rgb;
    
        // Curves.
        if (parameters.skipTone < toolEpsilon) {
            result = applyRGBCurve(hslToRgb(applyLuminanceCurve(rgbToHsl(result), curves)), curves);
        }
    
        // Highlights and Shadows.
        {
            float highlights = parameters.highlights;
            float shadows = parameters.shadows;
            float hsLuminance = dot(result, float3(0.3, 0.3, 0.3));
            float shadow = clamp(
                (pow(hsLuminance, 1.0 / shadows) + (-0.76) * pow(hsLuminance, 2.0 / shadows)) - hsLuminance,
                0.0,
                1.0);
            float highlightPower = 2.0 - highlights;
            float highlight = clamp(
                (1.0 - (pow(1.0 - hsLuminance, 1.0 / highlightPower)
                    + (-0.8) * pow(1.0 - hsLuminance, 2.0 / highlightPower))) - hsLuminance,
                -1.0,
                0.0);
            float3 hsresult = hsLuminance > 0.0
                ? (hsLuminance + shadow + highlight) * (result / hsLuminance)
                : result;
            float contrastedLuminance = ((hsLuminance - 0.5) * 1.5) + 0.5;
            float whiteInterp = contrastedLuminance * contrastedLuminance * contrastedLuminance;
            float whiteTarget = clamp(highlights, 1.0, 2.0) - 1.0;
            hsresult = mix(hsresult, float3(1.0), float3(whiteInterp * whiteTarget));
            float invContrastedLuminance = 1.0 - contrastedLuminance;
            float blackInterp = invContrastedLuminance * invContrastedLuminance * invContrastedLuminance;
            float blackTarget = 1.0 - clamp(shadows, 0.0, 1.0);
            hsresult = mix(hsresult, float3(0.0), float3(blackInterp * blackTarget));
            result = hsresult;
        }
    
        // Contrast.
        result = clamp(((result - float3(0.5)) * parameters.contrast + float3(0.5)), float3(0.0), float3(1.0));
    
        // Fade.
        if (abs(parameters.fadeAmount) > toolEpsilon) {
            result = fadeAdjust(result, parameters.fadeAmount);
        }
    
        // Saturation.
        {
            float satLuminance = dot(result, float3(0.2126, 0.7152, 0.0722));
            float3 greyScaleColor = float3(satLuminance);
            result = clamp(mix(greyScaleColor, result, float3(parameters.saturation)), float3(0.0), float3(1.0));
        }
    
        // Tint.
        if (abs(parameters.shadowsTintIntensity) > toolEpsilon) {
            float3 color = float3(
                parameters.shadowsTintRed, parameters.shadowsTintGreen, parameters.shadowsTintBlue);
            result = tintShadows(result, color, parameters.shadowsTintIntensity * 2.0);
        }
        if (abs(parameters.highlightsTintIntensity) > toolEpsilon) {
            float3 color = float3(
                parameters.highlightsTintRed, parameters.highlightsTintGreen, parameters.highlightsTintBlue);
            result = tintHighlights(result, color, parameters.highlightsTintIntensity * 2.0);
        }
    
        // Exposure.
        if (abs(parameters.exposure) > toolEpsilon) {
            float mag = parameters.exposure * 1.045;
            float exppower = 1.0 + abs(mag);
            if (mag < 0.0) {
                exppower = 1.0 / exppower;
            }
            result = 1.0 - pow(max(1.0 - result, float3(0.0)), float3(exppower));
        }
    
        // Warmth.
        if (abs(parameters.warmth) > toolEpsilon) {
            float3 yuvVec;
            if (parameters.warmth > 0.0) {
                yuvVec = float3(0.1765, -0.1255, 0.0902);
            } else {
                yuvVec = -float3(0.0588, 0.1569, -0.1255);
            }
            float3 yuvColor = rgbToYuv(result);
            float luma = yuvColor.r;
            float curveScale = sin(luma * 3.14159);
            yuvColor += 0.375 * parameters.warmth * curveScale * yuvVec;
            result = yuvToRgb(yuvColor);
        }
    
        // Grain.
        if (abs(parameters.grain) > toolEpsilon) {
            float3 rotOffset = float3(1.425, 3.892, 5.835);
            float2 rotCoordsR = coordRot(texCoord, rotOffset.x);
            float2 grainScale = float2(parameters.width / grainsize, parameters.height / grainsize);
            float3 noise = float3(pnoise3D(float3(rotCoordsR * grainScale, 0.0)));
            float3 lumcoeff = float3(0.299, 0.587, 0.114);
            float luminance = dot(result, lumcoeff);
            // smoothstep(0.2, 0.0, luminance) as GLSL computes it with reversed edges.
            float ramp = clamp((luminance - 0.2) / (0.0 - 0.2), 0.0, 1.0);
            float lum = ramp * ramp * (3.0 - 2.0 * ramp);
            lum += luminance;
            float lumSquared = lum * lum;
            noise = mix(noise, float3(0.0), float3(lumSquared * lumSquared));
            result = result + noise * parameters.grain;
        }
    
        // Vignette.
        if (abs(parameters.vignette) > toolEpsilon) {
            const float midpoint = 0.7;
            const float fuzziness = 0.62;
            float radDist = length(texCoord - 0.5) / sqrt(0.5);
            float mag = easeInOutSigmoid(radDist * midpoint, fuzziness) * parameters.vignette * 0.645;
            result = mix(pow(max(result, float3(0.0)), float3(1.0 / (1.0 - mag))), float3(0.0), float3(mag * mag));
        }
    
        destination[gid.y * size.x + gid.x] = storePixel(result);
    }
    """

    private let lock = NSLock()
    private var pipelines: Pipelines?
    private var didFail = false

    /// PGPhotoGaussianBlurFilter's `setInputSize`: a sigma of 0.8% of the picture's longer side, sampled out to where
    /// a tap would weigh under 1/256 and rounded up to an even count, with the normalized weights from the center
    /// out. `nil` when the picture is too large for the filter's formula.
    private static func gaussianWeights(width: Int, height: Int) -> [Float]? {
        gaussianWeights(sigma: (Double(max(width, height)) * 0.008).rounded(.up))
    }

    /// GPUImageGaussianBlurFilter's weights for a whole `sigma`, sampled out to where a tap would weigh under 1/256,
    /// or to `fixedRadius`.
    private static func gaussianWeights(sigma: Double, fixedRadius: Int? = nil) -> [Float]? {
        guard sigma >= 1 else { return [1] }
        let variance = sigma * sigma
        let normalization = (2 * Double.pi * variance).squareRoot()
        var sampleRadius: Int
        if let fixedRadius {
            sampleRadius = fixedRadius
        } else {
            let edge = -2 * variance * log(normalization / 256)
            guard edge > 0 else { return nil }
            sampleRadius = Int(edge.squareRoot().rounded(.down))
            sampleRadius += sampleRadius % 2
        }
        guard sampleRadius >= 1 else { return [1] }
        let weights = (0...sampleRadius).map { offset in
            exp(-Double(offset * offset) / (2 * variance)) / normalization
        }
        let sum = weights.dropFirst().reduce(weights[0]) { $0 + 2 * $1 }
        return weights.map { Float($0 / sum) }
    }

    private static func makeBuffer(_ values: [Float], on device: MTLDevice) -> MTLBuffer? {
        values.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
        }
    }

    /// Draws `image` and renders the tools over it. Call off the main thread.
    func render(_ image: CGImage, tools: PhotoToolValues, grainSize: CGSize) -> CGImage? {
        guard let source = PhotoToolsSource(image: image) else { return nil }
        return render(source, tools: tools, grainSize: grainSize)
    }

    /// The tools over `source`; `grainSize` is PGPhotoToolComposer's `imageSize`, the crop in the full photo's
    /// pixels, which sets the grain's scale. `nil` when Metal can't render. Call off the main thread.
    func render(_ source: PhotoToolsSource, tools: PhotoToolValues, grainSize: CGSize) -> CGImage? {
        guard let pipelines = preparedPipelines(),
              let input = source.buffer(on: pipelines.device),
              let commandBuffer = pipelines.queue.makeCommandBuffer()
        else { return nil }
        let length = source.width * source.height * 4
        var parameters = Parameters(tools: tools, grainSize: grainSize)
        var size = SIMD2<UInt32>(UInt32(source.width), UInt32(source.height))
        var current = input
        // PGPhotoEditor's `updateProcessChain`: the passes the tools don't skip, by their order.
        if tools[.skin] != 0,
           let output = encodeSkin(
               from: current,
               width: source.width,
               length: length,
               pipelines: pipelines,
               in: commandBuffer,
               parameters: &parameters,
               size: &size,
           )
        {
            current = output
        }
        if tools[.enhance] != 0, let table = source.enhanceTable(on: pipelines.device),
           let output = pipelines.device.makeBuffer(length: length, options: .storageModePrivate)
        {
            encode(
                pipelines.enhance,
                in: commandBuffer,
                buffers: [current, output, table],
                parameters: &parameters,
                size: &size,
            )
            current = output
        }
        if tools[.sharpen] != 0,
           let output = pipelines.device.makeBuffer(length: length, options: .storageModePrivate)
        {
            encode(
                pipelines.sharpen,
                in: commandBuffer,
                buffers: [current, output],
                parameters: &parameters,
                size: &size,
            )
            current = output
        }
        if !tools.blur.isDefault,
           let weights = Self.gaussianWeights(width: source.width, height: source.height),
           let vertical = pipelines.device.makeBuffer(length: length, options: .storageModePrivate),
           let output = pipelines.device.makeBuffer(length: length, options: .storageModePrivate)
        {
            if let weightsBuffer = Self.makeBuffer(weights, on: pipelines.device) {
                let blur = BlurParameters(
                    blur: tools.blur,
                    width: source.width,
                    height: source.height,
                    sampleRadius: weights.count - 1,
                )
                encode(
                    pipelines.blurVertical,
                    in: commandBuffer,
                    buffers: [(0, current), (1, vertical), (2, weightsBuffer)],
                    blur: blur,
                    parameters: &parameters,
                    size: &size,
                )
                encode(
                    pipelines.blurFocus,
                    in: commandBuffer,
                    buffers: [(0, current), (1, output), (2, weightsBuffer), (6, vertical)],
                    blur: blur,
                    parameters: &parameters,
                    size: &size,
                )
                current = output
            }
        }
        guard let result = pipelines.device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
        var curves = [PhotoCurvesChannel.luminance, .red, .green, .blue]
            .flatMap { tools.curves[$0].interpolated().data }
        encode(
            pipelines.compose,
            in: commandBuffer,
            buffers: [current, result],
            curves: &curves,
            parameters: &parameters,
            size: &size,
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            log("Photo tools render failed: \(String(describing: commandBuffer.error))")
            return nil
        }
        return makeImage(result, width: source.width, height: source.height)
    }

    /// PGPhotoSkinPass's YUGPUImageHighPassSkinSmoothingFilter: a mask from the high pass of the green and blue
    /// channels' overlay, with a blur of 0.6% of the picture's width; the skin tone curve dissolved in by the amount
    /// where the mask is dark; then GPUImageSharpenFilter at 0.4 of the amount.
    private func encodeSkin(
        from input: MTLBuffer,
        width: Int,
        length: Int,
        pipelines: Pipelines,
        in commandBuffer: MTLCommandBuffer,
        parameters: inout Parameters,
        size: inout SIMD2<UInt32>,
    ) -> MTLBuffer? {
        let device = pipelines.device
        // `updateHighPassRadius`: the blur keeps whole sigmas and starts as its four-sample one of 2.
        let sigma = (Double(width) * 0.006).rounded()
        guard let weights = Self.gaussianWeights(sigma: sigma, fixedRadius: sigma == 2 ? 4 : nil),
              let weightsBuffer = Self.makeBuffer(weights, on: device),
              let overlay = device.makeBuffer(length: length, options: .storageModePrivate),
              let vertical = device.makeBuffer(length: length, options: .storageModePrivate),
              let mask = device.makeBuffer(length: length, options: .storageModePrivate),
              let composed = device.makeBuffer(length: length, options: .storageModePrivate),
              let sharpened = device.makeBuffer(length: length, options: .storageModePrivate)
        else { return nil }
        let blur = BlurParameters(sampleRadius: weights.count - 1)
        encode(
            pipelines.skinOverlay,
            in: commandBuffer,
            buffers: [(0, input), (1, overlay)],
            parameters: &parameters,
            size: &size,
        )
        encode(
            pipelines.blurVertical,
            in: commandBuffer,
            buffers: [(0, overlay), (1, vertical), (2, weightsBuffer)],
            blur: blur,
            parameters: &parameters,
            size: &size,
        )
        encode(
            pipelines.skinMask,
            in: commandBuffer,
            buffers: [(0, overlay), (1, mask), (2, weightsBuffer), (6, vertical)],
            blur: blur,
            parameters: &parameters,
            size: &size,
        )
        encode(
            pipelines.skinCompose,
            in: commandBuffer,
            buffers: [(0, input), (1, composed), (6, mask)],
            table: Self.skinToneCurve,
            parameters: &parameters,
            size: &size,
        )
        var sharpen = parameters
        sharpen.sharpness = 0.4 * parameters.skin
        encode(
            pipelines.sharpen,
            in: commandBuffer,
            buffers: [(0, composed), (1, sharpened)],
            parameters: &sharpen,
            size: &size,
        )
        return sharpened
    }

    private func preparedPipelines() -> Pipelines? {
        lock.withLock {
            if let pipelines { return pipelines }
            guard !didFail else { return nil }
            do {
                guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
                    throw CocoaError(.featureUnsupported)
                }
                let library = try device.makeLibrary(source: Self.source, options: nil)
                func pipeline(_ name: String) throws -> MTLComputePipelineState {
                    guard let function = library.makeFunction(name: name) else { throw CocoaError(.featureUnsupported) }
                    return try device.makeComputePipelineState(function: function)
                }
                let prepared = try Pipelines(
                    device: device,
                    queue: queue,
                    skinOverlay: pipeline("photoToolsSkinOverlay"),
                    skinMask: pipeline("photoToolsSkinMask"),
                    skinCompose: pipeline("photoToolsSkinCompose"),
                    enhance: pipeline("photoToolsEnhance"),
                    sharpen: pipeline("photoToolsSharpen"),
                    blurVertical: pipeline("photoToolsBlurVertical"),
                    blurFocus: pipeline("photoToolsBlurFocus"),
                    compose: pipeline("photoToolsCompose"),
                )
                pipelines = prepared
                return prepared
            } catch {
                didFail = true
                log("Photo tools are unavailable: \(error)")
                return nil
            }
        }
    }

    private func encode(
        _ pipeline: MTLComputePipelineState,
        in commandBuffer: MTLCommandBuffer,
        buffers: [MTLBuffer],
        curves: inout [Float],
        parameters: inout Parameters,
        size: inout SIMD2<UInt32>,
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in buffers.enumerated() {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }
        curves.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                encoder.setBytes(baseAddress, length: bytes.count, index: 2)
            }
        }
        dispatch(pipeline, encoder: encoder, parameters: &parameters, size: &size)
    }

    private func encode(
        _ pipeline: MTLComputePipelineState,
        in commandBuffer: MTLCommandBuffer,
        buffers: [MTLBuffer],
        parameters: inout Parameters,
        size: inout SIMD2<UInt32>,
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in buffers.enumerated() {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }
        dispatch(pipeline, encoder: encoder, parameters: &parameters, size: &size)
    }

    /// A pass with its buffers at the shader's indices, a table at index 2 and the blur's uniforms when it takes
    /// them.
    private func encode(
        _ pipeline: MTLComputePipelineState,
        in commandBuffer: MTLCommandBuffer,
        buffers: [(index: Int, buffer: MTLBuffer)],
        table: [Float]? = nil,
        blur: BlurParameters? = nil,
        parameters: inout Parameters,
        size: inout SIMD2<UInt32>,
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        for item in buffers {
            encoder.setBuffer(item.buffer, offset: 0, index: item.index)
        }
        table?.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                encoder.setBytes(baseAddress, length: bytes.count, index: 2)
            }
        }
        if var blur {
            encoder.setBytes(&blur, length: MemoryLayout<BlurParameters>.stride, index: 5)
        }
        dispatch(pipeline, encoder: encoder, parameters: &parameters, size: &size)
    }

    private func dispatch(
        _ pipeline: MTLComputePipelineState,
        encoder: MTLComputeCommandEncoder,
        parameters: inout Parameters,
        size: inout SIMD2<UInt32>,
    ) {
        encoder.setBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 3)
        encoder.setBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 4)
        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        let threadsPerGroup = MTLSize(width: width, height: height, depth: 1)
        let groups = MTLSize(
            width: (Int(size.x) + width - 1) / width,
            height: (Int(size.y) + height - 1) / height,
            depth: 1,
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }

    private func makeImage(_ buffer: MTLBuffer, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        let data = Data(bytes: buffer.contents(), count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent,
        )
    }
}
