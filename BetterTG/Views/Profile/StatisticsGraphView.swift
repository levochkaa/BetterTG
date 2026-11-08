// StatisticsGraphView.swift

import UIKit

// MARK: - StatisticsChartData

/// GraphCore's ChartsCollection: a statistical graph's JSON (columns, types, names, colors) as the x axis's dates and
/// a series per value column.
struct StatisticsChartData {
    struct Series {
        let name: String
        let color: UIColor
        let values: [Double]
    }

    /// Seconds since 1970, or an hour of the day for an hourly graph.
    let x: [Double]
    let series: [Series]

    /// The distance between two points, which is a bar's width.
    var step: Double {
        x.count > 1 ? x[1] - x[0] : (x.first ?? 0) < 24 ? 1 : 86400
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let columns = object["columns"] as? [[Any]],
              let types = object["types"] as? [String: String],
              let names = object["names"] as? [String: String],
              let colors = object["colors"] as? [String: String]
        else { return nil }
        var x = [Double]()
        var series = [Series]()
        for column in columns {
            guard let id = column.first as? String, let type = types[id] else { return nil }
            let values = column.dropFirst().compactMap(Self.double)
            guard values.count == column.count - 1 else { return nil }
            switch type {
            case "x":
                x = values.map { $0 < 24 ? $0 : $0 / 1000 }
            case "area",
                 "bar",
                 "line",
                 "step":
                guard let name = names[id], let hex = colors[id], let color = Self.color(hex) else { return nil }
                series.append(Series(name: name, color: color, values: values))
            default:
                return nil
            }
        }
        guard !x.isEmpty, !series.isEmpty, series.allSatisfy({ $0.values.count == x.count }) else { return nil }
        self.x = x
        self.series = series
    }

    private static func double(_ value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    /// GColor(hexString:): a colour name before the # wins, otherwise the six or eight hex digits after it.
    private static func color(_ string: String) -> UIColor? {
        let parts = string.components(separatedBy: "#")
        let named: [String: Int] = [
            "red": 0xFF3B30, "green": 0x34C759, "blue": 0x007AFF, "golden": 0xFFCC00, "yellow": 0xFFCC00,
            "lightgreen": 0x7ED321, "lightblue": 0x5AC8FA, "seablue": 0x35AFDC, "orange": 0xFF9500,
            "violet": 0xAF52DE, "emerald": 0x50E3C2, "pink": 0xFF2D55, "indigo": 0x5E5CE6,
        ]
        if let name = parts.first?.lowercased(), let rgb = named[name] {
            return UIColor(rgb: rgb)
        }
        guard let hex = parts.last, let value = UInt64(hex, radix: 16) else { return nil }
        switch hex.count {
        case 6:
            return UIColor(rgb: Int(value))
        case 8:
            return UIColor(
                red: CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue: CGFloat((value >> 8) & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255,
            )
        default:
            return nil
        }
    }
}

// MARK: - StatisticsGraphKind

/// StatsGraphItem's ChartType for the graphs a channel's statistics show.
enum StatisticsGraphKind {
    /// GeneralLinesChartController: followers and notifications.
    case lines
    /// StepBarsChartController(hourly: true): views by hour, with no range selector.
    case hourlyStep
    /// StackedBarsChartController: views and followers by source, reactions.
    case bars
    /// PercentPieChartController: languages.
    case pie
    /// TwoAxisStepBarsChartController: views and shares, each on its own axis.
    case twoAxisStep

    var isStep: Bool {
        self == .hourlyStep || self == .twoAxisStep
    }

    /// Bars fill the step before their point.
    var isBar: Bool {
        self != .lines && self != .pie
    }
}

// MARK: - StatisticsChartColors

/// PresentationThemeChart's day and night colours (ChartTheme(presentationTheme:)).
private enum StatisticsChartColors {
    static let labels = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(rgb: 0x8E8E93)
        : UIColor(rgb: 0x252529).withAlphaComponent(0.5)
    }

    static let lines = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(rgb: 0xD8D8D8).withAlphaComponent(0.35)
        : UIColor(rgb: 0x182D3B).withAlphaComponent(0.3)
    }

    static let rangeFrame = UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x6D6D72) : UIColor(rgb: 0xCAD4DE) }
    static let rangeTint = UIColor.systemGroupedBackground.withAlphaComponent(0.5)
}

// MARK: - StatisticsPlotView

/// GraphUI's ChartView with its renderers: the lines, steps, stacked bars or pie of the visible range, with
/// VerticalScalesRenderer's lines and values and HorizontalScalesRenderer's dates. The range selector's preview draws
/// the whole graph without scales.
private final class StatisticsPlotView: UIView {
    private enum Axis {
        /// Values on the left, in the labels' colour or the given one.
        case left(UIColor?)
        /// Values on the right in the given colour, with no lines.
        case right(UIColor)
    }

