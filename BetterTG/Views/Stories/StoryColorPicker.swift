// StoryColorPicker.swift

import UIKit

// MARK: - StoryColorPickerViewController

/// ColorPickerScreen: a dark sheet with Close and Color, the Grid, Spectrum and Sliders tabs over a field of 12 by 10
/// squares, OPACITY with its slider and percentage, then the colour's preview beside five palette swatches. Every
/// change
/// reaches `onChange` at once, as ColorPickerScreen's `updated` does.
final class StoryColorPickerViewController: UIViewController, UIGestureRecognizerDelegate {
    private enum Mode: Int {
        case grid
        case spectrum
        case sliders
    }

    private static let sideInset: CGFloat = 16
    private static let palette: [UInt32] = [0x000000, 0x0161FD, 0x32C759, 0xFFCC02, 0xFF3A30]

    var onChange: ((UIColor) -> Void)?
    var onDismiss: (() -> Void)?

    private var color: UIColor
    /// Where the spectrum's knob stands, while the colour came from the spectrum.
    private var spectrumPosition: CGPoint?
    private var mode = Mode.grid
    private var keyboardHeight: CGFloat = 0

    private let closeGlass = UIVisualEffectView()
    private let titleLabel = UILabel()
    private let modeControl = UISegmentedControl()
    private let gridView = StoryColorGridView()
    private let spectrumView = StoryColorSpectrumView()
    private let slidersView = StoryColorSlidersView()
    private let opacityTitle = UILabel()
    private let opacitySlider = StoryColorSlider()
    private let opacityField = StoryColorField(suffix: "%")
    private let divider = UIView()
    private let preview = StoryColorPreview()
    private var swatches = [StoryPaletteSwatch]()

    private var topOfField: CGFloat {
        76 + modeControl.intrinsicContentSize.height + 20
    }

    private var bottomInset: CGFloat {
        let safeBottom = view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom
        return safeBottom > 0 ? safeBottom + 5 : 12
    }

