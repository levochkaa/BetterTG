// MainView.swift

import Combine
import UIKit

final class MainViewController: UIViewController, UISearchResultsUpdating, UIPageViewControllerDataSource,
    UIPageViewControllerDelegate
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
        configureFolderSelector()

        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.reloadFromState() }
            }
            .store(in: &cancellables)
        reloadFromState()
    }

    private let rootVM: RootVM
    private let pageController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
    )
    private let folderSelector = FolderSelectorView()
    private var folderControllers = [FolderViewController]()
    private var cancellables = Set<AnyCancellable>()

    private func configureNavigation() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search chats…"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

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

    private func configurePageController() {
        pageController.dataSource = self
        pageController.delegate = self
        addChild(pageController)
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
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
            folderSelector.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            folderSelector.heightAnchor.constraint(equalToConstant: 48),
            pageController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: folderSelector.topAnchor),
        ])
    }

    private func reloadFromState() {
        let currentIDs = folderControllers.map(\.folder.id)
        let newIDs = rootVM.folders.map(\.id)
        navigationItem.leftBarButtonItem?.isHidden = rootVM.archive == nil

        guard currentIDs != newIDs else {
            folderControllers.forEach { $0.updateQuery(rootVM.query) }
            return
        }

        folderControllers = rootVM.folders.map {
            FolderViewController(folder: $0, rootVM: rootVM, showsStandaloneSearch: false)
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
        pageController.setViewControllers([folderControllers[targetIndex]], direction: direction, animated: animated)
    }

    func updateSearchResults(for searchController: UISearchController) {
        rootVM.query = searchController.searchBar.text ?? ""
        folderControllers.forEach { $0.updateQuery(rootVM.query) }
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
        backgroundColor = UIColor.black.withAlphaComponent(0.9)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.spacing = 8
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
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
