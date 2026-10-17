// MediaGalleryImageTransitionView.swift

import AVFoundation
import UIKit

// MARK: - MediaGalleryImageTransitionView

/// Animate the clipping window and the full image independently. Scaling a
/// rasterized thumbnail can never reveal the pixels outside its initial crop.
final class MediaGalleryImageTransitionView: UIView {
    let image: UIImage

    private let imageView: UIImageView
    private var liveVideoSurface: LocalVideoSurfaceView?

    /// `liveVideo` attaches the playing video over the frame, as Telegram flies the live video node: the frame stays
    /// underneath until the layer has a picture.
    init(image: UIImage, imageFrame: CGRect, liveVideo: ((AVPlayerLayer) -> Void)? = nil) {
        self.image = image
        self.imageView = UIImageView(image: image)
        super.init(frame: .zero)
        clipsToBounds = true
        imageView.contentMode = .scaleToFill
        imageView.frame = imageFrame
        addSubview(imageView)
        if let liveVideo {
            let surface = LocalVideoSurfaceView(frame: imageView.bounds)
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            surface.backgroundColor = .clear
            surface.isUserInteractionEnabled = false
            // The frame already has the video's aspect, so the layer fills it like the image does.
            surface.playerLayer.videoGravity = .resize
            imageView.addSubview(surface)
            liveVideo(surface.playerLayer)
            self.liveVideoSurface = surface
        }
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

// MARK: - MediaGalleryVideoFrameSnapshotView

/// The frame a playing video shows, with a way to attach the same player to the transition's own layer.
final class MediaGalleryVideoFrameSnapshotView: UIImageView {
    var attachLiveVideo: ((AVPlayerLayer) -> Void)?
}
