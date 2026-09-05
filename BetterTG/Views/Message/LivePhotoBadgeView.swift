// LivePhotoBadgeView.swift

import UIKit

final class LivePhotoBadgeView: UIImageView {
    init() {
        super.init(image: UIImage(systemName: "livephoto"))
        tintColor = .white
        contentMode = .scaleAspectFit
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = 2
        layer.shadowOffset = .zero
        isUserInteractionEnabled = false
        isHidden = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
