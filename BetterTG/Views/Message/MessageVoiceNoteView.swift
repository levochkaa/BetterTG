// MessageVoiceNoteView.swift

import Combine
import TDLibKit
import UIKit

final class VoiceNotePlaybackView: UIView, ReusableMediaView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        Media.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.render() } }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let playButton = UIButton(type: .system)
    private let waveformView = TelegramWaveformView()
    private let durationLabel = UILabel()
    private var voiceNote: VoiceNote?
    private var localPath: String?
    private var downloadTask: Task<Void, Never>?
    private var fileCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private var isCurrentVoicePlaying: Bool {
        guard let localPath else { return false }
        return Media.shared.savedMediaPath == localPath && Media.shared.isPlaying
    }

    func configure(voiceNote: VoiceNote) {
        prepareForReuse()
        self.voiceNote = voiceNote
        waveformView.samples = Self.decodeWaveform(voiceNote.waveform)
        update(file: voiceNote.voice)
        fileCancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { $0.file.id == voiceNote.voice.id }
            .sink { [weak self] in self?.update(file: $0.file) }
        downloadTask = Task { [weak self] in
            let downloaded = try? await td.downloadFile(
                fileId: voiceNote.voice.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
            guard let self, let downloaded else { return }
            await MainActor.run { self.update(file: downloaded) }
        }
        render()
    }

    func prepareForReuse() {
        let fileID = voiceNote?.voice.id
        downloadTask?.cancel()
        downloadTask = nil
        fileCancellable?.cancel()
        fileCancellable = nil
        voiceNote = nil
        localPath = nil
        waveformView.samples = []
        waveformView.progress = 0
        if let fileID {
            Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
        }
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
            durationLabel.trailingAnchor.constraint(equalTo: waveformView.trailingAnchor),
            durationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 225),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    private func update(file: File) {
        guard voiceNote?.voice.id == file.id, file.local.isDownloadingCompleted else { return }
        localPath = file.local.path
        render()
    }

    private func render() {
        guard let voiceNote else { return }
        playButton.setImage(
            UIImage(systemName: isCurrentVoicePlaying ? "pause.fill" : "play.fill"),
            for: .normal,
        )
        let current = Media.shared.savedMediaPath == localPath ? Int(Media.shared.currentTime) : 0
        durationLabel.text = "\(format(current)) / \(format(voiceNote.duration))"
        waveformView.progress = voiceNote.duration > 0
            ? min(1, max(0, CGFloat(current) / CGFloat(voiceNote.duration)))
            : 0
        let enabled = localPath != nil
        playButton.isEnabled = enabled
        playButton.alpha = enabled ? 1 : 0.45
        waveformView.isEnabled = enabled
    }

    private func format(_ duration: Int) -> String {
        String(format: "%d:%02d", duration / 60, duration % 60)
    }

    private func seek(to progress: CGFloat) {
        guard let localPath, let voiceNote else { return }
        if Media.shared.savedMediaPath != localPath {
            Media.shared.toggle(with: localPath, duration: voiceNote.duration)
        }
        Media.shared.seek(to: TimeInterval(progress) * TimeInterval(voiceNote.duration))
    }

    @objc private func toggle() {
        guard let localPath, let voiceNote else { return }
        Media.shared.toggle(with: localPath, duration: voiceNote.duration)
    }

    private static func decodeWaveform(_ data: Data) -> [CGFloat] {
        guard !data.isEmpty else { return [] }
        let sampleCount = data.count * 8 / 5
        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (0 ..< sampleCount).map { index in
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
}

private final class TelegramWaveformView: UIControl {
    var samples = [CGFloat]() {
        didSet { setNeedsDisplay() }
    }
    var progress = CGFloat.zero {
        didSet { setNeedsDisplay() }
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
        accessibilityLabel = "Voice message waveform"
        accessibilityTraits = [.adjustable]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        let bars = resampledBars()
        draw(bars: bars, color: unplayedColor, context: context, clipWidth: bounds.width)
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height))
        draw(bars: bars, color: playedColor, context: context, clipWidth: bounds.width * progress)
        context.restoreGState()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        updateProgress(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateProgress(for: touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { updateProgress(for: touch) }
    }

    override func accessibilityIncrement() {
        applyAccessibleProgress(progress + 0.05)
    }

    override func accessibilityDecrement() {
        applyAccessibleProgress(progress - 0.05)
    }

    private func updateProgress(for touch: UITouch) {
        guard bounds.width > 0 else { return }
        let updated = min(1, max(0, touch.location(in: self).x / bounds.width))
        progress = updated
        accessibilityValue = "\(Int(updated * 100)) percent"
        onSeek?(updated)
    }

    private func applyAccessibleProgress(_ updated: CGFloat) {
        let clipped = min(1, max(0, updated))
        progress = clipped
        accessibilityValue = "\(Int(clipped * 100)) percent"
        onSeek?(clipped)
    }

    private func resampledBars() -> [CGFloat] {
        let targetCount = max(1, Int(bounds.width / 3.5))
        guard !samples.isEmpty else {
            return (0 ..< targetCount).map { index in
                0.2 + CGFloat((index * 17) % 13) / 40
            }
        }
        return (0 ..< targetCount).map { targetIndex in
            let lower = targetIndex * samples.count / targetCount
            let upper = max(lower + 1, (targetIndex + 1) * samples.count / targetCount)
            return samples[lower ..< min(upper, samples.count)].max() ?? 0
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
