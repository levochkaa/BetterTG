// VoicePlayOnceViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - VoicePlayOnceViewController

/// Telegram's play-once overlay for a self-destructing voice message (ChatControllerImpl.openViewOnceMediaMessage): the
/// note plays once over the dimmed chat, its waveform can't be scrubbed, and closing ends it. TDLib deletes a view-once
/// note's file as soon as its content is opened, so the note is first decoded into a private temporary file, and only
/// then does openMessageContent run on the message's own client. A note that can't be loaded is not opened and stays
/// playable. The private file is removed when playback ends or the overlay closes.
final class VoicePlayOnceViewController: UIViewController {
    // MARK: Private

    private let message: Message
    private let voiceNote: VoiceNote
    private let backend: VideoNotePlaybackBackend
    private let permit: MediaRevealPermit
    private let player = LocalMediaPlayer()
    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let tooltipLabel = UILabel()
    private let cardView = UIView()
    private let playButton = UIButton(type: .system)
    private let waveformView = TelegramWaveformView()
    private let durationLabel = UILabel()
    private let closeButton = UIButton(configuration: .filled())
    private var privateFileURL: URL?
    private var preparationTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isFinished = false

    private var isViewOnce: Bool {
        if case .messageSelfDestructTypeImmediately = message.selfDestructType { return true }
        return false
    }

    /// Playback may continue only while this overlay, the message's client and an unrecorded foreground screen last.
    private var admitsPlayback: Bool {
        !Task.isCancelled && !isFinished && backend.isCurrent() && viewIfLoaded?.window != nil
            && traitCollection.sceneCaptureState != .active && UIApplication.shared.applicationState == .active
    }

    /// Opening the note also needs the chat route that showed it: the reveal permit for its current revision.
    private var admitsOpening: Bool {
        admitsPlayback && permit.matches(message)
    }

    init(message: Message, voiceNote: VoiceNote, backend: VideoNotePlaybackBackend, permit: MediaRevealPermit) {
        self.message = message
        self.voiceNote = voiceNote
        self.backend = backend
        self.permit = permit
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        preparationTask?.cancel()
        deadlineTask?.cancel()
        if let privateFileURL { try? FileManager.default.removeItem(at: privateFileURL) }
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        observe()
        render(position: 0)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard preparationTask == nil, !isFinished else { return }
        preparationTask = Task { [weak self] in await self?.prepareAndPlay() }
    }

    override func accessibilityPerformEscape() -> Bool {
        finish()
        return true
    }

    private static func decodedSizeLimit(duration: Int) -> Int64 {
        // 16-bit stereo at 48 kHz, the decoder's widest output, with room for a duration rounded down.
        Int64(max(60, duration + 10)) * 48000 * 2 * 2 + 44
    }

