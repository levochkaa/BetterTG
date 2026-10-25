// AnimatedFileView.swift

import TDLibKit
import UIKit

protocol AnimatedFileView where Self: UIView {
    var onFirstFrameReady: (() -> Void)? { get set }
    /// The Power Saving process the animation follows; nil plays as usual.
    var energySaving: EnergySavingRole? { get set }
    /// InlineStickerItemLayer's loopCount: the loops played from the first frame each time the player is shown,
    /// before it rests on the first frame; nil loops on.
    var loopLimit: Int? { get set }

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
