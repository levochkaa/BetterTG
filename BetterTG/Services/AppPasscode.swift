// AppPasscode.swift

import Combine
import CryptoKit
import LocalAuthentication
import Security
import UIKit

// MARK: - AppPasscode

/// Telegram's app passcode (PasscodeCore with PresentationPasscodeSettings): the passcode's salted hash in the
/// Keychain, its kind, the auto-lock timeout and Face ID, and the lock itself. The app locks at launch while a
/// passcode is set, when it returns after the auto-lock time and when the chat list's lock is tapped; a lock window
/// covers everything until the passcode or Face ID opens it. Five wrong attempts lock entry for a minute.
@MainActor final class AppPasscode {
    enum Kind: String, CaseIterable {
        case fourDigits
        case sixDigits
        case alphanumeric

        var digitCount: Int? {
            switch self {
            case .fourDigits: 4
            case .sixDigits: 6
            case .alphanumeric: nil
            }
        }
    }

    private enum Keys {
        static let kind = "BetterTG.passcode.kind"
        static let autoLock = "BetterTG.passcode.autoLock"
        static let biometrics = "BetterTG.passcode.biometrics"
        static let failedAttempts = "BetterTG.passcode.failedAttempts"
        static let blockedUntil = "BetterTG.passcode.blockedUntil"
        static let keychainService = "BetterTG.passcode"
        static let keychainAccount = "passcode"
    }

    static let shared = AppPasscode()

    /// PasscodeSettings' auto-lock choices: disabled, 1 and 5 minutes, 1 and 5 hours.
    static let autoLockTimeouts: [Int?] = [nil, 60, 5 * 60, 60 * 60, 5 * 60 * 60]

    @Published private(set) var isSet: Bool
    @Published private(set) var isLocked = false

    private let defaults = UserDefaults.standard
    private var lockWindow: UIWindow?
    private var backgroundedAt: Date?

    private(set) var kind: Kind {
        get { defaults.string(forKey: Keys.kind).flatMap(Kind.init(rawValue:)) ?? .fourDigits }
        set { defaults.set(newValue.rawValue, forKey: Keys.kind) }
    }

    /// Seconds away before the app locks; nil never locks on its own. Telegram's default is an hour.
    var autoLockTimeout: Int? {
        get {
            guard defaults.object(forKey: Keys.autoLock) != nil else { return 60 * 60 }
            let value = defaults.integer(forKey: Keys.autoLock)
            return value > 0 ? value : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Keys.autoLock) }
    }

    var usesBiometrics: Bool {
        get { defaults.object(forKey: Keys.biometrics) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.biometrics) }
    }

    /// LocalAuth.biometricAuthentication: Face ID or Touch ID while biometrics can unlock, else none.
    var biometryType: LABiometryType {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        return context.biometryType
    }

    // MARK: Attempts

    var failedAttempts: Int {
        defaults.integer(forKey: Keys.failedAttempts)
    }

    /// When entry opens again after too many wrong attempts.
    var blockedUntil: Date? {
        let value = defaults.double(forKey: Keys.blockedUntil)
        guard value > 0 else { return nil }
        let date = Date(timeIntervalSince1970: value)
        return date > Date() ? date : nil
    }

    private init() {
        self.isSet = Self.readKeychain() != nil
    }

    // MARK: Keychain

    private static func hash(_ passcode: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(passcode.utf8)))
    }

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.keychainAccount,
        ]
    }

    private static func readKeychain() -> Data? {
        var query = query()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func writeKeychain(_ data: Data) {
        deleteKeychain()
        var query = query()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteKeychain() {
        SecItemDelete(query() as CFDictionary)
    }

    // MARK: Passcode

    func setPasscode(_ passcode: String, kind: Kind) {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let record = salt + Self.hash(passcode, salt: salt)
        Self.writeKeychain(record)
        self.kind = kind
        resetFailedAttempts()
        isSet = true
    }

    func removePasscode() {
        Self.deleteKeychain()
        resetFailedAttempts()
        isSet = false
        unlock()
    }

    func verify(_ passcode: String) -> Bool {
        guard let record = Self.readKeychain(), record.count > 16 else { return false }
        let salt = record.prefix(16)
        return Self.hash(passcode, salt: Data(salt)) == record.dropFirst(16)
    }

    func recordFailedAttempt() {
        let attempts = failedAttempts + 1
        defaults.set(attempts, forKey: Keys.failedAttempts)
        // PasscodeEntryControllerNode: every fifth wrong passcode blocks entry for a minute.
        if attempts.isMultiple(of: 5) {
            defaults.set(Date().addingTimeInterval(60).timeIntervalSince1970, forKey: Keys.blockedUntil)
        }
    }

    func resetFailedAttempts() {
        defaults.removeObject(forKey: Keys.failedAttempts)
        defaults.removeObject(forKey: Keys.blockedUntil)
    }

    // MARK: Lock

    /// The scene connected: a set passcode locks the app before anything shows.
    func sceneDidConnect(_ scene: UIWindowScene) {
        guard isSet else { return }
        lock(in: scene)
    }

    func sceneDidEnterBackground() {
        backgroundedAt = Date()
    }

    /// AppLockContextImpl: coming back after the auto-lock time locks the app.
    func sceneWillEnterForeground(_ scene: UIWindowScene) {
        defer { backgroundedAt = nil }
        guard isSet, !isLocked, let timeout = autoLockTimeout, let backgroundedAt,
              Date().timeIntervalSince(backgroundedAt) >= TimeInterval(timeout) else { return }
        lock(in: scene)
    }

    /// The chat list's lock: the app locks at once.
    func lockNow() {
        guard isSet, !isLocked,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        lock(in: scene)
    }

    private func lock(in scene: UIWindowScene) {
        guard lockWindow == nil else { return }
        isLocked = true
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = AppAppearance.current.userInterfaceStyle
        window.rootViewController = PasscodeLockViewController { [weak self] in self?.unlock() }
        window.makeKeyAndVisible()
        lockWindow = window
    }

    private func unlock() {
        isLocked = false
        guard let window = lockWindow else { return }
        lockWindow = nil
        UIView.animate(withDuration: 0.3) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
            window.windowScene = nil
        }
    }
}
