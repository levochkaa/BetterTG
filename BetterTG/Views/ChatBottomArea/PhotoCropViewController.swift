// PhotoCropViewController.swift

import Photos
import UIKit

// MARK: - PhotoCropEdit

/// What TGMediaEditingContext keeps for an edited photo: its adjustments and the grid's thumbnail of the result.
struct PhotoCropEdit {
    let adjustments: PhotoCropAdjustments
    let thumbnail: UIImage?
}

// MARK: - PhotoEditorTab

/// The editor's tabs: TGPhotoCropController's crop and TGPhotoToolsController's tools.
enum PhotoEditorTab {
    case crop
    case tools
}

// MARK: - PhotoToolsTab

/// TGPhotoToolsController's `availableTabs`: the slider list, Tint, Blur and Curves.
enum PhotoToolsTab {
    case list
    case tint
    case blur
    case curves
}

// MARK: - PhotoCropViewController

/// TGPhotoEditorController for a picked photo with its crop tab (TGPhotoCropController) and its tools tab
/// (TGPhotoToolsController), switched at the top like the gallery's edit buttons. The crop tab has the crop view with
/// its straightening dial, RESET above the toolbar, and Rotate, Mirror and Aspect Ratio. The tools tab shows the
/// cropped photo with the tools over it as they change, the tools list, Tint, Blur and Curves; holding the photo shows
/// the original and tapping it hides the controls. Done hands back the crop and tools with a thumbnail, or nothing for
/// an untouched photo; Cancel asks before it drops changes.
final class PhotoCropViewController: UIViewController {
    // MARK: Private

    /// `TGPhotoEditorToolbarSize`.
    private static let toolbarHeight: CGFloat = 49
    /// `TGPhotoEditorPanelSize`: the straightening dial's room under the photo, and Tint's and Curves' panels.
    private static let panelHeight: CGFloat = 115
    /// `TGPhotoEditorToolsPanelSize`: the tools list's panel.
    private static let toolsPanelHeight: CGFloat = 180
    /// `TGPhotoCropButtonsWrapperSize`: RESET's strip right above the toolbar.
    private static let buttonsWrapperHeight: CGFloat = 61
    /// `TGPhotoCropAreaInsetSize`.
    private static let areaInset: CGFloat = 9
    /// The strip at the top with the Crop and Tools tabs.
    private static let tabBarHeight: CGFloat = 44
    /// TGPhotoEditorButton's size; the touch area is larger.
    private static let tabSide: CGFloat = 33
    private static let tabTouchSide: CGFloat = 44
    private static let screenImageSide: CGFloat = 1280
    /// The grid's thumbnails are 256 px squares.
    private static let thumbnailSide: CGFloat = 256
    /// The app's tint for Done and the applied tabs, where Telegram's editor uses its accent.
    private static let activeColor = PhotoEditorColors.accent
    /// TGPhotoCropController's ratios after Original and Square, the longer side first.
    private static let ratios: [(longer: CGFloat, shorter: CGFloat)] = [
        (3, 2),
        (5, 3),
        (4, 3),
        (5, 4),
        (7, 5),
        (16, 9),
    ]

    override var prefersStatusBarHidden: Bool {
        true
    }

    // MARK: Internal

    /// The finished edit with the grid's thumbnail of it; `nil` when the photo is left untouched.
    var onDone: ((PhotoCropEdit?) -> Void)?

    /// TGPhotoCropController's `_autoRotationAngle`: the straightening AUTO applies, zero for none.
    private(set) var autoRotationAngle: CGFloat = 0

    private let image: UIImage
    private let imagePixelSize: CGSize
    /// The full photo's upright pixel size, which PGPhotoEditor gives the grain's scale (`_cropRect.size`).
    private let fullPixelSize: CGSize
    private let initialAdjustments: PhotoCropAdjustments?
    /// The video cover's shape (MediaEditorScreen's `coverEditor`): the crop keeps it, and only Mirror stays in the
    /// crop tab's toolbar, as a quarter turn or another ratio would change the shape.
    private let fixedAspectRatio: CGFloat?
    private let cropView: PhotoCropView
    private let resetButton = UIButton(type: .system)
    private let tabBarView = UIView()
    private let cropTabButton = UIButton(type: .system)
    private let toolsTabButton = UIButton(type: .system)
    private let tabSelectionView = PhotoCropViewController.makeSelectionView()
    private let toolbarView = UIView()
    private let toolbarSelectionView = PhotoCropViewController.makeSelectionView()
    private let cancelButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private let mirrorButton = UIButton(type: .system)
    private let aspectRatioButton = UIButton(type: .system)
    private let toolsListButton = UIButton(type: .system)
    private let tintButton = UIButton(type: .system)
    private let blurButton = UIButton(type: .system)
    private let curvesButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let previewView = UIImageView()
    private let curvesAreaView = PhotoCurvesAreaView()
    private let blurAreaView = PhotoBlurAreaView()
    private let toolsPanelView = UIView()
    private let toolsPanelBackgroundView = UIView()
    private let toolsListView: PhotoToolsListView
    private let tintView = PhotoTintToolView()
    private let blurView = PhotoBlurToolView()
    private let curvesPanelView = PhotoCurvesPanelView()
    private let hudView = PhotoEditorHUDView()
    private let renderQueue = DispatchQueue(label: "BetterTG.PhotoToolsPreview", qos: .userInitiated)
    private let histogramQueue = DispatchQueue(label: "BetterTG.PhotoToolsHistogram", qos: .userInitiated)
    private let horizonQueue = DispatchQueue(label: "BetterTG.PhotoCropHorizon", qos: .userInitiated)
    private let faceQueue = DispatchQueue(label: "BetterTG.PhotoEditorFaces", qos: .userInitiated)

