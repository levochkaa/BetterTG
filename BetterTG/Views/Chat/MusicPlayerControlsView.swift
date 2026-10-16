// MusicPlayerControlsView.swift

import UIKit

// MARK: - MusicPlayerControlsView

/// OverlayAudioPlayerControlsNode, the panel at the bottom of the music player: the album art beside the title and
/// performer, the scrubber over the elapsed and remaining time, and the order, previous, play/pause, next and looping
/// buttons, at Telegram's offsets from the panel's top.
final class MusicPlayerControlsView: UIView {
    struct Content: Equatable {
        var title: String
        var performer: String
        var isPlaying: Bool
        var position: TimeInterval
        var duration: TimeInterval
        var rate: Float
        /// A track over ten minutes (SharedMediaPlaybackDisplayData's `long`): the rate button shows and the
        /// scrubber scrubs finer as the finger moves down.
        var isLong: Bool
        var settings: MusicPlaybackSettings
        /// False while no track is loaded (the playlist loading its next track): playback buttons are disabled.
        var isEnabled: Bool
    }

    /// OverlayAudioPlayerControlsNode.basePanelHeight.
    static let panelHeight = CGFloat(190)

    var onTogglePlayback: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onOrder: (() -> Void)?
    var onLooping: (() -> Void)?
    var onRate: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onAlbumArt: (() -> Void)?

    /// The small album art the enlarged one grows out of.
    let albumArtView = UIImageView()

    private let albumArtPlaceholder = UIImageView()
    private let titleLabel = UILabel()
    private let performerLabel = UILabel()
    private let scrubber = MusicPlayerScrubberView()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let rateButton = UIButton(type: .system)
    private let orderButton = MusicPlayerButton(highlightsCircle: false)
    private let previousButton = MusicPlayerButton(highlightsCircle: true)
    private let playPauseButton = MusicPlayerButton(highlightsCircle: true)
    private let nextButton = MusicPlayerButton(highlightsCircle: true)
    private let loopingButton = MusicPlayerButton(highlightsCircle: false)
    private var content: Content?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureInfo()
        configureScrubber()
        configureButtons()
        configureLayout()
        accessibilityElements = [
            albumArtView,
            titleLabel,
            performerLabel,
            scrubber,
            elapsedLabel,
            rateButton,
            remainingLabel,
            orderButton,
            previousButton,
            playPauseButton,
            nextButton,
            loopingButton,
        ]
        // A CGColor border doesn't follow appearance changes on its own.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MusicPlayerControlsView, _) in
            view.rateButton.layer.borderColor = UIColor.secondaryLabel.resolvedColor(with: view.traitCollection).cgColor
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// MediaPlayerTimeTextNodeState.string: m:ss, h:mm:ss from an hour, -:-- without a time.
    static func timeString(seconds: Int?) -> String {
        guard let seconds else { return "-:--" }
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let remainder = seconds % 60
        return hours != 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    /// AudioPlaybackRate.stringValue, uppercased in the rate icon: "1X", "1.5X", "2X".
    private static func rateTitle(_ rate: Float) -> String {
        let value = rate.rounded() == rate ? String(Int(rate)) : String(format: "%.1f", rate)
        return "\(value)X"
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func symbol(
        _ name: String,
        pointSize: CGFloat,
        weight: UIImage.SymbolWeight = .semibold,
    ) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    func configure(_ content: Content) {
        guard content != self.content else { return }
        let previous = self.content
        self.content = content
        titleLabel.text = content.title
        performerLabel.text = content.performer
        if previous?.isPlaying != content.isPlaying {
            playPauseButton.setImage(
                Self.symbol(content.isPlaying ? "pause.fill" : "play.fill", pointSize: 34),
                for: .normal,
            )
            playPauseButton.accessibilityLabel = L10n.telegram(
                content.isPlaying ? "VoiceOver.Media.PlaybackPause" : "VoiceOver.Media.PlaybackPlay",
            )
        }
        for button in [previousButton, playPauseButton, nextButton] {
            button.isEnabled = content.isEnabled
        }
        scrubber.fineScrubbingEnabled = content.isLong
        scrubber.isUserInteractionEnabled = content.isEnabled
        scrubber.update(position: content.position, duration: content.isEnabled ? content.duration : 0)
        updateTimeLabels()
        let rateTitle = Self.rateTitle(content.rate)
        rateButton.setTitle(rateTitle, for: .normal)
        rateButton.accessibilityValue = rateTitle
        rateButton.isHidden = !content.isEnabled || !content.isLong
        if previous?.settings != content.settings {
            updateOrderButton(content.settings.order)
            updateLoopingButton(content.settings.looping)
        }
    }

    /// The loaded track's album art; nil shows the placeholder.
    func setAlbumArt(_ image: UIImage?) {
        guard albumArtView.image !== image else { return }
        albumArtView.image = image
        albumArtPlaceholder.isHidden = image != nil
        albumArtView.isAccessibilityElement = image != nil
    }

    private func configureInfo() {
        albumArtView.translatesAutoresizingMaskIntoConstraints = false
        albumArtView.contentMode = .scaleAspectFill
        albumArtView.clipsToBounds = true
        albumArtView.layer.cornerRadius = 10
        albumArtView.layer.cornerCurve = .continuous
        albumArtView.backgroundColor = .secondarySystemFill
        albumArtView.isUserInteractionEnabled = true
        albumArtView.accessibilityLabel = L10n.betterTG("Accessibility.MusicAlbumArt")
        albumArtView.accessibilityTraits = .button
        albumArtView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(albumArtTapped)))
        addSubview(albumArtView)

        albumArtPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        albumArtPlaceholder.image = Self.symbol("music.note", pointSize: 20, weight: .medium)
        albumArtPlaceholder.tintColor = .secondaryLabel
        albumArtView.addSubview(albumArtPlaceholder)

        // stringsForDisplayData: the title in semibold 17, the performer in regular 15.
        for (label, font, color) in [
            (titleLabel, UIFont.systemFont(ofSize: 17, weight: .semibold), UIColor.label),
            (performerLabel, UIFont.systemFont(ofSize: 15, weight: .regular), UIColor.secondaryLabel),
        ] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = font
            label.textColor = color
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
    }

