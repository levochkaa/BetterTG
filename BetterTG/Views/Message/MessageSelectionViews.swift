// MessageSelectionViews.swift

import UIKit

// MARK: - MediaSelectionCheckView

/// CheckNode on an album item. `.overlay` (GridMessageSelectionNode) is a 28 pt circle 2 pt inside a photo's top
/// right corner, a 1.5 pt white ring with a soft shadow; `.plain` (FileMessageSelectionNode) is a 20 pt ring in the
/// bubble's placeholder color on a file icon's corner. Both fill with the accent and draw the check once selected.
final class MediaSelectionCheckView: UIView {
    enum Style {
        case overlay
        case plain

        var size: CGFloat {
            self == .overlay ? 28 : 20
        }
    }

    let style: Style
    private(set) var isSelected = false

    private let ringLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let checkLayer = CAShapeLayer()

    init(style: Style = .overlay) {
        self.style = style
        super.init(frame: CGRect(x: 0, y: 0, width: style.size, height: style.size))
        isUserInteractionEnabled = false
        ringLayer.fillColor = UIColor.clear.cgColor
        switch style {
        case .overlay:
            ringLayer.strokeColor = UIColor.white.cgColor
            ringLayer.lineWidth = 1.5
            ringLayer.shadowColor = UIColor.black.cgColor
            ringLayer.shadowOpacity = 0.22
            ringLayer.shadowRadius = 1.25
            ringLayer.shadowOffset = .zero
        case .plain:
            ringLayer.strokeColor = UIColor.secondaryLabel.cgColor
            ringLayer.lineWidth = 1.33
        }
        fillLayer.fillColor = UIColor.systemBlue.cgColor
        checkLayer.fillColor = UIColor.clear.cgColor
        checkLayer.strokeColor = UIColor.white.cgColor
        checkLayer.lineWidth = 1.5
        checkLayer.lineCap = .round
        checkLayer.lineJoin = .round
        for sublayer in [ringLayer, fillLayer, checkLayer] {
            layer.addSublayer(sublayer)
        }
        apply(selected: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = style == .overlay ? 2 - 1 / max(traitCollection.displayScale, 1) : 0
        let ringInset = inset + ringLayer.lineWidth / 2
        // The overlay fills inside its ring; the plain check fills over it.
        let fillInset = style == .overlay ? inset + ringLayer.lineWidth : 0
        for sublayer in [ringLayer, fillLayer, checkLayer] {
            sublayer.frame = bounds
        }
        ringLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: ringInset, dy: ringInset)).cgPath
        fillLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: fillInset, dy: fillInset)).cgPath
        // CheckNode's check, scaled to the size less the inset.
        let scale = (bounds.width - inset) / 18
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let start = CGPoint(x: center.x - (4 - 0.3333) * scale, y: center.y + 0.5 * scale)
        let corner = CGPoint(x: start.x + 2.5 * scale, y: start.y + 3 * scale)
        let check = UIBezierPath()
        check.move(to: start)
        check.addLine(to: corner)
        check.addLine(to: CGPoint(x: corner.x + 4.6667 * scale, y: corner.y - 6 * scale))
        checkLayer.path = check.cgPath
    }

    /// Fills and draws the check, or takes them away, over 0.2 s when animated.
    func setSelected(_ selected: Bool, animated: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        apply(selected: selected)
        CATransaction.commit()
    }

    /// GridMessageSelectionNode's 0.5 s spring in from 0.2 scale as selection starts.
    func animateIn() {
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    private func apply(selected: Bool) {
        fillLayer.transform = selected ? CATransform3DIdentity : CATransform3DMakeScale(0.001, 0.001, 1)
        checkLayer.strokeEnd = selected ? 1 : 0
    }
}

// MARK: - MessageSelectionIndicatorView

final class MessageSelectionIndicatorView: UIView {
    private let checkmarkView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .systemBackground
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 14
        layer.cornerCurve = .circular

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold),
        )
        checkmarkView.tintColor = .white
        addSubview(checkmarkView)
        NSLayoutConstraint.activate([
            checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 14),
            checkmarkView.heightAnchor.constraint(equalToConstant: 14),
        ])
        setSelected(false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        backgroundColor = selected ? .systemBlue : .systemBackground
        checkmarkView.isHidden = !selected
    }
}

// MARK: - MessageSelectionToolbar

final class MessageSelectionToolbar: UIView {
    static let contentHeight: CGFloat = 52

    var onDelete: (() -> Void)?
    var onForward: (() -> Void)?

    private let blurView = TelegramBarBackgroundView(edge: .bottom)
    private let deleteButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let forwardButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        selectedCount: Int,
        canDelete: Bool,
        canForward: Bool,
        isBusy: Bool = false,
    ) {
        countLabel.text = L10n.telegramPlural("Conversation.ForwardOptions.Title", count: selectedCount)
        deleteButton.isEnabled = canDelete && !isBusy
        forwardButton.isEnabled = canForward && !isBusy
        deleteButton.alpha = deleteButton.isEnabled ? 1 : 0.35
        forwardButton.alpha = forwardButton.isEnabled ? 1 : 0.35
        isUserInteractionEnabled = !isBusy
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setImage(
            UIImage(
                systemName: "trash",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular),
            ),
            for: .normal,
        )
        deleteButton.tintColor = .systemRed
        deleteButton.accessibilityLabel = L10n.betterTG("Accessibility.DeleteSelectedMessages")
        deleteButton.addTarget(self, action: #selector(deletePressed), for: .touchUpInside)
        addSubview(deleteButton)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.textAlignment = .center
        countLabel.textColor = .secondaryLabel
        countLabel.adjustsFontForContentSizeCategory = true
        addSubview(countLabel)

        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.setImage(
            UIImage(
                systemName: "arrowshape.turn.up.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular),
            ),
            for: .normal,
        )
        forwardButton.accessibilityLabel = L10n.betterTG("Accessibility.ForwardSelectedMessages")
        forwardButton.addTarget(self, action: #selector(forwardPressed), for: .touchUpInside)
        addSubview(forwardButton)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            deleteButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            deleteButton.topAnchor.constraint(equalTo: topAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 52),
            deleteButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            forwardButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            forwardButton.topAnchor.constraint(equalTo: topAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 52),
            forwardButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            countLabel.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: forwardButton.leadingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
        ])
    }

    @objc private func deletePressed() {
        onDelete?()
    }

    @objc private func forwardPressed() {
        onForward?()
    }
}
