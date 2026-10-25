// WebBrowser.swift

import SafariServices
import UIKit

// MARK: - WebBrowser

/// Telegram's Open Links In (WebBrowserSettings with OpenInOptions' browsers): links outside Telegram open inside the
/// app, or in Safari or another browser installed on the device, with each browser's own URL form. BetterTG's
/// in-app browser is Safari's view controller rather than Telegram's own browser.
enum WebBrowser: String, CaseIterable {
    case telegram
    case safari
    case chrome
    case firefox
    case firefoxFocus
    case operaMini
    case operaTouch
    case duckDuckGo
    case edge
    case yandex
    case brave
    case dolphin
    case onion
    case ucbrowser
    case alook
    case vivaldi

    private static let key = "BetterTG.webBrowser"

    /// The chosen browser, the in-app one by default as in Telegram; one no longer installed counts as Safari.
    @MainActor static var current: WebBrowser {
        get {
            let stored = UserDefaults.standard.string(forKey: key).flatMap(WebBrowser.init(rawValue:)) ?? .telegram
            return stored.isAvailable ? stored : .safari
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// The in-app browser, Safari and the browsers installed now, in OpenInOptions' order.
    @MainActor static var available: [WebBrowser] {
        allCases.filter(\.isAvailable)
    }

    var title: String {
        switch self {
        case .telegram: L10n.telegram("WebBrowser.Telegram")
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .firefoxFocus: "Firefox Focus"
        case .operaMini: "Opera Mini"
        case .operaTouch: "Opera Touch"
        case .duckDuckGo: "DuckDuckGo"
        case .edge: "Microsoft Edge"
        case .yandex: "Yandex Browser"
        case .brave: "Brave"
        case .dolphin: "Dolphin"
        case .onion: "Onion Browser"
        case .ucbrowser: "UC Browser"
        case .alook: "Alook Browser"
        case .vivaldi: "Vivaldi"
        }
    }

    /// The scheme that tells whether the browser is installed; nil for the in-app browser and Safari.
    private var scheme: String? {
        switch self {
        case .safari,
             .telegram: nil
        case .chrome: "googlechrome"
        case .firefox: "firefox"
        case .firefoxFocus: "firefox-focus"
        case .operaMini: "opera-http"
        case .operaTouch: "touch-http"
        case .duckDuckGo: "ddgQuickLink"
        case .edge: "microsoft-edge-http"
        case .yandex: "yandexbrowser-open-url"
        case .brave: "brave"
        case .dolphin: "dolphin"
        case .onion: "onionhttp"
        case .ucbrowser: "ucbrowser"
        case .alook: "alook"
        case .vivaldi: "vivaldi"
        }
    }

    @MainActor private var isAvailable: Bool {
        guard let scheme, let url = URL(string: scheme + "://") else { return true }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Opens a web link in the chosen browser: the in-app one over `presenter`, or the browser's app. Links that
    /// aren't http or https go to the system.
    @MainActor static func open(_ url: URL, from presenter: UIViewController?) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            UIApplication.shared.open(url)
            return
        }
        let browser = current
        if browser == .telegram, let presenter = presenter?.topmostPresented {
            let controller = SFSafariViewController(url: url)
            controller.dismissButtonStyle = .close
            presenter.present(controller, animated: true)
            return
        }
        UIApplication.shared.open(browser.externalURL(for: url) ?? url)
    }

    /// OpenInOptions' URL for the browser.
    private func externalURL(for url: URL) -> URL? {
        let string = url.absoluteString
        let queryEscaped = string.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)
        func replacingScheme(http: String, https: String) -> URL? {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
            components.scheme = components.scheme == "https" ? https : http
            return components.url
        }
        switch self {
        case .telegram:
            return url
        case .safari:
            // Safari even where another browser is the system's default.
            return string.hasPrefix("https://")
                ? URL(string: string.replacing("https://", with: "x-safari-https://"))
                : url
        case .chrome:
            return replacingScheme(http: "googlechrome", https: "googlechromes")
        case .firefox:
            return queryEscaped.flatMap { URL(string: "firefox://open-url?url=\($0)") }
        case .firefoxFocus:
            return queryEscaped.flatMap { URL(string: "firefox-focus://open-url?url=\($0)") }
        case .operaMini:
            return replacingScheme(http: "opera-http", https: "opera-https")
        case .operaTouch:
            return replacingScheme(http: "touch-http", https: "touch-https")
        case .duckDuckGo:
            return URL(string: "ddgQuickLink://\(string)")
        case .edge:
            return replacingScheme(http: "microsoft-edge-http", https: "microsoft-edge-https")
        case .yandex:
            return string.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
                .flatMap { URL(string: "yandexbrowser-open-url://\($0)") }
        case .brave:
            return queryEscaped.flatMap { URL(string: "brave://open-url?url=\($0)") }
        case .dolphin:
            return URL(string: "dolphin://\(string)")
        case .onion:
            return replacingScheme(http: "onionhttp", https: "onionhttps")
        case .ucbrowser:
            return URL(string: "ucbrowser://\(string)")
        case .alook:
            return URL(string: "alook://\(string)")
        case .vivaldi:
            return replacingScheme(http: "vivaldi", https: "vivaldi")
        }
    }
}

private extension UIViewController {
    var topmostPresented: UIViewController {
        var controller = self
        while let presented = controller.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }
}

private extension CharacterSet {
    /// UrlEscaping's urlQueryValueAllowed: a query value's characters, without RFC 3986's delimiters.
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@" + "!$&'()*+,;=")
        return allowed
    }()
}