    init(color: UIColor) {
        self.color = color
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        // The sheet's dark blur: set before presenting so the sheet's own glass takes it too.
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let closeEffect = UIGlassEffect(style: .regular)
        closeEffect.isInteractive = true
        closeGlass.effect = closeEffect
        closeGlass.cornerConfiguration = .capsule()
        closeGlass.clipsToBounds = true
        let close = UIButton(type: .system)
        close.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
            ),
            for: .normal,
        )
        close.tintColor = .white
        close.accessibilityLabel = L10n.telegram("Common.Close")
        close.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        closeGlass.contentView.addSubview(close)
        view.addSubview(closeGlass)
        titleLabel.text = L10n.telegram("Paint.ColorTitle")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        for (index, key) in ["Paint.ColorGrid", "Paint.ColorSpectrum", "Paint.ColorSliders"].enumerated() {
            modeControl.insertSegment(withTitle: L10n.telegram(key), at: index, animated: false)
        }
        modeControl.selectedSegmentIndex = 0
        modeControl.backgroundColor = UIColor(white: 1, alpha: 0.07)
        modeControl.addAction(UIAction { [weak self] _ in
            guard let self, let mode = Mode(rawValue: modeControl.selectedSegmentIndex) else { return }
            self.mode = mode
            update(animated: true)
        }, for: .valueChanged)
        view.addSubview(modeControl)
        gridView.onSelect = { [weak self] color in self?.setColor(color, keepAlpha: true) }
        spectrumView.onSelect = { [weak self] color, position in
            self?.setColor(color, keepAlpha: true, spectrumPosition: position)
        }
        slidersView.onChange = { [weak self] color in self?.setColor(color, keepAlpha: true) }
        for field in [gridView, spectrumView, slidersView] as [UIView] {
            view.addSubview(field)
        }
        opacityTitle.text = L10n.telegram("Paint.ColorOpacity").uppercased()
        opacityTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        opacityTitle.textColor = UIColor(red: 0x9B / 255, green: 0x9D / 255, blue: 0xA5 / 255, alpha: 1)
        view.addSubview(opacityTitle)
        opacitySlider.onChange = { [weak self] value in self?.setAlpha(value) }
        view.addSubview(opacitySlider)
        opacityField.isValid = { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty || (Int(value).map { (0...100).contains($0) } ?? false)
        }
        opacityField.onChange = { [weak self] value in self?.setAlpha(CGFloat(Int(value) ?? 0) / 100) }
        view.addSubview(opacityField)
        divider.backgroundColor = UIColor(red: 0x48 / 255, green: 0x48 / 255, blue: 0x4A / 255, alpha: 1)
        view.addSubview(divider)
        view.addSubview(preview)
        swatches = Self.palette.map { rgb in
            let swatch = StoryPaletteSwatch(color: StoryColorPickerViewController.color(rgb))
            swatch.addAction(UIAction { [weak self] _ in
                self?.setColor(StoryColorPickerViewController.color(rgb), keepAlpha: false)
            }, for: .touchUpInside)
            view.addSubview(swatch)
            return swatch
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
        configureSheet()
        update(animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        onDismiss?()
        onDismiss = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout()
    }

    static func rgb(_ color: UIColor) -> UInt32 {
        let (red, green, blue, _) = components(color)
        return UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
    }

    // MARK: Colour

    private static func color(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1,
        )
    }

    private static func components(_ color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            color.getWhite(&white, alpha: &alpha)
            (red, green, blue) = (white, white, white)
        }
        return (red, green, blue, alpha)
    }

    // MARK: Layout

    /// The field's width, narrower where a width-sized field would make the sheet taller than the screen, so its
    /// squares stay square (iPhone Duo's folded screen).
    private func fieldWidth(for width: CGFloat) -> CGFloat {
        var fieldWidth = width - view.safeAreaInsets.left - view.safeAreaInsets.right - Self.sideInset * 2
        let screenHeight = view.window?.bounds.height ?? presentingViewController?.view.bounds.height ?? view.bounds
            .height
        let maxContentHeight = screenHeight - 6 - (view.window?.safeAreaInsets.top ?? 0)
        let belowField: CGFloat = 21 + 16 + 8 + 36 + 24 + 1 + 22 + 82 + 10 + bottomInset
        let squareLimit = ((maxContentHeight - topOfField - belowField) / 10).rounded(.down)
        if squareLimit > 0, squareLimit < (fieldWidth / 12).rounded(.down) {
            fieldWidth = squareLimit * 12
        }
        return fieldWidth
    }

    /// ColorPickerContent's height: the rows down to the swatches, then the bottom inset, or the keyboard less 120 pt.
    private func contentHeight(for width: CGFloat) -> CGFloat {
        let squareSize = (fieldWidth(for: width) / 12).rounded(.down)
        var height = topOfField + squareSize * 10 + 21 + ceil(opacityTitle.font.lineHeight) + 8 + 36 + 24 + 1 + 22
            + 82 + 10
        height += keyboardHeight > 0 ? max(bottomInset, keyboardHeight - 120) : bottomInset
        return height
    }

    /// The rows keep to the band between the side insets (iPhone Duo's strip beside its folded screen).
    private func layout() {
        let band = view.bounds.inset(by: UIEdgeInsets(
            top: 0,
            left: view.safeAreaInsets.left,
            bottom: 0,
            right: view.safeAreaInsets.right,
        ))
        let width = band.width
        let inset = band.minX + Self.sideInset
        let right = band.maxX - Self.sideInset
        closeGlass.frame = CGRect(x: inset, y: 16, width: 44, height: 44)
        titleLabel.frame = CGRect(x: band.minX + 50, y: 16, width: width - 100, height: 44)
        let modeHeight = modeControl.intrinsicContentSize.height
        modeControl.frame = CGRect(x: inset, y: 76, width: right - inset, height: modeHeight)
        var y = topOfField
        let fieldWidth = fieldWidth(for: view.bounds.width)
        let squareSize = (fieldWidth / 12).rounded(.down)
        let fieldFrame = CGRect(x: band.midX - fieldWidth / 2, y: y, width: fieldWidth, height: squareSize * 10)
        gridView.frame = fieldFrame
        spectrumView.frame = fieldFrame
        slidersView.frame = fieldFrame
        y += fieldFrame.height + 21
        let titleHeight = ceil(opacityTitle.font.lineHeight)
        opacityTitle.frame = CGRect(x: inset + 5, y: y, width: right - inset, height: titleHeight)
        y += titleHeight + 8
        opacitySlider.frame = CGRect(x: inset, y: y, width: right - inset - 89, height: 36)
        opacityField.frame = CGRect(x: right - 77, y: y, width: 77, height: 36)
        y += 36 + 24
        divider.frame = CGRect(x: inset, y: y - 0.5, width: right - inset, height: 1)
        y += 1 + 22
        preview.frame = CGRect(x: inset, y: y, width: 82, height: 82)
        var x = inset + 82 + 38
        for swatch in swatches {
            swatch.frame = CGRect(x: x - 15, y: y, width: 30, height: 30)
            x += 30 + 20
        }
    }

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.custom(identifier: .init("content")) { [weak self] context in
            guard let self else { return context.maximumDetentValue }
            let safeBottom = view.window?.safeAreaInsets.bottom ?? 0
            return min(context.maximumDetentValue, contentHeight(for: view.bounds.width) - safeBottom)
        }]
        // SheetComponent's dark blur: the sheet's glass takes the presentation's style, not the content's.
        sheet.traitOverrides.userInterfaceStyle = .dark
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = 38
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = view.window
        else { return }
        let height = max(0, window.bounds.height - frame.minY)
        guard height != keyboardHeight else { return }
        keyboardHeight = height
        sheetPresentationController?.animateChanges {
            sheetPresentationController?.invalidateDetents()
        }
    }

    /// updateColor: a colour from the grid, spectrum or sliders keeps the opacity; a swatch brings its own.
    private func setColor(_ newColor: UIColor, keepAlpha: Bool, spectrumPosition: CGPoint? = nil) {
        let alpha = Self.components(color).alpha
        color = keepAlpha ? newColor.withAlphaComponent(alpha) : newColor
        self.spectrumPosition = spectrumPosition
        onChange?(color)
        update(animated: false)
    }

    private func setAlpha(_ alpha: CGFloat) {
        color = color.withAlphaComponent(max(0, min(1, alpha)))
        onChange?(color)
        update(animated: false)
    }

    private func update(animated: Bool) {
        let (red, green, blue, alpha) = Self.components(color)
        let opaque = UIColor(red: red, green: green, blue: blue, alpha: 1)
        let changes = {
            self.gridView.alpha = self.mode == .grid ? 1 : 0
            self.spectrumView.alpha = self.mode == .spectrum ? 1 : 0
            self.slidersView.alpha = self.mode == .sliders ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
        gridView.isUserInteractionEnabled = mode == .grid
        spectrumView.isUserInteractionEnabled = mode == .spectrum
        slidersView.isUserInteractionEnabled = mode == .sliders
        gridView.selectedRGB = Self.rgb(opaque)
        spectrumView.setKnob(at: spectrumPosition, color: color)
        slidersView.update(color: color)
        opacitySlider.update(
            left: opaque.withAlphaComponent(0),
            right: opaque,
            current: color,
            value: alpha,
        )
        opacityField.setText("\(Int(alpha * 100))")
        preview.color = color
        for (swatch, rgb) in zip(swatches, Self.palette) {
            swatch.isSelected = Self.rgb(color) == rgb && alpha == 1
        }
    }
}

