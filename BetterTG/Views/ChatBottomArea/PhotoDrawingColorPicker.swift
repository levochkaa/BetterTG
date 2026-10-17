// PhotoDrawingColorPicker.swift

import Combine
import UIKit

// MARK: - PhotoDrawingColorPickerViewController

/// ColorPickerScreen: Grid, Spectrum and Sliders over the opacity slider, the color's preview and five swatches, with
/// the eyedropper, which closes the sheet to pick the color from the photo.
final class PhotoDrawingColorPickerViewController: UIViewController {
    // MARK: Private

    private static let detentIdentifier = UISheetPresentationController.Detent.Identifier("PhotoDrawingColor")
    private static let sideInset: CGFloat = 16
    private static let modeHeight: CGFloat = 32
    private static let opacityTitleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    /// The swatches beside the preview.
    private static let swatchColors = [0x000000, 0x0161FD, 0x32C759, 0xFFCC02, 0xFF3A30]
        .map { PhotoDrawingColor(rgb: $0) }

    // MARK: Internal

    /// `colorChanged`: every change while the sheet is open.
    var onColorChanged: ((PhotoDrawingColor) -> Void)?
    /// `openEyedropper`: the sheet goes as the eyedropper opens.
    var onEyedropper: (() -> Void)?

    private let scrollView = UIScrollView()
    private let closeButton = UIButton(type: .close)
    private let eyedropperButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let modeControl = UISegmentedControl(items: [
        L10n.telegram("Paint.ColorGrid"),
        L10n.telegram("Paint.ColorSpectrum"),
        L10n.telegram("Paint.ColorSliders"),
    ])
    private let gridView = PhotoDrawingColorGridView()
    private let spectrumView = PhotoDrawingSpectrumView(cornerRadius: 10, knobOffset: 0)
    private let slidersView = PhotoDrawingColorSlidersView()
    private let opacityLabel = UILabel()
    private let opacitySlider = PhotoDrawingColorSlider()
    private let opacityField = PhotoDrawingColorField(kind: .number(maximum: 100), suffix: "%")
    private let dividerView = UIView()
    private let previewView = PhotoDrawingColorPreviewView()
    private var swatchButtons = [PhotoDrawingSwatchButton]()
    private var cancellables = Set<AnyCancellable>()
    private var color: PhotoDrawingColor
    /// `DrawingColor.position`: where the spectrum's knob sits for a color picked there.
    private var spectrumPosition: CGPoint?

    /// `width` is the sheet's, which its height follows.
    init(color: PhotoDrawingColor, width: CGFloat) {
        self.color = color
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        overrideUserInterfaceStyle = .dark
        if let sheet = sheetPresentationController {
            let height = Self.contentHeight(width: width)
            sheet.detents = [.custom(identifier: Self.detentIdentifier) { context in
                min(height, context.maximumDetentValue)
            }]
            sheet.prefersGrabberVisible = false
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        configureHeader()
        configureModes()
        configureOpacity()
        configureFooter()
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.keyboardWillChangeFrame(notification) }
            .store(in: &cancellables)
        update()
        updateModeVisibility()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        layoutContent()
    }

    private static func squareSide(width: CGFloat) -> CGFloat {
        floor((width - sideInset * 2) / 12)
    }

    /// ColorPickerContent's height above the bottom safe area, which the sheet adds.
    private static func contentHeight(width: CGFloat) -> CGFloat {
        let fieldHeight = squareSide(width: width) * 10
        let opacityHeight = ceil(opacityTitleFont.lineHeight) + 8 + 36
        return 76 + modeHeight + 20 + fieldHeight + 21 + opacityHeight + 24 + 1 + 22 + 82 + 10 + 5
    }

    private func configureHeader() {
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        scrollView.addSubview(closeButton)
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        eyedropperButton.setImage(UIImage(systemName: "eyedropper", withConfiguration: configuration), for: .normal)
        eyedropperButton.tintColor = .label
        eyedropperButton.accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Eyedropper")
        eyedropperButton.addAction(UIAction { [weak self] _ in self?.openEyedropper() }, for: .touchUpInside)
        scrollView.addSubview(eyedropperButton)
        titleLabel.text = L10n.telegram("Paint.ColorTitle")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        scrollView.addSubview(titleLabel)
    }

