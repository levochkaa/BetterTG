// LoginStageContent.swift

import TDLibKit
import UIKit

/// What the login screen shows for a step, after Telegram's authorization controllers.
struct LoginStageContent {
    enum Action: Equatable {
        case requestQRCode
        case resendCode
        case openURL(URL)
        case forgotPassword
        case resetEmail
        case showTermsOfService
        case usePhoneNumber
    }

    struct Option: Equatable {
        let title: String
        /// Nil shows the title as text that can't be tapped yet, such as a countdown.
        let action: Action?
    }

    /// Marks bold runs (Telegram's `**`) in `text` without touching asterisks in arguments such as email patterns.
    static let boldMarker = "\u{E000}"

    var title: String
    var text: String?
    var placeholder = ""
    var secondaryPlaceholder: String?
    var keyboardType = UIKeyboardType.default
    var contentType: UITextContentType?
    var secondaryContentType: UITextContentType?
    var autocapitalization = UITextAutocapitalizationType.none
    var isSecure = false
    var acceptsInput = true
    var option: Option?
    var secondaryOption: Option?
    var note: String?

    static func make(stage: LoginState?, state: AuthorizationState?, remaining: Int) -> Self {
        switch stage {
        case nil:
            var content = Self(title: L10n.betterTG("Login.WaitingForAuthorization"))
            if case .authorizationStateWaitPremiumPurchase = state {
                content.text = L10n.betterTG("Login.PremiumRequired")
            }
            return content
        case .phoneNumber:
            var content = Self(
                title: L10n.telegram("Login.PhoneTitle"),
                text: L10n.telegram("Login.PhoneAndCountryHelp"),
            )
            content.placeholder = L10n.telegram("Login.PhonePlaceholder")
            content.keyboardType = .numberPad
            content.contentType = .telephoneNumber
            content.option = Option(title: L10n.telegram("AuthSessions.AddDeviceIntro.Title"), action: .requestQRCode)
            return content
        case .code:
            guard case .authorizationStateWaitCode(let value) = state else {
                return Self(title: L10n.telegram("Login.EnterCodeTelegramTitle"))
            }
            return code(value.codeInfo, remaining: remaining)
        case .twoFactor:
            var content = Self(
                title: L10n.telegram("LoginPassword.Title"),
                text: L10n.telegram("TwoStepAuth.EnterPasswordHelp"),
            )
            if case .authorizationStateWaitPassword(let value) = state, !value.passwordHint.isEmpty {
                content.placeholder = value.passwordHint
            } else {
                content.placeholder = L10n.telegram("LoginPassword.PasswordPlaceholder")
            }
            content.isSecure = true
            content.contentType = .password
            content.option = Option(title: L10n.telegram("TwoStepAuth.EnterPasswordForgot"), action: .forgotPassword)
            return content
        case .passwordRecovery:
            var content = Self(
                title: L10n.telegram("TwoStepAuth.RecoveryTitle"),
                text: L10n.telegram("TwoStepAuth.RecoveryCodeHelp"),
            )
            content.placeholder = L10n.telegram("TwoStepAuth.RecoveryCode")
            content.keyboardType = .numberPad
            content.contentType = .oneTimeCode
            return content
        case .newPassword:
            var content = Self(title: L10n.telegram("TwoFactorSetup.Password.Title"))
            content.placeholder = L10n.telegram("TwoFactorSetup.Password.PlaceholderPassword")
            content.secondaryPlaceholder = L10n.telegram("TwoFactorSetup.Hint.Placeholder")
            content.isSecure = true
            content.contentType = .newPassword
            return content
        case .emailAddress:
            var content = Self(
                title: L10n.telegram("LoginEmail.Title"),
                text: L10n.telegram("LoginEmail.Description"),
            )
            content.placeholder = L10n.telegram("Login.AddEmailPlaceholder")
            content.keyboardType = .emailAddress
            content.contentType = .emailAddress
            return content
        case .emailCode:
            guard case .authorizationStateWaitEmailCode(let value) = state else {
                return Self(title: L10n.telegram("Login.EnterCodeEmailTitle"))
            }
            return emailCode(value, remaining: remaining)
        case .registration:
            var content = Self(title: L10n.telegram("Login.InfoTitle"), text: L10n.telegram("Login.InfoHelp"))
            content.placeholder = L10n.telegram("UserInfo.FirstNamePlaceholder")
            content.secondaryPlaceholder = L10n.telegram("UserInfo.LastNamePlaceholder")
            content.contentType = .givenName
            content.secondaryContentType = .familyName
            content.autocapitalization = .words
            if case .authorizationStateWaitRegistration(let value) = state, !value.termsOfService.text.text.isEmpty {
                // "By signing up, you agree to the [Terms of Service]."
                let label = L10n.telegram("Login.TermsOfServiceLabel")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                content.option = Option(title: label, action: .showTermsOfService)
            }
            return content
        case .qrCode:
            // Telegram Desktop's QR login steps; Telegram iOS has no QR login screen of its own.
            var content = Self(
                title: L10n.betterTG("Login.QRCode.Title"),
                text: [
                    L10n.betterTG("Login.QRCode.Step1"),
                    L10n.betterTG("Login.QRCode.Step2"),
                    L10n.betterTG("Login.QRCode.Step3"),
                ]
                    .enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n"),
            )
            content.acceptsInput = false
            content.option = Option(title: L10n.betterTG("Login.QRCode.UsePhone"), action: .usePhoneNumber)
            return content
        }
    }

