// BetterTGApp.swift

import SwiftUI
import TDLibKit

@main
struct BetterTGApp: App {

    init() {
        TdApi.shared.startTdLibUpdateHandler()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