    private func configureModes() {
        modeControl.selectedSegmentIndex = 0
        modeControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            UIView.animate(withDuration: 0.2) { self.updateModeVisibility() }
        }, for: .valueChanged)
        scrollView.addSubview(modeControl)
        gridView.onSelect = { [weak self] color in
            self?.select(color, keepsAlpha: true)
        }
        spectrumView.onSelect = { [weak self] color, position in
            self?.select(color, keepsAlpha: true, spectrumPosition: position)
        }
        slidersView.onChange = { [weak self] color in
            self?.select(color, keepsAlpha: true)
        }
        for modeView in [gridView, spectrumView, slidersView] as [UIView] {
            scrollView.addSubview(modeView)
        }
    }

    private func configureOpacity() {
        opacityLabel.text = L10n.telegram("Paint.ColorOpacity")
        opacityLabel.font = Self.opacityTitleFont
        opacityLabel.textColor = UIColor(rgb: 0x9B9DA5)
        scrollView.addSubview(opacityLabel)
        opacitySlider.onChange = { [weak self] value in
            self?.setAlpha(value)
        }
        scrollView.addSubview(opacitySlider)
        opacityField.onChange = { [weak self] text in
            self?.setAlpha(CGFloat(Int(text) ?? 0) / 100)
        }
        scrollView.addSubview(opacityField)
    }

    private func configureFooter() {
        dividerView.backgroundColor = UIColor(rgb: 0x48484A)
        scrollView.addSubview(dividerView)
        scrollView.addSubview(previewView)
        for swatch in Self.swatchColors {
            let button = PhotoDrawingSwatchButton(color: swatch)
            button.addAction(UIAction { [weak self] _ in
                self?.select(swatch, keepsAlpha: false)
            }, for: .touchUpInside)
            scrollView.addSubview(button)
            swatchButtons.append(button)
        }
    }

    private func layoutContent() {
        let width = view.bounds.width
        let inset = Self.sideInset
        let closeSize = closeButton.intrinsicContentSize
        closeButton.frame = CGRect(
            x: 38 - closeSize.width / 2,
            y: 38 - closeSize.height / 2,
            width: closeSize.width,
            height: closeSize.height,
        )
        eyedropperButton.frame = CGRect(x: width - view.safeAreaInsets.right - 16 - 44, y: 16, width: 44, height: 44)
        titleLabel.frame = CGRect(x: 50, y: 16, width: max(0, width - 100), height: 44)
        var y: CGFloat = 76
        modeControl.frame = CGRect(x: inset, y: y, width: width - inset * 2, height: Self.modeHeight)
        y += Self.modeHeight + 20
        let field = CGRect(x: inset, y: y, width: width - inset * 2, height: Self.squareSide(width: width) * 10)
        gridView.frame = field
        spectrumView.frame = field
        slidersView.frame = CGRect(x: inset, y: y, width: field.width, height: PhotoDrawingColorSlidersView.height)
        y += field.height + 21
        let titleHeight = ceil(Self.opacityTitleFont.lineHeight)
        opacityLabel.frame = CGRect(x: inset + 5, y: y, width: max(0, field.width - 5), height: titleHeight)
        y += titleHeight + 8
        opacitySlider.frame = CGRect(x: inset, y: y, width: max(0, field.width - 89), height: 36)
        opacityField.frame = CGRect(x: width - inset - 77, y: y, width: 77, height: 36)
        y += 36 + 24
        dividerView.frame = CGRect(x: inset, y: y - 0.5, width: field.width, height: 1)
        y += 1 + 22
        previewView.frame = CGRect(x: inset, y: y, width: 82, height: 82)
        var x = inset + 82 + 38
        for button in swatchButtons {
            button.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
            button.center = CGPoint(x: x, y: y + 15)
            x += 30 + 20
        }
        y += 82 + 10
        scrollView.contentSize = CGSize(width: width, height: y + view.safeAreaInsets.bottom + 5)
    }

    private func updateModeVisibility() {
        let mode = modeControl.selectedSegmentIndex
        for (index, modeView) in ([gridView, spectrumView, slidersView] as [UIView]).enumerated() {
            modeView.alpha = index == mode ? 1 : 0
            modeView.isUserInteractionEnabled = index == mode
        }
    }

    /// State's `updateColor(_:keepAlpha:)`.
    private func select(_ newColor: PhotoDrawingColor, keepsAlpha: Bool, spectrumPosition position: CGPoint? = nil) {
        color = keepsAlpha ? newColor.withAlpha(color.alpha) : newColor
        spectrumPosition = position
        update()
        onColorChanged?(color)
    }

    /// State's `updateAlpha`.
    private func setAlpha(_ alpha: CGFloat) {
        color = color.withAlpha(alpha)
        update()
        onColorChanged?(color)
    }

    private func update() {
        gridView.selectedColor = color
        spectrumView.setSelection(color: color, position: spectrumPosition)
        slidersView.color = color
        opacitySlider.update(left: color.withAlpha(0), right: color.withAlpha(1), current: color, value: color.alpha)
        opacityField.setText("\(Int(color.alpha * 100))")
        previewView.color = color
        for (button, swatch) in zip(swatchButtons, Self.swatchColors) {
            button.isChosen = swatch == color
        }
    }

    private func openEyedropper() {
        let onEyedropper = onEyedropper
        dismiss(animated: true)
        onEyedropper?()
    }

    /// The fields stay above the keyboard.
    private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        let fields = [opacityField] + slidersView.fields
        guard overlap > 0, let field = fields.first(where: \.isEditing) else { return }
        scrollView.scrollRectToVisible(
            field.convert(field.bounds, to: scrollView).insetBy(dx: 0, dy: -12),
            animated: true,
        )
    }
}

// MARK: - PhotoDrawingColorGridView

/// ColorGridComponent: twelve columns by ten rows of colors, the chosen one framed.
final class PhotoDrawingColorGridView: UIView, UIGestureRecognizerDelegate {
    // MARK: Internal

