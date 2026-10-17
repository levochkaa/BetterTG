// StickerPeekProbe.swift

#if DEBUG
    import libwebp
    import TDLibKit
    import UIKit

    /// Launch with `-ui-probe-sticker-peek`. Once an account is active it opens the sticker panel on generated still
    /// WebP stickers, three in Favorites, three in Recently Used and six in one pack, in place of TDLib's, so
    /// Telegram's
    /// sticker peek is checked by holding a sticker and sliding over the others. Tap sends, Send Silently, Schedule
    /// Message and the peek's own items are only recorded, in the log and in Documents/sticker-peek-probe.txt, with
    /// every sticker cell's centre in window points.
    @MainActor enum StickerPeekProbe {
        private struct Spec {
            let emoji: String
            let color: UIColor
        }

        private struct ProbeError: Error, CustomStringConvertible {
            let description: String
        }

        private static let flag = "-ui-probe-sticker-peek"
        private static let fileIDBase = 1_920_000_000
        private static let packID: Int64 = 9_200_000_001
        private static let stickerSide = 512
        private static let specs = [
            Spec(emoji: "😀", color: .systemPink),
            Spec(emoji: "👍", color: .systemOrange),
            Spec(emoji: "🔥", color: .systemYellow),
            Spec(emoji: "🎉", color: .systemGreen),
            Spec(emoji: "❤️", color: .systemTeal),
            Spec(emoji: "😎", color: .systemBlue),
            Spec(emoji: "🐱", color: .systemIndigo),
            Spec(emoji: "🌈", color: .systemPurple),
            Spec(emoji: "🍕", color: .systemRed),
            Spec(emoji: "⚽️", color: .systemBrown),
            Spec(emoji: "🚀", color: .systemMint),
            Spec(emoji: "🎵", color: .systemCyan),
        ]
        private static var lines = [String]()

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains(flag) else { return }
            Task { @MainActor in
                do {
                    try await ProbeFixtures.waitForActiveAccount()
                } catch {
                    record("Sticker peek probe failed: \(error)")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                let stickers: [Sticker]
                do {
                    stickers = try makeStickers()
                } catch {
                    record("Sticker peek probe failed: \(error)")
                    return
                }
                guard let presenter, let accountID = TDLib.shared.activeAccountID else {
                    record("Sticker peek probe failed: no presenter or account")
                    return
                }
                let picker = makePicker(stickers: stickers, accountID: accountID)
                StickerPeekView.probeObserver = { observe($0) }
                let navigation = TelegramNavigationController(rootViewController: picker)
                navigation.modalPresentationStyle = .pageSheet
                navigation.sheetPresentationController?.detents = [.large()]
                navigation.sheetPresentationController?.prefersGrabberVisible = false
                presenter.present(navigation, animated: true)
                record("Sticker peek probe opened the sticker panel with \(stickers.count) stickers")
                // The sheet's entrance and the stickers' first frames.
                try? await Task.sleep(for: .milliseconds(1500))
                recordCells(in: picker.view)
            }
        }

        /// The generated stickers, which the poll attachment probe borrows too.
        static func makeStickers() throws -> [Sticker] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "sticker-peek-probe",
                isDirectory: true,
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try specs.enumerated().map { index, spec in
                guard let data = makeWebP(color: spec.color, label: String(index + 1)) else {
                    throw ProbeError(description: "sticker \(index + 1) didn't encode")
                }
                let url = directory.appendingPathComponent("sticker-\(index + 1).webp")
                try data.write(to: url, options: .atomic)
                let file = completedFile(id: fileIDBase + index, path: url.path, size: Int64(data.count))
                let fullType = TDNativeStickerFullType.stickerFullTypeRegular(
                    TDNativeStickerFullTypeRegular(premiumAnimation: nil),
                )
                return Sticker(
                    id: Int64(fileIDBase + index),
                    setId: packID,
                    width: stickerSide,
                    height: stickerSide,
                    emoji: spec.emoji,
                    format: .stickerFormatWebp,
                    fullType: fullType,
                    thumbnail: nil,
                    sticker: file,
                )
            }
        }

        private static func makePicker(
            stickers: [Sticker],
            accountID: UUID,
        ) -> ComposerMediaPickerViewController {
            let picker = ComposerMediaPickerViewController(
                accountID: accountID,
                chatID: 0,
                client: TDLib.shared.activeClient,
            )
            picker.initialMode = .stickers
            picker.probeStickers = ComposerMediaPickerViewController.ProbeStickers(
                favorites: Array(stickers[0..<3]),
                recent: Array(stickers[3..<6]),
                packID: packID,
                packTitle: "Peek Probe",
                pack: Array(stickers[6...]),
            )
            picker.onSticker = { record("Sticker peek probe sent \($0.emoji) by tap") }
            picker.onProbeStickerAction = { action, sticker in
                record("Sticker peek probe action \(action) for \(sticker.emoji)")
            }
            picker.stickerSendActions = { sendActions(for: $0) }
            return picker
        }

        /// The chat's items ChatView puts at the top of the menu, recorded instead of sent.
        private static func sendActions(for sticker: Sticker) -> [TelegramContextMenuAction] {
            [
                TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.SendMessage.SendSilently"),
                    image: UIImage(systemName: "bell.slash"),
                ) { record("Sticker peek probe sent \(sticker.emoji) silently") },
                TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.SendMessage.ScheduleMessage"),
                    image: UIImage(systemName: "calendar.badge.clock"),
                ) { record("Sticker peek probe scheduled \(sticker.emoji)") },
            ]
        }

        private static func observe(_ line: String) {
            record("Sticker peek probe \(line)")
            guard line.hasPrefix("opened") || line.hasPrefix("menu opened") else { return }
            // The preview's and the menu's springs settle before their frames are read.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard let peek = StickerPeekView.current else { return }
                record("Sticker peek probe layout: \(peek.probeSummary)")
            }
        }

        /// Each visible sticker cell's label and centre in window points, top to bottom, for the hold and slide.
        private static func recordCells(in root: UIView) {
            var cells = [ComposerStickerCell]()
            collectCells(in: root, into: &cells)
            let frames = cells.compactMap { cell -> (String, CGRect)? in
                guard cell.window != nil, !cell.isHidden else { return nil }
                return (cell.accessibilityLabel ?? "?", cell.convert(cell.bounds, to: nil))
            }
            .sorted { $0.1.minY == $1.1.minY ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
            guard !frames.isEmpty else {
                record("Sticker peek probe found no sticker cells")
                return
            }
            for (index, (label, frame)) in frames.enumerated() {
                record(
                    "Sticker peek probe cell \(index): \(label) centre (\(Int(frame.midX)), \(Int(frame.midY))) "
                        + "size \(Int(frame.width))x\(Int(frame.height))",
                )
            }
        }

        private static func collectCells(in view: UIView, into cells: inout [ComposerStickerCell]) {
            if let cell = view as? ComposerStickerCell {
                cells.append(cell)
                return
            }
            for subview in view.subviews {
                collectCells(in: subview, into: &cells)
            }
        }

        private static func record(_ line: String) {
            lines.append(line)
            log(line)
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            try? Data(lines.joined(separator: "\n").utf8).write(
                to: directory.appendingPathComponent("sticker-peek-probe.txt"),
                options: .atomic,
            )
        }

        // MARK: Fixtures

        /// A downloaded sticker file, which the cell and the preview decode without asking TDLib for it.
        private static func completedFile(id: Int, path: String, size: Int64) -> File {
            let local = LocalFile(
                path: path,
                canBeDownloaded: false,
                canBeDeleted: false,
                isDownloadingActive: false,
                isDownloadingCompleted: true,
                downloadOffset: 0,
                downloadedPrefixSize: size,
                downloadedSize: size,
            )
            let remote = RemoteFile(
                id: "",
                uniqueId: "bettertg-sticker-peek-probe-\(id)",
                isUploadingActive: false,
                isUploadingCompleted: true,
                uploadedSize: size,
            )
            return File(id: id, size: size, expectedSize: size, local: local, remote: remote)
        }

        /// A rounded square in the sticker's colour with its number, on a transparent background, as a still WebP.
        private static func makeWebP(color: UIColor, label: String) -> Data? {
            let side = stickerSide
            let size = CGSize(width: side, height: side)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                color.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 32, dy: 32), cornerRadius: 112)
                    .fill()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 260, weight: .heavy),
                    .foregroundColor: UIColor.white,
                ]
                let text = label as NSString
                let textSize = text.size(withAttributes: attributes)
                text.draw(
                    at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                    withAttributes: attributes,
                )
            }
            guard let cgImage = image.cgImage,
                  let bitmap = CGContext(
                      data: nil,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: side * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                  )
            else { return nil }
            bitmap.draw(cgImage, in: CGRect(origin: .zero, size: size))
            guard let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
            var output: UnsafeMutablePointer<UInt8>?
            let length = WebPEncodeRGBA(pixels, Int32(side), Int32(side), Int32(bitmap.bytesPerRow), 90, &output)
            guard length > 0, let output else { return nil }
            defer { WebPFree(output) }
            return Data(bytes: output, count: length)
        }
    }
#endif
