// TelegramLinkResolution.swift

import UIKit

// MARK: - TelegramLinkResolution

/// Owns the router's current operation and its delayed loading overlay. Replacement must clear the old overlay
/// even when TDLib has not returned from a cancelled request. All router entry points use the same owner.
@MainActor final class TelegramLinkResolution {
    private var currentTask: Task<Void, Never>?
    private var progress: LinkResolutionProgressView?

    var task: Task<Void, Never>? {
        get { currentTask }
        set {
            currentTask?.cancel()
            progress?.finish(animated: false)
            progress = nil
            currentTask = newValue
        }
    }

    /// Telegram shows progress once resolving needs the network. TDLib doesn't expose cache/network boundaries,
    /// so keep BetterTG's 250 ms delay; completion before it must never flash an overlay.
    func showProgress(in window: UIWindow?) {
        guard let task, let window else { return }
        progress?.finish(animated: false)
        let progress = LinkResolutionProgressView { [weak self] in self?.cancel() }
        self.progress = progress
        progress.onRemoval = { [weak self, weak progress] in
            if self?.progress === progress { self?.progress = nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak progress, weak window] in
            guard let progress, let window else { return }
            progress.show(in: window)
        }
        Task { [weak progress] in
            await task.value
            progress?.finish()
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        progress?.finish()
    }
}

// MARK: - LinkResolutionProgressView

/// Telegram OverlayStatusController's ProgressWindow + the loading branch of ProgressSpinnerView.
/// Blur stays non-glass. The full-window view intercepts touches, including taps outside the 100 pt square.
final class LinkResolutionProgressView: UIView {
    var onRemoval: (() -> Void)?

    private let cancel: () -> Void
    private let container = UIVisualEffectView()
    private let tint = UIView()
    private let spinner = UIView()
    private let arc = CAShapeLayer()
    private var isFinished = false

    init(cancel: @escaping () -> Void) {
        self.cancel = cancel
        super.init(frame: .zero)
        backgroundColor = .clear
        container.layer.cornerRadius = 20
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        tint.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        container.contentView.addSubview(tint)
        container.contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 100),
            container.heightAnchor.constraint(equalToConstant: 100),
            tint.topAnchor.constraint(equalTo: container.contentView.topAnchor),
            tint.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: container.contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.contentView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 48),
            spinner.heightAnchor.constraint(equalToConstant: 48),
        ])
        // ProgressSpinnerView: 4 pt round stroke, 3 pt outer inset, a three-quarter arc at radius 19.
        arc.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        arc.path = UIBezierPath(
            arcCenter: CGPoint(x: 24, y: 24),
            radius: 19,
            startAngle: -2 * .pi,
            endAngle: -.pi / 2,
            clockwise: true,
        ).cgPath
        arc.fillColor = UIColor.clear.cgColor
        arc.lineWidth = 4
        arc.lineCap = .round
        spinner.layer.addSublayer(arc)
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (
            self: LinkResolutionProgressView,
            _: UITraitCollection,
        ) in
            self.updateAppearance()
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityViewIsModal = true
        accessibilityIdentifier = "telegram-link-progress"
        accessibilityLabel = L10n.telegram("Common.Cancel")
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityActivate() -> Bool {
        tapped()
        return true
    }

    override func accessibilityPerformEscape() -> Bool {
        tapped()
        return true
    }

    func show(in window: UIWindow) {
        guard !isFinished, superview == nil else { return }
        frame = window.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(self)
        layoutIfNeeded()
        updateAppearance()
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = -2 * Double.pi
        rotation.duration = 0.75
        rotation.isCumulative = true
        rotation.repeatCount = .infinity
        arc.add(rotation, forKey: "rotation")
        container.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(springDuration: 0.3, bounce: 0) { self.container.transform = .identity }
        UIView.animate(withDuration: 0.3) { self.container.alpha = 1 }
    }

    /// Replacement removes immediately; completion/cancel fades. Finishing before delayed show is terminal.
    func finish(animated: Bool = true) {
        // A replacement can arrive during an earlier completion/cancel fade. It removes that retiring view too.
        if !animated {
            isFinished = true
            isUserInteractionEnabled = false
            remove()
            return
        }
        guard !isFinished else { return }
        isFinished = true
        isUserInteractionEnabled = false
        guard superview != nil else {
            remove()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: .beginFromCurrentState) {
            self.container.alpha = 0
        } completion: { _ in self.remove() }
    }

    private func remove() {
        arc.removeAnimation(forKey: "rotation")
        removeFromSuperview()
        let completion = onRemoval
        onRemoval = nil
        completion?()
    }

    private func updateAppearance() {
        let light = traitCollection.userInterfaceStyle != .dark
        container.effect = UIBlurEffect(style: light ? .light : .dark)
        tint.backgroundColor = light ? UIColor(white: 244 / 255, alpha: 0.75) : .clear
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.strokeColor = (light ? UIColor(white: 90 / 255, alpha: 1) : .white).cgColor
        CATransaction.commit()
    }

    @objc private func tapped() {
        guard !isFinished else { return }
        cancel()
        finish()
    }
}
