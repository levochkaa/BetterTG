// EnergyUsage.swift

import UIKit

// MARK: - EnergySavingRole

/// A player's place in Power Saving: the process it follows, and while that is off whether it plays a single pass (a
/// message's sticker or emoji, as ChatMessageAnimatedStickerItemNode and the text's emoji stop looping) or holds its
/// first frame (panels, lists and reactions, which stop animating).
struct EnergySavingRole {
    enum Playback {
        case once
        case still
    }

    let item: EnergyUsage.Item
    let whenOff: Playback

    /// How the player is held now; nil while its process runs.
    @MainActor var limit: Playback? {
        EnergyUsage.shared.allows(item) ? nil : whenOff
    }
}

// MARK: - EnergyUsage

/// Telegram's EnergyUsageSettings with SharedAccountContext's power saving: the battery level below which Power Saving
/// Mode turns every resource-intensive process off (4% and below never, 96% and above always), and the processes
/// themselves, kept on the device. BetterTG has counterparts for Autoplay GIFs, Sticker Animations and Emoji
/// Animations; it doesn't autoplay videos, keeps no background time or preloading, and draws the system's materials.
@MainActor final class EnergyUsage {
    enum Item: String, CaseIterable {
        case autoplayGif
        case loopStickers
        case loopEmoji

        var symbol: String {
            switch self {
            case .autoplayGif: "play.rectangle.fill"
            case .loopStickers: "face.smiling.inverse"
            case .loopEmoji: "smiley.fill"
            }
        }

        var tint: UIColor {
            switch self {
            case .autoplayGif: .systemBlue
            case .loopStickers: .systemGreen
            case .loopEmoji: .systemTeal
            }
        }

        var title: String {
            switch self {
            case .autoplayGif: L10n.telegram("PowerSavingScreen.OptionAutoplayGifTitle")
            case .loopStickers: L10n.telegram("PowerSavingScreen.OptionAutoplayStickersTitle")
            case .loopEmoji: L10n.telegram("PowerSavingScreen.OptionAutoplayEmojiTitle")
            }
        }

        var text: String {
            switch self {
            case .autoplayGif: L10n.telegram("PowerSavingScreen.OptionAutoplayGifText")
            case .loopStickers: L10n.telegram("PowerSavingScreen.OptionAutoplayStickersText")
            case .loopEmoji: L10n.telegram("PowerSavingScreen.OptionAutoplayEmojiText")
            }
        }
    }

    /// Posted when a process is allowed or stopped, by a setting or the battery.
    static let didChange = Notification.Name("BetterTG.EnergyUsage.didChange")

    static let shared = EnergyUsage()

    private static let thresholdKey = "BetterTG.energyUsage.activationThreshold"

    /// Whether Power Saving Mode is on now, so every process is off.
    private(set) var isPowerSavingOn = false

    /// The battery percentage Power Saving Mode starts at; Telegram's default is 15.
    var activationThreshold: Int {
        get { UserDefaults.standard.object(forKey: Self.thresholdKey) as? Int ?? 15 }
        set {
            UserDefaults.standard.set(max(4, min(96, newValue)), forKey: Self.thresholdKey)
            updatePowerSaving(force: true)
        }
    }

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.isPowerSavingOn = Self.shouldBeOnNow(threshold: activationThreshold)
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main,
        ) { _ in
            MainActor.assumeIsolated { EnergyUsage.shared.updatePowerSaving() }
        }
    }

    private static func itemKey(_ item: Item) -> String { "BetterTG.energyUsage." + item.rawValue }

    /// automaticEnergyUsageShouldBeOnNow: never at 4% and below, always at 96% and above, else at or below the
    /// threshold while the battery level is known.
    private static func shouldBeOnNow(threshold: Int) -> Bool {
        if threshold <= 4 { return false }
        if threshold >= 96 { return true }
        let level = UIDevice.current.batteryLevel
        return level >= 0 && level <= Float(threshold) / 100
    }

    /// The process's own setting, on by default.
    func isEnabled(_ item: Item) -> Bool {
        UserDefaults.standard.object(forKey: Self.itemKey(item)) as? Bool ?? true
    }

    func setEnabled(_ item: Item, _ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.itemKey(item))
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// EnergyUsageSettings.powerSavingDefault turns everything off while Power Saving Mode is on.
    func allows(_ item: Item) -> Bool {
        !isPowerSavingOn && isEnabled(item)
    }

    private func updatePowerSaving(force: Bool = false) {
        let isOn = Self.shouldBeOnNow(threshold: activationThreshold)
        guard force || isOn != isPowerSavingOn else { return }
        isPowerSavingOn = isOn
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
