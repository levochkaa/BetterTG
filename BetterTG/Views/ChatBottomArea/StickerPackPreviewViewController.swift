// StickerPackPreviewViewController.swift

import TDLibKit
import UIKit

// MARK: - StickerPackPreviewViewController

/// Telegram's StickerPackScreen for one pack: its stickers, a tap that sends one where the chat takes stickers, Copy
/// Link, and Add or Remove N Stickers (changeStickerSet) with Telegram's toast.
@MainActor final class StickerPackPreviewViewController: UIViewController, UICollectionViewDataSource,
UICollectionViewDelegate {
    /// Sends a sticker; nil when the chat can't take one.
    var onSend: ((Sticker) -> Void)?

    private let setID: Int64
    private let client: TDLibClient
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let actionButton = UIButton(configuration: .filled())
    private let moreButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var stickerSet: TDNativeStickerSet?
    private var stickers = [Sticker]()
    private var loadTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?

    private var contextIsCurrent: Bool {
        TDLib.shared.activeClient.id == client.id
    }

    init(setID: Int64, client: TDLibClient) {
        self.setID = setID
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        changeTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Close"), style: .plain, target: self, action: #selector(closePressed),
        )
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.isEnabled = false
        moreButton.addTarget(self, action: #selector(morePressed), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: moreButton)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            ComposerStickerCell.self,
            forCellWithReuseIdentifier: ComposerStickerCell.reuseIdentifier,
        )
        view.addSubview(collectionView)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.configuration?.cornerStyle = .large
        actionButton.configuration?.buttonSize = .large
        actionButton.isHidden = true
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        view.addSubview(actionButton)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -8),
            actionButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        load()
    }

    /// Presents the pack in a sheet from `host`.
    static func present(
        setID: Int64,
        client: TDLibClient,
        from host: UIViewController,
        onSend: ((Sticker) -> Void)?,
    ) {
        let preview = StickerPackPreviewViewController(setID: setID, client: client)
        preview.onSend = onSend
        let navigation = UINavigationController(rootViewController: preview)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        host.present(navigation, animated: true)
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        stickers.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ComposerStickerCell.reuseIdentifier,
            for: indexPath,
        )
        (cell as? ComposerStickerCell)?.configure(sticker: stickers[indexPath.item], client: client)
        return cell
    }

    func collectionView(_: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(true)
    }

    func collectionView(_: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ComposerStickerCell)?.setPlaybackVisible(false)
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let onSend, contextIsCurrent, stickers.indices.contains(indexPath.item) else { return }
        let sticker = stickers[indexPath.item]
        // BetterTG sends no Premium stickers.
        if case .stickerFullTypeRegular(let regular) = sticker.fullType, regular.premiumAnimation != nil { return }
        dismiss(animated: true) { onSend(sticker) }
    }

    private func makeLayout() -> UICollectionViewLayout {
        let columns = 5
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / CGFloat(columns)),
            heightDimension: .fractionalHeight(1),
        ))
        item.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalWidth(1 / CGFloat(columns)),
            ),
            repeatingSubitem: item,
            count: columns,
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func load() {
        activityIndicator.startAnimating()
        let client = client
        let setID = setID
        loadTask = Task { [weak self] in
            let set = try? await client.send(TDNativeRequests.getStickerSet(setId: setID))
            guard let self, !Task.isCancelled else { return }
            activityIndicator.stopAnimating()
            guard let set, contextIsCurrent else {
                title = L10n.telegram("Login.UnknownError")
                return
            }
            stickerSet = set
            stickers = set.stickers
            title = set.title
            moreButton.isEnabled = !set.name.isEmpty
            collectionView.reloadData()
            updateActionButton()
        }
    }

    private func updateActionButton() {
        guard let stickerSet else { return }
        let installed = stickerSet.isInstalled && !stickerSet.isArchived
        actionButton.isHidden = false
        actionButton.configuration?.title = L10n.telegramPlural(
            installed ? "StickerPack.RemoveStickerCount" : "StickerPack.AddStickerCount",
            count: stickers.count,
        )
        actionButton.configuration?.baseBackgroundColor = installed ? .systemRed : .tintColor
        actionButton.isEnabled = changeTask == nil
    }

    @objc private func closePressed() {
        dismiss(animated: true)
    }

    @objc private func morePressed() {
        guard let name = stickerSet?.name, !name.isEmpty else { return }
        presentTelegramContextMenu(sourceView: moreButton, actions: [
            TelegramContextMenuAction(
                title: L10n.telegram("StickerPack.CopyLink"),
                image: UIImage(systemName: "link"),
            ) { [weak self] in
                UIPasteboard.setPlainText("https://t.me/addstickers/\(name)")
                guard let self else { return }
                TelegramUndoToast.show(
                    text: L10n.telegram("Conversation.LinkCopied"),
                    in: view,
                    bottomInset: 80,
                    undo: nil,
                )
            },
        ], presentationStyle: .menuOnly)
    }

    /// Telegram's Add or Remove button, then the sheet closes with "Stickers Added" or "Stickers Removed".
    @objc private func actionPressed() {
        guard changeTask == nil, let stickerSet, contextIsCurrent else { return }
        let install = !(stickerSet.isInstalled && !stickerSet.isArchived)
        let client = client
        let setID = setID
        let title = stickerSet.title
        changeTask = Task { [weak self] in
            let succeeded: Bool
            do {
                _ = try await client.send(TDNativeRequests.changeStickerSet(
                    setId: setID, isInstalled: install, isArchived: false,
                ))
                succeeded = true
            } catch {
                succeeded = false
            }
            guard let self, !Task.isCancelled else { return }
            changeTask = nil
            guard succeeded, contextIsCurrent else {
                updateActionButton()
                presentChatListActionFailure()
                return
            }
            let toast = L10n.telegram(
                install ? "StickerPackActionInfo.AddedText" : "StickerPackActionInfo.RemovedText",
                title,
            )
            .withoutTelegramMarkup
            let presenter = navigationController?.presentingViewController
            dismiss(animated: true) {
                guard let view = presenter?.view else { return }
                TelegramUndoToast.show(text: toast, in: view, bottomInset: 12, undo: nil)
            }
        }
        updateActionButton()
    }
}
