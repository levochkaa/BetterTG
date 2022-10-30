// BetterTG_WatchApp_App.swift

import SwiftUI
import TDLibKit

@main
struct BetterTGWatchApp: App {

    init() {
        TdApi.shared.startTdLibUpdateHandler()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
