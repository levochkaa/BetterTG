// SecretMediaTimerView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - SelfDestructDeadlines

/// When each opened self-destructing message expires, on the uptime clock. TDLib reports the time left
/// (`Message.selfDestructIn`) only in a message it returns, so the first deadline learned for a message stays, and its
/// bubble and preview count down to the same moment (Telegram's `countdownBeginTime`).
@MainActor enum SelfDestructDeadlines {
    struct Key: Hashable {
        let clientID: Int32
        let chatID: Int64
        let messageID: Int64

        init(clientID: Int32, message: Message) {
            self.clientID = clientID
            self.chatID = message.chatId
            self.messageID = message.id
        }
    }

    static let changed = PassthroughSubject<Key, Never>()

    private static var deadlines = [Key: TimeInterval]()

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The known deadline, or one taken from a message whose timer already runs.
    static func deadline(clientID: Int32, message: Message) -> TimeInterval? {
        let key = Key(clientID: clientID, message: message)
        if let deadline = deadlines[key] { return deadline }
        guard message.selfDestructIn.isFinite, message.selfDestructIn > 0 else { return nil }
        let deadline = now + message.selfDestructIn
        deadlines[key] = deadline
        return deadline
    }

    /// The preview learns the deadline from TDLib right after it opens the message.
    static func record(_ deadline: TimeInterval, clientID: Int32, message: Message) {
        let key = Key(clientID: clientID, message: message)
        let current = now
        deadlines = deadlines.filter { $0.value > current - 60 }
        deadlines[key] = deadline
        changed.send(key)
    }
}

// MARK: - SecretMediaTimerView

/// Telegram's RadialStatusNode secret states: a flame in a dark circle before the media is opened
/// (`staticTimeout`), the flame inside the ring of the time left once its countdown runs (`secretTimeout`), or the
/// view-once mark in a dashed ring.
final class SecretMediaTimerView: UIView {
    // MARK: Internal

    enum Icon { case flame, viewOnce }

    struct Countdown: Equatable {
        let deadline: TimeInterval
        let timeout: TimeInterval
    }

    override var intrinsicContentSize: CGSize { CGSize(width: diameter, height: diameter) }

    // MARK: Private

    private let diameter: CGFloat
    private let iconView = UIImageView()
    private let onceLabel = UILabel()
    private let ringLayer = CAShapeLayer()
    private var icon = Icon.flame
    private var countdown: Countdown?

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        isUserInteractionEnabled = false
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: diameter * 0.4,
            weight: .semibold,
        )
        iconView.image = UIImage(systemName: "flame.fill")
        addSubview(iconView)
        onceLabel.text = "1"
        onceLabel.textColor = .white
        onceLabel.textAlignment = .center
        onceLabel.font = UIFont.systemFont(ofSize: diameter * 0.45, weight: .bold).rounded
        onceLabel.isHidden = true
        addSubview(onceLabel)
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = UIColor.white.cgColor
        ringLayer.lineWidth = diameter > 32 ? 2 : 1.5
        ringLayer.lineCap = .round
        ringLayer.isHidden = true
        layer.addSublayer(ringLayer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        iconView.frame = bounds
        onceLabel.frame = bounds
        let inset = diameter > 32 ? 4.0 : 3.0
        // Clockwise from the top, so the ring empties toward twelve o'clock as in RadialStatusNode.
        ringLayer.frame = bounds
        ringLayer.path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: max(0, bounds.width / 2 - inset),
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true,
        ).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyCountdown()
    }

    func configure(icon: Icon, countdown: Countdown?) {
        guard icon != self.icon || countdown != self.countdown || ringLayer.animation(forKey: "countdown") == nil
        else { return }
        self.icon = icon
        self.countdown = countdown
        iconView.isHidden = icon == .viewOnce
        onceLabel.isHidden = icon != .viewOnce
        applyCountdown()
    }

    private func applyCountdown() {
        ringLayer.removeAnimation(forKey: "countdown")
        if icon == .viewOnce {
            ringLayer.isHidden = false
            ringLayer.lineDashPattern = [NSNumber(value: Double(diameter) / 9), NSNumber(value: Double(diameter) / 14)]
            ringLayer.strokeEnd = 1
            return
        }
        ringLayer.lineDashPattern = nil
        guard let countdown, countdown.timeout > 0 else {
            ringLayer.isHidden = true
            return
        }
        let remaining = max(0, countdown.deadline - SelfDestructDeadlines.now)
        ringLayer.isHidden = false
        ringLayer.strokeEnd = 0
        guard remaining > 0, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = min(1, remaining / countdown.timeout)
        animation.toValue = 0
        animation.duration = remaining
        ringLayer.add(animation, forKey: "countdown")
    }
}

// MARK: - SecretMediaBadgeView

/// Telegram's secret media badge in the bubble's top-left corner: "1" for view-once media, or the seconds left.
final class SecretMediaBadgeView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        isUserInteractionEnabled = false
        iconView.tintColor = .white
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        label.textColor = .white
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func configure(isViewOnce: Bool, text: String) {
        iconView.image = UIImage(systemName: isViewOnce ? "circle.dashed" : "flame.fill")
        label.text = text
    }
}

private extension UIFont {
    var rounded: UIFont {
        fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}