    private static let labelFont = UIFont.systemFont(ofSize: 11)

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .gmt
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .gmt
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let detailsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .gmt
        formatter.dateStyle = .medium
        return formatter
    }()

    let data: StatisticsChartData
    let kind: StatisticsGraphKind
    let isPreview: Bool
    var visible: [Bool] { didSet { setNeedsDisplay() } }
    var range: ClosedRange<Double> { didSet { setNeedsDisplay() } }
    /// The point the details show: its line and bullets, or its bar at full colour with the rest dimmed.
    var selectedIndex: Int? { didSet { setNeedsDisplay() } }

    /// A zoomable graph's details offer the day's hours (zoomToken); a zoomed one reads times.
    var onZoom: ((Double) -> Void)?
    var isZoomed = false

    /// LineBulletsRenderer's bullets for the selected point, gathered while the series draw.
    private var bullets = [(CGPoint, UIColor)]()

    private var ignoresTouch = false
    private let feedback = UISelectionFeedbackGenerator()
    private var isLoadingZoom = false

    private lazy var detailsView: StatisticsDetailsView = {
        let view = StatisticsDetailsView()
        view.onTap = { [weak self] in self?.hideDetails() }
        view.onZoom = { [weak self] in
            guard let self, let selectedIndex else { return }
            isLoadingZoom = true
            showDetails(selectedIndex)
            onZoom?(data.x[selectedIndex])
        }
        addSubview(view)
        return view
    }()

    /// ChartView's chartInsets; the preview fills its frame.
    private var chartFrame: CGRect {
        let insets = isPreview ? .zero : UIEdgeInsets(top: 40, left: 16, bottom: 35, right: 16)
        return bounds.inset(by: insets)
    }

    private var visibleSeries: [StatisticsChartData.Series] {
        zip(data.series, visible).filter(\.1).map(\.0)
    }

    /// The points LinesChartRenderer.LineData.verticalRange(calculatingRange:addBounds:) reads: the visible ones and
    /// one past each end. A bar is visible while its step is.
    private var visibleIndices: ClosedRange<Int> {
        let last = data.x.count - 1
        var lower = data.x.firstIndex { $0 > range.lowerBound } ?? last
        if kind == .lines {
            lower = max(0, lower - 1)
        }
        let upper = data.x.firstIndex { $0 >= range.upperBound } ?? last
        return lower...max(lower, upper)
    }

    /// PieChartComponentController.pieDataWithCurrentPreviewRange: each shown series' sum over the days after the
    /// range's start through its end.
    private var pieValues: [Double] {
        let indices = data.x.indices.filter { data.x[$0] > range.lowerBound + 1 && data.x[$0] <= range.upperBound }
        return data.series.enumerated().map { index, line in
            visible[index] ? indices.reduce(0) { $0 + line.values[$1] } : 0
        }
    }

    init(data: StatisticsChartData, kind: StatisticsGraphKind, range: ClosedRange<Double>, isPreview: Bool) {
        self.data = data
        self.kind = kind
        self.range = range
        self.isPreview = isPreview
        self.visible = data.series.map { _ in true }
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StatisticsPlotView, _) in
            view.setNeedsDisplay()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), chartFrame.width > 0, chartFrame.height > 0,
              range.upperBound > range.lowerBound
        else { return }
        bullets = []
        switch kind {
        case .lines:
            drawLines(context)
        case .hourlyStep:
            drawSteps(context, series: visibleSeries, axis: .left(nil))
        case .twoAxisStep:
            drawTwoAxisSteps(context)
        case .bars:
            drawBars(context)
        case .pie:
            if isPreview {
                drawPercentArea(context)
            } else {
                drawPie(context)
            }
        }
        if !isPreview, kind != .pie {
            drawDates()
            drawSelection(context)
        }
    }

    // MARK: Details

    /// ChartView's touches: a touch selects the nearest point and a drag follows it, with a tick on each new point;
    /// a touch while the details show hides them, as does a tap on the details.
    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard !isPreview, let point = touches.first?.location(in: self) else { return }
        // PieChartComponentController.chartInteractionDidBegin: a touch on a segment selects it.
        if kind == .pie {
            if let segment = pieSegment(at: point) {
                let wasShown = selectedIndex != nil
                selectedIndex = segment
                showDetails(segment)
                if !wasShown {
                    detailsView.alpha = 0
                    UIView.animate(withDuration: 0.2) { self.detailsView.alpha = 1 }
                }
            }
            return
        }
        if selectedIndex != nil {
            hideDetails()
            ignoresTouch = true
            return
        }
        select(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard !isPreview, kind != .pie, !ignoresTouch, let point = touches.first?.location(in: self) else { return }
        select(at: point)
    }

    override func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
        ignoresTouch = false
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        ignoresTouch = false
    }

    /// BaseConstants.detailsNumberFormatter: whole numbers with spaces between thousands.
    private static func detailsText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    /// ScalesNumberFormatter: millions as M and from ten thousand as K, with spaces between thousands.
    private static func scaleText(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumIntegerDigits = 1
        formatter.maximumFractionDigits = decimals
        let power = log10(value)
        let (scaled, suffix) = power >= 6 ? (value / 1_000_000, "M") : power >= 4 ? (value / 1000, "K") : (value, "")
        return (formatter.string(from: NSNumber(value: scaled)) ?? "") + suffix
    }

    /// findClosestDateTo for a touch's horizontal fraction of the chart; a bar answers for its whole step.
    func closestIndex(toFraction fraction: CGFloat) -> Int? {
        guard !data.x.isEmpty else { return nil }
        var value = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
        if kind.isBar {
            value += data.step / 2
        }
        return data.x.indices.min { abs(data.x[$0] - value) < abs(data.x[$1] - value) }
    }

    func hideDetails() {
        isLoadingZoom = false
        guard selectedIndex != nil else { return }
        selectedIndex = nil
        UIView.animate(withDuration: 0.2) { self.detailsView.alpha = 0 }
    }

    /// Refreshes the details for the shown series and range; a hidden pie segment loses its selection.
    func updateDetails() {
        guard let selectedIndex else { return }
        if kind == .pie, !visible[selectedIndex] {
            hideDetails()
            return
        }
        showDetails(selectedIndex)
    }

    /// VerticalLinesRenderer's line through the selected point and LineBulletsRenderer's bullets on it, over the
    /// scales. Stacked bars show their selection by colour alone.
    private func drawSelection(_ context: CGContext) {
        guard let selectedIndex, kind != .bars else { return }
        let x = xPosition(data.x[selectedIndex])
        context.setLineWidth(1 / max(1, traitCollection.displayScale))
        context.setStrokeColor(StatisticsChartColors.lines.cgColor)
        context.strokeLineSegments(between: [CGPoint(x: x, y: chartFrame.minY), CGPoint(x: x, y: chartFrame.maxY)])
        context.setLineWidth(2)
        for (point, color) in bullets {
            let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            context.setFillColor(UIColor.secondarySystemGroupedBackground.cgColor)
            context.setStrokeColor(color.cgColor)
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
        }
    }

    private func select(at point: CGPoint) {
        let fraction = (min(max(point.x, 0), bounds.width) - chartFrame.minX) / chartFrame.width
        guard let index = closestIndex(toFraction: fraction) else { return }
        if selectedIndex != nil, index != selectedIndex {
            feedback.selectionChanged()
        }
        let wasShown = selectedIndex != nil
        selectedIndex = index
        showDetails(index)
        if !wasShown {
            detailsView.alpha = 0
            UIView.animate(withDuration: 0.2) { self.detailsView.alpha = 1 }
        }
    }

    /// GeneralChartComponentController.chartDetailsViewModel: the day (or the hour) and each shown series' value in
    /// its colour, with stacked bars' Total; ChartView.detailsViewPosition puts it 8 pt right of the point, or left of
    /// it when it would cross the edge, 5 pt under the chart's top.
    private func showDetails(_ index: Int) {
        // chartDetailsViewModel(segmentInde:): the segment's name and sum with no title, a quarter of the way in.
        if kind == .pie {
            let line = data.series[index]
            detailsView.configure(
                title: "",
                rows: [(line.name, Self.detailsText(pieValues[index]), line.color)],
                total: nil,
            )
            let size = detailsView.size
            let position = chartFrame.width / 4
            detailsView.frame = CGRect(
                origin: CGPoint(x: max(8, min(position + 8, bounds.width - size.width - 8)), y: chartFrame.minY + 5),
                size: size,
            )
            return
        }
        let date = data.x[index]
        // chartDetailsViewModel: the time once zoomed, otherwise the day.
        let title = date <= 24
            ? "\(Int(date)):00"
            : (isZoomed ? Self.timeFormatter : Self.detailsDateFormatter)
                .string(from: Date(timeIntervalSince1970: date))
        let rows = data.series.enumerated().filter { visible[$0.offset] }.map { _, line in
            (line.name, Self.detailsText(line.values[index]), line.color)
        }
        var total: String?
        if kind == .bars, rows.count > 1 {
            let sum = data.series.enumerated().filter { visible[$0.offset] }.reduce(0) { $0 + $1.element.values[index] }
            total = Self.detailsText(sum)
        }
        detailsView.configure(
            title: title,
            rows: rows,
            total: total,
            showsArrow: onZoom != nil && !isZoomed,
            isLoading: isLoadingZoom,
        )
        let size = detailsView.size
        let position = xPosition(date)
        let x = size.width + 8 > position
            ? max(8, min(position + 8, bounds.width - size.width - 8))
            : max(8, min(position - size.width - 8, bounds.width - size.width - 8))
        detailsView.frame = CGRect(origin: CGPoint(x: x, y: chartFrame.minY + 5), size: size)
    }

    // MARK: Transforms

    private func xPosition(_ value: Double) -> CGFloat {
        chartFrame.minX + CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * chartFrame.width
    }

    private func yPosition(_ value: Double, in vertical: ClosedRange<Double>) -> CGFloat {
        let distance = vertical.upperBound - vertical.lowerBound
        guard distance > 0 else { return chartFrame.maxY }
        return chartFrame.maxY - CGFloat((value - vertical.lowerBound) / distance) * chartFrame.height
    }

    // MARK: Scales

    /// GeneralChartComponentController.verticalLimitsLabels: a step from 8, 5, 2.5, 2 or 1 times a power of ten that
    /// leaves about 85 pt between lines, from the multiple below the lowest value to the one above the highest.
    private func verticalLabels(for values: ClosedRange<Double>) -> (ClosedRange<Double>, [(Double, String)]) {
        let distance = values.upperBound - values.lowerBound
        guard distance > 0 else { return (0...1, []) }
        var perItem = distance / Double(chartFrame.height / 85)
        var multiplier = 1.0
        while perItem > 10 {
            perItem /= 10
            multiplier *= 10
        }
        var divisor = 1.0
        var decimals = 2
        while perItem < 1 {
            perItem *= 10
            divisor *= 10
            decimals += 1
        }
        let base = ([8, 5, 2.5, 2, 1].first { perItem > $0 } ?? 1) * multiplier / divisor
        var value = (values.lowerBound / base).rounded(.down) * base
        let lowerBound = value
        var labels = [(Double, String)]()
        while value < values.upperBound {
            labels.append((value, Self.scaleText(value, decimals: decimals)))
            value += base
        }
        return (lowerBound...value, labels)
    }

    /// VerticalScalesRenderer: the lines over the chart, the axis under it and each value above its line.
    private func drawVerticalScale(_ labels: [(Double, String)], range vertical: ClosedRange<Double>, axis: Axis) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let pixel = 1 / max(1, traitCollection.displayScale)
        if case .left = axis {
            context.setLineWidth(pixel)
            context.setStrokeColor(StatisticsChartColors.lines.cgColor)
            var segments = [CGPoint]()
            for (value, _) in labels {
                let y = yPosition(value, in: vertical)
                if y < chartFrame.maxY - 2 {
                    segments += [CGPoint(x: chartFrame.minX, y: y), CGPoint(x: chartFrame.maxX, y: y)]
                }
            }
            segments += [
                CGPoint(x: chartFrame.minX, y: chartFrame.maxY),
                CGPoint(x: chartFrame.maxX, y: chartFrame.maxY),
            ]
            context.strokeLineSegments(between: segments)
        }
        for (value, text) in labels {
            let color: UIColor =
                switch axis {
                case .left(let color): color ?? StatisticsChartColors.labels
                case .right(let color): color
                }
            let string = NSAttributedString(string: text, attributes: [.font: Self.labelFont, .foregroundColor: color])
            let y = yPosition(value, in: vertical) - Self.labelFont.pointSize - 6
            let x =
                if case .right = axis {
                    chartFrame.maxX - string.size().width
                } else {
                    chartFrame.minX
                }
            string.draw(at: CGPoint(x: x, y: y))
        }
    }

    /// HorizontalScalesRenderer with updateHorizontalLimitLabels' stride: every 2ⁿth point back from the last, at
    /// least 50 pt apart, as "MMM d" or an hour as "9:00", ending at its point.
    private func drawDates() {
        // ChartScaleType: days at least 50 pt apart as "MMM d", an hourly or five-minute graph's times 40 pt apart as
        // "HH:mm".
        let isTimed = data.step < 86400 && (data.x.first ?? 0) > 24
        let numberOfItems = (range.upperBound - range.lowerBound) / data.step
        let maximumNumberOfItems = Double(chartFrame.width / (isTimed ? 40 : 50))
        let tempStride = max(1, Int((numberOfItems / maximumNumberOfItems).rounded(.up)))
        var stride = 1
        while stride < tempStride {
            stride *= 2
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: StatisticsChartColors.labels,
        ]
        for index in Swift.stride(from: data.x.count - 1, through: 0, by: -stride) {
            let value = data.x[index]
            guard value > range.lowerBound else { break }
            let text = value <= 24
                ? "\(Int(value)):00"
                : (isTimed ? Self.timeFormatter : Self.dayFormatter).string(from: Date(timeIntervalSince1970: value))
            let string = NSAttributedString(string: text, attributes: attributes)
            let size = string.size()
            let x = xPosition(value) - size.width
            guard x < bounds.maxX else { continue }
            string.draw(at: CGPoint(x: x, y: chartFrame.maxY + 8))
        }
    }

    // MARK: Lines

    private func drawLines(_ context: CGContext) {
        let series = visibleSeries
        guard !series.isEmpty else { return }
        let indices = isPreview ? 0...data.x.count - 1 : visibleIndices
        let values = series.flatMap { $0.values[indices] }
        guard var lower = values.min(), var upper = values.max() else { return }
        if lower == upper {
            (lower, upper) = (0, upper * 2)
        }
        var vertical = lower...upper
        var labels = [(Double, String)]()
        if !isPreview {
            (vertical, labels) = verticalLabels(for: vertical)
        }
        // VerticalScalesRenderer draws over the chart.
        defer {
            if !isPreview {
                drawVerticalScale(labels, range: vertical, axis: .left(nil))
            }
        }
        context.setLineWidth(isPreview ? 1 : 2)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for line in series {
            context.setStrokeColor(line.color.cgColor)
            context.beginPath()
            for (index, value) in line.values.enumerated() {
                let point = CGPoint(x: xPosition(data.x[index]), y: yPosition(value, in: vertical))
                if index == 0 {
                    context.move(to: point)
                } else {
                    context.addLine(to: point)
                }
            }
            context.strokePath()
            if !isPreview, let selectedIndex {
                let point = CGPoint(
                    x: xPosition(data.x[selectedIndex]),
                    y: yPosition(line.values[selectedIndex], in: vertical),
                )
                bullets.append((point, line.color))
            }
        }
    }

    // MARK: Steps

    /// BarChartRenderer(step: true): each series as a line along its bars' tops.
    private func drawSteps(
        _ context: CGContext,
        series: [StatisticsChartData.Series],
        axis: Axis,
    ) {
        guard !series.isEmpty else { return }
        // The step before the visible ones shows in the margin, so the scale counts it too.
        let indices = isPreview
            ? 0...data.x.count - 1
            : max(0, visibleIndices.lowerBound - 1)...visibleIndices.upperBound
        let maximum = series.flatMap { $0.values[indices] }.max() ?? 0
        var vertical = 0...(maximum > 0 ? maximum : 1)
        var labels = [(Double, String)]()
        if !isPreview {
            (vertical, labels) = verticalLabels(for: vertical)
        }
        // VerticalScalesRenderer draws over the chart.
        defer {
            if !isPreview {
                drawVerticalScale(labels, range: vertical, axis: axis)
            }
        }
        context.setLineWidth(isPreview ? 1 : 2)
        context.setLineJoin(.miter)
        for line in series.reversed() {
            var points = [CGPoint]()
            for (index, value) in line.values.enumerated() {
                let y = yPosition(value, in: vertical)
                points.append(CGPoint(x: xPosition(data.x[index] - data.step), y: y))
                points.append(CGPoint(x: xPosition(data.x[index]), y: y))
            }
            context.setStrokeColor(line.color.cgColor)
            context.beginPath()
            context.addLines(between: points)
            context.strokePath()
            if !isPreview, let selectedIndex {
                let point = CGPoint(
                    x: xPosition(data.x[selectedIndex]),
                    y: yPosition(line.values[selectedIndex], in: vertical),
                )
                bullets.append((point, line.color))
            }
        }
    }

    /// TwoAxisStepBarsChartController: the first series on the left axis and the second on the right, each axis's
    /// values in its series' colour. The lines follow the left axis, or the right one while the first series is
    /// hidden.
    private func drawTwoAxisSteps(_ context: CGContext) {
        for (index, line) in data.series.enumerated() where visible[index] {
            let axis: Axis = index == 0 || !visible[0] ? .left(line.color) : .right(line.color)
            drawSteps(context, series: [line], axis: axis)
        }
    }

    // MARK: Bars

    /// BarChartRenderer: the visible series stacked in each bar.
    private func drawBars(_ context: CGContext) {
        let series = visibleSeries
        guard !series.isEmpty else { return }
        // The bar before the visible ones shows in the margin, so the scale counts it too.
        let indices = isPreview ? 0...data.x.count - 1 : visibleIndices
        let drawn = isPreview ? indices : max(0, indices.lowerBound - 1)...indices.upperBound
        let maximum = drawn.map { index in series.reduce(0) { $0 + $1.values[index] } }.max() ?? 0
        var vertical = 0...(maximum > 0 ? maximum : 1)
        var labels = [(Double, String)]()
        if !isPreview {
            (vertical, labels) = verticalLabels(for: vertical)
        }
        // VerticalScalesRenderer draws over the chart.
        defer {
            if !isPreview {
                drawVerticalScale(labels, range: vertical, axis: .left(nil))
            }
        }
        var rects = series.map { _ in [CGRect]() }
        var selectedRects = series.map { _ in [CGRect]() }
        for index in drawn {
            let left = xPosition(data.x[index] - data.step)
            let right = xPosition(data.x[index])
            var stacked = 0.0
            for (component, line) in series.enumerated() {
                let bottom = yPosition(stacked, in: vertical)
                stacked += line.values[index]
                let top = yPosition(stacked, in: vertical)
                let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                if !isPreview, index == selectedIndex {
                    selectedRects[component].append(rect)
                } else {
                    rects[component].append(rect)
                }
            }
        }
        // generalUnselectedAlpha: the other bars fade to half while one is selected.
        let alpha: CGFloat = !isPreview && selectedIndex != nil ? 0.5 : 1
        for (component, line) in series.enumerated() {
            context.setFillColor(line.color.withAlphaComponent(alpha).cgColor)
            context.fill(rects[component])
            context.setFillColor(line.color.cgColor)
            context.fill(selectedRects[component])
        }
    }

    // MARK: Pie

    /// PieChartRenderer: the visible days' shares from a third of a turn, each share of at least 1.5% labelled in
    /// white, the larger the share the larger and nearer the centre.
    private func drawPie(_ context: CGContext) {
        let values = pieValues
        let total = values.reduce(0, +)
        guard total > 0 else { return }
        let radius = min(chartFrame.width, chartFrame.height) / 2
        let diagramRadius = radius - radius / 15
        let maximumFontSize = radius / 7
        let formatter = NumberFormatter()
        var start = CGFloat.pi / 3
        for (index, value) in values.enumerated() where value > 0 {
            let percent = CGFloat(value / total)
            let size = 2 * .pi * percent
            let end = start + size
            // The selected segment stands out by the selection offset, unless it is the only one.
            let middleAngle = (start + end) / 2
            let offset = index == selectedIndex && values.count(where: { $0 > 0 }) > 1 ? radius / 15 : 0
            let center = CGPoint(
                x: chartFrame.midX + cos(middleAngle) * offset,
                y: chartFrame.midY + sin(middleAngle) * offset,
            )
            context.setFillColor(data.series[index].color.cgColor)
            context.move(to: center)
            context.addArc(center: center, radius: diagramRadius, startAngle: start, endAngle: end, clockwise: false)
            context.fillPath()
            if percent >= 0.015 {
                let fraction = min(1, max(0, size / (.pi / 4)))
                let fontSize = (4 + (maximumFontSize - 4) * fraction).rounded(.up)
                let offset = diagramRadius / 2 + diagramRadius / 2 * (1 - fraction)
                let text = NSAttributedString(
                    string: formatter.string(from: NSNumber(value: Double(percent * 100))) ?? "",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                        .foregroundColor: UIColor.white,
                    ],
                )
                let textSize = text.size()
                let middle = (start + end) / 2
                text.draw(at: CGPoint(
                    x: center.x + cos(middle) * offset - textSize.width / 2,
                    y: center.y + sin(middle) * offset - textSize.height / 2,
                ))
            }
            start = end
        }
    }

    /// PieChartRenderer.selectedItemIndex: the segment under a point within the radius.
    private func pieSegment(at point: CGPoint) -> Int? {
        let center = CGPoint(x: chartFrame.midX, y: chartFrame.midY)
        let radius = min(chartFrame.width, chartFrame.height) / 2
        guard hypot(point.x - center.x, point.y - center.y) <= radius else { return nil }
        let angle = atan2(center.y - point.y, center.x - point.x) + .pi
        let values = pieValues
        let total = values.reduce(0, +)
        guard total > 0 else { return nil }
        var start = CGFloat.pi / 3
        for (index, value) in values.enumerated() {
            let end = start + 2 * .pi * CGFloat(value / total)
            if angle >= start && angle <= end || angle + 2 * .pi >= start && angle + 2 * .pi <= end {
                return value > 0 ? index : nil
            }
            start = end
        }
        return nil
    }

    /// PercentChartRenderer: each day's shares stacked to the full height.
    private func drawPercentArea(_ context: CGContext) {
        let series = visibleSeries
        guard !series.isEmpty else { return }
        let totals = data.x.indices.map { index in series.reduce(0) { $0 + $1.values[index] } }
        var below = data.x.map { _ in 0.0 }
        for line in series {
            let above = data.x.indices.map { index in
                below[index] + (totals[index] > 0 ? line.values[index] / totals[index] : 0)
            }
            context.beginPath()
            for index in data.x.indices {
                let point = CGPoint(x: xPosition(data.x[index]), y: yPosition(above[index], in: 0...1))
                if index == 0 {
                    context.move(to: point)
                } else {
                    context.addLine(to: point)
                }
            }
            for index in data.x.indices.reversed() {
                context.addLine(to: CGPoint(x: xPosition(data.x[index]), y: yPosition(below[index], in: 0...1)))
            }
            context.closePath()
            context.setFillColor(line.color.cgColor)
            context.fillPath()
            below = above
        }
    }
}