    /// `palleteColors`.
    static let palette = [
        0xFFFFFF, 0xEBEBEB, 0xD6D6D6, 0xC2C2C2, 0xADADAD, 0x999999, 0x858585, 0x707070, 0x5C5C5C, 0x474747, 0x333333,
        0x000000, 0x00374A, 0x011D57, 0x11053B, 0x2E063D, 0x3C071B, 0x5C0701, 0x5A1C00, 0x583300, 0x563D00, 0x666100,
        0x4F5504, 0x263E0F, 0x004D65, 0x012F7B, 0x1A0A52, 0x450D59, 0x551029, 0x831100, 0x7B2900, 0x7A4A00, 0x785800,
        0x8D8602, 0x6F760A, 0x38571A, 0x016E8F, 0x0042A9, 0x2C0977, 0x61187C, 0x791A3D, 0xB51A00, 0xAD3E00, 0xA96800,
        0xA67B01, 0xC4BC00, 0x9BA50E, 0x4E7A27, 0x008CB4, 0x0056D6, 0x371A94, 0x7A219E, 0x99244F, 0xE22400, 0xDA5100,
        0xD38301, 0xD19D01, 0xF5EC00, 0xC3D117, 0x669D34, 0x00A1D8, 0x0061FE, 0x4D22B2, 0x982ABC, 0xB92D5D, 0xFF4015,
        0xFF6A00, 0xFFAB01, 0xFDC700, 0xFEFB41, 0xD9EC37, 0x76BB40, 0x01C7FC, 0x3A87FE, 0x5E30EB, 0xBE38F3, 0xE63B7A,
        0xFF6250, 0xFF8648, 0xFEB43F, 0xFECB3E, 0xFFF76B, 0xE4EF65, 0x96D35F, 0x52D6FC, 0x74A7FF, 0x864FFE, 0xD357FE,
        0xEE719E, 0xFF8C82, 0xFFA57D, 0xFFC777, 0xFFD977, 0xFFF994, 0xEAF28F, 0xB1DD8B, 0x93E3FD, 0xA7C6FF, 0xB18CFE,
        0xE292FE, 0xF4A4C0, 0xFFB5AF, 0xFFC5AB, 0xFFD9A8, 0xFEE4A8, 0xFFFBB9, 0xF2F7B7, 0xCDE8B5, 0xCBF0FF, 0xD3E2FF,
        0xD9C9FE, 0xEFCAFF, 0xF9D3E0, 0xFFDBD8, 0xFFE2D6, 0xFFECD4, 0xFFF2D5, 0xFEFCDD, 0xF7FADB, 0xDFEED4,
    ]

    var onSelect: ((PhotoDrawingColor) -> Void)?

    var selectedColor: PhotoDrawingColor? {
        didSet {
            if selectedColor != oldValue {
                setNeedsLayout()
            }
        }
    }

    // MARK: Private

    private let wrapperView = UIView()
    private let imageView = UIImageView()
    private let selectionView = UIImageView()
    private var imageSize = CGSize.zero
    private var selectionKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wrapperView.clipsToBounds = true
        wrapperView.layer.cornerRadius = 10
        wrapperView.isUserInteractionEnabled = false
        addSubview(wrapperView)
        wrapperView.addSubview(imageView)
        selectionView.isUserInteractionEnabled = false
        addSubview(selectionView)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(1, traitCollection.displayScale)
        let square = floor(bounds.width / 12 * scale) / scale
        let size = CGSize(width: bounds.width, height: square * 10)
        if size != imageSize, size.width > 0 {
            imageSize = size
            imageView.image = Self.makeImage(size: size, square: square)
        }
        wrapperView.frame = CGRect(origin: .zero, size: size)
        imageView.frame = wrapperView.bounds
        layoutSelection(square: square, scale: scale)
    }

    /// `UIBezierPath(roundRect:topLeftRadius:topRightRadius:bottomLeftRadius:bottomRightRadius:)`.
    static func roundedRectPath(
        _ rect: CGRect,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomLeft: CGFloat,
        bottomRight: CGFloat,
    ) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRight),
            radius: topRight,
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY),
            radius: bottomRight,
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft),
            radius: bottomLeft,
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + topLeft, y: rect.minY),
            radius: topLeft,
        )
        path.closeSubpath()
        return path
    }

    /// `generateColorGridImage`: the last column takes what the whole squares leave.
    private static func makeImage(size: CGSize, square: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            for row in 0..<10 {
                for column in 0..<12 {
                    let width = column == 11 ? size.width - square * 11 : square
                    UIColor(rgb: palette[row * 12 + column]).setFill()
                    context.fill(CGRect(
                        x: CGFloat(column) * square,
                        y: CGFloat(row) * square,
                        width: width,
                        height: square,
                    ))
                }
            }
        }
    }

    /// `generateColorSelectionImage`: the chosen square's frame, rounded like the grid at its corners.
    private static func selectionImage(side: CGFloat, radii: [CGFloat], isLight: Bool, scale: CGFloat) -> UIImage {
        let margin: CGFloat = 10
        let size = CGSize(width: side + margin * 2, height: side + margin * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cgContext = context.cgContext
            cgContext.addPath(roundedRectPath(
                CGRect(x: margin, y: margin, width: side, height: side),
                topLeft: radii[0],
                topRight: radii[1],
                bottomLeft: radii[2],
                bottomRight: radii[3],
            ))
            cgContext.setShadow(offset: .zero, blur: 9, color: UIColor(white: 0, alpha: 0.15).cgColor)
            cgContext.setLineWidth(3 - 1 / scale)
            cgContext.setStrokeColor(UIColor(rgb: isLight ? 0xFFFFFF : 0x1A1A1C).cgColor)
            cgContext.strokePath()
        }
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }

    private func layoutSelection(square: CGFloat, scale: CGFloat) {
        guard let selectedColor, let index = Self.palette.firstIndex(of: selectedColor.rgb), square > 0 else {
            selectionView.image = nil
            selectionKey = nil
            return
        }
        let small: CGFloat = 2
        let large: CGFloat = 10
        var radii = [small, small, small, small]
        if index == 0 {
            radii[0] = large
        } else if index == 11 {
            radii[1] = large
        } else if index == Self.palette.count - 12 {
            radii[2] = large
        } else if index == Self.palette.count - 1 {
            radii[3] = large
        }
        let isLight = selectedColor.lightness < 0.5
        let key = "\(index) \(isLight) \(square)"
        if key != selectionKey {
            selectionKey = key
            selectionView.image = Self.selectionImage(side: square, radii: radii, isLight: isLight, scale: scale)
        }
        let row = index / 12
        let column = index % 12
        selectionView.frame = CGRect(
            x: CGFloat(column) * square,
            y: CGFloat(row) * square,
            width: square,
            height: square,
        )
        .insetBy(dx: -10, dy: -10)
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        pick(at: recognizer.location(in: self))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed else { return }
        pick(at: recognizer.location(in: self))
    }

    private func pick(at point: CGPoint) {
        guard let picked = color(at: point), picked != selectedColor else { return }
        onSelect?(picked)
    }

    /// `getColor(at:)`.
    private func color(at point: CGPoint) -> PhotoDrawingColor? {
        guard imageSize.width > 0, point.x >= 0, point.x <= imageSize.width, point.y >= 0,
              point.y <= imageSize.height
        else { return nil }
        let row = max(0, min(10, Int(point.y / imageSize.height * 10)))
        let column = max(0, min(12, Int(point.x / imageSize.width * 12)))
        let index = row * 12 + column
        return PhotoDrawingColor(rgb: index < Self.palette.count ? Self.palette[index] : 0x000000)
    }
}