// MARK: - StoryColorGridView

/// ColorGridComponent: Telegram's 120 colours as 12 by 10 squares in a 10 pt round field; a touch or a drag picks the
/// square under the finger, which takes a 3 pt ring, white on a dark colour and 0x1a1a1c on a light one, rounded 10 pt
/// at the field's corners and 2 pt elsewhere.
private final class StoryColorGridView: UIView, UIGestureRecognizerDelegate {
    static let colors: [UInt32] = [
        0xFFFFFF, 0xEBEBEB, 0xD6D6D6, 0xC2C2C2, 0xADADAD, 0x999999, 0x858585, 0x707070, 0x5C5C5C, 0x474747, 0x333333,
        0x000000,
        0x00374A, 0x011D57, 0x11053B, 0x2E063D, 0x3C071B, 0x5C0701, 0x5A1C00, 0x583300, 0x563D00, 0x666100, 0x4F5504,
        0x263E0F,
        0x004D65, 0x012F7B, 0x1A0A52, 0x450D59, 0x551029, 0x831100, 0x7B2900, 0x7A4A00, 0x785800, 0x8D8602, 0x6F760A,
        0x38571A,
        0x016E8F, 0x0042A9, 0x2C0977, 0x61187C, 0x791A3D, 0xB51A00, 0xAD3E00, 0xA96800, 0xA67B01, 0xC4BC00, 0x9BA50E,
        0x4E7A27,
        0x008CB4, 0x0056D6, 0x371A94, 0x7A219E, 0x99244F, 0xE22400, 0xDA5100, 0xD38301, 0xD19D01, 0xF5EC00, 0xC3D117,
        0x669D34,
        0x00A1D8, 0x0061FE, 0x4D22B2, 0x982ABC, 0xB92D5D, 0xFF4015, 0xFF6A00, 0xFFAB01, 0xFDC700, 0xFEFB41, 0xD9EC37,
        0x76BB40,
        0x01C7FC, 0x3A87FE, 0x5E30EB, 0xBE38F3, 0xE63B7A, 0xFF6250, 0xFF8648, 0xFEB43F, 0xFECB3E, 0xFFF76B, 0xE4EF65,
        0x96D35F,
        0x52D6FC, 0x74A7FF, 0x864FFE, 0xD357FE, 0xEE719E, 0xFF8C82, 0xFFA57D, 0xFFC777, 0xFFD977, 0xFFF994, 0xEAF28F,
        0xB1DD8B,
        0x93E3FD, 0xA7C6FF, 0xB18CFE, 0xE292FE, 0xF4A4C0, 0xFFB5AF, 0xFFC5AB, 0xFFD9A8, 0xFEE4A8, 0xFFFBB9, 0xF2F7B7,
        0xCDE8B5,
        0xCBF0FF, 0xD3E2FF, 0xD9C9FE, 0xEFCAFF, 0xF9D3E0, 0xFFDBD8, 0xFFE2D6, 0xFFECD4, 0xFFF2D5, 0xFEFCDD, 0xF7FADB,
        0xDFEED4,
    ]