// MARK: - StatisticsDetailsView

/// GraphUI's ChartDetailsView: the day in bold, then each series' name and its value in the series' colour, and
/// Total for stacked bars, on PresentationThemeChart's details colour with 5 pt corners. A tap hides it; with the
/// arrow of a zoomable graph a tap zooms into the day instead, the arrow turning into an activity indicator meanwhile.
private final class StatisticsDetailsView: UIView {
    private static let background = UIColor { $0.userInterfaceStyle == .dark ? .black : UIColor(rgb: 0xF5F5FB) }
    private static let text = UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(rgb: 0x6D6D72) }
    private static let arrowColor = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(rgb: 0xD8D8D8)
        : UIColor(rgb: 0xC5C7CD)
    }

    var onTap: (() -> Void)?
    var onZoom: (() -> Void)?
    private(set) var size = CGSize.zero

    private let titleLabel = UILabel()
    private var labels = [UILabel]()
    private let arrowView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var showsArrow = false

    init() {
        super.init(frame: .zero)
        backgroundColor = Self.background
        layer.cornerRadius = 5
        clipsToBounds = true
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = Self.text
        addSubview(titleLabel)
        // Chart/arrow_right: a 6 by 10 pt chevron.
        arrowView.image = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 10))
            .image { context in
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: 5, y: 5))
                path.addLine(to: CGPoint(x: 1, y: 9))
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor.black.setStroke()
                path.stroke()
                _ = context
            }
            .withRenderingMode(.alwaysTemplate)
        arrowView.tintColor = Self.arrowColor
        addSubview(arrowView)
        activityIndicator.color = Self.arrowColor
        activityIndicator.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// ChartDetailsView.setup: 10 pt margins, 110 pt for a name and 70 pt for its value, 18 pt rows.
    func configure(
        title: String,
        rows: [(String, String, UIColor)],
        total: String?,
        showsArrow: Bool = false,
        isLoading: Bool = false,
    ) {
        labels.forEach { $0.removeFromSuperview() }
        labels = []
        let width: CGFloat = 10 * 2 + 110 + 70
        self.showsArrow = showsArrow && !isLoading
        arrowView.isHidden = !self.showsArrow
        arrowView.frame = CGRect(x: width - 6 - 10, y: 10 + 2, width: 6, height: 10)
        activityIndicator.center = CGPoint(x: width - 3 - 10, y: 16)
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        isUserInteractionEnabled = !isLoading
        titleLabel.text = title
        titleLabel.isHidden = title.isEmpty
        titleLabel.frame = CGRect(x: 10, y: 8, width: width, height: 18)
        var y: CGFloat = title.isEmpty ? 8 : 8 + 18
        func addRow(_ name: String, _ value: String, _ color: UIColor, wraps: Bool) {
            let nameLabel = UILabel()
            nameLabel.font = .systemFont(ofSize: 12)
            nameLabel.textColor = Self.text
            nameLabel.numberOfLines = wraps ? 2 : 1
            nameLabel.text = name
            var nameSize = nameLabel.sizeThatFits(CGSize(width: 110, height: CGFloat.greatestFiniteMagnitude))
            nameSize.height = ceil(wraps ? nameSize.height : 18)
            nameLabel.frame = CGRect(
                x: 10,
                y: y + (wraps ? 2 : 0),
                width: min(110, nameSize.width),
                height: nameSize.height,
            )
            let valueLabel = UILabel()
            valueLabel.font = .systemFont(ofSize: 12, weight: .bold)
            valueLabel.textColor = color
            valueLabel.textAlignment = .right
            valueLabel.text = value
            valueLabel.frame = CGRect(x: 10 + 110, y: y, width: 70, height: 18)
            for label in [nameLabel, valueLabel] {
                addSubview(label)
                labels.append(label)
            }
            y += wraps ? nameSize.height + 4 : 18
        }
        for (name, value, color) in rows {
            addRow(name, value, color, wraps: true)
        }
        if let total {
            addRow(L10n.telegram("Stats.Total"), total, Self.text, wraps: false)
        }
        size = CGSize(width: width, height: y + 8)
    }

    @objc private func handleTap() {
        if showsArrow {
            onZoom?()
        } else {
            onTap?()
        }
    }
}

