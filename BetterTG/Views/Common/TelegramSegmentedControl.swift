// TelegramSegmentedControl.swift

import UIKit

/// Telegram SegmentControlComponent's iOS 26 branch. The host can fill a 44 pt navigation title slot while
/// the native control keeps its 36 pt geometry and UIKit's continuous touch/selection response.
final class TelegramSegmentedControl: UIView {
    private final class Control: UISegmentedControl {
        private var foregroundColor: UIColor {
            if traitCollection.userInterfaceStyle == .dark {
                UIColor.white.withAlphaComponent(0.36)
            } else {
                UIColor(white: 247 / 255, alpha: 1)
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            resetChrome()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            resetChrome()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            resetChrome()
        }

        /// Same guarded native hierarchy adaptation as Telegram: remove legacy image chrome and colour the
        /// selected loupe's plain backing views. UIKit still owns the live lens and gesture recognizers.
        func resetChrome() {
            for case let image as UIImageView in subviews {
                image.isHidden = true
            }
            guard let selector = subviews.last, let loupe = selector.subviews.first,
                  let content = loupe.subviews.first else { return }
            for view in content.subviews where type(of: view) == UIView.self {
                view.backgroundColor = foregroundColor
            }
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 300, height: 36) }

    var onSelection: ((Int) -> Void)?

    private let control: Control

    var selectedIndex: Int {
        get { control.selectedSegmentIndex }
        set { control.selectedSegmentIndex = newValue }
    }

    init(items: [String]) {
        self.control = Control(items: items)
        super.init(frame: .zero)
        addSubview(control)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (
            self: TelegramSegmentedControl,
            _: UITraitCollection,
        ) in
            self.updateAppearance()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        control.frame = CGRect(x: 0, y: floor((bounds.height - 36) / 2), width: bounds.width, height: 36)
    }

    private func updateAppearance() {
        let dark = traitCollection.userInterfaceStyle == .dark
        control.backgroundColor = dark ? UIColor.white.withAlphaComponent(0.11) : UIColor.black.withAlphaComponent(0.06)
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: dark ? UIColor.white : UIColor.black,
        ], for: .normal)
        control.resetChrome()
    }

    @objc private func selectionChanged() { onSelection?(selectedIndex) }
}
