// UsagePieChartView.swift

import UIKit

// MARK: - UsagePieChartView

/// PieChartComponent: a 200 pt ring with a 100 pt hole, one section per item clockwise from the right, 2 pt apart,
/// each with its share in 16 pt rounded semibold white when it fits inside the section (pushed outward up to 65% of
/// the ring), and the total in 20 pt rounded bold in the middle. A change of items moves the sections over 0.4 s.
/// With nothing used the ring gives way to Telegram's empty "0 KB" in the accent colour, 100 pt tall.
final class UsagePieChartView: UIView {
    struct Item: Equatable {
        let id: String
        let fraction: CGFloat
        let color: UIColor
    }

    private struct Section {
        var start: CGFloat
        var end: CGFloat
        var color: UIColor
    }

    static let chartHeight: CGFloat = 200
    static let emptyHeight: CGFloat = 100

    private static let outerRadius: CGFloat = 100
    private static let innerRadius: CGFloat = 50
    private static let spacing: CGFloat = 2
    private static let labelFont = UIFont.rounded(size: 16, weight: .semibold)

    private(set) var isEmpty = true

    /// A view in the hole in place of the total, such as a chat's 72 pt avatar.
    var centerView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let centerView { addSubview(centerView) }
            totalLabel.isHidden = isEmpty || centerView != nil
            setNeedsLayout()
        }
    }

    var emptyColor = UIColor.tintColor {
        didSet {
            emptyValueLabel.textColor = emptyColor
            emptyUnitLabel.textColor = emptyColor
        }
    }

    private var items = [Item]()
    private var shapes = [String: CAShapeLayer]()
    private var labels = [String: UILabel]()
    private var from = [String: Section]()
    private var to = [String: Section]()
    private var animationStart: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private let totalLabel = UILabel()
    private let emptyValueLabel = UILabel()
    private let emptyUnitLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        totalLabel.font = .rounded(size: 20, weight: .bold)
        totalLabel.textColor = .label
        totalLabel.textAlignment = .center
        addSubview(totalLabel)
        emptyValueLabel.text = "0"
        emptyValueLabel.font = .systemFont(ofSize: 50, weight: UIFont.Weight(0.25))
        emptyValueLabel.textColor = .tintColor
        addSubview(emptyValueLabel)
        emptyUnitLabel.text = "KB"
        emptyUnitLabel.font = .rounded(size: 12, weight: .semibold)
        emptyUnitLabel.textColor = .tintColor
        addSubview(emptyUnitLabel)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: Self.chartHeight / 2)
        centerView?.frame = CGRect(x: center.x - 36, y: center.y - 36, width: 72, height: 72)
        let totalSize = totalLabel.sizeThatFits(CGSize(width: 90, height: 40))
        totalLabel.frame = CGRect(
            x: center.x - totalSize.width / 2, y: center.y - totalSize.height / 2,
            width: totalSize.width, height: totalSize.height,
        )
        let valueSize = emptyValueLabel.sizeThatFits(CGSize(width: 100, height: 100))
        emptyValueLabel.frame = CGRect(
            x: floor(bounds.midX - valueSize.width / 2), y: 16, width: valueSize.width, height: valueSize.height,
        )
        let unitSize = emptyUnitLabel.sizeThatFits(CGSize(width: 100, height: 100))
        emptyUnitLabel.frame = CGRect(
            x: emptyValueLabel.frame.maxX + 1, y: emptyValueLabel.frame.minY + 10,
            width: unitSize.width, height: unitSize.height,
        )
        render(progress: currentProgress())
    }

    /// The share as PieChartComponent writes it: tenths below whole numbers, "<0.1%" for less.
    static func fractionText(_ fraction: CGFloat) -> String {
        let value = floor(Double(fraction) * 1000) / 10
        if fraction == 0 { return "" }
        if value < 0.1 { return "<0.1%" }
        if abs(Double(Int(value)) - value) < 0.001 { return "\(Int(value))%" }
        return "\(value)%"
    }

    // MARK: Geometry

    /// The sections' angles: each item's share of the circle, from 0 clockwise.
    private static func sections(for items: [Item]) -> [String: Section] {
        var result = [String: Section]()
        var angle: CGFloat = 0
        for item in items {
            let value = item.fraction * .pi * 2
            result[item.id] = Section(start: angle, end: angle + value, color: item.color)
            angle += value
        }
        return result
    }

    /// The ring's slice between the angles, 2 pt from its neighbours at both radii.
    private static func path(for section: Section, center: CGPoint) -> CGPath {
        let value = section.end - section.start
        let full = abs(value - .pi * 2) <= 0.0001
        let innerSpacing = full ? 0 : spacing / innerRadius
        let outerSpacing = full ? 0 : spacing / outerRadius
        let innerStart = section.start + innerSpacing / 2
        let innerEnd = max(innerStart, section.end - innerSpacing / 2)
        let outerStart = section.start + outerSpacing / 2
        let outerEnd = max(outerStart, section.end - outerSpacing / 2)
        let path = CGMutablePath()
        path.addArc(center: center, radius: innerRadius, startAngle: innerEnd, endAngle: innerStart, clockwise: true)
        path.addArc(center: center, radius: outerRadius, startAngle: outerStart, endAngle: outerEnd, clockwise: false)
        path.closeSubpath()
        return path
    }

    /// updateLabel: the share at the section's middle angle, from halfway through the ring out to 65% of it, at the
    /// first distance where it fits between the circles and the section's edges; hidden when it fits nowhere.
    private static func place(_ label: UILabel, in section: Section, center: CGPoint, fullCircle: Bool) {
        let size = label.sizeThatFits(CGSize(width: 100, height: 100))
        let mid = (section.start + section.end) / 2
        let halfAngle = (section.end - section.start) / 2
        var fits = false
        var distance = innerRadius + (outerRadius - innerRadius) * 0.5
        for step in 0...10 {
            let offset = 0.5 + 0.15 * CGFloat(step) / 10
            distance = innerRadius + (outerRadius - innerRadius) * offset
            let halfDiagonal = hypot(size.width, size.height) / 2
            let radial = distance - halfDiagonal >= innerRadius - 2 && distance + halfDiagonal <= outerRadius + 2
            let angular = fullCircle || halfAngle >= .pi / 2 || sin(halfAngle) * distance >= halfDiagonal + 1
            if radial, angular {
                fits = true
                break
            }
        }
        label.bounds = CGRect(origin: .zero, size: size)
        label.center = CGPoint(x: center.x + cos(mid) * distance, y: center.y + sin(mid) * distance)
        label.alpha = fits ? 1 : 0
    }

    /// The items' shares of the whole, in order, and the total under them.
    func update(items: [Item], totalText: String?, animated: Bool) {
        let visible = items.filter { $0.fraction > 0 }
        isEmpty = visible.isEmpty
        totalLabel.text = totalText
        totalLabel.isHidden = isEmpty || centerView != nil
        centerView?.isHidden = isEmpty
        emptyValueLabel.isHidden = !isEmpty
        emptyUnitLabel.isHidden = !isEmpty
        let target = Self.sections(for: visible)
        // Each section starts from where it stands now, a new one from a sliver at its end.
        var start = [String: Section]()
        let progress = currentProgress()
        for item in visible {
            if let current = interpolated(item.id, progress: progress) {
                start[item.id] = current
            } else if let section = target[item.id] {
                start[item.id] = Section(start: section.end, end: section.end, color: section.color)
            }
        }
        for (id, section) in to where target[id] == nil {
            let current = interpolated(id, progress: progress) ?? section
            start[id] = current
        }
        var end = target
        for (id, section) in start where end[id] == nil {
            end[id] = Section(start: section.end, end: section.end, color: section.color)
        }
        self.items = visible
        from = start
        to = end
        for item in visible where labels[item.id] == nil {
            let label = UILabel()
            label.font = Self.labelFont
            label.textColor = .white
            addSubview(label)
            labels[item.id] = label
        }
        for item in visible {
            labels[item.id]?.text = Self.fractionText(item.fraction)
        }
        if animated, window != nil {
            animationStart = CACurrentMediaTime()
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(step))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else {
            animationStart = 0
            render(progress: 1)
        }
        setNeedsLayout()
    }

    // MARK: Animation

    @objc private func step() {
        let progress = currentProgress()
        render(progress: progress)
        if progress >= 1 {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func currentProgress() -> CGFloat {
        guard animationStart > 0 else { return 1 }
        let linear = min(1, max(0, (CACurrentMediaTime() - animationStart) / 0.4))
        // listViewAnimationCurveSystem's ease out.
        return CGFloat(1 - pow(1 - linear, 3))
    }

    private func interpolated(_ id: String, progress: CGFloat) -> Section? {
        guard let end = to[id] else { return nil }
        guard let start = from[id] else { return end }
        return Section(
            start: start.start + (end.start - start.start) * progress,
            end: start.end + (end.end - start.end) * progress,
            color: end.color,
        )
    }

    private func render(progress: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: Self.chartHeight / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var live = Set<String>()
        for (id, _) in to {
            guard let section = interpolated(id, progress: progress) else { continue }
            let visible = section.end - section.start > 0.0001
            if progress >= 1, !visible {
                continue
            }
            live.insert(id)
            let shape = shapes[id] ?? {
                let shape = CAShapeLayer()
                layer.insertSublayer(shape, at: 0)
                shapes[id] = shape
                return shape
            }()
            shape.fillColor = section.color.cgColor
            shape.path = Self.path(for: section, center: center)
            if let label = labels[id] {
                Self.place(
                    label,
                    in: section,
                    center: center,
                    fullCircle: section.end - section.start >= .pi * 2 - 0.001,
                )
                if progress < 1 {
                    label.alpha = min(label.alpha, 1)
                }
            }
        }
        for (id, shape) in shapes where !live.contains(id) {
            shape.removeFromSuperlayer()
            shapes[id] = nil
            labels[id]?.removeFromSuperview()
            labels[id] = nil
        }
        CATransaction.commit()
    }
}

// MARK: - UsageChartHeaderView

/// DataUsageScreen's and StorageUsageScreen's header: the ring, 23 pt to the title in 20 pt semibold, 6 pt to the
/// description in 13 pt, centred.
final class UsageChartHeaderView: UIView {
    private let chart = UsagePieChartView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let progressBackground = CALayer()
    private let progressForeground = CALayer()
    private var progress: CGFloat?

    /// See `UsagePieChartView.centerView`.
    var centerView: UIView? {
        get { chart.centerView }
        set { chart.centerView = newValue }
    }

    /// The empty ring's "0 KB" colour: the accent for network usage, green for cleared storage.
    var emptyColor: UIColor {
        get { chart.emptyColor }
        set { chart.emptyColor = newValue }
    }

    private var chartHeight: CGFloat {
        chart.isEmpty ? UsagePieChartView.emptyHeight : UsagePieChartView.chartHeight
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(chart)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        addSubview(descriptionLabel)
        progressBackground.cornerRadius = 2
        progressForeground.cornerRadius = 2
        layer.addSublayer(progressBackground)
        layer.addSublayer(progressForeground)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateProgressColors()
        }
        updateProgressColors()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateProgressColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        chart.frame = CGRect(x: 0, y: 8, width: bounds.width, height: chartHeight)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: bounds.width, height: 40))
        titleLabel.frame = CGRect(x: 0, y: chart.frame.maxY + 23, width: bounds.width, height: titleSize.height)
        let descriptionSize = descriptionLabel.sizeThatFits(CGSize(
            width: bounds.width - 62, height: .greatestFiniteMagnitude,
        ))
        descriptionLabel.frame = CGRect(
            x: 31, y: titleLabel.frame.maxY + 6, width: bounds.width - 62, height: descriptionSize.height,
        )
        // StorageUsageScreen's usage bar: 200 pt by 4 under the description, the share in the accent colour.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let progressWidth = min(200, bounds.width - 32)
        let progressFrame = CGRect(
            x: floor((bounds.width - progressWidth) / 2), y: descriptionLabel.frame.maxY + 8,
            width: progressWidth, height: 4,
        )
        progressBackground.frame = progressFrame
        progressForeground.frame = CGRect(
            origin: progressFrame.origin,
            size: CGSize(width: max(4, floor((progress ?? 0) * progressWidth)), height: 4),
        )
        progressBackground.isHidden = progress == nil
        progressForeground.isHidden = progress == nil
        CATransaction.commit()
    }

    func update(
        items: [UsagePieChartView.Item],
        totalText: String,
        title: String,
        description: String?,
        progress: CGFloat? = nil,
        animated: Bool,
    ) {
        self.progress = progress
        chart.update(items: items, totalText: totalText, animated: animated)
        titleLabel.text = title
        descriptionLabel.text = description
        setNeedsLayout()
    }

    func height(for width: CGFloat) -> CGFloat {
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: width, height: 40)).height
        let descriptionHeight = descriptionLabel.text == nil
            ? 0
            : descriptionLabel.sizeThatFits(CGSize(
                width: width - 62, height: .greatestFiniteMagnitude,
            ))
            .height
        let progressHeight: CGFloat = progress == nil ? 0 : 8 + 4 + 4
        return 8 + chartHeight + 23 + titleHeight + 6 + descriptionHeight + progressHeight + 20
    }

    private func updateProgressColors() {
        let accent = tintColor.resolvedColor(with: traitCollection)
        progressBackground.backgroundColor = accent.withAlphaComponent(0.2).cgColor
        progressForeground.backgroundColor = accent.cgColor
    }
}

extension UIFont {
    /// Telegram's `Font.with(design: .round)`.
    static func rounded(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