// MARK: - StatisticsRangeView

/// GraphUI's RangeChartView: the whole graph under a crop frame whose handles and middle drag the visible range, with
/// the rest tinted. A tap beside the frame centres it there.
private final class StatisticsRangeView: UIView, UIGestureRecognizerDelegate {
    private enum Marker {
        case lower
        case upper
        case center
    }

    let preview: StatisticsPlotView
    var fraction: ClosedRange<CGFloat> = 0.8...1 { didSet { setNeedsLayout() } }
    var onChange: ((ClosedRange<CGFloat>) -> Void)?

    private let lowerTint = UIView()
    private let upperTint = UIView()
    private let cropView = UIImageView()
    private let minimumDistance: CGFloat
    private var marker: Marker?
    private var markerOffset: CGFloat = 0

    private var contentFrame: CGRect {
        bounds.inset(by: UIEdgeInsets(top: 1, left: 16, bottom: 1, right: 16))
    }

    init(preview: StatisticsPlotView, minimumDistance: CGFloat) {
        self.preview = preview
        self.minimumDistance = minimumDistance
        super.init(frame: .zero)
        addSubview(preview)
        for tint in [lowerTint, upperTint] {
            tint.backgroundColor = StatisticsChartColors.rangeTint
            tint.isUserInteractionEnabled = false
            addSubview(tint)
        }
        addSubview(cropView)
        updateCropImage()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StatisticsRangeView, _) in
            view.updateCropImage()
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let content = contentFrame
        preview.frame = content
        let lower = location(fraction.lowerBound)
        let upper = location(fraction.upperBound)
        cropView.frame = CGRect(x: lower, y: content.minY - 1, width: upper - lower, height: content.height + 2)
        lowerTint.frame = CGRect(
            x: content.minX,
            y: content.minY,
            width: max(0, lower - content.minX + 10),
            height: content.height,
        )
        upperTint.frame = CGRect(
            x: upper - 10,
            y: content.minY,
            width: max(0, content.maxX - upper + 10),
            height: content.height,
        )
        lowerTint.layer.cornerRadius = 5
        lowerTint.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        upperTint.layer.cornerRadius = 5
        upperTint.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    /// The pan takes horizontal drags only, so the list still scrolls over the graph.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    private func location(_ value: CGFloat) -> CGFloat {
        contentFrame.minX + value * contentFrame.width
    }

    /// ChartTheme(presentationTheme:)'s rangeCropImage: 11 pt handles with chevrons joined by hairlines.
    private func updateCropImage() {
        let frameColor = StatisticsChartColors.rangeFrame.resolvedColor(with: traitCollection)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 114, height: 42)).image { renderer in
            let context = renderer.cgContext
            context.setFillColor(frameColor.cgColor)
            UIBezierPath(
                roundedRect: CGRect(x: 0, y: 0, width: 11, height: 42),
                byRoundingCorners: [.topLeft, .bottomLeft],
                cornerRadii: CGSize(width: 6, height: 6),
            ).fill()
            UIBezierPath(
                roundedRect: CGRect(x: 103, y: 0, width: 11, height: 42),
                byRoundingCorners: [.topRight, .bottomRight],
                cornerRadii: CGSize(width: 6, height: 6),
            ).fill()
            context.fill([
                CGRect(x: 7, y: 0, width: 100, height: 1),
                CGRect(x: 7, y: 41, width: 100, height: 1),
            ])
            context.setLineCap(.round)
            context.setLineWidth(1.5)
            context.setStrokeColor(UIColor.white.cgColor)
            context.addLines(between: [CGPoint(x: 7, y: 17), CGPoint(x: 4, y: 21), CGPoint(x: 7, y: 25)])
            context.addLines(between: [CGPoint(x: 107, y: 17), CGPoint(x: 110, y: 21), CGPoint(x: 107, y: 25)])
            context.strokePath()
        }
        cropView.image = image.resizableImage(
            withCapInsets: UIEdgeInsets(top: 15, left: 11, bottom: 15, right: 11),
            resizingMode: .stretch,
        )
    }

    /// RangeChartView.touchesBegan: a handle within 25 pt, else the middle.
    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: self)
        switch pan.state {
        case .began:
            let start = CGPoint(x: point.x - pan.translation(in: self).x, y: point.y)
            let lower = location(fraction.lowerBound)
            let upper = location(fraction.upperBound)
            if abs(upper - start.x + 12.5) < 25 {
                marker = .upper
                markerOffset = start.x - upper
            } else if abs(lower - start.x - 12.5) < 25 {
                marker = .lower
                markerOffset = start.x - lower
            } else if start.x > lower, start.x < upper {
                marker = .center
                markerOffset = start.x - lower
            } else {
                marker = nil
            }
        case .changed:
            guard let marker else { return }
            let content = contentFrame
            let value = (point.x - markerOffset - content.minX) / content.width
            switch marker {
            case .lower:
                setFraction(min(max(0, value), fraction.upperBound - minimumDistance)...fraction.upperBound)
            case .upper:
                setFraction(fraction.lowerBound...max(min(1, value), fraction.lowerBound + minimumDistance))
            case .center:
                let distance = fraction.upperBound - fraction.lowerBound
                let lower = min(max(0, value), 1 - distance)
                setFraction(lower...lower + distance)
            }
        default:
            marker = nil
        }
    }

    @objc private func handleTap(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: self)
        guard point.x < location(fraction.lowerBound) || point.x > location(fraction.upperBound) else { return }
        let distance = fraction.upperBound - fraction.lowerBound
        let center = (point.x - contentFrame.minX) / contentFrame.width
        let lower = min(max(0, center - distance / 2), 1 - distance)
        setFraction(lower...lower + distance)
    }

    private func setFraction(_ value: ClosedRange<CGFloat>) {
        guard value != fraction else { return }
        fraction = value
        onChange?(value)
    }
}

