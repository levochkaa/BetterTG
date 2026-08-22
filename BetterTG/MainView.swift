// MainView.swift

import Combine
import UIKit

final class MainViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate
{
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
        title = "BetterTG"
        configureNavigation()
        configurePageController()
        configureSearchHeader()
        configureFolderSelector()

        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.reloadFromState() }
            }
            .store(in: &cancellables)
        reloadFromState()
        configureAutomatedSmokeRoute()
    }

    private let rootVM: RootVM
    private let pageController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
    )
    private let folderSelector = FolderSelectorView()
    private let searchHeader = ChatListNavigationSearchView()
    private var folderControllers = [FolderViewController]()
    private var cancellables = Set<AnyCancellable>()
    private var searchQuery = ""

    private func configureNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "archivebox"),
            style: .plain,
            target: self,
            action: #selector(openArchive),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings),
        )
    }

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
    }

    private func configureSearchHeader() {
        searchHeader.translatesAutoresizingMaskIntoConstraints = false
        searchHeader.onQueryChange = { [weak self] query in
            guard let self else { return }
            searchQuery = query
            folderControllers.forEach { $0.updateQuery(query) }
        }
        searchHeader.onActiveChange = { [weak self] active in
            guard active else { return }
            self?.currentFolderController?.revealSearch(animated: true)
        }
        view.addSubview(searchHeader)
        NSLayoutConstraint.activate([
            searchHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchHeader.heightAnchor.constraint(equalToConstant: ChatListNavigationSearchView.scrollHeight),
        ])
    }

    private func configureFolderSelector() {
        folderSelector.translatesAutoresizingMaskIntoConstraints = false
        folderSelector.onSelection = { [weak self] id in self?.selectFolder(id: id, animated: true) }
        folderSelector.onReselection = { [weak self] id in
            self?.folderControllers.first(where: { $0.folder.id == id })?.scrollToTop()
        }
        view.addSubview(folderSelector)
        NSLayoutConstraint.activate([
            folderSelector.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderSelector.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            folderSelector.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -48),
            folderSelector.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pageController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.bringSubviewToFront(searchHeader)
        view.bringSubviewToFront(folderSelector)
    }

    private func reloadFromState() {
        let currentIDs = folderControllers.map(\.folder.id)
        let newIDs = rootVM.folders.map(\.id)
        navigationItem.leftBarButtonItem?.isHidden = rootVM.archive == nil

        guard currentIDs != newIDs else {
            folderControllers.forEach { $0.updateQuery(searchQuery) }
            return
        }

        folderControllers = rootVM.folders.map { folder in
            let controller = FolderViewController(folder: folder, rootVM: rootVM, showsStandaloneSearch: false)
            controller.updateQuery(searchQuery)
            controller.isSearchActive = { [weak self] in self?.searchHeader.isActive == true }
            controller.onSearchScrollOffsetChange = { [weak self, weak controller] offset in
                guard let self, self.currentFolderController === controller else { return }
                searchHeader.applyScroll(offset: offset)
            }
            return controller
        }
        folderSelector.configure(folders: rootVM.folders, selectedID: rootVM.currentFolder)
        guard let selected = rootVM.currentFolder ?? rootVM.folders.first?.id else { return }
        selectFolder(id: selected, animated: false)
    }

    private func selectFolder(id: Int, animated: Bool) {
        guard let targetIndex = folderControllers.firstIndex(where: { $0.folder.id == id }) else { return }
        let previousIndex = folderControllers.firstIndex(where: { $0.folder.id == rootVM.currentFolder }) ?? targetIndex
        let direction: UIPageViewController.NavigationDirection = targetIndex >= previousIndex ? .forward : .reverse
        rootVM.currentFolder = id
        folderSelector.select(id: id)
        searchHeader.applyScroll(offset: folderControllers[targetIndex].searchScrollOffset, animated: animated)
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
        folderSelector.select(id: folder.id)
        if let currentFolderController {
            searchHeader.applyScroll(offset: currentFolderController.searchScrollOffset, animated: true)
        }
    }

    @objc private func openArchive() {
        guard let archive = rootVM.archive else { return }
        NavigationStorage.shared.push(.archive(archive))
    }

    @objc private func openSettings() {
        present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
    }
}

final class FolderSelectorView: UIView {
    var onSelection: ((Int) -> Void)?
    var onReselection: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.spacing = 8
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -4),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private var selectedID: Int?
    private var buttons = [Int: UIButton]()

    func configure(folders: [CustomFolder], selectedID: Int?) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        for folder in folders {
            var configuration = UIButton.Configuration.gray()
            configuration.title = folder.name
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
            let button = UIButton(configuration: configuration)
            button.tag = folder.id
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
            buttons[folder.id] = button
        }
        select(id: selectedID ?? folders.first?.id)
    }

    func select(id: Int?) {
        selectedID = id
        for (buttonID, button) in buttons {
            button.configuration?.baseBackgroundColor = buttonID == id ? .systemBlue : .secondarySystemBackground
            button.configuration?.baseForegroundColor = .white
        }
        guard let id, let button = buttons[id] else { return }
        scrollView.scrollRectToVisible(button.frame.insetBy(dx: -24, dy: 0), animated: true)
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        if selectedID == sender.tag {
            onReselection?(sender.tag)
        } else {
            onSelection?(sender.tag)
        }
    }
}
