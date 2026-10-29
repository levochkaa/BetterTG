// ComposerSendTextProbe.swift

#if DEBUG
import TDLibKit
import UIKit

/// Isolates the input's glass compositing from account data. Captures use the device tool, not layer rendering.
@MainActor enum ComposerSendTextProbe {
    private final class Controller: UIViewController {
        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        let text = FormattedTextView(placeholder: "")
        let mode = UISegmentedControl(items: ["Live", "Snapshot", "Copy"])
        let scenario = UISegmentedControl(items: ["Plain", "Rich", "Scrolled", "Emoji"])
        var transferred: UIView?
        var verified = false
        var emojiTask: Task<Void, Never>?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            mode.selectedSegmentIndex = 0
            mode.addTarget(self, action: #selector(changeMode), for: .valueChanged)
            view.addSubview(mode)
            scenario.selectedSegmentIndex = 0
            scenario.addTarget(self, action: #selector(changeScenario), for: .valueChanged)
            view.addSubview(scenario)
            glass.layer.cornerRadius = 22
            glass.layer.cornerCurve = .continuous
            glass.clipsToBounds = true
            view.addSubview(glass)
            text.text = "Live text inside glass\nBold, italic and a link\nA third line 🙂"
            text.isEditable = false
            text.isSelectable = false
            glass.contentView.addSubview(text)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !verified else { return }
            verified = true
            let result: String
            do {
                try verifyCopy()
                result = "Composer send text probe passed: attributed text and viewport preserved; "
                    + "source selection, focus and undo untouched; later edits and clear leave captured text intact"
            } catch {
                result = "Composer send text probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("composer-send-text-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            mode.frame = CGRect(x: 16, y: 90, width: view.bounds.width - 32, height: 36)
            scenario.frame = CGRect(x: 16, y: 138, width: view.bounds.width - 32, height: 36)
            glass.frame = CGRect(x: 8, y: 350, width: view.bounds.width - 16, height: 150)
            text.frame = CGRect(x: 30, y: 15, width: glass.bounds.width - 60, height: 120)
        }

        private static func richText(lines: Int) -> NSAttributedString {
            let value = NSMutableAttributedString(
                string: (0..<lines).lazy.map { "Line \($0 + 1): bold italic 🙂 مرحبا" }.joined(separator: "\n"),
                attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label],
            )
            value.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 17), range: NSRange(location: 8, length: 4))
            value.addAttribute(
                .font,
                value: UIFont.italicSystemFont(ofSize: 17),
                range: NSRange(location: 13, length: 6),
            )
            value.addAttribute(
                .link,
                value: URL(string: "https://telegram.org")!,
                range: NSRange(location: 0, length: 6),
            )
            return value
        }

        @objc func changeMode() {
            transferred?.removeFromSuperview()
            transferred = nil
            text.isHidden = false
            glass.clipsToBounds = true
            guard mode.selectedSegmentIndex != 0 else { return }
            if mode.selectedSegmentIndex == 1 {
                let snapshot = text.snapshotView(afterScreenUpdates: false)
                snapshot?.frame = text.convert(text.bounds, to: view)
                if let snapshot { view.addSubview(snapshot) }
                transferred = snapshot
            } else {
                let copy = text.makeSendTransitionView()
                copy.frame = text.convert(text.bounds, to: view)
                view.addSubview(copy)
                transferred = copy
            }
            text.isHidden = true
        }

