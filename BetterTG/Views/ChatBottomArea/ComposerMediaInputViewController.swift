// ComposerMediaInputViewController.swift

import UIKit

// MARK: - ComposerMediaInputViewController

/// Telegram's `.media` input mode (ChatEntityKeyboardInputNode): the emoji, sticker and GIF panel stands where the
/// system keyboard goes, as tall as the keyboard (`standardInputHeight`), and stays up after a sticker or GIF is
/// sent.
final class ComposerMediaInputViewController: UIInputViewController {
    let picker: ComposerMediaPickerViewController

    private let panelView: PanelInputView

    /// The panel takes the container's width: the system sizes a self-sizing input view's height only, so the width
    /// stays the frame's.
    init(picker: ComposerMediaPickerViewController, size: CGSize) {
        self.picker = picker
        self.panelView = PanelInputView(size: size)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        inputView = panelView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(picker)
        picker.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker.view)
        NSLayoutConstraint.activate([
            picker.view.topAnchor.constraint(equalTo: view.topAnchor),
            picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        picker.didMove(toParent: self)
    }

    /// The panel's width through a rotation or a fold, which the system leaves to a self-sizing input view.
    func setPanelWidth(_ width: CGFloat) {
        panelView.frame.size.width = width
    }

    /// Follows the system keyboard's height for the current width; true when it changed.
    @discardableResult func setPanelHeight(_ height: CGFloat) -> Bool {
        guard abs(height - panelView.panelHeight) > 0.5 else { return false }
        panelView.panelHeight = height
        return true
    }
}

// MARK: - PanelInputView

/// Sizes itself like ReplyKeyboardInputView, by an intrinsic height. A self-sizing input view keeps its frame's
/// width, so it starts at the window's width: a 320 pt frame left the panel's content in 320 of 402 pt, and a
/// flexible width doubled it as the host grew from zero.
private final class PanelInputView: UIInputView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: panelHeight)
    }

    var panelHeight: CGFloat {
        didSet { invalidateIntrinsicContentSize() }
    }

    init(size: CGSize) {
        self.panelHeight = size.height
        super.init(frame: CGRect(origin: .zero, size: size), inputViewStyle: .keyboard)
        allowsSelfSizing = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
