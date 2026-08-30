// AnimatedFileView.swift

import TDLibKitDynamic
import UIKit

protocol AnimatedFileView where Self: UIView {
    var onFirstFrameReady: (() -> Void)? { get set }

    func configure(
        file: File,
        thumbnail: Thumbnail?,
        displaySize: CGSize?,
        onTap: (() -> Void)?,
    )
    func prepareForReuse()
    func setPlaybackVisible(_ isVisible: Bool)
}