    var onSelect: ((UIColor) -> Void)?
    var selectedRGB: UInt32? {
        didSet {
            guard selectedRGB != oldValue else { return }
            setNeedsLayout()
        }
    }

    private let wrapper = UIView()
    private let imageView = UIImageView()
    private let selection = CAShapeLayer()
    private var imageSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        wrapper.clipsToBounds = true
        wrapper.layer.cornerRadius = 10
        addSubview(wrapper)
        wrapper.addSubview(imageView)
        selection.fillColor = UIColor.clear.cgColor
        selection.lineWidth = 3
        selection.shadowColor = UIColor.black.cgColor
        selection.shadowOpacity = 0.15
        selection.shadowRadius = 4.5
        selection.shadowOffset = .zero
        layer.addSublayer(selection)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(touched(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let squareSize = (bounds.width / 12).rounded(.down)
        let size = CGSize(width: bounds.width, height: squareSize * 10)
        wrapper.frame = CGRect(origin: .zero, size: size)
        imageView.frame = wrapper.bounds
        if size != imageSize, size.width > 0 {
            imageSize = size
            imageView.image = UIGraphicsImageRenderer(size: size).image { context in
                for (index, rgb) in Self.colors.enumerated() {
                    let column = index % 12
                    let row = index / 12
                    let width = column == 11 ? size.width - squareSize * 11 : squareSize
                    Self.uiColor(rgb).setFill()
                    context.fill(CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: width,
                        height: squareSize,
                    ))
                }
            }
        }
        guard let selectedRGB, let index = Self.colors.firstIndex(of: selectedRGB) else {
            selection.path = nil
            return
        }
        let column = index % 12
        let row = index / 12
        let rect = CGRect(
            x: CGFloat(column) * squareSize,
            y: CGFloat(row) * squareSize,
            width: squareSize,
            height: squareSize,
        )
        let large: CGFloat = 10
        let small: CGFloat = 2
        let corners = (
            topLeft: index == 0 ? large : small,
            topRight: index == 11 ? large : small,
            bottomLeft: index == Self.colors.count - 12 ? large : small,
            bottomRight: index == Self.colors.count - 1 ? large : small,
        )
        selection.path = Self.roundedRect(rect, corners).cgPath
        let isDark = StoryTextEntityView.lightness(Self.uiColor(selectedRGB)) < 0.5
        selection.strokeColor = (isDark
            ? UIColor.white
            : UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1C / 255, alpha: 1)).cgColor
    }

    static func uiColor(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1,
        )
    }

    private static func roundedRect(
        _ rect: CGRect,
        _ corners: (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat),
    ) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + corners.topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corners.topRight, y: rect.minY))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - corners.topRight, y: rect.minY + corners.topRight),
            radius: corners.topRight,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corners.bottomRight))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - corners.bottomRight, y: rect.maxY - corners.bottomRight),
            radius: corners.bottomRight,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: rect.minX + corners.bottomLeft, y: rect.maxY))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + corners.bottomLeft, y: rect.maxY - corners.bottomLeft),
            radius: corners.bottomLeft,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corners.topLeft))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + corners.topLeft, y: rect.minY + corners.topLeft),
            radius: corners.topLeft,
            startAngle: .pi,
            endAngle: .pi * 3 / 2,
            clockwise: true,
        )
        path.close()
        return path
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func touched(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed, imageSize.width > 0 else { return }
        let point = gesture.location(in: self)
        guard point.x >= 0, point.x <= imageSize.width, point.y >= 0, point.y <= imageSize.height else { return }
        let row = max(0, min(9, Int(point.y / imageSize.height * 10)))
        let column = max(0, min(11, Int(point.x / imageSize.width * 12)))
        let rgb = Self.colors[row * 12 + column]
        guard rgb != selectedRGB else { return }
        onSelect?(Self.uiColor(rgb))
    }
}

