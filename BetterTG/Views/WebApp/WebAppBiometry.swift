// WebAppBiometry.swift

import LocalAuthentication
import Security
import UIKit

// MARK: - WebAppBiometry

/// WebAppController's biometry bridge (`web_app_biometry_*`): the device's Face ID or Touch ID, the bot's access asked
/// for
/// once and changeable in its settings, and a token the page can save behind the user's presence. The state belongs
/// to the account and the bot; the token is encrypted with a key that needs the user to decrypt it.
@MainActor final class WebAppBiometry {
    private let bridge: WebAppBridge

    /// requestBiometryAuth's key ID: "A<account>WebBot<bot>".
    private var keyID: Data {
        Data("A\(bridge.accountKey)WebBot\(UInt64(bitPattern: bridge.botUserID))".utf8)
    }

    init(bridge: WebAppBridge) {
        self.bridge = bridge
    }

    /// sendBiometryInfoReceivedEvent: creates the bot's state on first use.
    func sendInfo() {
        let permissions = update { permissions in
            if permissions.biometry == nil { permissions.biometry = .create() }
        }
        guard let state = permissions.biometry else { return }
        var data = [String: Any]()
        if let type = WebAppBiometryKey.biometryType {
            data["available"] = true
            data["type"] = type
            data["access_requested"] = state.accessRequested
            data["access_granted"] = state.accessGranted
            data["token_saved"] = state.opaqueToken != nil
            data["device_id"] = state.deviceID.map { String(format: "%02x", $0) }.joined()
        } else {
            data["available"] = false
        }
        bridge.send("biometry_info_received", data)
    }

    /// requestBiometryAccess: asked once per bot, with the page's reason under the question when it gives one.
    func requestAccess(_ json: [String: Any]?) {
        let reason = (json?["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if load().biometry?.accessRequested == true { return sendInfo() }
        guard let presenter = bridge.topPresenter() else { return }
        let key = WebAppBiometryKey.biometryType == "finger"
            ? "WebApp.AlertBiometryAccessTouchIDText"
            : "WebApp.AlertBiometryAccessText"
        let question = L10n.telegram(key, bridge.botName)
        let alert = UIAlertController(
            title: reason == nil ? nil : question,
            message: reason ?? question,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.No"), style: .default) { [weak self] _ in
            self?.setAccessGranted(false)
        })
        let allow = UIAlertAction(title: L10n.telegram("Common.Yes"), style: .default) { [weak self] _ in
            self?.setAccessGranted(true)
        }
        alert.addAction(allow)
        alert.preferredAction = allow
        presenter.present(alert, animated: true)
    }

    /// requestBiometryAuth: decrypting the saved token, or an empty one when there is none or the key changed, makes
    /// the system ask for Face ID or Touch ID.
    func requestAuth() {
        guard let state = load().biometry else { return }
        guard state.accessRequested, state.accessGranted else { return sendAuthResult(nil) }
        let keyID = keyID
        let token = state.opaqueToken
        let reason = L10n.betterTG("WebApp.BiometryReason", bridge.botName)
        Task { [weak self] in
            let result = await WebAppBiometryKey.authenticate(token: token, keyID: keyID, reason: reason)
            self?.sendAuthResult(result)
        }
    }

    /// requestBiometryUpdateToken: an empty token removes the saved one.
    func updateToken(_ json: [String: Any]?) {
        guard let token = (json?["token"] as? String).flatMap({ $0.isEmpty ? nil : Data($0.utf8) }) else {
            update { permissions in
                var biometry = permissions.biometry ?? .create()
                biometry.opaqueToken = nil
                permissions.biometry = biometry
            }
            bridge.send("biometry_token_updated", ["status": "removed"])
            return
        }
        let keyID = keyID
        Task { [weak self] in
            let encrypted = await WebAppBiometryKey.encrypt(token, keyID: keyID)
            guard let self else { return }
            if let encrypted {
                update { permissions in
                    var biometry = permissions.biometry ?? .create()
                    biometry.opaqueToken = encrypted
                    permissions.biometry = biometry
                }
                bridge.send("biometry_token_updated", ["status": "updated"])
            } else {
                bridge.send("biometry_token_updated", ["status": "failed"])
            }
        }
    }

    /// openBotSettings.
    func openSettings() {
        WebAppBotSettingsViewController.present(.biometry, bridge: bridge)
    }

    // MARK: Private

    private func load() -> WebAppBotPermissions {
        WebAppBotPermissions.load(accountKey: bridge.accountKey, botUserID: bridge.botUserID)
    }

    @discardableResult private func update(_ change: (inout WebAppBotPermissions) -> Void) -> WebAppBotPermissions {
        WebAppBotPermissions.update(accountKey: bridge.accountKey, botUserID: bridge.botUserID, change)
    }

    private func setAccessGranted(_ granted: Bool) {
        update { permissions in
            var biometry = permissions.biometry ?? .create()
            biometry.accessRequested = true
            biometry.accessGranted = granted
            permissions.biometry = biometry
        }
        sendInfo()
    }

    /// sendBiometryAuthResult: the token's text, empty when none was saved, or "failed".
    private func sendAuthResult(_ token: WebAppBiometryKey.AuthResult?) {
        guard case .authorized(let data) = token else {
            bridge.send("biometry_auth_requested", ["status": "failed"])
            return
        }
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        bridge.send("biometry_auth_requested", ["status": "authorized", "token": text])
    }
}

// MARK: - WebAppBiometryKey

/// LocalAuth's PrivateKey: a P-256 key in the Secure Enclave, created for the bot's key ID, that encrypts with
/// ECIES and asks for the user's presence on every decryption. Where there is no Secure Enclave, such as the
/// Simulator, Telegram passes the token through unencrypted; BetterTG keeps a keychain key of the same kind and
/// asks LocalAuthentication before decrypting with it.
private final class WebAppBiometryKey: @unchecked Sendable {
    enum AuthResult {
        /// The decrypted token, nil when the page had saved none.
        case authorized(Data?)
    }

