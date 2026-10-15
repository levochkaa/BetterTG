// MessageVoiceNoteView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - VoiceNotePlaybackView

/// Telegram's voice message bubble (ChatMessageInteractiveFileNode). The note's file loads through the client that
/// listed its message and follows only that client's file updates; the bubble never follows a replacement client.
/// A self-destructing note is never loaded here: like Telegram's view-once voice, it plays once in an overlay that
/// consumes it.
final class VoiceNotePlaybackView: UIView, ReusableMediaView {
    // MARK: Private

    private let playButton = UIButton(type: .system)
    private let waveformView = TelegramWaveformView()
    private let durationLabel = UILabel()
    /// Telegram's view-once badge on the play button; a timed note shows a timer.
    private let selfDestructBadge = UIImageView()
    /// Telegram's consumable-content dot: the note has not been listened to yet (by the user, or by the recipient of
    /// an outgoing note).
    private let unlistenedDot = UIView()
    private var message: Message?
    private var voiceNote: VoiceNote?
    private var backend: VideoNotePlaybackBackend?
    private var permit: MediaRevealPermit?
    private var localPath: String?
    private var isListened = true
    private var isSelfDestructing = false
    private var configurationID = UUID()
    private var downloadTask: Task<Void, Never>?
    private var bindings = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()

    private var isCurrentVoice: Bool {
        guard let localPath else { return false }
        return Media.shared.savedMediaPath == localPath
    }

    private var isCurrentVoicePlaying: Bool {
        isCurrentVoice && Media.shared.isPlaying
    }

    /// An incoming note the user hasn't played, or a sent note its recipient hasn't played. A sent note's state is
    /// its recipient's, so Saved Messages and group or channel posts, which have no single recipient, show no dot.
    private var showsUnlistenedDot: Bool {
        guard !isListened, let message else { return false }
        guard message.isOutgoing else { return true }
        return message.sendingState == nil && message.chatId > 0
            && message.chatId != TDLib.shared.activeAccount?.userID
    }