    private func configureScrubber() {
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        scrubber.accessibilityLabel = L10n.betterTG("Accessibility.MusicPlaybackPosition")
        scrubber.onScrub = { [weak self] _ in self?.updateTimeLabels() }
        scrubber.onSeek = { [weak self] timestamp in
            self?.updateTimeLabels()
            self?.onSeek?(timestamp)
        }
        addSubview(scrubber)

        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabel
            addSubview(label)
        }
        remainingLabel.textAlignment = .right

        rateButton.translatesAutoresizingMaskIntoConstraints = false
        rateButton.tintColor = .secondaryLabel
        rateButton.titleLabel?.font = Self.roundedFont(size: 11, weight: .semibold)
        rateButton.layer.borderWidth = 1.5
        rateButton.layer.cornerRadius = 5
        rateButton.layer.cornerCurve = .continuous
        rateButton.layer.borderColor = UIColor.secondaryLabel.cgColor
        rateButton.accessibilityLabel = L10n.telegram("VoiceOver.Media.PlaybackRate")
        rateButton.accessibilityHint = L10n.telegram("VoiceOver.Media.PlaybackRateChange")
        rateButton.isHidden = true
        rateButton.addTarget(self, action: #selector(rateTapped), for: .touchUpInside)
        addSubview(rateButton)
    }

