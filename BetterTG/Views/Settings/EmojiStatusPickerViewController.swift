// EmojiStatusPickerViewController.swift

import TDLibKit
import UIKit

// MARK: - EmojiStatusPickerViewController

/// Telegram's EmojiStatusSelectionController from Settings: the Premium star, which clears the status, then the recent
/// statuses and TDLib's default and themed ones in a grid. A tap sets the status; a long press sets it until a time
/// (EmojiStatusPreviewScreen's 1 hour, 2 hours, 8 hours or 2 days).
final class EmojiStatusPickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private enum Item: Hashable {
        case clear
        case emoji(Int64)
    }

    /// EmojiStatusPreviewScreen's delayDurations.
    private static let durations = [1 * 60 * 60, 2 * 60 * 60, 8 * 60 * 60, 2 * 24 * 60 * 60]

    private let client: TDLibClient
    private let currentEmojiID: Int64?
    /// A status of another kind, such as a gift's, leaves the star unmarked too.
    private let hasStatus: Bool
    private var items: [Item] = [.clear]
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    init(client: TDLibClient, currentEmojiID: Int64?, hasStatus: Bool) {
        self.client = client
        self.currentEmojiID = currentEmojiID
        self.hasStatus = hasStatus
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.medium(), .large()]
        sheetPresentationController?.prefersGrabberVisible = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EmojiStatusCell.self, forCellWithReuseIdentifier: EmojiStatusCell.reuseIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: 24, left: 0, bottom: 16, right: 0)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self,
            action: #selector(longPressed(_:)),
        ))
        load()
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EmojiStatusCell.reuseIdentifier,
            for: indexPath,
        )
        guard let statusCell = cell as? EmojiStatusCell else { return cell }
        switch items[indexPath.item] {
        case .clear:
            statusCell.configure(.premium, isSelected: !hasStatus, client: client)
        case .emoji(let id):
            statusCell.configure(.emoji(id), isSelected: currentEmojiID == id, client: client)
        }
        return statusCell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        choose(items[indexPath.item], until: 0)
    }

    private func makeLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / 8),
            heightDimension: .fractionalWidth(1 / 8),
        ))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalWidth(1 / 8),
            ),
            repeatingSubitem: item,
            count: 8,
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        return UICollectionViewCompositionalLayout(section: section)
    }

    /// The recent statuses first, then the default and themed ones, each once.
    private func load() {
        let client = client
        Task { [weak self] in
            let recent = await (try? client.send(TDNativeRequests.getRecentEmojiStatuses()))?.emojiStatuses ?? []
            let defaults = await (try? client.send(TDNativeRequests.getDefaultEmojiStatuses()))?.customEmojiIds ?? []
            let themed = await (try? client.send(TDNativeRequests.getThemedEmojiStatuses()))?.customEmojiIds ?? []
            var ids = [Int64]()
            for status in recent {
                if case .emojiStatusTypeCustomEmoji(let custom) = status.type { ids.append(custom.customEmojiId) }
            }
            ids += defaults + themed
            var seen = Set<Int64>()
            let unique = ids.filter { seen.insert($0).inserted }
            guard let self else { return }
            items = [.clear] + unique.map(Item.emoji)
            collectionView.reloadData()
        }
    }

    /// EmojiStatusPreviewScreen: Set Until, then the durations.
    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
              case .emoji = items[indexPath.item],
              let cell = collectionView.cellForItem(at: indexPath)
        else { return }
        let item = items[indexPath.item]
        var actions = [TelegramContextMenuAction(title: L10n.telegram("EmojiStatusSetup.SetUntil"), image: nil)]
        actions[0].isSectionTitle = true
        for duration in Self.durations {
            let title =
                if duration < 24 * 60 * 60 {
                    L10n.telegramPlural("SetTimeoutFor.Hours", count: duration / 3600)
                } else {
                    L10n.telegramPlural("SetTimeoutFor.Days", count: duration / 86400)
                }
            actions.append(TelegramContextMenuAction(title: title, image: nil) { [weak self] in
                self?.choose(item, until: Int(Date().timeIntervalSince1970) + duration)
            })
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, tracking: gesture, presentationStyle: .menuOnly)
    }

    /// setEmojiStatus: the emoji, until a time or for good, or none for the star.
    private func choose(_ item: Item, until expirationDate: Int) {
        let status: TDNativeEmojiStatus? =
            switch item {
            case .clear: nil
            case .emoji(let id): TDNativeEmojiStatus(
                    type: .emojiStatusTypeCustomEmoji(TDNativeEmojiStatusTypeCustomEmoji(customEmojiId: id)),
                    expirationDate: expirationDate,
                )
            }
        let client = client
        Task { _ = try? await client.send(TDNativeRequests.setEmojiStatus(emojiStatus: status)) }
        dismiss(animated: true)
    }
}

// MARK: - EmojiStatusCell

private final class EmojiStatusCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiStatusCell"

    private let statusView = PeerEmojiStatusView(side: 30, loopLimit: 1)
    private let selectionView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.backgroundColor = .tintColor.withAlphaComponent(0.15)
        selectionView.layer.cornerRadius = 10
        selectionView.layer.cornerCurve = .continuous
        contentView.addSubview(selectionView)
        statusView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusView)
        NSLayoutConstraint.activate([
            selectionView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            selectionView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionView.widthAnchor.constraint(equalToConstant: 40),
            selectionView.heightAnchor.constraint(equalToConstant: 40),
            statusView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusView.widthAnchor.constraint(equalToConstant: statusView.side),
            statusView.heightAnchor.constraint(equalToConstant: statusView.side),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ status: PeerEmojiStatus, isSelected: Bool, client: TDLibClient) {
        statusView.configure(status, client: client)
        selectionView.isHidden = !isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
