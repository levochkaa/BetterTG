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

    private let backwardButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
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
        if let fileID {
            Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
        }
    }

    private func configureViews() {
        let controls = UIStackView(arrangedSubviews: [backwardButton, playButton, forwardButton])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 12
        backwardButton.setImage(UIImage(systemName: "gobackward.5"), for: .normal)
        playButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        playButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 34), forImageIn: .normal)
        forwardButton.setImage(UIImage(systemName: "goforward.5"), for: .normal)
        backwardButton.addTarget(self, action: #selector(seekBackward), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(seekForward), for: .touchUpInside)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .preferredFont(forTextStyle: .caption1)
        durationLabel.textColor = .secondaryLabel
        durationLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [controls, durationLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
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
            UIImage(systemName: isCurrentVoicePlaying ? "pause.circle.fill" : "play.circle.fill"),
            for: .normal,
        )
        let current = Media.shared.savedMediaPath == localPath ? Int(Media.shared.currentTime) : 0
        durationLabel.text = "\(format(current)) / \(format(voiceNote.duration))"
        let enabled = localPath != nil
        playButton.isEnabled = enabled
        backwardButton.isEnabled = isCurrentVoicePlaying
        forwardButton.isEnabled = isCurrentVoicePlaying
    }

    private func format(_ duration: Int) -> String {
        String(format: "%d:%02d", duration / 60, duration % 60)
    }

    @objc private func toggle() {
        guard let localPath, let voiceNote else { return }
        Media.shared.toggle(with: localPath, duration: voiceNote.duration)
    }

    @objc private func seekBackward() {
        Media.shared.seekBackward()
    }

    @objc private func seekForward() {
        Media.shared.seekForward()
    }
}