// MARK: - StatisticsVisibilityView

/// GraphUI's ChartVisibilityView: a chip per series, filled with a check while it shows and outlined while hidden. The
/// last shown series shakes instead of hiding, and a hold shows only its series, or all of them again.
private final class StatisticsVisibilityView: UIView {
    private static let font = UIFont.systemFont(ofSize: 14, weight: .medium)

    private(set) var selection: [Bool]
    var onChange: (([Bool]) -> Void)?

    private let series: [StatisticsChartData.Series]
    private var buttons = [UIButton]()

    init(series: [StatisticsChartData.Series], selection: [Bool]? = nil) {
        self.series = series
        self.selection = selection ?? series.map { _ in true }
        super.init(frame: .zero)
        for (index, _) in series.enumerated() {
            let button = UIButton(type: .custom)
            button.titleLabel?.font = Self.font
            button.layer.cornerRadius = 15
            button.layer.masksToBounds = true
            button.addAction(UIAction { [weak self] _ in self?.toggle(index) }, for: .touchUpInside)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
            button.addGestureRecognizer(hold)
            button.tag = index
            buttons.append(button)
            addSubview(button)
        }
        updateStyles()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StatisticsVisibilityView, _) in
            view.updateStyles()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (button, frame) in zip(buttons, Self.frames(width: bounds.width, series: series)) {
            button.frame = frame
        }
    }

    /// generateItemsFrames: rows of 30 pt chips 8 pt apart, each its title plus 40 pt, inset 16 pt.
    static func frames(width: CGFloat, series: [StatisticsChartData.Series]) -> [CGRect] {
        var origin = CGPoint(x: 16, y: 0)
        var frames = [CGRect]()
        for line in series {
            let chipWidth = ((line.name as NSString).size(withAttributes: [.font: font]).width + 40).rounded(.up)
            if origin.x + chipWidth >= width - 32, origin.x > 16 {
                origin = CGPoint(x: 16, y: origin.y + 38)
            }
            frames.append(CGRect(origin: origin, size: CGSize(width: chipWidth, height: 30)))
            origin.x += chipWidth + 8
        }
        return frames
    }

    /// calculateVisibilityHeight: the chips and 16 pt under them, with no chips for a single series.
    static func height(width: CGFloat, series: [StatisticsChartData.Series]) -> CGFloat {
        guard series.count > 1, let last = frames(width: width, series: series).last else { return 0 }
        return last.maxY + 16
    }

    private func updateStyles() {
        for (index, button) in buttons.enumerated() {
            let color = series[index].color
            if selection[index] {
                button.backgroundColor = color
                button.layer.borderWidth = 0
                button.setTitle("✓ " + series[index].name, for: .normal)
                button.setTitleColor(.white, for: .normal)
            } else {
                button.backgroundColor = .clear
                button.layer.borderWidth = 1
                button.layer.borderColor = color.cgColor
                button.setTitle(series[index].name, for: .normal)
                button.setTitleColor(color, for: .normal)
            }
        }
    }

    private func toggle(_ index: Int) {
        if selection[index], selection.count(where: { $0 }) == 1 {
            let shake = CAKeyframeAnimation(keyPath: "position.x")
            shake.values = [0, -6, 6, -4, 4, 0]
            shake.duration = 0.3
            shake.isAdditive = true
            buttons[index].layer.add(shake, forKey: "shake")
            return
        }
        selection[index].toggle()
        changed()
    }

    @objc private func handleHold(_ hold: UILongPressGestureRecognizer) {
        guard hold.state == .began, let index = hold.view?.tag else { return }
        let othersShown = selection.enumerated().contains { $0.element && $0.offset != index }
        selection = selection.indices.map { othersShown ? $0 == index : true }
        changed()
    }

    private func changed() {
        UIView.animate(withDuration: 0.2) { self.updateStyles() }
        onChange?(selection)
    }
}

