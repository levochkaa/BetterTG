// BetterTGApp.swift

import SwiftUI
import TDLibKit
import AVKit

@main
struct BetterTGApp: App {
    
    init() {
        TDLib.shared.startTdLibUpdateHandler()
        
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
