// BetterTGApp.swift

import AVKit
import SwiftUI
import TDLibKit

// MARK: - BetterTGApp

@main struct BetterTGApp: App {
    // MARK: Lifecycle

    init() {
        TDLib.shared.startTdLibUpdateHandler()

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
//        UINavigationBar.appearance().compactAppearance = appearance
//        UINavigationBar.appearance().standardAppearance = appearance
//        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }

    // MARK: Internal

    @UIApplicationDelegateAdaptor var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }
}

// MARK: - SceneDelegate

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        Utils.screen = scene.screen
    }
}
