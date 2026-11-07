// GiftPatternLayer.swift

import TDLibKit
import UIKit

// MARK: - GiftPatternLayer

/// PeerInfoCoverComponent's avatar pattern for an upgraded gift: the gift's symbol in five rings of six around a
/// centre, alternate rings turned half a step, each copy scaled by LokiRng(123, 0, 0) between 0.7 and 1, drawn in the
/// backdrop's pattern colour fading from 0.6 at the centre to nothing at the edge of a 380 pt wide area.
final class GiftPatternLayer: CALayer {
    private let contentLayer = CAGradientLayer()
    private let maskContainer = CALayer()
    private var itemLayers = [CALayer]()
    private var image: CGImage?

    override init() {
        super.init()
        contentLayer.type = .radial
        contentLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        contentLayer.endPoint = CGPoint(x: 1, y: 1)
        contentLayer.mask = maskContainer
        addSublayer(contentLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setColor(_ color: UIColor) {
        contentLayer.colors = [color.withAlphaComponent(0.6).cgColor, color.withAlphaComponent(0).cgColor]
    }

    func setImage(_ image: CGImage?) {
        self.image = image
        for item in itemLayers {
            item.contents = image
        }
    }

    /// Lays the rings out around `center` in the layer's bounds; `defaultHeight` is the cover's height the pattern
    /// area takes, and narrow covers (gift tiles) shrink the rings as PeerInfoCoverComponent does.
    func layout(center: CGPoint, defaultHeight: CGFloat, avatarSide: CGFloat = 100) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let width = bounds.width
        let area = CGRect(
            x: center.x - 190,
            y: center.y - floor(defaultHeight / 2),
            width: 380,
            height: floor(defaultHeight),
        )
        contentLayer.frame = area
        maskContainer.frame = CGRect(origin: .zero, size: area.size)

        var baseDistance = avatarSide / 2 + 22
        var baseRowDistance: CGFloat = 28
        var baseItemSize: CGFloat = 26
        if width <= 60 {
            baseDistance *= 0.35
            baseRowDistance *= 0.3
            baseItemSize *= 0.4
        } else if width < 150 {
            baseDistance *= 0.6
            baseRowDistance *= 0.6
            baseItemSize *= 0.83
        }
        var random = LokiRandom(seed0: 123, seed1: 0, seed2: 0)
        let count = 7
        let angleSpan = CGFloat.pi * 2 / CGFloat(count - 1)
        var index = 0
        for row in 0..<5 {
            for item in 0..<count - 1 {
                let distance = baseDistance + CGFloat(row) * baseRowDistance
                var angle = -CGFloat.pi * 0.5 + CGFloat(item) * angleSpan
                if row % 2 != 0 { angle += angleSpan * 0.5 }
                let position = CGPoint(
                    x: area.width * 0.5 + cos(angle) * distance,
                    y: area.height * 0.5 + sin(angle) * distance,
                )
                let scale = 0.7 + CGFloat(random.next()) * (1 - 0.7)
                let side = floor(baseItemSize * scale)
                let layer: CALayer
                if itemLayers.count > index {
                    layer = itemLayers[index]
                } else {
                    layer = CALayer()
                    layer.contents = image
                    layer.contentsGravity = .resizeAspect
                    // layerTintColor black at 0.8: the mask keeps 0.8 of the symbol's alpha.
                    layer.opacity = 0.8
                    maskContainer.addSublayer(layer)
                    itemLayers.append(layer)
                }
                layer.frame = CGRect(x: position.x - side / 2, y: position.y - side / 2, width: side, height: side)
                index += 1
            }
        }
    }
}

// MARK: - GiftSymbolImages

/// The first frame of an upgraded gift's symbol, which the pattern repeats (PeerInfoCoverComponent loads it at 96 pt).
@MainActor enum GiftSymbolImages {
    private static let cache = NSCache<NSString, CGImage>()

    static func image(for sticker: Sticker, client: TDLibClient) async -> CGImage? {
        let key = (sticker.sticker.remote.uniqueId.isEmpty ? "\(sticker.sticker.id)" : sticker.sticker.remote.uniqueId)
            as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard case .stickerFormatTgs = sticker.format else { return nil }
        var file = sticker.sticker
        if !file.local.isDownloadingCompleted {
            guard let downloaded = try? await client.downloadFile(
                fileId: file.id, limit: 0, offset: 0, priority: 1, synchronous: true,
            ) else { return nil }
            file = downloaded
        }
        guard file.local.isDownloadingCompleted,
              let source = await TGSFrameSourceRepository.source(path: file.local.path, side: 192)
        else { return nil }
        let image = await withCheckedContinuation { continuation in
            source.frame(0) { continuation.resume(returning: $0) }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

// MARK: - LokiRandom

/// Telegram's LokiRng: a seeded generator of floats in 0..<1, so the pattern's sizes repeat on every cover.
struct LokiRandom {
    private var seed: Float

    init(seed0: UInt32, seed1: UInt32, seed2: UInt32) {
        let seedA = seed0 &* 1_099_087_573
        let seedB = seed1 &* 1_099_087_573
        let seedC = seed2 &* 1_099_087_573
        var r = Self.round(seedA) ^ seedB
        r = Self.round(r) ^ seedC
        self.seed = Float(Self.round(r)) * 2.3283064365387e-10
    }

    private static func round(_ value: UInt32) -> UInt32 {
        let z1 = taus(value, 13, 19, 12, 429_496_729)
        let z2 = taus(value, 2, 25, 4, 4_294_967_288)
        let z3 = taus(value, 3, 11, 17, 429_496_280)
        let z4 = 1_664_525 &* value &+ 1_013_904_223
        return z1 ^ z2 ^ z3 ^ z4
    }

    private static func taus(_ z: UInt32, _ s1: UInt32, _ s2: UInt32, _ s3: UInt32, _ m: UInt32) -> UInt32 {
        let b = ((z << s1) ^ z) >> s2
        return ((z & m) << s3) ^ b
    }

    mutating func next() -> Float {
        let hashed = UInt32(seed * Float(UInt32(1_099_087_573)))
        let old = seed
        seed = Float(Self.round(hashed)) * 2.3283064365387e-10
        return old
    }
}
