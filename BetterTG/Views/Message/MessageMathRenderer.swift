// MessageMathRenderer.swift

import SwiftMath
import UIKit

/// Telegram's InstantPageMath uses SwiftMath and the same 1.12 font multiplier.
/// Keep formula parsing and drawing in the native UIKit math renderer.
@MainActor enum MessageMathRenderer {
    struct Rendered {
        let image: UIImage
        let descent: CGFloat
    }

    static func render(_ expression: String, fontSize: CGFloat, inline: Bool, traits: UITraitCollection) -> Rendered? {
        guard expression.utf8.count <= 16384 else { return nil }
        let label = MTMathUILabel()
        label.fontSize = fontSize * 1.12
        label.textColor = UIColor.label.resolvedColor(with: traits)
        label.labelMode = inline ? .text : .display
        label.latex = expression
        guard label.error == nil else { return nil }
        let size = label.intrinsicContentSize
        guard size.width > 0, size.height > 0, size.width <= 4096, size.height <= 2048 else { return nil }
        label.frame = CGRect(origin: .zero, size: size)
        label.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { context in
            // SwiftMath lays out glyphs in a bottom-left coordinate system.
            // Drawing the list directly avoids CALayer.render applying the
            // label's flipped geometry a second time to the exported bitmap.
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            label.displayList?.draw(context.cgContext)
        }
        return Rendered(image: image, descent: label.displayList?.descent ?? 0)
    }

    static func block(_ expression: String, width: CGFloat, traits: UITraitCollection) -> UIView? {
        guard let rendered = render(expression, fontSize: 17, inline: false, traits: traits) else { return nil }
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = true
        let image = UIImageView(image: rendered.image)
        image.frame = CGRect(
            x: max(0, (width - image.bounds.width) / 2),
            y: 2,
            width: image.bounds.width,
            height: image.bounds.height,
        )
        scroll.addSubview(image)
        scroll.contentSize = CGSize(width: max(width, image.bounds.width), height: image.bounds.height + 4)
        scroll.heightAnchor.constraint(equalToConstant: image.bounds.height + 4).isActive = true
        scroll.isAccessibilityElement = true
        scroll.accessibilityLabel = expression
        return scroll
    }
}
