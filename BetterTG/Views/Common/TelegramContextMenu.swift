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

enum TelegramContextMenuPresentationStyle: Equatable {
    case extracted
    case menuOnly
}

extension UIViewController {
    @discardableResult
    func presentTelegramContextMenu(
        sourceView: UIView,
        actions: [TelegramContextMenuAction],
        tracking gesture: UIGestureRecognizer? = nil,
        sourceBaseTransform: CGAffineTransform? = nil,
        performsInitialFeedback: Bool = true,
        presentationStyle: TelegramContextMenuPresentationStyle = .extracted,
    ) -> Bool {
        guard !actions.isEmpty, presentedViewController == nil else { return false }
        let controller = TelegramContextMenuController(
            sourceView: sourceView,
            actions: actions,
            trackingGesture: gesture,
            sourceTransform: sourceBaseTransform ?? sourceView.transform,
            presentationStyle: presentationStyle,
        )
        if performsInitialFeedback {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
            if presentationStyle == .extracted {
                UIView.animate(
                    withDuration: 0.12,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    sourceView.transform = sourceView.transform.scaledBy(x: 0.98, y: 0.98)
                }
            }
        }
        present(controller, animated: false)
        return true
    }
}

private final class TelegramContextMenuController: UIViewController {
    init(
        sourceView: UIView,
        actions: [TelegramContextMenuAction],
        trackingGesture: UIGestureRecognizer?,
        sourceTransform: CGAffineTransform,
        presentationStyle: TelegramContextMenuPresentationStyle,
    ) {
        self.sourceView = sourceView
        self.sourceTransform = sourceTransform
        self.actions = actions
        self.trackingGesture = trackingGesture
        self.presentationStyle = presentationStyle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
        trackingGesture?.addTarget(self, action: #selector(trackingGestureChanged(_:)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        trackingGesture?.removeTarget(self, action: #selector(trackingGestureChanged(_:)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateIn()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreviewAndMenu()
    }

    private weak var sourceView: UIView?
    private let sourceTransform: CGAffineTransform
    private let presentationStyle: TelegramContextMenuPresentationStyle
    private weak var trackingGesture: UIGestureRecognizer?
    private let actions: [TelegramContextMenuAction]
    private let backgroundEffectView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()
    private let previewContainer = UIView()
    private let menuEffectView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        return UIVisualEffectView(effect: effect)
    }()
    private let menuStack = UIStackView()
    private let selectionHighlightView = UIView()
    private var previewView: UIView?
    private var actionButtons = [TelegramContextMenuActionButton]()
    private weak var trackedButton: TelegramContextMenuActionButton?
    private var hasAnimatedIn = false
    private var isPerformingAction = false

    private func configureViews() {
        view.backgroundColor = .clear

        backgroundEffectView.frame = view.bounds
        backgroundEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundEffectView)

