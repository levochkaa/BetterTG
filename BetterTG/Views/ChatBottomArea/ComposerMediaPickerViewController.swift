// ComposerMediaPickerViewController.swift

import TDLibKit
import UIKit

// MARK: - ComposerMediaPickerViewController

@MainActor final class ComposerMediaPickerViewController: UIViewController, UICollectionViewDelegate,
UISearchBarDelegate {
    enum Mode: Int {
        case emoji
        case customEmoji
        case stickers
        case gifs
    }

    private enum Section {
        case content
    }

    private enum ItemID: Hashable {
        case animation(Int)
        case emoji(String)
        case sticker(Int)
    }

    private static let emojis =
        "😀 😃 😄 😁 😆 😅 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😋 😜 🤪 🤨 🧐 🤓 😎 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 🤗 🤔 🫡 🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😮 😲 🥱 😴 🤤 😪 😵 🤐 🤢 🤮 🤧 😷 🤒 🤕 👍 👎 👏 🙌 🫶 ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 💯 🔥 🎉 ✨ 🚀"
            .split(separator: " ")
            .map(String.init)

    var onAnimation: ((Animation) -> Void)?
    var onDismiss: (() -> Void)?
    var onEmoji: ((String) -> Void)?
    var onCustomEmoji: ((Sticker) -> Void)?
    var onSticker: ((Sticker) -> Void)?

    private let accountID: UUID
    private let chatID: Int64
    private let client: TDLibClient
    private let segmentedControl = UISegmentedControl(items: [
        "Emoji",
        L10n.betterTG("CustomEmoji.Tab"),
        "Stickers",
        "GIFs",
    ])
    private let searchBar = UISearchBar()
    private var searchBarHeightConstraint: NSLayoutConstraint!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, ItemID>!
    private var animations = [Int: Animation]()
    private var savedAnimations = [Animation]()
    private var stickers = [Int: Sticker]()
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var canUseCustomEmoji = false

    private var mode: Mode {
        Mode(rawValue: segmentedControl.selectedSegmentIndex) ?? .emoji
    }

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(accountID: UUID, chatID: Int64, client: TDLibClient) {
        self.accountID = accountID
        self.chatID = chatID
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Emoji and Stickers"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .plain,
            target: self,
            action: #selector(donePressed),
        )
        configureViews()
        configureDataSource()
        segmentedControl.selectedSegmentIndex = Mode.emoji.rawValue
        searchBar.isHidden = true
        searchBarHeightConstraint.constant = 0
        applyEmojiSnapshot()
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard contextIsCurrent,
              let item = dataSource.itemIdentifier(for: indexPath)
        else {
            dismissPicker()
            return
        }
        switch item {
        case .emoji(let emoji):
            onEmoji?(emoji)
        case .sticker(let id):
            guard let sticker = stickers[id] else { return }
            if case .stickerFullTypeCustomEmoji = sticker.fullType {
                guard canUseCustomEmoji else {
                    let alert = UIAlertController(
                        title: nil,
                        message: L10n.betterTG("CustomEmoji.PremiumRequired"),
                        preferredStyle: .alert,
                    )
                    alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .cancel))
                    present(alert, animated: true)
                    return
                }
                onCustomEmoji?(sticker)
            } else { onSticker?(sticker) }
        case .animation(let id):
            guard let animation = animations[id] else { return }
            onAnimation?(animation)
        }
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(true)
        (cell as? ComposerAnimationCell)?.restartLoading()
    }

    func collectionView(_: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(false)
        (cell as? ComposerAnimationCell)?.cancelLoading()
    }

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        loadTask?.cancel()
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await reload(query: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func configureViews() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addSubview(segmentedControl)

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "Search stickers"
        searchBar.searchBarStyle = .minimal
        view.addSubview(searchBar)
        searchBarHeightConstraint = searchBar.heightAnchor.constraint(equalToConstant: 44)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(ComposerEmojiCell.self, forCellWithReuseIdentifier: ComposerEmojiCell.reuseIdentifier)
        collectionView.register(
            ComposerStickerCell.self,
            forCellWithReuseIdentifier: ComposerStickerCell.reuseIdentifier,
        )
        collectionView.register(
            ComposerAnimationCell.self,
            forCellWithReuseIdentifier: ComposerAnimationCell.reuseIdentifier,
        )
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            searchBarHeightConstraint,
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            collectionView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] _, _ in
            let columns = self?.mode == .emoji || self?.mode == .customEmoji ? 8 : 4
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                heightDimension: .fractionalHeight(1),
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalWidth(1 / CGFloat(columns)),
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns,
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 20, trailing: 8)
            return section
        }
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, ItemID>(
            collectionView: collectionView,
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            switch item {
            case .emoji(let emoji):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ComposerEmojiCell.reuseIdentifier,
                    for: indexPath,
                ) as? ComposerEmojiCell
                cell?.configure(emoji: emoji)
                return cell ?? UICollectionViewCell()
            case .sticker(let id):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ComposerStickerCell.reuseIdentifier,
                    for: indexPath,
                ) as? ComposerStickerCell
                if let sticker = stickers[id] {
                    cell?.configure(sticker: sticker, client: client)
                }
                return cell ?? UICollectionViewCell()
            case .animation(let id):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ComposerAnimationCell.reuseIdentifier,
                    for: indexPath,
                ) as? ComposerAnimationCell
                if let animation = animations[id] {
                    cell?.configure(animation: animation, client: client)
                }
                return cell ?? UICollectionViewCell()
            }
        }
    }

    @objc private func modeChanged() {
        loadTask?.cancel()
        searchTask?.cancel()
        searchBar.text = ""
        searchBar.placeholder = mode == .gifs ? "Filter saved GIFs" : "Search stickers"
        if mode == .customEmoji { searchBar.placeholder = L10n.betterTG("CustomEmoji.Search") }
        searchBar.isHidden = mode == .emoji
        searchBarHeightConstraint.constant = mode == .emoji ? 0 : 44
        collectionView.collectionViewLayout.invalidateLayout()
        switch mode {
        case .emoji:
            applyEmojiSnapshot()
        case .customEmoji, .gifs, .stickers:
            loadTask = Task { [weak self] in await self?.reload(query: "") }
        }
    }

    private func reload(query: String) async {
        guard contextIsCurrent else { return }
        switch mode {
        case .emoji:
            applyEmojiSnapshot()
        case .customEmoji:
            let selectedMode = mode
            async let request = client.getStickers(
                chatId: chatID,
                limit: 200,
                query: query,
                stickerType: .stickerTypeCustomEmoji,
            )
            async let userRequest = client.getMe()
            let result = try? await request
            let user = try? await userRequest
            guard !Task.isCancelled, contextIsCurrent, mode == selectedMode else { return }
            canUseCustomEmoji = user?.isPremium == true || user?.id == chatID
            let values = (result?.stickers ?? [])
                .filter {
                    if case .stickerFullTypeCustomEmoji = $0.fullType {
                        true
                    } else {
                        false
                    }
                }
            stickers.merge(Dictionary(
                values.map { ($0.sticker.id, $0) },
                uniquingKeysWith: { _, latest in latest },
            )) { _, latest in latest }
            applySnapshot(values.map { .sticker($0.sticker.id) }.uniqued())
        case .stickers:
            let result = try? await client.getStickers(
                chatId: chatID,
                limit: 100,
                query: query,
                stickerType: .stickerTypeRegular,
            )
            guard !Task.isCancelled, contextIsCurrent else { return }
            let values = (result?.stickers ?? []).filter {
                if case .stickerFullTypeRegular(let regular) = $0.fullType {
                    regular.premiumAnimation == nil
                } else {
                    false
                }
            }
            stickers = Dictionary(uniqueKeysWithValues: values.map { ($0.sticker.id, $0) })
            applySnapshot(values.map { .sticker($0.sticker.id) })
        case .gifs:
            if savedAnimations.isEmpty {
                savedAnimations = await (try? client.getSavedAnimations().animations) ?? []
            }
            guard !Task.isCancelled, contextIsCurrent else { return }
            let values = query.isEmpty
                ? savedAnimations
                : savedAnimations.filter { $0.fileName.localizedCaseInsensitiveContains(query) }
            animations = Dictionary(uniqueKeysWithValues: values.map { ($0.animation.id, $0) })
            applySnapshot(values.map { .animation($0.animation.id) })
        }
    }

    private func applyEmojiSnapshot() {
        applySnapshot(Self.emojis.map(ItemID.emoji))
    }

    private func applySnapshot(_ items: [ItemID]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ItemID>()
        snapshot.appendSections([.content])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
        collectionView.backgroundView = items.isEmpty ? emptyLabel() : nil
    }

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = mode == .gifs ? "No saved GIFs" : "No stickers found"
        if mode == .customEmoji { label.text = L10n.betterTG("CustomEmoji.Empty") }
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }

    @objc private func donePressed() {
        dismissPicker()
    }

    private func dismissPicker() {
        dismiss(animated: true, completion: onDismiss)
    }
}

