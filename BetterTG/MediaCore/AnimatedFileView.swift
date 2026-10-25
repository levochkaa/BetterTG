// AnimatedFileView.swift

import TDLibKit
import UIKit

// MARK: - TemplatableImageView

/// setLayerContentsMaskMode for an image view: while `templateColor` is set, every image it shows is its alpha
/// painted in that colour. TDImageLoadingView builds on it.
// swiftformat:disable:next preferFinalClasses
class TemplatableImageView: UIImageView {
    override var image: UIImage? {
        get { super.image }
        // Without a template colour the image passes through untouched: avatars and media load through here.
        set { super.image = templateColor == nil ? newValue : newValue?.withRenderingMode(.alwaysTemplate) }
    }

    var templateColor: UIColor? {
        didSet {
            guard templateColor != oldValue else { return }
            tintColor = templateColor
            // A presented sheet dims template images; a repainted emoji keeps its colour as Telegram's does.
            tintAdjustmentMode = templateColor == nil ? .automatic : .normal
            super.image = super.image?.withRenderingMode(templateColor == nil ? .automatic : .alwaysTemplate)
        }
    }
}

// MARK: - AnimationFrameView

/// Shows rendered animation frames straight through its layer's contents, as Telegram's animation nodes do: setting a
/// UIImageView's image resolved every frame again, and tinted a template one on the CPU. A template colour paints the
/// frame's alpha through a mask on the GPU instead.
final class AnimationFrameView: UIView {
    var templateColor: UIColor? {
        didSet {
            guard templateColor != oldValue else { return }
            applyFrame()
        }
    }

    private(set) var frameImage: CGImage?

    private let maskLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.contentsGravity = .resizeAspect
        maskLayer.contentsGravity = .resizeAspect
        // A view's own layer doesn't animate its changes; the mask is told not to. An explicit transaction per frame
        // committed every view's frame separately.
        maskLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyFrame()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        maskLayer.frame = bounds
    }

    func show(_ image: CGImage?) {
        frameImage = image
        if templateColor == nil {
            layer.contents = image
        } else {
            maskLayer.contents = image
        }
    }

    private func applyFrame() {
        if let templateColor {
            layer.contents = nil
            layer.backgroundColor = templateColor.resolvedColor(with: traitCollection).cgColor
            maskLayer.contents = frameImage
            layer.mask = maskLayer
        } else {
            layer.mask = nil
            layer.backgroundColor = nil
            maskLayer.contents = nil
            layer.contents = frameImage
        }
    }
}

// MARK: - AnimatedFileView

protocol AnimatedFileView where Self: UIView {
    var onFirstFrameReady: (() -> Void)? { get set }
    /// The Power Saving process the animation follows; nil plays as usual.
    var energySaving: EnergySavingRole? { get set }
    /// InlineStickerItemLayer's loopCount: the loops played from the first frame each time the player is shown,
    /// before it rests on the first frame; nil loops on.
    var loopLimit: Int? { get set }
    /// InlineStickerItemLayer's dynamicColor for a template emoji (Telegram's isCustomTemplateEmoji, TDLib's
    /// `needs_repainting`): the colour the whole animation takes, keeping its alpha; nil keeps its own colours.
    var templateColor: UIColor? { get set }

    func configure(
        file: File,
        client: TDLibClient,
        thumbnail: Thumbnail?,
        displaySize: CGSize?,
        onTap: (() -> Void)?,
    )
    func prepareForReuse()
    func setPlaybackVisible(_ isVisible: Bool)
}
