// ChatTitleIconsProbe.swift

import UIKit

#if DEBUG
    /// Renders the chat header's title with ChatTitleView's lock and mute icons around the verified badge, to
    /// Documents/title-icons.png. Launch with `-ui-probe-title-icons`; the result goes to the log and to
    /// Documents/title-icons-probe.txt.
    @MainActor enum ChatTitleIconsProbe {
        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-title-icons") else { return }
            let width = CGFloat(402)
            let height = TelegramChatNavigationBar.contentHeight + 8
            let variants: [(String, TelegramChatNavigationBar.TitleIcons, PeerCredibilityBadge?)] = [
                ("Secret chat", .init(lock: true, mute: false), nil),
                ("Muted group", .init(lock: false, mute: true), nil),
                ("Secret and muted", .init(lock: true, mute: true), nil),
                ("Verified", .init(lock: false, mute: false), .verified),
            ]
            let canvas = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height * CGFloat(variants.count)))
            canvas.backgroundColor = .systemBackground
            canvas.overrideUserInterfaceStyle = .dark
            for (index, variant) in variants.enumerated() {
                let bar = TelegramChatNavigationBar(frame: CGRect(
                    x: 0,
                    y: height * CGFloat(index),
                    width: width,
                    height: height,
                ))
                bar.titleBadge = variant.2
                bar.titleIcons = variant.1
                bar.configure(title: variant.0, status: "last seen recently", statusColor: .secondaryLabel)
                canvas.addSubview(bar)
                bar.layoutIfNeeded()
            }
            canvas.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
                canvas.layer.render(in: context.cgContext)
            }
            let result = "Title icons probe rendered: lock/mute/both/verified=true"
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? image.pngData()?.write(to: directory.appendingPathComponent("title-icons.png"), options: .atomic)
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("title-icons-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }
#endif