// MARK: - PhotoDrawingSpectrumView

/// ColorSpectrumComponent and ColorSpectrumPickerView: Telegram's spectrum, its hues down the height and white on
/// the left fading to black on the right, picked where it is pressed and dragged.
final class PhotoDrawingSpectrumView: UIView, UIGestureRecognizerDelegate {
    // MARK: Private

    /// The hues of `Media Editor/Spectrum` from top to bottom.
    private static let hueStops = [
        0xFF0808, 0xFF1108, 0xFF2B08, 0xFF5708, 0xFF9108, 0xFFCB08, 0xFFF408, 0xFEFF08, 0xE8FF08, 0xB7FF08, 0x7BFF08,
        0x45FF08, 0x20FF08, 0x0CFF08, 0x08FF09, 0x08FF17, 0x08FF37, 0x08FF69, 0x08FFA4, 0x08FFDA, 0x08FFFB, 0x08FBFF,
        0x08DAFF, 0x08A4FF, 0x0869FF, 0x0837FF, 0x0817FF, 0x0809FF, 0x0C08FF, 0x2008FF, 0x4508FF, 0x7B08FF, 0xB708FF,
        0xE808FF, 0xFE08FF, 0xFF08F4, 0xFF08CB, 0xFF0891, 0xFF0857, 0xFF082B, 0xFF0811, 0xFF0809,
    ]

    /// `Media Editor/Grayscale` from left to right: its gray and opacity.
    private static let grayStops: [(white: Int, alpha: Int)] = [
        (255, 255), (255, 237), (255, 213), (255, 186), (255, 156), (255, 126), (255, 98), (255, 73), (255, 50),
        (255, 32), (255, 19), (255, 9), (255, 3), (255, 1), (255, 0), (253, 0), (240, 0), (223, 1), (203, 3),
        (181, 10), (157, 20), (134, 33), (109, 51), (86, 73), (64, 99), (44, 126), (26, 156), (11, 186), (2, 213),
        (0, 236), (0, 254),
    ]

    // MARK: Internal

    /// A picked color and its place, from 0 to 1 across and down.
    var onSelect: ((PhotoDrawingColor, CGPoint) -> Void)?

    private let knobOffset: CGFloat
    private let wrapperView = UIView()
    private let imageView = UIImageView()
    private let knobLayer = CALayer()
    private let circleLayer = CAShapeLayer()
    private var imageSize = CGSize.zero
    private var selectedColor: PhotoDrawingColor?
    private var selectedPosition: CGPoint?

