// WebEmbedPlayerViewController.swift

import UIKit
import WebKit

// MARK: - WebEmbedType

/// WebEmbedPlayerNode's kinds: YouTube through Telegram's IFrame API page, which reports its state and takes
/// commands, and any other player in a plain iframe.
enum WebEmbedType: Equatable {
    case youtube(videoID: String, timestamp: Int)
    case iframe(url: String)

    var supportsSeeking: Bool {
        if case .youtube = self {
            true
        } else {
            false
        }
    }

    /// webEmbedType: a YouTube link or embed URL plays as YouTube, anything else in the iframe.
    init(url: String, embedURL: String) {
        self =
            if let (videoID, timestamp) = Self.youtubeVideo(url) ?? Self.youtubeVideo(embedURL) {
                .youtube(videoID: videoID, timestamp: timestamp)
            } else {
                .iframe(url: embedURL.isEmpty ? url : embedURL)
            }
    }

    /// extractYoutubeVideoIdAndTimestamp: `v` or the path after `embed/` or youtu.be, and `t` or `time_continue`
    /// as seconds or "1h2m3s".
    static func youtubeVideo(_ string: String) -> (String, Int)? {
        guard let url = URL(string: string), let host = url.host?.lowercased(),
              ["youtube.com", "youtu.be"].contains(where: { host == $0 || host.hasSuffix(".\($0)") }),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var videoID: String?
        var timestamp = 0
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            if item.name == "v" {
                videoID = value
            } else if item.name == "t" || item.name == "time_continue" {
                timestamp = timecode(value)
            }
        }
        if videoID == nil {
            var nextIsVideoID = host.contains("youtu.be")
            for component in components.path.components(separatedBy: "/") {
                if !component.isEmpty, nextIsVideoID {
                    videoID = component
                    break
                } else if component == "embed" {
                    nextIsVideoID = true
                }
            }
        }
        return videoID.map { ($0, timestamp) }
    }

    private static func timecode(_ value: String) -> Int {
        guard value.contains("s") else { return Int(value) ?? 0 }
        var total = 0
        var number = ""
        for character in value.lowercased() {
            if character.isNumber {
                number.append(character)
                continue
            }
            let multiplier =
                switch character {
                case "h": 3600
                case "m": 60
                case "s": 1
                default: 0
                }
            total += (Int(number) ?? 0) * multiplier
            number = ""
        }
        return total
    }
}

// MARK: - WebEmbedPlayerViewController

/// Telegram's gallery for a link's embedded player (UniversalVideoGalleryItem with WebEmbedVideoContent): the player in
/// a web view at the preview's aspect over black, the gallery's close button and title, and for YouTube Telegram's
/// own controls driven by the IFrame API page (play and pause, the scrubber with the time, seeking), its state read
/// from the page's `embed://` callbacks. Other players keep their own controls. Telegram's storyboard previews,
/// rates and Picture in Picture aren't ported; the browser button opens the link instead.
final class WebEmbedPlayerViewController: UIViewController, WKNavigationDelegate {
    override var prefersStatusBarHidden: Bool { !chromeVisible }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private let type: WebEmbedType
    private let pageURL: URL?
    private let titleText: String
    private let aspectSize: CGSize
    private let webView: WKWebView
    private let topBar = UIView()
    private let bottomBar = UIView()
    private let closeButton = UIButton(type: .system)
    private let browserButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private var webViewConstraints = [NSLayoutConstraint]()
    private var isReady = false
    private var isPlaying = false
    private var isScrubbing = false
    private var duration: Double = 0
    private var position: Double = 0
    private var chromeVisible = true

    /// The player for an embedded video, GIF or audio player link preview, from `timestamp` seconds when given;
    /// nil for any other preview.
    convenience init?(preview: LinkPreview, timestamp: Int? = nil) {
        let embed: (url: String, width: Int, height: Int)? =
            switch preview.type {
            case .linkPreviewTypeEmbeddedVideoPlayer(let value): (value.url, value.width, value.height)
            case .linkPreviewTypeEmbeddedAnimationPlayer(let value): (value.url, value.width, value.height)
            case .linkPreviewTypeEmbeddedAudioPlayer(let value): (value.url, value.width, value.height)
            default: nil
            }
        guard let embed else { return nil }
        var type = WebEmbedType(url: preview.url, embedURL: embed.url)
        // webEmbedType's forcedTimestamp.
        if let timestamp, case .youtube(let videoID, _) = type {
            type = .youtube(videoID: videoID, timestamp: timestamp)
        }
        self.init(
            type: type,
            pageURL: getUrl(from: preview.url),
            title: preview.title.isEmpty ? preview.siteName : preview.title,
            size: CGSize(width: embed.width, height: embed.height),
        )
    }