// MARK: - StatisticsGraphView

/// StatsGraphItem's node with ChartStackSection: the visible range's dates over the graph, the range selector and the
/// series' chips; while the graph loads an activity indicator, and the server's text when it can't be drawn.
final class StatisticsGraphView: UIView {
    enum State {
        case loading
        case failed(String)
        case loaded(StatisticsChartData)
    }

    /// getStatisticalGraph with the graph's zoomToken: the hours around a day, for a two-axis graph.
    var zoomLoader: ((Double) async -> StatisticsChartData?)? {
        didSet {
            if kind == .twoAxisStep, case .loaded(let data) = state {
                setUp(data)
            }
        }
    }

    private let kind: StatisticsGraphKind
    private let state: State
    private let titleLabel = UILabel()
    /// ChartStackSection's back button: Zoom Out with a chevron, the title moving 36 pt aside for it.
    private let zoomOutButton = UIButton(type: .system)
    private var zoomedOutFraction: ClosedRange<CGFloat>?
    private var selection: [Bool]?
    private var plot: StatisticsPlotView?
    private var rangeView: StatisticsRangeView?
    private var visibilityView: StatisticsVisibilityView?
    private var totalRange: ClosedRange<Double> = 0...1

    /// The data the graph shows now: the zoomed hours or the original days.
    private var currentData: StatisticsChartData?