// MARK: - StoryColorSpectrumView

/// ColorSpectrumComponent: the spectrum over its grey ramp in a 10 pt round field; the colour under the finger is
/// picked from the picture, and the knob, a 32 pt dark circle around the colour, stands there.
private final class StoryColorSpectrumView: UIView, UIGestureRecognizerDelegate {
    var onSelect: ((UIColor, CGPoint) -> Void)?

    private let wrapper = UIView()
    private let imageView = UIImageView()
    private let knob = CALayer()
    private let circle = CAShapeLayer()
    private var position: CGPoint?
    private var pixels: (data: [UInt8], width: Int, height: Int)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wrapper.clipsToBounds = true
        wrapper.layer.cornerRadius = 10
        addSubview(wrapper)
        wrapper.addSubview(imageView)
        knob.contents = StoryColorSlider.knobImage().cgImage
        layer.addSublayer(knob)
        circle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 26, height: 26)).cgPath
        layer.addSublayer(circle)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(touched(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        wrapper.frame = bounds
        if imageView.frame.size != bounds.size, bounds.width > 0 {
            imageView.frame = bounds
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
                UIImage(named: "MediaEditor/Spectrum")?.draw(in: CGRect(origin: .zero, size: self.bounds.size))
                UIImage(named: "MediaEditor/Grayscale")?.draw(in: CGRect(origin: .zero, size: self.bounds.size))
            }
            imageView.image = image
            pixels = Self.pixels(of: image.cgImage)
        }
        placeKnob()
    }

    private static func pixels(of image: CGImage?) -> (data: [UInt8], width: Int, height: Int)? {
        guard let image else { return nil }
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (data, width, height) : nil
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }

    func setKnob(at position: CGPoint?, color: UIColor) {
        self.position = position
        circle.fillColor = color.cgColor
        placeKnob()
    }

    private func placeKnob() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let position, bounds.width > 0 else {
            knob.isHidden = true
            circle.isHidden = true
            return
        }
        knob.isHidden = false
        circle.isHidden = false
        let frame = CGRect(
            x: (bounds.width * position.x - 16).rounded(.down),
            y: (bounds.height * position.y - 16).rounded(.down),
            width: 32,
            height: 32,
        )
        knob.frame = frame.insetBy(dx: -10, dy: -10)
        circle.frame = frame.insetBy(dx: 3, dy: 3)
    }

    @objc private func touched(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed, let pixels, bounds.width > 0 else { return }
        let point = gesture.location(in: self)
        guard point.x >= 0, point.x <= bounds.width, point.y >= 0, point.y <= bounds.height else { return }
        let x = min(pixels.width - 1, Int(point.x / bounds.width * CGFloat(pixels.width)))
        let y = min(pixels.height - 1, Int(point.y / bounds.height * CGFloat(pixels.height)))
        let offset = (y * pixels.width + x) * 4
        let color = UIColor(
            red: CGFloat(pixels.data[offset]) / 255,
            green: CGFloat(pixels.data[offset + 1]) / 255,
            blue: CGFloat(pixels.data[offset + 2]) / 255,
            alpha: 1,
        )
        onSelect?(color, CGPoint(x: point.x / bounds.width, y: point.y / bounds.height))
    }
}

