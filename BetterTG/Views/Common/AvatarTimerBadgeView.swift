// AvatarTimerBadgeView.swift

import Accelerate
import UIKit

// MARK: - AvatarTimerBadgeView

/// Telegram's AvatarBadgeView with its timeout icon: a disc at the avatar's corner filled with the avatar's own
/// picture, blurred to a single colour and saturated, carrying the auto-delete period in bold inside a timer ring,
/// solid on the left and dashed on the right.
final class AvatarTimerBadgeView: UIImageView {
    enum Content: Equatable {
        case color(UIColor)
        case image(UIImage)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.color(let lhs), .color(let rhs)): lhs == rhs
            case (.image(let lhs), .image(let rhs)): lhs === rhs
            default: false
            }
        }
    }

    private struct Parameters: Equatable {
        var size: CGSize
        var avatarSize: CGSize
        var text: String
    }

    private var content: Content?
    private var parameters: Parameters?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// shortTimeIntervalString with `useLargeFormat`: the period in its largest whole unit, as "1d", "1w" or "1mo".
    static func text(seconds: Int) -> String {
        let (key, count): (String, Int) =
            switch seconds {
            case ..<60: ("Seconds", seconds)
            case ..<(60 * 60): ("Minutes", seconds / 60)
            case ..<(60 * 60 * 24): ("Hours", seconds / (60 * 60))
            case ..<(60 * 60 * 24 * 7): ("Days", seconds / (60 * 60 * 24))
            case ..<(60 * 60 * 24 * 31): ("Weeks", seconds / (60 * 60 * 24 * 7))
            case ..<(60 * 60 * 24 * 365): ("Months", seconds / (60 * 60 * 24 * 30))
            default: ("Years", seconds / (60 * 60 * 24 * 365))
            }
        let value = max(1, count)
        return L10n.telegramPlural("MessageTimer.LargeShort\(key)", count: value)
    }

    /// AvatarBadgeView's background: the avatar drawn into 16 × 16 pixels with the badge's corner in view, its mean
    /// luminance, then a 15 px box blur, 1.7× saturation and a slight darkening.
    private static func fill(_ content: Content, _ parameters: Parameters) -> (UIImage, Bool)? {
        let side = 16
        let size = CGSize(width: side, height: side)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
        ), let data = context.data else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        switch content {
        case .color(let color):
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        case .image(let image):
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.scaleBy(x: size.width / parameters.size.width, y: size.height / parameters.size.height)
            let offset = 1 - 0.6
            let frame = CGRect(
                x: parameters.size.width - parameters.avatarSize.width + offset * parameters.size.width,
                y: parameters.size.height - parameters.avatarSize.height + offset * parameters.size.height,
                width: parameters.avatarSize.width,
                height: parameters.avatarSize.height,
            )
            UIGraphicsPushContext(context)
            image.draw(in: frame)
            UIGraphicsPopContext()
        }

        let bytesPerRow = context.bytesPerRow
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var sums = (red: 0, green: 0, blue: 0)
        for y in 0..<side {
            for x in 0..<side {
                let pixel = bytes.advanced(by: y * bytesPerRow + x * 4)
                sums.blue += Int(pixel[0])
                sums.green += Int(pixel[1])
                sums.red += Int(pixel[2])
            }
        }
        let norm = 1 / (255 * CGFloat(side * side))
        let luminance = 0.299 * CGFloat(sums.red) * norm + 0.587 * CGFloat(sums.green) * norm
            + 0.114 * CGFloat(sums.blue) * norm
        let isLightImage = luminance > 0.9
        let brightness: CGFloat = isLightImage ? 0.99 : 0.94

        var buffer = vImage_Buffer(
            data: data,
            height: vImagePixelCount(side),
            width: vImagePixelCount(side),
            rowBytes: bytesPerRow,
        )
        vImageBoxConvolve_ARGB8888(
            &buffer,
            &buffer,
            nil,
            0,
            0,
            15,
            15,
            nil,
            vImage_Flags(kvImageTruncateKernel | kvImageDoNotTile),
        )

        let divisor = Int32(0x1000)
        let weights = (red: CGFloat(0.3086), green: CGFloat(0.6094), blue: CGFloat(0.0820))
        let saturation = CGFloat(1.7)
        let saturationMatrix: [CGFloat] = [
            (1 - saturation) * weights.red + saturation, (1 - saturation) * weights.red,
            (1 - saturation) * weights.red, 0,
            (1 - saturation) * weights.green, (1 - saturation) * weights.green + saturation,
            (1 - saturation) * weights.green, 0,
            (1 - saturation) * weights.blue, (1 - saturation) * weights.blue,
            (1 - saturation) * weights.blue + saturation, 0,
            0, 0, 0, 1,
        ]
        let brightnessMatrix: [CGFloat] = [
            brightness, 0, 0, 0,
            0, brightness, 0, 0,
            0, 0, brightness, 0,
            0, 0, 0, 1,
        ]
        var matrix = [Int16](repeating: 0, count: 16)
        for i in 0..<4 {
            for j in 0..<4 {
                var sum = CGFloat.zero
                for k in 0..<4 {
                    sum += saturationMatrix[i + k * 4] * brightnessMatrix[k + j * 4]
                }
                matrix[i + j * 4] = Int16(sum * CGFloat(divisor))
            }
        }
        vImageMatrixMultiply_ARGB8888(&buffer, &buffer, &matrix, divisor, nil, nil, vImage_Flags(kvImageDoNotTile))

        guard let blurred = context.makeImage() else { return nil }
        return (UIImage(cgImage: blurred), isLightImage)
    }

    private static func render(fill: UIImage, isLightImage: Bool, parameters: Parameters) -> UIImage {
        let size = parameters.size
        let format = UIGraphicsImageRendererFormat.preferred()
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            context.clear(bounds)
            let textColor = isLightImage ? UIColor(white: 0.7, alpha: 1) : .white

            context.setBlendMode(.copy)
            context.setFillColor(UIColor.black.cgColor)
            context.fillEllipse(in: bounds)
            fill.draw(in: bounds, blendMode: .sourceIn, alpha: 1)
            context.setBlendMode(.normal)

            var fontSize = floor(size.height * 0.48)
            while true {
                let string = NSAttributedString(string: parameters.text, attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: textColor,
                ])
                let textBounds = string.boundingRect(
                    with: CGSize(width: 100, height: 100),
                    options: .usesLineFragmentOrigin,
                    context: nil,
                )
                if textBounds.width <= size.width - 5 * 2 || fontSize <= 2 {
                    let scale = format.scale
                    string.draw(at: CGPoint(
                        x: textBounds.minX + floor((size.width - textBounds.width) / 2 * scale) / scale,
                        y: textBounds.minY + floor((size.height - textBounds.height) / 2 * scale) / scale,
                    ))
                    break
                }
                fontSize -= 1
            }

            let lineWidth = CGFloat(1.5)
            let radius = size.width * 0.5 - 2 - lineWidth * 0.5
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            context.setLineWidth(lineWidth)
            context.setStrokeColor(textColor.cgColor)
            context.setLineCap(.round)
            context.addArc(
                center: center,
                radius: radius,
                startAngle: .pi * 0.5,
                endAngle: -.pi * 0.5,
                clockwise: false,
            )
            context.strokePath()
            let section = CGFloat.pi / 11
            for index in stride(from: 1, to: 10, by: 2) {
                let start = .pi * 0.5 - CGFloat(index) * section - section * 0.15
                context.addArc(
                    center: center,
                    radius: radius,
                    startAngle: start,
                    endAngle: start - section * 0.75,
                    clockwise: true,
                )
                context.strokePath()
            }
        }
    }

    /// The avatar's picture or, without one, its placeholder's last gradient colour, as AvatarNode feeds its badge.
    func update(content: Content) {
        guard content != self.content else { return }
        self.content = content
        redraw()
    }

    func update(size: CGSize, avatarSize: CGSize, text: String) {
        let parameters = Parameters(size: size, avatarSize: avatarSize, text: text)
        guard parameters != self.parameters else { return }
        self.parameters = parameters
        redraw()
    }

    private func redraw() {
        guard let content, let parameters, let (fill, isLightImage) = Self.fill(content, parameters) else { return }
        image = Self.render(fill: fill, isLightImage: isLightImage, parameters: parameters)
    }
}
