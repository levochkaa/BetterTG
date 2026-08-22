// RootView.swift

import Combine
import UIKit

final class RootViewController: UIViewController {
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
        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.render(animated: true) }
            }
            .store(in: &cancellables)
        render(animated: false)
    }

    private let rootVM: RootVM
    private var displayedController: UIViewController?
    private var displayedLoggedInState: Bool?
    private var cancellables = Set<AnyCancellable>()

    private func render(animated: Bool) {
        guard displayedLoggedInState != rootVM.loggedIn else { return }
        displayedLoggedInState = rootVM.loggedIn

        let controller: UIViewController
        if rootVM.loggedIn {
            let mainController = MainViewController(rootVM: rootVM)
            controller = NavigationStorage.shared.setRoot(mainController)
        } else {
            controller = LoginViewController()
        }

        transition(from: displayedController, to: controller, animated: animated)
        displayedController = controller
    }

    private func transition(from oldController: UIViewController?, to newController: UIViewController, animated: Bool) {
        addChild(newController)
        newController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newController.view)
        NSLayoutConstraint.activate([
            newController.view.topAnchor.constraint(equalTo: view.topAnchor),
            newController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            newController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        newController.didMove(toParent: self)

        guard let oldController else { return }
        oldController.willMove(toParent: nil)
        let completion = {
            oldController.view.removeFromSuperview()
            oldController.removeFromParent()
        }
        guard animated else { return completion() }

        newController.view.alpha = 0
        UIView.animate(withDuration: 0.25, animations: {
            newController.view.alpha = 1
            oldController.view.alpha = 0
        }, completion: { _ in completion() })
    }
}
