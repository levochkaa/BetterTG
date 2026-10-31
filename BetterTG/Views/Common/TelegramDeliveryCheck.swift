// TelegramDeliveryCheck.swift

import UIKit

/// Telegram's PresentationResourcesChatList.generateStatusCheckImage geometry.
enum TelegramDeliveryCheck {
    private static let bubbleCache = NSCache<NSString, UIImage>()

    /// A bubble's status: `generateCheckImage`'s full check and, 6 pt on, its partial one for a read message. `width`
    /// is Telegram's check size, the date's point size. Both states take the same room, so the time holds still.
    static func bubbleImage(isRead: Bool, width: CGFloat) -> UIImage {
        let key = "\(isRead)-\(width)" as NSString
        if let cached = bubbleCache.object(forKey: key) { return cached }
        let scale = width / 11
        let offset = floor(width * 6 / 11)
        let size = CGSize(width: width + offset, height: floor(width * 9 / 11))
        let image = UIGraphicsImageRenderer(size: size)
            .image { renderer in
                let context = renderer.cgContext
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: 1, y: 1)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(0.99)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.move(to: CGPoint(x: 0, y: 4))
                context.addLine(to: CGPoint(x: 2.95157047, y: 6.95157047))
                context.addCurve(
                    to: CGPoint(x: 3.04490857, y: 6.95157047),
                    control1: CGPoint(x: 2.97734507, y: 6.97734507),
                    control2: CGPoint(x: 3.01913396, y: 6.97734507),
                )
                context.addLine(to: CGPoint(x: 9.5, y: 0))
                context.strokePath()
                if isRead {
                    context.translateBy(x: offset / scale, y: 0)
                    context.move(to: CGPoint(x: 0.5, y: 7))
                    context.addLine(to: CGPoint(x: 7, y: 0))
                    context.strokePath()
                }
            }
            .withRenderingMode(.alwaysTemplate)
        bubbleCache.setObject(image, forKey: key)
        return image
    }

    /// A bubble's pending clock in the checks' room: `generateClockFrameImage` and `generateClockMinImage`, which
    /// Telegram spins and this holds still.
    static func bubbleClockImage(width: CGFloat) -> UIImage {
        let key = "clock-\(width)" as NSString
        if let cached = bubbleCache.object(forKey: key) { return cached }
        let scale = width / 11
        let room = width + floor(width * 6 / 11)
        let image = UIGraphicsImageRenderer(size: CGSize(width: room, height: width))
            .image { renderer in
                let context = renderer.cgContext
                context.translateBy(x: floor(2 * scale), y: 0)
                context.scaleBy(x: scale, y: scale)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setFillColor(UIColor.white.cgColor)
                context.setLineWidth(1)
                context.strokeEllipse(in: CGRect(x: 0.5, y: 0.5, width: 10, height: 10))
                context.fill(CGRect(x: 5, y: 3, width: 1, height: 2.5))
                context.fill(CGRect(x: 5, y: 5, width: 4.5, height: 1))
            }
            .withRenderingMode(.alwaysTemplate)
        bubbleCache.setObject(image, forKey: key)
        return image
    }

    /// A chat list row's status, as `ChatListStatusChecksNode` ends up drawing it in its 24 pt square, cut to the
    /// checks' room: a delivered check on the right, and for a read message another before it, which leaves the right
    /// one only its long stroke.
    static func listImage(isRead: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        let pixel = 1 / format.scale
        return UIGraphicsImageRenderer(size: CGSize(width: 17, height: 10), format: format)
            .image { renderer in
                let context = renderer.cgContext
                context.translateBy(x: -4, y: -7.5)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(1 + pixel)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setMiterLimit(10)
                let short = CGPoint(x: 3.5, y: 3.5)
                let long = CGPoint(x: 7.5 - pixel, y: -8)
                func corner(from start: CGPoint) -> CGPoint {
                    CGPoint(x: start.x + short.x, y: start.y + short.y)
                }
                func end(from start: CGPoint) -> CGPoint {
                    CGPoint(x: start.x + short.x + long.x, y: start.y + short.y + long.y)
                }
                let right = CGPoint(x: 9, y: 13)
                context.move(to: end(from: right))
                context.addLine(to: corner(from: right))
                if !isRead { context.addLine(to: right) }
                context.strokePath()
                if isRead {
                    let left = CGPoint(x: 5, y: 13)
                    context.move(to: end(from: left))
                    context.addLine(to: corner(from: left))
                    context.addLine(to: left)
                    context.strokePath()
                }
            }
            .withRenderingMode(.alwaysTemplate)
    }
}
