// PollLinkEditor.swift

import TDLibKit
import UIKit

// MARK: - PollLinkEditor

/// chatTextLinkEditController with `preview: true` as a poll option's link editor: Add Link, or Edit Link for an
/// attached one, "Attach a link to this option.", the URL field and Done. Done takes a link Telegram would open
/// (`explicitUrl` adds https://, `isValidUrl` wants an http, https or tonsite address with a domain) or an empty field,
/// which removes the link. A new link starts from a URL on the pasteboard. A second after the field settles on a valid
/// link, the alert shows its web page (AlertWebpagePreviewComponent), and Done hands that page over with the link
/// it previews.
@MainActor enum PollLinkEditor {
    private static let contentSelector = NSSelectorFromString("setContentViewController:")

    /// - Parameter apply: The link and the web page shown for it, an empty link to remove it, or nil for Cancel.
    static func make(
        link: String?,
        client: TDLibClient,
        apply: @escaping (String?, LinkPreview?) -> Void,
    ) -> UIAlertController {
        let alert = UIAlertController(
            title: L10n.telegram(link == nil ? "TextFormat.AddLinkTitle" : "TextFormat.EditLinkTitle"),
            message: L10n.telegram("CreatePoll.Link.Description"),
            preferredStyle: .alert,
        )
        let preview = PollLinkPreviewContentViewController(client: client)
        // Without a content view the alert can't show the page, and the poll creator asks for it after Done.
        let showsPreview = setContent(preview, of: alert)
        let done = UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [weak alert] _ in
            let value = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            preview.cancel()
            guard !value.isEmpty else { return apply("", nil) }
            let url = explicitURL(value)
            apply(url, preview.preview(for: url))
        }
        alert.addTextField { [weak done] field in
            field.placeholder = L10n.telegram("TextFormat.AddLinkPlaceholder")
            field.text = link
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.returnKeyType = .done
            if link == nil, UIPasteboard.general.hasURLs, let url = UIPasteboard.general.url?.absoluteString {
                field.text = url
            }
            field.addAction(UIAction { [weak field] _ in
                let text = field?.text ?? ""
                done?.isEnabled = isAcceptable(text)
                guard showsPreview else { return }
                preview.update(link: explicitURL(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }, for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { _ in
            preview.cancel()
            apply(nil, nil)
        })
        alert.addAction(done)
        alert.preferredAction = done
        let text = alert.textFields?.first?.text ?? ""
        done.isEnabled = isAcceptable(text)
        if showsPreview {
            preview.update(link: explicitURL(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return alert
    }

    /// UrlEscaping's isValidUrl with chatTextLinkEditController's schemes: http, https and tonsite, the web ones
    /// with a top level domain, and no user.
    fileprivate static func isValidURL(_ value: String) -> Bool {
        let requiresTopLevelDomain = ["http": true, "https": true, "tonsite": true]
        guard let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: escaped), let scheme = url.scheme?.lowercased(),
              let requiresDomain = requiresTopLevelDomain[scheme], let host = url.host, url.user == nil
        else { return false }
        guard requiresDomain else { return true }
        return host.contains(".") && host.components(separatedBy: ".").last?.isEmpty == false
    }

    /// An empty field, or a link Telegram accepts.
    private static func isAcceptable(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || isValidURL(explicitURL(value))
    }

    /// UrlEscaping's explicitUrl: an address without a scheme gets https://, or tonsite:// on a .ton domain.
    private static func explicitURL(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("http:"), !lowercased.hasPrefix("https:"), !lowercased.hasPrefix("tonsite:"),
              !value.contains("://")
        else { return value }
        if URL(string: "http://\(value)")?.host?.hasSuffix(".ton") == true { return "tonsite://\(value)" }
        return "https://\(value)"
    }

    /// `-[UIAlertController setContentViewController:]`, checked before it is called.
    private static func setContent(_ content: UIViewController, of alert: UIAlertController) -> Bool {
        guard UIAlertController.instancesRespond(to: contentSelector) else { return false }
        typealias SetContent = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        unsafeBitCast(alert.method(for: contentSelector), to: SetContent.self)(alert, contentSelector, content)
        return true
    }
}

// MARK: - PollLinkPreviewContentViewController

/// chatTextLinkEditController's preview signal: each new link clears the page at once and, a second later, shows
/// the one `webpagePreview` (getLinkPreview) returns for it, under the alert's text.
private final class PollLinkPreviewContentViewController: UIViewController {
    private let client: TDLibClient
    private var link = ""
    private var shown: (link: String, preview: LinkPreview)?
    private var request: Task<Void, Never>?
    private var previewView: PollLinkPreviewView?

    init(client: TDLibClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updatePreferredContentSize()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancel()
    }

    /// `currentPreview`: the page shown for the link Done applies, if it's the one shown.
    func preview(for link: String) -> LinkPreview? {
        guard let shown, shown.link == link else { return nil }
        return shown.preview
    }

    func cancel() {
        request?.cancel()
        request = nil
    }

    /// The field's link, as `explicitUrl` makes it; the same link again changes nothing.
    func update(link newLink: String) {
        guard newLink != link else { return }
        link = newLink
        cancel()
        show(nil)
        guard !newLink.isEmpty, PollLinkEditor.isValidURL(newLink) else { return }
        let client = client
        let text = FormattedText(entities: [], text: newLink)
        request = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let preview = try? await client.send(TDNativeRequests.getLinkPreview(text: text, linkPreviewOptions: nil))
            guard let self, !Task.isCancelled, link == newLink, let preview else { return }
            show((newLink, preview))
        }
    }

    private func show(_ value: (link: String, preview: LinkPreview)?) {
        guard shown != nil || value != nil else { return }
        shown = value
        previewView?.removeFromSuperview()
        previewView = nil
        if let value {
            let previewView = PollLinkPreviewView(preview: value.preview, client: client)
            previewView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(previewView)
            NSLayoutConstraint.activate([
                previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
                previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            ])
            self.previewView = previewView
        }
        guard isViewLoaded, view.window != nil else { return updatePreferredContentSize() }
        // The alert grows to the page and shrinks back with the same ease as the content update.
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.updatePreferredContentSize()
            self.parent?.view.layoutIfNeeded()
            self.view.window?.layoutIfNeeded()
        }
    }

    private func updatePreferredContentSize() {
        let width = view.bounds.width > 0 ? view.bounds.width : 270
        let height: CGFloat =
            if previewView == nil {
                0
            } else {
                view.systemLayoutSizeFitting(
                    CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel,
                )
                .height
            }
        if preferredContentSize.height != height {
            preferredContentSize = CGSize(width: width, height: height)
        }
    }
}

// MARK: - PollLinkPreviewView

/// AlertWebpagePreviewComponent: the web page as ChatMessageAttachedContentNode draws it in a preview, with the
/// accent line, the site name in two lines, the title in five, the text in four beside media or six without, and the
/// page's image beside the text or, for large media, above or under it.
private final class PollLinkPreviewView: UIView {
    private let imageView = TDImageLoadingView()

    init(preview: LinkPreview, client: TDLibClient) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 5
        clipsToBounds = true
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)
        let accent = UIView()
        accent.backgroundColor = .systemBlue
        accent.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accent)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            accent.topAnchor.constraint(equalTo: topAnchor),
            accent.bottomAnchor.constraint(equalTo: bottomAnchor),
            accent.leadingAnchor.constraint(equalTo: leadingAnchor),
            accent.widthAnchor.constraint(equalToConstant: 3),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        let text = UIStackView()
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = 3
        let media = MessageLinkPreviewView.thumbnail(preview.type)
        let siteName = preview.siteName.isEmpty
            ? (URL(string: preview.url)?.host ?? preview.displayUrl)
            : preview.siteName
        text.addArrangedSubview(Self.label(siteName, size: 13, weight: .semibold, color: .systemBlue, lines: 2))
        if !preview.title.isEmpty {
            text.addArrangedSubview(Self.label(preview.title, size: 15, weight: .semibold, color: .label, lines: 5))
        }
        if !preview.description.text.isEmpty {
            text.addArrangedSubview(Self.label(
                preview.description.text,
                size: 15,
                weight: .regular,
                color: .label,
                lines: media == nil ? 6 : 4,
            ))
        }
        guard let media else {
            content.addArrangedSubview(text)
            return
        }
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 4
        imageView.load(file: media.file, placeholderData: media.placeholder, maximumPixelSize: 720, client: client)
        if preview.showLargeMedia {
            if preview.showMediaAboveDescription { content.addArrangedSubview(imageView) }
            content.addArrangedSubview(text)
            if !preview.showMediaAboveDescription { content.addArrangedSubview(imageView) }
            let aspect = min(1.3, max(0.5, media.size.height / max(1, media.size.width)))
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspect).isActive = true
        } else {
            let row = UIStackView(arrangedSubviews: [text, imageView])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 8
            content.addArrangedSubview(row)
            imageView.widthAnchor.constraint(equalToConstant: 54).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 54).isActive = true
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func label(
        _ value: String,
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        lines: Int,
    ) -> UILabel {
        let label = UILabel()
        label.text = value
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}
