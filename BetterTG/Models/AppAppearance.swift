// AppAppearance.swift

import UIKit

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    // MARK: Private

    private static let defaultsKey = "appAppearance"

    // MARK: Internal

    static var current: AppAppearance {
        get {
            guard let value = UserDefaults.standard.string(forKey: defaultsKey) else { return .system }
            return AppAppearance(rawValue: value) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var title: String {
        switch self {
        case .system: L10n.telegram("AutoNightTheme.System")
        case .light: L10n.telegram("Appearance.ThemeDay")
        case .dark: L10n.telegram("Appearance.ThemeNight")
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor func apply() {
        Self.current = self
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = userInterfaceStyle }
    }
}
