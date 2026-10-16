// VoicePlaybackHeaderView.swift

import UIKit

// MARK: - VoicePlaybackHeaderView

/// Telegram's playback header (MediaNavigationAccessoryHeaderNode): play/pause, the author over "Voice Message" or
/// the group, the playback rate, close, and a 2 pt progress line along the bottom. Tapping the text opens the note.
final class VoicePlaybackHeaderView: UIView {
    struct Content: Equatable {
        let title: String
        let subtitle: String
        let isPlaying: Bool
        let progress: CGFloat
        let rate: Float
        /// Hidden for music under ten minutes, as Telegram does.
        var showsRate = true
        /// Music swipes between the chat's tracks.
        var isMusic = false
    }

    static let contentHeight = CGFloat(37)

    var onTogglePlayback: (() -> Void)?
    var onCycleRate: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpen: (() -> Void)?
    /// MediaNavigationAccessoryHeaderNode's horizontal swipe, which pulls in the track beside the current one: the
    /// playlist's next track sits on the left, so a swipe to the right plays it and a swipe to the left plays the
    /// previous one.
    var onPlayNext: (() -> Void)?
    var onPlayPrevious: (() -> Void)?

    private let playButton = UIButton(type: .system)
    private let openControl = UIControl()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let rateButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let progressView = UIView()
    private let separator = UIView()
    private var progress = CGFloat(0)
    private var content: Content?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.tintColor = .systemBlue
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        addSubview(playButton)

        openControl.translatesAutoresizingMaskIntoConstraints = false
        openControl.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        openControl.isAccessibilityElement = true
        openControl.accessibilityTraits = .button
        addSubview(openControl)
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(trackSwiped(_:)))
            swipe.direction = direction
            openControl.addGestureRecognizer(swipe)
        }

        for (label, color) in [(titleLabel, UIColor.label), (subtitleLabel, UIColor.secondaryLabel)] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
                for: .systemFont(ofSize: 12, weight: .regular),
                maximumPointSize: 14,
            )
            label.adjustsFontForContentSizeCategory = true
            label.textColor = color
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.isUserInteractionEnabled = false
            openControl.addSubview(label)
        }

        rateButton.translatesAutoresizingMaskIntoConstraints = false
        rateButton.tintColor = .secondaryLabel
        rateButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold).rounded
        rateButton.layer.borderWidth = 1.5
        rateButton.layer.cornerRadius = 5
        rateButton.layer.cornerCurve = .continuous
        rateButton.layer.borderColor = UIColor.secondaryLabel.cgColor
        rateButton.accessibilityLabel = L10n.telegram("VoiceOver.Media.PlaybackRate")
        rateButton.accessibilityHint = L10n.telegram("VoiceOver.Media.PlaybackRateChange")
        rateButton.addTarget(self, action: #selector(rateTapped), for: .touchUpInside)
        rateButton.setContentHuggingPriority(.required, for: .horizontal)
        rateButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(rateButton)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = .secondaryLabel
        closeButton.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            ),
            for: .normal,
        )
        closeButton.accessibilityLabel = L10n.telegram("VoiceOver.Media.PlaybackStop")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)

        progressView.backgroundColor = .systemBlue
        addSubview(progressView)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
            playButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            playButton.topAnchor.constraint(equalTo: topAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            closeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: topAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            rateButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            rateButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            rateButton.heightAnchor.constraint(equalToConstant: 18),
            rateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            openControl.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 4),
            openControl.trailingAnchor.constraint(equalTo: rateButton.leadingAnchor, constant: -8),
            openControl.topAnchor.constraint(equalTo: topAnchor),
            openControl.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            titleLabel.leadingAnchor.constraint(equalTo: openControl.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: openControl.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: openControl.centerYAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: openControl.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: openControl.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
        ])
        accessibilityElements = [playButton, openControl, rateButton, closeButton]
        // A CGColor border doesn't follow appearance changes on its own.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.rateButton.layer.borderColor = UIColor.secondaryLabel.resolvedColor(with: self.traitCollection).cgColor
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        progressView.frame = CGRect(
            x: 0,
            y: min(bounds.height, Self.contentHeight) - 2,
            width: bounds.width * progress,
            height: 2,
        )
    }

    /// Telegram's AudioPlaybackRate.stringValue, uppercased in the rate icon: "1X", "1.5X", "2X".
    private static func rateTitle(_ rate: Float) -> String {
        let value = rate.rounded() == rate ? String(Int(rate)) : String(format: "%.1f", rate)
        return "\(value)X"
    }

    func configure(_ content: Content) {
        guard content != self.content else { return }
        self.content = content
        titleLabel.text = content.title
        subtitleLabel.text = content.subtitle
        openControl.accessibilityLabel = "\(content.title). \(content.subtitle)"
        playButton.setImage(UIImage(systemName: content.isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = L10n.telegram(
            content.isPlaying ? "VoiceOver.Media.PlaybackPause" : "VoiceOver.Media.PlaybackPlay",
        )
        let rateTitle = Self.rateTitle(content.rate)
        rateButton.setTitle(rateTitle, for: .normal)
        rateButton.accessibilityValue = rateTitle
        rateButton.isHidden = !content.showsRate
        progress = max(0, min(1, content.progress))
        setNeedsLayout()
    }

    @objc private func playTapped() {
        onTogglePlayback?()
    }

    @objc private func openTapped() {
        onOpen?()
    }

    @objc private func rateTapped() {
        onCycleRate?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func trackSwiped(_ gesture: UISwipeGestureRecognizer) {
        guard content?.isMusic == true else { return }
        if gesture.direction == .right {
            onPlayNext?()
        } else {
            onPlayPrevious?()
        }
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

#if DEBUG
    /// Shows the header in a playing and a paused state and cycles the rate through the real Media path.
    /// Launch with `-ui-probe-voice-header`.
    @MainActor enum VoicePlaybackHeaderProbe {
        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-voice-header") else { return }
            Task { @MainActor in
                try? await ProbeFixtures.waitForActiveAccount()
                run(in: window)
            }
        }

        private static func run(in window: UIWindow) {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            let playing = VoicePlaybackHeaderView()
            let paused = VoicePlaybackHeaderView()
            for (index, header) in [playing, paused].enumerated() {
                header.translatesAutoresizingMaskIntoConstraints = false
                header.accessibilityIdentifier = "voice-header-\(index)"
                controller.view.addSubview(header)
                NSLayoutConstraint.activate([
                    header.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
                    header.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
                    header.topAnchor.constraint(
                        equalTo: controller.view.safeAreaLayoutGuide.topAnchor,
                        constant: CGFloat(index) * 60 + 20,
                    ),
                    header.heightAnchor.constraint(equalToConstant: VoicePlaybackHeaderView.contentHeight),
                ])
            }
            let start = Media.shared.playbackRate
            Media.shared.cyclePlaybackRate()
            let cycled = Media.shared.playbackRate
            while Media.shared.playbackRate != start {
                Media.shared.cyclePlaybackRate()
            }
            playing.configure(.init(
                title: "Ada Lovelace", subtitle: L10n.telegram("MusicPlayer.VoiceNote"),
                isPlaying: true, progress: 0.4, rate: 1.5,
            ))
            paused.configure(.init(
                title: "A very long author name that has to be truncated in the middle", subtitle: "Parity Group",
                isPlaying: false, progress: 1, rate: 2,
            ))
            controller.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(controller, animated: false)
            controller.view.layoutIfNeeded()
            log(
                "Voice header probe: rate \(start)->\(cycled)->\(Media.shared.playbackRate), height=\(playing.bounds.height)",
            )
        }
    }
#endif
