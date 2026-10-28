// InstantViewController.swift

import TDLibKit
import UIKit

// MARK: - InstantViewController

/// Telegram's Instant View (InstantPageController): the article TDLib's getWebPageInstantView gives for a link,
/// laid out from its page blocks at the screen's width with Telegram's 17 pt side insets, the views count at the
/// end, and Share in the bar. A page TDLib can't give opens in the chosen browser instead. The blocks draw with the
/// rich message renderer rather than Telegram's InstantPageLayout, without its font settings or search.
final class InstantViewController: UIViewController {
    private static let sideInset: CGFloat = 17

    private let url: String
    private let siteName: String
    private let client: TDLibClient
    private let scrollView = UIScrollView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var page: TDNativeWebPageInstantView?
    private var contentView: MessageRichContentView?
    private var footerLabel: UILabel?
    private var laidOutWidth: CGFloat = 0
    private var loadTask: Task<Void, Never>?

    init(url: String, siteName: String, client: TDLibClient) {
        self.url = url
        self.siteName = siteName
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = siteName.isEmpty ? URL(string: url)?.host : siteName
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(share),
        )
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if page != nil, abs(view.bounds.width - laidOutWidth) > 0.5 { render() }
    }

    /// The page as TDLib has it, the full one when the cached copy is partial.
    private func load() {
        let client = client
        let url = url
        loadTask = Task { [weak self] in
            let page = try? await client.send(TDNativeRequests.getWebPageInstantView(url: url, onlyLocal: false))
            guard !Task.isCancelled, let self else { return }
            spinner.stopAnimating()
            guard let page, !page.blocks.isEmpty else {
                // No Instant View after all: the link opens as any other.
                if let link = URL(string: url) { WebBrowser.open(link, from: self) }
                navigationController?.popViewController(animated: true)
                return
            }
            self.page = page
            render()
        }
    }

    private func render() {
        guard let page else { return }
        laidOutWidth = view.bounds.width
        contentView?.prepareForReuse()
        contentView?.removeFromSuperview()
        footerLabel?.removeFromSuperview()
        let content = MessageRichContentView(
            content: TDNativeRichMessage(blocks: page.blocks, isRtl: page.isRtl, isFull: true),
            messageID: 0,
            chatID: 0,
            client: client,
            state: MessageRichContentState(),
            contentWidth: max(1, view.bounds.width - Self.sideInset * 2),
        ) { [weak self] action in
            self?.perform(action)
        }
        // InstantPageArticleNode: a related article opens in its own Instant View.
        content.onOpenArticle = { [weak self] url in
            guard let self else { return }
            navigationController?.pushViewController(
                InstantViewController(url: url, siteName: siteName, client: client),
                animated: true,
            )
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        contentView = content
        let footer = UILabel()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.font = .systemFont(ofSize: 13)
        footer.textColor = .secondaryLabel
        footer.textAlignment = .center
        footer.text = page.viewCount > 0
            ? L10n.telegramPlural("InstantPage.Views", count: page.viewCount)
            : nil
        scrollView.addSubview(footer)
        footerLabel = footer
        // InstantPageLayout: 25 pt before the first block and after the last.
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 25),
            content.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: Self.sideInset,
            ),
            footer.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 25),
            footer.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                constant: Self.sideInset,
            ),
            footer.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                constant: -Self.sideInset,
            ),
            footer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -25),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        content.setPlaybackVisible(true)
    }

    private func perform(_ action: MessageContentAction) {
        switch action {
        case .openDocument(let url):
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = view
            present(activity, animated: true)
        case .openLocation(let location, _):
            if let maps = URL(string: "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)") {
                UIApplication.shared.open(maps)
            }
        default:
            break
        }
    }

    @objc private func share() {
        guard let link = URL(string: url) else { return }
        let activity = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        presentGrowing(activity, from: navigationItem.rightBarButtonItem?.telegramChromeView)
    }
}
