// ForumTopicRunHeaderCell.swift

import TDLibKit
import UIKit

// MARK: - ForumTopicRunHeaderCell

final class ForumTopicRunHeaderCell: UICollectionViewCell {
    static let reuseIdentifier = "ForumTopicRunHeaderCell"

    private let control = UIControl()
    private let pillView = UIView()
    private let iconView = ForumTopicRunIconView()
    private let titleLabel = UILabel()
    private let arrowView = UIImageView(image: UIImage(systemName: "chevron.right"))
    private var onOpen: (() -> Void)?
    private var iconSignature: [String]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetUnavailableContent()
    }

    func resetUnavailableContent() {
        iconView.prepareForReuse()
        iconSignature = nil
        onOpen = nil
        titleLabel.text = nil
        control.isAccessibilityElement = false
        control.accessibilityLabel = nil
        control.accessibilityValue = nil
        control.accessibilityHint = nil
        control.accessibilityIdentifier = nil
    }

    func configure(
        id: ForumTopicRunHeaderID,
        info: ForumTopicInfo?,
        client: TDLibClient,
        onOpen: @escaping () -> Void,
    ) {
        contentView.isHidden = false
        accessibilityElementsHidden = false
        isUserInteractionEnabled = true
        self.onOpen = onOpen
        let title = info?.name ?? (id.topicID == 1
            ? L10n.betterTG("Forum.GeneralTopic")
            : L10n.betterTG("Forum.TopicFallback"))
        titleLabel.text = title
        let nextIconSignature = [
            String(id.topicID),
            title,
            String(describing: info?.icon.color),
            String(describing: info?.icon.customEmojiId),
            String(info?.isGeneral == true),
        ]
        if iconSignature != nextIconSignature {
            iconSignature = nextIconSignature
            iconView.configure(topicID: id.topicID, info: info, client: client)
        }
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityIdentifier = "forum-topic-run-\(id.topicID)-\(id.runStartMessageID)"
        control.accessibilityLabel = L10n.betterTG("Accessibility.TopicNamed", title)
        control.accessibilityValue = info?.isClosed == true ? L10n.betterTG("Forum.Closed") : nil
        control.accessibilityHint = L10n.betterTG("Accessibility.OpenTopicHint")
    }

    private func configureViews() {
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addTarget(self, action: #selector(openPressed), for: .touchUpInside)
        contentView.addSubview(control)

        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.isUserInteractionEnabled = false
        pillView.backgroundColor = .secondarySystemBackground
        pillView.layer.cornerRadius = 11
        pillView.layer.cornerCurve = .continuous
        control.addSubview(pillView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        pillView.addSubview(titleLabel)

        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.tintColor = .tertiaryLabel
        arrowView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        arrowView.contentMode = .scaleAspectFit
        pillView.addSubview(arrowView)

        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            control.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            control.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            control.heightAnchor.constraint(equalToConstant: 22),
            control.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -32),
            pillView.topAnchor.constraint(equalTo: control.topAnchor),
            pillView.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            pillView.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            pillView.bottomAnchor.constraint(equalTo: control.bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: arrowView.leadingAnchor, constant: -6),
            arrowView.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -6),
            arrowView.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            arrowView.widthAnchor.constraint(equalToConstant: 7),
            arrowView.heightAnchor.constraint(equalToConstant: 11),
        ])
    }

    @objc private func openPressed() {
        onOpen?()
    }
}

// MARK: - ForumTopicRunIconView

private final class ForumTopicRunIconView: UIView {
    private let backgroundView = UIView()
    private let label = UILabel()
    private let imageView = UIImageView()
    private var customEmojiView: CustomEmojiInlineView?
    private var loadTask: Task<Void, Never>?
    private var generation = UInt64.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = 8
        addSubview(backgroundView)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 8, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .center
        addSubview(imageView)
        for view in [backgroundView, label, imageView] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        customEmojiView?.setPlaybackVisible(window != nil)
    }

    func configure(topicID: Int, info: ForumTopicInfo?, client: TDLibClient) {
        prepareForReuse()
        backgroundView.backgroundColor = UIColor(rgb: info?.icon.color ?? 0x4A9EF1)
        if info?.isGeneral == true || topicID == 1 {
            imageView.image = UIImage(
                systemName: "bubble.left.and.bubble.right.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .semibold),
            )
            imageView.isHidden = false
            label.isHidden = true
        } else {
            label.text = info?.name.first.map { String($0).uppercased() } ?? "#"
        }
        guard let customEmojiID = info?.icon.customEmojiId,
              customEmojiID != 0
        else { return }
        let currentGeneration = generation
        loadTask = Task { [weak self] in
            let sticker = await CustomEmojiStickerRepository.shared.stickers(
                for: [customEmojiID],
                client: client,
            )[customEmojiID]
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.generation == currentGeneration,
                      let sticker
                else { return }
                self.install(sticker, client: client)
            }
        }
    }

    func prepareForReuse() {
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        customEmojiView?.prepareForReuse()
        customEmojiView?.removeFromSuperview()
        customEmojiView = nil
        backgroundView.isHidden = false
        label.isHidden = false
        label.text = nil
        imageView.isHidden = true
        imageView.image = nil
    }

    private func install(_ sticker: Sticker, client: TDLibClient) {
        let view = CustomEmojiInlineView()
        // ChatListItem: topic icons stop animating with Emoji Animations off.
        view.energySaving = EnergySavingRole(item: .loopEmoji, whenOff: .still)
        customEmojiView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        view.configure(sticker: sticker, client: client)
        view.onFirstFrameReady = { [weak self, weak view] in
            guard let self, customEmojiView === view else { return }
            backgroundView.isHidden = true
            label.isHidden = true
            imageView.isHidden = true
        }
        view.setPlaybackVisible(window != nil)
    }
}