    private var hostViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        Media.shared
            .objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.render() } }
            .store(in: &cancellables)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func decodeWaveform(_ data: Data) -> [CGFloat] {
        guard !data.isEmpty else { return [] }
        let sampleCount = data.count * 8 / 5
        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (0..<sampleCount).map { index in
                let bitOffset = index * 5
                let byteIndex = bitOffset / 8
                let shift = bitOffset % 8
                var value = UInt16(bytes[byteIndex])
                if byteIndex + 1 < bytes.count {
                    value |= UInt16(bytes[byteIndex + 1]) << 8
                }
                return CGFloat((value >> shift) & 0x1F) / 31
            }
        }
    }

    // MARK: Internal

    func configure(
        message: Message,
        client: TDLibClient,
        context: MediaGalleryPlaybackContext?,
        permit: MediaRevealPermit?,
    ) {
        prepareForReuse()
        guard case .messageVoiceNote(let value) = message.content else { return }
        let voiceNote = value.voiceNote
        self.message = message
        self.voiceNote = voiceNote
        self.permit = permit
        isListened = value.isListened
        isSelfDestructing = message.selfDestructType != nil
        configureSelfDestructBadge(message.selfDestructType)
        waveformView.samples = Self.decodeWaveform(voiceNote.waveform)
        // File IDs belong to the client that listed the message, so the note loads only through that client.
        if let backend = VideoNotePlaybackBackend.captured(client: client, context: context) {
            self.backend = backend
            observe(backend)
            if !isSelfDestructing {
                update(file: voiceNote.voice)
                startDownload(using: backend)
            }
        }
        render()
    }

    func prepareForReuse() {
        configurationID = UUID()
        bindings.removeAll()
        downloadTask?.cancel()
        downloadTask = nil
        if let backend, let fileID = voiceNote?.voice.id, localPath == nil {
            Task { await backend.cancelDownload(fileID) }
        }
        backend = nil
        permit = nil
        message = nil
        voiceNote = nil
        localPath = nil
        isListened = true
        isSelfDestructing = false
        selfDestructBadge.isHidden = true
        waveformView.samples = []
        waveformView.progress = 0
    }

    private func configureViews() {
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold),
            forImageIn: .normal,
        )
        playButton.tintColor = .white
        playButton.backgroundColor = .systemBlue
        playButton.layer.cornerRadius = 20
        playButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        addSubview(playButton)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.unplayedColor = UIColor.secondaryLabel.withAlphaComponent(0.55)
        waveformView.playedColor = .systemBlue
        waveformView.onSeek = { [weak self] progress in self?.seek(to: progress) }
        addSubview(waveformView)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = .secondaryLabel
        durationLabel.textAlignment = .left
        addSubview(durationLabel)

        unlistenedDot.translatesAutoresizingMaskIntoConstraints = false
        unlistenedDot.backgroundColor = .systemBlue
        unlistenedDot.layer.cornerRadius = 3
        unlistenedDot.isHidden = true
        addSubview(unlistenedDot)

        selfDestructBadge.translatesAutoresizingMaskIntoConstraints = false
        selfDestructBadge.contentMode = .scaleAspectFit
        selfDestructBadge.tintColor = .systemBlue
        selfDestructBadge.backgroundColor = .systemBackground
        selfDestructBadge.layer.cornerRadius = 9
        selfDestructBadge.clipsToBounds = true
        selfDestructBadge.isHidden = true
        addSubview(selfDestructBadge)

        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40),

            waveformView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            waveformView.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 9),
            waveformView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            waveformView.heightAnchor.constraint(equalToConstant: 30),
            durationLabel.topAnchor.constraint(equalTo: waveformView.bottomAnchor, constant: 1),
            durationLabel.leadingAnchor.constraint(equalTo: waveformView.leadingAnchor),
            durationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            unlistenedDot.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 4),
            unlistenedDot.trailingAnchor.constraint(lessThanOrEqualTo: waveformView.trailingAnchor),
            unlistenedDot.centerYAnchor.constraint(equalTo: durationLabel.centerYAnchor),
            unlistenedDot.widthAnchor.constraint(equalToConstant: 6),
            unlistenedDot.heightAnchor.constraint(equalToConstant: 6),
            selfDestructBadge.centerXAnchor.constraint(equalTo: playButton.trailingAnchor, constant: -4),
            selfDestructBadge.centerYAnchor.constraint(equalTo: playButton.bottomAnchor, constant: -4),
            selfDestructBadge.widthAnchor.constraint(equalToConstant: 18),
            selfDestructBadge.heightAnchor.constraint(equalToConstant: 18),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 225),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    private func observe(_ backend: VideoNotePlaybackBackend) {
        let bindingID = configurationID
        backend.observe(&bindings, for: .updateFile) { [weak self] event in
            guard let self, configurationID == bindingID, event.source == backend.source, backend.isCurrent()
            else { return }
            update(file: event.value.file)
        }
        backend.clientChanges
            .sink { [weak self] _ in
                guard let self, configurationID == bindingID, !backend.isCurrent() else { return }
                downloadTask?.cancel()
                downloadTask = nil
            }
            .store(in: &bindings)
    }

    private func startDownload(using backend: VideoNotePlaybackBackend) {
        guard localPath == nil, let fileID = voiceNote?.voice.id else { return }
        let bindingID = configurationID
        downloadTask = Task { [weak self] in
            let downloaded = try? await backend.download(fileID, false)
            guard let self, configurationID == bindingID else { return }
            downloadTask = nil
            guard let downloaded, backend.isCurrent() else { return }
            update(file: downloaded)
        }
    }

    private func update(file: File) {
        guard voiceNote?.voice.id == file.id, file.local.isDownloadingCompleted,
              !file.local.path.isEmpty else { return }
        localPath = file.local.path
        render()
    }

    private func render() {
        guard let message, let voiceNote else { return }
        unlistenedDot.isHidden = !showsUnlistenedDot
        playButton.accessibilityValue = showsUnlistenedDot ? L10n.betterTG("Accessibility.VoiceNotListened") : nil
        guard !isSelfDestructing else {
            // Telegram neither scrubs nor shows progress in a play-once bubble; the overlay plays it.
            playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            durationLabel.text = format(voiceNote.duration)
            waveformView.progress = 0
            waveformView.isEnabled = false
            let enabled = backend?.isCurrent() == true && permit?.matches(message) == true
            playButton.isEnabled = enabled
            playButton.alpha = enabled ? 1 : 0.45
            playButton.accessibilityHint = L10n.telegram("Chat.PlayOnceVoiceMessageTooltip")
            return
        }
        playButton.accessibilityHint = nil
        playButton.setImage(
            UIImage(systemName: isCurrentVoicePlaying ? "pause.fill" : "play.fill"),
            for: .normal,
        )
        // Telegram's waveform follows the exact position; whole seconds made it jump once a second.
        let position = isCurrentVoice ? Media.shared.playbackPosition : 0
        durationLabel.text = "\(format(Int(position))) / \(format(voiceNote.duration))"
        waveformView.progress = voiceNote.duration > 0
            ? min(1, max(0, CGFloat(position / Double(voiceNote.duration))))
            : 0
        let enabled = localPath != nil
        playButton.isEnabled = enabled
        playButton.alpha = enabled ? 1 : 0.45
        waveformView.isEnabled = enabled
    }

    private func configureSelfDestructBadge(_ type: MessageSelfDestructType?) {
        let symbol: String? =
            switch type {
            case .messageSelfDestructTypeImmediately: "1.circle.fill"
            case .messageSelfDestructTypeTimer: "timer.circle.fill"
            case nil: nil
            }
        selfDestructBadge.image = symbol.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        }
        selfDestructBadge.isHidden = symbol == nil
    }

    private func format(_ duration: Int) -> String {
        String(format: "%d:%02d", duration / 60, duration % 60)
    }

    private func seek(to progress: CGFloat) {
        guard !isSelfDestructing, let localPath, let voiceNote else { return }
        let time = TimeInterval(progress) * TimeInterval(voiceNote.duration)
        if isCurrentVoice {
            Media.shared.seek(to: time)
        } else if !Media.shared.isPlaying {
            // Scrubbing positions a note without starting it; the next tap plays from there.
            Media.shared.prepare(with: localPath, duration: voiceNote.duration, at: time)
        } else {
            // Telegram scrubs only the current note, so another note's playback keeps going.
            render()
        }
    }

    @objc private func toggle() {
        guard !isSelfDestructing else {
            presentPlayOnce()
            return
        }
        guard let localPath, let voiceNote else { return }
        let starts = !isCurrentVoicePlaying
        Media.shared.toggle(with: localPath, duration: voiceNote.duration)
        if starts { markListened() }
    }

    /// Telegram opens a view-once voice message in its play-once overlay, and refuses while the screen is recorded
    /// (ChatControllerImpl.openViewOnceMediaMessage).
    private func presentPlayOnce() {
        guard let message, let voiceNote, let backend, backend.isCurrent(), let permit, permit.matches(message),
              let presenter = hostViewController?.chatListTopPresenter else { return }
        guard traitCollection.sceneCaptureState != .active else {
            let alert = UIAlertController(
                title: nil,
                message: L10n.telegram("Chat.PlayOnceMesasge.DisableScreenCapture"),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            presenter.present(alert, animated: true)
            return
        }
        presenter.present(
            VoicePlayOnceViewController(message: message, voiceNote: voiceNote, backend: backend, permit: permit),
            animated: true,
        )
    }

    /// Telegram marks a voice message consumed when its playback starts (PeerMessagesMediaPlaylist
    /// onItemPlaybackStarted). TDLib's openMessageContent on the message's own client marks it listened, which the
    /// sender sees; an outgoing note stays unlistened until its recipient plays it.
    private func markListened() {
        guard !isListened, let message, !message.isOutgoing, let backend, backend.isCurrent() else { return }
        isListened = true
        render()
        let bindingID = configurationID
        Task { [weak self] in
            do {
                try await backend.open(message.chatId, message.id)
            } catch {
                guard let self, configurationID == bindingID else { return }
                isListened = false
                render()
            }
        }
    }
}