// MARK: - StoryColorSlidersView

/// ColorSlidersComponent: RED, GREEN and BLUE, each a slider between the colour without and with all of it and its
/// value out of 255, then Hex Color # with the colour's six digits.
private final class StoryColorSlidersView: UIView {
    var onChange: ((UIColor) -> Void)?

    private let titles = ["RED", "GREEN", "BLUE"].map { text in
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor(red: 0x9B / 255, green: 0x9D / 255, blue: 0xA5 / 255, alpha: 1)
        return label
    }

    private let sliders = (0..<3).map { _ in StoryColorSlider() }
    private let fields = (0..<3).map { _ in StoryColorField(suffix: nil) }
    private let hexTitle = UILabel()
    private let hexField = StoryColorField(suffix: nil, isHex: true)
    private var color = UIColor.white

    override init(frame: CGRect) {
        super.init(frame: frame)
        for (index, title) in titles.enumerated() {
            addSubview(title)
            addSubview(sliders[index])
            addSubview(fields[index])
            sliders[index].onChange = { [weak self] value in self?.set(component: index, to: value) }
            fields[index].isValid = { value in
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (Int(value).map { (0...255).contains($0) } ?? false)
            }
            fields[index].onChange = { [weak self] value in
                self?.set(component: index, to: CGFloat(Int(value) ?? 0) / 255)
            }
        }
        hexTitle.text = "Hex Color #"
        hexTitle.font = .systemFont(ofSize: 17)
        hexTitle.textColor = .white
        addSubview(hexTitle)
        hexField.isValid = { value in
            value.count <= 6
                && value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil
        }
        hexField.onChange = { [weak self] value in
            guard let self, value.count == 6, let rgb = UInt32(value, radix: 16) else { return }
            let alpha = color.cgColor.alpha
            onChange?(StoryColorGridView.uiColor(rgb).withAlphaComponent(alpha))
        }
        addSubview(hexField)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        let titleHeight = ceil(UIFont.systemFont(ofSize: 13, weight: .semibold).lineHeight)
        for index in 0..<3 {
            titles[index].frame = CGRect(x: 5, y: y, width: bounds.width, height: titleHeight)
            y += titleHeight + 8
            sliders[index].frame = CGRect(x: 0, y: y, width: bounds.width - 89, height: 36)
            fields[index].frame = CGRect(x: bounds.width - 77, y: y, width: 77, height: 36)
            y += 36 + 28
        }
        hexField.frame = CGRect(x: bounds.width - 77, y: y, width: 77, height: 36)
        let hexWidth = hexTitle.sizeThatFits(.zero).width
        hexTitle.frame = CGRect(x: hexField.frame.minX - 12 - hexWidth, y: y, width: hexWidth, height: 36)
    }