    private static let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA512AESGCM

    /// LocalAuth.biometricAuthentication: "face" for Face ID and Optic ID, "finger" for Touch ID.
    static var biometryType: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID,
             .opticID: return "face"
        case .touchID: return "finger"
        default: return nil
        }
    }

    let publicKeyRepresentation: Data

    private let privateKey: SecKey
    private let publicKey: SecKey
    private let isSecureEnclave: Bool

    private init(privateKey: SecKey, publicKey: SecKey, publicKeyRepresentation: Data, isSecureEnclave: Bool) {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.publicKeyRepresentation = publicKeyRepresentation
        self.isSecureEnclave = isSecureEnclave
    }

    static func authenticate(
        token: WebAppBotPermissions.Biometry.OpaqueToken?,
        keyID: Data,
        reason: String,
    ) async -> AuthResult? {
        guard let key = await background({ getOrCreate(keyID: keyID) }) else { return nil }
        if !key.isSecureEnclave {
            let context = LAContext()
            guard await (try? context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
            else { return nil }
        }
        // The keychain was reset when the token's key is gone: an empty token still asks for the user.
        let encrypted: Data
        if let token, token.publicKey == key.publicKeyRepresentation {
            encrypted = token.data
        } else if let empty = key.encrypt(Data()) {
            encrypted = empty
        } else {
            return nil
        }
        guard let decrypted = await background({ key.decrypt(encrypted) }) else { return nil }
        return .authorized(token == nil ? nil : decrypted)
    }

    static func encrypt(_ token: Data, keyID: Data) async -> WebAppBotPermissions.Biometry.OpaqueToken? {
        await background {
            guard let key = getOrCreate(keyID: keyID), let data = key.encrypt(token) else { return nil }
            return WebAppBotPermissions.Biometry.OpaqueToken(publicKey: key.publicKeyRepresentation, data: data)
        }
    }

    // MARK: Private

    /// Keychain work and decryption block while the system asks for the user.
    private static func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    /// LocalAuth.getOrCreatePrivateKey, tagged "$#_" + key ID; the keychain fallback has its own tag.
    private static func getOrCreate(keyID: Data) -> WebAppBiometryKey? {
        #if !targetEnvironment(simulator)
            let tag = Data("$#_".utf8) + keyID
            if let key = find(tag: tag, isSecureEnclave: true) ?? create(tag: tag, isSecureEnclave: true) {
                return key
            }
        #endif
        let fallbackTag = Data("$#_keychain_".utf8) + keyID
        return find(tag: fallbackTag, isSecureEnclave: false) ?? create(tag: fallbackTag, isSecureEnclave: false)
    }

    private static func find(tag: Data, isSecureEnclave: Bool) -> WebAppBiometryKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item,
              CFGetTypeID(item) == SecKeyGetTypeID()
        else { return nil }
        return make(privateKey: item as! SecKey, isSecureEnclave: isSecureEnclave)
    }

    /// LocalAuth.addPrivateKey: 256-bit, permanent, usable only with the user present while a passcode is set.
    private static func create(tag: Data, isSecureEnclave: Bool) -> WebAppBiometryKey? {
        var privateAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
        ]
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        if isSecureEnclave {
            guard let access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.userPresence, .privateKeyUsage],
                nil,
            ) else { return nil }
            privateAttributes[kSecAttrAccessControl as String] = access
            attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        } else {
            privateAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        attributes[kSecPrivateKeyAttrs as String] = privateAttributes
        var error: Unmanaged<CFError>?
        let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
        _ = error?.takeRetainedValue()
        return privateKey.flatMap { make(privateKey: $0, isSecureEnclave: isSecureEnclave) }
    }

    private static func make(privateKey: SecKey, isSecureEnclave: Bool) -> WebAppBiometryKey? {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let representation = SecKeyCopyExternalRepresentation(publicKey, nil)
        else { return nil }
        return WebAppBiometryKey(
            privateKey: privateKey,
            publicKey: publicKey,
            publicKeyRepresentation: representation as Data,
            isSecureEnclave: isSecureEnclave,
        )
    }

    private func encrypt(_ data: Data) -> Data? {
        var error: Unmanaged<CFError>?
        let result = SecKeyCreateEncryptedData(publicKey, Self.algorithm, data as CFData, &error)
        _ = error?.takeRetainedValue()
        return result as Data?
    }

    /// nil when the user cancelled or the key refused.
    private func decrypt(_ data: Data) -> Data? {
        var error: Unmanaged<CFError>?
        let result = SecKeyCreateDecryptedData(privateKey, Self.algorithm, data as CFData, &error)
        _ = error?.takeRetainedValue()
        return result as Data?
    }
}