    private var editorTab: PhotoEditorTab
    private var toolsTab = PhotoToolsTab.list
    private var toolValues: PhotoToolValues
    private var curvesChannel = PhotoCurvesChannel.luminance
    /// TGPhotoToolsController's `_preview`: the photo alone on the whole screen.
    private var isPreviewing = false
    /// The photo is held to compare (PGPhotoEditor's `disableAll`).
    private var isShowingOriginal = false
    /// The cropped photo the tools draw over, cut again when the crop changed since.
    private var previewBaseImage: UIImage?
    private var previewSource: PhotoToolsSource?
    private var previewSourceCrop: PhotoCropAdjustments?
    private var previewEditedImage: UIImage?
    private var previewEditedTools: PhotoToolValues?
    private var isRenderingPreview = false
    private var needsPreviewRender = false
    /// The shown photo the histogram was last counted from.
    private weak var histogramImage: UIImage?
    private var isCountingHistogram = false
    private var needsHistogram = false
    /// `_resetButton.selected`: the button reads AUTO and straightens the photo.
    private var isAutoButtonSelected = false

    /// The crop view's crop with the tools, which the crop view doesn't keep across RESET.
    private var currentAdjustments: PhotoCropAdjustments {
        var adjustments = cropView.adjustments
        adjustments.tools = toolValues
        return adjustments
    }

    /// TGPhotoEditorController's `dismissEditor` test: a new edit of the untouched photo, or any change to an earlier
    /// one.
    private var hasChanges: Bool {
        let current = currentAdjustments
        guard let initialAdjustments else { return !current.hasDefaultCropping || !current.tools.isDefault }
        return current != initialAdjustments
    }

    private var isToolTracking: Bool {
        toolsListView.isTracking || tintView.isTracking || blurAreaView.isTracking
    }

    // MARK: Tabs

    private var selectedToolsButton: UIButton {
        switch toolsTab {
        case .list: toolsListButton
        case .tint: tintButton
        case .blur: blurButton
        case .curves: curvesButton
        }
    }

    /// `fullPixelSize` is the library photo's size, so the grain matches the sent photo; the editor's image size
    /// when unknown. `initialToolsTab` is the tools tab's panel when it opens. `fixedAspectRatio`, height over
    /// width, starts a new edit filling the photo in that shape and keeps it.
    init(
        image: UIImage,
        adjustments: PhotoCropAdjustments?,
        fullPixelSize: CGSize? = nil,
        initialTab: PhotoEditorTab = .crop,
        initialToolsTab: PhotoToolsTab = .list,
        fixedAspectRatio: CGFloat? = nil,
    ) {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let fixedRatio = fixedAspectRatio.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        let initial = adjustments?.scaled(to: pixelSize)
            ?? fixedRatio.map { PhotoCropAdjustments.filling(aspectRatio: $0, originalSize: pixelSize) }
            ?? PhotoCropAdjustments(originalSize: pixelSize)
        var fullSize = pixelSize
        if let fullPixelSize, fullPixelSize.width > 0, fullPixelSize.height > 0 {
            let isTurned = (fullPixelSize.width >= fullPixelSize.height) != (pixelSize.width >= pixelSize.height)
            fullSize = isTurned ? CGSize(width: fullPixelSize.height, height: fullPixelSize.width) : fullPixelSize
        }
        self.image = image
        self.imagePixelSize = pixelSize
        self.fullPixelSize = fullSize
        self.initialAdjustments = adjustments == nil && fixedRatio == nil ? nil : initial
        self.fixedAspectRatio = fixedRatio
        self.cropView = PhotoCropView(image: image, adjustments: initial)
        self.toolValues = initial.tools
        self.toolsListView = PhotoToolsListView(values: initial.tools)
        self.editorTab = initialTab
        self.toolsTab = initialToolsTab
        super.init(nibName: nil, bundle: nil)
        cropView.fixedAspectRatio = fixedRatio ?? 0
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        cropView.onCroppingChanged = { [weak self] in self?.croppingChanged() }
        cropView.onInteractionBegan = { [weak self] in self?.setAutoButtonHidden(true) }
        view.addSubview(cropView)
        configurePreview()
        configureResetButton()
        configureToolsPanel()
        view.addSubview(hudView)
        configureTabBar()
        configureToolbar()
        applyVisibility()
        updateTabs()
        schedulePreviewRender()
        detectHorizon()
        detectFaces()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let safeArea = view.safeAreaInsets
        let toolbarTop = bounds.height - safeArea.bottom - Self.toolbarHeight
        toolbarView.frame = CGRect(
            x: 0,
            y: toolbarTop,
            width: bounds.width,
            height: Self.toolbarHeight + safeArea.bottom,
        )
        layoutToolbar()
        tabBarView.frame = CGRect(x: 0, y: safeArea.top, width: bounds.width, height: Self.tabBarHeight)
        layoutTabBar()
        // RESET at 20 pt into its strip above the toolbar, reaching 10 pt further for touches.
        let resetWidth = ceil(resetButton.titleLabel?.intrinsicContentSize.width ?? 0)
        let resetFrame = CGRect(
            x: (bounds.width - resetWidth) / 2,
            y: toolbarTop - Self.buttonsWrapperHeight + 20,
            width: resetWidth,
            height: 24,
        )
        resetButton.frame = resetFrame.insetBy(dx: -10, dy: -10)
        // `photoContainerFrameForParentViewFrame` with the dial's panel under the tabs; the crop area is inset by
        // `TGPhotoCropAreaInsetSize`.
        let container = CGRect(
            x: safeArea.left,
            y: safeArea.top + Self.tabBarHeight,
            width: bounds.width - safeArea.left - safeArea.right,
            height: toolbarTop - Self.panelHeight - safeArea.top - Self.tabBarHeight,
        )
        cropView.frame = container.insetBy(dx: Self.areaInset, dy: Self.areaInset)
        layoutTools(container: container, toolbarTop: toolbarTop)
    }

