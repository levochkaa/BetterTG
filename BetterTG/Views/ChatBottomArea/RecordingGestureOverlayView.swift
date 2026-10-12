// RecordingGestureOverlayView.swift

import UIKit

/// UIKit counterpart of Telegram's media-recording button and slide-to-cancel
/// indicator. The visual follows the touch; the composer owns the gesture.
final class RecordingGestureOverlayView: UIView {
    private let circle = UIView()
    private let halo = UIView()
    private let icon = UIImageView()
    private let lockPill = UIView()
    private let lockIcon = UIImageView()
    private let arrow = UIImageView()
    private let hint = UILabel()
    private var active = false
    private var translation = CGPoint.zero
    private var anchor = CGPoint.zero
    private var animationGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        circle.backgroundColor = .systemBlue
        circle.layer.cornerRadius = 38
        halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        halo.layer.cornerRadius = 47
        icon.tintColor = .white
        icon.contentMode = .center
        lockPill.backgroundColor = .secondarySystemBackground
        lockPill.layer.cornerRadius = 20
        lockPill.layer.shadowColor = UIColor.black.cgColor
        lockPill.layer.shadowOpacity = 0.12
        lockPill.layer.shadowRadius = 8
        lockIcon.tintColor = .secondaryLabel
        lockIcon.contentMode = .center
        arrow.image = UIImage(
            systemName: "chevron.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
        )
        arrow.tintColor = .secondaryLabel
        arrow.contentMode = .center
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = .secondaryLabel
        hint.textAlignment = .center
        hint.adjustsFontSizeToFitWidth = true
        addSubview(hint)
        addSubview(lockPill)
        lockPill.addSubview(lockIcon)
        lockPill.addSubview(arrow)
        addSubview(halo)
        addSubview(circle)
        circle.addSubview(icon)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontal = min(0, max(-130, translation.x))
        let vertical = min(0, max(-80, translation.y))
        // A horizontal cancel and a vertical lock remain distinct, as in Telegram.
        let motion = abs(horizontal) > abs(vertical)
            ? CGPoint(x: horizontal, y: 0)
            : CGPoint(x: 0, y: vertical)
        let center = CGPoint(x: anchor.x + motion.x, y: anchor.y + motion.y)
        circle.bounds = CGRect(x: 0, y: 0, width: 76, height: 76)
        circle.center = center
        halo.bounds = CGRect(x: 0, y: 0, width: 94, height: 94)
        halo.center = center
        icon.frame = circle.bounds
        lockPill.bounds = CGRect(x: 0, y: 0, width: 40, height: 72)
        lockPill.center = CGPoint(x: anchor.x, y: anchor.y - 105)
        lockIcon.frame = CGRect(x: 0, y: 9, width: 40, height: 30)
        arrow.frame = CGRect(x: 0, y: 42 + vertical * 0.15, width: 40, height: 20)
        hint.frame = CGRect(
            x: 72 + horizontal * 0.4,
            y: anchor.y - 18,
            width: max(50, anchor.x - 122),
            height: 36,
        )
    }

    func update(active: Bool, video: Bool, translation: CGPoint, anchor: CGPoint) {
        self.translation = translation
        self.anchor = anchor
        icon.image = UIImage(
            systemName: video ? "video.fill" : "mic.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium),
        )
        lockIcon.image = UIImage(
            systemName: translation.y < -60 ? "lock.fill" : "lock.open.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold),
        )
        hint.text = translation.x < -70
            ? L10n.betterTG("Composer.ReleaseToCancel")
            : "‹  \(L10n.telegram("Conversation.SlideToCancel"))"
        hint.alpha = max(0, 1 + translation.y / 70)
        setNeedsLayout()
        guard self.active != active else { return }
        self.active = active
        animationGeneration += 1
        let generation = animationGeneration
        if active {
            isHidden = false
            alpha = 0
            circle.transform = CGAffineTransform(scaleX: 0.45, y: 0.45)
            lockPill.transform = CGAffineTransform(translationX: 0, y: 20)
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.76,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
            ) {
                self.alpha = 1
                self.circle.transform = .identity
                self.lockPill.transform = .identity
            }
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.86
            pulse.toValue = 1.08
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            halo.layer.add(pulse, forKey: "recordingPulse")
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                self.alpha = 0
                self.circle.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)
                self.lockPill.transform = CGAffineTransform(translationX: 0, y: -12)
            }, completion: { [weak self] _ in
                guard let self, animationGeneration == generation else { return }
                isHidden = true
                halo.layer.removeAnimation(forKey: "recordingPulse")
            })
        }
    }
}
