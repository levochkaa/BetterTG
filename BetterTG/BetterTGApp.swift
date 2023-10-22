// BetterTGApp.swift

import SwiftUI
import TDLibKit
import AVKit
import SDWebImageWebPCoder
import Lottie

@main
struct BetterTGApp: App {
    
    init() {
        startTdLibUpdateHandler()
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
//        UINavigationBar.appearance().compactAppearance = appearance
//        UINavigationBar.appearance().standardAppearance = appearance
//        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
        
        LottieConfiguration.shared.renderingEngine = .specific(.coreAnimation)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