        dimView.frame = view.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.backgroundColor = presentationStyle == .extracted
            ? UIColor.black.withAlphaComponent(0.18)
            : .clear
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissMenu)))
        view.addSubview(dimView)

        previewContainer.layer.shadowColor = UIColor.black.cgColor
        previewContainer.layer.shadowOpacity = 0.24
        previewContainer.layer.shadowRadius = 24
        previewContainer.layer.shadowOffset = CGSize(width: 0, height: 10)
        previewContainer.alpha = 0
        view.addSubview(previewContainer)

        if presentationStyle == .extracted,
           let sourceView,
           let snapshot = sourceView.snapshotView(afterScreenUpdates: false)
        {
            snapshot.frame = previewContainer.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            previewContainer.addSubview(snapshot)
            previewView = snapshot
        }

        menuEffectView.layer.cornerRadius = 26
        menuEffectView.layer.cornerCurve = .continuous
        menuEffectView.cornerConfiguration = .corners(radius: 26)
        menuEffectView.clipsToBounds = true
        menuEffectView.alpha = 0
        view.addSubview(menuEffectView)

        selectionHighlightView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        selectionHighlightView.layer.cornerRadius = 20
        selectionHighlightView.layer.cornerCurve = .continuous
        selectionHighlightView.alpha = 0
        selectionHighlightView.isUserInteractionEnabled = false
        menuEffectView.contentView.addSubview(selectionHighlightView)

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

        menuSelectionGesture.minimumPressDuration = 0
        menuSelectionGesture.cancelsTouchesInView = true
        menuEffectView.addGestureRecognizer(menuSelectionGesture)

        for (index, action) in actions.enumerated() {
            if index > 0, action.startsNewSection {
                menuStack.addArrangedSubview(TelegramContextMenuSectionDivider())
            }
            let button = TelegramContextMenuActionButton(action: action)
            button.addTarget(self, action: #selector(actionPressed(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 52).isActive = true
            menuStack.addArrangedSubview(button)
            actionButtons.append(button)
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
            $0 + ($1.startsNewSection ? 9 : 0)
        }
        let menuHeight = CGFloat(actions.count) * 52 + separatorHeight
        let menuWidth = min(CGFloat(260), availableWidth)
        let menuX = sourceFrame.midX > view.bounds.midX
            ? view.bounds.width - horizontalInset - menuWidth
            : horizontalInset
        let anchorFrame = presentationStyle == .menuOnly ? sourceFrame : previewContainer.frame
        let spacing: CGFloat = presentationStyle == .menuOnly ? 4 : 10
        let belowY = anchorFrame.maxY + spacing
        let maximumY = view.bounds.height - max(view.safeAreaInsets.bottom, CGFloat(12)) - menuHeight
        let menuY = belowY <= maximumY
            ? belowY
            : max(verticalInset, anchorFrame.minY - spacing - menuHeight)
        menuEffectView.frame = CGRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
    }

    private func animateIn() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        if presentationStyle == .extracted {
            previewContainer.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
        menuEffectView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            if self.presentationStyle == .extracted {
                self.backgroundEffectView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            }
            self.dimView.alpha = 1
            if self.presentationStyle == .extracted {
                self.previewContainer.alpha = 1
                self.previewContainer.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
            }
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
            self.dismiss(animated: false) {
                if let sourceView = self.sourceView {
                    UIView.animate(
                        withDuration: 0.2,
                        delay: 0,
                        usingSpringWithDamping: 0.86,
                        initialSpringVelocity: 0,
                        options: [.allowUserInteraction, .beginFromCurrentState],
                    ) {
                        sourceView.transform = self.sourceTransform
                    }
                }
                completion?()
            }
        }
    }

    @objc private func dismissMenu() {
        dismissMenu(completion: nil)
    }

    @objc private func actionPressed(_ sender: TelegramContextMenuActionButton) {
        perform(sender)
    }

    private func perform(_ button: TelegramContextMenuActionButton) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        trackingGesture?.removeTarget(self, action: #selector(trackingGestureChanged(_:)))
        let handler = button.menuAction.handler
        dismissMenu(completion: handler)
    }

    @objc private func trackingGestureChanged(_ gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .changed:
            updateTrackedButton(at: gesture.location(in: view))
        case .ended:
            if let trackedButton {
                perform(trackedButton)
            }
        case .cancelled, .failed:
            updateTrackedButton(at: nil)
        default:
            break
        }
    }

    @objc private func menuSelectionGestureChanged(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            updateTrackedButton(at: gesture.location(in: view))
        case .ended:
            if let trackedButton {
                perform(trackedButton)
            } else {
                updateTrackedButton(at: nil)
            }
        case .cancelled, .failed:
            updateTrackedButton(at: nil)
        default:
            break
        }
    }

    private func updateTrackedButton(at location: CGPoint?) {
        let button = location.flatMap { point in
            actionButtons.first { $0.convert($0.bounds, to: view).contains(point) }
        }
        guard trackedButton !== button else { return }
        let previousButton = trackedButton
        trackedButton = button
        updateSelectionHighlight(from: previousButton, to: button)
        if button != nil, previousButton != nil {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func updateSelectionHighlight(
        from previousButton: TelegramContextMenuActionButton?,
        to button: TelegramContextMenuActionButton?,
    ) {
        menuEffectView.layoutIfNeeded()
        guard let button else {
            UIView.animate(
                withDuration: 0.08,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            ) {
                self.selectionHighlightView.alpha = 0
            }
            return
        }

        let targetFrame = button.convert(button.bounds.insetBy(dx: 6, dy: 4), to: menuEffectView.contentView)
        let crossesSectionDivider: Bool = {
            guard let previousButton,
                  let previousIndex = actionButtons.firstIndex(where: { $0 === previousButton }),
                  let nextIndex = actionButtons.firstIndex(where: { $0 === button })
            else { return false }
            let lower = min(previousIndex, nextIndex)
            let upper = max(previousIndex, nextIndex)
            guard lower != upper else { return false }
            return actions[(lower + 1) ... upper].contains(where: \.startsNewSection)
        }()

        if previousButton == nil || selectionHighlightView.alpha < 0.01 || crossesSectionDivider {
            let placeAndReveal = {
                self.selectionHighlightView.frame = targetFrame
                UIView.animate(
                    withDuration: 0.08,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    self.selectionHighlightView.alpha = 1
                }
            }
            if crossesSectionDivider, selectionHighlightView.alpha > 0.01 {
                UIView.animate(
                    withDuration: 0.06,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    self.selectionHighlightView.alpha = 0
                } completion: { _ in
                    placeAndReveal()
                }
            } else {
                placeAndReveal()
            }
        } else {
            UIView.animate(
                withDuration: 0.1,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
            ) {
                self.selectionHighlightView.frame = targetFrame
                self.selectionHighlightView.alpha = 1
            }
        }
    }

    private lazy var menuSelectionGesture = UILongPressGestureRecognizer(
        target: self,
        action: #selector(menuSelectionGestureChanged(_:)),
    )
}

private final class TelegramContextMenuSectionDivider: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 9).isActive = true

        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = UIColor.separator.withAlphaComponent(0.62)
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    private let titleLabel = UILabel()
    private let iconView = UIImageView()
}

