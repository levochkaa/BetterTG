// BetterTGApp.swift

import SwiftUI
@preconcurrency import TDLibKit
import AVKit

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
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
