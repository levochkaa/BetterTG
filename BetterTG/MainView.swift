// MainView.swift

import Combine
import UIKit

final class MainViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    init(rootVM: RootVM) {
        self.rootVM = rootVM
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePageController()
        configureNavigationBar()
        configureFolderPicker()

        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.reloadFromState() }
            }
            .store(in: &cancellables)
        reloadFromState()
        configureAutomatedSmokeRoute()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateNavigationBarHeight(contentHeight: currentNavigationContentHeight)
    }

    private let rootVM: RootVM
    private let pageController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
    )
    private let folderPicker = FolderPickerView()
    private lazy var customNavigationBar = TelegramListNavigationBar(
        title: "BetterTG",
        placeholder: "Search chats…",
        leftImage: UIImage(systemName: "archivebox"),
        rightImage: UIImage(systemName: "gearshape"),
        leftAction: { [weak self] in self?.openArchive() },
        rightAction: { [weak self] in self?.openSettings() },
    )
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private var currentNavigationContentHeight = TelegramListNavigationBar.expandedContentHeight
    private var folderControllers = [FolderViewController]()
    private var cancellables = Set<AnyCancellable>()
    private var searchQuery = ""
    private var pageScrollObservation: NSKeyValueObservation?
    private var interactiveFolderTransition: (fromID: Int, toID: Int)?

    private func configureAutomatedSmokeRoute() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-ui-smoke-chat") else { return }
        rootVM.$folders
            .compactMap { folders in folders.lazy.flatMap(\.chats).first }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { chat in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NavigationStorage.shared.push(.customChat(chat), animated: false)
                }
            }
            .store(in: &cancellables)
        #endif
    }

    private func configurePageController() {
        pageController.dataSource = self
        pageController.delegate = self
        addChild(pageController)
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        if let scrollView = pageController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            pageScrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.updateInteractiveFolderSelection(from: scrollView)
            }
        }
        NSLayoutConstraint.activate([
            pageController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureNavigationBar() {
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        customNavigationBar.onQueryChange = { [weak self] query in
            guard let self else { return }
            searchQuery = query
            folderControllers.forEach { $0.updateQuery(query) }
        }
        customNavigationBar.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            folderControllers.forEach { $0.setSearchActive(active, animated: $0 === self.currentFolderController) }
            if active {
                customNavigationBar.applyScroll(offset: 0, animated: true)
            }
        }
        customNavigationBar.onVisibleHeightChange = { [weak self] contentHeight in
            self?.updateNavigationBarHeight(contentHeight: contentHeight)
        }
        view.addSubview(customNavigationBar)
        navigationBarHeightConstraint = customNavigationBar.heightAnchor.constraint(
            equalToConstant: currentNavigationContentHeight + view.safeAreaInsets.top,
        )
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
    }

    private func configureFolderPicker() {
        folderPicker.translatesAutoresizingMaskIntoConstraints = false
        folderPicker.onSelection = { [weak self] id in self?.selectFolder(id: id, animated: true) }
        folderPicker.onReselection = { [weak self] id in
            self?.folderControllers.first(where: { $0.folder.id == id })?.scrollToTop()
        }
        view.addSubview(folderPicker)
        NSLayoutConstraint.activate([
            folderPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            folderPicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -58),
            folderPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.bringSubviewToFront(customNavigationBar)
        view.bringSubviewToFront(folderPicker)
    }

    private func updateNavigationBarHeight(contentHeight: CGFloat) {
        currentNavigationContentHeight = contentHeight
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + contentHeight
    }

    private func reloadFromState() {
        let currentIDs = folderControllers.map(\.folder.id)
        let newIDs = rootVM.folders.map(\.id)
        customNavigationBar.setLeftButtonHidden(rootVM.archive == nil)

        guard currentIDs != newIDs else {
            folderControllers.forEach { $0.updateQuery(searchQuery) }
            folderPicker.configure(folders: rootVM.folders, selectedID: rootVM.currentFolder)
            return
        }

        folderControllers = rootVM.folders.map { folder in
            let controller = FolderViewController(folder: folder, rootVM: rootVM, showsStandaloneSearch: false)
            controller.updateQuery(searchQuery)
            controller.isSearchActive = { [weak self] in self?.customNavigationBar.isSearchActive == true }
            controller.onSearchScrollOffsetChange = { [weak self, weak controller] offset in
                guard let self, self.currentFolderController === controller else { return }
                customNavigationBar.applyScroll(offset: offset)
            }
            return controller
        }
        folderPicker.configure(folders: rootVM.folders, selectedID: rootVM.currentFolder)
        guard let selected = rootVM.currentFolder ?? rootVM.folders.first?.id else { return }
        selectFolder(id: selected, animated: false)
    }

    private func selectFolder(id: Int, animated: Bool) {
        guard let targetIndex = folderControllers.firstIndex(where: { $0.folder.id == id }) else { return }
        let previousIndex = folderControllers.firstIndex(where: { $0.folder.id == rootVM.currentFolder }) ?? targetIndex
        let direction: UIPageViewController.NavigationDirection = targetIndex >= previousIndex ? .forward : .reverse
        rootVM.currentFolder = id
        folderPicker.select(id: id, animated: animated)
        customNavigationBar.applyScroll(offset: folderControllers[targetIndex].searchScrollOffset, animated: animated)
        pageController.setViewControllers([folderControllers[targetIndex]], direction: direction, animated: animated)
    }

    private var currentFolderController: FolderViewController? {
        pageController.viewControllers?.first as? FolderViewController
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerBefore viewController: UIViewController,
    ) -> UIViewController? {
        guard let index = folderControllers.firstIndex(where: { $0 === viewController }), index > 0 else { return nil }
        return folderControllers[index - 1]
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerAfter viewController: UIViewController,
    ) -> UIViewController? {
        guard let index = folderControllers.firstIndex(where: { $0 === viewController }),
              index + 1 < folderControllers.count else { return nil }
        return folderControllers[index + 1]
    }

    func pageViewController(
        _: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController],
    ) {
        guard let fromID = currentFolderController?.folder.id,
              let toID = (pendingViewControllers.first as? FolderViewController)?.folder.id
        else { return }
        interactiveFolderTransition = (fromID, toID)
    }

    func pageViewController(
        _: UIPageViewController,
        didFinishAnimating _: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool,
    ) {
        defer { interactiveFolderTransition = nil }
        guard completed, let folder = (pageController.viewControllers?.first as? FolderViewController)?.folder else {
            let previousID = (previousViewControllers.first as? FolderViewController)?.folder.id
            folderPicker.select(id: previousID, animated: true)
            return
        }
        rootVM.currentFolder = folder.id
        folderPicker.select(id: folder.id, animated: true)
        if let currentFolderController {
            customNavigationBar.applyScroll(offset: currentFolderController.searchScrollOffset, animated: true)
        }
    }

    private func updateInteractiveFolderSelection(from scrollView: UIScrollView) {
        guard let transition = interactiveFolderTransition,
              scrollView.bounds.width > 0,
              scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        else { return }
        let fraction = min(1, abs(scrollView.contentOffset.x - scrollView.bounds.width) / scrollView.bounds.width)
        folderPicker.updateSelectionTransition(
            fromID: transition.fromID,
            toID: transition.toID,
            fraction: fraction,
        )
    }

    @objc private func openArchive() {
        guard let archive = rootVM.archive else { return }
        NavigationStorage.shared.push(.archive(archive))
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }
}

