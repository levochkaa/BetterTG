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
            guard let self, active else { return }
            currentFolderController?.revealSearch(animated: true)
            customNavigationBar.applyScroll(offset: 0, animated: true)
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
        folderPicker.select(id: id)
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
        didFinishAnimating _: Bool,
        previousViewControllers _: [UIViewController],
        transitionCompleted completed: Bool,
    ) {
        guard completed, let folder = (pageController.viewControllers?.first as? FolderViewController)?.folder else { return }
        rootVM.currentFolder = folder.id
        folderPicker.select(id: folder.id)
        if let currentFolderController {
            customNavigationBar.applyScroll(offset: currentFolderController.searchScrollOffset, animated: true)
        }
    }

    @objc private func openArchive() {
        guard let archive = rootVM.archive else { return }
        NavigationStorage.shared.push(.archive(archive))
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }
}

/// Telegram's iOS 26 folder picker pattern: a native UISegmentedControl over blur.
final class FolderPickerView: UIView {
    var onSelection: ((Int) -> Void)?
    var onReselection: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        segmentedWidthConstraint?.constant = max(controlContainer.bounds.width, totalSegmentWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let controlContainer = FolderPickerScrollView()
    private var segmentedControl: UISegmentedControl?
    private var segmentedWidthConstraint: NSLayoutConstraint?
    private var folders = [CustomFolder]()
    private var selectedID: Int?
    private var segmentWidths = [CGFloat]()

    private var totalSegmentWidth: CGFloat {
        segmentWidths.reduce(0, +)
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.showsHorizontalScrollIndicator = false
        controlContainer.alwaysBounceHorizontal = true
        controlContainer.isDirectionalLockEnabled = true
        controlContainer.delaysContentTouches = false
        controlContainer.canCancelContentTouches = true
        controlContainer.clipsToBounds = true
        addSubview(controlContainer)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlContainer.topAnchor.constraint(equalTo: topAnchor),
            controlContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            controlContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            controlContainer.heightAnchor.constraint(equalToConstant: 58),
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
            select(id: resolvedSelectedID)
            return
        }
        self.selectedID = resolvedSelectedID
        rebuildControl()
    }

    func select(id: Int?) {
        let selectedIndex = folders.firstIndex(where: { $0.id == id }) ?? UISegmentedControl.noSegment
        let selectionChanged = selectedID != id || segmentedControl?.selectedSegmentIndex != selectedIndex
        selectedID = id
        segmentedControl?.selectedSegmentIndex = selectedIndex
        guard selectionChanged else { return }
        scrollSelectedSegmentIntoView(animated: true)
    }

    private func rebuildControl() {
        segmentedControl?.removeFromSuperview()
        let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        segmentWidths = folders.map { folder in
            max(60, ceil((folder.name as NSString).size(withAttributes: [.font: titleFont]).width) + 32)
        }
        let actions = folders.map { folder in
            UIAction(title: folder.name) { [weak self] _ in
                guard let self else { return }
                if selectedID == folder.id {
                    onReselection?(folder.id)
                } else {
                    selectedID = folder.id
                    scrollSelectedSegmentIntoView(animated: true)
                    onSelection?(folder.id)
                }
            }
        }
        let control = FolderSegmentedControl(frame: .zero, actions: actions)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.apportionsSegmentWidthsByContent = true
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.selectedSegmentIndex = folders.firstIndex(where: { $0.id == selectedID }) ?? UISegmentedControl.noSegment
        control.setTitleTextAttributes([
            .font: titleFont,
        ], for: .normal)
        control.accessibilityLabel = "Chat Folders"
        controlContainer.addSubview(control)
        segmentedControl = control
        let widthConstraint = control.widthAnchor.constraint(equalToConstant: totalSegmentWidth)
        segmentedWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: controlContainer.frameLayoutGuide.centerYAnchor),
            control.heightAnchor.constraint(equalToConstant: 36),
            widthConstraint,
            controlContainer.contentLayoutGuide.heightAnchor.constraint(equalTo: controlContainer.frameLayoutGuide.heightAnchor),
        ])
        layoutIfNeeded()
        scrollSelectedSegmentIntoView(animated: false)
    }

    private func scrollSelectedSegmentIntoView(animated: Bool) {
        guard let control = segmentedControl, control.selectedSegmentIndex != UISegmentedControl.noSegment else { return }
        layoutIfNeeded()
        let widthScale = control.bounds.width / max(1, totalSegmentWidth)
        let selectedX = segmentWidths.prefix(control.selectedSegmentIndex).reduce(0, +) * widthScale
        let selectedWidth = segmentWidths[control.selectedSegmentIndex] * widthScale
        let selectedCenter = control.frame.minX + selectedX + selectedWidth / 2
        let maximumOffset = max(0, controlContainer.contentSize.width - controlContainer.bounds.width)
        let targetOffset = min(max(0, selectedCenter - controlContainer.bounds.width / 2), maximumOffset)
        controlContainer.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: animated)
    }
}

private final class FolderPickerScrollView: UIScrollView {
    override func touchesShouldCancel(in _: UIView) -> Bool {
        true
    }
}

private final class FolderSegmentedControl: UISegmentedControl {
    override func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        true
    }
}