// MARK: - ComposerEmojiCell

private final class ComposerEmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "ComposerEmojiCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func configure(emoji: String) {
        label.text = emoji
        isAccessibilityElement = true
        accessibilityLabel = emoji
        accessibilityTraits = .button
    }
}

// MARK: - ComposerStickerCell

private final class ComposerStickerCell: UICollectionViewCell {
    static let reuseIdentifier = "ComposerStickerCell"

    private let stickerView = CustomEmojiInlineView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stickerView.translatesAutoresizingMaskIntoConstraints = false
        stickerView.isUserInteractionEnabled = false
        contentView.addSubview(stickerView)
        NSLayoutConstraint.activate([
            stickerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            stickerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 3),
            stickerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
            stickerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        stickerView.prepareForReuse()
    }

    func configure(sticker: Sticker, client: TDLibClient) {
        stickerView.configure(sticker: sticker, client: client)
        isAccessibilityElement = true
        accessibilityLabel = sticker.emoji.isEmpty ? "Sticker" : "Sticker \(sticker.emoji)"
        accessibilityTraits = .button
    }

    func setPlaybackVisible(_ visible: Bool) {
        stickerView.setPlaybackVisible(visible)
    }
}

// MARK: - ComposerAnimationCell

private final class ComposerAnimationCell: UICollectionViewCell {
    static let reuseIdentifier = "ComposerAnimationCell"