    /// `knobOffset` lifts the knob above the finger, as ColorSpectrumPickerView does under the color button.
    init(cornerRadius: CGFloat, knobOffset: CGFloat) {
        self.knobOffset = knobOffset
        super.init(frame: .zero)
        layer.allowsGroupOpacity = true
        wrapperView.clipsToBounds = true
        wrapperView.layer.cornerRadius = cornerRadius
        wrapperView.isUserInteractionEnabled = false
        addSubview(wrapperView)
        wrapperView.addSubview(imageView)
        knobLayer.contents = PhotoDrawingColorSlider.knobImage.cgImage
        knobLayer.isHidden = true
        layer.addSublayer(knobLayer)
        circleLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 26, height: 26), transform: nil)
        circleLayer.isHidden = true
        layer.addSublayer(circleLayer)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != imageSize, bounds.width > 0, bounds.height > 0 {
            imageSize = bounds.size
            imageView.image = Self.makeImage(size: bounds.size)
        }
        wrapperView.frame = bounds
        imageView.frame = bounds
        layoutKnob()
    }

    /// The color the spectrum's images give at `position`, from 0 to 1 across and down, in whole 8-bit steps.
    static func color(at position: CGPoint) -> PhotoDrawingColor {
        let hue = interpolate(hueStops.map { PhotoDrawingColor(rgb: $0) }, at: position.y)
        let gray = interpolate(
            grayStops.map { PhotoDrawingColor(rgb: $0.white * 0x010101, alpha: CGFloat($0.alpha) / 255) },
            at: position.x,
        )
        let keep = 1 - gray.alpha
        let mixed = PhotoDrawingColor(
            red: hue.red * keep + gray.red * gray.alpha,
            green: hue.green * keep + gray.green * gray.alpha,
            blue: hue.blue * keep + gray.blue * gray.alpha,
        )
        return PhotoDrawingColor(rgb: mixed.rgb)
    }

    private static func interpolate(_ stops: [PhotoDrawingColor], at fraction: CGFloat) -> PhotoDrawingColor {
        guard stops.count > 1 else { return stops.first ?? .white }
        let position = min(max(fraction, 0), 1) * CGFloat(stops.count - 1)
        let index = min(Int(position), stops.count - 2)
        return stops[index].mixed(with: stops[index + 1], alpha: position - CGFloat(index))
    }

    /// `generateSpectrumImage`: the hues down the height under the grays across it.
    private static func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let cgContext = context.cgContext
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let hues = hueStops.map { PhotoDrawingColor(rgb: $0).cgColor }
            let hueLocations = hues.indices.map { CGFloat($0) / CGFloat(hues.count - 1) }
            if let gradient = CGGradient(colorsSpace: space, colors: hues as CFArray, locations: hueLocations) {
                cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let grays = grayStops.map {
                PhotoDrawingColor(rgb: $0.white * 0x010101, alpha: CGFloat($0.alpha) / 255).cgColor
            }
            let grayLocations = grays.indices.map { CGFloat($0) / CGFloat(grays.count - 1) }
            if let gradient = CGGradient(colorsSpace: space, colors: grays as CFArray, locations: grayLocations) {
                cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
        }
    }

    func setSelection(color: PhotoDrawingColor?, position: CGPoint?) {
        selectedColor = color
        selectedPosition = position
        layoutKnob()
    }

    /// ColorSpectrumPickerView's `handlePan(point:)` while the color button is held: `point` is in the window and
    /// clamped to the spectrum.
    func track(windowPoint point: CGPoint) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        var location = convert(point, from: nil)
        location.x = max(0, min(bounds.width - 1, location.x))
        location.y = max(0, min(bounds.height - 1, location.y))
        pick(at: location)
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }

    private func layoutKnob() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let selectedColor, let selectedPosition, bounds.width > 0 else {
            knobLayer.isHidden = true
            circleLayer.isHidden = true
            return
        }
        let scale = max(1, traitCollection.displayScale)
        let knob = CGRect(
            x: floor((bounds.width * selectedPosition.x - 16) * scale) / scale,
            y: floor((bounds.height * selectedPosition.y - 16) * scale) / scale - knobOffset,
            width: 32,
            height: 32,
        )
        knobLayer.isHidden = false
        circleLayer.isHidden = false
        knobLayer.frame = knob.insetBy(dx: -10, dy: -10)
        circleLayer.fillColor = selectedColor.cgColor
        circleLayer.frame = knob.insetBy(dx: 3, dy: 3)
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        pick(at: recognizer.location(in: self))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed else { return }
        pick(at: recognizer.location(in: self))
    }

    private func pick(at point: CGPoint) {
        guard bounds.width > 0, bounds.height > 0, point.x >= 0, point.x <= bounds.width, point.y >= 0,
              point.y <= bounds.height
        else { return }
        let position = CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)
        let color = Self.color(at: position)
        guard color != selectedColor || position != selectedPosition else { return }
        setSelection(color: color, position: position)
        onSelect?(color, position)
    }
}

// MARK: - PhotoDrawingColorSlider

/// ColorSliderComponent: a 36 pt capsule from one color to another, over a checkerboard when either end shows
/// through, with a knob in the current color.
final class PhotoDrawingColorSlider: UIView, UIGestureRecognizerDelegate {
    // MARK: Internal

    /// `generateKnobImage`: a dark 32 pt disc with its shadow, 10 pt of margin around it.
    static let knobImage: UIImage = {
        let size = CGSize(width: 52, height: 52)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setShadow(offset: .zero, blur: 9, color: UIColor(white: 0, alpha: 0.3).cgColor)
            context.cgContext.setFillColor(UIColor(rgb: 0x1A1A1C).cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: 10, y: 10, width: 32, height: 32))
        }
    }()

    // MARK: Private

    /// `generateCheckeredImage`'s 12 pt white and clear squares.
    private static let checkerTile: UIImage = {
        let length: CGFloat = 12
        let size = CGSize(width: length * 2, height: length * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: length, y: 0, width: length, height: length))
            context.fill(CGRect(x: 0, y: length, width: length, height: length))
        }
    }()

    var onChange: ((CGFloat) -> Void)?

    private let wrapperView = UIView()
    private let transparencyLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let knobLayer = CALayer()
    private let circleLayer = CAShapeLayer()
    private var value: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        wrapperView.clipsToBounds = true
        wrapperView.layer.cornerRadius = 18
        wrapperView.isUserInteractionEnabled = false
        addSubview(wrapperView)
        transparencyLayer.backgroundColor = UIColor(patternImage: Self.checkerTile).cgColor
        wrapperView.layer.addSublayer(transparencyLayer)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        wrapperView.layer.addSublayer(gradientLayer)
        knobLayer.contents = Self.knobImage.cgImage
        layer.addSublayer(knobLayer)
        circleLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 26, height: 26), transform: nil)
        layer.addSublayer(circleLayer)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.01
        press.delegate = self
        addGestureRecognizer(press)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wrapperView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 36)
        transparencyLayer.frame = wrapperView.bounds
        gradientLayer.frame = wrapperView.bounds
        layoutKnob()
        CATransaction.commit()
    }

    func update(left: PhotoDrawingColor, right: PhotoDrawingColor, current: PhotoDrawingColor, value: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.colors = [left.cgColor, right.cgColor]
        transparencyLayer.isHidden = left.alpha >= 1 && right.alpha >= 1
        circleLayer.fillColor = current.cgColor
        self.value = min(max(value, 0), 1)
        layoutKnob()
        CATransaction.commit()
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }

    private func layoutKnob() {
        let scale = max(1, traitCollection.displayScale)
        let knob = CGRect(
            x: 2 + floor((bounds.width - 4 - 32) * value * scale) / scale,
            y: 2,
            width: 32,
            height: 32,
        )
        knobLayer.frame = knob.insetBy(dx: -10, dy: -10)
        circleLayer.frame = knob.insetBy(dx: 3, dy: 3)
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        track(recognizer.location(in: self))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed else { return }
        track(recognizer.location(in: self))
    }

    private func track(_ location: CGPoint) {
        let side: CGFloat = 36
        guard bounds.width > side else { return }
        onChange?(max(0, min(1, (location.x - side / 2) / (bounds.width - side))))
    }
}