        @objc func changeScenario() {
            emojiTask?.cancel()
            mode.selectedSegmentIndex = 0
            changeMode()
            text.customEmojiClient = nil
            text.contentOffset = .zero
            if scenario.selectedSegmentIndex == 3 {
                emojiTask = Task { [weak self] in await self?.showEmoji() }
                return
            }
            text.attributedText = scenario.selectedSegmentIndex == 0
                ? NSAttributedString(
                    string: "Live text inside glass\nBold, italic and a link\nA third line 🙂",
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label,
                    ],
                )
                : Self.richText(lines: scenario.selectedSegmentIndex == 2 ? 20 : 3)
            text.isScrollEnabled = scenario.selectedSegmentIndex == 2
            text.layoutIfNeeded()
            if scenario.selectedSegmentIndex == 2 { text.contentOffset = CGPoint(x: 0, y: 90) }
        }

        private func showEmoji() async {
            text.text = "Loading one test emoji…"
            try? await ProbeFixtures.waitForActiveAccount()
            guard !Task.isCancelled else { return }
            let client = TDLib.shared.activeClient
            let statuses = try? await client.send(TDNativeRequests.getThemedEmojiStatuses())
            guard !Task.isCancelled, let id = statuses?.customEmojiIds.first else {
                text.text = "No emoji fixture available"
                return
            }
            let value = NSMutableAttributedString(
                string: "Custom emoji ⭐️", attributes: [
                    .font: UIFont.systemFont(ofSize: 17),
                    .foregroundColor: UIColor.label,
                ],
            )
            ComposerText.setCustomEmoji(
                [TelegramCustomEmojiRun(id: id, range: NSRange(location: 13, length: 2))], in: value,
            )
            text.setAttributedText(ComposerText.value(value))
            text.customEmojiClient = client
            for _ in 0..<100 {
                guard !Task.isCancelled else { return }
                if let manager = text.layoutManager as? ComposerEmojiLayoutManager,
                   !manager.hiddenCharacterRanges.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            let copy = text.makeSendTransitionView()
            let hidden = (copy.textView.layoutManager as? ComposerEmojiLayoutManager)?.hiddenCharacterRanges ?? []
            let captures = copy.textView.subviews.filter { !($0 is UIScrollView) && !$0.subviews.isEmpty }
            let passed = hidden == [NSRange(location: 13, length: 2)] && !captures.isEmpty
            let result = "Composer send custom emoji probe \(passed ? "passed" : "failed"): "
                + "decoded frame and template mask copied without a second renderer"
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("composer-send-emoji-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }

        private func verifyCopy() throws {
            struct Failure: Error, CustomStringConvertible { let description: String }
            func require(_ condition: Bool, _ reason: String) throws {
                if !condition { throw Failure(description: reason) }
            }
            let source = FormattedTextView(placeholder: "")
            source.frame = CGRect(x: -1000, y: 0, width: 260, height: 90)
            glass.contentView.addSubview(source)
            defer { source.resignFirstResponder()
            source.removeFromSuperview()
            }
            source.attributedText = Self.richText(lines: 20)
            source.isScrollEnabled = true
            source.layoutIfNeeded()
            source.contentOffset = CGPoint(x: 0, y: 90)
            source.selectedRange = NSRange(location: 15, length: 6)
            let selected = source.selectedRange
            let offset = source.contentOffset
            let copy = source.makeSendTransitionView()
            try require(copy.textView.attributedText.isEqual(to: source.attributedText), "rich text changed")
            try require(copy.textView.contentOffset == source.contentOffset, "scroll offset changed")
            try require(copy.bounds.size == source.bounds.size, "viewport changed")
            try require(source.selectedRange == selected, "source selection changed")
            try require(
                !copy.textView.isEditable && !copy.textView.isSelectable && !copy.isUserInteractionEnabled,
                "copy is interactive",
            )
            let captured = NSAttributedString(attributedString: copy.textView.attributedText)
            source.attributedText = NSAttributedString(string: "Next message")
            source.text = ""
            try require(copy.textView.attributedText.isEqual(to: captured), "source edit cleared the capture")
            copy.frame.size = CGSize(width: 60, height: 30)
            copy.layoutIfNeeded()
            try require(copy.textView.bounds.size == source.bounds.size, "shrinking a caption reflowed its text")
            try require(copy.textView.contentOffset == offset, "shrinking a caption changed its offset")
            source.becomeFirstResponder()
            source.insertText("Undo stays here")
            let undo = source.undoManager
            let hadUndo = undo?.canUndo == true
            let focusedCopy = source.makeSendTransitionView()
            try require(source.isFirstResponder && !focusedCopy.isFirstResponder, "focus transferred")
            try require(hadUndo && undo === source.undoManager && undo?.canUndo == true, "undo lost")
            undo?.undo()
            try require(source.text.isEmpty, "undo no longer edits the source")
            try require(focusedCopy.textView.text == "Undo stays here", "undo changed the capture")
        }
    }

    private static var host: UIWindow?

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-composer-send-text"),
              let scene = window.windowScene else { return }
        let host = UIWindow(windowScene: scene)
        host.frame = window.bounds
        host.windowLevel = .normal + 1
        host.rootViewController = Controller()
        host.isHidden = false
        self.host = host
    }
}
#endif
