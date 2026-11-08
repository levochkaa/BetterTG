// ProfileMusicStripView.swift

import TDLibKit
import UIKit

// MARK: - ProfileMusicStripView

/// PeerInfoHeaderNode's music strip under the profile's buttons: a note, the track's title in semibold 12 accent, its
/// performer in regular 12 secondary, and an arrow; a tap opens the profile's playlist (displaySavedMusic).
final class ProfileMusicStripView: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }

    private let iconView = UIImageView()
    private let label = UILabel()
    private let arrowView = UIImageView()

    private var audio: Audio?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let symbol = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        iconView.image = UIImage(systemName: "music.note", withConfiguration: symbol)
        iconView.tintColor = tintColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        arrowView.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold),
        )
        arrowView.tintColor = .secondaryLabel
        arrowView.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [iconView, label, arrowView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        iconView.tintColor = tintColor
        if let audio { configure(audio) }
    }

    /// The track's title, its file name without one, else Unknown Track; Unknown Artist without a performer.
    func configure(_ audio: Audio) {
        self.audio = audio
        let title = audio.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let performer = audio.performer.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = audio.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = !title.isEmpty ? title : !fileName.isEmpty ? fileName : L10n.telegram("MediaPlayer.UnknownTrack")
        let artist = performer.isEmpty ? L10n.telegram("MediaPlayer.UnknownArtist") : performer
        let text = NSMutableAttributedString(string: track, attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: tintColor ?? .systemBlue,
        ])
        text.append(NSAttributedString(string: " \(artist)", attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel,
        ]))
        // The node's 2 pt kern on the space before the performer.
        text.addAttribute(.kern, value: 2, range: NSRange(location: (track as NSString).length, length: 1))
        label.attributedText = text
        accessibilityLabel = "\(track), \(artist)"
    }
}
