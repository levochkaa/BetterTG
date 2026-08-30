// BetterTGApp.swift

import AppIntents
import UIKit

// MARK: - AppDelegate

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: Internal

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        PushRelayCoordinator.shared.start()
        RichNotificationCacheCoordinator.shared.start()
        TDLib.shared.startTdLibUpdateHandler()
        logPendingRichNotificationDiagnostics()
        configureAppearance()
        return true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        PushRelayCoordinator.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
    ) {
        PushRelayCoordinator.shared.didFailToRegisterForRemoteNotifications(error)
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
    ) {
        Task {
            let changed = await PushRelayCoordinator.shared.handleBackgroundNotification(userInfo: userInfo)
            completionHandler(changed ? .newData : .noData)
        }
    }

    func applicationDidEnterBackground(_: UIApplication) {
        TDLib.shared.releaseForNotificationService()
    }

    func applicationWillEnterForeground(_: UIApplication) {
        logPendingRichNotificationDiagnostics()
        TDLib.shared.resumeAfterNotificationService()
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role,
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // MARK: Private

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.18)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.35)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .systemBlue
    }

    private func logPendingRichNotificationDiagnostics() {
        for entry in RichNotificationDiagnostics.drain() {
            let fields = entry.fields
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            log("NSE diagnostic: event=\(entry.event)\(fields.isEmpty ? "" : ",\(fields)")")
        }
    }
}

// MARK: - SceneDelegate

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Utils.screen = windowScene.screen

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = AppAppearance.current.userInterfaceStyle
        window.rootViewController = RootViewController(rootVM: .shared)
        window.makeKeyAndVisible()
        self.window = window

        if let response = connectionOptions.notificationResponse {
            Task {
                await PushRelayCoordinator.shared.handleNotificationResponse(response)
            }
        }
    }
}