    private var displaysRange: Bool {
        kind != .hourlyStep
    }

    init(kind: StatisticsGraphKind, state: State) {
        self.kind = kind
        self.state = state
        super.init(frame: .zero)
        clipsToBounds = true
        switch state {
        case .loading:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            addCentered(indicator)
        case .failed(let text):
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 16)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            addCentered(label)
        case .loaded(let data):
            setUp(data)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// ChartStackSection.layoutSubviews under StatsGraphItem's 8 pt: the title 5 pt down, the 310 pt graph, the 42 pt
    /// range selector and the chips 16 pt under it; the hourly graph stands 40 pt higher, its title out of sight.
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let top: CGFloat = kind == .hourlyStep ? -32 : 8
        let titleInset: CGFloat = zoomOutButton.isHidden ? 0 : 36
        titleLabel.frame = CGRect(x: titleInset, y: top + 5, width: width - titleInset, height: 28)
        zoomOutButton.frame = CGRect(x: 8, y: top, width: 96, height: 38)
        plot?.frame = CGRect(x: 0, y: top, width: width, height: 310)
        rangeView?.frame = CGRect(x: 0, y: top + 310, width: width, height: 42)
        visibilityView?.frame = CGRect(
            x: 0,
            y: top + (displaysRange ? 368 : 326),
            width: width,
            height: bounds.height - top - (displaysRange ? 368 : 326),
        )
    }

