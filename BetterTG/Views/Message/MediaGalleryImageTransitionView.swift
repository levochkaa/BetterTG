// MediaGalleryImageTransitionView.swift

import AVFoundation
import UIKit

/// Animate the clipping window and the full image independently. Scaling a
/// rasterized thumbnail can never reveal the pixels outside its initial crop.
final class MediaGalleryImageTransitionView: UIView {
    let image: UIImage

    private let imageView: UIImageView

    init(image: UIImage, imageFrame: CGRect) {
        self.image = image
        self.imageView = UIImageView(image: image)
        super.init(frame: .zero)
        clipsToBounds = true
        imageView.contentMode = .scaleToFill
        imageView.frame = imageFrame
        addSubview(imageView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func imageFrame(size: CGSize, bounds: CGRect, contentMode: UIView.ContentMode) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        if contentMode == .scaleToFill { return bounds }
        if contentMode == .scaleAspectFit { return AVMakeRect(aspectRatio: size, insideRect: bounds) }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - scaled.width / 2,
            y: bounds.midY - scaled.height / 2,
            width: scaled.width,
            height: scaled.height,
        )
    }

    func setImageFrame(_ frame: CGRect) { imageView.frame = frame }
}
