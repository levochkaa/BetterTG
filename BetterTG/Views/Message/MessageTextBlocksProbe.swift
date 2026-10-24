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
                    try verifyCollapse()
                    result = "Text blocks probe passed: paragraph-ranges/quote/code-title/plain-pre/expandable=true; "
                        + "layout-indent/frames-ordered/status-below=true; "
                        + "collapsed-three-lines/expanded-taller/short-open/tap-toggles=true"
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

        /// An expandable quote of six lines folds to three with the arrow, opens taller, and one of two lines stays
        /// open without an arrow; a tap on the folded quote opens it. Both states go to Documents/text-collapse.png.
        private static func verifyCollapse() throws {
            let lines = (1...6).lazy.map { "Quoted line number \($0) of the expandable quote" }.joined(separator: "\n")
            let text = "Before\n\(lines)\nAfter"
            let range = (text as NSString).range(of: lines)
            let formatted = FormattedText(
                entities: [TextEntity(
                    length: range.length,
                    offset: range.location,
                    type: .textEntityTypeExpandableBlockQuote,
                )],
                text: text,
            )
            func make(expanded: Set<Int>) -> MessageTextContentView {
                let view = MessageTextContentView(frame: .zero, textContainer: nil)
                view.overrideUserInterfaceStyle = .dark
                view.configure(
                    formattedText: formatted,
                    client: TDLib.shared.activeClient,
                    statusText: "20:00",
                    statusColor: .secondaryLabel,
                    maximumWidth: 280,
                    expandedQuoteBlocks: expanded,
                )
                view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
                view.layoutIfNeeded()
                return view
            }
            let collapsed = make(expanded: [])
            let expanded = make(expanded: [0])
            try require(collapsed.probeBlockCollapse == [.collapsed], "collapsed state \(collapsed.probeBlockCollapse)")
            try require(expanded.probeBlockCollapse == [.expanded], "expanded state")
            let foldedHeight = collapsed.probeBlockFrames.first?.height ?? 0
            let openHeight = expanded.probeBlockFrames.first?.height ?? 0
            let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
            try require(
                foldedHeight < lineHeight * 4 && openHeight > lineHeight * 5.5,
                "heights \(foldedHeight) \(openHeight)",
            )
            try require(collapsed.bounds.height < expanded.bounds.height, "view heights")
            let short = FormattedText(
                entities: [TextEntity(length: 9, offset: 0, type: .textEntityTypeExpandableBlockQuote)],
                text: "One\nTwo ok\nTail",
            )
            let shortView = MessageTextContentView(frame: .zero, textContainer: nil)
            shortView.configure(
                formattedText: short,
                client: TDLib.shared.activeClient,
                statusText: "",
                statusColor: .secondaryLabel,
                maximumWidth: 280,
            )
            try require(shortView.probeBlockCollapse == [nil], "short quote")
            var toggled: Int?
            collapsed.onToggleQuoteBlock = { toggled = $0 }
            if let frame = collapsed.probeBlockFrames.first {
                collapsed.probeTap(at: CGPoint(x: frame.midX, y: frame.midY))
            }
            try require(toggled == 0, "tap toggles")
            let canvas = UIView(frame: CGRect(
                x: 0,
                y: 0,
                width: collapsed.bounds.width + expanded.bounds.width + 36,
                height: max(collapsed.bounds.height, expanded.bounds.height) + 24,
            ))
            canvas.backgroundColor = .secondarySystemBackground
            canvas.overrideUserInterfaceStyle = .dark
            collapsed.frame.origin = CGPoint(x: 12, y: 12)
            expanded.frame.origin = CGPoint(x: collapsed.frame.maxX + 12, y: 12)
            canvas.addSubview(collapsed)
            canvas.addSubview(expanded)
            canvas.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
                canvas.layer.render(in: context.cgContext)
            }
            if let data = image.pngData(),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            {
                try? data.write(to: directory.appendingPathComponent("text-collapse.png"), options: .atomic)
            }
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
