// ComposerMediaInputViewController.swift

import UIKit

// MARK: - ComposerMediaInputViewController

/// Telegram's `.media` input mode (ChatEntityKeyboardInputNode): the emoji, sticker and GIF panel stands where the
/// system keyboard goes, as tall as the keyboard (`standardInputHeight`), and stays up after a sticker or GIF is
/// sent.
final class ComposerMediaInputViewController: UIInputViewController {
    let picker: ComposerMediaPickerViewController

    private var heightConstraint: NSLayoutConstraint?
    private var panelHeight: CGFloat

    init(picker: ComposerMediaPickerViewController, height: CGFloat) {
        self.picker = picker
        self.panelHeight = height
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let inputView = UIInputView(
            frame: CGRect(x: 0, y: 0, width: 320, height: panelHeight),
            inputViewStyle: .keyboard,
        )
        inputView.allowsSelfSizing = true
        self.inputView = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let height = view.heightAnchor.constraint(equalToConstant: panelHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height
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

    /// Follows the system keyboard's height for the current width; true when it changed.
    @discardableResult func setPanelHeight(_ height: CGFloat) -> Bool {
        guard abs(height - panelHeight) > 0.5 else { return false }
        panelHeight = height
        heightConstraint?.constant = height
        return true
    }
}