    func update(color: UIColor) {
        self.color = color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let values = [red, green, blue]
        for index in 0..<3 {
            var low = values
            low[index] = 0
            var high = values
            high[index] = 1
            sliders[index].update(
                left: UIColor(red: low[0], green: low[1], blue: low[2], alpha: 1),
                right: UIColor(red: high[0], green: high[1], blue: high[2], alpha: 1),
                current: color,
                value: values[index],
            )
            fields[index].setText("\(Int(values[index] * 255))")
        }
        hexField.setText(String(format: "%06X", StoryColorPickerViewController.rgb(color)))
    }

    private func set(component index: Int, to value: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var values = [red, green, blue]
        values[index] = max(0, min(1, value))
        onChange?(UIColor(red: values[0], green: values[1], blue: values[2], alpha: alpha))
    }
}

// MARK: - StoryColorSlider

/// ColorSliderComponent: a 36 pt capsule with the gradient between its two colours over a checkerboard where they are
/// see-through, and a 32 pt dark knob 2 pt in with the current colour in its middle; a touch or a drag sets the value.
private final class StoryColorSlider: UIView, UIGestureRecognizerDelegate {
    var onChange: ((CGFloat) -> Void)?

    private let wrapper = UIView()
    private let checkers = UIImageView()
    private let gradient = CAGradientLayer()
    private let knob = CALayer()
    private let circle = CAShapeLayer()
    private var value: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        wrapper.clipsToBounds = true
        wrapper.layer.cornerRadius = 18
        addSubview(wrapper)
        wrapper.addSubview(checkers)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        wrapper.layer.addSublayer(gradient)
        knob.contents = Self.knobImage().cgImage
        layer.addSublayer(knob)
        circle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 26, height: 26)).cgPath
        layer.addSublayer(circle)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(touched(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wrapper.frame = bounds
        if checkers.frame.size != bounds.size, bounds.width > 0 {
            checkers.frame = bounds
            checkers.image = Self.checkers(size: bounds.size)
        }
        gradient.frame = bounds
        let frame = CGRect(x: 2 + ((bounds.width - 4 - 32) * value).rounded(.down), y: 2, width: 32, height: 32)
        knob.frame = frame.insetBy(dx: -10, dy: -10)
        circle.frame = frame.insetBy(dx: 3, dy: 3)
        CATransaction.commit()
    }

    /// generateKnobImage: a 32 pt 0x1a1a1c circle with a 9 pt shadow of 30% black, 10 pt of margin around it.
    static func knobImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 52, height: 52)).image { context in
            let cg = context.cgContext
            cg.setShadow(offset: .zero, blur: 9, color: UIColor(white: 0, alpha: 0.3).cgColor)
            cg.setFillColor(UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1C / 255, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: 10, y: 10, width: 32, height: 32))
        }
    }

    /// generateCheckeredImage: 12 pt white squares on clear.
    static func checkers(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            let length: CGFloat = 12
            for column in 0..<Int(ceil(size.width / length)) {
                for row in 0..<Int(ceil(size.height / length)) where column % 2 != row % 2 {
                    context.fill(CGRect(
                        x: CGFloat(column) * length,
                        y: CGFloat(row) * length,
                        width: length,
                        height: length,
                    ))
                }
            }
        }
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }

    func update(left: UIColor, right: UIColor, current: UIColor, value: CGFloat) {
        self.value = max(0, min(1, value))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = [left.cgColor, right.cgColor]
        circle.fillColor = current.cgColor
        CATransaction.commit()
        checkers.isHidden = left.cgColor.alpha >= 1 && right.cgColor.alpha >= 1
        setNeedsLayout()
    }

    @objc private func touched(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed, bounds.width > 36 else { return }
        let x = gesture.location(in: self).x - 18
        onChange?(max(0, min(1, x / (bounds.width - 36))))
    }
}

// MARK: - StoryColorField

/// ColorFieldComponent: a 9 pt round field of 60% black with its value in 17 pt semibold monospaced digits, centred
/// or, with a suffix, right-aligned 33 pt before it; it selects all as it begins and takes only valid text.
private final class StoryColorField: UIView, UITextFieldDelegate {
    var onChange: ((String) -> Void)?
    var isValid: ((String) -> Bool)?