    private func configureButtons() {
        previousButton.setImage(Self.symbol("backward.fill", pointSize: 26), for: .normal)
        previousButton.accessibilityLabel = L10n.betterTG("Accessibility.MusicPreviousTrack")
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        nextButton.setImage(Self.symbol("forward.fill", pointSize: 26), for: .normal)
        nextButton.accessibilityLabel = L10n.betterTG("Accessibility.MusicNextTrack")
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        playPauseButton.setImage(Self.symbol("play.fill", pointSize: 34), for: .normal)
        playPauseButton.accessibilityLabel = L10n.telegram("VoiceOver.Media.PlaybackPlay")
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        for button in [previousButton, playPauseButton, nextButton] {
            button.tintColor = .label
        }
        orderButton.accessibilityLabel = L10n.betterTG("Accessibility.MusicOrder")
        orderButton.addTarget(self, action: #selector(orderTapped), for: .touchUpInside)
        loopingButton.accessibilityLabel = L10n.betterTG("Accessibility.MusicRepeat")
        loopingButton.addTarget(self, action: #selector(loopingTapped), for: .touchUpInside)
        for button in [orderButton, previousButton, playPauseButton, nextButton, loopingButton] {
            addSubview(button)
        }
        updateOrderButton(.regular)
        updateLoopingButton(.off)
    }

    /// updateLayout's frames: the info row 21 pt down, the scrubber 58 pt under it with the times 19 pt below its
    /// line, and 64 pt buttons 34 pt below the line; previous and next span at most 320 pt and keep 76 pt from the
    /// sides, where order and looping sit.
    private func configureLayout() {
        let side = CGFloat(16)
        let scrubberInset = CGFloat(9)
        let infoTop = CGFloat(21)
        let scrubberTop = infoTop + 58
        let buttonSize = CGFloat(64)
        let guide = safeAreaLayoutGuide
        let buttonsGuide = UILayoutGuide()
        addLayoutGuide(buttonsGuide)
        let preferredButtonsWidth = buttonsGuide.widthAnchor.constraint(equalToConstant: 320)
        preferredButtonsWidth.priority = .defaultHigh
        var constraints = [
            albumArtView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: side),
            albumArtView.topAnchor.constraint(equalTo: topAnchor, constant: infoTop - 3),
            albumArtView.widthAnchor.constraint(equalToConstant: 46),
            albumArtView.heightAnchor.constraint(equalToConstant: 46),
            albumArtPlaceholder.centerXAnchor.constraint(equalTo: albumArtView.centerXAnchor),
            albumArtPlaceholder.centerYAnchor.constraint(equalTo: albumArtView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: albumArtView.trailingAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -side),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: infoTop + 1),
            performerLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            performerLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            performerLabel.topAnchor.constraint(equalTo: topAnchor, constant: infoTop + 24),
            scrubber.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: side + scrubberInset),
            scrubber.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -(side + scrubberInset)),
            scrubber.topAnchor.constraint(equalTo: topAnchor, constant: scrubberTop - 8),
            scrubber.heightAnchor.constraint(equalToConstant: 26),
            elapsedLabel.leadingAnchor.constraint(equalTo: scrubber.leadingAnchor),
            elapsedLabel.topAnchor.constraint(equalTo: topAnchor, constant: scrubberTop + 19),
            remainingLabel.trailingAnchor.constraint(equalTo: scrubber.trailingAnchor),
            remainingLabel.topAnchor.constraint(equalTo: elapsedLabel.topAnchor),
            remainingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: elapsedLabel.trailingAnchor, constant: 8),
            rateButton.trailingAnchor.constraint(equalTo: remainingLabel.leadingAnchor, constant: -5),
            rateButton.centerYAnchor.constraint(equalTo: remainingLabel.centerYAnchor),
            rateButton.heightAnchor.constraint(equalToConstant: 18),
            rateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            buttonsGuide.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            buttonsGuide.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            buttonsGuide.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -2 * (side + 60)),
            preferredButtonsWidth,
            buttonsGuide.topAnchor.constraint(equalTo: topAnchor, constant: scrubberTop + 34),
            buttonsGuide.heightAnchor.constraint(equalToConstant: buttonSize),
            previousButton.leadingAnchor.constraint(equalTo: buttonsGuide.leadingAnchor),
            playPauseButton.centerXAnchor.constraint(equalTo: buttonsGuide.centerXAnchor),
            nextButton.trailingAnchor.constraint(equalTo: buttonsGuide.trailingAnchor),
            orderButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: side - 12),
            loopingButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -(side - 12)),
        ]
        for button in [orderButton, previousButton, playPauseButton, nextButton, loopingButton] {
            constraints += [
                button.topAnchor.constraint(equalTo: buttonsGuide.topAnchor),
                button.widthAnchor.constraint(equalToConstant: buttonSize),
                button.heightAnchor.constraint(equalToConstant: buttonSize),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    /// The left time counts up and the right one down (MediaPlayerTimeTextNode's normal and reversed modes); while no
    /// track is loaded both keep their last values (keepPreviousValueOnEmptyState).
    private func updateTimeLabels() {
        guard let content, content.isEnabled, content.duration > 0 else {
            if elapsedLabel.text == nil {
                elapsedLabel.text = Self.timeString(seconds: nil)
                remainingLabel.text = Self.timeString(seconds: nil)
            }
            scrubber.accessibilityValue = nil
            return
        }
        let timestamp = scrubber.displayedTimestamp
        let elapsed = Self.timeString(seconds: Int(floor(timestamp)))
        elapsedLabel.text = elapsed
        remainingLabel.text = Self.timeString(seconds: Int(abs(floor(timestamp - content.duration))))
        scrubber.accessibilityValue = L10n.betterTG(
            "Accessibility.MusicPlaybackPositionValue",
            elapsed,
            Self.timeString(seconds: Int(content.duration)),
        )
    }

    /// updateOrderButton: the reverse icon in the secondary color for the regular order and the accent color for the
    /// reversed one; the shuffle icon in the accent color for the random order.
    private func updateOrderButton(_ order: MusicPlaybackSettings.Order) {
        let (symbol, color, value): (String, UIColor, String) =
            switch order {
            case .regular: ("arrow.up.arrow.down", .secondaryLabel, "Accessibility.MusicOrderRegular")
            case .reversed: ("arrow.up.arrow.down", .systemBlue, "Accessibility.MusicOrderReversed")
            case .random: ("shuffle", .systemBlue, "Accessibility.MusicOrderRandom")
            }
        orderButton.setImage(Self.symbol(symbol, pointSize: 20), for: .normal)
        orderButton.tintColor = color
        orderButton.accessibilityValue = L10n.betterTG(value)
    }

    /// updateLoopButton: repeat in the secondary color while off, repeat-one and repeat in the accent color.
    private func updateLoopingButton(_ looping: MusicPlaybackSettings.Looping) {
        let (symbol, color, value): (String, UIColor, String) =
            switch looping {
            case .off: ("repeat", .secondaryLabel, "Accessibility.MusicRepeatOff")
            case .item: ("repeat.1", .systemBlue, "Accessibility.MusicRepeatOne")
            case .all: ("repeat", .systemBlue, "Accessibility.MusicRepeatAll")
            }
        loopingButton.setImage(Self.symbol(symbol, pointSize: 20), for: .normal)
        loopingButton.tintColor = color
        loopingButton.accessibilityValue = L10n.betterTG(value)
    }

    @objc private func albumArtTapped() {
        guard albumArtView.image != nil else { return }
        onAlbumArt?()
    }

    @objc private func playPauseTapped() {
        onTogglePlayback?()
    }

    @objc private func previousTapped() {
        onPrevious?()
    }

    @objc private func nextTapped() {
        onNext?()
    }

    @objc private func orderTapped() {
        onOrder?()
    }

    @objc private func loopingTapped() {
        onLooping?()
    }

    @objc private func rateTapped() {
        onRate?()
    }
}

// MARK: - MusicPlayerScrubberView

/// MediaPlayerScrubbingNode's standard content as the music player sets it up: a 7 pt line with round caps and no
/// handle. A drag moves the position by its own distance from where it began; on long tracks, moving the finger
/// down past 50, 100 and 150 pt scrubs at half, a quarter and a hundredth of that speed.
final class MusicPlayerScrubberView: UIView, UIGestureRecognizerDelegate {
    private static let lineHeight = CGFloat(7)

    /// The scrubbed position while dragging, then nil once the drag ends.
    var onScrub: ((TimeInterval?) -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var fineScrubbingEnabled = false

    private let trackView = UIView()
    private let fillView = UIView()
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private weak var panRecognizer: UIPanGestureRecognizer?
    private var position: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var scrubbingTimestamp: TimeInterval?
    private var scrubbingBeginTimestamp: TimeInterval?
    private var scrubbingStartLocation: CGPoint?
    private var scrubbingMultiplier = 1.0
    /// A seek the player hasn't reported yet (the scrubber's ignoreSeekId), shown until it does or a second passes.
    private var pendingSeek: (timestamp: TimeInterval, deadline: CFTimeInterval)?

    /// The position the line and the times show: the scrubbed one while dragging.
    var displayedTimestamp: TimeInterval {
        scrubbingTimestamp ?? pendingSeek?.timestamp ?? position
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        trackView.isUserInteractionEnabled = false
        trackView.backgroundColor = .systemFill
        trackView.clipsToBounds = true
        trackView.layer.cornerRadius = Self.lineHeight / 2
        fillView.backgroundColor = .label
        addSubview(trackView)
        trackView.addSubview(fillView)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        self.panRecognizer = pan
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        trackView.frame = CGRect(
            x: 0,
            y: floor((bounds.height - Self.lineHeight) / 2),
            width: bounds.width,
            height: Self.lineHeight,
        )
        let fraction = duration > 0 ? max(0, min(1, displayedTimestamp / duration)) : 0
        fillView.frame = CGRect(x: 0, y: 0, width: trackView.bounds.width * CGFloat(fraction), height: Self.lineHeight)
    }

    /// The sheet's own drag doesn't start on the scrubber, as UISlider keeps its drags.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panRecognizer { return duration > 0 }
        return !(gestureRecognizer is UIPanGestureRecognizer)
    }

    override func accessibilityIncrement() {
        step(by: 5)
    }

    override func accessibilityDecrement() {
        step(by: -5)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        gestureRecognizer === panRecognizer && otherGestureRecognizer is UIPanGestureRecognizer
            && otherGestureRecognizer.view !== self
    }

    func update(position: TimeInterval, duration: TimeInterval) {
        if let pendingSeek, abs(position - pendingSeek.timestamp) < 1 || CACurrentMediaTime() > pendingSeek.deadline {
            self.pendingSeek = nil
        }
        self.position = position
        self.duration = duration
        if duration <= 0, scrubbingStartLocation != nil { endScrubbing(applying: false) }
        setNeedsLayout()
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard duration > 0 else { return }
            let start = displayedTimestamp
            scrubbingStartLocation = location
            scrubbingBeginTimestamp = start
            scrubbingTimestamp = start
            scrubbingMultiplier = 1
            pendingSeek = nil
            feedback.prepare()
            setNeedsLayout()
            onScrub?(start)
        case .changed:
            guard let start = scrubbingStartLocation else { return }
            if fineScrubbingEnabled, location.y > start.y {
                let distance = location.y - start.y
                let multiplier: Double =
                    if distance > 150 {
                        0.01
                    } else if distance > 100 {
                        0.25
                    } else if distance > 50 {
                        0.5
                    } else {
                        1
                    }
                // A new speed carries on from the scrubbed position and the finger's current x.
                if multiplier != scrubbingMultiplier {
                    scrubbingMultiplier = multiplier
                    scrubbingStartLocation = CGPoint(x: location.x, y: start.y)
                    scrubbingBeginTimestamp = scrubbingTimestamp
                    feedback.impactOccurred()
                    return
                }
            }
            scrub(to: location)
        case .cancelled, .ended, .failed:
            guard scrubbingStartLocation != nil else { return }
            scrub(to: location)
            endScrubbing(applying: recognizer.state == .ended)
        default:
            break
        }
    }

    private func scrub(to location: CGPoint) {
        guard let start = scrubbingStartLocation, let begin = scrubbingBeginTimestamp, duration > 0,
              bounds.width > 0 else { return }
        let fraction = Double((location.x - start.x) / bounds.width)
        let timestamp = max(0, min(duration, begin + duration * fraction * scrubbingMultiplier))
        scrubbingTimestamp = timestamp
        setNeedsLayout()
        onScrub?(timestamp)
    }

    private func endScrubbing(applying: Bool) {
        let timestamp = scrubbingTimestamp
        scrubbingStartLocation = nil
        scrubbingBeginTimestamp = nil
        scrubbingTimestamp = nil
        scrubbingMultiplier = 1
        if applying, let timestamp {
            pendingSeek = (timestamp, CACurrentMediaTime() + 1)
        }
        setNeedsLayout()
        onScrub?(nil)
        if applying, let timestamp { onSeek?(timestamp) }
    }

    private func step(by seconds: TimeInterval) {
        guard duration > 0 else { return }
        let timestamp = max(0, min(duration, displayedTimestamp + seconds))
        pendingSeek = (timestamp, CACurrentMediaTime() + 1)
        setNeedsLayout()
        onSeek?(timestamp)
    }
}

// MARK: - MusicPlayerButton

/// IconButtonNode with the player's circleColor: a soft circle shows behind the icon while it's pressed.
private final class MusicPlayerButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            guard highlightsCircle, isHighlighted != oldValue else { return }
            let alpha: CGFloat = isHighlighted ? 1 : 0
            UIView.animate(
                withDuration: isHighlighted ? 0.1 : 0.25,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
            ) {
                self.circleView.alpha = alpha
            }
        }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }

    private let circleView = UIView()
    private let highlightsCircle: Bool

    init(highlightsCircle: Bool) {
        self.highlightsCircle = highlightsCircle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        circleView.isUserInteractionEnabled = false
        circleView.backgroundColor = .systemFill
        circleView.alpha = 0
        insertSubview(circleView, at: 0)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        circleView.frame = bounds
        circleView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        sendSubviewToBack(circleView)
    }
}
