// MessageTextBlocksProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Checks quotes and code blocks in message text offline: MessageTextBlock's paragraph ranges, kinds and titles,
    /// and a laid-out text view with a quote, a titled code block and plain text, rendered to
    /// Documents/text-blocks.png.
    /// Launch with `-ui-probe-text-blocks`; the result goes to the log and to Documents/text-blocks-probe.txt.
    @MainActor enum MessageTextBlocksProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private static let sample: FormattedText = {
            let quote = "A quoted line that is long enough to wrap onto a second line in the bubble"
            let code = "let answer = 42\nprint(answer)"
            let text = "Intro text\n\(quote)\n\(code)\nOutro"
            let string = text as NSString
            let quoteRange = string.range(of: quote)
            let codeRange = string.range(of: code)
            return FormattedText(
                entities: [
                    TextEntity(length: quoteRange.length, offset: quoteRange.location, type: .textEntityTypeBlockQuote),
                    TextEntity(
                        length: codeRange.length,
                        offset: codeRange.location,
                        type: .textEntityTypePreCode(.init(language: "swift")),
                    ),
                ],
                text: text,
            )
        }()

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-text-blocks") else { return }
            Task {
                let result: String
                do {
                    try await ProbeFixtures.waitForActiveAccount()
                    try verifyBlocks()
                    try verifyLayout()
                    result = "Text blocks probe passed: paragraph-ranges/quote/code-title/plain-pre/expandable=true; "
                        + "layout-indent/frames-ordered/status-below=true"
                } catch {
                    result = "Text blocks probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("text-blocks-probe.txt"),
                        options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verifyBlocks() throws {
            let blocks = MessageTextBlock.blocks(in: sample)
            try require(blocks.count == 2, "count \(blocks.count)")
            try require(blocks[0].kind == .quote && blocks[1].kind == .code(title: "Swift"), "kinds \(blocks)")
            let string = sample.text as NSString
            try require(
                string.substring(with: blocks[1].range) == "let answer = 42\nprint(answer)",
                "code range \(string.substring(with: blocks[1].range))",
            )
            let plain = FormattedText(
                entities: [
                    TextEntity(length: 4, offset: 0, type: .textEntityTypePre),
                    TextEntity(length: 3, offset: 5, type: .textEntityTypeExpandableBlockQuote),
                ],
                text: "code\nquo",
            )
            let plainBlocks = MessageTextBlock.blocks(in: plain)
            try require(
                plainBlocks.map(\.kind) == [.code(title: nil), .quote] && !plainBlocks[0].reservesIcon,
                "plain \(plainBlocks)",
            )
        }

        private static func verifyLayout() throws {
            let view = MessageTextContentView(frame: .zero, textContainer: nil)
            view.overrideUserInterfaceStyle = .dark
            view.configure(
                formattedText: sample,
                client: TDLib.shared.activeClient,
                statusText: "20:00",
                statusColor: .secondaryLabel,
                maximumWidth: 280,
            )
            let size = view.intrinsicContentSize
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutIfNeeded()
            let frames = view.probeBlockFrames
            try require(frames.count == 2, "frames \(frames)")
            try require(frames[0].maxY <= frames[1].minY && frames[0].minX == 0, "order \(frames)")
            try require(view.probeFirstLineIndent(of: 0) == MessageTextBlock.leftInset, "indent")
            let canvas = UIView(frame: CGRect(
                origin: .zero,
                size: CGSize(width: size.width + 24, height: size.height + 24),
            ))
            canvas.backgroundColor = .secondarySystemBackground
            canvas.overrideUserInterfaceStyle = .dark
            view.frame.origin = CGPoint(x: 12, y: 12)
            canvas.addSubview(view)
            canvas.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
                canvas.layer.render(in: context.cgContext)
            }
            if let data = image.pngData(),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            {
                try? data.write(to: directory.appendingPathComponent("text-blocks.png"), options: .atomic)
            }
        }
    }
#endif
