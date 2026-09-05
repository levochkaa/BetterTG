// TelegramDeliveryCheck.swift

import UIKit

/// Telegram's PresentationResourcesChatList.generateStatusCheckImage geometry.
enum TelegramDeliveryCheck {
    static func image(isRead: Bool) -> UIImage {
        let size = CGSize(width: isRead ? 18 : 13, height: 13)
        return UIGraphicsImageRenderer(size: size)
            .image { renderer in
                let context = renderer.cgContext
                context.translateBy(x: 1, y: 2)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(1.32)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.move(to: CGPoint(x: 0, y: 4.48))
                context.addLine(to: CGPoint(x: 3.59439858, y: 7.93062264))
                context.addCurve(
                    to: CGPoint(x: 3.73437658, y: 7.92776595),
                    control1: CGPoint(x: 3.63384129, y: 7.96848764),
                    control2: CGPoint(x: 3.69651158, y: 7.96720866),
                )
                context.addLine(to: CGPoint(x: 11.1666667, y: 0))
                context.strokePath()
                if isRead {
                    context.move(to: CGPoint(x: 7.33333333, y: 8))
                    context.addLine(to: CGPoint(x: 14.8333333, y: 0))
                    context.strokePath()
                }
            }
            .withRenderingMode(.alwaysTemplate)
    }
}