    init(type: WebEmbedType, pageURL: URL?, title: String, size: CGSize) {
        self.type = type
        self.pageURL = pageURL
        self.titleText = title
        self.aspectSize = size.width > 0 && size.height > 0 ? size : CGSize(width: 16, height: 9)
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        let userContent = WKUserContentController()
        if case .iframe = type {
            userContent.addUserScript(WKUserScript(
                source: "var meta = document.createElement('meta'); meta.setAttribute('name', 'viewport'); "
                    + "meta.setAttribute('content', 'width=device-width'); "
                    + "document.getElementsByTagName('head')[0].appendChild(meta)",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
            ))
        }
        configuration.userContentController = userContent
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        view.addSubview(webView)
        configureChrome()
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutWebView()
    }

    private static func resource(_ name: String, _ type: String) -> String? {
        guard let path = Bundle.main.path(forResource: name, ofType: type) else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    private static func thumbImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14)).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 14, height: 14))
        }
    }

    private static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void,
    ) {
        if let url = action.request.url, url.scheme == "embed" {
            callback(url)
            decisionHandler(.cancel)
        } else if action.targetFrame != nil {
            decisionHandler(.allow)
        } else {
            // A link out of the player, such as the YouTube logo, opens in the browser.
            if let url = action.request.url, url.absoluteString.contains("youtube") {
                WebBrowser.open(url, from: self)
            }
            decisionHandler(.cancel)
        }
    }

    // MARK: Player

    /// YoutubeEmbedImplementation.setup and GenericEmbedImplementation.setup: Telegram's page with the player's
    /// parameters, loaded from Telegram's origin.
    private func load() {
        switch type {
        case .youtube(let videoID, let timestamp):
            guard let template = Self.resource("Youtube", "html"), let script = Self.resource("YoutubeUserScript", "js")
            else { return openInBrowser() }
            let parameters: [String: Any] = [
                "videoId": videoID,
                "width": "100%",
                "height": "100%",
                "events": [
                    "onReady": "onReady",
                    "onStateChange": "onStateChange",
                    "onPlaybackQualityChange": "onPlaybackQualityChange",
                    "onError": "onPlayerError",
                ],
                "playerVars": [
                    "cc_load_policy": 1,
                    "iv_load_policy": 3,
                    "controls": 0,
                    "playsinline": 1,
                    "autohide": 1,
                    "showinfo": 0,
                    "rel": 0,
                    "modestbranding": 1,
                    "start": timestamp,
                ],
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: parameters),
                  let json = String(data: data, encoding: .utf8) else { return openInBrowser() }
            webView.configuration.userContentController.addUserScript(WKUserScript(
                source: script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
            ))
            webView.loadHTMLString(
                template.replacing("%@", with: json).replacing("%%", with: "%"),
                baseURL: URL(string: "https://ph.telegra.Telegraph"),
            )
        case .iframe(let url):
            guard let template = Self.resource("Generic", "html") else { return openInBrowser() }
            if let script = Self.resource("GenericUserScript", "js") {
                webView.configuration.userContentController.addUserScript(WKUserScript(
                    source: script,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: false,
                ))
            }
            webView.loadHTMLString(
                template.replacing("%@", with: url).replacing("%%", with: "%"),
                baseURL: URL(string: "about:blank"),
            )
        }
    }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// YoutubeEmbedImplementation.callback: `onReady` starts playback, `onState` carries the state (YT's -1 unstarted,
    /// 0 ended, 1 playing, 2 paused, 3 buffering), the position and the duration.
    private func callback(_ url: URL) {
        switch url.host {
        case "onReady":
            isReady = true
            if case .youtube(_, let timestamp) = type, timestamp > 0 { evaluate("seek(\(timestamp));") }
            evaluate("play();")
        case "onState":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                items.first { $0.name == name }?.value
            }
            if value("failed") == "true" {
                openInBrowser()
                return
            }
            if let playback = value("playback").flatMap(Int.init) { isPlaying = playback == 1 || playback == 3 }
            if let duration = value("duration").flatMap(Double.init), duration > 0 { self.duration = duration }
            if let position = value("position").flatMap(Double.init) { self.position = position }
            updateControls()
        default:
            break
        }
    }

    // MARK: Chrome

    private func configureChrome() {
        for bar in [topBar, bottomBar] {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            view.addSubview(bar)
        }
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        browserButton.translatesAutoresizingMaskIntoConstraints = false
        browserButton.setImage(UIImage(systemName: "safari"), for: .normal)
        browserButton.tintColor = .white
        browserButton.accessibilityLabel = L10n.telegram("Web.OpenExternal")
        browserButton.addAction(UIAction { [weak self] _ in self?.openInBrowser() }, for: .touchUpInside)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.text = titleText
        for subview in [closeButton, browserButton, titleLabel] {
            topBar.addSubview(subview)
        }
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.tintColor = .white
        playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.setThumbImage(Self.thumbImage(), for: .normal)
        slider.addAction(UIAction { [weak self] _ in self?.isScrubbing = true }, for: .touchDown)
        slider.addAction(UIAction { [weak self] _ in self?.scrubbed() }, for: [.touchUpInside, .touchUpOutside])
        slider.addAction(UIAction { [weak self] _ in self?.updateTimeLabel() }, for: .valueChanged)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        timeLabel.textColor = .white
        for subview in [playButton, slider, timeLabel] {
            bottomBar.addSubview(subview)
        }
        // Telegram's gallery shows its scrubber for a player it can seek.
        bottomBar.isHidden = !type.supportsSeeking
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        // Telegram's YouTube page hides YouTube's own controls; touches go to Telegram's.
        webView.isUserInteractionEnabled = !type.supportsSeeking
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            closeButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            browserButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            browserButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            browserButton.widthAnchor.constraint(equalToConstant: 44),
            browserButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: browserButton.leadingAnchor, constant: -8),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),
            playButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            playButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 6),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            slider.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 4),
            slider.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            timeLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            timeLabel.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
        ])
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        updateControls()
    }

    /// The player at the preview's aspect, as large as the screen allows.
    private func layoutWebView() {
        let bounds = view.bounds.inset(by: view.safeAreaInsets)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / aspectSize.width, bounds.height / aspectSize.height)
        let size = CGSize(width: floor(aspectSize.width * scale), height: floor(aspectSize.height * scale))
        NSLayoutConstraint.deactivate(webViewConstraints)
        webViewConstraints = [
            webView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            webView.widthAnchor.constraint(equalToConstant: size.width),
            webView.heightAnchor.constraint(equalToConstant: size.height),
        ]
        NSLayoutConstraint.activate(webViewConstraints)
    }

    private func updateControls() {
        playButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = L10n.telegram(isPlaying
            ? "VoiceOver.Media.PlaybackPause"
            : "VoiceOver.Media.PlaybackPlay")
        playButton.isEnabled = isReady
        guard !isScrubbing else { return }
        slider.maximumValue = Float(max(1, duration))
        slider.value = Float(min(position, duration))
        slider.isEnabled = isReady && duration > 0
        updateTimeLabel()
    }

    private func updateTimeLabel() {
        let current = isScrubbing ? Double(slider.value) : position
        timeLabel.text = "\(Self.format(current)) / \(Self.format(duration))"
    }

    private func togglePlayback() {
        guard isReady else { return }
        evaluate(isPlaying ? "pause();" : "play();")
        isPlaying.toggle()
        updateControls()
    }

    private func scrubbed() {
        isScrubbing = false
        position = Double(slider.value)
        evaluate("seek(\(position));")
        updateControls()
    }

    @objc private func toggleChrome(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        guard !topBar.frame.contains(point), bottomBar.isHidden || !bottomBar.frame.contains(point) else { return }
        chromeVisible.toggle()
        UIView.animate(withDuration: 0.2) {
            self.topBar.alpha = self.chromeVisible ? 1 : 0
            self.bottomBar.alpha = self.chromeVisible ? 1 : 0
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func openInBrowser() {
        guard let pageURL else { return }
        let presenter = presentingViewController
        dismiss(animated: true) {
            WebBrowser.open(pageURL, from: presenter)
        }
    }
}

#if DEBUG
    extension WebEmbedPlayerViewController {
        /// `-debug-embed-player URL`: the player for the link once the window shows, to check it without a preview.
        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-debug-embed-player"), index + 1 < arguments.count else {
                return
            }
            let url = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak window] in
                var presenter = window?.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                presenter?.present(
                    WebEmbedPlayerViewController(
                        type: WebEmbedType(url: url, embedURL: ""),
                        pageURL: URL(string: url),
                        title: "YouTube",
                        size: CGSize(width: 1280, height: 720),
                    ),
                    animated: true,
                )
            }
        }
    }
#endif
