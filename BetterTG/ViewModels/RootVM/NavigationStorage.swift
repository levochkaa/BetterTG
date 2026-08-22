// NavigationStorage.swift

import UIKit

@MainActor
final class NavigationStorage {
    private init() {
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.isTranslucent = false
    }

    static let shared = NavigationStorage()

    let navigationController = UINavigationController()

    var viewControllers: [UIViewController] {
        navigationController.viewControllers
    }

    @discardableResult
    func setRoot(_ controller: UIViewController) -> UINavigationController {
        navigationController.setViewControllers([controller], animated: false)
        return navigationController
    }

    func push(_ route: Route, animated: Bool = true) {
        let controller: UIViewController
        switch route {
        case .customChat(let customChat):
            controller = ChatViewController(customChat: customChat)
        case .archive(let customFolder):
            controller = FolderViewController(folder: customFolder, rootVM: .shared, showsStandaloneSearch: true)
        }
        navigationController.pushViewController(controller, animated: animated)
    }

    func pop(animated: Bool = true) {
        navigationController.popViewController(animated: animated)
    }

    func popToRoot(animated: Bool = true) {
        navigationController.popToRootViewController(animated: animated)
    }
}

/// Replaced by the full UIKit chat controller in the chat/messages migration slice.
final class ChatViewController: UIViewController {
    init(customChat: CustomChat) {
        self.customChat = customChat
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = customChat.chat.title

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Migrating chat to UIKit…"
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private let customChat: CustomChat
}
