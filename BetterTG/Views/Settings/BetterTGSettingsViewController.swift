// BetterTGSettingsViewController.swift

import UIKit

// MARK: - BetterTGSettingsViewController

/// BetterTG's own options in one place, as Swiftgram's SGSettingsController keeps its: the tabs, the chat list's search
/// and folder tabs, and animated media. Each change applies at once.
final class BetterTGSettingsViewController: SettingsListViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BetterTG"
    }

    override func makeSections() -> [SettingsSection] {
        let settings = BetterTGSettings.shared
        let tabsShown = !settings.hidesTabBar
        return [
            SettingsSection(
                header: L10n.betterTG("BetterTGSettings.Tabs"),
                footer: L10n.betterTG("BetterTGSettings.WideTabBarInfo"),
                rows: [
                    toggle("BetterTGSettings.HideTabBar", isOn: settings.hidesTabBar) { settings.hidesTabBar = $0 },
                    toggle("BetterTGSettings.ArchiveTab", isOn: settings.showsArchiveTab, isEnabled: tabsShown) {
                        settings.showsArchiveTab = $0
                    },
                    toggle("BetterTGSettings.SettingsTab", isOn: settings.showsSettingsTab, isEnabled: tabsShown) {
                        settings.showsSettingsTab = $0
                    },
                    toggle("BetterTGSettings.TabNames", isOn: settings.showsTabNames, isEnabled: tabsShown) {
                        settings.showsTabNames = $0
                    },
                    toggle("BetterTGSettings.WideTabBar", isOn: settings.wideTabBar, isEnabled: tabsShown) {
                        settings.wideTabBar = $0
                    },
                ],
            ),
            SettingsSection(
                header: L10n.betterTG("BetterTGSettings.ChatList"),
                footer: L10n.betterTG("BetterTGSettings.SearchBarAtTopInfo"),
                rows: [
                    toggle("BetterTGSettings.SearchBarAtTop", isOn: settings.searchBarAtTop) {
                        settings.searchBarAtTop = $0
                    },
                ],
            ),
            SettingsSection(
                header: L10n.telegram("Settings.ChatFolders"),
                footer: L10n.betterTG("Folders.TabsAtBottomFooter"),
                rows: [
                    toggle("Folders.TabsAtBottom", isOn: FolderTabAppearance.shared.tabsAtBottom) {
                        FolderTabAppearance.shared.tabsAtBottom = $0
                    },
                ],
            ),
            SettingsSection(
                header: L10n.betterTG("Settings.MediaSection"),
                footer: L10n.betterTG("Settings.AnimatedMediaInfo"),
                rows: [
                    {
                        var row = toggle("Settings.AnimatedMedia", isOn: settings.animatedMedia) {
                            settings.animatedMedia = $0
                        }
                        row.style = .subtitle
                        row.detail = L10n.betterTG("Settings.AnimatedMediaFormats")
                        return row
                    }(),
                ],
            ),
        ]
    }

    private func toggle(
        _ key: String,
        isOn: Bool,
        isEnabled: Bool = true,
        onChange: @escaping (Bool) -> Void,
    ) -> SettingsRow {
        var row = SettingsRow(title: L10n.betterTG(key), accessory: .toggle(isOn: isOn) { [weak self] value in
            onChange(value)
            // Hide Tab Bar turns the tab rows off and on.
            self?.reload()
        })
        row.isEnabled = isEnabled
        return row
    }
}