    /// A Telegram string with its bold runs kept as `boldMarker` pairs.
    static func styled(_ key: String, _ arguments: CVarArg...) -> String {
        let template = L10n.telegram(key).replacingOccurrences(of: "**", with: boldMarker)
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }

    /// `styled` without its bold runs, for alert text.
    static func plain(_ key: String, _ arguments: CVarArg...) -> String {
        let template = L10n.telegram(key).replacingOccurrences(of: "**", with: "")
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }

    static func attributed(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let boldFont = font.fontDescriptor
            .withSymbolicTraits(.traitBold)
            .map { UIFont(descriptor: $0, size: 0) } ?? font
        let result = NSMutableAttributedString()
        for (index, run) in text.components(separatedBy: boldMarker).enumerated() {
            result.append(NSAttributedString(string: run, attributes: [
                .font: index.isMultiple(of: 2) ? font : boldFont,
                .foregroundColor: color,
            ]))
        }
        return result
    }

    /// Telegram's interval words ("in 3 days"), as `unmuteIntervalString` writes them.
    static func intervalText(seconds: Int) -> String {
        if seconds < 60 * 60 {
            return L10n.telegramPlural("MuteExpires.Minutes", count: max(1, seconds / 60))
        } else if seconds < 60 * 60 * 24 {
            return L10n.telegramPlural("MuteExpires.Hours", count: max(1, seconds / (60 * 60)))
        }
        return L10n.telegramPlural("MuteExpires.Days", count: max(1, seconds / (60 * 60 * 24)))
    }

