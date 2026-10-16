// PhotoCropViewController.swift

import Photos
import UIKit

// MARK: - PhotoCropEdit

/// What TGMediaEditingContext keeps for an edited photo: its adjustments and the grid's thumbnail of the result.
struct PhotoCropEdit {
    let adjustments: PhotoCropAdjustments
    let thumbnail: UIImage?
}

// MARK: - PhotoCropViewController

/// TGPhotoEditorController opened on its crop tab (TGPhotoCropController) for a picked photo: the crop view with its
/// straightening dial, RESET above the toolbar, and the toolbar's Cancel, Rotate, Mirror, Aspect Ratio and Done. Done
/// hands back the crop with a thumbnail of it, or nothing for the whole photo; Cancel asks before it drops changes.
final class PhotoCropViewController: UIViewController {
    // MARK: Private

    /// `TGPhotoEditorToolbarSize`.
    private static let toolbarHeight: CGFloat = 49
    /// `TGPhotoEditorPanelSize`: the straightening dial's room under the photo.
    private static let panelHeight: CGFloat = 115
    /// `TGPhotoCropButtonsWrapperSize`: RESET's strip right above the toolbar.
    private static let buttonsWrapperHeight: CGFloat = 61
    /// `TGPhotoCropAreaInsetSize`.
    private static let areaInset: CGFloat = 9
    /// TGPhotoEditorButton's size; the touch area is larger.
    private static let tabSide: CGFloat = 33
    private static let tabTouchSide: CGFloat = 44
    private static let screenImageSide: CGFloat = 1280
    /// The grid's thumbnails are 256 px squares.
    private static let thumbnailSide: CGFloat = 256
    /// The app's tint for Done and the active tabs, where Telegram's editor uses its accent.
    private static let activeColor = UIColor.systemBlue
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

    /// The finished crop with the grid's thumbnail of it; `nil` when the photo is left whole.
    var onDone: ((PhotoCropEdit?) -> Void)?

    private let image: UIImage
    private let imagePixelSize: CGSize
    private let initialAdjustments: PhotoCropAdjustments?
    private let cropView: PhotoCropView
    private let resetButton = UIButton(type: .system)
    private let toolbarView = UIView()
    private let cancelButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private let mirrorButton = UIButton(type: .system)
    private let aspectRatioButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    /// TGPhotoEditorController's `dismissEditor` test: a new crop off the whole photo, or any change to an earlier one.
    private var hasChanges: Bool {
        let current = cropView.adjustments
        guard let initialAdjustments else { return !current.hasDefaultCropping }
        return current != initialAdjustments
    }

    init(image: UIImage, adjustments: PhotoCropAdjustments?) {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let initial = adjustments?.scaled(to: pixelSize) ?? PhotoCropAdjustments(originalSize: pixelSize)
        self.image = image
        self.imagePixelSize = pixelSize
        self.initialAdjustments = adjustments == nil ? nil : initial
        self.cropView = PhotoCropView(image: image, adjustments: initial)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        cropView.onCroppingChanged = { [weak self] in self?.updateTabs() }
        view.addSubview(cropView)
        configureResetButton()
        configureToolbar()
        updateTabs()
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
        // RESET at 20 pt into its strip above the toolbar, reaching 10 pt further for touches.
        let resetWidth = ceil(resetButton.titleLabel?.intrinsicContentSize.width ?? 0)
        let resetFrame = CGRect(
            x: (bounds.width - resetWidth) / 2,
            y: toolbarTop - Self.buttonsWrapperHeight + 20,
            width: resetWidth,
            height: 24,
        )
        resetButton.frame = resetFrame.insetBy(dx: -10, dy: -10)
        // `photoContainerFrameForParentViewFrame` with the dial's panel, inset by `TGPhotoCropAreaInsetSize`.
        let container = CGRect(
            x: safeArea.left,
            y: safeArea.top,
            width: bounds.width - safeArea.left - safeArea.right,
            height: toolbarTop - Self.panelHeight - safeArea.top,
        )
        cropView.frame = container.insetBy(dx: Self.areaInset, dy: Self.areaInset)
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

    private func configureResetButton() {
        resetButton.setTitle(L10n.telegram("PhotoEditor.CropReset"), for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 13)
        resetButton.tintColor = .white
        resetButton.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)
        view.addSubview(resetButton)
    }