    private let imageView = TDImageLoadingView()
    private var imageOrigin: TDImageOrigin?
    private let badge = UILabel()
    private var animation: Animation?
    private var loadingCancelled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .tertiarySystemFill
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = "GIF"
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 5
        badge.clipsToBounds = true
        contentView.addSubview(badge)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            badge.widthAnchor.constraint(equalToConstant: 30),
            badge.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
        imageView.image = nil
        animation = nil
        imageOrigin = nil
        loadingCancelled = false
    }

    func configure(animation: Animation, client: TDLibClient) {
        imageOrigin = .captured(client: client)
        self.animation = animation
        loadingCancelled = false
        loadAnimation(animation)
        isAccessibilityElement = true
        accessibilityLabel = animation.fileName.isEmpty ? "GIF" : "GIF \(animation.fileName)"
        accessibilityTraits = .button
    }

    func restartLoading() {
        guard loadingCancelled, let animation else { return }
        loadingCancelled = false
        loadAnimation(animation)
    }

    func cancelLoading() {
        loadingCancelled = true
        imageView.cancel()
    }

    private func loadAnimation(_ animation: Animation) {
        if let thumbnail = animation.thumbnail {
            imageView.load(
                file: thumbnail.file,
                placeholderData: animation.minithumbnail?.data,
                maximumPixelSize: 320,
                origin: imageOrigin,
            )
        } else {
            imageView.loadPlaceholder(data: animation.minithumbnail?.data, origin: imageOrigin)
        }
    }
}
