// MainView.swift

import Combine
import TDLibKitDynamic
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
        view.backgroundColor = .systemBackground
        configurePageController()
        configureNavigationBar()
        configureFolderPicker()

        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.reloadFromState() }
            }
            .store(in: &cancellables)
        FolderUnreadStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.reloadFolderUnreadStates() }
            }
            .store(in: &cancellables)
        folderUnreadStates = FolderUnreadStore.shared.states(for: td.id)
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
    private var folderUnreadStates = [ChatList: FolderUnreadState]()

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
        folderPicker.onAction = { [weak self] action, folder in
            self?.performFolderAction(action, for: folder)
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
            folderPicker.configure(
                folders: rootVM.folders,
                selectedID: rootVM.currentFolder,
                unreadStates: folderUnreadStates,
            )
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
        folderPicker.configure(
            folders: rootVM.folders,
            selectedID: rootVM.currentFolder,
            unreadStates: folderUnreadStates,
        )
        guard let selected = rootVM.currentFolder ?? rootVM.folders.first?.id else { return }
        selectFolder(id: selected, animated: false)
    }

    private func reloadFolderUnreadStates() {
        let states = FolderUnreadStore.shared.states(for: td.id)
        guard folderUnreadStates != states else { return }
        folderUnreadStates = states
        folderPicker.configure(
            folders: rootVM.folders,
            selectedID: rootVM.currentFolder,
            unreadStates: folderUnreadStates,
        )
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

    private func performFolderAction(_ action: FolderMenuAction, for folder: CustomFolder) {
        switch action {
        case .editFolders:
            pushFolderController(ChatFoldersViewController(rootVM: rootVM))
        case .reorderTabs:
            pushFolderController(ChatFolderOrderViewController(rootVM: rootVM))
        case .editFolder:
            guard case .folder = folder.type else { return }
            pushFolderController(ChatFolderEditorViewController(rootVM: rootVM, folder: folder))
        case .addChats:
            addChats(to: folder)
        case .readAll:
            markAllChatsAsRead(in: folder)
        case .toggleMute:
            setAllChatsMuted(!folder.areAllChatsMuted, in: folder)
        case .remove:
            confirmFolderRemoval(folder)
        }
    }

    private func pushFolderController(_ controller: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(controller, animated: true)
        } else {
            present(UINavigationController(rootViewController: controller), animated: true)
        }
    }

    private func addChats(to folder: CustomFolder) {
        guard case .folder(let info, let definition) = folder.type else { return }
        let controller = ChatFolderChatSelectionViewController(
            rootVM: rootVM,
            title: "Add Chats",
            selectedChatIDs: Set(definition.includedChatIds)
        ) { [weak self] selectedChatIDs in
            guard let self else { return }
            let updated = definition.replacingIncludedChatIDs(selectedChatIDs)
            Task { @MainActor [weak self] in
                do {
                    _ = try await td.editChatFolder(chatFolderId: info.id, folder: updated)
                } catch {
                    self?.presentFolderError(error)
                }
            }
        }
        pushFolderController(controller)
    }

    private func markAllChatsAsRead(in folder: CustomFolder) {
        Task { @MainActor [weak self] in
            do {
                _ = try await td.readChatList(chatList: folder.chatList)
            } catch {
                self?.presentFolderError(error)
            }
        }
    }

    private func setAllChatsMuted(_ muted: Bool, in folder: CustomFolder) {
        guard case .folder(_, let definition) = folder.type else { return }
        Task { @MainActor [weak self] in
            do {
                let chatCount = try await td.getChatFolderChatCount(folder: definition).count
                guard chatCount <= 200 else {
                    self?.presentFolderNotice(
                        title: "Too Many Chats",
                        message: "Mute All is available for folders with up to 200 chats."
                    )
                    return
                }
                let chatIDs = try await td.getChats(chatList: folder.chatList, limit: 200).chatIds
                var firstError: (any Swift.Error)?
                for chatID in chatIDs {
                    do {
                        let chat = try await td.getChat(chatId: chatID)
                        _ = try await td.setChatNotificationSettings(
                            chatId: chatID,
                            notificationSettings: chat.notificationSettings.replacingMuteFor(
                                muted ? Int(Int32.max) : 0
                            )
                        )
                    } catch {
                        firstError = firstError ?? error
                    }
                }
                if let firstError {
                    self?.presentFolderError(firstError)
                }
            } catch {
                self?.presentFolderError(error)
            }
        }
    }

    private func confirmFolderRemoval(_ folder: CustomFolder) {
        guard case .folder(let info, _) = folder.type else { return }
        let alert = UIAlertController(
            title: "Remove \(folder.name)?",
            message: "The folder will be removed from your account. Its chats won't be deleted or left.",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            Task { @MainActor [weak self] in
                do {
                    _ = try await td.deleteChatFolder(chatFolderId: info.id, leaveChatIds: [])
                    if self?.rootVM.currentFolder == folder.id {
                        self?.rootVM.currentFolder = self?.rootVM.folders.first(where: { $0.id == 0 })?.id
                    }
                } catch {
                    self?.presentFolderError(error)
                }
            }
        })
        present(alert, animated: true)
    }

    private func presentFolderError(_ error: any Swift.Error) {
        presentFolderNotice(title: "Couldn't Update Folder", message: error.localizedDescription)
    }

    private func presentFolderNotice(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

enum FolderMenuAction {
    case editFolders
    case reorderTabs
    case editFolder
    case addChats
    case readAll
    case toggleMute
    case remove
}

/// Telegram's iOS 26 folder strip: a clipped scrolling lens with a continuously
/// moving selection capsule and content-sized (or evenly filled) tabs.
final class FolderPickerView: UIView {
    var onSelection: ((Int) -> Void)?
    var onReselection: ((Int) -> Void)?
    var onAction: ((FolderMenuAction, CustomFolder) -> Void)?

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

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
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
        effect.tintColor = UIColor.label.withAlphaComponent(0.08)
        return UIVisualEffectView(effect: effect)
    }()
    private var folders = [CustomFolder]()
    private var selectedID: Int?
    private var naturalSegmentWidths = [CGFloat]()
    private var resolvedSegmentWidths = [CGFloat]()
    private var segmentWidthConstraints = [NSLayoutConstraint]()
    private var buttons = [FolderButton]()
    private var unreadStates = [FolderUnreadState]()
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

    func configure(
        folders: [CustomFolder],
        selectedID: Int?,
        unreadStates: [ChatList: FolderUnreadState],
    ) {
        let displayedUnreadStates: [FolderUnreadState] = folders.map { folder in
            if case .folder = folder.type {
                unreadStates[folder.chatList] ?? FolderUnreadState.empty
            } else {
                FolderUnreadState.empty
            }
        }
        let needsRebuild = self.folders.count != folders.count || zip(self.folders, folders).contains { pair in
            pair.0.id != pair.1.id || pair.0.name != pair.1.name
        }
        let unreadStatesChanged = self.unreadStates != displayedUnreadStates
        self.folders = folders
        self.unreadStates = displayedUnreadStates
        let resolvedSelectedID = selectedID ?? folders.first?.id
        guard needsRebuild else {
            if unreadStatesChanged {
                updateButtonContents(animated: true)
            }
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
        naturalSegmentWidths = folders.indices.map { index in
            naturalSegmentWidth(for: folders[index], unreadState: unreadStates[index])
        }
        resolvedSegmentWidths = naturalSegmentWidths
        for (index, folder) in folders.enumerated() {
            let button = FolderButton(type: .system)
            button.tag = index
            button.configure(title: folder.name, unreadState: unreadStates[index], animated: false)
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

    private func updateButtonContents(animated: Bool) {
        guard folders.count == buttons.count, unreadStates.count == buttons.count else { return }
        for index in buttons.indices {
            buttons[index].configure(
                title: folders[index].name,
                unreadState: unreadStates[index],
                animated: animated,
            )
        }
        naturalSegmentWidths = folders.indices.map { index in
            naturalSegmentWidth(for: folders[index], unreadState: unreadStates[index])
        }
        updateResolvedWidths()
        layoutSelection(animated: animated)
    }

    private func naturalSegmentWidth(for folder: CustomFolder, unreadState: FolderUnreadState) -> CGFloat {
        max(60, ceil(FolderButton.contentWidth(title: folder.name, unreadCount: unreadState.count)) + 32)
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
            button.updateAppearance(
                titleColor: UIColor.label.withAlphaComponent(0.68 + selectedAlpha * 0.32),
            )
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
            actions: folderActions(for: folder),
            tracking: gesture,
            presentationStyle: .menuOnly,
        )
        button.accessibilityHint = "Actions for \(folder.name)"
    }

    private func folderActions(for folder: CustomFolder) -> [TelegramContextMenuAction] {
        if case .main = folder.type {
            var actions = [
                TelegramContextMenuAction(
                    title: "Edit Folders",
                    image: UIImage(systemName: "square.and.pencil"),
                ) { [weak self] in self?.onAction?(.editFolders, folder) },
            ]
            if folders.count > 1 {
                actions.append(TelegramContextMenuAction(
                    title: "Reorder Tabs",
                    image: UIImage(systemName: "arrow.up.arrow.down"),
                    startsNewSection: true,
                ) { [weak self] in self?.onAction?(.reorderTabs, folder) })
            }
            return actions
        }
        var actions = [
            TelegramContextMenuAction(
                title: "Edit Folder",
                image: UIImage(systemName: "square.and.pencil"),
            ) { [weak self] in self?.onAction?(.editFolder, folder) },
            TelegramContextMenuAction(
                title: "Add Chats",
                image: UIImage(systemName: "person.badge.plus"),
            ) { [weak self] in self?.onAction?(.addChats, folder) },
        ]
        if folder.hasUnreadChats {
            actions.append(TelegramContextMenuAction(
                title: "Read All",
                image: UIImage(systemName: "envelope.open"),
            ) { [weak self] in self?.onAction?(.readAll, folder) })
        }
        actions.append(contentsOf: [
            TelegramContextMenuAction(
                title: folder.areAllChatsMuted ? "Unmute All" : "Mute All",
                image: UIImage(systemName: folder.areAllChatsMuted ? "bell" : "bell.slash"),
            ) { [weak self] in self?.onAction?(.toggleMute, folder) },
            TelegramContextMenuAction(
                title: "Remove",
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.onAction?(.remove, folder) },
        ])
        if folders.count > 1 {
            actions.append(TelegramContextMenuAction(
                title: "Reorder Tabs",
                image: UIImage(systemName: "arrow.up.arrow.down"),
                startsNewSection: true,
            ) { [weak self] in self?.onAction?(.reorderTabs, folder) })
        }
        return actions
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

private final class FolderButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { contentStack.alpha = isHighlighted ? 0.55 : 1 }
    }

    private static let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let badgeFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let activeBadgeTextColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    }

    private let contentStack = UIStackView()
    private let folderTitleLabel = UILabel()
    private let unreadBadgeLabel = FolderUnreadBadgeLabel()
    private var unreadHasUnmuted = false
    private var resolvedTitleColor = UIColor.label

    static func contentWidth(title: String, unreadCount: Int) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
        guard unreadCount > 0 else { return titleWidth }
        let badgeTextWidth = ("\(unreadCount)" as NSString).size(withAttributes: [.font: badgeFont]).width
        return titleWidth + 4 + max(18, badgeTextWidth + 8)
    }

    func configure(title: String, unreadState: FolderUnreadState, animated: Bool) {
        folderTitleLabel.text = title
        accessibilityLabel = title
        accessibilityValue = unreadState.count > 0 ? "\(unreadState.count) unread chats" : nil
        unreadHasUnmuted = unreadState.hasUnmuted

        let wasHidden = unreadBadgeLabel.isHidden
        unreadBadgeLabel.text = "\(unreadState.count)"
        let shouldHide = unreadState.count == 0
        updateAppearance(titleColor: resolvedTitleColor)

        guard animated, wasHidden != shouldHide else {
            unreadBadgeLabel.isHidden = shouldHide
            unreadBadgeLabel.alpha = shouldHide ? 0 : 1
            unreadBadgeLabel.transform = shouldHide
                ? CGAffineTransform(scaleX: 0.4, y: 0.4)
                : .identity
            return
        }
        if !shouldHide {
            unreadBadgeLabel.isHidden = false
            unreadBadgeLabel.alpha = 0
            unreadBadgeLabel.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        }
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.76,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.unreadBadgeLabel.alpha = shouldHide ? 0 : 1
            self.unreadBadgeLabel.transform = shouldHide
                ? CGAffineTransform(scaleX: 0.4, y: 0.4)
                : .identity
        } completion: { _ in
            self.unreadBadgeLabel.isHidden = shouldHide
        }
    }

    func updateAppearance(titleColor: UIColor) {
        resolvedTitleColor = titleColor
        folderTitleLabel.textColor = titleColor
        if unreadHasUnmuted {
            unreadBadgeLabel.backgroundColor = .label
            unreadBadgeLabel.textColor = Self.activeBadgeTextColor
        } else {
            unreadBadgeLabel.backgroundColor = .tertiarySystemFill
            unreadBadgeLabel.textColor = .secondaryLabel
        }
    }

    private func configureViews() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 4
        contentStack.isUserInteractionEnabled = false

        folderTitleLabel.font = Self.titleFont
        folderTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        unreadBadgeLabel.font = Self.badgeFont
        unreadBadgeLabel.textAlignment = .center
        unreadBadgeLabel.layer.cornerRadius = 9
        unreadBadgeLabel.clipsToBounds = true
        unreadBadgeLabel.isHidden = true
        unreadBadgeLabel.alpha = 0

        contentStack.addArrangedSubview(folderTitleLabel)
        contentStack.addArrangedSubview(unreadBadgeLabel)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            unreadBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
}

private final class FolderUnreadBadgeLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let contentSize = super.intrinsicContentSize
        return CGSize(width: max(18, contentSize.width + 8), height: 18)
    }
}