// MARK: - PhotoDrawingColorField

/// ColorFieldComponent: a value in a dark rounded field, all of it selected when it gets focus.
final class PhotoDrawingColorField: UIView, UITextFieldDelegate {
    // MARK: Internal

    enum Kind {
        case number(maximum: Int)
        case hex
    }

    var onChange: ((String) -> Void)?

    // MARK: Private

    private let kind: Kind
    private let textField = UITextField()
    private let suffixLabel = UILabel()
    private var currentText = ""

    var isEditing: Bool {
        textField.isFirstResponder
    }

    init(kind: Kind, suffix: String? = nil) {
        self.kind = kind
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous
        textField.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        textField.textColor = .white
        textField.textAlignment = suffix == nil ? .center : .right
        textField.keyboardAppearance = .dark
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .allCharacters
        textField.spellCheckingType = .no
        textField.keyboardType =
            switch kind {
            case .number: .numberPad
            case .hex: .asciiCapable
            }
        textField.delegate = self
        textField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onChange?(textField.text ?? "")
        }, for: .editingChanged)
        addSubview(textField)
        if let suffix {
            suffixLabel.text = suffix
            suffixLabel.font = textField.font
            suffixLabel.textColor = .white
            suffixLabel.isUserInteractionEnabled = false
            addSubview(suffixLabel)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if suffixLabel.superview != nil {
            let size = suffixLabel.intrinsicContentSize
            suffixLabel.frame = CGRect(
                x: bounds.width - size.width - 14,
                y: floor((bounds.height - size.height) / 2),
                width: size.width,
                height: size.height,
            )
            textField.frame = CGRect(x: -33, y: 0, width: bounds.width, height: bounds.height)
        } else {
            textField.frame = bounds
        }
    }

    /// The color's value; a field being typed in keeps its text until it loses focus.
    func setText(_ text: String) {
        currentText = text
        if !textField.isFirstResponder {
            textField.text = text
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.selectAll(nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.text = currentText
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        let updated = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        switch kind {
        case .number(let maximum):
            if updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            guard let value = Int(updated) else { return false }
            return value >= 0 && value <= maximum
        case .hex:
            let digits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            return updated.count <= 6 && updated.rangeOfCharacter(from: digits.inverted) == nil
        }
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        false
    }
}

// MARK: - PhotoDrawingColorSlidersView

/// ColorSlidersComponent: red, green and blue sliders with their values, and the hex value.
final class PhotoDrawingColorSlidersView: UIView {
    // MARK: Internal

    static let height: CGFloat = (ceil(titleFont.lineHeight) + 8 + 36 + 28) * 3 + 36 + 8

    // MARK: Private

    private static let titleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

    var onChange: ((PhotoDrawingColor) -> Void)?

    var color = PhotoDrawingColor.white {
        didSet {
            update()
        }
    }

    private var rows = [(title: UILabel, slider: PhotoDrawingColorSlider, field: PhotoDrawingColorField)]()
    private let hexTitle = UILabel()
    private let hexField = PhotoDrawingColorField(kind: .hex)

    var fields: [PhotoDrawingColorField] {
        rows.map(\.field) + [hexField]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let titles = ["PhotoEditor.Color.Red", "PhotoEditor.Color.Green", "PhotoEditor.Color.Blue"]
        for (channel, key) in titles.enumerated() {
            let title = UILabel()
            title.text = L10n.betterTG(key)
            title.font = Self.titleFont
            title.textColor = UIColor(rgb: 0x9B9DA5)
            addSubview(title)
            let slider = PhotoDrawingColorSlider()
            slider.onChange = { [weak self] value in
                guard let self else { return }
                onChange?(Self.color(color, channel: channel, value: value))
            }
            addSubview(slider)
            let field = PhotoDrawingColorField(kind: .number(maximum: 255))
            field.onChange = { [weak self] text in
                guard let self else { return }
                onChange?(Self.color(color, channel: channel, value: CGFloat(Int(text) ?? 0) / 255))
            }
            addSubview(field)
            rows.append((title, slider, field))
        }
        hexTitle.text = L10n.betterTG("PhotoEditor.Color.Hex")
        hexTitle.font = .systemFont(ofSize: 17)
        hexTitle.textColor = .white
        addSubview(hexTitle)
        hexField.onChange = { [weak self] text in
            guard let self, text.count == 6, let rgb = Int(text, radix: 16) else { return }
            onChange?(PhotoDrawingColor(rgb: rgb, alpha: color.alpha))
        }
        addSubview(hexField)
        update()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let titleHeight = ceil(Self.titleFont.lineHeight)
        var y: CGFloat = 0
        for row in rows {
            row.title.frame = CGRect(x: 5, y: y, width: max(0, width - 5), height: titleHeight)
            y += titleHeight + 8
            row.slider.frame = CGRect(x: 0, y: y, width: max(0, width - 89), height: 36)
            row.field.frame = CGRect(x: width - 77, y: y, width: 77, height: 36)
            y += 36 + 28
        }
        hexField.frame = CGRect(x: width - 77, y: y, width: 77, height: 36)
        let titleSize = hexTitle.intrinsicContentSize
        hexTitle.frame = CGRect(
            x: width - 77 - 12 - titleSize.width,
            y: y + (36 - titleSize.height) / 2,
            width: titleSize.width,
            height: titleSize.height,
        )
    }

    /// `withUpdatedRed`, `withUpdatedGreen` and `withUpdatedBlue`.
    private static func color(_ color: PhotoDrawingColor, channel: Int, value: CGFloat) -> PhotoDrawingColor {
        var updated = color
        let clamped = min(max(value, 0), 1)
        switch channel {
        case 0: updated.red = clamped
        case 1: updated.green = clamped
        default: updated.blue = clamped
        }
        return updated
    }

    private func update() {
        let channels = [color.red, color.green, color.blue]
        for (channel, row) in rows.enumerated() {
            let left = Self.color(color, channel: channel, value: 0).withAlpha(1)
            let right = Self.color(color, channel: channel, value: 1).withAlpha(1)
            row.slider.update(left: left, right: right, current: color, value: channels[channel])
            row.field.setText("\(Int(channels[channel] * 255))")
        }
        hexField.setText(String(format: "%06X", color.rgb))
    }
}

// MARK: - PhotoDrawingColorPreviewView

/// ColorPreviewComponent: the color over a square split between black and white.
final class PhotoDrawingColorPreviewView: UIView {
    // MARK: Internal

    var color = PhotoDrawingColor.white {
        didSet {
            colorView.backgroundColor = color.uiColor
        }
    }

    // MARK: Private

    private let backgroundView = UIImageView()
    private let colorView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        addSubview(backgroundView)
        addSubview(colorView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        colorView.frame = bounds
        if backgroundView.image?.size != bounds.size, bounds.width > 0 {
            backgroundView.image = Self.makeBackground(size: bounds.size)
        }
    }

    /// `generatePreviewBackgroundImage`: black over the top left half, white under it.
    private static func makeBackground(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: size))
            cgContext.move(to: .zero)
            cgContext.addLine(to: CGPoint(x: size.width, y: 0))
            cgContext.addLine(to: CGPoint(x: 0, y: size.height))
            cgContext.closePath()
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.fillPath()
        }
    }
}

