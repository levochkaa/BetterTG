// TelegramContextMenu.swift

import UIKit

struct TelegramContextMenuAction {
    let title: String
    let image: UIImage?
    let isDestructive: Bool
    let startsNewSection: Bool
    let handler: () -> Void

    init(
        title: String,
        image: UIImage? = nil,
        isDestructive: Bool = false,
        startsNewSection: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.image = image
        self.isDestructive = isDestructive
        self.startsNewSection = startsNewSection
        self.handler = handler
    }
}

extension UIViewController {
    func presentTelegramContextMenu(sourceView: UIView, actions: [TelegramContextMenuAction]) {
        guard !actions.isEmpty, presentedViewController == nil else { return }
        let controller = TelegramContextMenuController(sourceView: sourceView, actions: actions)
        present(controller, animated: false)
    }
}

private final class TelegramContextMenuController: UIViewController {
    init(sourceView: UIView, actions: [TelegramContextMenuAction]) {
        self.sourceView = sourceView
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        animateIn()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreviewAndMenu()
    }

    private weak var sourceView: UIView?
    private let actions: [TelegramContextMenuAction]
    private let backgroundEffectView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()
    private let previewContainer = UIView()
    private let menuEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let menuStack = UIStackView()
    private var previewView: UIView?
    private var hasAnimatedIn = false

    private func configureViews() {
        view.backgroundColor = .clear

        backgroundEffectView.frame = view.bounds
        backgroundEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundEffectView)

        dimView.frame = view.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissMenu)))
        view.addSubview(dimView)

        previewContainer.layer.shadowColor = UIColor.black.cgColor
        previewContainer.layer.shadowOpacity = 0.24
        previewContainer.layer.shadowRadius = 24
        previewContainer.layer.shadowOffset = CGSize(width: 0, height: 10)
        previewContainer.alpha = 0
        view.addSubview(previewContainer)

        if let sourceView, let snapshot = sourceView.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = previewContainer.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            previewContainer.addSubview(snapshot)
            previewView = snapshot
        }

        menuEffectView.layer.cornerRadius = 14
        menuEffectView.layer.cornerCurve = .continuous
        menuEffectView.clipsToBounds = true
        menuEffectView.alpha = 0
        view.addSubview(menuEffectView)

        menuStack.axis = .vertical
        menuStack.alignment = .fill
        menuStack.translatesAutoresizingMaskIntoConstraints = false
        menuEffectView.contentView.addSubview(menuStack)
        NSLayoutConstraint.activate([
            menuStack.topAnchor.constraint(equalTo: menuEffectView.contentView.topAnchor),
            menuStack.leadingAnchor.constraint(equalTo: menuEffectView.contentView.leadingAnchor),
            menuStack.trailingAnchor.constraint(equalTo: menuEffectView.contentView.trailingAnchor),
            menuStack.bottomAnchor.constraint(equalTo: menuEffectView.contentView.bottomAnchor),
        ])

        for (index, action) in actions.enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = action.startsNewSection
                    ? UIColor.separator.withAlphaComponent(0.9)
                    : UIColor.separator.withAlphaComponent(0.55)
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: action.startsNewSection ? 7 : 1 / traitCollection.displayScale)
                    .isActive = true
                menuStack.addArrangedSubview(separator)
            }
            let button = TelegramContextMenuActionButton(action: action)
            button.addTarget(self, action: #selector(actionPressed(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 50).isActive = true
            menuStack.addArrangedSubview(button)
        }
    }

    private func layoutPreviewAndMenu() {
        guard let sourceView, let window = sourceView.window else { return }
        let sourceFrameInWindow = sourceView.convert(sourceView.bounds, to: window)
        let sourceFrame = window.convert(sourceFrameInWindow, to: view)
        let horizontalInset: CGFloat = 12
        let verticalInset = max(view.safeAreaInsets.top, CGFloat(12))
        let availableWidth = view.bounds.width - horizontalInset * 2
        let previewWidth = min(sourceFrame.width, availableWidth)
        let previewX = min(max(horizontalInset, sourceFrame.minX), view.bounds.width - horizontalInset - previewWidth)
        let previewHeight = min(sourceFrame.height, view.bounds.height * 0.45)
        let previewY = min(max(verticalInset, sourceFrame.midY - previewHeight / 2), view.bounds.height - verticalInset - previewHeight)
        previewContainer.frame = CGRect(x: previewX, y: previewY, width: previewWidth, height: previewHeight)
        previewView?.frame = previewContainer.bounds

        let separatorHeight = actions.dropFirst().reduce(CGFloat.zero) {
            $0 + ($1.startsNewSection ? 7 : 1 / traitCollection.displayScale)
        }
        let menuHeight = CGFloat(actions.count) * 50 + separatorHeight
        let menuWidth = min(CGFloat(260), availableWidth)
        let menuX = sourceFrame.midX > view.bounds.midX
            ? view.bounds.width - horizontalInset - menuWidth
            : horizontalInset
        let spacing: CGFloat = 10
        let belowY = previewContainer.frame.maxY + spacing
        let maximumY = view.bounds.height - max(view.safeAreaInsets.bottom, CGFloat(12)) - menuHeight
        let menuY = belowY <= maximumY
            ? belowY
            : max(verticalInset, previewContainer.frame.minY - spacing - menuHeight)
        menuEffectView.frame = CGRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
    }

    private func animateIn() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        previewContainer.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        menuEffectView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.backgroundEffectView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            self.dimView.alpha = 1
            self.previewContainer.alpha = 1
            self.previewContainer.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
            self.menuEffectView.alpha = 1
            self.menuEffectView.transform = .identity
        }
    }

    private func dismissMenu(completion: (() -> Void)? = nil) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
        ) {
            self.backgroundEffectView.effect = nil
            self.dimView.alpha = 0
            self.previewContainer.alpha = 0
            self.previewContainer.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            self.menuEffectView.alpha = 0
            self.menuEffectView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }

    @objc private func dismissMenu() {
        dismissMenu(completion: nil)
    }

    @objc private func actionPressed(_ sender: TelegramContextMenuActionButton) {
        let handler = sender.menuAction.handler
        dismissMenu(completion: handler)
    }
}

private final class TelegramContextMenuActionButton: UIControl {
    let menuAction: TelegramContextMenuAction

    init(action: TelegramContextMenuAction) {
        menuAction = action
        super.init(frame: .zero)

        let color: UIColor = action.isDestructive ? .systemRed : .label
        titleLabel.text = action.title
        titleLabel.textColor = color
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        iconView.image = action.image
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: iconView.leadingAnchor, constant: -12),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
        ])
        accessibilityLabel = action.title
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.white.withAlphaComponent(0.09) : .clear }
    }

    private let titleLabel = UILabel()
    private let iconView = UIImageView()
}

extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
