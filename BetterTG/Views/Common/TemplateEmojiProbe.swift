// TemplateEmojiProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Shows the account's themed and default emoji statuses that TDLib marks `needs_repainting`, each in the text
    /// colour and in the accent colour, over light and dark backgrounds, beside one emoji that keeps its own colours.
    /// Launch with `-ui-probe-template-emoji`; the counts go to the log and to Documents/template-emoji-probe.txt.
    @MainActor enum TemplateEmojiProbe {
        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-template-emoji") else { return }
            Task { @MainActor in
                try? await ProbeFixtures.waitForActiveAccount()
                let client = TDLib.shared.activeClient
                let themed = try? await client.send(TDNativeRequests.getThemedEmojiStatuses())
                let defaults = try? await client.send(TDNativeRequests.getDefaultEmojiStatuses())
                let identifiers = (themed?.customEmojiIds ?? []) + (defaults?.customEmojiIds ?? [])
                let stickers = await CustomEmojiStickerRepository.shared.stickers(for: identifiers, client: client)
                let ordered = identifiers.compactMap { stickers[$0] }
                let templates = ordered.filter {
                    if case .stickerFullTypeCustomEmoji(let emoji) = $0.fullType { return emoji.needsRepainting }
                    return false
                }
                var seen = Set<Int64>()
                let shown = templates.filter { seen.insert($0.id).inserted }.prefix(5)
                let plain = ordered.first { sticker in !templates.contains { $0.id == sticker.id } }
                let formats = shown.lazy.map { "\($0.format)" }.joined(separator: ",")
                let result = "Template emoji probe: themed=\(themed?.customEmojiIds.count ?? 0) "
                    + "default=\(defaults?.customEmojiIds.count ?? 0) template=\(templates.count) formats=\(formats)"
                log(result)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("template-emoji-probe.txt"),
                        options: .atomic,
                    )
                }
                present(in: window, templates: Array(shown), plain: plain, client: client)
            }
        }

        private static func present(in window: UIWindow, templates: [Sticker], plain: Sticker?, client: TDLibClient) {
            let controller = UIViewController()
            controller.modalPresentationStyle = .fullScreen
            let halves = UIStackView()
            halves.axis = .vertical
            halves.distribution = .fillEqually
            halves.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(halves)
            NSLayoutConstraint.activate([
                halves.topAnchor.constraint(equalTo: controller.view.topAnchor),
                halves.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
                halves.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
                halves.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            ])
            for style in [UIUserInterfaceStyle.light, .dark] {
                let half = UIView()
                half.overrideUserInterfaceStyle = style
                half.backgroundColor = .systemBackground
                let rows = UIStackView()
                rows.axis = .vertical
                rows.spacing = 12
                rows.alignment = .center
                rows.translatesAutoresizingMaskIntoConstraints = false
                half.addSubview(rows)
                NSLayoutConstraint.activate([
                    rows.centerXAnchor.constraint(equalTo: half.centerXAnchor),
                    rows.centerYAnchor.constraint(equalTo: half.centerYAnchor),
                ])
                // Text colour, accent colour, then the plain emoji with a template colour it ignores.
                for color in [UIColor.label, .systemBlue] {
                    rows.addArrangedSubview(row(templates, color: color, client: client))
                }
                if let plain { rows.addArrangedSubview(row([plain], color: .label, client: client)) }
                halves.addArrangedSubview(half)
            }
            window.rootViewController?.present(controller, animated: false)
        }

        private static func row(_ stickers: [Sticker], color: UIColor, client: TDLibClient) -> UIStackView {
            let row = UIStackView()
            row.spacing = 12
            for sticker in stickers {
                let view = CustomEmojiInlineView()
                view.templateColor = color
                view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    view.widthAnchor.constraint(equalToConstant: 40),
                    view.heightAnchor.constraint(equalToConstant: 40),
                ])
                view.configure(sticker: sticker, client: client)
                view.setPlaybackVisible(true)
                row.addArrangedSubview(view)
            }
            return row
        }
    }
#endif