    /// StatsGraphItem's height: 361 pt and 15 pt of padding, 82 pt less for the hourly graph, which has no range
    /// selector and no title, plus the chips.
    static func height(width: CGFloat, kind: StatisticsGraphKind, state: State) -> CGFloat {
        guard case .loaded(let data) = state else { return 376 }
        return (kind == .hourlyStep ? 294 : 376) + StatisticsVisibilityView.height(width: width, series: data.series)
    }

    private func addCentered(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerXAnchor),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
        ])
    }

    private func setUp(_ data: StatisticsChartData, zoomedRange: ClosedRange<Double>? = nil) {
        plot?.removeFromSuperview()
        rangeView?.removeFromSuperview()
        visibilityView?.removeFromSuperview()
        rangeView = nil
        visibilityView = nil
        let lower = kind.isBar ? data.x[0] - data.step : data.x[0]
        totalRange = lower...max(lower + data.step, data.x[data.x.count - 1])
        var initial: ClosedRange<CGFloat> = displaysRange ? zoomedOutFraction ?? 0.8...1 : 0...1
        if let zoomedRange {
            let distance = totalRange.upperBound - totalRange.lowerBound
            let lowerFraction = CGFloat((zoomedRange.lowerBound - totalRange.lowerBound) / distance)
            let upperFraction = CGFloat((zoomedRange.upperBound - totalRange.lowerBound) / distance)
            initial = max(0, min(lowerFraction, 1))...max(0, min(max(upperFraction, lowerFraction), 1))
        }
        let plot = StatisticsPlotView(data: data, kind: kind, range: range(for: initial), isPreview: false)
        plot.isZoomed = zoomedRange != nil
        if let zoomLoader, zoomedRange == nil {
            plot.onZoom = { [weak self] date in
                Task { @MainActor [weak self] in
                    guard let zoomed = await zoomLoader(date), let self else {
                        self?.plot?.hideDetails()
                        return
                    }
                    zoomIn(zoomed, date: date)
                }
            }
        }
        if let selection {
            plot.visible = selection
        }
        insertSubview(plot, at: 0)
        self.plot = plot
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.isHidden = !displaysRange
        addSubview(titleLabel)
        zoomOutButton.isHidden = zoomedRange == nil
        if zoomOutButton.superview == nil {
            var configuration = UIButton.Configuration.plain()
            configuration.title = L10n.telegram("Stats.ZoomOut")
            configuration.image = UIImage(
                systemName: "chevron.left",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            )
            configuration.imagePadding = 3
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 14)
                return attributes
            }
            zoomOutButton.configuration = configuration
            zoomOutButton.contentHorizontalAlignment = .leading
            zoomOutButton.addAction(UIAction { [weak self] _ in self?.zoomOut() }, for: .touchUpInside)
            addSubview(zoomOutButton)
        }
        if displaysRange {
            let preview = StatisticsPlotView(data: data, kind: kind, range: totalRange, isPreview: true)
            if let selection {
                preview.visible = selection
            }
            let step = CGFloat(data.step / (totalRange.upperBound - totalRange.lowerBound))
            let rangeView = StatisticsRangeView(preview: preview, minimumDistance: max(0.1, step))
            rangeView.fraction = initial
            rangeView.onChange = { [weak self] fraction in self?.updateRange(fraction) }
            addSubview(rangeView)
            self.rangeView = rangeView
        }
        if data.series.count > 1 {
            let visibilityView = StatisticsVisibilityView(series: data.series, selection: selection)
            visibilityView.onChange = { [weak self] selection in
                self?.selection = selection
                self?.plot?.visible = selection
                self?.plot?.updateDetails()
                self?.rangeView?.preview.visible = selection
            }
            addSubview(visibilityView)
            self.visibilityView = visibilityView
        }
        currentData = data
        updateTitle()
        setNeedsLayout()
    }

    /// BaseLinesChartController.didTapZoomIn: the loaded hours from the day's start to its last hour.
    private func zoomIn(_ zoomed: StatisticsChartData, date: Double) {
        guard case .loaded = state, let rangeView, zoomedOutFraction == nil else { return }
        zoomedOutFraction = rangeView.fraction
        let start = max(date, zoomed.x.first ?? date)
        let end = min(date + 86400 - 3600, zoomed.x.last ?? date)
        setUp(zoomed, zoomedRange: (kind.isBar ? start - zoomed.step : start)...max(start, end))
    }

    /// didTapZoomOut: back to the days at the range they showed.
    private func zoomOut() {
        guard case .loaded(let data) = state, zoomedOutFraction != nil else { return }
        setUp(data)
        zoomedOutFraction = nil
    }

    private func range(for fraction: ClosedRange<CGFloat>) -> ClosedRange<Double> {
        let distance = totalRange.upperBound - totalRange.lowerBound
        return totalRange.lowerBound + Double(fraction.lowerBound) * distance
            ... totalRange.lowerBound + Double(fraction.upperBound) * distance
    }

    private func updateRange(_ fraction: ClosedRange<CGFloat>) {
        // updateChartRange cancels the interaction; a pie keeps its segment with the new sum.
        if kind != .pie {
            plot?.hideDetails()
        }
        plot?.range = range(for: fraction)
        if kind == .pie {
            plot?.updateDetails()
        }
        updateTitle()
    }

    /// GeneralChartComponentController.updateChartRangeTitle: the first and last visible days in the medium style, or
    /// one day in the full style. A bar's day is its point, and a pie counts the days after the range's start.
    private func updateTitle() {
        guard let plot, let data = currentData else { return }
        let from = Date(timeIntervalSince1970: plot.range.lowerBound + (kind.isBar || kind == .pie ? data.step : 0) + 1)
        let to = Date(timeIntervalSince1970: plot.range.upperBound)
        let formatter = DateFormatter()
        formatter.timeZone = .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        if calendar.isDate(from, inSameDayAs: to) {
            formatter.dateStyle = .full
            titleLabel.text = formatter.string(from: from)
        } else {
            formatter.dateStyle = .medium
            titleLabel.text = "\(formatter.string(from: from)) - \(formatter.string(from: to))"
        }
    }
}