    private let textField = UITextField()
    private let suffixLabel = UILabel()
    private let hasSuffix: Bool

    init(suffix: String?, isHex: Bool = false) {
        self.hasSuffix = suffix != nil
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        layer.cornerRadius = 9
        let font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        textField.font = font
        textField.textColor = .white
        textField.textAlignment = hasSuffix ? .right : .center
        textField.keyboardType = isHex ? .asciiCapable : .numberPad
        textField.keyboardAppearance = .dark
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .allCharacters
        textField.delegate = self
        textField.addAction(UIAction { [weak self] _ in
            self?.onChange?(self?.textField.text ?? "")
        }, for: .editingChanged)
        addSubview(textField)
        if let suffix {
            suffixLabel.text = suffix
            suffixLabel.font = font
            suffixLabel.textColor = .white
            addSubview(suffixLabel)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        textField.frame = bounds.offsetBy(dx: hasSuffix ? -33 : 0, dy: 0)
        let size = suffixLabel.sizeThatFits(.zero)
        suffixLabel.frame = CGRect(
            x: bounds.width - size.width - 14,
            y: ((bounds.height - size.height) / 2).rounded(.down),
            width: size.width,
            height: size.height,
        )
    }

    /// The value, unless the field is being typed into.
    func setText(_ text: String) {
        guard !textField.isFirstResponder else { return }
        textField.text = text
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        let updated = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        return isValid?(updated) ?? true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.selectAll(nil)
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        false
    }
}

// MARK: - StoryColorPreview

/// ColorPreviewComponent: the colour over a square split black and white on its diagonal, rounded 12 pt.
private final class StoryColorPreview: UIView {
    var color = UIColor.white {
        didSet { colorView.backgroundColor = color }
    }

    private let backgroundView = UIImageView()
    private let colorView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        addSubview(backgroundView)
        addSubview(colorView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        colorView.frame = bounds
        guard backgroundView.frame.size != bounds.size, bounds.width > 0 else { return }
        backgroundView.frame = bounds
        let size = bounds.size
        backgroundView.image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.move(to: .zero)
            cg.addLine(to: CGPoint(x: size.width, y: 0))
            cg.addLine(to: CGPoint(x: 0, y: size.height))
            cg.closePath()
            cg.fillPath()
            cg.setFillColor(UIColor.white.cgColor)
            cg.move(to: CGPoint(x: size.width, y: 0))
            cg.addLine(to: CGPoint(x: size.width, y: size.height))
            cg.addLine(to: CGPoint(x: 0, y: size.height))
            cg.closePath()
            cg.fillPath()
        }
    }
}

// MARK: - StoryPaletteSwatch

/// ColorSwatchComponent's palette swatch: a 30 pt circle of the colour inside a 3 pt ring of it; selected, the circle
/// shrinks 5 pt from the ring. Black takes a 0x1f1f1f edge.
private final class StoryPaletteSwatch: UIControl {
    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            updatePath(animated: true)
        }
    }

    private let ring = CALayer()
    private let circle = CAShapeLayer()

    init(color: UIColor) {
        super.init(frame: .zero)
        ring.borderWidth = 3
        layer.addSublayer(ring)
        circle.fillColor = color.cgColor
        layer.addSublayer(circle)
        if StoryColorPickerViewController.rgb(color) == 0 {
            let edge = UIColor(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255, alpha: 1).cgColor
            circle.strokeColor = edge
            circle.lineWidth = 1
            ring.borderColor = edge
        } else {
            ring.borderColor = color.cgColor
        }
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.cornerRadius = bounds.width / 2
        circle.frame = bounds
        CATransaction.commit()
        updatePath(animated: false)
    }

    private func updatePath(animated: Bool) {
        let path = UIBezierPath(ovalIn: bounds.insetBy(dx: isSelected ? 5 : 0, dy: isSelected ? 5 : 0)).cgPath
        if animated {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = circle.presentation()?.path ?? circle.path
            animation.toValue = path
            animation.duration = 0.2
            circle.add(animation, forKey: "path")
        }
        circle.path = path
    }
}