/// Telegram's iOS 26 folder strip: a clipped scrolling lens with a continuously
/// moving selection capsule and content-sized (or evenly filled) tabs.
final class FolderPickerView: UIView {
    var onSelection: ((Int) -> Void)?
    var onReselection: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateResolvedWidths()
        layoutSelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let controlEffectView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        return UIVisualEffectView(effect: effect)
    }()
    private let controlContainer = FolderPickerScrollView()
    private let buttonStack = UIStackView()
    private let selectionEffectView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        effect.tintColor = UIColor.white.withAlphaComponent(0.08)
        return UIVisualEffectView(effect: effect)
    }()
    private var folders = [CustomFolder]()
    private var selectedID: Int?
    private var naturalSegmentWidths = [CGFloat]()
    private var resolvedSegmentWidths = [CGFloat]()
    private var segmentWidthConstraints = [NSLayoutConstraint]()
    private var buttons = [FolderButton]()
    private var interactiveSelection: (fromID: Int, toID: Int, fraction: CGFloat)?

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        controlEffectView.translatesAutoresizingMaskIntoConstraints = false
        controlEffectView.layer.cornerCurve = .continuous
        controlEffectView.layer.cornerRadius = 21
        controlEffectView.cornerConfiguration = .capsule()
        controlEffectView.clipsToBounds = true
        addSubview(controlEffectView)

        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.showsHorizontalScrollIndicator = false
        controlContainer.isDirectionalLockEnabled = true
        controlContainer.delaysContentTouches = false
        controlContainer.canCancelContentTouches = true
        controlContainer.clipsToBounds = true
        controlContainer.layer.cornerCurve = .continuous
        controlEffectView.contentView.addSubview(controlContainer)

        selectionEffectView.isUserInteractionEnabled = false
        selectionEffectView.layer.cornerCurve = .continuous
        selectionEffectView.clipsToBounds = true
        controlContainer.addSubview(selectionEffectView)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.alignment = .fill
        buttonStack.distribution = .fill
        buttonStack.spacing = 0
        controlContainer.addSubview(buttonStack)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlEffectView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            controlEffectView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            controlEffectView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            controlEffectView.heightAnchor.constraint(equalToConstant: 42),
            controlContainer.topAnchor.constraint(equalTo: controlEffectView.contentView.topAnchor, constant: 3),
            controlContainer.leadingAnchor.constraint(equalTo: controlEffectView.contentView.leadingAnchor, constant: 3),
            controlContainer.trailingAnchor.constraint(equalTo: controlEffectView.contentView.trailingAnchor, constant: -3),
            controlContainer.bottomAnchor.constraint(equalTo: controlEffectView.contentView.bottomAnchor, constant: -3),
            buttonStack.topAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.topAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.bottomAnchor),
            buttonStack.heightAnchor.constraint(equalTo: controlContainer.frameLayoutGuide.heightAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }

    func configure(folders: [CustomFolder], selectedID: Int?) {
        let needsRebuild = self.folders.count != folders.count || zip(self.folders, folders).contains { pair in
            pair.0.id != pair.1.id || pair.0.name != pair.1.name
        }
        self.folders = folders
        let resolvedSelectedID = selectedID ?? folders.first?.id
        guard needsRebuild else {
            select(id: resolvedSelectedID, animated: true)
            return
        }
        self.selectedID = resolvedSelectedID
        rebuildControl()
    }

    func select(id: Int?, animated: Bool = true) {
        let selectionChanged = selectedID != id
        selectedID = id
        interactiveSelection = nil
        updateButtonAppearance()
        layoutSelection(animated: animated && selectionChanged)
        if selectionChanged {
            scrollSelectedSegmentIntoView(animated: animated)
        }
    }

    func updateSelectionTransition(fromID: Int, toID: Int, fraction: CGFloat) {
        interactiveSelection = (fromID, toID, min(max(0, fraction), 1))
        layoutSelection(animated: false)
        updateButtonAppearance()
    }

    private func rebuildControl() {
        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        segmentWidthConstraints.removeAll()
        buttons.removeAll()
        let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        naturalSegmentWidths = folders.map { folder in
            max(60, ceil((folder.name as NSString).size(withAttributes: [.font: titleFont]).width) + 32)
        }
        resolvedSegmentWidths = naturalSegmentWidths
        for (index, folder) in folders.enumerated() {
            let button = FolderButton(type: .system)
            button.tag = index
            button.setTitle(folder.name, for: .normal)
            button.titleLabel?.font = titleFont
            button.accessibilityLabel = folder.name
            button.addTarget(self, action: #selector(folderPressed(_:)), for: .touchUpInside)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(folderLongPressed(_:)))
            longPress.minimumPressDuration = 0.3
            longPress.allowableMovement = 8
            button.addGestureRecognizer(longPress)
            buttonStack.addArrangedSubview(button)
            let width = button.widthAnchor.constraint(equalToConstant: naturalSegmentWidths[index])
            width.isActive = true
            segmentWidthConstraints.append(width)
            buttons.append(button)
        }
        layoutIfNeeded()
        updateResolvedWidths()
        updateButtonAppearance()
        layoutSelection(animated: false)
        scrollSelectedSegmentIntoView(animated: false)
    }

    private func scrollSelectedSegmentIntoView(animated: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == selectedID }), buttons.indices.contains(index) else { return }
        layoutIfNeeded()
        let selectedFrame = buttons[index].convert(buttons[index].bounds, to: controlContainer)
        let maximumOffset = max(0, controlContainer.contentSize.width - controlContainer.bounds.width)
        let centeredOffset = selectedFrame.midX - controlContainer.bounds.width / 2
        let targetOffset = min(max(0, centeredOffset), maximumOffset)
        controlContainer.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: animated)
    }

    private func updateResolvedWidths() {
        guard !buttons.isEmpty, controlContainer.bounds.width > 0 else { return }
        let naturalTotal = naturalSegmentWidths.reduce(0, +)
        let availableWidth = controlContainer.bounds.width
        let widths: [CGFloat]
        if naturalTotal < availableWidth {
            let regularWidth = floor(availableWidth / CGFloat(buttons.count))
            widths = buttons.indices.map { index in
                index == buttons.count - 1
                    ? availableWidth - regularWidth * CGFloat(buttons.count - 1)
                    : regularWidth
            }
        } else {
            widths = naturalSegmentWidths
        }
        guard widths != resolvedSegmentWidths else { return }
        resolvedSegmentWidths = widths
        for (constraint, width) in zip(segmentWidthConstraints, widths) {
            constraint.constant = width
        }
        controlContainer.alwaysBounceHorizontal = widths.reduce(0, +) > availableWidth + 0.5
        buttonStack.layoutIfNeeded()
    }

    private func layoutSelection(animated: Bool) {
        guard !buttons.isEmpty else {
            selectionEffectView.alpha = 0
            return
        }
        let frame: CGRect?
        if let interactiveSelection,
           let fromIndex = folders.firstIndex(where: { $0.id == interactiveSelection.fromID }),
           let toIndex = folders.firstIndex(where: { $0.id == interactiveSelection.toID }),
           buttons.indices.contains(fromIndex), buttons.indices.contains(toIndex)
        {
            let fromFrame = buttons[fromIndex].convert(buttons[fromIndex].bounds, to: controlContainer)
            let toFrame = buttons[toIndex].convert(buttons[toIndex].bounds, to: controlContainer)
            let fraction = interactiveSelection.fraction
            frame = CGRect(
                x: fromFrame.minX + (toFrame.minX - fromFrame.minX) * fraction,
                y: 0,
                width: fromFrame.width + (toFrame.width - fromFrame.width) * fraction,
                height: controlContainer.bounds.height,
            )
        } else if let index = folders.firstIndex(where: { $0.id == selectedID }), buttons.indices.contains(index) {
            frame = buttons[index].convert(buttons[index].bounds, to: controlContainer)
        } else {
            frame = nil
        }
        guard let frame else {
            selectionEffectView.alpha = 0
            return
        }
        let changes = {
            self.selectionEffectView.frame = frame.insetBy(dx: 1, dy: 1)
            self.selectionEffectView.layer.cornerRadius = self.selectionEffectView.bounds.height / 2
            self.selectionEffectView.alpha = 1
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
    }

    private func updateButtonAppearance() {
        for (index, button) in buttons.enumerated() {
            let selectedAlpha: CGFloat
            if let interactiveSelection,
               let fromIndex = folders.firstIndex(where: { $0.id == interactiveSelection.fromID }),
               let toIndex = folders.firstIndex(where: { $0.id == interactiveSelection.toID })
            {
                if index == fromIndex {
                    selectedAlpha = 1 - interactiveSelection.fraction
                } else if index == toIndex {
                    selectedAlpha = interactiveSelection.fraction
                } else {
                    selectedAlpha = 0
                }
            } else {
                selectedAlpha = folders[index].id == selectedID ? 1 : 0
            }
            button.setTitleColor(UIColor.white.withAlphaComponent(0.68 + selectedAlpha * 0.32), for: .normal)
        }
    }

    @objc private func folderPressed(_ sender: FolderButton) {
        guard folders.indices.contains(sender.tag) else { return }
        let folder = folders[sender.tag]
        if selectedID == folder.id {
            onReselection?(folder.id)
        } else {
            select(id: folder.id, animated: true)
            onSelection?(folder.id)
        }
    }

    @objc private func folderLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? FolderButton,
              folders.indices.contains(button.tag)
        else { return }
        let folder = folders[button.tag]
        nearestViewController?.presentTelegramContextMenu(
            sourceView: button,
            actions: [
                TelegramContextMenuAction(
                    title: "Folder actions coming soon",
                    image: UIImage(systemName: "ellipsis"),
                ) {},
            ],
            tracking: gesture,
        )
        button.accessibilityHint = "Actions for \(folder.name)"
    }
}

private final class FolderPickerScrollView: UIScrollView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func touchesShouldCancel(in _: UIView) -> Bool {
        true
    }
}

private final class FolderButton: UIButton {}