// MARK: - PhotoDrawingSwatchButton

/// ColorSwatchComponent's palette swatch: a filled circle, which shrinks inside a ring of its color when chosen.
final class PhotoDrawingSwatchButton: UIControl {
    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1
        }
    }

    // MARK: Internal

    let color: PhotoDrawingColor

    var isChosen = false {
        didSet {
            guard isChosen != oldValue else { return }
            accessibilityTraits = isChosen ? [.button, .selected] : .button
            updatePath(animated: window != nil)
        }
    }

    // MARK: Private

    private let ringLayer = CALayer()
    private let circleLayer = CAShapeLayer()

    init(color: PhotoDrawingColor) {
        self.color = color
        super.init(frame: .zero)
        layer.allowsGroupOpacity = true
        ringLayer.borderWidth = 3
        ringLayer.backgroundColor = UIColor.clear.cgColor
        layer.addSublayer(ringLayer)
        circleLayer.fillColor = color.cgColor
        if color.rgb == 0x000000 {
            circleLayer.strokeColor = UIColor(rgb: 0x1F1F1F).cgColor
            circleLayer.lineWidth = 1
            ringLayer.borderColor = UIColor(rgb: 0x1F1F1F).cgColor
        } else {
            ringLayer.borderColor = color.cgColor
        }
        layer.addSublayer(circleLayer)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = L10n.betterTG("Accessibility.PhotoEditor.Color")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.frame = bounds
        ringLayer.cornerRadius = bounds.width / 2
        circleLayer.frame = bounds
        updatePath(animated: false)
        CATransaction.commit()
    }

    private func updatePath(animated: Bool) {
        let path = CGPath(ellipseIn: isChosen ? bounds.insetBy(dx: 5, dy: 5) : bounds, transform: nil)
        if animated, let current = circleLayer.path {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = current
            animation.toValue = path
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            circleLayer.add(animation, forKey: "path")
        }
        circleLayer.path = path
    }
}

// MARK: - PhotoDrawingEyedropperView

/// EyedropperView: a loupe over the photo showing it fifteen times larger on a pixel grid, its ring in the color
/// under the center square. Dragging moves it, and lifting the finger picks the color.
final class PhotoDrawingEyedropperView: UIView {
    // MARK: Private

    private static let size = CGSize(width: 148, height: 148)
    private static let outerWidth: CGFloat = 12
    private static let ringWidth: CGFloat = 5
    private static let selectionWidth: CGFloat = 4

