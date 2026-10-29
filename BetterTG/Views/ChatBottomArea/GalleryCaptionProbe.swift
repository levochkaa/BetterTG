// GalleryCaptionProbe.swift

#if DEBUG
import Photos
import TDLibKit
import UIKit

/// The real Gallery and Photos loader with a local send sink. No TDLib send or composer/account mutation.
@MainActor enum GalleryCaptionProbe {
    private final class Host: UIViewController {
        private let status = UILabel()
        private var gallery: AttachmentSheetViewController?
        private var opened = false
        private var requests = 0
        private var lastRequest: AttachmentMediaSendRequest?
        private var details = ""
        private var imported = 0
        private var mapped = false
        private var layouts = [String]()

        override func viewDidLoad() {
            super.viewDidLoad()
            title = "Gallery caption fixture"
            view.backgroundColor = .systemGroupedBackground
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 18
            stack.translatesAutoresizingMaskIntoConstraints = false
            for title in ["Open Gallery", "Retry all", "Retry remaining", "Appearance"] {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    switch title {
                    case "Appearance":
                        overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .light : .dark
                    case "Retry all",
                         "Retry remaining":
                        guard let gallery, let request = lastRequest else { return }
                        let partial = title == "Retry remaining"
                        let ids = Set(request.assets.dropFirst(partial ? 1 : 0).map(\.localIdentifier))
                        gallery.prepareForRetry(assetIDs: ids, captionWasSent: partial)
                        show(gallery)
                    default: openGallery()
                    }
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
            status.numberOfLines = 0
            status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            stack.addArrangedSubview(status)
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(recordLayout),
                name: UIResponder.keyboardDidChangeFrameNotification,
                object: nil,
            )
            report()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !opened else { return }
            opened = true
            openGallery()
        }

        private func openGallery() {
            let caption = ComposerText.attributed(FormattedText(entities: [
                .init(length: 4, offset: 5, type: .textEntityTypeBold),
            ], text: "Seed bold"))
            let picker = AttachmentSheetViewController(configuration: AttachmentSheetConfiguration(
                allowsPhotos: true, allowsCamera: false, tabs: [.gallery, .file], allowsSendAsFile: true,
                canSchedule: true, canSendWhenOnline: true,
                caption: caption, allowsCaptionEditing: true,
            ), client: TDLib.shared.activeClient)
            picker.switchesTabsInPlace = true
            picker.onSelectTab = { [weak self] tab in self?.switchTab(tab) }
            picker.onSend = { [weak self] request in self?.accept(request) }
            gallery = picker
            show(picker)
        }

        private func show(_ picker: AttachmentSheetViewController) {
            let navigation = picker.makeNavigationController()
            navigation.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
            present(navigation, animated: true) { self.recordLayout() }
        }

        private func switchTab(_ tab: AttachmentSheetTab) {
            guard let navigation = presentedViewController as? TelegramNavigationController, let gallery else { return }
            if tab == .gallery {
                navigation.replaceAttachmentSheetContent(with: gallery)
            } else {
                let file = UIViewController()
                file.title = "File fixture"
                file.view.backgroundColor = .systemGroupedBackground
                AttachmentPanelView.install(in: file, tabs: [.gallery, .file], current: .file) { [weak self] in
                    self?.switchTab($0)
                }
                navigation.replaceAttachmentSheetContent(with: file)
            }
        }

        private func accept(_ request: AttachmentMediaSendRequest) {
            requests += 1
            lastRequest = request
            imported = 0
            mapped = false
            let caption = ComposerText.formatted(request.caption)
            let entities = caption.entities.lazy.map { "\($0.offset):\($0.length):\($0.type)" }.joined(separator: ",")
            details = "count=\(request.assets.count); mode=\(request.mode); timing=\(request.timing); scheduling=\(String(describing: request.schedulingState)); above=\(request.captionIsAbove)\ncaption=\(caption.text)\nentities=\(entities)"
            report()
            PhotoAssetSelectionLoader
                .load(request.assets, highQualityPhotos: request.highQualityPhotos) { [weak self] images in
                guard let self else { return }
                imported = images.count
                mapped = images.compactMap(\.sourceAssetIdentifier) == request.assets.map(\.localIdentifier)
                report()
                let urls = images.flatMap(\.fileURLs)
                Task.detached { SelectedDocumentFileStore.removeUnleased(urls) }
            }
        }

        @objc private func recordLayout() {
            guard let navigation = presentedViewController as? TelegramNavigationController,
                  let screen = navigation.topViewController else { return }
            let panel = screen.view.subviews.first { $0 is AttachmentPanelView }
            layouts
                .append(
                    "panel=\(String(describing: panel?.frame)); keyboard=\(screen.view.keyboardLayoutGuide.layoutFrame); safe=\(screen.view.safeAreaInsets)",
                )
            write(layouts.joined(separator: "\n"), name: "gallery-caption-layout.txt")
        }

        private func report() {
            let text = "Gallery fixture: requests=\(requests); imported=\(imported); mapped=\(mapped)\n\(details)"
            status.text = text
            status.accessibilityLabel = text
            write(text, name: "gallery-caption-probe.txt")
        }

        private func write(_ text: String, name: String) {
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(text.utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
            }
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-gallery-caption") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let navigation = TelegramNavigationController(rootViewController: Host())
            navigation.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(navigation, animated: false)
        }
    }
}
#endif