// MARK: - TelegramWaveformView

final class TelegramWaveformView: UIControl {
    var samples = [CGFloat]() {
        didSet { setNeedsDisplay() }
    }

    var progress = CGFloat.zero {
        didSet {
            accessibilityValue = "\(Int(min(1, max(0, progress)) * 100)) percent"
            setNeedsDisplay()
        }
    }

    var playedColor = UIColor.systemBlue {
        didSet { setNeedsDisplay() }
    }

    var unplayedColor = UIColor.secondaryLabel {
        didSet { setNeedsDisplay() }
    }

    var onSeek: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = L10n.betterTG("Accessibility.VoiceWaveform")
        accessibilityTraits = [.adjustable]
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        let bars = resampledBars()
        draw(bars: bars, color: unplayedColor, context: context, clipWidth: bounds.width)
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height))
        draw(bars: bars, color: playedColor, context: context, clipWidth: bounds.width * progress)
        context.restoreGState()
    }

    override func beginTracking(_ touch: UITouch, with _: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        updateProgress(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with _: UIEvent?) -> Bool {
        updateProgress(for: touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with _: UIEvent?) {
        if let touch {
            updateProgress(for: touch)
        }
    }

    override func accessibilityIncrement() {
        applyAccessibleProgress(progress + 0.05)
    }

    override func accessibilityDecrement() {
        applyAccessibleProgress(progress - 0.05)
    }

    // MARK: Private

    private func updateProgress(for touch: UITouch) {
        guard bounds.width > 0 else { return }
        let updated = min(1, max(0, touch.location(in: self).x / bounds.width))
        progress = updated
        accessibilityValue = L10n.betterTG("Accessibility.Percent", Int(updated * 100))
        onSeek?(updated)
    }

    private func applyAccessibleProgress(_ updated: CGFloat) {
        let clipped = min(1, max(0, updated))
        progress = clipped
        accessibilityValue = L10n.betterTG("Accessibility.Percent", Int(clipped * 100))
        onSeek?(clipped)
    }

    private func resampledBars() -> [CGFloat] {
        let targetCount = max(1, Int(bounds.width / 3.5))
        guard !samples.isEmpty else {
            return (0..<targetCount).map { index in
                0.2 + CGFloat((index * 17) % 13) / 40
            }
        }
        return (0..<targetCount).map { targetIndex in
            let lower = targetIndex * samples.count / targetCount
            let upper = max(lower + 1, (targetIndex + 1) * samples.count / targetCount)
            return samples[lower..<min(upper, samples.count)].max() ?? 0
        }
    }

    private func draw(bars: [CGFloat], color: UIColor, context: CGContext, clipWidth _: CGFloat) {
        let spacing: CGFloat = 1.5
        let barWidth = max(1.5, (bounds.width - spacing * CGFloat(max(0, bars.count - 1))) / CGFloat(bars.count))
        context.setFillColor(color.cgColor)
        for (index, sample) in bars.enumerated() {
            let height = max(3, min(bounds.height, 3 + sample * (bounds.height - 3)))
            let x = CGFloat(index) * (barWidth + spacing)
            let barRect = CGRect(x: x, y: (bounds.height - height) / 2, width: barWidth, height: height)
            context.fillEllipse(in: barRect)
        }
    }
}