    private func configureToolbar() {
        toolbarView.backgroundColor = .black
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

    /// TGPhotoToolbarView's portrait layout: Cancel and Done in 49 pt squares at the ends, and the three tabs at a
    /// quarter, half and three quarters of the width between them, the outer ones 5 pt further out.
    private func layoutToolbar() {
        let width = toolbarView.bounds.width
        let side = Self.toolbarHeight
        cancelButton.frame = CGRect(x: 0, y: 0, width: side, height: side)
        doneButton.frame = CGRect(x: width - side, y: 0, width: side, height: side)
        let available = width - side * 2
        let sideOffset: CGFloat = 5
        let centers = [
            side + available / 4 - sideOffset,
            side + available / 2,
            side + available * 3 / 4 + sideOffset,
        ]
        let centerY = 8 + Self.tabSide / 2
        for (button, centerX) in zip([rotateButton, mirrorButton, aspectRatioButton], centers) {
            button.bounds = CGRect(x: 0, y: 0, width: Self.tabTouchSide, height: Self.tabTouchSide)
            button.center = CGPoint(x: centerX, y: centerY)
        }
    }

    /// `highlightedTabs`: Mirror while mirrored and Aspect Ratio while a ratio is locked.
    private func updateTabs() {
        let isMirrored = cropView.adjustments.isMirrored
        let isLocked = cropView.isAspectRatioLocked
        mirrorButton.tintColor = isMirrored ? Self.activeColor : .white
        mirrorButton.accessibilityTraits = isMirrored ? [.button, .selected] : .button
        aspectRatioButton.tintColor = isLocked ? Self.activeColor : .white
        aspectRatioButton.accessibilityTraits = isLocked ? [.button, .selected] : .button
    }

    @objc private func resetPressed() {
        cropView.reset(animated: true)
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
        let adjustments = cropView.adjustments
        let croppedSize = adjustments.croppedSize
        let originalSize = adjustments.originalSize
        // Ratios are the crop's height over its width before its quarter turns.
        var choices: [(title: String, ratio: CGFloat)] = [
            (L10n.telegram("PhotoEditor.CropAspectRatioOriginal"), originalSize.height / originalSize.width),
            (L10n.telegram("PhotoEditor.CropAspectRatioSquare"), 1),
        ]
        for definition in Self.ratios {
            let isLandscape = croppedSize.width >= croppedSize.height
            let widthComponent = isLandscape ? definition.longer : definition.shorter
            let heightComponent = isLandscape ? definition.shorter : definition.longer
            let ratio = heightComponent / widthComponent
            choices.append((
                "\(Int(widthComponent)):\(Int(heightComponent))",
                adjustments.orientation.isSideward ? 1 / ratio : ratio,
            ))
        }
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
        guard !cropView.isTracking, !cropView.isAnimating else { return }
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

    /// `doneButtonPressed`: a waiting change settles, and a crop of the whole photo without a locked ratio counts
    /// as no edit (PGPhotoEditorValues' `isDefaultValues`).
    @objc private func donePressed() {
        guard !cropView.isTracking else { return }
        cropView.commitPendingChanges()
        let adjustments = cropView.adjustments
        var edit: PhotoCropEdit?
        if !adjustments.hasDefaultCropping || cropView.isAspectRatioLocked {
            edit = PhotoCropEdit(adjustments: adjustments, thumbnail: thumbnail(of: adjustments))
        }
        onDone?(edit)
        dismiss(animated: true)
    }

    /// The crop's picture for the square grid cell, its shorter side at least the cell's.
    private func thumbnail(of adjustments: PhotoCropAdjustments) -> UIImage? {
        let size = adjustments.croppedSize
        let shorter = min(size.width, size.height)
        guard shorter > 0 else { return nil }
        let longest = Self.thumbnailSide * max(size.width, size.height) / shorter
        return adjustments.render(image, sourcePixelSize: imagePixelSize, maximumSide: min(longest, 1024))
    }
}
