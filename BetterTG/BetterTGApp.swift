// BetterTGApp.swift

import SwiftUI
import TDLibKit
import AVKit
import SDWebImageWebPCoder

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
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio, options: [
                .allowAirPlay,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .interruptSpokenAudioAndMixWithOthers,
                .overrideMutedMicrophoneInterruption
            ])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log("Error setting audioSessionPlay: \(error)")
        }
        
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
