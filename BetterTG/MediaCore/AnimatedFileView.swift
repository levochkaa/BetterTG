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
