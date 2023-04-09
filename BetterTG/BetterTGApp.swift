// BetterTGApp.swift

import SwiftUI
import TDLibKit
import AVKit
import SDWebImageWebPCoder
import Lottie

@main
struct BetterTGApp: App {
    
    init() {
        TdApi.shared.startTdLibUpdateHandler()
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
//        UINavigationBar.appearance().compactAppearance = appearance
//        UINavigationBar.appearance().standardAppearance = appearance
//        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
        
        UIApplication.window?.overrideUserInterfaceStyle = .dark
        UIApplication.keyWindow?.overrideUserInterfaceStyle = .dark
        
        LottieConfiguration.shared.renderingEngine = .specific(.coreAnimation)
        LottieLogger.shared = .printToConsole
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        }
    }
}
