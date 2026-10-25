// AnimatedFileView.swift

import TDLibKit
import UIKit

protocol AnimatedFileView where Self: UIView {
    var onFirstFrameReady: (() -> Void)? { get set }
    /// The Power Saving process the animation follows; nil plays as usual.
    var energySaving: EnergySavingRole? { get set }

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