    /// `generateShadowImage`.
    private static let shadowImage: UIImage = {
        let inset: CGFloat = 60
        let imageSize = CGSize(width: size.width + inset * 2, height: size.height + inset * 2)
        return UIGraphicsImageRenderer(size: imageSize).image { context in
            context.cgContext.setShadow(offset: .zero, blur: 40, color: UIColor(white: 0, alpha: 0.9).cgColor)
            context.cgContext.setFillColor(UIColor(white: 0, alpha: 0.1).cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: inset, y: inset, width: size.width, height: size.height))
        }
    }()

    // MARK: Internal

    var onComplete: ((PhotoDrawingColor) -> Void)?
    var onDismiss: (() -> Void)?

    private let pixels: Data
    private let bytesPerRow: Int
    private let pixelSize: CGSize
    private let containerView = UIView()
    private let shadowLayer = CALayer()
    private let clipView = UIView()
    private let zoomedView = UIImageView()
    private let gridLayer = CALayer()
    private let outerColorLayer = CALayer()
    private let ringLayer = CALayer()
    private let selectionLayer = CALayer()
    private var isGridLight = true
    private var currentColor: PhotoDrawingColor?

    /// `snapshot` is the photo with its painting at one pixel a point over the view's bounds, `pixels` its BGRA
    /// bytes.
    init(frame: CGRect, snapshot: CGImage, pixels: Data, bytesPerRow: Int) {
        self.pixels = pixels
        self.bytesPerRow = bytesPerRow
        self.pixelSize = CGSize(width: snapshot.width, height: snapshot.height)
        super.init(frame: frame)
        let bounds = CGRect(origin: .zero, size: Self.size)
        containerView.frame = CGRect(
            x: floor((frame.width - Self.size.width) / 2),
            y: floor((frame.height - Self.size.height) / 2),
            width: Self.size.width,
            height: Self.size.height,
        )
        addSubview(containerView)
        shadowLayer.contents = Self.shadowImage.cgImage
        shadowLayer.frame = bounds.insetBy(dx: -60, dy: -60)
        containerView.layer.addSublayer(shadowLayer)
        let inset = Self.outerWidth + Self.ringWidth
        clipView.frame = bounds.insetBy(dx: inset, dy: inset)
        clipView.clipsToBounds = true
        clipView.layer.cornerRadius = Self.size.width / 2 - inset
        clipView.layer.cornerCurve = .circular
        containerView.addSubview(clipView)
        zoomedView.image = UIImage(cgImage: snapshot, scale: 1, orientation: .up)
        zoomedView.layer.magnificationFilter = .nearest
        zoomedView.bounds = CGRect(origin: .zero, size: pixelSize)
        clipView.addSubview(zoomedView)
        gridLayer.opacity = 0.6
        gridLayer.frame = clipView.bounds
        gridLayer.contents = Self.gridImage(size: clipView.bounds.size, isLight: true).cgImage
        clipView.layer.addSublayer(gridLayer)
        ringLayer.frame = bounds.insetBy(dx: Self.outerWidth, dy: Self.outerWidth)
        ringLayer.cornerRadius = ringLayer.frame.width / 2
        ringLayer.borderWidth = Self.ringWidth
        ringLayer.borderColor = UIColor.white.cgColor
        containerView.layer.addSublayer(ringLayer)
        outerColorLayer.frame = bounds
        outerColorLayer.cornerRadius = bounds.width / 2
        outerColorLayer.borderWidth = Self.outerWidth
        containerView.layer.addSublayer(outerColorLayer)
        selectionLayer.borderColor = UIColor.white.cgColor
        selectionLayer.borderWidth = Self.selectionWidth
        selectionLayer.cornerRadius = 2
        let pixel = 1 / max(1, UITraitCollection.current.displayScale)
        selectionLayer.frame = CGRect(x: clipView.frame.minX + 48, y: clipView.frame.minY + 48, width: 17, height: 17)
            .insetBy(dx: -pixel, dy: -pixel)
        containerView.layer.addSublayer(selectionLayer)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        updateColor()
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.01
        scale.toValue = 1
        scale.damping = 20
        scale.stiffness = 300
        scale.duration = 0.4
        containerView.layer.add(scale, forKey: "scale")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        containerView.layer.add(fade, forKey: "opacity")
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// `generateGridImage`: a line every 14 pt from 7 pt in.
    private static func gridImage(size: CGSize, isLight: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            (isLight ? UIColor.white : UIColor(rgb: 0x505050)).setFill()
            var offset: CGFloat = 7
            for _ in 0..<8 {
                context.fill(CGRect(x: 0, y: offset, width: size.width, height: 1))
                context.fill(CGRect(x: offset, y: 0, width: 1, height: size.height))
                offset += 14
            }
        }
    }

    /// `dismiss`: the loupe goes without a color.
    func dismiss() {
        animateOut()
        onDismiss?()
    }

    private func setColor(_ color: PhotoDrawingColor) {
        currentColor = color
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outerColorLayer.borderColor = color.cgColor
        selectionLayer.backgroundColor = color.cgColor
        let isLightColor = color.lightness > 0.9
        ringLayer.borderColor = isLightColor ? UIColor(rgb: 0x999999).cgColor : UIColor.white.cgColor
        if isGridLight == isLightColor {
            isGridLight = !isLightColor
            gridLayer.contents = Self.gridImage(size: clipView.bounds.size, isLight: isGridLight).cgImage
        }
        CATransaction.commit()
    }

    /// `getColorAt`: black outside the photo.
    private func color(at point: CGPoint) -> PhotoDrawingColor {
        guard point.x >= 0, point.x < pixelSize.width, point.y >= 0, point.y < pixelSize.height else {
            return .black
        }
        let offset = Int(point.y) * bytesPerRow + Int(point.x) * 4
        guard offset + 3 < pixels.count else { return .black }
        return PhotoDrawingColor(
            red: CGFloat(pixels[offset + 2]) / 255,
            green: CGFloat(pixels[offset + 1]) / 255,
            blue: CGFloat(pixels[offset]) / 255,
        )
    }

    private func updateColor() {
        let point = containerView.center
        let scale: CGFloat = 15
        zoomedView.transform = CGAffineTransform(scaleX: scale, y: scale)
        zoomedView.center = CGPoint(
            x: clipView.bounds.width / 2 + (pixelSize.width / 2 - point.x) * scale,
            y: clipView.bounds.height / 2 + (pixelSize.height / 2 - point.y) * scale,
        )
        setColor(color(at: point))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .changed:
            let translation = recognizer.translation(in: self)
            containerView.center = CGPoint(
                x: containerView.center.x + translation.x,
                y: containerView.center.y + translation.y,
            )
            recognizer.setTranslation(.zero, in: self)
            updateColor()
        case .cancelled, .ended:
            guard let currentColor else { return }
            animateOut()
            onComplete?(currentColor)
        default:
            break
        }
    }

    private func animateOut() {
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2, animations: {
            self.containerView.alpha = 0
            self.containerView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }
}