    static func clockText(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// The code screen for the way the code was sent (`authorizationCurrentOptionText`).
    private static func code(_ info: TDNativeAuthenticationCodeInfo, remaining: Int) -> Self {
        let phone = info.phoneNumber.hasPrefix("+") ? info.phoneNumber : "+" + info.phoneNumber
        var content = Self(title: L10n.telegram("Login.EnterCodeTelegramTitle"))
        content.placeholder = L10n.telegram("Login.Code")
        content.keyboardType = .numberPad
        content.contentType = .oneTimeCode
        content.option = resendOption(info, remaining: remaining)
        switch info.type {
        case .authenticationCodeTypeTelegramMessage:
            content.text = styled("Login.EnterCodeTelegramText", phone)
        case .authenticationCodeTypeFirebaseAndroid, .authenticationCodeTypeFirebaseIos, .authenticationCodeTypeSms:
            content.title = L10n.telegram("Login.EnterCodeSMSTitle")
            content.text = styled("Login.EnterCodeSMSText", phone)
        case .authenticationCodeTypeSmsWord(let value):
            content.title = L10n.telegram("Login.EnterWordTitle")
            content.text = value.firstLetter.isEmpty
                ? styled("Login.EnterWordText", phone)
                : styled("Login.EnterWordBeginningText", value.firstLetter, phone)
            content.placeholder = L10n.telegram("Login.EnterWordPlaceholder")
            content.keyboardType = .default
            content.contentType = nil
        case .authenticationCodeTypeSmsPhrase(let value):
            content.title = L10n.telegram("Login.EnterPhraseTitle")
            content.text = value.firstWord.isEmpty
                ? styled("Login.EnterPhraseText", phone)
                : styled("Login.EnterPhraseBeginningText", value.firstWord, phone)
            content.placeholder = L10n.telegram("Login.EnterPhrasePlaceholder")
            content.keyboardType = .default
            content.contentType = nil
        case .authenticationCodeTypeCall, .authenticationCodeTypeFlashCall:
            content.text = styled("Login.CodeSentCallText", phone)
        case .authenticationCodeTypeMissedCall(let value):
            content.title = L10n.telegram("Login.EnterMissingDigits")
            content.text = [
                L10n.telegram("Login.ShortCallTitle").replacingOccurrences(of: "\n", with: " "),
                boldMarker + value.phoneNumberPrefix + boldMarker,
                L10n.telegram("Login.CodePhonePatternInfoText").replacingOccurrences(of: "\n", with: " "),
            ].joined(separator: "\n")
        case .authenticationCodeTypeFragment(let value):
            content.title = L10n.telegram("Login.EnterCodeFragmentTitle")
            content.text = styled("Login.EnterCodeFragmentText", phone)
            if let url = URL(string: value.url) {
                content.secondaryOption = Option(title: L10n.telegram("Login.OpenFragment"), action: .openURL(url))
            }
        }
        return content
    }

    /// Telegram's next-code line: a countdown until TDLib allows a resend, then the way the next code comes
    /// (`authorizationNextOptionText`). Nil when TDLib has no next code type.
    private static func resendOption(_ info: TDNativeAuthenticationCodeInfo, remaining: Int) -> Option? {
        guard let next = info.nextType else { return nil }
        let (isCall, key) =
            switch next {
            case .authenticationCodeTypeFirebaseAndroid, .authenticationCodeTypeFirebaseIos, .authenticationCodeTypeSms,
                 .authenticationCodeTypeSmsPhrase, .authenticationCodeTypeSmsWord:
                (false, "Login.SendCodeViaSms")
            case .authenticationCodeTypeCall:
                (true, "Login.SendCodeViaCall")
            case .authenticationCodeTypeFlashCall, .authenticationCodeTypeMissedCall:
                (true, "Login.SendCodeViaFlashCall")
            case .authenticationCodeTypeFragment:
                (false, "Login.GetCodeViaFragment")
            case .authenticationCodeTypeTelegramMessage:
                (false, "Login.HaveNotReceivedCodeInternal")
            }
        guard remaining > 0 else { return Option(title: L10n.telegram(key), action: .resendCode) }
        let time = clockText(seconds: remaining)
        return Option(
            title: isCall
                ? L10n.telegram("ChangePhoneNumberCode.CallTimer", time)
                : L10n.telegram("Login.WillSendSms", time),
            action: nil,
        )
    }

    /// The email code screen with Telegram's reset option (`AuthorizationSequenceCodeEntryControllerNode`).
    private static func emailCode(_ state: TDNativeAuthorizationStateWaitEmailCode, remaining: Int) -> Self {
        // The pattern's asterisks stay plain: the text has no bold runs.
        var content = Self(
            title: L10n.telegram("Login.EnterCodeEmailTitle"),
            text: L10n.telegram("Login.EnterCodeEmailText", state.codeInfo.emailAddressPattern),
        )
        content.placeholder = L10n.telegram("Login.Code")
        content.keyboardType = .numberPad
        content.contentType = .oneTimeCode
        switch state.emailAddressResetState {
        case .emailAddressResetStateAvailable:
            content.option = Option(title: L10n.telegram("Login.Email.CantAccess"), action: .resetEmail)
        case .emailAddressResetStatePending:
            let resetText =
                if remaining <= 0 {
                    L10n.telegram("Login.Email.ResetingNow")
                } else if remaining < 60 * 60 * 24 {
                    L10n.telegram("Login.Email.ElapsedTime", clockText(seconds: remaining))
                } else {
                    intervalText(seconds: remaining)
                }
            content.note = L10n.telegram("Login.Email.WillBeResetIn", resetText)
            content.option = Option(title: L10n.telegram("Login.Email.ResetNowViaSMS"), action: .resetEmail)
        case nil:
            break
        }
        return content
    }
}