    private func configureViews() {
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        view.addSubview(backgroundView)

        tooltipLabel.translatesAutoresizingMaskIntoConstraints = false
        tooltipLabel.text = L10n.telegram("Chat.PlayOnceVoiceMessageTooltip")
        tooltipLabel.font = .preferredFont(forTextStyle: .footnote)
        tooltipLabel.adjustsFontForContentSizeCategory = true
        tooltipLabel.textColor = .white
        tooltipLabel.textAlignment = .center
        tooltipLabel.numberOfLines = 0
        view.addSubview(tooltipLabel)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 18
        view.addSubview(cardView)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold),
            forImageIn: .normal,
        )
        playButton.tintColor = .white
        playButton.backgroundColor = .systemBlue
        playButton.layer.cornerRadius = 20
        playButton.isEnabled = false
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        cardView.addSubview(playButton)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.samples = VoiceNoteCodec.normalizedWaveform(data: voiceNote.waveform).map { CGFloat($0) }
        waveformView.unplayedColor = UIColor.secondaryLabel.withAlphaComponent(0.55)
        waveformView.playedColor = .systemBlue
        waveformView.isEnabled = false
        cardView.addSubview(waveformView)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = .secondaryLabel
        cardView.addSubview(durationLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        // Telegram's incoming view-once note is deleted on close; a timed or sent note only closes.
        closeButton.configuration?.title = L10n.telegram(
            isViewOnce && !message.isOutgoing ? "Chat.PlayOnceMesasgeCloseAndDelete" : "Chat.PlayOnceMesasgeClose",
        )
        closeButton.configuration?.cornerStyle = .capsule
        closeButton.configuration?.baseBackgroundColor = .secondarySystemBackground
        closeButton.configuration?.baseForegroundColor = .label
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(closeButton)

        let cardWidth = cardView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -48)
        cardWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            cardWidth,
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 340),

            tooltipLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            tooltipLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            tooltipLabel.bottomAnchor.constraint(equalTo: cardView.topAnchor, constant: -16),

            playButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            playButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            playButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40),

            waveformView.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 9),
            waveformView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            waveformView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            waveformView.heightAnchor.constraint(equalToConstant: 30),
            durationLabel.leadingAnchor.constraint(equalTo: waveformView.leadingAnchor),
            durationLabel.topAnchor.constraint(equalTo: waveformView.bottomAnchor, constant: 1),

            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 16),
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func observe() {
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .ended:
                    // Telegram closes the overlay once the note has played.
                    finish()
                case .failed:
                    finish(failed: true)
                case .buffering,
                     .idle,
                     .paused,
                     .playing,
                     .preparing:
                    render(position: nil)
                }
            }
            .store(in: &cancellables)
        player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.render(position: time) }
            .store(in: &cancellables)
        // Another player taking over the audio ends the single play.
        Media.shared
            .$isPlaying
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard isPlaying else { return }
                self?.finish()
            }
            .store(in: &cancellables)
        backend.clientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !backend.isCurrent() else { return }
                finish()
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.player.pause() }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.finish() }
            .store(in: &cancellables)
        registerForTraitChanges([UITraitSceneCaptureState.self]) { (controller: VoicePlayOnceViewController, _) in
            guard controller.traitCollection.sceneCaptureState == .active else { return }
            controller.finish()
        }
    }

    private func prepareAndPlay() async {
        do {
            guard admitsOpening else { return finish() }
            let latest = try await backend.message(message.chatId, message.id)
            // An expired or edited note is no longer the one the user tapped.
            guard admitsOpening, isSameNote(latest), case .messageVoiceNote(let value) = latest.content else {
                return finish()
            }
            var file = value.voiceNote.voice
            if !file.local.isDownloadingCompleted {
                file = try await backend.download(file.id, true)
            }
            guard admitsOpening, file.id == voiceNote.voice.id, file.local.isDownloadingCompleted,
                  !file.local.path.isEmpty
            else { return finish(failed: true) }
            let outputURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("voice-once-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            privateFileURL = outputURL
            try await FFmpegAudioDecoder.decodeToWAV(
                sourceURL: URL(fileURLWithPath: file.local.path),
                outputURL: outputURL,
                maximumOutputBytes: Self.decodedSizeLimit(duration: voiceNote.duration),
            )
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: outputURL.path,
            )
            guard admitsOpening else { return finish() }
            let checked = try await backend.message(message.chatId, message.id)
            guard admitsOpening, isSameNote(checked) else { return finish() }
            // Telegram consumes a play-once note when its playback starts; the sender's own note is not consumed.
            if !message.isOutgoing {
                let openedAt = backend.now()
                try await backend.open(message.chatId, message.id)
                guard admitsPlayback else { return finish() }
                if case .messageSelfDestructTypeTimer = message.selfDestructType,
                   let opened = try? await backend.message(message.chatId, message.id),
                   opened.selfDestructIn.isFinite, opened.selfDestructIn > 0
                {
                    scheduleDeadline(after: openedAt + opened.selfDestructIn - backend.now())
                }
            }
            guard admitsPlayback else { return finish() }
            VideoNotePlaybackView.pauseActivePlayback()
            Media.shared.beginExclusivePlayback()
            player.load(url: outputURL, autoplay: true)
            playButton.isEnabled = true
        } catch is CancellationError {
            finish()
        } catch {
            finish(failed: true)
        }
    }

    private func isSameNote(_ latest: Message) -> Bool {
        guard case .messageVoiceNote(let value) = latest.content else { return false }
        return latest.chatId == message.chatId && latest.id == message.id && latest.editDate == message.editDate
            && latest.selfDestructType == message.selfDestructType && latest.isOutgoing == message.isOutgoing
            && value.voiceNote.voice.id == voiceNote.voice.id
    }

    /// A timed note expires while it plays; TDLib then deletes it, and its copy stops with it.
    private func scheduleDeadline(after interval: TimeInterval) {
        deadlineTask?.cancel()
        let backend = backend
        deadlineTask = Task { [weak self] in
            do {
                try await backend.sleep(max(0, interval))
            } catch {
                return
            }
            self?.finish()
        }
    }

    private func render(position: TimeInterval?) {
        let isPlaying = player.isPlaybackRequested
        playButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = L10n.telegram(
            isPlaying ? "VoiceOver.Media.PlaybackPause" : "VoiceOver.Media.PlaybackPlay",
        )
        guard let position else { return }
        let duration = max(1, voiceNote.duration)
        waveformView.progress = min(1, max(0, CGFloat(position / Double(duration))))
        let remaining = max(0, duration - Int(position))
        durationLabel.text = String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    @objc private func togglePlayback() {
        guard !isFinished, admitsPlayback else { return }
        if player.isPlaybackRequested {
            player.pause()
        } else {
            player.play()
        }
        render(position: nil)
    }

    @objc private func close() {
        finish()
    }

    private func finish(failed: Bool = false) {
        guard !isFinished else { return }
        isFinished = true
        preparationTask?.cancel()
        deadlineTask?.cancel()
        player.stop()
        if let privateFileURL {
            try? FileManager.default.removeItem(at: privateFileURL)
            self.privateFileURL = nil
        }
        let presenter = presentingViewController
        dismiss(animated: true) {
            if failed { presenter?.presentChatListActionFailure() }
        }
    }
}
