// RootView.swift

import Combine
import UIKit

// MARK: - RootViewController

final class RootViewController: UIViewController {
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        displayedController
    }

    // MARK: Private

    private let rootVM: RootVM
    private var displayedController: UIViewController?
    /// Whether the main shell shows, nil for the launch placeholder.
    private var displayedLoggedInState: Bool??
    private var displayedAccountID: UUID?
    private var lastDuoLayout: IPhoneDuoLayout?
    private var cancellables = Set<AnyCancellable>()

    /// An account that signed in before, whose client TDLib is still creating: Telegram opens on its chat list from
    /// the cold start, so the root keeps the launch screen until the shell can show, instead of the sign-in screen's
    /// Waiting for Authorization.
    private var awaitsSignedInClient: Bool {
        !rootVM.loggedIn && TDLib.shared.activeAccount?.userID != nil
            && (TDLib.shared.activeUpdateSource == nil || TDLib.shared.activeAccountIsStarting)
    }

    init(rootVM: RootVM) {
        self.rootVM = rootVM
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.render(animated: true) }
            }
            .store(in: &cancellables)
        // The placeholder gives way once the client reports where the account stands.
        TDLib.shared
            .authorizationUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render(animated: true) }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .appLanguageChanged) { [weak self] _ in
            self?.displayedLoggedInState = nil
            self?.displayedAccountID = nil
            self?.view.semanticContentAttribute = AppLocalization.shared.isRTL ? .forceRightToLeft : .forceLeftToRight
            self?.render(animated: false)
        }
        render(animated: false)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyBarTopSafeArea()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let duoLayout = view.iPhoneDuoLayout
        guard duoLayout != lastDuoLayout else { return }
        lastDuoLayout = duoLayout
        view.window?.setIPhoneDuoBarsNeedLayout()
    }

    private func render(animated: Bool) {
        let loggedInState: Bool? = awaitsSignedInClient ? nil : rootVM.loggedIn
        guard displayedLoggedInState != .some(loggedInState) || displayedAccountID != rootVM.activeAccountID
            || (displayedController as? LoginViewController)?.isRevoked == true else { return }
        displayedLoggedInState = .some(loggedInState)
        displayedAccountID = rootVM.activeAccountID

        let controller: UIViewController
        if loggedInState == nil {
            controller = LaunchPlaceholderViewController()
        } else if rootVM.loggedIn {
            let mainController = MainTabsViewController(rootVM: rootVM)
            controller = NavigationStorage.shared.setRoot(mainController)
        } else {
            controller = LoginViewController(accountID: displayedAccountID)
        }

        let previousController = displayedController
        displayedController = controller
        transition(from: previousController, to: controller, animated: animated)
    }

    private func transition(from oldController: UIViewController?, to newController: UIViewController, animated: Bool) {
        if let oldController, oldController === newController {
            return
        }

        // The navigation controller is shared, so a quick round trip shows it again while it still fades out.
        let isReturning = newController.parent === self
        if isReturning {
            view.bringSubviewToFront(newController.view)
        } else {
            addChild(newController)
            newController.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(newController.view)
            NSLayoutConstraint.activate([
                newController.view.topAnchor.constraint(equalTo: view.topAnchor),
                newController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                newController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                newController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        newController.didMove(toParent: self)

        guard let oldController else {
            newController.view.alpha = 1
            return
        }
        oldController.willMove(toParent: nil)
        let completion = { [weak self] in
            // A later transition may have shown this controller again; it stays.
            guard self?.displayedController !== oldController else { return }
            oldController.view.removeFromSuperview()
            oldController.removeFromParent()
        }
        guard animated else {
            newController.view.alpha = 1
            return completion()
        }

        if !isReturning { newController.view.alpha = 0 }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState], animations: {
            newController.view.alpha = 1
            oldController.view.alpha = 0
        }, completion: { _ in completion() })
    }
}

// MARK: - LaunchPlaceholderViewController

/// The launch screen as Info.plist's UILaunchScreen draws it: its colour, and its image at its own size, across the
/// middle of the screen and down the middle of the safe area.
private final class LaunchPlaceholderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "launchScreenBackground") ?? .systemBackground
        let imageView = UIImageView(image: UIImage(named: "launchScreen"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }
}
