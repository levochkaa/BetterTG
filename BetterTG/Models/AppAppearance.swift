// AppAppearance.swift

import UIKit

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

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
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    func apply() {
        Self.current = self
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = userInterfaceStyle }
    }

    private static let defaultsKey = "appAppearance"
}