    /// The photo for the editor as the library shows it, fitted to TGPhotoEditorController's screen image
    /// (`TGPhotoEditorScreenImageHardLimitSize`).
    static func loadImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: screenImageSide, height: screenImageSide),
            contentMode: .aspectFit,
            options: options,
        ) { image, info in
            if image == nil {
                log("Could not read the photo to edit: \(String(describing: info?[PHImageErrorKey]))")
            }
            completion(image)
        }
    }

    /// TGPhotoEditorButton's selection: a light rounded square behind the selected tab.
    static func makeSelectionView() -> UIView {
        let selectionView = UIView(frame: CGRect(x: 0, y: 0, width: tabSide, height: tabSide))
        selectionView.backgroundColor = PhotoEditorColors.selectionBackground
        selectionView.layer.cornerRadius = 8
        selectionView.layer.cornerCurve = .continuous
        selectionView.isUserInteractionEnabled = false
        return selectionView
    }

    /// TGPhotoEditorButton's states: the selected tab dark on its light square, an applied one in the accent color.
    static func style(_ button: UIButton, isSelected: Bool, isApplied: Bool) {
        button.tintColor = isSelected ? PhotoEditorColors.selectedIcon : isApplied ? activeColor : .white
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    /// TGPhotoCropController's aspect ratio sheet: the photo's own ratio, a square, and six more turned to the
    /// crop's longer side. Ratios are the crop's height over its width before its quarter turns.
    static func aspectRatioChoices(for adjustments: PhotoCropAdjustments) -> [(title: String, ratio: CGFloat)] {
        let croppedSize = adjustments.croppedSize
        let originalSize = adjustments.originalSize
        var choices: [(title: String, ratio: CGFloat)] = [
            (L10n.telegram("PhotoEditor.CropAspectRatioOriginal"), originalSize.height / originalSize.width),
            (L10n.telegram("PhotoEditor.CropAspectRatioSquare"), 1),
        ]
        for definition in ratios {
            let isLandscape = croppedSize.width >= croppedSize.height
            let widthComponent = isLandscape ? definition.longer : definition.shorter
            let heightComponent = isLandscape ? definition.shorter : definition.longer
            let ratio = heightComponent / widthComponent
            choices.append((
                "\(Int(widthComponent)):\(Int(heightComponent))",
                adjustments.orientation.isSideward ? 1 / ratio : ratio,
            ))
        }
        return choices
    }

    private static func setVisible(_ view: UIView, _ isVisible: Bool) {
        view.alpha = isVisible ? 1 : 0
        view.isUserInteractionEnabled = isVisible
    }

    /// `setAutorotationAngle:`: a straightening of 5° or more is kept, and the button offers it as AUTO while the
    /// whole photo shows without a locked ratio.
    func setAutoRotationAngle(_ angle: CGFloat) {
        guard abs(angle) >= 5 * .pi / 180 else { return }
        autoRotationAngle = angle
        if cropView.adjustments.hasDefaultCropping, !cropView.isAspectRatioLocked {
            setAutoButtonHidden(false)
        }
    }

    // MARK: Configuration

    private func configurePreview() {
        previewView.contentMode = .scaleToFill
        previewView.isUserInteractionEnabled = true
        previewView.accessibilityIgnoresInvertColors = true
        // TGPhotoEditorPreviewView: holding shows the original, a tap hides the controls.
        let press = UILongPressGestureRecognizer(target: self, action: #selector(previewPressed(_:)))
        press.minimumPressDuration = 0.175
        let tap = UITapGestureRecognizer(target: self, action: #selector(previewTapped))
        tap.require(toFail: press)
        previewView.addGestureRecognizer(press)
        previewView.addGestureRecognizer(tap)
        view.addSubview(previewView)
        curvesAreaView.onValueChanged = { [weak self] curves in
            guard let self else { return }
            toolValues.curves = curves
            toolValuesChanged()
        }
        view.addSubview(curvesAreaView)
        blurAreaView.setValue(toolValues.blur)
        blurAreaView.onValueChanged = { [weak self] blur in
            guard let self else { return }
            toolValues.blur = blur
            toolValuesChanged()
        }
        view.addSubview(blurAreaView)
    }

    private func configureResetButton() {
        resetButton.setTitle(L10n.telegram("PhotoEditor.CropReset"), for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 13)
        resetButton.tintColor = .white
        resetButton.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)
        view.addSubview(resetButton)
    }

    /// TGPhotoToolsController's panel: the list, or Tint's and Curves' controls, on the toolbar's translucent black,
    /// which clears while a slider is dragged so the photo shows.
    private func configureToolsPanel() {
        toolsPanelBackgroundView.backgroundColor = PhotoEditorColors.panelBackground
        toolsPanelBackgroundView.isUserInteractionEnabled = false
        toolsPanelView.addSubview(toolsPanelBackgroundView)
        toolsListView.onValueChanged = { [weak self] tool, value, isReset in
            guard let self else { return }
            toolValues[tool] = value
            toolValuesChanged()
            // The change block: the HUD names the tool while it is dragged, and goes on a reset.
            if isReset {
                hudView.setText(nil)
            } else {
                hudView.setTitle(
                    L10n.telegram(tool.titleKey),
                    value: PhotoTool.stringValue(value, maximumValue: tool.maximumValue) ?? "0.00",
                )
            }
        }
        toolsListView.interactionBegan = { [weak self] in
            self?.toolsPanelBackgroundView.alpha = 0
        }
        toolsListView.interactionEnded = { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.15) { self.toolsPanelBackgroundView.alpha = 1 }
            hudView.setText(nil)
        }
        tintView.backgroundColor = PhotoEditorColors.panelBackground
        tintView.setValue(toolValues.tint)
        tintView.onValueChanged = { [weak self] tint in
            guard let self else { return }
            toolValues.tint = tint
            toolValuesChanged()
        }
        blurView.backgroundColor = PhotoEditorColors.panelBackground
        blurView.setType(toolValues.blur.type)
        blurView.onTypeChanged = { [weak self] type in
            guard let self else { return }
            toolValues.blur.type = type
            blurAreaView.setValue(toolValues.blur)
            toolValuesChanged()
        }
        curvesPanelView.backgroundColor = PhotoEditorColors.panelBackground
        curvesPanelView.onChannelChanged = { [weak self] channel in
            guard let self else { return }
            curvesChannel = channel
            curvesAreaView.setValue(toolValues.curves, channel: channel)
        }
        curvesAreaView.setValue(toolValues.curves, channel: curvesChannel)
        for panel in [toolsListView, tintView, blurView, curvesPanelView] as [UIView] {
            toolsPanelView.addSubview(panel)
        }
        view.addSubview(toolsPanelView)
    }

    /// The gallery's edit buttons for the two tabs.
    private func configureTabBar() {
        tabBarView.addSubview(tabSelectionView)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let items: [(button: UIButton, symbol: String, label: String, action: Selector)] = [
            (cropTabButton, "crop.rotate", L10n.betterTG("Accessibility.PhotoEditor.Crop"), #selector(cropTabPressed)),
            (
                toolsTabButton,
                "slider.horizontal.3",
                L10n.betterTG("Accessibility.PhotoEditor.Tools"),
                #selector(toolsTabPressed),
            ),
        ]
        for item in items {
            item.button.setImage(UIImage(systemName: item.symbol, withConfiguration: symbolConfiguration), for: .normal)
            item.button.accessibilityLabel = item.label
            item.button.addTarget(self, action: item.action, for: .touchUpInside)
            tabBarView.addSubview(item.button)
        }
        view.addSubview(tabBarView)
    }

    private func configureToolbar() {
        toolbarView.backgroundColor = .black
        toolbarView.addSubview(toolbarSelectionView)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let items: [(button: UIButton, symbol: String, label: String, action: Selector)] = [
            (cancelButton, "xmark", L10n.telegram("Common.Cancel"), #selector(cancelPressed)),
            (rotateButton, "rotate.left", L10n.betterTG("Accessibility.PhotoEditor.Rotate"), #selector(rotatePressed)),
            (
                mirrorButton,
                "flip.horizontal",
                L10n.betterTG("Accessibility.PhotoEditor.Mirror"),
                #selector(mirrorPressed),
            ),
            (
                aspectRatioButton,
                "aspectratio",
                L10n.betterTG("Accessibility.PhotoEditor.AspectRatio"),
                #selector(aspectRatioPressed),
            ),
            (
                toolsListButton,
                "slider.horizontal.3",
                L10n.betterTG("Accessibility.PhotoEditor.Adjustments"),
                #selector(toolsListPressed),
            ),
            (tintButton, "drop.halffull", L10n.telegram("PhotoEditor.TintTool"), #selector(tintPressed)),
            (blurButton, "drop", L10n.telegram("PhotoEditor.TiltShift"), #selector(blurPressed)),
            (
                curvesButton,
                "point.topleft.down.to.point.bottomright.curvepath",
                L10n.telegram("PhotoEditor.CurvesTool"),
                #selector(curvesPressed),
            ),
            (doneButton, "checkmark", L10n.telegram("Common.Done"), #selector(donePressed)),
        ]
        for item in items {
            item.button.setImage(UIImage(systemName: item.symbol, withConfiguration: symbolConfiguration), for: .normal)
            item.button.tintColor = .white
            item.button.accessibilityLabel = item.label
            item.button.addTarget(self, action: item.action, for: .touchUpInside)
            toolbarView.addSubview(item.button)
        }
        doneButton.tintColor = Self.activeColor
        view.addSubview(toolbarView)
    }

    // MARK: Layout

    /// TGPhotoToolbarView's portrait layout: Cancel and Done in 49 pt squares at the ends, and the tab's tools between
    /// them: three at a quarter, half and three quarters of the width with the outer ones 5 pt further out, or four at
    /// fifths with the outer ones 5 pt and the inner ones 2.5 pt further out.
    private func layoutToolbar() {
        let width = toolbarView.bounds.width
        let side = Self.toolbarHeight
        cancelButton.frame = CGRect(x: 0, y: 0, width: side, height: side)
        doneButton.frame = CGRect(x: width - side, y: 0, width: side, height: side)
        let available = width - side * 2
        let sideOffset: CGFloat = 5
        let scale = max(1, traitCollection.displayScale)
        let innerOffset = floor(sideOffset / 2 * scale) / scale
        let threeCenters = [
            side + available / 4 - sideOffset,
            side + available / 2,
            side + available * 3 / 4 + sideOffset,
        ]
        let fourCenters = [
            side + available / 5 - sideOffset,
            side + available * 2 / 5 - innerOffset,
            side + available * 3 / 5 + innerOffset,
            side + available * 4 / 5 + sideOffset,
        ]
        let centerY = 8 + Self.tabSide / 2
        let groups: [(buttons: [UIButton], centers: [CGFloat])] = [
            ([rotateButton, mirrorButton, aspectRatioButton], threeCenters),
            ([toolsListButton, tintButton, blurButton, curvesButton], fourCenters),
        ]
        for group in groups {
            for (button, centerX) in zip(group.buttons, group.centers) {
                button.bounds = CGRect(x: 0, y: 0, width: Self.tabTouchSide, height: Self.tabTouchSide)
                button.center = CGPoint(x: centerX, y: centerY)
            }
        }
        toolbarSelectionView.center = selectedToolsButton.center
    }

    private func layoutTabBar() {
        let width = tabBarView.bounds.width
        let centerY = Self.tabBarHeight / 2
        for (button, offset) in [(cropTabButton, -30), (toolsTabButton, 30)] as [(UIButton, CGFloat)] {
            button.bounds = CGRect(x: 0, y: 0, width: Self.tabTouchSide, height: Self.tabTouchSide)
            button.center = CGPoint(x: width / 2 + offset, y: centerY)
        }
        tabSelectionView.center = (editorTab == .crop ? cropTabButton : toolsTabButton).center
    }

    /// TGPhotoToolsController's `updateToolViews` and `updatePreviewView`: the panel over the bottom of the photo's
    /// container, the photo fitted in the container or in the whole screen while previewing, and Curves and Blur over
    /// it.
    private func layoutTools(container: CGRect, toolbarTop: CGFloat) {
        let panelHeight = toolsTab == .list ? Self.toolsPanelHeight : Self.panelHeight
        toolsPanelView.frame = CGRect(x: 0, y: toolbarTop - panelHeight, width: view.bounds.width, height: panelHeight)
        for panel in [toolsPanelBackgroundView, toolsListView, tintView, blurView, curvesPanelView] as [UIView] {
            panel.frame = toolsPanelView.bounds
        }
        hudView.frame = container
        let previewContainer = isPreviewing ? view.bounds : container
        let fitted = PhotoCropAdjustments.scaleToSize(cropView.adjustments.croppedSize, previewContainer.size)
        previewView.frame = CGRect(
            x: previewContainer.midX - fitted.width / 2,
            y: previewContainer.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height,
        )
        curvesAreaView.frame = previewContainer
        curvesAreaView.actualArea = previewView.frame.offsetBy(dx: -previewContainer.minX, dy: -previewContainer.minY)
        // The blur's area is the container's size around the photo's center, and doesn't animate.
        UIView.performWithoutAnimation {
            blurAreaView.frame = CGRect(
                x: previewView.frame.midX - previewContainer.width / 2,
                y: previewView.frame.midY - previewContainer.height / 2,
                width: previewContainer.width,
                height: previewContainer.height,
            )
            blurAreaView.actualAreaSize = previewView.frame.size
        }
    }

    /// What each tab shows; previewing leaves only the photo.
    private func applyVisibility() {
        let isCrop = editorTab == .crop
        let showsControls = !isPreviewing
        Self.setVisible(cropView, isCrop)
        Self.setVisible(resetButton, isCrop)
        Self.setVisible(previewView, !isCrop)
        Self.setVisible(curvesAreaView, !isCrop && toolsTab == .curves)
        Self.setVisible(blurAreaView, !isCrop && toolsTab == .blur)
        Self.setVisible(toolsPanelView, !isCrop && showsControls)
        Self.setVisible(toolsListView, toolsTab == .list)
        Self.setVisible(tintView, toolsTab == .tint)
        Self.setVisible(blurView, toolsTab == .blur)
        Self.setVisible(curvesPanelView, toolsTab == .curves)
        for button in [rotateButton, mirrorButton, aspectRatioButton] {
            Self.setVisible(button, isCrop && (fixedAspectRatio == nil || button === mirrorButton))
        }
        for button in [toolsListButton, tintButton, blurButton, curvesButton] {
            Self.setVisible(button, !isCrop)
        }
        toolbarSelectionView.alpha = isCrop ? 0 : 1
        Self.setVisible(tabBarView, showsControls)
        Self.setVisible(toolbarView, showsControls)
    }

    /// `highlightedTabs` and `activeTab`: Mirror while mirrored, Aspect Ratio while a ratio is locked, a tools tab
    /// while its tools change the photo, and the top tabs while their edits apply.
    private func updateTabs() {
        let adjustments = cropView.adjustments
        let isMirrored = adjustments.isMirrored
        let isLocked = cropView.isAspectRatioLocked
        mirrorButton.tintColor = isMirrored ? Self.activeColor : .white
        mirrorButton.accessibilityTraits = isMirrored ? [.button, .selected] : .button
        aspectRatioButton.tintColor = isLocked ? Self.activeColor : .white
        aspectRatioButton.accessibilityTraits = isLocked ? [.button, .selected] : .button
        let hasSliderValues = PhotoTool.allCases.contains { toolValues[$0] != 0 }
        Self.style(toolsListButton, isSelected: toolsTab == .list, isApplied: hasSliderValues)
        Self.style(tintButton, isSelected: toolsTab == .tint, isApplied: !toolValues.tint.isDefault)
        Self.style(blurButton, isSelected: toolsTab == .blur, isApplied: !toolValues.blur.isDefault)
        Self.style(curvesButton, isSelected: toolsTab == .curves, isApplied: !toolValues.curves.isDefault)
        toolbarSelectionView.center = selectedToolsButton.center
        Self.style(cropTabButton, isSelected: editorTab == .crop, isApplied: !adjustments.hasDefaultCropping)
        Self.style(toolsTabButton, isSelected: editorTab == .tools, isApplied: !toolValues.isDefault)
        tabSelectionView.center = (editorTab == .crop ? cropTabButton : toolsTabButton).center
    }

    /// `presentTab`: the crop settles before the tools draw over it.
    private func setTab(_ newTab: PhotoEditorTab) {
        guard newTab != editorTab, !isToolTracking, !cropView.isTracking, !cropView.isAnimating else { return }
        cropView.commitPendingChanges()
        editorTab = newTab
        isShowingOriginal = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        schedulePreviewRender()
        updateTabs()
        UIView.animate(withDuration: 0.2) { self.applyVisibility() }
    }

    /// `handleTabAction`.
    private func setToolsTab(_ newTab: PhotoToolsTab) {
        guard newTab != toolsTab, !isToolTracking else { return }
        toolsTab = newTab
        switch newTab {
        case .list: break
        case .tint: tintView.setValue(toolValues.tint)
        case .blur:
            blurView.setType(toolValues.blur.type)
            blurAreaView.setValue(toolValues.blur)
        case .curves: curvesAreaView.setValue(toolValues.curves, channel: curvesChannel)
        }
        updateTabs()
        updateHistogram()
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
            self.applyVisibility()
        }
    }

    // MARK: Preview

    private func toolValuesChanged() {
        updateTabs()
        schedulePreviewRender()
    }

    /// The photo cut as the crop says, at the editor's screen size, when the crop changed since it was cut.
    private func preparePreviewSource() {
        var crop = cropView.adjustments
        crop.tools = PhotoToolValues()
        guard crop != previewSourceCrop else { return }
        previewSourceCrop = crop
        previewBaseImage = crop.render(image, sourcePixelSize: imagePixelSize, maximumSide: Self.screenImageSide)
        previewSource = previewBaseImage?.cgImage.flatMap { PhotoToolsSource(image: $0) }
        previewEditedImage = nil
        previewEditedTools = nil
    }

    /// PGPhotoEditor's `processAnimated`: the tools render off the main thread, one pass at a time, and a change
    /// during a pass renders again once it ends.
    private func schedulePreviewRender() {
        guard editorTab == .tools else { return }
        preparePreviewSource()
        updatePreviewImage()
        guard !toolValues.isDefault, previewEditedTools != toolValues,
              let source = previewSource, let crop = previewSourceCrop
        else { return }
        guard !isRenderingPreview else {
            needsPreviewRender = true
            return
        }
        isRenderingPreview = true
        let tools = toolValues
        let grainSize = crop.toolsGrainSize(fullPixelSize: fullPixelSize)
        renderQueue.async { [weak self] in
            let rendered = PhotoToolsRenderer.shared
                .render(source, tools: tools, grainSize: grainSize)
                .map { UIImage(cgImage: $0) }
            DispatchQueue.main.async {
                self?.finishPreviewRender(rendered, tools: tools, source: source)
            }
        }
    }

    private func finishPreviewRender(_ rendered: UIImage?, tools: PhotoToolValues, source: PhotoToolsSource) {
        isRenderingPreview = false
        if source === previewSource {
            previewEditedImage = rendered
            previewEditedTools = rendered == nil ? nil : tools
            updatePreviewImage()
        }
        if needsPreviewRender {
            needsPreviewRender = false
            schedulePreviewRender()
        }
    }

    private func updatePreviewImage() {
        let showsTools = !isShowingOriginal && !toolValues.isDefault
        previewView.image = showsTools ? previewEditedImage ?? previewBaseImage : previewBaseImage
        updateHistogram()
    }

    /// PGPhotoEditor's `histogramSignal` for Curves: the shown photo counted off the main thread whenever it changes
    /// while Curves is open, one count at a time.
    private func updateHistogram() {
        guard editorTab == .tools, toolsTab == .curves, let image = previewView.image, image !== histogramImage else {
            return
        }
        guard !isCountingHistogram else {
            needsHistogram = true
            return
        }
        guard let cgImage = image.cgImage else { return }
        histogramImage = image
        isCountingHistogram = true
        histogramQueue.async { [weak self] in
            let histogram = PhotoHistogram(image: cgImage)
            DispatchQueue.main.async {
                self?.finishHistogram(histogram)
            }
        }
    }

    private func finishHistogram(_ histogram: PhotoHistogram?) {
        isCountingHistogram = false
        if let histogram {
            curvesPanelView.setHistogram(histogram)
        }
        if needsHistogram {
            needsHistogram = false
            updateHistogram()
        }
    }

    @objc private func cropTabPressed() {
        setTab(.crop)
    }

    @objc private func toolsTabPressed() {
        setTab(.tools)
    }

    @objc private func toolsListPressed() {
        setToolsTab(.list)
    }

    @objc private func tintPressed() {
        setToolsTab(.tint)
    }

    @objc private func blurPressed() {
        setToolsTab(.blur)
    }

    @objc private func curvesPressed() {
        setToolsTab(.curves)
    }

    /// `touchedDown` and `touchedUp`: the original while held, named in the HUD.
    @objc private func previewPressed(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isShowingOriginal = true
            hudView.setText(L10n.telegram("PhotoEditor.Original"))
        case .cancelled, .ended, .failed:
            isShowingOriginal = false
            hudView.setText(nil)
        default:
            return
        }
        updatePreviewImage()
    }

    /// `setPreview:`: the controls fade and the photo fills the screen, or back.
    @objc private func previewTapped() {
        guard !isToolTracking else { return }
        isPreviewing.toggle()
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.view.layoutIfNeeded()
            self.applyVisibility()
        }
    }

    /// The horizon's angle for AUTO, found off the main thread as the editor opens.
    private func detectHorizon() {
        let image = image
        horizonQueue.async { [weak self] in
            let angle = PhotoHorizonDetector.straighteningAngle(for: image)
            DispatchQueue.main.async {
                guard let angle else { return }
                self?.setAutoRotationAngle(angle)
            }
        }
    }

    /// TGPhotoEditorController's `detectFaces`: a face found as the editor opens adds Soften Skin to the tools.
    private func detectFaces() {
        let image = image
        faceQueue.async { [weak self] in
            guard PhotoFaceDetector.hasFaces(in: image) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                toolsListView.setHasFaces(true, values: toolValues)
            }
        }
    }

    /// TGPhotoCropController's `croppingChanged`: any crop but the whole photo, or a locked ratio, takes AUTO away.
    private func croppingChanged() {
        updateTabs()
        if !cropView.adjustments.hasDefaultCropping || cropView.isAspectRatioLocked {
            setAutoButtonHidden(true)
        }
    }

    /// `setAutoButtonHidden:`: the button reads AUTO while it would straighten the photo, RESET otherwise.
    private func setAutoButtonHidden(_ hidden: Bool) {
        guard isAutoButtonSelected == hidden else { return }
        isAutoButtonSelected = !hidden
        let title = L10n.telegram(hidden ? "PhotoEditor.CropReset" : "PhotoEditor.CropAuto")
        UIView.performWithoutAnimation {
            resetButton.setTitle(title, for: .normal)
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    /// `resetButtonPressed`: AUTO springs the dial to the found angle and turns into RESET; RESET puts the crop back
    /// and offers AUTO again when there is an angle.
    @objc private func resetPressed() {
        guard !cropView.isAnimatingContent else { return }
        let hasAutoRotationAngle = abs(autoRotationAngle) > .ulpOfOne
        if cropView.adjustments.hasDefaultCropping, !cropView.isAspectRatioLocked, hasAutoRotationAngle,
           isAutoButtonSelected
        {
            cropView.animateRotation(to: autoRotationAngle)
            setAutoButtonHidden(true)
        } else {
            cropView.reset(animated: true)
            if hasAutoRotationAngle {
                setAutoButtonHidden(false)
            }
        }
        updateTabs()
    }

    @objc private func rotatePressed() {
        cropView.rotate90DegreesCounterclockwise()
    }

    @objc private func mirrorPressed() {
        cropView.mirror()
    }

    /// `aspectRatioButtonPressedWithSourceView`: a locked ratio unlocks; otherwise the crop settles and a sheet
    /// offers the photo's own ratio, a square and six more turned to the crop's longer side.
    @objc private func aspectRatioPressed() {
        guard !cropView.isAnimating else { return }
        if cropView.isAspectRatioLocked {
            cropView.unlockAspectRatio()
            return
        }
        cropView.performConfirm(animated: true)
        let choices = Self.aspectRatioChoices(for: cropView.adjustments)
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for choice in choices {
            let ratio = choice.ratio
            sheet.addAction(UIAlertAction(title: choice.title, style: .default) { [weak self] _ in
                // Telegram lets the sheet go first on iPhone.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.cropView.setLockedAspectRatio(ratio, animated: true)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = aspectRatioButton
        sheet.popoverPresentationController?.sourceRect = aspectRatioButton.bounds
        present(sheet, animated: true)
    }

    /// `dismissEditor`: changes are dropped only after Discard Changes.
    @objc private func cancelPressed() {
        // TGPhotoCropController's `isDismissAllowed`.
        guard !cropView.isTracking, !cropView.isAnimating, !isToolTracking else { return }
        guard hasChanges else {
            dismiss(animated: true)
            return
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: L10n.telegram("PhotoEditor.DiscardChanges"),
            style: .destructive,
        ) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = cancelButton
        sheet.popoverPresentationController?.sourceRect = cancelButton.bounds
        present(sheet, animated: true)
    }

    /// `doneButtonPressed`: a waiting change settles, and the whole photo without a locked ratio or tools counts as
    /// no edit (PGPhotoEditorValues' `isDefaultValues`).
    @objc private func donePressed() {
        guard !cropView.isTracking, !cropView.isAnimating, !isToolTracking else { return }
        cropView.commitPendingChanges()
        let adjustments = currentAdjustments
        var edit: PhotoCropEdit?
        if !adjustments.hasDefaultCropping || cropView.isAspectRatioLocked || !adjustments.tools.isDefault {
            edit = PhotoCropEdit(adjustments: adjustments, thumbnail: thumbnail(of: adjustments))
        }
        onDone?(edit)
        dismiss(animated: true)
    }

    /// The edited photo for the square grid cell, its shorter side at least the cell's.
    private func thumbnail(of adjustments: PhotoCropAdjustments) -> UIImage? {
        let size = adjustments.croppedSize
        let shorter = min(size.width, size.height)
        guard shorter > 0 else { return nil }
        let longest = Self.thumbnailSide * max(size.width, size.height) / shorter
        return adjustments.renderEdited(
            image,
            sourcePixelSize: imagePixelSize,
            fullPixelSize: fullPixelSize,
            maximumSide: min(longest, 1024),
        )
    }
}