/// Telegram's context gesture starts showing press progress before activation and
/// yields immediately to a real drag. This keeps scrolling responsive while making
/// a stationary hold feel immediate.
final class TelegramContextGestureRecognizer: UIGestureRecognizer {
    var onPressingChanged: ((Bool) -> Void)?
    var feedbackDelay: TimeInterval = 0.1
    var activationDelay: TimeInterval = 0.26
    var allowableMovement: CGFloat = 12

    override func reset() {
        super.reset()
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        feedbackWorkItem = nil
        activationWorkItem = nil
        initialLocation = nil
        feedbackStarted = false
        activated = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, let touch = touches.first, let view else {
            state = .failed
            return
        }
        initialLocation = touch.location(in: view)

        let feedback = DispatchWorkItem { [weak self] in
            guard let self, state == .possible else { return }
            feedbackStarted = true
            onPressingChanged?(true)
        }
        feedbackWorkItem = feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + feedbackDelay, execute: feedback)

        let activation = DispatchWorkItem { [weak self] in
            guard let self, state == .possible else { return }
            if !feedbackStarted {
                feedbackStarted = true
                onPressingChanged?(true)
            }
            activated = true
            cancelCompetingParentGestures()
            state = .began
        }
        activationWorkItem = activation
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay, execute: activation)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, let view, let initialLocation else { return }
        let location = touch.location(in: view)
        if state == .possible,
           hypot(location.x - initialLocation.x, location.y - initialLocation.y) > allowableMovement
        {
            cancelBeforeActivation()
        } else if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        if state == .began || state == .changed {
            state = .ended
        } else {
            cancelBeforeActivation()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        if state == .began || state == .changed {
            state = .cancelled
        } else {
            cancelBeforeActivation()
        }
    }

    private var feedbackWorkItem: DispatchWorkItem?
    private var activationWorkItem: DispatchWorkItem?
    private var initialLocation: CGPoint?
    private var feedbackStarted = false
    private var activated = false

    private func cancelCompetingParentGestures() {
        var ancestor = view
        while let currentView = ancestor {
            for gesture in currentView.gestureRecognizers ?? [] where gesture !== self {
                switch gesture.state {
                case .possible, .began, .changed:
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                default:
                    break
                }
            }
            ancestor = currentView.superview
        }
    }

    private func cancelBeforeActivation() {
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        if feedbackStarted, !activated {
            feedbackStarted = false
            onPressingChanged?(false)
        }
        state = .failed
    }
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
