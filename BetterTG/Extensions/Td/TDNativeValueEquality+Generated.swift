// TDNativeValueEquality+Generated.swift

import Foundation
import TDLibKit

// MARK: - TDNativeAccountInfo + @retroactive Hashable

extension TDNativeAccountInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.registrationMonth == rhs.registrationMonth else { return false }
        guard lhs.registrationYear == rhs.registrationYear else { return false }
        guard lhs.phoneNumberCountryCode == rhs.phoneNumberCountryCode else { return false }
        guard lhs.lastNameChangeDate == rhs.lastNameChangeDate else { return false }
        guard lhs.lastPhotoChangeDate == rhs.lastPhotoChangeDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(registrationMonth)
        hasher.combine(registrationYear)
        hasher.combine(phoneNumberCountryCode)
        hasher.combine(lastNameChangeDate)
        hasher.combine(lastPhotoChangeDate)
    }
}

// MARK: - TDNativeActiveStoryState + @retroactive Hashable

extension TDNativeActiveStoryState: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.activeStoryStateLive(let lhs), .activeStoryStateLive(let rhs)):
            lhs == rhs
        case (.activeStoryStateUnread, .activeStoryStateUnread):
            true
        case (.activeStoryStateRead, .activeStoryStateRead):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .activeStoryStateLive(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .activeStoryStateUnread:
            hasher.combine(1)
        case .activeStoryStateRead:
            hasher.combine(2)
        }
    }
}

// MARK: - TDNativeActiveStoryStateLive + @retroactive Hashable

extension TDNativeActiveStoryStateLive: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyId == rhs.storyId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyId)
    }
}

// MARK: - TDNativeAddress + @retroactive Hashable

extension TDNativeAddress: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.countryCode == rhs.countryCode else { return false }
        guard lhs.state == rhs.state else { return false }
        guard lhs.city == rhs.city else { return false }
        guard lhs.streetLine1 == rhs.streetLine1 else { return false }
        guard lhs.streetLine2 == rhs.streetLine2 else { return false }
        guard lhs.postalCode == rhs.postalCode else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(countryCode)
        hasher.combine(state)
        hasher.combine(city)
        hasher.combine(streetLine1)
        hasher.combine(streetLine2)
        hasher.combine(postalCode)
    }
}

// MARK: - TDNativeAnimatedEmoji + @retroactive Hashable

extension TDNativeAnimatedEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sticker == rhs.sticker else { return false }
        guard lhs.stickerWidth == rhs.stickerWidth else { return false }
        guard lhs.stickerHeight == rhs.stickerHeight else { return false }
        guard lhs.fitzpatrickType == rhs.fitzpatrickType else { return false }
        guard lhs.sound == rhs.sound else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
        hasher.combine(stickerWidth)
        hasher.combine(stickerHeight)
        hasher.combine(fitzpatrickType)
        hasher.combine(sound)
    }
}

// MARK: - TDNativeAudio + @retroactive Hashable

extension TDNativeAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.performer == rhs.performer else { return false }
        guard lhs.fileName == rhs.fileName else { return false }
        guard lhs.mimeType == rhs.mimeType else { return false }
        guard lhs.albumCoverMinithumbnail == rhs.albumCoverMinithumbnail else { return false }
        guard lhs.albumCoverThumbnail == rhs.albumCoverThumbnail else { return false }
        guard lhs.externalAlbumCovers == rhs.externalAlbumCovers else { return false }
        guard lhs.audio == rhs.audio else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(duration)
        hasher.combine(title)
        hasher.combine(performer)
        hasher.combine(fileName)
        hasher.combine(mimeType)
        hasher.combine(albumCoverMinithumbnail)
        hasher.combine(albumCoverThumbnail)
        hasher.combine(externalAlbumCovers)
        hasher.combine(audio)
    }
}

// MARK: - TDNativeAuthenticationCodeInfo + @retroactive Hashable

extension TDNativeAuthenticationCodeInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.phoneNumber == rhs.phoneNumber else { return false }
        guard lhs.type == rhs.type else { return false }
        guard lhs.nextType == rhs.nextType else { return false }
        guard lhs.timeout == rhs.timeout else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(phoneNumber)
        hasher.combine(type)
        hasher.combine(nextType)
        hasher.combine(timeout)
    }
}

// MARK: - TDNativeAuthenticationCodeType + @retroactive Hashable

extension TDNativeAuthenticationCodeType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.authenticationCodeTypeTelegramMessage(let lhs), .authenticationCodeTypeTelegramMessage(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeSms(let lhs), .authenticationCodeTypeSms(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeSmsWord(let lhs), .authenticationCodeTypeSmsWord(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeSmsPhrase(let lhs), .authenticationCodeTypeSmsPhrase(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeCall(let lhs), .authenticationCodeTypeCall(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeFlashCall(let lhs), .authenticationCodeTypeFlashCall(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeMissedCall(let lhs), .authenticationCodeTypeMissedCall(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeFragment(let lhs), .authenticationCodeTypeFragment(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeFirebaseAndroid(let lhs), .authenticationCodeTypeFirebaseAndroid(let rhs)):
            lhs == rhs
        case (.authenticationCodeTypeFirebaseIos(let lhs), .authenticationCodeTypeFirebaseIos(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .authenticationCodeTypeTelegramMessage(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .authenticationCodeTypeSms(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .authenticationCodeTypeSmsWord(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .authenticationCodeTypeSmsPhrase(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .authenticationCodeTypeCall(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .authenticationCodeTypeFlashCall(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .authenticationCodeTypeMissedCall(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .authenticationCodeTypeFragment(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .authenticationCodeTypeFirebaseAndroid(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .authenticationCodeTypeFirebaseIos(let value):
            hasher.combine(9)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeAuthenticationCodeTypeCall + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeCall: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(length)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeFirebaseAndroid + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeFirebaseAndroid: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.deviceVerificationParameters == rhs.deviceVerificationParameters else { return false }
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(deviceVerificationParameters)
        hasher.combine(length)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeFirebaseIos + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeFirebaseIos: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.receipt == rhs.receipt else { return false }
        guard lhs.pushTimeout == rhs.pushTimeout else { return false }
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(receipt)
        hasher.combine(pushTimeout)
        hasher.combine(length)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeFlashCall + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeFlashCall: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.pattern == rhs.pattern else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pattern)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeFragment + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeFragment: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(length)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeMissedCall + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeMissedCall: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.phoneNumberPrefix == rhs.phoneNumberPrefix else { return false }
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(phoneNumberPrefix)
        hasher.combine(length)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeSms + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeSms: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(length)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeSmsPhrase + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeSmsPhrase: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.firstWord == rhs.firstWord else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(firstWord)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeSmsWord + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeSmsWord: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.firstLetter == rhs.firstLetter else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(firstLetter)
    }
}

// MARK: - TDNativeAuthenticationCodeTypeTelegramMessage + @retroactive Hashable

extension TDNativeAuthenticationCodeTypeTelegramMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(length)
    }
}

// MARK: - TDNativeAuthorizationState + @retroactive Hashable

extension TDNativeAuthorizationState: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.authorizationStateWaitTdlibParameters, .authorizationStateWaitTdlibParameters):
            true
        case (.authorizationStateWaitPhoneNumber, .authorizationStateWaitPhoneNumber):
            true
        case (.authorizationStateWaitPremiumPurchase(let lhs), .authorizationStateWaitPremiumPurchase(let rhs)):
            lhs == rhs
        case (.authorizationStateWaitEmailAddress(let lhs), .authorizationStateWaitEmailAddress(let rhs)):
            lhs == rhs
        case (.authorizationStateWaitEmailCode(let lhs), .authorizationStateWaitEmailCode(let rhs)):
            lhs == rhs
        case (.authorizationStateWaitCode(let lhs), .authorizationStateWaitCode(let rhs)):
            lhs == rhs
        case (
            .authorizationStateWaitOtherDeviceConfirmation(let lhs),
            .authorizationStateWaitOtherDeviceConfirmation(let rhs),
        ):
            lhs == rhs
        case (.authorizationStateWaitRegistration(let lhs), .authorizationStateWaitRegistration(let rhs)):
            lhs == rhs
        case (.authorizationStateWaitPassword(let lhs), .authorizationStateWaitPassword(let rhs)):
            lhs == rhs
        case (.authorizationStateReady, .authorizationStateReady):
            true
        case (.authorizationStateLoggingOut, .authorizationStateLoggingOut):
            true
        case (.authorizationStateClosing, .authorizationStateClosing):
            true
        case (.authorizationStateClosed, .authorizationStateClosed):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .authorizationStateWaitTdlibParameters:
            hasher.combine(0)
        case .authorizationStateWaitPhoneNumber:
            hasher.combine(1)
        case .authorizationStateWaitPremiumPurchase(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .authorizationStateWaitEmailAddress(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .authorizationStateWaitEmailCode(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .authorizationStateWaitCode(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .authorizationStateWaitOtherDeviceConfirmation(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .authorizationStateWaitRegistration(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .authorizationStateWaitPassword(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .authorizationStateReady:
            hasher.combine(9)
        case .authorizationStateLoggingOut:
            hasher.combine(10)
        case .authorizationStateClosing:
            hasher.combine(11)
        case .authorizationStateClosed:
            hasher.combine(12)
        }
    }
}

// MARK: - TDNativeAuthorizationStateWaitCode + @retroactive Hashable

extension TDNativeAuthorizationStateWaitCode: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.codeInfo == rhs.codeInfo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(codeInfo)
    }
}

// MARK: - TDNativeAuthorizationStateWaitEmailAddress + @retroactive Hashable

extension TDNativeAuthorizationStateWaitEmailAddress: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.allowAppleId == rhs.allowAppleId else { return false }
        guard lhs.allowGoogleId == rhs.allowGoogleId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(allowAppleId)
        hasher.combine(allowGoogleId)
    }
}

// MARK: - TDNativeAuthorizationStateWaitEmailCode + @retroactive Hashable

extension TDNativeAuthorizationStateWaitEmailCode: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.allowAppleId == rhs.allowAppleId else { return false }
        guard lhs.allowGoogleId == rhs.allowGoogleId else { return false }
        guard lhs.codeInfo == rhs.codeInfo else { return false }
        guard lhs.emailAddressResetState == rhs.emailAddressResetState else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(allowAppleId)
        hasher.combine(allowGoogleId)
        hasher.combine(codeInfo)
        hasher.combine(emailAddressResetState)
    }
}

// MARK: - TDNativeAuthorizationStateWaitOtherDeviceConfirmation + @retroactive Hashable

extension TDNativeAuthorizationStateWaitOtherDeviceConfirmation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.link == rhs.link else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(link)
    }
}

// MARK: - TDNativeAuthorizationStateWaitPassword + @retroactive Hashable

extension TDNativeAuthorizationStateWaitPassword: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.passwordHint == rhs.passwordHint else { return false }
        guard lhs.hasRecoveryEmailAddress == rhs.hasRecoveryEmailAddress else { return false }
        guard lhs.hasPassportData == rhs.hasPassportData else { return false }
        guard lhs.recoveryEmailAddressPattern == rhs.recoveryEmailAddressPattern else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(passwordHint)
        hasher.combine(hasRecoveryEmailAddress)
        hasher.combine(hasPassportData)
        hasher.combine(recoveryEmailAddressPattern)
    }
}

// MARK: - TDNativeAuthorizationStateWaitPremiumPurchase + @retroactive Hashable

extension TDNativeAuthorizationStateWaitPremiumPurchase: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storeProductId == rhs.storeProductId else { return false }
        guard lhs.premiumDayCount == rhs.premiumDayCount else { return false }
        guard lhs.supportEmailAddress == rhs.supportEmailAddress else { return false }
        guard lhs.supportEmailSubject == rhs.supportEmailSubject else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storeProductId)
        hasher.combine(premiumDayCount)
        hasher.combine(supportEmailAddress)
        hasher.combine(supportEmailSubject)
    }
}

// MARK: - TDNativeAuthorizationStateWaitRegistration + @retroactive Hashable

extension TDNativeAuthorizationStateWaitRegistration: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.termsOfService == rhs.termsOfService else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(termsOfService)
    }
}

// MARK: - TDNativeBackground + @retroactive Hashable

extension TDNativeBackground: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.isDefault == rhs.isDefault else { return false }
        guard lhs.isDark == rhs.isDark else { return false }
        guard lhs.name == rhs.name else { return false }
        guard lhs.document == rhs.document else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isDefault)
        hasher.combine(isDark)
        hasher.combine(name)
        hasher.combine(document)
        hasher.combine(type)
    }
}

// MARK: - TDNativeBackgroundFill + @retroactive Hashable

extension TDNativeBackgroundFill: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.backgroundFillSolid(let lhs), .backgroundFillSolid(let rhs)):
            lhs == rhs
        case (.backgroundFillGradient(let lhs), .backgroundFillGradient(let rhs)):
            lhs == rhs
        case (.backgroundFillFreeformGradient(let lhs), .backgroundFillFreeformGradient(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .backgroundFillSolid(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .backgroundFillGradient(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .backgroundFillFreeformGradient(let value):
            hasher.combine(2)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeBackgroundFillFreeformGradient + @retroactive Hashable

extension TDNativeBackgroundFillFreeformGradient: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.colors == rhs.colors else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(colors)
    }
}

// MARK: - TDNativeBackgroundFillGradient + @retroactive Hashable

extension TDNativeBackgroundFillGradient: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.topColor == rhs.topColor else { return false }
        guard lhs.bottomColor == rhs.bottomColor else { return false }
        guard lhs.rotationAngle == rhs.rotationAngle else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(topColor)
        hasher.combine(bottomColor)
        hasher.combine(rotationAngle)
    }
}

// MARK: - TDNativeBackgroundFillSolid + @retroactive Hashable

extension TDNativeBackgroundFillSolid: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.color == rhs.color else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(color)
    }
}

// MARK: - TDNativeBackgroundType + @retroactive Hashable

extension TDNativeBackgroundType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.backgroundTypeWallpaper(let lhs), .backgroundTypeWallpaper(let rhs)):
            lhs == rhs
        case (.backgroundTypePattern(let lhs), .backgroundTypePattern(let rhs)):
            lhs == rhs
        case (.backgroundTypeFill(let lhs), .backgroundTypeFill(let rhs)):
            lhs == rhs
        case (.backgroundTypeChatTheme(let lhs), .backgroundTypeChatTheme(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .backgroundTypeWallpaper(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .backgroundTypePattern(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .backgroundTypeFill(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .backgroundTypeChatTheme(let value):
            hasher.combine(3)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeBackgroundTypeChatTheme + @retroactive Hashable

extension TDNativeBackgroundTypeChatTheme: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.themeName == rhs.themeName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(themeName)
    }
}

// MARK: - TDNativeBackgroundTypeFill + @retroactive Hashable

extension TDNativeBackgroundTypeFill: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.fill == rhs.fill else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fill)
    }
}

// MARK: - TDNativeBackgroundTypePattern + @retroactive Hashable

extension TDNativeBackgroundTypePattern: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.fill == rhs.fill else { return false }
        guard lhs.intensity == rhs.intensity else { return false }
        guard lhs.isInverted == rhs.isInverted else { return false }
        guard lhs.isMoving == rhs.isMoving else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fill)
        hasher.combine(intensity)
        hasher.combine(isInverted)
        hasher.combine(isMoving)
    }
}

// MARK: - TDNativeBackgroundTypeWallpaper + @retroactive Hashable

extension TDNativeBackgroundTypeWallpaper: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isBlurred == rhs.isBlurred else { return false }
        guard lhs.isMoving == rhs.isMoving else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isBlurred)
        hasher.combine(isMoving)
    }
}

// MARK: - TDNativeBasicGroup + @retroactive Hashable

extension TDNativeBasicGroup: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.memberCount == rhs.memberCount else { return false }
        guard lhs.status == rhs.status else { return false }
        guard lhs.isActive == rhs.isActive else { return false }
        guard lhs.upgradedToSupergroupId == rhs.upgradedToSupergroupId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(memberCount)
        hasher.combine(status)
        hasher.combine(isActive)
        hasher.combine(upgradedToSupergroupId)
    }
}

// MARK: - TDNativeBirthdate + @retroactive Hashable

extension TDNativeBirthdate: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.day == rhs.day else { return false }
        guard lhs.month == rhs.month else { return false }
        guard lhs.year == rhs.year else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(day)
        hasher.combine(month)
        hasher.combine(year)
    }
}

// MARK: - TDNativeBotWriteAccessAllowReason + @retroactive Hashable

extension TDNativeBotWriteAccessAllowReason: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.botWriteAccessAllowReasonConnectedWebsite(let lhs), .botWriteAccessAllowReasonConnectedWebsite(let rhs)):
            lhs == rhs
        case (.botWriteAccessAllowReasonAddedToAttachmentMenu, .botWriteAccessAllowReasonAddedToAttachmentMenu):
            true
        case (.botWriteAccessAllowReasonLaunchedWebApp(let lhs), .botWriteAccessAllowReasonLaunchedWebApp(let rhs)):
            lhs == rhs
        case (.botWriteAccessAllowReasonAcceptedRequest, .botWriteAccessAllowReasonAcceptedRequest):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .botWriteAccessAllowReasonConnectedWebsite(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .botWriteAccessAllowReasonAddedToAttachmentMenu:
            hasher.combine(1)
        case .botWriteAccessAllowReasonLaunchedWebApp(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .botWriteAccessAllowReasonAcceptedRequest:
            hasher.combine(3)
        }
    }
}

// MARK: - TDNativeBotWriteAccessAllowReasonConnectedWebsite + @retroactive Hashable

extension TDNativeBotWriteAccessAllowReasonConnectedWebsite: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.domainName == rhs.domainName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(domainName)
    }
}

// MARK: - TDNativeBotWriteAccessAllowReasonLaunchedWebApp + @retroactive Hashable

extension TDNativeBotWriteAccessAllowReasonLaunchedWebApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.webApp == rhs.webApp else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(webApp)
    }
}

// MARK: - TDNativeBusinessBotManageBar + @retroactive Hashable

extension TDNativeBusinessBotManageBar: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUserId == rhs.botUserId else { return false }
        guard lhs.manageUrl == rhs.manageUrl else { return false }
        guard lhs.isBotPaused == rhs.isBotPaused else { return false }
        guard lhs.canBotReply == rhs.canBotReply else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUserId)
        hasher.combine(manageUrl)
        hasher.combine(isBotPaused)
        hasher.combine(canBotReply)
    }
}

// MARK: - TDNativeCallDiscardReason + @retroactive Hashable

extension TDNativeCallDiscardReason: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.callDiscardReasonEmpty, .callDiscardReasonEmpty):
            true
        case (.callDiscardReasonMissed, .callDiscardReasonMissed):
            true
        case (.callDiscardReasonDeclined, .callDiscardReasonDeclined):
            true
        case (.callDiscardReasonDisconnected, .callDiscardReasonDisconnected):
            true
        case (.callDiscardReasonHungUp, .callDiscardReasonHungUp):
            true
        case (.callDiscardReasonUpgradeToGroupCall(let lhs), .callDiscardReasonUpgradeToGroupCall(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .callDiscardReasonEmpty:
            hasher.combine(0)
        case .callDiscardReasonMissed:
            hasher.combine(1)
        case .callDiscardReasonDeclined:
            hasher.combine(2)
        case .callDiscardReasonDisconnected:
            hasher.combine(3)
        case .callDiscardReasonHungUp:
            hasher.combine(4)
        case .callDiscardReasonUpgradeToGroupCall(let value):
            hasher.combine(5)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeCallDiscardReasonUpgradeToGroupCall + @retroactive Hashable

extension TDNativeCallDiscardReasonUpgradeToGroupCall: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.inviteLink == rhs.inviteLink else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(inviteLink)
    }
}

// MARK: - TDNativeChat + @retroactive Hashable

extension TDNativeChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.type == rhs.type else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.accentColorId == rhs.accentColorId else { return false }
        guard lhs.backgroundCustomEmojiId == rhs.backgroundCustomEmojiId else { return false }
        guard lhs.upgradedGiftColors == rhs.upgradedGiftColors else { return false }
        guard lhs.profileAccentColorId == rhs.profileAccentColorId else { return false }
        guard lhs.profileBackgroundCustomEmojiId == rhs.profileBackgroundCustomEmojiId else { return false }
        guard lhs.permissions == rhs.permissions else { return false }
        guard lhs.lastMessage == rhs.lastMessage else { return false }
        guard lhs.positions == rhs.positions else { return false }
        guard lhs.chatLists == rhs.chatLists else { return false }
        guard lhs.messageSenderId == rhs.messageSenderId else { return false }
        guard lhs.blockList == rhs.blockList else { return false }
        guard lhs.hasProtectedContent == rhs.hasProtectedContent else { return false }
        guard lhs.isTranslatable == rhs.isTranslatable else { return false }
        guard lhs.isMarkedAsUnread == rhs.isMarkedAsUnread else { return false }
        guard lhs.viewAsTopics == rhs.viewAsTopics else { return false }
        guard lhs.hasScheduledMessages == rhs.hasScheduledMessages else { return false }
        guard lhs.hasWelcomeMessages == rhs.hasWelcomeMessages else { return false }
        guard lhs.canBeDeletedOnlyForSelf == rhs.canBeDeletedOnlyForSelf else { return false }
        guard lhs.canBeDeletedForAllUsers == rhs.canBeDeletedForAllUsers else { return false }
        guard lhs.canBeReported == rhs.canBeReported else { return false }
        guard lhs.defaultDisableNotification == rhs.defaultDisableNotification else { return false }
        guard lhs.unreadCount == rhs.unreadCount else { return false }
        guard lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId else { return false }
        guard lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId else { return false }
        guard lhs.unreadMentionCount == rhs.unreadMentionCount else { return false }
        guard lhs.unreadReactionCount == rhs.unreadReactionCount else { return false }
        guard lhs.unreadPollVoteCount == rhs.unreadPollVoteCount else { return false }
        guard lhs.notificationSettings == rhs.notificationSettings else { return false }
        guard lhs.availableReactions == rhs.availableReactions else { return false }
        guard lhs.messageAutoDeleteTime == rhs.messageAutoDeleteTime else { return false }
        guard lhs.emojiStatus == rhs.emojiStatus else { return false }
        guard lhs.background == rhs.background else { return false }
        guard lhs.theme == rhs.theme else { return false }
        guard lhs.actionBar == rhs.actionBar else { return false }
        guard lhs.businessBotManageBar == rhs.businessBotManageBar else { return false }
        guard lhs.videoChat == rhs.videoChat else { return false }
        guard lhs.pendingJoinRequests == rhs.pendingJoinRequests else { return false }
        guard lhs.replyMarkupMessageId == rhs.replyMarkupMessageId else { return false }
        guard lhs.draftMessage == rhs.draftMessage else { return false }
        guard lhs.clientData == rhs.clientData else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
        hasher.combine(title)
        hasher.combine(photo)
        hasher.combine(accentColorId)
        hasher.combine(backgroundCustomEmojiId)
        hasher.combine(upgradedGiftColors)
        hasher.combine(profileAccentColorId)
        hasher.combine(profileBackgroundCustomEmojiId)
        hasher.combine(permissions)
        hasher.combine(lastMessage)
        hasher.combine(positions)
        hasher.combine(chatLists)
        hasher.combine(messageSenderId)
        hasher.combine(blockList)
        hasher.combine(hasProtectedContent)
        hasher.combine(isTranslatable)
        hasher.combine(isMarkedAsUnread)
        hasher.combine(viewAsTopics)
        hasher.combine(hasScheduledMessages)
        hasher.combine(hasWelcomeMessages)
        hasher.combine(canBeDeletedOnlyForSelf)
        hasher.combine(canBeDeletedForAllUsers)
        hasher.combine(canBeReported)
        hasher.combine(defaultDisableNotification)
        hasher.combine(unreadCount)
        hasher.combine(lastReadInboxMessageId)
        hasher.combine(lastReadOutboxMessageId)
        hasher.combine(unreadMentionCount)
        hasher.combine(unreadReactionCount)
        hasher.combine(unreadPollVoteCount)
        hasher.combine(notificationSettings)
        hasher.combine(availableReactions)
        hasher.combine(messageAutoDeleteTime)
        hasher.combine(emojiStatus)
        hasher.combine(background)
        hasher.combine(theme)
        hasher.combine(actionBar)
        hasher.combine(businessBotManageBar)
        hasher.combine(videoChat)
        hasher.combine(pendingJoinRequests)
        hasher.combine(replyMarkupMessageId)
        hasher.combine(draftMessage)
        hasher.combine(clientData)
    }
}

// MARK: - TDNativeChatActionBar + @retroactive Hashable

extension TDNativeChatActionBar: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatActionBarReportSpam(let lhs), .chatActionBarReportSpam(let rhs)):
            lhs == rhs
        case (.chatActionBarInviteMembers, .chatActionBarInviteMembers):
            true
        case (.chatActionBarReportAddBlock(let lhs), .chatActionBarReportAddBlock(let rhs)):
            lhs == rhs
        case (.chatActionBarAddContact, .chatActionBarAddContact):
            true
        case (.chatActionBarSharePhoneNumber, .chatActionBarSharePhoneNumber):
            true
        case (.chatActionBarJoinRequest(let lhs), .chatActionBarJoinRequest(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatActionBarReportSpam(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .chatActionBarInviteMembers:
            hasher.combine(1)
        case .chatActionBarReportAddBlock(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .chatActionBarAddContact:
            hasher.combine(3)
        case .chatActionBarSharePhoneNumber:
            hasher.combine(4)
        case .chatActionBarJoinRequest(let value):
            hasher.combine(5)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeChatActionBarJoinRequest + @retroactive Hashable

extension TDNativeChatActionBarJoinRequest: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        guard lhs.isChannel == rhs.isChannel else { return false }
        guard lhs.requestDate == rhs.requestDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(isChannel)
        hasher.combine(requestDate)
    }
}

// MARK: - TDNativeChatActionBarReportAddBlock + @retroactive Hashable

extension TDNativeChatActionBarReportAddBlock: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canUnarchive == rhs.canUnarchive else { return false }
        guard lhs.accountInfo == rhs.accountInfo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canUnarchive)
        hasher.combine(accountInfo)
    }
}

// MARK: - TDNativeChatActionBarReportSpam + @retroactive Hashable

extension TDNativeChatActionBarReportSpam: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canUnarchive == rhs.canUnarchive else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canUnarchive)
    }
}

// MARK: - TDNativeChatAdministratorRights + @retroactive Hashable

extension TDNativeChatAdministratorRights: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canManageChat == rhs.canManageChat else { return false }
        guard lhs.canChangeInfo == rhs.canChangeInfo else { return false }
        guard lhs.canPostMessages == rhs.canPostMessages else { return false }
        guard lhs.canEditMessages == rhs.canEditMessages else { return false }
        guard lhs.canDeleteMessages == rhs.canDeleteMessages else { return false }
        guard lhs.canInviteUsers == rhs.canInviteUsers else { return false }
        guard lhs.canRestrictMembers == rhs.canRestrictMembers else { return false }
        guard lhs.canPinMessages == rhs.canPinMessages else { return false }
        guard lhs.canManageTopics == rhs.canManageTopics else { return false }
        guard lhs.canPromoteMembers == rhs.canPromoteMembers else { return false }
        guard lhs.canManageVideoChats == rhs.canManageVideoChats else { return false }
        guard lhs.canPostStories == rhs.canPostStories else { return false }
        guard lhs.canEditStories == rhs.canEditStories else { return false }
        guard lhs.canDeleteStories == rhs.canDeleteStories else { return false }
        guard lhs.canManageDirectMessages == rhs.canManageDirectMessages else { return false }
        guard lhs.canManageTags == rhs.canManageTags else { return false }
        guard lhs.canSendWelcomeMessages == rhs.canSendWelcomeMessages else { return false }
        guard lhs.isAnonymous == rhs.isAnonymous else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canManageChat)
        hasher.combine(canChangeInfo)
        hasher.combine(canPostMessages)
        hasher.combine(canEditMessages)
        hasher.combine(canDeleteMessages)
        hasher.combine(canInviteUsers)
        hasher.combine(canRestrictMembers)
        hasher.combine(canPinMessages)
        hasher.combine(canManageTopics)
        hasher.combine(canPromoteMembers)
        hasher.combine(canManageVideoChats)
        hasher.combine(canPostStories)
        hasher.combine(canEditStories)
        hasher.combine(canDeleteStories)
        hasher.combine(canManageDirectMessages)
        hasher.combine(canManageTags)
        hasher.combine(canSendWelcomeMessages)
        hasher.combine(isAnonymous)
    }
}

// MARK: - TDNativeChatAvailableReactions + @retroactive Hashable

extension TDNativeChatAvailableReactions: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatAvailableReactionsAll(let lhs), .chatAvailableReactionsAll(let rhs)):
            lhs == rhs
        case (.chatAvailableReactionsSome(let lhs), .chatAvailableReactionsSome(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatAvailableReactionsAll(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .chatAvailableReactionsSome(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeChatAvailableReactionsAll + @retroactive Hashable

extension TDNativeChatAvailableReactionsAll: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.maxReactionCount == rhs.maxReactionCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(maxReactionCount)
    }
}

// MARK: - TDNativeChatAvailableReactionsSome + @retroactive Hashable

extension TDNativeChatAvailableReactionsSome: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.reactions == rhs.reactions else { return false }
        guard lhs.maxReactionCount == rhs.maxReactionCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reactions)
        hasher.combine(maxReactionCount)
    }
}

// MARK: - TDNativeChatBackground + @retroactive Hashable

extension TDNativeChatBackground: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.background == rhs.background else { return false }
        guard lhs.darkThemeDimming == rhs.darkThemeDimming else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(background)
        hasher.combine(darkThemeDimming)
    }
}

// MARK: - TDNativeChatJoinRequestsInfo + @retroactive Hashable

extension TDNativeChatJoinRequestsInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.totalCount == rhs.totalCount else { return false }
        guard lhs.userIds == rhs.userIds else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(totalCount)
        hasher.combine(userIds)
    }
}

// MARK: - TDNativeChatMember + @retroactive Hashable

extension TDNativeChatMember: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.memberId == rhs.memberId else { return false }
        guard lhs.tag == rhs.tag else { return false }
        guard lhs.inviterUserId == rhs.inviterUserId else { return false }
        guard lhs.joinedChatDate == rhs.joinedChatDate else { return false }
        guard lhs.status == rhs.status else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(memberId)
        hasher.combine(tag)
        hasher.combine(inviterUserId)
        hasher.combine(joinedChatDate)
        hasher.combine(status)
    }
}

// MARK: - TDNativeChatMemberStatus + @retroactive Hashable

extension TDNativeChatMemberStatus: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatMemberStatusCreator(let lhs), .chatMemberStatusCreator(let rhs)):
            lhs == rhs
        case (.chatMemberStatusAdministrator(let lhs), .chatMemberStatusAdministrator(let rhs)):
            lhs == rhs
        case (.chatMemberStatusMember(let lhs), .chatMemberStatusMember(let rhs)):
            lhs == rhs
        case (.chatMemberStatusRestricted(let lhs), .chatMemberStatusRestricted(let rhs)):
            lhs == rhs
        case (.chatMemberStatusLeft, .chatMemberStatusLeft):
            true
        case (.chatMemberStatusBanned(let lhs), .chatMemberStatusBanned(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatMemberStatusCreator(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .chatMemberStatusAdministrator(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .chatMemberStatusMember(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .chatMemberStatusRestricted(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .chatMemberStatusLeft:
            hasher.combine(4)
        case .chatMemberStatusBanned(let value):
            hasher.combine(5)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeChatMemberStatusAdministrator + @retroactive Hashable

extension TDNativeChatMemberStatusAdministrator: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canBeEdited == rhs.canBeEdited else { return false }
        guard lhs.rights == rhs.rights else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canBeEdited)
        hasher.combine(rights)
    }
}

// MARK: - TDNativeChatMemberStatusBanned + @retroactive Hashable

extension TDNativeChatMemberStatusBanned: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.bannedUntilDate == rhs.bannedUntilDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bannedUntilDate)
    }
}

// MARK: - TDNativeChatMemberStatusCreator + @retroactive Hashable

extension TDNativeChatMemberStatusCreator: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isAnonymous == rhs.isAnonymous else { return false }
        guard lhs.isMember == rhs.isMember else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isAnonymous)
        hasher.combine(isMember)
    }
}

// MARK: - TDNativeChatMemberStatusMember + @retroactive Hashable

extension TDNativeChatMemberStatusMember: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.memberUntilDate == rhs.memberUntilDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(memberUntilDate)
    }
}

// MARK: - TDNativeChatMemberStatusRestricted + @retroactive Hashable

extension TDNativeChatMemberStatusRestricted: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isMember == rhs.isMember else { return false }
        guard lhs.restrictedUntilDate == rhs.restrictedUntilDate else { return false }
        guard lhs.permissions == rhs.permissions else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isMember)
        hasher.combine(restrictedUntilDate)
        hasher.combine(permissions)
    }
}

// MARK: - TDNativeChatNotificationSettings + @retroactive Hashable

extension TDNativeChatNotificationSettings: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.useDefaultMuteFor == rhs.useDefaultMuteFor else { return false }
        guard lhs.muteFor == rhs.muteFor else { return false }
        guard lhs.useDefaultSound == rhs.useDefaultSound else { return false }
        guard lhs.soundId == rhs.soundId else { return false }
        guard lhs.useDefaultShowPreview == rhs.useDefaultShowPreview else { return false }
        guard lhs.showPreview == rhs.showPreview else { return false }
        guard lhs.useDefaultMuteStories == rhs.useDefaultMuteStories else { return false }
        guard lhs.muteStories == rhs.muteStories else { return false }
        guard lhs.useDefaultStorySound == rhs.useDefaultStorySound else { return false }
        guard lhs.storySoundId == rhs.storySoundId else { return false }
        guard lhs.useDefaultShowStoryPoster == rhs.useDefaultShowStoryPoster else { return false }
        guard lhs.showStoryPoster == rhs.showStoryPoster else { return false }
        guard lhs.useDefaultDisablePinnedMessageNotifications == rhs.useDefaultDisablePinnedMessageNotifications
        else { return false }
        guard lhs.disablePinnedMessageNotifications == rhs.disablePinnedMessageNotifications else { return false }
        guard lhs.useDefaultDisableMentionNotifications == rhs.useDefaultDisableMentionNotifications
        else { return false }
        guard lhs.disableMentionNotifications == rhs.disableMentionNotifications else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(useDefaultMuteFor)
        hasher.combine(muteFor)
        hasher.combine(useDefaultSound)
        hasher.combine(soundId)
        hasher.combine(useDefaultShowPreview)
        hasher.combine(showPreview)
        hasher.combine(useDefaultMuteStories)
        hasher.combine(muteStories)
        hasher.combine(useDefaultStorySound)
        hasher.combine(storySoundId)
        hasher.combine(useDefaultShowStoryPoster)
        hasher.combine(showStoryPoster)
        hasher.combine(useDefaultDisablePinnedMessageNotifications)
        hasher.combine(disablePinnedMessageNotifications)
        hasher.combine(useDefaultDisableMentionNotifications)
        hasher.combine(disableMentionNotifications)
    }
}

// MARK: - TDNativeChatPermissions + @retroactive Hashable

extension TDNativeChatPermissions: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canSendBasicMessages == rhs.canSendBasicMessages else { return false }
        guard lhs.canSendAudios == rhs.canSendAudios else { return false }
        guard lhs.canSendDocuments == rhs.canSendDocuments else { return false }
        guard lhs.canSendPhotos == rhs.canSendPhotos else { return false }
        guard lhs.canSendVideos == rhs.canSendVideos else { return false }
        guard lhs.canSendVideoNotes == rhs.canSendVideoNotes else { return false }
        guard lhs.canSendVoiceNotes == rhs.canSendVoiceNotes else { return false }
        guard lhs.canSendPolls == rhs.canSendPolls else { return false }
        guard lhs.canSendOtherMessages == rhs.canSendOtherMessages else { return false }
        guard lhs.canAddLinkPreviews == rhs.canAddLinkPreviews else { return false }
        guard lhs.canReactToMessages == rhs.canReactToMessages else { return false }
        guard lhs.canEditTag == rhs.canEditTag else { return false }
        guard lhs.canChangeInfo == rhs.canChangeInfo else { return false }
        guard lhs.canInviteUsers == rhs.canInviteUsers else { return false }
        guard lhs.canPinMessages == rhs.canPinMessages else { return false }
        guard lhs.canCreateTopics == rhs.canCreateTopics else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canSendBasicMessages)
        hasher.combine(canSendAudios)
        hasher.combine(canSendDocuments)
        hasher.combine(canSendPhotos)
        hasher.combine(canSendVideos)
        hasher.combine(canSendVideoNotes)
        hasher.combine(canSendVoiceNotes)
        hasher.combine(canSendPolls)
        hasher.combine(canSendOtherMessages)
        hasher.combine(canAddLinkPreviews)
        hasher.combine(canReactToMessages)
        hasher.combine(canEditTag)
        hasher.combine(canChangeInfo)
        hasher.combine(canInviteUsers)
        hasher.combine(canPinMessages)
        hasher.combine(canCreateTopics)
    }
}

// MARK: - TDNativeChatPhoto + @retroactive Hashable

extension TDNativeChatPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.addedDate == rhs.addedDate else { return false }
        guard lhs.minithumbnail == rhs.minithumbnail else { return false }
        guard lhs.sizes == rhs.sizes else { return false }
        guard lhs.animation == rhs.animation else { return false }
        guard lhs.smallAnimation == rhs.smallAnimation else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(addedDate)
        hasher.combine(minithumbnail)
        hasher.combine(sizes)
        hasher.combine(animation)
        hasher.combine(smallAnimation)
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeChatPhotoSticker + @retroactive Hashable

extension TDNativeChatPhotoSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.backgroundFill == rhs.backgroundFill else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(backgroundFill)
    }
}

// MARK: - TDNativeChatPhotoStickerType + @retroactive Hashable

extension TDNativeChatPhotoStickerType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatPhotoStickerTypeRegularOrMask(let lhs), .chatPhotoStickerTypeRegularOrMask(let rhs)):
            lhs == rhs
        case (.chatPhotoStickerTypeCustomEmoji(let lhs), .chatPhotoStickerTypeCustomEmoji(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatPhotoStickerTypeRegularOrMask(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .chatPhotoStickerTypeCustomEmoji(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeChatPhotoStickerTypeCustomEmoji + @retroactive Hashable

extension TDNativeChatPhotoStickerTypeCustomEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.customEmojiId == rhs.customEmojiId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(customEmojiId)
    }
}

// MARK: - TDNativeChatPhotoStickerTypeRegularOrMask + @retroactive Hashable

extension TDNativeChatPhotoStickerTypeRegularOrMask: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.stickerSetId == rhs.stickerSetId else { return false }
        guard lhs.stickerId == rhs.stickerId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stickerSetId)
        hasher.combine(stickerId)
    }
}

// MARK: - TDNativeChatPosition + @retroactive Hashable

extension TDNativeChatPosition: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.list == rhs.list else { return false }
        guard lhs.order == rhs.order else { return false }
        guard lhs.isPinned == rhs.isPinned else { return false }
        guard lhs.source == rhs.source else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(list)
        hasher.combine(order)
        hasher.combine(isPinned)
        hasher.combine(source)
    }
}

// MARK: - TDNativeChatSource + @retroactive Hashable

extension TDNativeChatSource: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatSourceMtprotoProxy, .chatSourceMtprotoProxy):
            true
        case (.chatSourcePublicServiceAnnouncement(let lhs), .chatSourcePublicServiceAnnouncement(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatSourceMtprotoProxy:
            hasher.combine(0)
        case .chatSourcePublicServiceAnnouncement(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeChatSourcePublicServiceAnnouncement + @retroactive Hashable

extension TDNativeChatSourcePublicServiceAnnouncement: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(text)
    }
}

// MARK: - TDNativeChatTheme + @retroactive Hashable

extension TDNativeChatTheme: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatThemeEmoji(let lhs), .chatThemeEmoji(let rhs)):
            lhs == rhs
        case (.chatThemeGift(let lhs), .chatThemeGift(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatThemeEmoji(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .chatThemeGift(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeChatThemeEmoji + @retroactive Hashable

extension TDNativeChatThemeEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - TDNativeChatThemeGift + @retroactive Hashable

extension TDNativeChatThemeGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.giftTheme == rhs.giftTheme else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(giftTheme)
    }
}

// MARK: - TDNativeChatType + @retroactive Hashable

extension TDNativeChatType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chatTypePrivate(let lhs), .chatTypePrivate(let rhs)):
            lhs == rhs
        case (.chatTypeBasicGroup(let lhs), .chatTypeBasicGroup(let rhs)):
            lhs == rhs
        case (.chatTypeSupergroup(let lhs), .chatTypeSupergroup(let rhs)):
            lhs == rhs
        case (.chatTypeSecret(let lhs), .chatTypeSecret(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .chatTypePrivate(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .chatTypeBasicGroup(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .chatTypeSupergroup(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .chatTypeSecret(let value):
            hasher.combine(3)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeChatTypeBasicGroup + @retroactive Hashable

extension TDNativeChatTypeBasicGroup: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.basicGroupId == rhs.basicGroupId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(basicGroupId)
    }
}

// MARK: - TDNativeChatTypePrivate + @retroactive Hashable

extension TDNativeChatTypePrivate: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.userId == rhs.userId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }
}

// MARK: - TDNativeChatTypeSecret + @retroactive Hashable

extension TDNativeChatTypeSecret: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.secretChatId == rhs.secretChatId else { return false }
        guard lhs.userId == rhs.userId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(secretChatId)
        hasher.combine(userId)
    }
}

// MARK: - TDNativeChatTypeSupergroup + @retroactive Hashable

extension TDNativeChatTypeSupergroup: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.supergroupId == rhs.supergroupId else { return false }
        guard lhs.isChannel == rhs.isChannel else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(supergroupId)
        hasher.combine(isChannel)
    }
}

// MARK: - TDNativeChecklist + @retroactive Hashable

extension TDNativeChecklist: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        guard lhs.tasks == rhs.tasks else { return false }
        guard lhs.othersCanAddTasks == rhs.othersCanAddTasks else { return false }
        guard lhs.canAddTasks == rhs.canAddTasks else { return false }
        guard lhs.othersCanMarkTasksAsDone == rhs.othersCanMarkTasksAsDone else { return false }
        guard lhs.canMarkTasksAsDone == rhs.canMarkTasksAsDone else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(tasks)
        hasher.combine(othersCanAddTasks)
        hasher.combine(canAddTasks)
        hasher.combine(othersCanMarkTasksAsDone)
        hasher.combine(canMarkTasksAsDone)
    }
}

// MARK: - TDNativeChecklistTask + @retroactive Hashable

extension TDNativeChecklistTask: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.completedBy == rhs.completedBy else { return false }
        guard lhs.completionDate == rhs.completionDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(text)
        hasher.combine(completedBy)
        hasher.combine(completionDate)
    }
}

// MARK: - TDNativeContact + @retroactive Hashable

extension TDNativeContact: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.phoneNumber == rhs.phoneNumber else { return false }
        guard lhs.firstName == rhs.firstName else { return false }
        guard lhs.lastName == rhs.lastName else { return false }
        guard lhs.vcard == rhs.vcard else { return false }
        guard lhs.userId == rhs.userId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(phoneNumber)
        hasher.combine(firstName)
        hasher.combine(lastName)
        hasher.combine(vcard)
        hasher.combine(userId)
    }
}

// MARK: - TDNativeDateTimeFormattingType + @retroactive Hashable

extension TDNativeDateTimeFormattingType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.dateTimeFormattingTypeRelative, .dateTimeFormattingTypeRelative):
            true
        case (.dateTimeFormattingTypeAbsolute(let lhs), .dateTimeFormattingTypeAbsolute(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .dateTimeFormattingTypeRelative:
            hasher.combine(0)
        case .dateTimeFormattingTypeAbsolute(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeDateTimeFormattingTypeAbsolute + @retroactive Hashable

extension TDNativeDateTimeFormattingTypeAbsolute: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.timePrecision == rhs.timePrecision else { return false }
        guard lhs.datePrecision == rhs.datePrecision else { return false }
        guard lhs.showDayOfWeek == rhs.showDayOfWeek else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(timePrecision)
        hasher.combine(datePrecision)
        hasher.combine(showDayOfWeek)
    }
}

// MARK: - TDNativeDatedFile + @retroactive Hashable

extension TDNativeDatedFile: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.file == rhs.file else { return false }
        guard lhs.date == rhs.date else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(file)
        hasher.combine(date)
    }
}

// MARK: - TDNativeDiceStickers + @retroactive Hashable

extension TDNativeDiceStickers: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.diceStickersRegular(let lhs), .diceStickersRegular(let rhs)):
            lhs == rhs
        case (.diceStickersSlotMachine(let lhs), .diceStickersSlotMachine(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .diceStickersRegular(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .diceStickersSlotMachine(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeDiceStickersRegular + @retroactive Hashable

extension TDNativeDiceStickersRegular: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeDiceStickersSlotMachine + @retroactive Hashable

extension TDNativeDiceStickersSlotMachine: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.background == rhs.background else { return false }
        guard lhs.lever == rhs.lever else { return false }
        guard lhs.leftReel == rhs.leftReel else { return false }
        guard lhs.centerReel == rhs.centerReel else { return false }
        guard lhs.rightReel == rhs.rightReel else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(background)
        hasher.combine(lever)
        hasher.combine(leftReel)
        hasher.combine(centerReel)
        hasher.combine(rightReel)
    }
}

// MARK: - TDNativeDocument + @retroactive Hashable

extension TDNativeDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.fileName == rhs.fileName else { return false }
        guard lhs.mimeType == rhs.mimeType else { return false }
        guard lhs.minithumbnail == rhs.minithumbnail else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.document == rhs.document else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
        hasher.combine(mimeType)
        hasher.combine(minithumbnail)
        hasher.combine(thumbnail)
        hasher.combine(document)
    }
}

// MARK: - TDNativeDraftMessage + @retroactive Hashable

extension TDNativeDraftMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.replyTo == rhs.replyTo else { return false }
        guard lhs.date == rhs.date else { return false }
        guard lhs.content == rhs.content else { return false }
        guard lhs.effectId == rhs.effectId else { return false }
        guard lhs.suggestedPostInfo == rhs.suggestedPostInfo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(replyTo)
        hasher.combine(date)
        hasher.combine(content)
        hasher.combine(effectId)
        hasher.combine(suggestedPostInfo)
    }
}

// MARK: - TDNativeDraftMessageContent + @retroactive Hashable

extension TDNativeDraftMessageContent: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.draftMessageContentText(let lhs), .draftMessageContentText(let rhs)):
            lhs == rhs
        case (.draftMessageContentRichMessage(let lhs), .draftMessageContentRichMessage(let rhs)):
            lhs == rhs
        case (.draftMessageContentInputRichMessage(let lhs), .draftMessageContentInputRichMessage(let rhs)):
            lhs == rhs
        case (.draftMessageContentVideoNote(let lhs), .draftMessageContentVideoNote(let rhs)):
            lhs == rhs
        case (.draftMessageContentVoiceNote(let lhs), .draftMessageContentVoiceNote(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .draftMessageContentText(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .draftMessageContentRichMessage(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .draftMessageContentInputRichMessage(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .draftMessageContentVideoNote(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .draftMessageContentVoiceNote(let value):
            hasher.combine(4)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeDraftMessageContentInputRichMessage + @retroactive Hashable

extension TDNativeDraftMessageContentInputRichMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.message == rhs.message else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(message)
    }
}

// MARK: - TDNativeDraftMessageContentRichMessage + @retroactive Hashable

extension TDNativeDraftMessageContentRichMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.message == rhs.message else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(message)
    }
}

// MARK: - TDNativeDraftMessageContentText + @retroactive Hashable

extension TDNativeDraftMessageContentText: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.linkPreviewOptions == rhs.linkPreviewOptions else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(linkPreviewOptions)
    }
}

// MARK: - TDNativeDraftMessageContentVideoNote + @retroactive Hashable

extension TDNativeDraftMessageContentVideoNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.filePath == rhs.filePath else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.length == rhs.length else { return false }
        guard lhs.selfDestructType == rhs.selfDestructType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(filePath)
        hasher.combine(duration)
        hasher.combine(length)
        hasher.combine(selfDestructType)
    }
}

// MARK: - TDNativeDraftMessageContentVoiceNote + @retroactive Hashable

extension TDNativeDraftMessageContentVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.filePath == rhs.filePath else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.waveform == rhs.waveform else { return false }
        guard lhs.selfDestructType == rhs.selfDestructType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(filePath)
        hasher.combine(duration)
        hasher.combine(waveform)
        hasher.combine(selfDestructType)
    }
}

// MARK: - TDNativeEmailAddressAuthenticationCodeInfo + @retroactive Hashable

extension TDNativeEmailAddressAuthenticationCodeInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.emailAddressPattern == rhs.emailAddressPattern else { return false }
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(emailAddressPattern)
        hasher.combine(length)
    }
}

// MARK: - TDNativeEmailAddressResetState + @retroactive Hashable

extension TDNativeEmailAddressResetState: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.emailAddressResetStateAvailable(let lhs), .emailAddressResetStateAvailable(let rhs)):
            lhs == rhs
        case (.emailAddressResetStatePending(let lhs), .emailAddressResetStatePending(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .emailAddressResetStateAvailable(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .emailAddressResetStatePending(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeEmailAddressResetStateAvailable + @retroactive Hashable

extension TDNativeEmailAddressResetStateAvailable: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.waitPeriod == rhs.waitPeriod else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(waitPeriod)
    }
}

// MARK: - TDNativeEmailAddressResetStatePending + @retroactive Hashable

extension TDNativeEmailAddressResetStatePending: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.resetIn == rhs.resetIn else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(resetIn)
    }
}

// MARK: - TDNativeEmojiStatus + @retroactive Hashable

extension TDNativeEmojiStatus: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.expirationDate == rhs.expirationDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(expirationDate)
    }
}

// MARK: - TDNativeEmojiStatusType + @retroactive Hashable

extension TDNativeEmojiStatusType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.emojiStatusTypeCustomEmoji(let lhs), .emojiStatusTypeCustomEmoji(let rhs)):
            lhs == rhs
        case (.emojiStatusTypeUpgradedGift(let lhs), .emojiStatusTypeUpgradedGift(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .emojiStatusTypeCustomEmoji(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .emojiStatusTypeUpgradedGift(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeEmojiStatusTypeCustomEmoji + @retroactive Hashable

extension TDNativeEmojiStatusTypeCustomEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.customEmojiId == rhs.customEmojiId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(customEmojiId)
    }
}

// MARK: - TDNativeEmojiStatusTypeUpgradedGift + @retroactive Hashable

extension TDNativeEmojiStatusTypeUpgradedGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.upgradedGiftId == rhs.upgradedGiftId else { return false }
        guard lhs.giftTitle == rhs.giftTitle else { return false }
        guard lhs.giftName == rhs.giftName else { return false }
        guard lhs.modelCustomEmojiId == rhs.modelCustomEmojiId else { return false }
        guard lhs.symbolCustomEmojiId == rhs.symbolCustomEmojiId else { return false }
        guard lhs.backdropColors == rhs.backdropColors else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(upgradedGiftId)
        hasher.combine(giftTitle)
        hasher.combine(giftName)
        hasher.combine(modelCustomEmojiId)
        hasher.combine(symbolCustomEmojiId)
        hasher.combine(backdropColors)
    }
}

// MARK: - TDNativeEncryptedCredentials + @retroactive Hashable

extension TDNativeEncryptedCredentials: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.data == rhs.data else { return false }
        guard lhs.hash == rhs.hash else { return false }
        guard lhs.secret == rhs.secret else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(data)
        hasher.combine(hash)
        hasher.combine(secret)
    }
}

// MARK: - TDNativeEncryptedPassportElement + @retroactive Hashable

extension TDNativeEncryptedPassportElement: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.data == rhs.data else { return false }
        guard lhs.frontSide == rhs.frontSide else { return false }
        guard lhs.reverseSide == rhs.reverseSide else { return false }
        guard lhs.selfie == rhs.selfie else { return false }
        guard lhs.translation == rhs.translation else { return false }
        guard lhs.files == rhs.files else { return false }
        guard lhs.value == rhs.value else { return false }
        guard lhs.hash == rhs.hash else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(data)
        hasher.combine(frontSide)
        hasher.combine(reverseSide)
        hasher.combine(selfie)
        hasher.combine(translation)
        hasher.combine(files)
        hasher.combine(value)
        hasher.combine(hash)
    }
}

// MARK: - TDNativeEphemeralMessageContent + @retroactive Hashable

extension TDNativeEphemeralMessageContent: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canBeSaved == rhs.canBeSaved else { return false }
        guard lhs.hasTimestampedMedia == rhs.hasTimestampedMedia else { return false }
        guard lhs.content == rhs.content else { return false }
        guard lhs.replyMarkup == rhs.replyMarkup else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canBeSaved)
        hasher.combine(hasTimestampedMedia)
        hasher.combine(content)
        hasher.combine(replyMarkup)
    }
}

// MARK: - TDNativeError + @retroactive Hashable

extension TDNativeError: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.code == rhs.code else { return false }
        guard lhs.message == rhs.message else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(message)
    }
}

// MARK: - TDNativeFactCheck + @retroactive Hashable

extension TDNativeFactCheck: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.countryCode == rhs.countryCode else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(countryCode)
    }
}

// MARK: - TDNativeFirebaseDeviceVerificationParameters + @retroactive Hashable

extension TDNativeFirebaseDeviceVerificationParameters: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (
            .firebaseDeviceVerificationParametersSafetyNet(let lhs),
            .firebaseDeviceVerificationParametersSafetyNet(let rhs),
        ):
            lhs == rhs
        case (
            .firebaseDeviceVerificationParametersPlayIntegrity(let lhs),
            .firebaseDeviceVerificationParametersPlayIntegrity(let rhs),
        ):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .firebaseDeviceVerificationParametersSafetyNet(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .firebaseDeviceVerificationParametersPlayIntegrity(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeFirebaseDeviceVerificationParametersPlayIntegrity + @retroactive Hashable

extension TDNativeFirebaseDeviceVerificationParametersPlayIntegrity: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.nonce == rhs.nonce else { return false }
        guard lhs.cloudProjectNumber == rhs.cloudProjectNumber else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(nonce)
        hasher.combine(cloudProjectNumber)
    }
}

// MARK: - TDNativeFirebaseDeviceVerificationParametersSafetyNet + @retroactive Hashable

extension TDNativeFirebaseDeviceVerificationParametersSafetyNet: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.nonce == rhs.nonce else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(nonce)
    }
}

// MARK: - TDNativeForumTopic + @retroactive Hashable

extension TDNativeForumTopic: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.info == rhs.info else { return false }
        guard lhs.lastMessage == rhs.lastMessage else { return false }
        guard lhs.order == rhs.order else { return false }
        guard lhs.isPinned == rhs.isPinned else { return false }
        guard lhs.unreadCount == rhs.unreadCount else { return false }
        guard lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId else { return false }
        guard lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId else { return false }
        guard lhs.unreadMentionCount == rhs.unreadMentionCount else { return false }
        guard lhs.unreadReactionCount == rhs.unreadReactionCount else { return false }
        guard lhs.unreadPollVoteCount == rhs.unreadPollVoteCount else { return false }
        guard lhs.notificationSettings == rhs.notificationSettings else { return false }
        guard lhs.draftMessage == rhs.draftMessage else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(info)
        hasher.combine(lastMessage)
        hasher.combine(order)
        hasher.combine(isPinned)
        hasher.combine(unreadCount)
        hasher.combine(lastReadInboxMessageId)
        hasher.combine(lastReadOutboxMessageId)
        hasher.combine(unreadMentionCount)
        hasher.combine(unreadReactionCount)
        hasher.combine(unreadPollVoteCount)
        hasher.combine(notificationSettings)
        hasher.combine(draftMessage)
    }
}

// MARK: - TDNativeForumTopicIcon + @retroactive Hashable

extension TDNativeForumTopicIcon: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.color == rhs.color else { return false }
        guard lhs.customEmojiId == rhs.customEmojiId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(color)
        hasher.combine(customEmojiId)
    }
}

// MARK: - TDNativeForumTopicInfo + @retroactive Hashable

extension TDNativeForumTopicInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatId == rhs.chatId else { return false }
        guard lhs.forumTopicId == rhs.forumTopicId else { return false }
        guard lhs.name == rhs.name else { return false }
        guard lhs.icon == rhs.icon else { return false }
        guard lhs.creationDate == rhs.creationDate else { return false }
        guard lhs.creatorId == rhs.creatorId else { return false }
        guard lhs.isGeneral == rhs.isGeneral else { return false }
        guard lhs.isOutgoing == rhs.isOutgoing else { return false }
        guard lhs.isClosed == rhs.isClosed else { return false }
        guard lhs.isHidden == rhs.isHidden else { return false }
        guard lhs.isNameImplicit == rhs.isNameImplicit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
        hasher.combine(forumTopicId)
        hasher.combine(name)
        hasher.combine(icon)
        hasher.combine(creationDate)
        hasher.combine(creatorId)
        hasher.combine(isGeneral)
        hasher.combine(isOutgoing)
        hasher.combine(isClosed)
        hasher.combine(isHidden)
        hasher.combine(isNameImplicit)
    }
}

// MARK: - TDNativeForwardSource + @retroactive Hashable

extension TDNativeForwardSource: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatId == rhs.chatId else { return false }
        guard lhs.messageId == rhs.messageId else { return false }
        guard lhs.senderId == rhs.senderId else { return false }
        guard lhs.senderName == rhs.senderName else { return false }
        guard lhs.date == rhs.date else { return false }
        guard lhs.isOutgoing == rhs.isOutgoing else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
        hasher.combine(messageId)
        hasher.combine(senderId)
        hasher.combine(senderName)
        hasher.combine(date)
        hasher.combine(isOutgoing)
    }
}

// MARK: - TDNativeGame + @retroactive Hashable

extension TDNativeGame: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.shortName == rhs.shortName else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.animation == rhs.animation else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(shortName)
        hasher.combine(title)
        hasher.combine(text)
        hasher.combine(description)
        hasher.combine(photo)
        hasher.combine(animation)
    }
}

// MARK: - TDNativeGift + @retroactive Hashable

extension TDNativeGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.publisherChatId == rhs.publisherChatId else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.defaultSellStarCount == rhs.defaultSellStarCount else { return false }
        guard lhs.upgradeStarCount == rhs.upgradeStarCount else { return false }
        guard lhs.upgradeVariantCount == rhs.upgradeVariantCount else { return false }
        guard lhs.hasColors == rhs.hasColors else { return false }
        guard lhs.isForBirthday == rhs.isForBirthday else { return false }
        guard lhs.isPremium == rhs.isPremium else { return false }
        guard lhs.auctionInfo == rhs.auctionInfo else { return false }
        guard lhs.nextSendDate == rhs.nextSendDate else { return false }
        guard lhs.userLimits == rhs.userLimits else { return false }
        guard lhs.overallLimits == rhs.overallLimits else { return false }
        guard lhs.background == rhs.background else { return false }
        guard lhs.firstSendDate == rhs.firstSendDate else { return false }
        guard lhs.lastSendDate == rhs.lastSendDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(publisherChatId)
        hasher.combine(sticker)
        hasher.combine(starCount)
        hasher.combine(defaultSellStarCount)
        hasher.combine(upgradeStarCount)
        hasher.combine(upgradeVariantCount)
        hasher.combine(hasColors)
        hasher.combine(isForBirthday)
        hasher.combine(isPremium)
        hasher.combine(auctionInfo)
        hasher.combine(nextSendDate)
        hasher.combine(userLimits)
        hasher.combine(overallLimits)
        hasher.combine(background)
        hasher.combine(firstSendDate)
        hasher.combine(lastSendDate)
    }
}

// MARK: - TDNativeGiftAuction + @retroactive Hashable

extension TDNativeGiftAuction: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.giftsPerRound == rhs.giftsPerRound else { return false }
        guard lhs.startDate == rhs.startDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(giftsPerRound)
        hasher.combine(startDate)
    }
}

// MARK: - TDNativeGiftBackground + @retroactive Hashable

extension TDNativeGiftBackground: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.centerColor == rhs.centerColor else { return false }
        guard lhs.edgeColor == rhs.edgeColor else { return false }
        guard lhs.textColor == rhs.textColor else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(centerColor)
        hasher.combine(edgeColor)
        hasher.combine(textColor)
    }
}

// MARK: - TDNativeGiftChatTheme + @retroactive Hashable

extension TDNativeGiftChatTheme: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        guard lhs.lightSettings == rhs.lightSettings else { return false }
        guard lhs.darkSettings == rhs.darkSettings else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
        hasher.combine(lightSettings)
        hasher.combine(darkSettings)
    }
}

// MARK: - TDNativeGiftPurchaseLimits + @retroactive Hashable

extension TDNativeGiftPurchaseLimits: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.totalCount == rhs.totalCount else { return false }
        guard lhs.remainingCount == rhs.remainingCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(totalCount)
        hasher.combine(remainingCount)
    }
}

// MARK: - TDNativeGiftResaleParameters + @retroactive Hashable

extension TDNativeGiftResaleParameters: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.gramCentCount == rhs.gramCentCount else { return false }
        guard lhs.gramOnly == rhs.gramOnly else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
        hasher.combine(gramCentCount)
        hasher.combine(gramOnly)
    }
}

// MARK: - TDNativeGiftResalePrice + @retroactive Hashable

extension TDNativeGiftResalePrice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.giftResalePriceStar(let lhs), .giftResalePriceStar(let rhs)):
            lhs == rhs
        case (.giftResalePriceGram(let lhs), .giftResalePriceGram(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .giftResalePriceStar(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .giftResalePriceGram(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeGiftResalePriceGram + @retroactive Hashable

extension TDNativeGiftResalePriceGram: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gramCentCount == rhs.gramCentCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gramCentCount)
    }
}

// MARK: - TDNativeGiftResalePriceStar + @retroactive Hashable

extension TDNativeGiftResalePriceStar: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
    }
}

// MARK: - TDNativeGiveawayParameters + @retroactive Hashable

extension TDNativeGiveawayParameters: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.boostedChatId == rhs.boostedChatId else { return false }
        guard lhs.additionalChatIds == rhs.additionalChatIds else { return false }
        guard lhs.winnersSelectionDate == rhs.winnersSelectionDate else { return false }
        guard lhs.onlyNewMembers == rhs.onlyNewMembers else { return false }
        guard lhs.hasPublicWinners == rhs.hasPublicWinners else { return false }
        guard lhs.countryCodes == rhs.countryCodes else { return false }
        guard lhs.prizeDescription == rhs.prizeDescription else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(boostedChatId)
        hasher.combine(additionalChatIds)
        hasher.combine(winnersSelectionDate)
        hasher.combine(onlyNewMembers)
        hasher.combine(hasPublicWinners)
        hasher.combine(countryCodes)
        hasher.combine(prizeDescription)
    }
}

// MARK: - TDNativeGiveawayPrize + @retroactive Hashable

extension TDNativeGiveawayPrize: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.giveawayPrizePremium(let lhs), .giveawayPrizePremium(let rhs)):
            lhs == rhs
        case (.giveawayPrizeStars(let lhs), .giveawayPrizeStars(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .giveawayPrizePremium(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .giveawayPrizeStars(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeGiveawayPrizePremium + @retroactive Hashable

extension TDNativeGiveawayPrizePremium: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.monthCount == rhs.monthCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(monthCount)
    }
}

// MARK: - TDNativeGiveawayPrizeStars + @retroactive Hashable

extension TDNativeGiveawayPrizeStars: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
    }
}

// MARK: - TDNativeInlineButton + @retroactive Hashable

extension TDNativeInlineButton: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.style == rhs.style else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(style)
        hasher.combine(type)
    }
}

// MARK: - TDNativeInlineKeyboardButton + @retroactive Hashable

extension TDNativeInlineKeyboardButton: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.iconCustomEmojiId == rhs.iconCustomEmojiId else { return false }
        guard lhs.style == rhs.style else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(iconCustomEmojiId)
        hasher.combine(style)
        hasher.combine(type)
    }
}

// MARK: - TDNativeInlineKeyboardButtonType + @retroactive Hashable

extension TDNativeInlineKeyboardButtonType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inlineKeyboardButtonTypeUrl(let lhs), .inlineKeyboardButtonTypeUrl(let rhs)):
            lhs == rhs
        case (.inlineKeyboardButtonTypeLoginUrl(let lhs), .inlineKeyboardButtonTypeLoginUrl(let rhs)):
            lhs == rhs
        case (.inlineKeyboardButtonTypeWebApp(let lhs), .inlineKeyboardButtonTypeWebApp(let rhs)):
            lhs == rhs
        case (.inlineKeyboardButtonTypeCallback(let lhs), .inlineKeyboardButtonTypeCallback(let rhs)):
            lhs == rhs
        case (
            .inlineKeyboardButtonTypeCallbackWithPassword(let lhs),
            .inlineKeyboardButtonTypeCallbackWithPassword(let rhs),
        ):
            lhs == rhs
        case (.inlineKeyboardButtonTypeCallbackGame, .inlineKeyboardButtonTypeCallbackGame):
            true
        case (.inlineKeyboardButtonTypeSwitchInline(let lhs), .inlineKeyboardButtonTypeSwitchInline(let rhs)):
            lhs == rhs
        case (.inlineKeyboardButtonTypeBuy, .inlineKeyboardButtonTypeBuy):
            true
        case (.inlineKeyboardButtonTypeUser(let lhs), .inlineKeyboardButtonTypeUser(let rhs)):
            lhs == rhs
        case (.inlineKeyboardButtonTypeCopyText(let lhs), .inlineKeyboardButtonTypeCopyText(let rhs)):
            lhs == rhs
        case (.inlineKeyboardButtonTypeDisabled, .inlineKeyboardButtonTypeDisabled):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .inlineKeyboardButtonTypeUrl(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeLoginUrl(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeWebApp(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeCallback(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeCallbackWithPassword(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeCallbackGame:
            hasher.combine(5)
        case .inlineKeyboardButtonTypeSwitchInline(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeBuy:
            hasher.combine(7)
        case .inlineKeyboardButtonTypeUser(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeCopyText(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .inlineKeyboardButtonTypeDisabled:
            hasher.combine(10)
        }
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeCallback + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeCallback: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.data == rhs.data else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(data)
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeCallbackWithPassword + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeCallbackWithPassword: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.data == rhs.data else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(data)
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeCopyText + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeCopyText: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeLoginUrl + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeLoginUrl: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.id == rhs.id else { return false }
        guard lhs.forwardText == rhs.forwardText else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(id)
        hasher.combine(forwardText)
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeSwitchInline + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeSwitchInline: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.query == rhs.query else { return false }
        guard lhs.targetChat == rhs.targetChat else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(targetChat)
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeUrl + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeUrl: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeUser + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.userId == rhs.userId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }
}

// MARK: - TDNativeInlineKeyboardButtonTypeWebApp + @retroactive Hashable

extension TDNativeInlineKeyboardButtonTypeWebApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - TDNativeInputAnimation + @retroactive Hashable

extension TDNativeInputAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animation == rhs.animation else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.addedStickerFileIds == rhs.addedStickerFileIds else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
        hasher.combine(thumbnail)
        hasher.combine(addedStickerFileIds)
        hasher.combine(duration)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeInputAudio + @retroactive Hashable

extension TDNativeInputAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        guard lhs.albumCoverThumbnail == rhs.albumCoverThumbnail else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.performer == rhs.performer else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
        hasher.combine(albumCoverThumbnail)
        hasher.combine(duration)
        hasher.combine(title)
        hasher.combine(performer)
    }
}

// MARK: - TDNativeInputChecklist + @retroactive Hashable

extension TDNativeInputChecklist: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        guard lhs.tasks == rhs.tasks else { return false }
        guard lhs.othersCanAddTasks == rhs.othersCanAddTasks else { return false }
        guard lhs.othersCanMarkTasksAsDone == rhs.othersCanMarkTasksAsDone else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(tasks)
        hasher.combine(othersCanAddTasks)
        hasher.combine(othersCanMarkTasksAsDone)
    }
}

// MARK: - TDNativeInputChecklistTask + @retroactive Hashable

extension TDNativeInputChecklistTask: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(text)
    }
}

// MARK: - TDNativeInputDocument + @retroactive Hashable

extension TDNativeInputDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.disableContentTypeDetection == rhs.disableContentTypeDetection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
        hasher.combine(thumbnail)
        hasher.combine(disableContentTypeDetection)
    }
}

// MARK: - TDNativeInputFile + @retroactive Hashable

extension TDNativeInputFile: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inputFileId(let lhs), .inputFileId(let rhs)):
            lhs == rhs
        case (.inputFileRemote(let lhs), .inputFileRemote(let rhs)):
            lhs == rhs
        case (.inputFileLocal(let lhs), .inputFileLocal(let rhs)):
            lhs == rhs
        case (.inputFileGenerated(let lhs), .inputFileGenerated(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .inputFileId(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .inputFileRemote(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .inputFileLocal(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .inputFileGenerated(let value):
            hasher.combine(3)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInputFileGenerated + @retroactive Hashable

extension TDNativeInputFileGenerated: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.originalPath == rhs.originalPath else { return false }
        guard lhs.conversion == rhs.conversion else { return false }
        guard lhs.expectedSize == rhs.expectedSize else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(originalPath)
        hasher.combine(conversion)
        hasher.combine(expectedSize)
    }
}

// MARK: - TDNativeInputFileId + @retroactive Hashable

extension TDNativeInputFileId: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - TDNativeInputFileLocal + @retroactive Hashable

extension TDNativeInputFileLocal: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.path == rhs.path else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

// MARK: - TDNativeInputFileRemote + @retroactive Hashable

extension TDNativeInputFileRemote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - TDNativeInputMessageAnimation + @retroactive Hashable

extension TDNativeInputMessageAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animation == rhs.animation else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativeInputMessageAudio + @retroactive Hashable

extension TDNativeInputMessageAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputMessageChecklist + @retroactive Hashable

extension TDNativeInputMessageChecklist: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.checklist == rhs.checklist else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(checklist)
    }
}

// MARK: - TDNativeInputMessageContact + @retroactive Hashable

extension TDNativeInputMessageContact: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.contact == rhs.contact else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(contact)
    }
}

// MARK: - TDNativeInputMessageContent + @retroactive Hashable

extension TDNativeInputMessageContent: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inputMessageText(let lhs), .inputMessageText(let rhs)):
            lhs == rhs
        case (.inputMessageRichMessage(let lhs), .inputMessageRichMessage(let rhs)):
            lhs == rhs
        case (.inputMessageAnimation(let lhs), .inputMessageAnimation(let rhs)):
            lhs == rhs
        case (.inputMessageAudio(let lhs), .inputMessageAudio(let rhs)):
            lhs == rhs
        case (.inputMessageDocument(let lhs), .inputMessageDocument(let rhs)):
            lhs == rhs
        case (.inputMessagePaidMedia(let lhs), .inputMessagePaidMedia(let rhs)):
            lhs == rhs
        case (.inputMessagePhoto(let lhs), .inputMessagePhoto(let rhs)):
            lhs == rhs
        case (.inputMessageSticker(let lhs), .inputMessageSticker(let rhs)):
            lhs == rhs
        case (.inputMessageVideo(let lhs), .inputMessageVideo(let rhs)):
            lhs == rhs
        case (.inputMessageVideoNote(let lhs), .inputMessageVideoNote(let rhs)):
            lhs == rhs
        case (.inputMessageVoiceNote(let lhs), .inputMessageVoiceNote(let rhs)):
            lhs == rhs
        case (.inputMessageLiveLocation(let lhs), .inputMessageLiveLocation(let rhs)):
            lhs == rhs
        case (.inputMessageLocation(let lhs), .inputMessageLocation(let rhs)):
            lhs == rhs
        case (.inputMessageVenue(let lhs), .inputMessageVenue(let rhs)):
            lhs == rhs
        case (.inputMessageContact(let lhs), .inputMessageContact(let rhs)):
            lhs == rhs
        case (.inputMessageDice(let lhs), .inputMessageDice(let rhs)):
            lhs == rhs
        case (.inputMessageGame(let lhs), .inputMessageGame(let rhs)):
            lhs == rhs
        case (.inputMessageInvoice(let lhs), .inputMessageInvoice(let rhs)):
            lhs == rhs
        case (.inputMessagePoll(let lhs), .inputMessagePoll(let rhs)):
            lhs == rhs
        case (.inputMessageStakeDice(let lhs), .inputMessageStakeDice(let rhs)):
            lhs == rhs
        case (.inputMessageStory(let lhs), .inputMessageStory(let rhs)):
            lhs == rhs
        case (.inputMessageChecklist(let lhs), .inputMessageChecklist(let rhs)):
            lhs == rhs
        case (.inputMessageForwarded(let lhs), .inputMessageForwarded(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .inputMessageText(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .inputMessageRichMessage(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .inputMessageAnimation(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .inputMessageAudio(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .inputMessageDocument(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .inputMessagePaidMedia(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .inputMessagePhoto(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .inputMessageSticker(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .inputMessageVideo(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .inputMessageVideoNote(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .inputMessageVoiceNote(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .inputMessageLiveLocation(let value):
            hasher.combine(11)
            hasher.combine(value)
        case .inputMessageLocation(let value):
            hasher.combine(12)
            hasher.combine(value)
        case .inputMessageVenue(let value):
            hasher.combine(13)
            hasher.combine(value)
        case .inputMessageContact(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .inputMessageDice(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .inputMessageGame(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .inputMessageInvoice(let value):
            hasher.combine(17)
            hasher.combine(value)
        case .inputMessagePoll(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .inputMessageStakeDice(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .inputMessageStory(let value):
            hasher.combine(20)
            hasher.combine(value)
        case .inputMessageChecklist(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .inputMessageForwarded(let value):
            hasher.combine(22)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInputMessageDice + @retroactive Hashable

extension TDNativeInputMessageDice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.emoji == rhs.emoji else { return false }
        guard lhs.clearDraft == rhs.clearDraft else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(emoji)
        hasher.combine(clearDraft)
    }
}

// MARK: - TDNativeInputMessageDocument + @retroactive Hashable

extension TDNativeInputMessageDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputMessageForwarded + @retroactive Hashable

extension TDNativeInputMessageForwarded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.fromChatId == rhs.fromChatId else { return false }
        guard lhs.messageId == rhs.messageId else { return false }
        guard lhs.inGameShare == rhs.inGameShare else { return false }
        guard lhs.replaceVideoStartTimestamp == rhs.replaceVideoStartTimestamp else { return false }
        guard lhs.newVideoStartTimestamp == rhs.newVideoStartTimestamp else { return false }
        guard lhs.copyOptions == rhs.copyOptions else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fromChatId)
        hasher.combine(messageId)
        hasher.combine(inGameShare)
        hasher.combine(replaceVideoStartTimestamp)
        hasher.combine(newVideoStartTimestamp)
        hasher.combine(copyOptions)
    }
}

// MARK: - TDNativeInputMessageGame + @retroactive Hashable

extension TDNativeInputMessageGame: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUserId == rhs.botUserId else { return false }
        guard lhs.gameShortName == rhs.gameShortName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUserId)
        hasher.combine(gameShortName)
    }
}

// MARK: - TDNativeInputMessageInvoice + @retroactive Hashable

extension TDNativeInputMessageInvoice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.invoice == rhs.invoice else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.photoUrl == rhs.photoUrl else { return false }
        guard lhs.photoSize == rhs.photoSize else { return false }
        guard lhs.photoWidth == rhs.photoWidth else { return false }
        guard lhs.photoHeight == rhs.photoHeight else { return false }
        guard lhs.payload == rhs.payload else { return false }
        guard lhs.providerToken == rhs.providerToken else { return false }
        guard lhs.providerData == rhs.providerData else { return false }
        guard lhs.startParameter == rhs.startParameter else { return false }
        guard lhs.paidMedia == rhs.paidMedia else { return false }
        guard lhs.paidMediaCaption == rhs.paidMediaCaption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(invoice)
        hasher.combine(title)
        hasher.combine(description)
        hasher.combine(photoUrl)
        hasher.combine(photoSize)
        hasher.combine(photoWidth)
        hasher.combine(photoHeight)
        hasher.combine(payload)
        hasher.combine(providerToken)
        hasher.combine(providerData)
        hasher.combine(startParameter)
        hasher.combine(paidMedia)
        hasher.combine(paidMediaCaption)
    }
}

// MARK: - TDNativeInputMessageLiveLocation + @retroactive Hashable

extension TDNativeInputMessageLiveLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
    }
}

// MARK: - TDNativeInputMessageLocation + @retroactive Hashable

extension TDNativeInputMessageLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
    }
}

// MARK: - TDNativeInputMessagePaidMedia + @retroactive Hashable

extension TDNativeInputMessagePaidMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.paidMedia == rhs.paidMedia else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia else { return false }
        guard lhs.payload == rhs.payload else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
        hasher.combine(paidMedia)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
        hasher.combine(payload)
    }
}

// MARK: - TDNativeInputMessagePhoto + @retroactive Hashable

extension TDNativeInputMessagePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia else { return false }
        guard lhs.selfDestructType == rhs.selfDestructType else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
        hasher.combine(selfDestructType)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativeInputMessagePoll + @retroactive Hashable

extension TDNativeInputMessagePoll: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.question == rhs.question else { return false }
        guard lhs.options == rhs.options else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.media == rhs.media else { return false }
        guard lhs.isAnonymous == rhs.isAnonymous else { return false }
        guard lhs.allowsMultipleAnswers == rhs.allowsMultipleAnswers else { return false }
        guard lhs.allowsRevoting == rhs.allowsRevoting else { return false }
        guard lhs.membersOnly == rhs.membersOnly else { return false }
        guard lhs.countryCodes == rhs.countryCodes else { return false }
        guard lhs.shuffleOptions == rhs.shuffleOptions else { return false }
        guard lhs.hideResultsUntilCloses == rhs.hideResultsUntilCloses else { return false }
        guard lhs.type == rhs.type else { return false }
        guard lhs.openPeriod == rhs.openPeriod else { return false }
        guard lhs.closeDate == rhs.closeDate else { return false }
        guard lhs.isClosed == rhs.isClosed else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(question)
        hasher.combine(options)
        hasher.combine(description)
        hasher.combine(media)
        hasher.combine(isAnonymous)
        hasher.combine(allowsMultipleAnswers)
        hasher.combine(allowsRevoting)
        hasher.combine(membersOnly)
        hasher.combine(countryCodes)
        hasher.combine(shuffleOptions)
        hasher.combine(hideResultsUntilCloses)
        hasher.combine(type)
        hasher.combine(openPeriod)
        hasher.combine(closeDate)
        hasher.combine(isClosed)
    }
}

// MARK: - TDNativeInputMessageRichMessage + @retroactive Hashable

extension TDNativeInputMessageRichMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.message == rhs.message else { return false }
        guard lhs.clearDraft == rhs.clearDraft else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(message)
        hasher.combine(clearDraft)
    }
}

// MARK: - TDNativeInputMessageStakeDice + @retroactive Hashable

extension TDNativeInputMessageStakeDice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.stateHash == rhs.stateHash else { return false }
        guard lhs.stakeGramAmount == rhs.stakeGramAmount else { return false }
        guard lhs.clearDraft == rhs.clearDraft else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stateHash)
        hasher.combine(stakeGramAmount)
        hasher.combine(clearDraft)
    }
}

// MARK: - TDNativeInputMessageSticker + @retroactive Hashable

extension TDNativeInputMessageSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sticker == rhs.sticker else { return false }
        guard lhs.emoji == rhs.emoji else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
        hasher.combine(emoji)
    }
}

// MARK: - TDNativeInputMessageStory + @retroactive Hashable

extension TDNativeInputMessageStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyPosterChatId == rhs.storyPosterChatId else { return false }
        guard lhs.storyId == rhs.storyId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyPosterChatId)
        hasher.combine(storyId)
    }
}

// MARK: - TDNativeInputMessageText + @retroactive Hashable

extension TDNativeInputMessageText: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.linkPreviewOptions == rhs.linkPreviewOptions else { return false }
        guard lhs.clearDraft == rhs.clearDraft else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(linkPreviewOptions)
        hasher.combine(clearDraft)
    }
}

// MARK: - TDNativeInputMessageVenue + @retroactive Hashable

extension TDNativeInputMessageVenue: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.venue == rhs.venue else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(venue)
    }
}

// MARK: - TDNativeInputMessageVideo + @retroactive Hashable

extension TDNativeInputMessageVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia else { return false }
        guard lhs.selfDestructType == rhs.selfDestructType else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
        hasher.combine(selfDestructType)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativeInputMessageVideoNote + @retroactive Hashable

extension TDNativeInputMessageVideoNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.videoNote == rhs.videoNote else { return false }
        guard lhs.selfDestructType == rhs.selfDestructType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(videoNote)
        hasher.combine(selfDestructType)
    }
}

// MARK: - TDNativeInputMessageVoiceNote + @retroactive Hashable

extension TDNativeInputMessageVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.voiceNote == rhs.voiceNote else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.selfDestructType == rhs.selfDestructType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceNote)
        hasher.combine(caption)
        hasher.combine(selfDestructType)
    }
}

// MARK: - TDNativeInputPageBlock + @retroactive Hashable

extension TDNativeInputPageBlock: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inputPageBlockSectionHeading(let lhs), .inputPageBlockSectionHeading(let rhs)):
            lhs == rhs
        case (.inputPageBlockParagraph(let lhs), .inputPageBlockParagraph(let rhs)):
            lhs == rhs
        case (.inputPageBlockPreformatted(let lhs), .inputPageBlockPreformatted(let rhs)):
            lhs == rhs
        case (.inputPageBlockFooter(let lhs), .inputPageBlockFooter(let rhs)):
            lhs == rhs
        case (.inputPageBlockThinking(let lhs), .inputPageBlockThinking(let rhs)):
            lhs == rhs
        case (.inputPageBlockDivider, .inputPageBlockDivider):
            true
        case (.inputPageBlockMathematicalExpression(let lhs), .inputPageBlockMathematicalExpression(let rhs)):
            lhs == rhs
        case (.inputPageBlockAnchor(let lhs), .inputPageBlockAnchor(let rhs)):
            lhs == rhs
        case (.inputPageBlockList(let lhs), .inputPageBlockList(let rhs)):
            lhs == rhs
        case (.inputPageBlockBlockQuote(let lhs), .inputPageBlockBlockQuote(let rhs)):
            lhs == rhs
        case (.inputPageBlockExpandableBlockQuote(let lhs), .inputPageBlockExpandableBlockQuote(let rhs)):
            lhs == rhs
        case (.inputPageBlockPullQuote(let lhs), .inputPageBlockPullQuote(let rhs)):
            lhs == rhs
        case (.inputPageBlockAnimation(let lhs), .inputPageBlockAnimation(let rhs)):
            lhs == rhs
        case (.inputPageBlockAudio(let lhs), .inputPageBlockAudio(let rhs)):
            lhs == rhs
        case (.inputPageBlockDocument(let lhs), .inputPageBlockDocument(let rhs)):
            lhs == rhs
        case (.inputPageBlockPhoto(let lhs), .inputPageBlockPhoto(let rhs)):
            lhs == rhs
        case (.inputPageBlockVideo(let lhs), .inputPageBlockVideo(let rhs)):
            lhs == rhs
        case (.inputPageBlockVoiceNote(let lhs), .inputPageBlockVoiceNote(let rhs)):
            lhs == rhs
        case (.inputPageBlockCollage(let lhs), .inputPageBlockCollage(let rhs)):
            lhs == rhs
        case (.inputPageBlockSlideshow(let lhs), .inputPageBlockSlideshow(let rhs)):
            lhs == rhs
        case (.inputPageBlockTable(let lhs), .inputPageBlockTable(let rhs)):
            lhs == rhs
        case (.inputPageBlockDetails(let lhs), .inputPageBlockDetails(let rhs)):
            lhs == rhs
        case (.inputPageBlockMap(let lhs), .inputPageBlockMap(let rhs)):
            lhs == rhs
        case (.inputPageBlockButtonRow(let lhs), .inputPageBlockButtonRow(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .inputPageBlockSectionHeading(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .inputPageBlockParagraph(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .inputPageBlockPreformatted(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .inputPageBlockFooter(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .inputPageBlockThinking(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .inputPageBlockDivider:
            hasher.combine(5)
        case .inputPageBlockMathematicalExpression(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .inputPageBlockAnchor(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .inputPageBlockList(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .inputPageBlockBlockQuote(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .inputPageBlockExpandableBlockQuote(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .inputPageBlockPullQuote(let value):
            hasher.combine(11)
            hasher.combine(value)
        case .inputPageBlockAnimation(let value):
            hasher.combine(12)
            hasher.combine(value)
        case .inputPageBlockAudio(let value):
            hasher.combine(13)
            hasher.combine(value)
        case .inputPageBlockDocument(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .inputPageBlockPhoto(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .inputPageBlockVideo(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .inputPageBlockVoiceNote(let value):
            hasher.combine(17)
            hasher.combine(value)
        case .inputPageBlockCollage(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .inputPageBlockSlideshow(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .inputPageBlockTable(let value):
            hasher.combine(20)
            hasher.combine(value)
        case .inputPageBlockDetails(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .inputPageBlockMap(let value):
            hasher.combine(22)
            hasher.combine(value)
        case .inputPageBlockButtonRow(let value):
            hasher.combine(23)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInputPageBlockAnchor + @retroactive Hashable

extension TDNativeInputPageBlockAnchor: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - TDNativeInputPageBlockAnimation + @retroactive Hashable

extension TDNativeInputPageBlockAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animation == rhs.animation else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
        hasher.combine(caption)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativeInputPageBlockAudio + @retroactive Hashable

extension TDNativeInputPageBlockAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputPageBlockBlockQuote + @retroactive Hashable

extension TDNativeInputPageBlockBlockQuote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.credit == rhs.credit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(credit)
    }
}

// MARK: - TDNativeInputPageBlockButtonRow + @retroactive Hashable

extension TDNativeInputPageBlockButtonRow: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.buttons == rhs.buttons else { return false }
        guard lhs.align == rhs.align else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(buttons)
        hasher.combine(align)
    }
}

// MARK: - TDNativeInputPageBlockCollage + @retroactive Hashable

extension TDNativeInputPageBlockCollage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputPageBlockDetails + @retroactive Hashable

extension TDNativeInputPageBlockDetails: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.header == rhs.header else { return false }
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.isOpen == rhs.isOpen else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(header)
        hasher.combine(blocks)
        hasher.combine(isOpen)
    }
}

// MARK: - TDNativeInputPageBlockDocument + @retroactive Hashable

extension TDNativeInputPageBlockDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputPageBlockExpandableBlockQuote + @retroactive Hashable

extension TDNativeInputPageBlockExpandableBlockQuote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.credit == rhs.credit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(credit)
    }
}

// MARK: - TDNativeInputPageBlockFooter + @retroactive Hashable

extension TDNativeInputPageBlockFooter: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.footer == rhs.footer else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(footer)
    }
}

// MARK: - TDNativeInputPageBlockList + @retroactive Hashable

extension TDNativeInputPageBlockList: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.items == rhs.items else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(items)
    }
}

// MARK: - TDNativeInputPageBlockListItem + @retroactive Hashable

extension TDNativeInputPageBlockListItem: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.hasCheckbox == rhs.hasCheckbox else { return false }
        guard lhs.isChecked == rhs.isChecked else { return false }
        guard lhs.value == rhs.value else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(hasCheckbox)
        hasher.combine(isChecked)
        hasher.combine(value)
        hasher.combine(type)
    }
}

// MARK: - TDNativeInputPageBlockMap + @retroactive Hashable

extension TDNativeInputPageBlockMap: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        guard lhs.zoom == rhs.zoom else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(zoom)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputPageBlockMathematicalExpression + @retroactive Hashable

extension TDNativeInputPageBlockMathematicalExpression: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.expression == rhs.expression else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(expression)
    }
}

// MARK: - TDNativeInputPageBlockParagraph + @retroactive Hashable

extension TDNativeInputPageBlockParagraph: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeInputPageBlockPhoto + @retroactive Hashable

extension TDNativeInputPageBlockPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(caption)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativeInputPageBlockPreformatted + @retroactive Hashable

extension TDNativeInputPageBlockPreformatted: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.language == rhs.language else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(language)
    }
}

// MARK: - TDNativeInputPageBlockPullQuote + @retroactive Hashable

extension TDNativeInputPageBlockPullQuote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.credit == rhs.credit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(credit)
    }
}

// MARK: - TDNativeInputPageBlockSectionHeading + @retroactive Hashable

extension TDNativeInputPageBlockSectionHeading: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.size == rhs.size else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(size)
    }
}

// MARK: - TDNativeInputPageBlockSlideshow + @retroactive Hashable

extension TDNativeInputPageBlockSlideshow: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputPageBlockTable + @retroactive Hashable

extension TDNativeInputPageBlockTable: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.cells == rhs.cells else { return false }
        guard lhs.isBordered == rhs.isBordered else { return false }
        guard lhs.isStriped == rhs.isStriped else { return false }
        guard lhs.isCompact == rhs.isCompact else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(caption)
        hasher.combine(cells)
        hasher.combine(isBordered)
        hasher.combine(isStriped)
        hasher.combine(isCompact)
    }
}

// MARK: - TDNativeInputPageBlockThinking + @retroactive Hashable

extension TDNativeInputPageBlockThinking: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeInputPageBlockVideo + @retroactive Hashable

extension TDNativeInputPageBlockVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(caption)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativeInputPageBlockVoiceNote + @retroactive Hashable

extension TDNativeInputPageBlockVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.voiceNote == rhs.voiceNote else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceNote)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeInputPaidMedia + @retroactive Hashable

extension TDNativeInputPaidMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.media == rhs.media else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.addedStickerFileIds == rhs.addedStickerFileIds else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(media)
        hasher.combine(thumbnail)
        hasher.combine(addedStickerFileIds)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeInputPaidMediaType + @retroactive Hashable

extension TDNativeInputPaidMediaType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inputPaidMediaTypePhoto(let lhs), .inputPaidMediaTypePhoto(let rhs)):
            lhs == rhs
        case (.inputPaidMediaTypeVideo(let lhs), .inputPaidMediaTypeVideo(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .inputPaidMediaTypePhoto(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .inputPaidMediaTypeVideo(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInputPaidMediaTypePhoto + @retroactive Hashable

extension TDNativeInputPaidMediaTypePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
    }
}

// MARK: - TDNativeInputPaidMediaTypeVideo + @retroactive Hashable

extension TDNativeInputPaidMediaTypeVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.cover == rhs.cover else { return false }
        guard lhs.startTimestamp == rhs.startTimestamp else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.supportsStreaming == rhs.supportsStreaming else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cover)
        hasher.combine(startTimestamp)
        hasher.combine(duration)
        hasher.combine(supportsStreaming)
    }
}

// MARK: - TDNativeInputPhoto + @retroactive Hashable

extension TDNativeInputPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.video == rhs.video else { return false }
        guard lhs.addedStickerFileIds == rhs.addedStickerFileIds else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(thumbnail)
        hasher.combine(video)
        hasher.combine(addedStickerFileIds)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeInputPollMedia + @retroactive Hashable

extension TDNativeInputPollMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inputPollMediaAnimation(let lhs), .inputPollMediaAnimation(let rhs)):
            lhs == rhs
        case (.inputPollMediaAudio(let lhs), .inputPollMediaAudio(let rhs)):
            lhs == rhs
        case (.inputPollMediaDocument(let lhs), .inputPollMediaDocument(let rhs)):
            lhs == rhs
        case (.inputPollMediaLink(let lhs), .inputPollMediaLink(let rhs)):
            lhs == rhs
        case (.inputPollMediaLocation(let lhs), .inputPollMediaLocation(let rhs)):
            lhs == rhs
        case (.inputPollMediaPhoto(let lhs), .inputPollMediaPhoto(let rhs)):
            lhs == rhs
        case (.inputPollMediaSticker(let lhs), .inputPollMediaSticker(let rhs)):
            lhs == rhs
        case (.inputPollMediaVenue(let lhs), .inputPollMediaVenue(let rhs)):
            lhs == rhs
        case (.inputPollMediaVideo(let lhs), .inputPollMediaVideo(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .inputPollMediaAnimation(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .inputPollMediaAudio(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .inputPollMediaDocument(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .inputPollMediaLink(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .inputPollMediaLocation(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .inputPollMediaPhoto(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .inputPollMediaSticker(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .inputPollMediaVenue(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .inputPollMediaVideo(let value):
            hasher.combine(8)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInputPollMediaAnimation + @retroactive Hashable

extension TDNativeInputPollMediaAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animation == rhs.animation else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
    }
}

// MARK: - TDNativeInputPollMediaAudio + @retroactive Hashable

extension TDNativeInputPollMediaAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
    }
}

// MARK: - TDNativeInputPollMediaDocument + @retroactive Hashable

extension TDNativeInputPollMediaDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
    }
}

// MARK: - TDNativeInputPollMediaLink + @retroactive Hashable

extension TDNativeInputPollMediaLink: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - TDNativeInputPollMediaLocation + @retroactive Hashable

extension TDNativeInputPollMediaLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
    }
}

// MARK: - TDNativeInputPollMediaPhoto + @retroactive Hashable

extension TDNativeInputPollMediaPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeInputPollMediaSticker + @retroactive Hashable

extension TDNativeInputPollMediaSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeInputPollMediaVenue + @retroactive Hashable

extension TDNativeInputPollMediaVenue: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.venue == rhs.venue else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(venue)
    }
}

// MARK: - TDNativeInputPollMediaVideo + @retroactive Hashable

extension TDNativeInputPollMediaVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
    }
}

// MARK: - TDNativeInputPollOption + @retroactive Hashable

extension TDNativeInputPollOption: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.media == rhs.media else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(media)
    }
}

// MARK: - TDNativeInputPollType + @retroactive Hashable

extension TDNativeInputPollType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.inputPollTypeRegular(let lhs), .inputPollTypeRegular(let rhs)):
            lhs == rhs
        case (.inputPollTypeQuiz(let lhs), .inputPollTypeQuiz(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .inputPollTypeRegular(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .inputPollTypeQuiz(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInputPollTypeQuiz + @retroactive Hashable

extension TDNativeInputPollTypeQuiz: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.correctOptionIds == rhs.correctOptionIds else { return false }
        guard lhs.explanation == rhs.explanation else { return false }
        guard lhs.explanationMedia == rhs.explanationMedia else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(correctOptionIds)
        hasher.combine(explanation)
        hasher.combine(explanationMedia)
    }
}

// MARK: - TDNativeInputPollTypeRegular + @retroactive Hashable

extension TDNativeInputPollTypeRegular: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.allowAddingOptions == rhs.allowAddingOptions else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(allowAddingOptions)
    }
}

// MARK: - TDNativeInputRichMessage + @retroactive Hashable

extension TDNativeInputRichMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.source == rhs.source else { return false }
        guard lhs.isRtl == rhs.isRtl else { return false }
        guard lhs.detectAutomaticBlocks == rhs.detectAutomaticBlocks else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(isRtl)
        hasher.combine(detectAutomaticBlocks)
    }
}

// MARK: - TDNativeInputRichMessageMedia + @retroactive Hashable

extension TDNativeInputRichMessageMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.media == rhs.media else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(media)
    }
}

// MARK: - TDNativeInputSticker + @retroactive Hashable

extension TDNativeInputSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sticker == rhs.sticker else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
        hasher.combine(thumbnail)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeInputSuggestedPostInfo + @retroactive Hashable

extension TDNativeInputSuggestedPostInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.price == rhs.price else { return false }
        guard lhs.sendDate == rhs.sendDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(price)
        hasher.combine(sendDate)
    }
}

// MARK: - TDNativeInputThumbnail + @retroactive Hashable

extension TDNativeInputThumbnail: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(thumbnail)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeInputVideo + @retroactive Hashable

extension TDNativeInputVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.cover == rhs.cover else { return false }
        guard lhs.startTimestamp == rhs.startTimestamp else { return false }
        guard lhs.addedStickerFileIds == rhs.addedStickerFileIds else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        guard lhs.supportsStreaming == rhs.supportsStreaming else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(thumbnail)
        hasher.combine(cover)
        hasher.combine(startTimestamp)
        hasher.combine(addedStickerFileIds)
        hasher.combine(duration)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(supportsStreaming)
    }
}

// MARK: - TDNativeInputVideoNote + @retroactive Hashable

extension TDNativeInputVideoNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.videoNote == rhs.videoNote else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.length == rhs.length else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(videoNote)
        hasher.combine(thumbnail)
        hasher.combine(duration)
        hasher.combine(length)
    }
}

// MARK: - TDNativeInputVoiceNote + @retroactive Hashable

extension TDNativeInputVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.voiceNote == rhs.voiceNote else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.waveform == rhs.waveform else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceNote)
        hasher.combine(duration)
        hasher.combine(waveform)
    }
}

// MARK: - TDNativeInternalLinkType + @retroactive Hashable

extension TDNativeInternalLinkType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.internalLinkTypeAttachmentMenuBot(let lhs), .internalLinkTypeAttachmentMenuBot(let rhs)):
            lhs == rhs
        case (.internalLinkTypeAuthenticationCode(let lhs), .internalLinkTypeAuthenticationCode(let rhs)):
            lhs == rhs
        case (.internalLinkTypeBackground(let lhs), .internalLinkTypeBackground(let rhs)):
            lhs == rhs
        case (.internalLinkTypeBotAddToChannel(let lhs), .internalLinkTypeBotAddToChannel(let rhs)):
            lhs == rhs
        case (.internalLinkTypeBotStart(let lhs), .internalLinkTypeBotStart(let rhs)):
            lhs == rhs
        case (.internalLinkTypeBotStartInGroup(let lhs), .internalLinkTypeBotStartInGroup(let rhs)):
            lhs == rhs
        case (.internalLinkTypeBusinessChat(let lhs), .internalLinkTypeBusinessChat(let rhs)):
            lhs == rhs
        case (.internalLinkTypeCallsPage(let lhs), .internalLinkTypeCallsPage(let rhs)):
            lhs == rhs
        case (.internalLinkTypeChatAffiliateProgram(let lhs), .internalLinkTypeChatAffiliateProgram(let rhs)):
            lhs == rhs
        case (.internalLinkTypeChatBoost(let lhs), .internalLinkTypeChatBoost(let rhs)):
            lhs == rhs
        case (.internalLinkTypeChatFolderInvite(let lhs), .internalLinkTypeChatFolderInvite(let rhs)):
            lhs == rhs
        case (.internalLinkTypeChatInvite(let lhs), .internalLinkTypeChatInvite(let rhs)):
            lhs == rhs
        case (.internalLinkTypeChatSelection, .internalLinkTypeChatSelection):
            true
        case (.internalLinkTypeContactsPage(let lhs), .internalLinkTypeContactsPage(let rhs)):
            lhs == rhs
        case (.internalLinkTypeDirectMessagesChat(let lhs), .internalLinkTypeDirectMessagesChat(let rhs)):
            lhs == rhs
        case (.internalLinkTypeGame(let lhs), .internalLinkTypeGame(let rhs)):
            lhs == rhs
        case (.internalLinkTypeGiftAuction(let lhs), .internalLinkTypeGiftAuction(let rhs)):
            lhs == rhs
        case (.internalLinkTypeGiftCollection(let lhs), .internalLinkTypeGiftCollection(let rhs)):
            lhs == rhs
        case (.internalLinkTypeGroupCall(let lhs), .internalLinkTypeGroupCall(let rhs)):
            lhs == rhs
        case (.internalLinkTypeInstantView(let lhs), .internalLinkTypeInstantView(let rhs)):
            lhs == rhs
        case (.internalLinkTypeInvoice(let lhs), .internalLinkTypeInvoice(let rhs)):
            lhs == rhs
        case (.internalLinkTypeLanguagePack(let lhs), .internalLinkTypeLanguagePack(let rhs)):
            lhs == rhs
        case (.internalLinkTypeLiveStory(let lhs), .internalLinkTypeLiveStory(let rhs)):
            lhs == rhs
        case (.internalLinkTypeMainWebApp(let lhs), .internalLinkTypeMainWebApp(let rhs)):
            lhs == rhs
        case (.internalLinkTypeMessage(let lhs), .internalLinkTypeMessage(let rhs)):
            lhs == rhs
        case (.internalLinkTypeMessageDraft(let lhs), .internalLinkTypeMessageDraft(let rhs)):
            lhs == rhs
        case (.internalLinkTypeMyProfilePage(let lhs), .internalLinkTypeMyProfilePage(let rhs)):
            lhs == rhs
        case (.internalLinkTypeNewChannelChat, .internalLinkTypeNewChannelChat):
            true
        case (.internalLinkTypeNewGroupChat, .internalLinkTypeNewGroupChat):
            true
        case (.internalLinkTypeNewPrivateChat, .internalLinkTypeNewPrivateChat):
            true
        case (.internalLinkTypeNewStory(let lhs), .internalLinkTypeNewStory(let rhs)):
            lhs == rhs
        case (.internalLinkTypeOauth(let lhs), .internalLinkTypeOauth(let rhs)):
            lhs == rhs
        case (.internalLinkTypePassportDataRequest(let lhs), .internalLinkTypePassportDataRequest(let rhs)):
            lhs == rhs
        case (.internalLinkTypePhoneNumberConfirmation(let lhs), .internalLinkTypePhoneNumberConfirmation(let rhs)):
            lhs == rhs
        case (.internalLinkTypePremiumFeaturesPage(let lhs), .internalLinkTypePremiumFeaturesPage(let rhs)):
            lhs == rhs
        case (.internalLinkTypePremiumGiftCode(let lhs), .internalLinkTypePremiumGiftCode(let rhs)):
            lhs == rhs
        case (.internalLinkTypePremiumGiftPurchase(let lhs), .internalLinkTypePremiumGiftPurchase(let rhs)):
            lhs == rhs
        case (.internalLinkTypeProxy(let lhs), .internalLinkTypeProxy(let rhs)):
            lhs == rhs
        case (.internalLinkTypePublicChat(let lhs), .internalLinkTypePublicChat(let rhs)):
            lhs == rhs
        case (.internalLinkTypeQrCodeAuthentication, .internalLinkTypeQrCodeAuthentication):
            true
        case (.internalLinkTypeRequestManagedBot(let lhs), .internalLinkTypeRequestManagedBot(let rhs)):
            lhs == rhs
        case (.internalLinkTypeRestorePurchases, .internalLinkTypeRestorePurchases):
            true
        case (.internalLinkTypeSavedMessages, .internalLinkTypeSavedMessages):
            true
        case (.internalLinkTypeSearch, .internalLinkTypeSearch):
            true
        case (.internalLinkTypeSettings(let lhs), .internalLinkTypeSettings(let rhs)):
            lhs == rhs
        case (.internalLinkTypeStarPurchase(let lhs), .internalLinkTypeStarPurchase(let rhs)):
            lhs == rhs
        case (.internalLinkTypeStickerSet(let lhs), .internalLinkTypeStickerSet(let rhs)):
            lhs == rhs
        case (.internalLinkTypeStory(let lhs), .internalLinkTypeStory(let rhs)):
            lhs == rhs
        case (.internalLinkTypeStoryAlbum(let lhs), .internalLinkTypeStoryAlbum(let rhs)):
            lhs == rhs
        case (.internalLinkTypeTextCompositionStyle(let lhs), .internalLinkTypeTextCompositionStyle(let rhs)):
            lhs == rhs
        case (.internalLinkTypeTheme(let lhs), .internalLinkTypeTheme(let rhs)):
            lhs == rhs
        case (.internalLinkTypeUnknownDeepLink(let lhs), .internalLinkTypeUnknownDeepLink(let rhs)):
            lhs == rhs
        case (.internalLinkTypeUpgradedGift(let lhs), .internalLinkTypeUpgradedGift(let rhs)):
            lhs == rhs
        case (.internalLinkTypeUserPhoneNumber(let lhs), .internalLinkTypeUserPhoneNumber(let rhs)):
            lhs == rhs
        case (.internalLinkTypeUserToken(let lhs), .internalLinkTypeUserToken(let rhs)):
            lhs == rhs
        case (.internalLinkTypeVideoChat(let lhs), .internalLinkTypeVideoChat(let rhs)):
            lhs == rhs
        case (.internalLinkTypeWebApp(let lhs), .internalLinkTypeWebApp(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .internalLinkTypeAttachmentMenuBot(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .internalLinkTypeAuthenticationCode(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .internalLinkTypeBackground(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .internalLinkTypeBotAddToChannel(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .internalLinkTypeBotStart(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .internalLinkTypeBotStartInGroup(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .internalLinkTypeBusinessChat(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .internalLinkTypeCallsPage(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .internalLinkTypeChatAffiliateProgram(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .internalLinkTypeChatBoost(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .internalLinkTypeChatFolderInvite(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .internalLinkTypeChatInvite(let value):
            hasher.combine(11)
            hasher.combine(value)
        case .internalLinkTypeChatSelection:
            hasher.combine(12)
        case .internalLinkTypeContactsPage(let value):
            hasher.combine(13)
            hasher.combine(value)
        case .internalLinkTypeDirectMessagesChat(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .internalLinkTypeGame(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .internalLinkTypeGiftAuction(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .internalLinkTypeGiftCollection(let value):
            hasher.combine(17)
            hasher.combine(value)
        case .internalLinkTypeGroupCall(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .internalLinkTypeInstantView(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .internalLinkTypeInvoice(let value):
            hasher.combine(20)
            hasher.combine(value)
        case .internalLinkTypeLanguagePack(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .internalLinkTypeLiveStory(let value):
            hasher.combine(22)
            hasher.combine(value)
        case .internalLinkTypeMainWebApp(let value):
            hasher.combine(23)
            hasher.combine(value)
        case .internalLinkTypeMessage(let value):
            hasher.combine(24)
            hasher.combine(value)
        case .internalLinkTypeMessageDraft(let value):
            hasher.combine(25)
            hasher.combine(value)
        case .internalLinkTypeMyProfilePage(let value):
            hasher.combine(26)
            hasher.combine(value)
        case .internalLinkTypeNewChannelChat:
            hasher.combine(27)
        case .internalLinkTypeNewGroupChat:
            hasher.combine(28)
        case .internalLinkTypeNewPrivateChat:
            hasher.combine(29)
        case .internalLinkTypeNewStory(let value):
            hasher.combine(30)
            hasher.combine(value)
        case .internalLinkTypeOauth(let value):
            hasher.combine(31)
            hasher.combine(value)
        case .internalLinkTypePassportDataRequest(let value):
            hasher.combine(32)
            hasher.combine(value)
        case .internalLinkTypePhoneNumberConfirmation(let value):
            hasher.combine(33)
            hasher.combine(value)
        case .internalLinkTypePremiumFeaturesPage(let value):
            hasher.combine(34)
            hasher.combine(value)
        case .internalLinkTypePremiumGiftCode(let value):
            hasher.combine(35)
            hasher.combine(value)
        case .internalLinkTypePremiumGiftPurchase(let value):
            hasher.combine(36)
            hasher.combine(value)
        case .internalLinkTypeProxy(let value):
            hasher.combine(37)
            hasher.combine(value)
        case .internalLinkTypePublicChat(let value):
            hasher.combine(38)
            hasher.combine(value)
        case .internalLinkTypeQrCodeAuthentication:
            hasher.combine(39)
        case .internalLinkTypeRequestManagedBot(let value):
            hasher.combine(40)
            hasher.combine(value)
        case .internalLinkTypeRestorePurchases:
            hasher.combine(41)
        case .internalLinkTypeSavedMessages:
            hasher.combine(42)
        case .internalLinkTypeSearch:
            hasher.combine(43)
        case .internalLinkTypeSettings(let value):
            hasher.combine(44)
            hasher.combine(value)
        case .internalLinkTypeStarPurchase(let value):
            hasher.combine(45)
            hasher.combine(value)
        case .internalLinkTypeStickerSet(let value):
            hasher.combine(46)
            hasher.combine(value)
        case .internalLinkTypeStory(let value):
            hasher.combine(47)
            hasher.combine(value)
        case .internalLinkTypeStoryAlbum(let value):
            hasher.combine(48)
            hasher.combine(value)
        case .internalLinkTypeTextCompositionStyle(let value):
            hasher.combine(49)
            hasher.combine(value)
        case .internalLinkTypeTheme(let value):
            hasher.combine(50)
            hasher.combine(value)
        case .internalLinkTypeUnknownDeepLink(let value):
            hasher.combine(51)
            hasher.combine(value)
        case .internalLinkTypeUpgradedGift(let value):
            hasher.combine(52)
            hasher.combine(value)
        case .internalLinkTypeUserPhoneNumber(let value):
            hasher.combine(53)
            hasher.combine(value)
        case .internalLinkTypeUserToken(let value):
            hasher.combine(54)
            hasher.combine(value)
        case .internalLinkTypeVideoChat(let value):
            hasher.combine(55)
            hasher.combine(value)
        case .internalLinkTypeWebApp(let value):
            hasher.combine(56)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInternalLinkTypeAttachmentMenuBot + @retroactive Hashable

extension TDNativeInternalLinkTypeAttachmentMenuBot: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.targetChat == rhs.targetChat else { return false }
        guard lhs.botUsername == rhs.botUsername else { return false }
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(targetChat)
        hasher.combine(botUsername)
        hasher.combine(url)
    }
}

// MARK: - TDNativeInternalLinkTypeAuthenticationCode + @retroactive Hashable

extension TDNativeInternalLinkTypeAuthenticationCode: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.code == rhs.code else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
}

// MARK: - TDNativeInternalLinkTypeBackground + @retroactive Hashable

extension TDNativeInternalLinkTypeBackground: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.backgroundName == rhs.backgroundName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(backgroundName)
    }
}

// MARK: - TDNativeInternalLinkTypeBotAddToChannel + @retroactive Hashable

extension TDNativeInternalLinkTypeBotAddToChannel: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUsername == rhs.botUsername else { return false }
        guard lhs.administratorRights == rhs.administratorRights else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUsername)
        hasher.combine(administratorRights)
    }
}

// MARK: - TDNativeInternalLinkTypeBotStart + @retroactive Hashable

extension TDNativeInternalLinkTypeBotStart: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUsername == rhs.botUsername else { return false }
        guard lhs.startParameter == rhs.startParameter else { return false }
        guard lhs.autostart == rhs.autostart else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUsername)
        hasher.combine(startParameter)
        hasher.combine(autostart)
    }
}

// MARK: - TDNativeInternalLinkTypeBotStartInGroup + @retroactive Hashable

extension TDNativeInternalLinkTypeBotStartInGroup: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUsername == rhs.botUsername else { return false }
        guard lhs.startParameter == rhs.startParameter else { return false }
        guard lhs.administratorRights == rhs.administratorRights else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUsername)
        hasher.combine(startParameter)
        hasher.combine(administratorRights)
    }
}

// MARK: - TDNativeInternalLinkTypeBusinessChat + @retroactive Hashable

extension TDNativeInternalLinkTypeBusinessChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.linkName == rhs.linkName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(linkName)
    }
}

// MARK: - TDNativeInternalLinkTypeCallsPage + @retroactive Hashable

extension TDNativeInternalLinkTypeCallsPage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.section == rhs.section else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(section)
    }
}

// MARK: - TDNativeInternalLinkTypeChatAffiliateProgram + @retroactive Hashable

extension TDNativeInternalLinkTypeChatAffiliateProgram: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.username == rhs.username else { return false }
        guard lhs.referrer == rhs.referrer else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(username)
        hasher.combine(referrer)
    }
}

// MARK: - TDNativeInternalLinkTypeChatBoost + @retroactive Hashable

extension TDNativeInternalLinkTypeChatBoost: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - TDNativeInternalLinkTypeChatFolderInvite + @retroactive Hashable

extension TDNativeInternalLinkTypeChatFolderInvite: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.inviteLink == rhs.inviteLink else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(inviteLink)
    }
}

// MARK: - TDNativeInternalLinkTypeChatInvite + @retroactive Hashable

extension TDNativeInternalLinkTypeChatInvite: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.inviteLink == rhs.inviteLink else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(inviteLink)
    }
}

// MARK: - TDNativeInternalLinkTypeContactsPage + @retroactive Hashable

extension TDNativeInternalLinkTypeContactsPage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.section == rhs.section else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(section)
    }
}

// MARK: - TDNativeInternalLinkTypeDirectMessagesChat + @retroactive Hashable

extension TDNativeInternalLinkTypeDirectMessagesChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.channelUsername == rhs.channelUsername else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(channelUsername)
    }
}

// MARK: - TDNativeInternalLinkTypeGame + @retroactive Hashable

extension TDNativeInternalLinkTypeGame: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUsername == rhs.botUsername else { return false }
        guard lhs.gameShortName == rhs.gameShortName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUsername)
        hasher.combine(gameShortName)
    }
}

// MARK: - TDNativeInternalLinkTypeGiftAuction + @retroactive Hashable

extension TDNativeInternalLinkTypeGiftAuction: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.auctionId == rhs.auctionId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(auctionId)
    }
}

// MARK: - TDNativeInternalLinkTypeGiftCollection + @retroactive Hashable

extension TDNativeInternalLinkTypeGiftCollection: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.giftOwnerUsername == rhs.giftOwnerUsername else { return false }
        guard lhs.collectionId == rhs.collectionId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(giftOwnerUsername)
        hasher.combine(collectionId)
    }
}

// MARK: - TDNativeInternalLinkTypeGroupCall + @retroactive Hashable

extension TDNativeInternalLinkTypeGroupCall: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.inviteLink == rhs.inviteLink else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(inviteLink)
    }
}

// MARK: - TDNativeInternalLinkTypeInstantView + @retroactive Hashable

extension TDNativeInternalLinkTypeInstantView: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.fallbackUrl == rhs.fallbackUrl else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(fallbackUrl)
    }
}

// MARK: - TDNativeInternalLinkTypeInvoice + @retroactive Hashable

extension TDNativeInternalLinkTypeInvoice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.invoiceName == rhs.invoiceName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(invoiceName)
    }
}

// MARK: - TDNativeInternalLinkTypeLanguagePack + @retroactive Hashable

extension TDNativeInternalLinkTypeLanguagePack: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.languagePackId == rhs.languagePackId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(languagePackId)
    }
}

// MARK: - TDNativeInternalLinkTypeLiveStory + @retroactive Hashable

extension TDNativeInternalLinkTypeLiveStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyPosterUsername == rhs.storyPosterUsername else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyPosterUsername)
    }
}

// MARK: - TDNativeInternalLinkTypeMainWebApp + @retroactive Hashable

extension TDNativeInternalLinkTypeMainWebApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUsername == rhs.botUsername else { return false }
        guard lhs.startParameter == rhs.startParameter else { return false }
        guard lhs.mode == rhs.mode else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUsername)
        hasher.combine(startParameter)
        hasher.combine(mode)
    }
}

// MARK: - TDNativeInternalLinkTypeMessage + @retroactive Hashable

extension TDNativeInternalLinkTypeMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - TDNativeInternalLinkTypeMessageDraft + @retroactive Hashable

extension TDNativeInternalLinkTypeMessageDraft: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.containsLink == rhs.containsLink else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(containsLink)
    }
}

// MARK: - TDNativeInternalLinkTypeMyProfilePage + @retroactive Hashable

extension TDNativeInternalLinkTypeMyProfilePage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.section == rhs.section else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(section)
    }
}

// MARK: - TDNativeInternalLinkTypeNewStory + @retroactive Hashable

extension TDNativeInternalLinkTypeNewStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.contentType == rhs.contentType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(contentType)
    }
}

// MARK: - TDNativeInternalLinkTypeOauth + @retroactive Hashable

extension TDNativeInternalLinkTypeOauth: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - TDNativeInternalLinkTypePassportDataRequest + @retroactive Hashable

extension TDNativeInternalLinkTypePassportDataRequest: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUserId == rhs.botUserId else { return false }
        guard lhs.scope == rhs.scope else { return false }
        guard lhs.publicKey == rhs.publicKey else { return false }
        guard lhs.nonce == rhs.nonce else { return false }
        guard lhs.callbackUrl == rhs.callbackUrl else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUserId)
        hasher.combine(scope)
        hasher.combine(publicKey)
        hasher.combine(nonce)
        hasher.combine(callbackUrl)
    }
}

// MARK: - TDNativeInternalLinkTypePhoneNumberConfirmation + @retroactive Hashable

extension TDNativeInternalLinkTypePhoneNumberConfirmation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.hash == rhs.hash else { return false }
        guard lhs.phoneNumber == rhs.phoneNumber else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
        hasher.combine(phoneNumber)
    }
}

// MARK: - TDNativeInternalLinkTypePremiumFeaturesPage + @retroactive Hashable

extension TDNativeInternalLinkTypePremiumFeaturesPage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.referrer == rhs.referrer else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(referrer)
    }
}

// MARK: - TDNativeInternalLinkTypePremiumGiftCode + @retroactive Hashable

extension TDNativeInternalLinkTypePremiumGiftCode: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.code == rhs.code else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
}

// MARK: - TDNativeInternalLinkTypePremiumGiftPurchase + @retroactive Hashable

extension TDNativeInternalLinkTypePremiumGiftPurchase: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.referrer == rhs.referrer else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(referrer)
    }
}

// MARK: - TDNativeInternalLinkTypeProxy + @retroactive Hashable

extension TDNativeInternalLinkTypeProxy: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.proxy == rhs.proxy else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(proxy)
    }
}

// MARK: - TDNativeInternalLinkTypePublicChat + @retroactive Hashable

extension TDNativeInternalLinkTypePublicChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatUsername == rhs.chatUsername else { return false }
        guard lhs.draftText == rhs.draftText else { return false }
        guard lhs.openProfile == rhs.openProfile else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatUsername)
        hasher.combine(draftText)
        hasher.combine(openProfile)
    }
}

// MARK: - TDNativeInternalLinkTypeRequestManagedBot + @retroactive Hashable

extension TDNativeInternalLinkTypeRequestManagedBot: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.managerBotUsername == rhs.managerBotUsername else { return false }
        guard lhs.suggestedBotUsername == rhs.suggestedBotUsername else { return false }
        guard lhs.suggestedBotName == rhs.suggestedBotName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(managerBotUsername)
        hasher.combine(suggestedBotUsername)
        hasher.combine(suggestedBotName)
    }
}

// MARK: - TDNativeInternalLinkTypeSettings + @retroactive Hashable

extension TDNativeInternalLinkTypeSettings: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.section == rhs.section else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(section)
    }
}

// MARK: - TDNativeInternalLinkTypeStarPurchase + @retroactive Hashable

extension TDNativeInternalLinkTypeStarPurchase: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.purpose == rhs.purpose else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
        hasher.combine(purpose)
    }
}

// MARK: - TDNativeInternalLinkTypeStickerSet + @retroactive Hashable

extension TDNativeInternalLinkTypeStickerSet: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.stickerSetName == rhs.stickerSetName else { return false }
        guard lhs.expectCustomEmoji == rhs.expectCustomEmoji else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stickerSetName)
        hasher.combine(expectCustomEmoji)
    }
}

// MARK: - TDNativeInternalLinkTypeStory + @retroactive Hashable

extension TDNativeInternalLinkTypeStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyPosterUsername == rhs.storyPosterUsername else { return false }
        guard lhs.storyId == rhs.storyId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyPosterUsername)
        hasher.combine(storyId)
    }
}

// MARK: - TDNativeInternalLinkTypeStoryAlbum + @retroactive Hashable

extension TDNativeInternalLinkTypeStoryAlbum: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyAlbumOwnerUsername == rhs.storyAlbumOwnerUsername else { return false }
        guard lhs.storyAlbumId == rhs.storyAlbumId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyAlbumOwnerUsername)
        hasher.combine(storyAlbumId)
    }
}

// MARK: - TDNativeInternalLinkTypeTextCompositionStyle + @retroactive Hashable

extension TDNativeInternalLinkTypeTextCompositionStyle: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.styleName == rhs.styleName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(styleName)
    }
}

// MARK: - TDNativeInternalLinkTypeTheme + @retroactive Hashable

extension TDNativeInternalLinkTypeTheme: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.themeName == rhs.themeName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(themeName)
    }
}

// MARK: - TDNativeInternalLinkTypeUnknownDeepLink + @retroactive Hashable

extension TDNativeInternalLinkTypeUnknownDeepLink: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.link == rhs.link else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(link)
    }
}

// MARK: - TDNativeInternalLinkTypeUpgradedGift + @retroactive Hashable

extension TDNativeInternalLinkTypeUpgradedGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - TDNativeInternalLinkTypeUserPhoneNumber + @retroactive Hashable

extension TDNativeInternalLinkTypeUserPhoneNumber: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.phoneNumber == rhs.phoneNumber else { return false }
        guard lhs.draftText == rhs.draftText else { return false }
        guard lhs.openProfile == rhs.openProfile else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(phoneNumber)
        hasher.combine(draftText)
        hasher.combine(openProfile)
    }
}

// MARK: - TDNativeInternalLinkTypeUserToken + @retroactive Hashable

extension TDNativeInternalLinkTypeUserToken: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.token == rhs.token else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(token)
    }
}

// MARK: - TDNativeInternalLinkTypeVideoChat + @retroactive Hashable

extension TDNativeInternalLinkTypeVideoChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatUsername == rhs.chatUsername else { return false }
        guard lhs.inviteHash == rhs.inviteHash else { return false }
        guard lhs.isLiveStream == rhs.isLiveStream else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatUsername)
        hasher.combine(inviteHash)
        hasher.combine(isLiveStream)
    }
}

// MARK: - TDNativeInternalLinkTypeWebApp + @retroactive Hashable

extension TDNativeInternalLinkTypeWebApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUsername == rhs.botUsername else { return false }
        guard lhs.webAppShortName == rhs.webAppShortName else { return false }
        guard lhs.startParameter == rhs.startParameter else { return false }
        guard lhs.mode == rhs.mode else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUsername)
        hasher.combine(webAppShortName)
        hasher.combine(startParameter)
        hasher.combine(mode)
    }
}

// MARK: - TDNativeInvoice + @retroactive Hashable

extension TDNativeInvoice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.priceParts == rhs.priceParts else { return false }
        guard lhs.subscriptionPeriod == rhs.subscriptionPeriod else { return false }
        guard lhs.maxTipAmount == rhs.maxTipAmount else { return false }
        guard lhs.suggestedTipAmounts == rhs.suggestedTipAmounts else { return false }
        guard lhs.recurringPaymentTermsOfServiceUrl == rhs.recurringPaymentTermsOfServiceUrl else { return false }
        guard lhs.termsOfServiceUrl == rhs.termsOfServiceUrl else { return false }
        guard lhs.isTest == rhs.isTest else { return false }
        guard lhs.needName == rhs.needName else { return false }
        guard lhs.needPhoneNumber == rhs.needPhoneNumber else { return false }
        guard lhs.needEmailAddress == rhs.needEmailAddress else { return false }
        guard lhs.needShippingAddress == rhs.needShippingAddress else { return false }
        guard lhs.sendPhoneNumberToProvider == rhs.sendPhoneNumberToProvider else { return false }
        guard lhs.sendEmailAddressToProvider == rhs.sendEmailAddressToProvider else { return false }
        guard lhs.isFlexible == rhs.isFlexible else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(currency)
        hasher.combine(priceParts)
        hasher.combine(subscriptionPeriod)
        hasher.combine(maxTipAmount)
        hasher.combine(suggestedTipAmounts)
        hasher.combine(recurringPaymentTermsOfServiceUrl)
        hasher.combine(termsOfServiceUrl)
        hasher.combine(isTest)
        hasher.combine(needName)
        hasher.combine(needPhoneNumber)
        hasher.combine(needEmailAddress)
        hasher.combine(needShippingAddress)
        hasher.combine(sendPhoneNumberToProvider)
        hasher.combine(sendEmailAddressToProvider)
        hasher.combine(isFlexible)
    }
}

// MARK: - TDNativeKeyboardButton + @retroactive Hashable

extension TDNativeKeyboardButton: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.iconCustomEmojiId == rhs.iconCustomEmojiId else { return false }
        guard lhs.style == rhs.style else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(iconCustomEmojiId)
        hasher.combine(style)
        hasher.combine(type)
    }
}

// MARK: - TDNativeKeyboardButtonType + @retroactive Hashable

extension TDNativeKeyboardButtonType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.keyboardButtonTypeText, .keyboardButtonTypeText):
            true
        case (.keyboardButtonTypeRequestPhoneNumber, .keyboardButtonTypeRequestPhoneNumber):
            true
        case (.keyboardButtonTypeRequestLocation, .keyboardButtonTypeRequestLocation):
            true
        case (.keyboardButtonTypeRequestPoll(let lhs), .keyboardButtonTypeRequestPoll(let rhs)):
            lhs == rhs
        case (.keyboardButtonTypeRequestUsers(let lhs), .keyboardButtonTypeRequestUsers(let rhs)):
            lhs == rhs
        case (.keyboardButtonTypeRequestChat(let lhs), .keyboardButtonTypeRequestChat(let rhs)):
            lhs == rhs
        case (.keyboardButtonTypeRequestManagedBot(let lhs), .keyboardButtonTypeRequestManagedBot(let rhs)):
            lhs == rhs
        case (.keyboardButtonTypeWebApp(let lhs), .keyboardButtonTypeWebApp(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .keyboardButtonTypeText:
            hasher.combine(0)
        case .keyboardButtonTypeRequestPhoneNumber:
            hasher.combine(1)
        case .keyboardButtonTypeRequestLocation:
            hasher.combine(2)
        case .keyboardButtonTypeRequestPoll(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .keyboardButtonTypeRequestUsers(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .keyboardButtonTypeRequestChat(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .keyboardButtonTypeRequestManagedBot(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .keyboardButtonTypeWebApp(let value):
            hasher.combine(7)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeKeyboardButtonTypeRequestChat + @retroactive Hashable

extension TDNativeKeyboardButtonTypeRequestChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.chatIsChannel == rhs.chatIsChannel else { return false }
        guard lhs.restrictChatIsForum == rhs.restrictChatIsForum else { return false }
        guard lhs.chatIsForum == rhs.chatIsForum else { return false }
        guard lhs.restrictChatHasUsername == rhs.restrictChatHasUsername else { return false }
        guard lhs.chatHasUsername == rhs.chatHasUsername else { return false }
        guard lhs.chatIsCreated == rhs.chatIsCreated else { return false }
        guard lhs.userAdministratorRights == rhs.userAdministratorRights else { return false }
        guard lhs.botAdministratorRights == rhs.botAdministratorRights else { return false }
        guard lhs.botIsMember == rhs.botIsMember else { return false }
        guard lhs.requestTitle == rhs.requestTitle else { return false }
        guard lhs.requestUsername == rhs.requestUsername else { return false }
        guard lhs.requestPhoto == rhs.requestPhoto else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(chatIsChannel)
        hasher.combine(restrictChatIsForum)
        hasher.combine(chatIsForum)
        hasher.combine(restrictChatHasUsername)
        hasher.combine(chatHasUsername)
        hasher.combine(chatIsCreated)
        hasher.combine(userAdministratorRights)
        hasher.combine(botAdministratorRights)
        hasher.combine(botIsMember)
        hasher.combine(requestTitle)
        hasher.combine(requestUsername)
        hasher.combine(requestPhoto)
    }
}

// MARK: - TDNativeKeyboardButtonTypeRequestManagedBot + @retroactive Hashable

extension TDNativeKeyboardButtonTypeRequestManagedBot: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.suggestedName == rhs.suggestedName else { return false }
        guard lhs.suggestedUsername == rhs.suggestedUsername else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(suggestedName)
        hasher.combine(suggestedUsername)
    }
}

// MARK: - TDNativeKeyboardButtonTypeRequestPoll + @retroactive Hashable

extension TDNativeKeyboardButtonTypeRequestPoll: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.forceRegular == rhs.forceRegular else { return false }
        guard lhs.forceQuiz == rhs.forceQuiz else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(forceRegular)
        hasher.combine(forceQuiz)
    }
}

// MARK: - TDNativeKeyboardButtonTypeRequestUsers + @retroactive Hashable

extension TDNativeKeyboardButtonTypeRequestUsers: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.restrictUserIsBot == rhs.restrictUserIsBot else { return false }
        guard lhs.userIsBot == rhs.userIsBot else { return false }
        guard lhs.restrictUserIsPremium == rhs.restrictUserIsPremium else { return false }
        guard lhs.userIsPremium == rhs.userIsPremium else { return false }
        guard lhs.maxQuantity == rhs.maxQuantity else { return false }
        guard lhs.requestName == rhs.requestName else { return false }
        guard lhs.requestUsername == rhs.requestUsername else { return false }
        guard lhs.requestPhoto == rhs.requestPhoto else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(restrictUserIsBot)
        hasher.combine(userIsBot)
        hasher.combine(restrictUserIsPremium)
        hasher.combine(userIsPremium)
        hasher.combine(maxQuantity)
        hasher.combine(requestName)
        hasher.combine(requestUsername)
        hasher.combine(requestPhoto)
    }
}

// MARK: - TDNativeKeyboardButtonTypeWebApp + @retroactive Hashable

extension TDNativeKeyboardButtonTypeWebApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - TDNativeLabeledPricePart + @retroactive Hashable

extension TDNativeLabeledPricePart: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.label == rhs.label else { return false }
        guard lhs.amount == rhs.amount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(amount)
    }
}

// MARK: - TDNativeLinkPreview + @retroactive Hashable

extension TDNativeLinkPreview: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.displayUrl == rhs.displayUrl else { return false }
        guard lhs.siteName == rhs.siteName else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.author == rhs.author else { return false }
        guard lhs.type == rhs.type else { return false }
        guard lhs.hasLargeMedia == rhs.hasLargeMedia else { return false }
        guard lhs.showLargeMedia == rhs.showLargeMedia else { return false }
        guard lhs.showMediaAboveDescription == rhs.showMediaAboveDescription else { return false }
        guard lhs.skipConfirmation == rhs.skipConfirmation else { return false }
        guard lhs.showAboveText == rhs.showAboveText else { return false }
        guard lhs.instantViewVersion == rhs.instantViewVersion else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(displayUrl)
        hasher.combine(siteName)
        hasher.combine(title)
        hasher.combine(description)
        hasher.combine(author)
        hasher.combine(type)
        hasher.combine(hasLargeMedia)
        hasher.combine(showLargeMedia)
        hasher.combine(showMediaAboveDescription)
        hasher.combine(skipConfirmation)
        hasher.combine(showAboveText)
        hasher.combine(instantViewVersion)
    }
}

// MARK: - TDNativeLinkPreviewAlbumMedia + @retroactive Hashable

extension TDNativeLinkPreviewAlbumMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.linkPreviewAlbumMediaPhoto(let lhs), .linkPreviewAlbumMediaPhoto(let rhs)):
            lhs == rhs
        case (.linkPreviewAlbumMediaVideo(let lhs), .linkPreviewAlbumMediaVideo(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .linkPreviewAlbumMediaPhoto(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .linkPreviewAlbumMediaVideo(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeLinkPreviewAlbumMediaPhoto + @retroactive Hashable

extension TDNativeLinkPreviewAlbumMediaPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLinkPreviewAlbumMediaVideo + @retroactive Hashable

extension TDNativeLinkPreviewAlbumMediaVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
    }
}

// MARK: - TDNativeLinkPreviewOptions + @retroactive Hashable

extension TDNativeLinkPreviewOptions: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isDisabled == rhs.isDisabled else { return false }
        guard lhs.url == rhs.url else { return false }
        guard lhs.forceSmallMedia == rhs.forceSmallMedia else { return false }
        guard lhs.forceLargeMedia == rhs.forceLargeMedia else { return false }
        guard lhs.showAboveText == rhs.showAboveText else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isDisabled)
        hasher.combine(url)
        hasher.combine(forceSmallMedia)
        hasher.combine(forceLargeMedia)
        hasher.combine(showAboveText)
    }
}

// MARK: - TDNativeLinkPreviewType + @retroactive Hashable

extension TDNativeLinkPreviewType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.linkPreviewTypeAlbum(let lhs), .linkPreviewTypeAlbum(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeAnimation(let lhs), .linkPreviewTypeAnimation(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeApp(let lhs), .linkPreviewTypeApp(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeArticle(let lhs), .linkPreviewTypeArticle(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeAudio(let lhs), .linkPreviewTypeAudio(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeBackground(let lhs), .linkPreviewTypeBackground(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeChannelBoost(let lhs), .linkPreviewTypeChannelBoost(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeChat(let lhs), .linkPreviewTypeChat(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeDirectMessagesChat(let lhs), .linkPreviewTypeDirectMessagesChat(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeDocument(let lhs), .linkPreviewTypeDocument(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeEmbeddedAnimationPlayer(let lhs), .linkPreviewTypeEmbeddedAnimationPlayer(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeEmbeddedAudioPlayer(let lhs), .linkPreviewTypeEmbeddedAudioPlayer(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeEmbeddedVideoPlayer(let lhs), .linkPreviewTypeEmbeddedVideoPlayer(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeExternalAudio(let lhs), .linkPreviewTypeExternalAudio(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeExternalVideo(let lhs), .linkPreviewTypeExternalVideo(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeGiftAuction(let lhs), .linkPreviewTypeGiftAuction(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeGiftCollection(let lhs), .linkPreviewTypeGiftCollection(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeGroupCall, .linkPreviewTypeGroupCall):
            true
        case (.linkPreviewTypeInvoice, .linkPreviewTypeInvoice):
            true
        case (.linkPreviewTypeLiveStory(let lhs), .linkPreviewTypeLiveStory(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeMessage, .linkPreviewTypeMessage):
            true
        case (.linkPreviewTypePhoto(let lhs), .linkPreviewTypePhoto(let rhs)):
            lhs == rhs
        case (.linkPreviewTypePremiumGiftCode, .linkPreviewTypePremiumGiftCode):
            true
        case (.linkPreviewTypeRequestManagedBot, .linkPreviewTypeRequestManagedBot):
            true
        case (.linkPreviewTypeShareableChatFolder, .linkPreviewTypeShareableChatFolder):
            true
        case (.linkPreviewTypeSticker(let lhs), .linkPreviewTypeSticker(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeStickerSet(let lhs), .linkPreviewTypeStickerSet(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeStory(let lhs), .linkPreviewTypeStory(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeStoryAlbum(let lhs), .linkPreviewTypeStoryAlbum(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeSupergroupBoost(let lhs), .linkPreviewTypeSupergroupBoost(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeTextCompositionStyle(let lhs), .linkPreviewTypeTextCompositionStyle(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeTheme(let lhs), .linkPreviewTypeTheme(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeUnsupported, .linkPreviewTypeUnsupported):
            true
        case (.linkPreviewTypeUpgradedGift(let lhs), .linkPreviewTypeUpgradedGift(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeUser(let lhs), .linkPreviewTypeUser(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeVideo(let lhs), .linkPreviewTypeVideo(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeVideoChat(let lhs), .linkPreviewTypeVideoChat(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeVideoNote(let lhs), .linkPreviewTypeVideoNote(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeVoiceNote(let lhs), .linkPreviewTypeVoiceNote(let rhs)):
            lhs == rhs
        case (.linkPreviewTypeWebApp(let lhs), .linkPreviewTypeWebApp(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .linkPreviewTypeAlbum(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .linkPreviewTypeAnimation(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .linkPreviewTypeApp(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .linkPreviewTypeArticle(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .linkPreviewTypeAudio(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .linkPreviewTypeBackground(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .linkPreviewTypeChannelBoost(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .linkPreviewTypeChat(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .linkPreviewTypeDirectMessagesChat(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .linkPreviewTypeDocument(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .linkPreviewTypeEmbeddedAnimationPlayer(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .linkPreviewTypeEmbeddedAudioPlayer(let value):
            hasher.combine(11)
            hasher.combine(value)
        case .linkPreviewTypeEmbeddedVideoPlayer(let value):
            hasher.combine(12)
            hasher.combine(value)
        case .linkPreviewTypeExternalAudio(let value):
            hasher.combine(13)
            hasher.combine(value)
        case .linkPreviewTypeExternalVideo(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .linkPreviewTypeGiftAuction(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .linkPreviewTypeGiftCollection(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .linkPreviewTypeGroupCall:
            hasher.combine(17)
        case .linkPreviewTypeInvoice:
            hasher.combine(18)
        case .linkPreviewTypeLiveStory(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .linkPreviewTypeMessage:
            hasher.combine(20)
        case .linkPreviewTypePhoto(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .linkPreviewTypePremiumGiftCode:
            hasher.combine(22)
        case .linkPreviewTypeRequestManagedBot:
            hasher.combine(23)
        case .linkPreviewTypeShareableChatFolder:
            hasher.combine(24)
        case .linkPreviewTypeSticker(let value):
            hasher.combine(25)
            hasher.combine(value)
        case .linkPreviewTypeStickerSet(let value):
            hasher.combine(26)
            hasher.combine(value)
        case .linkPreviewTypeStory(let value):
            hasher.combine(27)
            hasher.combine(value)
        case .linkPreviewTypeStoryAlbum(let value):
            hasher.combine(28)
            hasher.combine(value)
        case .linkPreviewTypeSupergroupBoost(let value):
            hasher.combine(29)
            hasher.combine(value)
        case .linkPreviewTypeTextCompositionStyle(let value):
            hasher.combine(30)
            hasher.combine(value)
        case .linkPreviewTypeTheme(let value):
            hasher.combine(31)
            hasher.combine(value)
        case .linkPreviewTypeUnsupported:
            hasher.combine(32)
        case .linkPreviewTypeUpgradedGift(let value):
            hasher.combine(33)
            hasher.combine(value)
        case .linkPreviewTypeUser(let value):
            hasher.combine(34)
            hasher.combine(value)
        case .linkPreviewTypeVideo(let value):
            hasher.combine(35)
            hasher.combine(value)
        case .linkPreviewTypeVideoChat(let value):
            hasher.combine(36)
            hasher.combine(value)
        case .linkPreviewTypeVideoNote(let value):
            hasher.combine(37)
            hasher.combine(value)
        case .linkPreviewTypeVoiceNote(let value):
            hasher.combine(38)
            hasher.combine(value)
        case .linkPreviewTypeWebApp(let value):
            hasher.combine(39)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeLinkPreviewTypeAlbum + @retroactive Hashable

extension TDNativeLinkPreviewTypeAlbum: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.media == rhs.media else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(media)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeLinkPreviewTypeAnimation + @retroactive Hashable

extension TDNativeLinkPreviewTypeAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animation == rhs.animation else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
    }
}

// MARK: - TDNativeLinkPreviewTypeApp + @retroactive Hashable

extension TDNativeLinkPreviewTypeApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLinkPreviewTypeArticle + @retroactive Hashable

extension TDNativeLinkPreviewTypeArticle: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLinkPreviewTypeAudio + @retroactive Hashable

extension TDNativeLinkPreviewTypeAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
    }
}

// MARK: - TDNativeLinkPreviewTypeBackground + @retroactive Hashable

extension TDNativeLinkPreviewTypeBackground: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        guard lhs.backgroundType == rhs.backgroundType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
        hasher.combine(backgroundType)
    }
}

// MARK: - TDNativeLinkPreviewTypeChannelBoost + @retroactive Hashable

extension TDNativeLinkPreviewTypeChannelBoost: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLinkPreviewTypeChat + @retroactive Hashable

extension TDNativeLinkPreviewTypeChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.createsJoinRequest == rhs.createsJoinRequest else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(photo)
        hasher.combine(createsJoinRequest)
    }
}

// MARK: - TDNativeLinkPreviewTypeDirectMessagesChat + @retroactive Hashable

extension TDNativeLinkPreviewTypeDirectMessagesChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLinkPreviewTypeDocument + @retroactive Hashable

extension TDNativeLinkPreviewTypeDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
    }
}

// MARK: - TDNativeLinkPreviewTypeEmbeddedAnimationPlayer + @retroactive Hashable

extension TDNativeLinkPreviewTypeEmbeddedAnimationPlayer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.animation == rhs.animation else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(animation)
        hasher.combine(thumbnail)
        hasher.combine(duration)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeLinkPreviewTypeEmbeddedAudioPlayer + @retroactive Hashable

extension TDNativeLinkPreviewTypeEmbeddedAudioPlayer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.audio == rhs.audio else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(audio)
        hasher.combine(thumbnail)
        hasher.combine(duration)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeLinkPreviewTypeEmbeddedVideoPlayer + @retroactive Hashable

extension TDNativeLinkPreviewTypeEmbeddedVideoPlayer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.video == rhs.video else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(video)
        hasher.combine(thumbnail)
        hasher.combine(duration)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeLinkPreviewTypeExternalAudio + @retroactive Hashable

extension TDNativeLinkPreviewTypeExternalAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.mimeType == rhs.mimeType else { return false }
        guard lhs.duration == rhs.duration else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(mimeType)
        hasher.combine(duration)
    }
}

// MARK: - TDNativeLinkPreviewTypeExternalVideo + @retroactive Hashable

extension TDNativeLinkPreviewTypeExternalVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.mimeType == rhs.mimeType else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        guard lhs.duration == rhs.duration else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(mimeType)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(duration)
    }
}

// MARK: - TDNativeLinkPreviewTypeGiftAuction + @retroactive Hashable

extension TDNativeLinkPreviewTypeGiftAuction: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        guard lhs.auctionEndDate == rhs.auctionEndDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
        hasher.combine(auctionEndDate)
    }
}

// MARK: - TDNativeLinkPreviewTypeGiftCollection + @retroactive Hashable

extension TDNativeLinkPreviewTypeGiftCollection: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.icons == rhs.icons else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(icons)
    }
}

// MARK: - TDNativeLinkPreviewTypeLiveStory + @retroactive Hashable

extension TDNativeLinkPreviewTypeLiveStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyPosterChatId == rhs.storyPosterChatId else { return false }
        guard lhs.storyId == rhs.storyId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyPosterChatId)
        hasher.combine(storyId)
    }
}

// MARK: - TDNativeLinkPreviewTypePhoto + @retroactive Hashable

extension TDNativeLinkPreviewTypePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLinkPreviewTypeSticker + @retroactive Hashable

extension TDNativeLinkPreviewTypeSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeLinkPreviewTypeStickerSet + @retroactive Hashable

extension TDNativeLinkPreviewTypeStickerSet: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.stickers == rhs.stickers else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stickers)
    }
}

// MARK: - TDNativeLinkPreviewTypeStory + @retroactive Hashable

extension TDNativeLinkPreviewTypeStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyPosterChatId == rhs.storyPosterChatId else { return false }
        guard lhs.storyId == rhs.storyId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyPosterChatId)
        hasher.combine(storyId)
    }
}

// MARK: - TDNativeLinkPreviewTypeStoryAlbum + @retroactive Hashable

extension TDNativeLinkPreviewTypeStoryAlbum: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photoIcon == rhs.photoIcon else { return false }
        guard lhs.videoIcon == rhs.videoIcon else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photoIcon)
        hasher.combine(videoIcon)
    }
}

// MARK: - TDNativeLinkPreviewTypeSupergroupBoost + @retroactive Hashable

extension TDNativeLinkPreviewTypeSupergroupBoost: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLinkPreviewTypeTextCompositionStyle + @retroactive Hashable

extension TDNativeLinkPreviewTypeTextCompositionStyle: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.customEmojiId == rhs.customEmojiId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(customEmojiId)
    }
}

// MARK: - TDNativeLinkPreviewTypeTheme + @retroactive Hashable

extension TDNativeLinkPreviewTypeTheme: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.documents == rhs.documents else { return false }
        guard lhs.settings == rhs.settings else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(documents)
        hasher.combine(settings)
    }
}

// MARK: - TDNativeLinkPreviewTypeUpgradedGift + @retroactive Hashable

extension TDNativeLinkPreviewTypeUpgradedGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
    }
}

// MARK: - TDNativeLinkPreviewTypeUser + @retroactive Hashable

extension TDNativeLinkPreviewTypeUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.isBot == rhs.isBot else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(isBot)
    }
}

// MARK: - TDNativeLinkPreviewTypeVideo + @retroactive Hashable

extension TDNativeLinkPreviewTypeVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        guard lhs.cover == rhs.cover else { return false }
        guard lhs.startTimestamp == rhs.startTimestamp else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(cover)
        hasher.combine(startTimestamp)
    }
}

// MARK: - TDNativeLinkPreviewTypeVideoChat + @retroactive Hashable

extension TDNativeLinkPreviewTypeVideoChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.isLiveStream == rhs.isLiveStream else { return false }
        guard lhs.joinsAsSpeaker == rhs.joinsAsSpeaker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(isLiveStream)
        hasher.combine(joinsAsSpeaker)
    }
}

// MARK: - TDNativeLinkPreviewTypeVideoNote + @retroactive Hashable

extension TDNativeLinkPreviewTypeVideoNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.videoNote == rhs.videoNote else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(videoNote)
    }
}

// MARK: - TDNativeLinkPreviewTypeVoiceNote + @retroactive Hashable

extension TDNativeLinkPreviewTypeVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.voiceNote == rhs.voiceNote else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceNote)
    }
}

// MARK: - TDNativeLinkPreviewTypeWebApp + @retroactive Hashable

extension TDNativeLinkPreviewTypeWebApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeLiveLocation + @retroactive Hashable

extension TDNativeLiveLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        guard lhs.livePeriod == rhs.livePeriod else { return false }
        guard lhs.heading == rhs.heading else { return false }
        guard lhs.proximityAlertRadius == rhs.proximityAlertRadius else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(livePeriod)
        hasher.combine(heading)
        hasher.combine(proximityAlertRadius)
    }
}

// MARK: - TDNativeLocation + @retroactive Hashable

extension TDNativeLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.latitude == rhs.latitude else { return false }
        guard lhs.longitude == rhs.longitude else { return false }
        guard lhs.horizontalAccuracy == rhs.horizontalAccuracy else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
        hasher.combine(horizontalAccuracy)
    }
}

// MARK: - TDNativeMessage + @retroactive Hashable

extension TDNativeMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.senderId == rhs.senderId else { return false }
        guard lhs.receiverId == rhs.receiverId else { return false }
        guard lhs.chatId == rhs.chatId else { return false }
        guard lhs.sendingState == rhs.sendingState else { return false }
        guard lhs.schedulingState == rhs.schedulingState else { return false }
        guard lhs.isOutgoing == rhs.isOutgoing else { return false }
        guard lhs.isPinned == rhs.isPinned else { return false }
        guard lhs.isFromOffline == rhs.isFromOffline else { return false }
        guard lhs.canBeSaved == rhs.canBeSaved else { return false }
        guard lhs.hasTimestampedMedia == rhs.hasTimestampedMedia else { return false }
        guard lhs.isChannelPost == rhs.isChannelPost else { return false }
        guard lhs.isPaidStarSuggestedPost == rhs.isPaidStarSuggestedPost else { return false }
        guard lhs.isPaidGramSuggestedPost == rhs.isPaidGramSuggestedPost else { return false }
        guard lhs.containsUnreadMention == rhs.containsUnreadMention else { return false }
        guard lhs.containsUnreadPollVotes == rhs.containsUnreadPollVotes else { return false }
        guard lhs.date == rhs.date else { return false }
        guard lhs.editDate == rhs.editDate else { return false }
        guard lhs.forwardInfo == rhs.forwardInfo else { return false }
        guard lhs.importInfo == rhs.importInfo else { return false }
        guard lhs.interactionInfo == rhs.interactionInfo else { return false }
        guard lhs.unreadReactions == rhs.unreadReactions else { return false }
        guard lhs.factCheck == rhs.factCheck else { return false }
        guard lhs.suggestedPostInfo == rhs.suggestedPostInfo else { return false }
        guard lhs.replyTo == rhs.replyTo else { return false }
        guard lhs.topicId == rhs.topicId else { return false }
        guard lhs.selfDestructType == rhs.selfDestructType else { return false }
        guard lhs.selfDestructIn == rhs.selfDestructIn else { return false }
        guard lhs.autoDeleteIn == rhs.autoDeleteIn else { return false }
        guard lhs.viaBotUserId == rhs.viaBotUserId else { return false }
        guard lhs.guestBotCallerId == rhs.guestBotCallerId else { return false }
        guard lhs.senderBusinessBotUserId == rhs.senderBusinessBotUserId else { return false }
        guard lhs.senderBoostCount == rhs.senderBoostCount else { return false }
        guard lhs.senderTag == rhs.senderTag else { return false }
        guard lhs.paidMessageStarCount == rhs.paidMessageStarCount else { return false }
        guard lhs.authorSignature == rhs.authorSignature else { return false }
        guard lhs.mediaAlbumId == rhs.mediaAlbumId else { return false }
        guard lhs.effectId == rhs.effectId else { return false }
        guard lhs.restrictionInfo == rhs.restrictionInfo else { return false }
        guard lhs.summaryLanguageCode == rhs.summaryLanguageCode else { return false }
        guard lhs.content == rhs.content else { return false }
        guard lhs.ephemeralContent == rhs.ephemeralContent else { return false }
        guard lhs.replyMarkup == rhs.replyMarkup else { return false }
        guard lhs.ephemeralMessageId == rhs.ephemeralMessageId else { return false }
        guard lhs.chatInstance == rhs.chatInstance else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(senderId)
        hasher.combine(receiverId)
        hasher.combine(chatId)
        hasher.combine(sendingState)
        hasher.combine(schedulingState)
        hasher.combine(isOutgoing)
        hasher.combine(isPinned)
        hasher.combine(isFromOffline)
        hasher.combine(canBeSaved)
        hasher.combine(hasTimestampedMedia)
        hasher.combine(isChannelPost)
        hasher.combine(isPaidStarSuggestedPost)
        hasher.combine(isPaidGramSuggestedPost)
        hasher.combine(containsUnreadMention)
        hasher.combine(containsUnreadPollVotes)
        hasher.combine(date)
        hasher.combine(editDate)
        hasher.combine(forwardInfo)
        hasher.combine(importInfo)
        hasher.combine(interactionInfo)
        hasher.combine(unreadReactions)
        hasher.combine(factCheck)
        hasher.combine(suggestedPostInfo)
        hasher.combine(replyTo)
        hasher.combine(topicId)
        hasher.combine(selfDestructType)
        hasher.combine(selfDestructIn)
        hasher.combine(autoDeleteIn)
        hasher.combine(viaBotUserId)
        hasher.combine(guestBotCallerId)
        hasher.combine(senderBusinessBotUserId)
        hasher.combine(senderBoostCount)
        hasher.combine(senderTag)
        hasher.combine(paidMessageStarCount)
        hasher.combine(authorSignature)
        hasher.combine(mediaAlbumId)
        hasher.combine(effectId)
        hasher.combine(restrictionInfo)
        hasher.combine(summaryLanguageCode)
        hasher.combine(content)
        hasher.combine(ephemeralContent)
        hasher.combine(replyMarkup)
        hasher.combine(ephemeralMessageId)
        hasher.combine(chatInstance)
    }
}

// MARK: - TDNativeMessageAnimatedEmoji + @retroactive Hashable

extension TDNativeMessageAnimatedEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animatedEmoji == rhs.animatedEmoji else { return false }
        guard lhs.emoji == rhs.emoji else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animatedEmoji)
        hasher.combine(emoji)
    }
}

// MARK: - TDNativeMessageAudio + @retroactive Hashable

extension TDNativeMessageAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeMessageBasicGroupChatCreate + @retroactive Hashable

extension TDNativeMessageBasicGroupChatCreate: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        guard lhs.memberUserIds == rhs.memberUserIds else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(memberUserIds)
    }
}

// MARK: - TDNativeMessageBotWriteAccessAllowed + @retroactive Hashable

extension TDNativeMessageBotWriteAccessAllowed: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.reason == rhs.reason else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reason)
    }
}

// MARK: - TDNativeMessageCall + @retroactive Hashable

extension TDNativeMessageCall: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.uniqueId == rhs.uniqueId else { return false }
        guard lhs.isVideo == rhs.isVideo else { return false }
        guard lhs.discardReason == rhs.discardReason else { return false }
        guard lhs.duration == rhs.duration else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueId)
        hasher.combine(isVideo)
        hasher.combine(discardReason)
        hasher.combine(duration)
    }
}

// MARK: - TDNativeMessageChatAddMembers + @retroactive Hashable

extension TDNativeMessageChatAddMembers: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.memberUserIds == rhs.memberUserIds else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(memberUserIds)
    }
}

// MARK: - TDNativeMessageChatAddedToCommunity + @retroactive Hashable

extension TDNativeMessageChatAddedToCommunity: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.communityId == rhs.communityId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(communityId)
    }
}

// MARK: - TDNativeMessageChatBoost + @retroactive Hashable

extension TDNativeMessageChatBoost: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.boostCount == rhs.boostCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(boostCount)
    }
}

// MARK: - TDNativeMessageChatChangePhoto + @retroactive Hashable

extension TDNativeMessageChatChangePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeMessageChatChangeTitle + @retroactive Hashable

extension TDNativeMessageChatChangeTitle: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }
}

// MARK: - TDNativeMessageChatDeleteMember + @retroactive Hashable

extension TDNativeMessageChatDeleteMember: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.userId == rhs.userId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }
}

// MARK: - TDNativeMessageChatHasProtectedContentDisableRequested + @retroactive Hashable

extension TDNativeMessageChatHasProtectedContentDisableRequested: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isExpired == rhs.isExpired else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isExpired)
    }
}

// MARK: - TDNativeMessageChatHasProtectedContentToggled + @retroactive Hashable

extension TDNativeMessageChatHasProtectedContentToggled: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.requestMessageId == rhs.requestMessageId else { return false }
        guard lhs.oldHasProtectedContent == rhs.oldHasProtectedContent else { return false }
        guard lhs.newHasProtectedContent == rhs.newHasProtectedContent else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(requestMessageId)
        hasher.combine(oldHasProtectedContent)
        hasher.combine(newHasProtectedContent)
    }
}

// MARK: - TDNativeMessageChatJoinFromCommunity + @retroactive Hashable

extension TDNativeMessageChatJoinFromCommunity: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.communityId == rhs.communityId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(communityId)
    }
}

// MARK: - TDNativeMessageChatOwnerChanged + @retroactive Hashable

extension TDNativeMessageChatOwnerChanged: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.newOwnerUserId == rhs.newOwnerUserId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(newOwnerUserId)
    }
}

// MARK: - TDNativeMessageChatOwnerLeft + @retroactive Hashable

extension TDNativeMessageChatOwnerLeft: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.newOwnerUserId == rhs.newOwnerUserId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(newOwnerUserId)
    }
}

// MARK: - TDNativeMessageChatSetBackground + @retroactive Hashable

extension TDNativeMessageChatSetBackground: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.oldBackgroundMessageId == rhs.oldBackgroundMessageId else { return false }
        guard lhs.background == rhs.background else { return false }
        guard lhs.onlyForSelf == rhs.onlyForSelf else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(oldBackgroundMessageId)
        hasher.combine(background)
        hasher.combine(onlyForSelf)
    }
}

// MARK: - TDNativeMessageChatSetMessageAutoDeleteTime + @retroactive Hashable

extension TDNativeMessageChatSetMessageAutoDeleteTime: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.messageAutoDeleteTime == rhs.messageAutoDeleteTime else { return false }
        guard lhs.fromUserId == rhs.fromUserId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(messageAutoDeleteTime)
        hasher.combine(fromUserId)
    }
}

// MARK: - TDNativeMessageChatSetTheme + @retroactive Hashable

extension TDNativeMessageChatSetTheme: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.theme == rhs.theme else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(theme)
    }
}

// MARK: - TDNativeMessageChatShared + @retroactive Hashable

extension TDNativeMessageChatShared: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chat == rhs.chat else { return false }
        guard lhs.buttonId == rhs.buttonId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chat)
        hasher.combine(buttonId)
    }
}

// MARK: - TDNativeMessageChatUpgradeFrom + @retroactive Hashable

extension TDNativeMessageChatUpgradeFrom: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        guard lhs.basicGroupId == rhs.basicGroupId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(basicGroupId)
    }
}

// MARK: - TDNativeMessageChatUpgradeTo + @retroactive Hashable

extension TDNativeMessageChatUpgradeTo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.supergroupId == rhs.supergroupId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(supergroupId)
    }
}

// MARK: - TDNativeMessageChecklist + @retroactive Hashable

extension TDNativeMessageChecklist: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.list == rhs.list else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(list)
    }
}

// MARK: - TDNativeMessageChecklistTasksAdded + @retroactive Hashable

extension TDNativeMessageChecklistTasksAdded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.checklistMessageId == rhs.checklistMessageId else { return false }
        guard lhs.tasks == rhs.tasks else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(checklistMessageId)
        hasher.combine(tasks)
    }
}

// MARK: - TDNativeMessageChecklistTasksDone + @retroactive Hashable

extension TDNativeMessageChecklistTasksDone: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.checklistMessageId == rhs.checklistMessageId else { return false }
        guard lhs.markedAsDoneTaskIds == rhs.markedAsDoneTaskIds else { return false }
        guard lhs.markedAsNotDoneTaskIds == rhs.markedAsNotDoneTaskIds else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(checklistMessageId)
        hasher.combine(markedAsDoneTaskIds)
        hasher.combine(markedAsNotDoneTaskIds)
    }
}

// MARK: - TDNativeMessageContact + @retroactive Hashable

extension TDNativeMessageContact: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.contact == rhs.contact else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(contact)
    }
}

// MARK: - TDNativeMessageContent + @retroactive Hashable

extension TDNativeMessageContent: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.messageText(let lhs), .messageText(let rhs)):
            lhs == rhs
        case (.messageRichMessage(let lhs), .messageRichMessage(let rhs)):
            lhs == rhs
        case (.messageAnimation(let lhs), .messageAnimation(let rhs)):
            lhs == rhs
        case (.messageAudio(let lhs), .messageAudio(let rhs)):
            lhs == rhs
        case (.messageDocument(let lhs), .messageDocument(let rhs)):
            lhs == rhs
        case (.messagePaidMedia(let lhs), .messagePaidMedia(let rhs)):
            lhs == rhs
        case (.messagePhoto(let lhs), .messagePhoto(let rhs)):
            lhs == rhs
        case (.messageSticker(let lhs), .messageSticker(let rhs)):
            lhs == rhs
        case (.messageVideo(let lhs), .messageVideo(let rhs)):
            lhs == rhs
        case (.messageVideoNote(let lhs), .messageVideoNote(let rhs)):
            lhs == rhs
        case (.messageVoiceNote(let lhs), .messageVoiceNote(let rhs)):
            lhs == rhs
        case (.messageExpiredPhoto, .messageExpiredPhoto):
            true
        case (.messageExpiredVideo, .messageExpiredVideo):
            true
        case (.messageExpiredVideoNote, .messageExpiredVideoNote):
            true
        case (.messageExpiredVoiceNote, .messageExpiredVoiceNote):
            true
        case (.messageLiveLocation(let lhs), .messageLiveLocation(let rhs)):
            lhs == rhs
        case (.messageLocation(let lhs), .messageLocation(let rhs)):
            lhs == rhs
        case (.messageVenue(let lhs), .messageVenue(let rhs)):
            lhs == rhs
        case (.messageContact(let lhs), .messageContact(let rhs)):
            lhs == rhs
        case (.messageAnimatedEmoji(let lhs), .messageAnimatedEmoji(let rhs)):
            lhs == rhs
        case (.messageDice(let lhs), .messageDice(let rhs)):
            lhs == rhs
        case (.messageGame(let lhs), .messageGame(let rhs)):
            lhs == rhs
        case (.messagePoll(let lhs), .messagePoll(let rhs)):
            lhs == rhs
        case (.messageStakeDice(let lhs), .messageStakeDice(let rhs)):
            lhs == rhs
        case (.messageStory(let lhs), .messageStory(let rhs)):
            lhs == rhs
        case (.messageChecklist(let lhs), .messageChecklist(let rhs)):
            lhs == rhs
        case (.messageInvoice(let lhs), .messageInvoice(let rhs)):
            lhs == rhs
        case (.messageCall(let lhs), .messageCall(let rhs)):
            lhs == rhs
        case (.messageGroupCall(let lhs), .messageGroupCall(let rhs)):
            lhs == rhs
        case (.messageVideoChatScheduled(let lhs), .messageVideoChatScheduled(let rhs)):
            lhs == rhs
        case (.messageVideoChatStarted(let lhs), .messageVideoChatStarted(let rhs)):
            lhs == rhs
        case (.messageVideoChatEnded(let lhs), .messageVideoChatEnded(let rhs)):
            lhs == rhs
        case (.messageInviteVideoChatParticipants(let lhs), .messageInviteVideoChatParticipants(let rhs)):
            lhs == rhs
        case (.messagePollOptionAdded(let lhs), .messagePollOptionAdded(let rhs)):
            lhs == rhs
        case (.messagePollOptionDeleted(let lhs), .messagePollOptionDeleted(let rhs)):
            lhs == rhs
        case (.messageBasicGroupChatCreate(let lhs), .messageBasicGroupChatCreate(let rhs)):
            lhs == rhs
        case (.messageSupergroupChatCreate(let lhs), .messageSupergroupChatCreate(let rhs)):
            lhs == rhs
        case (.messageChatChangeTitle(let lhs), .messageChatChangeTitle(let rhs)):
            lhs == rhs
        case (.messageChatChangePhoto(let lhs), .messageChatChangePhoto(let rhs)):
            lhs == rhs
        case (.messageChatDeletePhoto, .messageChatDeletePhoto):
            true
        case (.messageChatOwnerLeft(let lhs), .messageChatOwnerLeft(let rhs)):
            lhs == rhs
        case (.messageChatOwnerChanged(let lhs), .messageChatOwnerChanged(let rhs)):
            lhs == rhs
        case (.messageChatHasProtectedContentToggled(let lhs), .messageChatHasProtectedContentToggled(let rhs)):
            lhs == rhs
        case (
            .messageChatHasProtectedContentDisableRequested(let lhs),
            .messageChatHasProtectedContentDisableRequested(let rhs),
        ):
            lhs == rhs
        case (.messageChatAddMembers(let lhs), .messageChatAddMembers(let rhs)):
            lhs == rhs
        case (.messageChatJoinByLink, .messageChatJoinByLink):
            true
        case (.messageChatJoinByRequest, .messageChatJoinByRequest):
            true
        case (.messageChatJoinFromCommunity(let lhs), .messageChatJoinFromCommunity(let rhs)):
            lhs == rhs
        case (.messageChatDeleteMember(let lhs), .messageChatDeleteMember(let rhs)):
            lhs == rhs
        case (.messageChatAddedToCommunity(let lhs), .messageChatAddedToCommunity(let rhs)):
            lhs == rhs
        case (.messageChatRemovedFromCommunity, .messageChatRemovedFromCommunity):
            true
        case (.messageChatUpgradeTo(let lhs), .messageChatUpgradeTo(let rhs)):
            lhs == rhs
        case (.messageChatUpgradeFrom(let lhs), .messageChatUpgradeFrom(let rhs)):
            lhs == rhs
        case (.messagePinMessage(let lhs), .messagePinMessage(let rhs)):
            lhs == rhs
        case (.messageScreenshotTaken, .messageScreenshotTaken):
            true
        case (.messageChatSetBackground(let lhs), .messageChatSetBackground(let rhs)):
            lhs == rhs
        case (.messageChatSetTheme(let lhs), .messageChatSetTheme(let rhs)):
            lhs == rhs
        case (.messageChatSetMessageAutoDeleteTime(let lhs), .messageChatSetMessageAutoDeleteTime(let rhs)):
            lhs == rhs
        case (.messageChatBoost(let lhs), .messageChatBoost(let rhs)):
            lhs == rhs
        case (.messageForumTopicCreated(let lhs), .messageForumTopicCreated(let rhs)):
            lhs == rhs
        case (.messageForumTopicEdited(let lhs), .messageForumTopicEdited(let rhs)):
            lhs == rhs
        case (.messageForumTopicIsClosedToggled(let lhs), .messageForumTopicIsClosedToggled(let rhs)):
            lhs == rhs
        case (.messageForumTopicIsHiddenToggled(let lhs), .messageForumTopicIsHiddenToggled(let rhs)):
            lhs == rhs
        case (.messageSuggestProfilePhoto(let lhs), .messageSuggestProfilePhoto(let rhs)):
            lhs == rhs
        case (.messageSuggestBirthdate(let lhs), .messageSuggestBirthdate(let rhs)):
            lhs == rhs
        case (.messageCustomServiceAction(let lhs), .messageCustomServiceAction(let rhs)):
            lhs == rhs
        case (.messageGameScore(let lhs), .messageGameScore(let rhs)):
            lhs == rhs
        case (.messageManagedBotCreated(let lhs), .messageManagedBotCreated(let rhs)):
            lhs == rhs
        case (.messagePaymentSuccessful(let lhs), .messagePaymentSuccessful(let rhs)):
            lhs == rhs
        case (.messagePaymentSuccessfulBot(let lhs), .messagePaymentSuccessfulBot(let rhs)):
            lhs == rhs
        case (.messagePaymentRefunded(let lhs), .messagePaymentRefunded(let rhs)):
            lhs == rhs
        case (.messageGiftedPremium(let lhs), .messageGiftedPremium(let rhs)):
            lhs == rhs
        case (.messagePremiumGiftCode(let lhs), .messagePremiumGiftCode(let rhs)):
            lhs == rhs
        case (.messageGiveawayCreated(let lhs), .messageGiveawayCreated(let rhs)):
            lhs == rhs
        case (.messageGiveaway(let lhs), .messageGiveaway(let rhs)):
            lhs == rhs
        case (.messageGiveawayCompleted(let lhs), .messageGiveawayCompleted(let rhs)):
            lhs == rhs
        case (.messageGiveawayWinners(let lhs), .messageGiveawayWinners(let rhs)):
            lhs == rhs
        case (.messageGiftedStars(let lhs), .messageGiftedStars(let rhs)):
            lhs == rhs
        case (.messageGiftedGrams(let lhs), .messageGiftedGrams(let rhs)):
            lhs == rhs
        case (.messageGiveawayPrizeStars(let lhs), .messageGiveawayPrizeStars(let rhs)):
            lhs == rhs
        case (.messageGift(let lhs), .messageGift(let rhs)):
            lhs == rhs
        case (.messageUpgradedGift(let lhs), .messageUpgradedGift(let rhs)):
            lhs == rhs
        case (.messageRefundedUpgradedGift(let lhs), .messageRefundedUpgradedGift(let rhs)):
            lhs == rhs
        case (.messageUpgradedGiftPurchaseOffer(let lhs), .messageUpgradedGiftPurchaseOffer(let rhs)):
            lhs == rhs
        case (.messageUpgradedGiftPurchaseOfferRejected(let lhs), .messageUpgradedGiftPurchaseOfferRejected(let rhs)):
            lhs == rhs
        case (.messagePaidMessagesRefunded(let lhs), .messagePaidMessagesRefunded(let rhs)):
            lhs == rhs
        case (.messagePaidMessagePriceChanged(let lhs), .messagePaidMessagePriceChanged(let rhs)):
            lhs == rhs
        case (.messageDirectMessagePriceChanged(let lhs), .messageDirectMessagePriceChanged(let rhs)):
            lhs == rhs
        case (.messageChecklistTasksDone(let lhs), .messageChecklistTasksDone(let rhs)):
            lhs == rhs
        case (.messageChecklistTasksAdded(let lhs), .messageChecklistTasksAdded(let rhs)):
            lhs == rhs
        case (.messageSuggestedPostApprovalFailed(let lhs), .messageSuggestedPostApprovalFailed(let rhs)):
            lhs == rhs
        case (.messageSuggestedPostApproved(let lhs), .messageSuggestedPostApproved(let rhs)):
            lhs == rhs
        case (.messageSuggestedPostDeclined(let lhs), .messageSuggestedPostDeclined(let rhs)):
            lhs == rhs
        case (.messageSuggestedPostPaid(let lhs), .messageSuggestedPostPaid(let rhs)):
            lhs == rhs
        case (.messageSuggestedPostRefunded(let lhs), .messageSuggestedPostRefunded(let rhs)):
            lhs == rhs
        case (.messageContactRegistered, .messageContactRegistered):
            true
        case (.messageUsersShared(let lhs), .messageUsersShared(let rhs)):
            lhs == rhs
        case (.messageChatShared(let lhs), .messageChatShared(let rhs)):
            lhs == rhs
        case (.messageBotWriteAccessAllowed(let lhs), .messageBotWriteAccessAllowed(let rhs)):
            lhs == rhs
        case (.messageWebAppDataSent(let lhs), .messageWebAppDataSent(let rhs)):
            lhs == rhs
        case (.messageWebAppDataReceived(let lhs), .messageWebAppDataReceived(let rhs)):
            lhs == rhs
        case (.messagePassportDataSent(let lhs), .messagePassportDataSent(let rhs)):
            lhs == rhs
        case (.messagePassportDataReceived(let lhs), .messagePassportDataReceived(let rhs)):
            lhs == rhs
        case (.messageProximityAlertTriggered(let lhs), .messageProximityAlertTriggered(let rhs)):
            lhs == rhs
        case (.messageUnsupported, .messageUnsupported):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .messageText(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .messageRichMessage(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .messageAnimation(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .messageAudio(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .messageDocument(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .messagePaidMedia(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .messagePhoto(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .messageSticker(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .messageVideo(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .messageVideoNote(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .messageVoiceNote(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .messageExpiredPhoto:
            hasher.combine(11)
        case .messageExpiredVideo:
            hasher.combine(12)
        case .messageExpiredVideoNote:
            hasher.combine(13)
        case .messageExpiredVoiceNote:
            hasher.combine(14)
        case .messageLiveLocation(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .messageLocation(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .messageVenue(let value):
            hasher.combine(17)
            hasher.combine(value)
        case .messageContact(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .messageAnimatedEmoji(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .messageDice(let value):
            hasher.combine(20)
            hasher.combine(value)
        case .messageGame(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .messagePoll(let value):
            hasher.combine(22)
            hasher.combine(value)
        case .messageStakeDice(let value):
            hasher.combine(23)
            hasher.combine(value)
        case .messageStory(let value):
            hasher.combine(24)
            hasher.combine(value)
        case .messageChecklist(let value):
            hasher.combine(25)
            hasher.combine(value)
        case .messageInvoice(let value):
            hasher.combine(26)
            hasher.combine(value)
        case .messageCall(let value):
            hasher.combine(27)
            hasher.combine(value)
        case .messageGroupCall(let value):
            hasher.combine(28)
            hasher.combine(value)
        case .messageVideoChatScheduled(let value):
            hasher.combine(29)
            hasher.combine(value)
        case .messageVideoChatStarted(let value):
            hasher.combine(30)
            hasher.combine(value)
        case .messageVideoChatEnded(let value):
            hasher.combine(31)
            hasher.combine(value)
        case .messageInviteVideoChatParticipants(let value):
            hasher.combine(32)
            hasher.combine(value)
        case .messagePollOptionAdded(let value):
            hasher.combine(33)
            hasher.combine(value)
        case .messagePollOptionDeleted(let value):
            hasher.combine(34)
            hasher.combine(value)
        case .messageBasicGroupChatCreate(let value):
            hasher.combine(35)
            hasher.combine(value)
        case .messageSupergroupChatCreate(let value):
            hasher.combine(36)
            hasher.combine(value)
        case .messageChatChangeTitle(let value):
            hasher.combine(37)
            hasher.combine(value)
        case .messageChatChangePhoto(let value):
            hasher.combine(38)
            hasher.combine(value)
        case .messageChatDeletePhoto:
            hasher.combine(39)
        case .messageChatOwnerLeft(let value):
            hasher.combine(40)
            hasher.combine(value)
        case .messageChatOwnerChanged(let value):
            hasher.combine(41)
            hasher.combine(value)
        case .messageChatHasProtectedContentToggled(let value):
            hasher.combine(42)
            hasher.combine(value)
        case .messageChatHasProtectedContentDisableRequested(let value):
            hasher.combine(43)
            hasher.combine(value)
        case .messageChatAddMembers(let value):
            hasher.combine(44)
            hasher.combine(value)
        case .messageChatJoinByLink:
            hasher.combine(45)
        case .messageChatJoinByRequest:
            hasher.combine(46)
        case .messageChatJoinFromCommunity(let value):
            hasher.combine(47)
            hasher.combine(value)
        case .messageChatDeleteMember(let value):
            hasher.combine(48)
            hasher.combine(value)
        case .messageChatAddedToCommunity(let value):
            hasher.combine(49)
            hasher.combine(value)
        case .messageChatRemovedFromCommunity:
            hasher.combine(50)
        case .messageChatUpgradeTo(let value):
            hasher.combine(51)
            hasher.combine(value)
        case .messageChatUpgradeFrom(let value):
            hasher.combine(52)
            hasher.combine(value)
        case .messagePinMessage(let value):
            hasher.combine(53)
            hasher.combine(value)
        case .messageScreenshotTaken:
            hasher.combine(54)
        case .messageChatSetBackground(let value):
            hasher.combine(55)
            hasher.combine(value)
        case .messageChatSetTheme(let value):
            hasher.combine(56)
            hasher.combine(value)
        case .messageChatSetMessageAutoDeleteTime(let value):
            hasher.combine(57)
            hasher.combine(value)
        case .messageChatBoost(let value):
            hasher.combine(58)
            hasher.combine(value)
        case .messageForumTopicCreated(let value):
            hasher.combine(59)
            hasher.combine(value)
        case .messageForumTopicEdited(let value):
            hasher.combine(60)
            hasher.combine(value)
        case .messageForumTopicIsClosedToggled(let value):
            hasher.combine(61)
            hasher.combine(value)
        case .messageForumTopicIsHiddenToggled(let value):
            hasher.combine(62)
            hasher.combine(value)
        case .messageSuggestProfilePhoto(let value):
            hasher.combine(63)
            hasher.combine(value)
        case .messageSuggestBirthdate(let value):
            hasher.combine(64)
            hasher.combine(value)
        case .messageCustomServiceAction(let value):
            hasher.combine(65)
            hasher.combine(value)
        case .messageGameScore(let value):
            hasher.combine(66)
            hasher.combine(value)
        case .messageManagedBotCreated(let value):
            hasher.combine(67)
            hasher.combine(value)
        case .messagePaymentSuccessful(let value):
            hasher.combine(68)
            hasher.combine(value)
        case .messagePaymentSuccessfulBot(let value):
            hasher.combine(69)
            hasher.combine(value)
        case .messagePaymentRefunded(let value):
            hasher.combine(70)
            hasher.combine(value)
        case .messageGiftedPremium(let value):
            hasher.combine(71)
            hasher.combine(value)
        case .messagePremiumGiftCode(let value):
            hasher.combine(72)
            hasher.combine(value)
        case .messageGiveawayCreated(let value):
            hasher.combine(73)
            hasher.combine(value)
        case .messageGiveaway(let value):
            hasher.combine(74)
            hasher.combine(value)
        case .messageGiveawayCompleted(let value):
            hasher.combine(75)
            hasher.combine(value)
        case .messageGiveawayWinners(let value):
            hasher.combine(76)
            hasher.combine(value)
        case .messageGiftedStars(let value):
            hasher.combine(77)
            hasher.combine(value)
        case .messageGiftedGrams(let value):
            hasher.combine(78)
            hasher.combine(value)
        case .messageGiveawayPrizeStars(let value):
            hasher.combine(79)
            hasher.combine(value)
        case .messageGift(let value):
            hasher.combine(80)
            hasher.combine(value)
        case .messageUpgradedGift(let value):
            hasher.combine(81)
            hasher.combine(value)
        case .messageRefundedUpgradedGift(let value):
            hasher.combine(82)
            hasher.combine(value)
        case .messageUpgradedGiftPurchaseOffer(let value):
            hasher.combine(83)
            hasher.combine(value)
        case .messageUpgradedGiftPurchaseOfferRejected(let value):
            hasher.combine(84)
            hasher.combine(value)
        case .messagePaidMessagesRefunded(let value):
            hasher.combine(85)
            hasher.combine(value)
        case .messagePaidMessagePriceChanged(let value):
            hasher.combine(86)
            hasher.combine(value)
        case .messageDirectMessagePriceChanged(let value):
            hasher.combine(87)
            hasher.combine(value)
        case .messageChecklistTasksDone(let value):
            hasher.combine(88)
            hasher.combine(value)
        case .messageChecklistTasksAdded(let value):
            hasher.combine(89)
            hasher.combine(value)
        case .messageSuggestedPostApprovalFailed(let value):
            hasher.combine(90)
            hasher.combine(value)
        case .messageSuggestedPostApproved(let value):
            hasher.combine(91)
            hasher.combine(value)
        case .messageSuggestedPostDeclined(let value):
            hasher.combine(92)
            hasher.combine(value)
        case .messageSuggestedPostPaid(let value):
            hasher.combine(93)
            hasher.combine(value)
        case .messageSuggestedPostRefunded(let value):
            hasher.combine(94)
            hasher.combine(value)
        case .messageContactRegistered:
            hasher.combine(95)
        case .messageUsersShared(let value):
            hasher.combine(96)
            hasher.combine(value)
        case .messageChatShared(let value):
            hasher.combine(97)
            hasher.combine(value)
        case .messageBotWriteAccessAllowed(let value):
            hasher.combine(98)
            hasher.combine(value)
        case .messageWebAppDataSent(let value):
            hasher.combine(99)
            hasher.combine(value)
        case .messageWebAppDataReceived(let value):
            hasher.combine(100)
            hasher.combine(value)
        case .messagePassportDataSent(let value):
            hasher.combine(101)
            hasher.combine(value)
        case .messagePassportDataReceived(let value):
            hasher.combine(102)
            hasher.combine(value)
        case .messageProximityAlertTriggered(let value):
            hasher.combine(103)
            hasher.combine(value)
        case .messageUnsupported:
            hasher.combine(104)
        }
    }
}

// MARK: - TDNativeMessageCopyOptions + @retroactive Hashable

extension TDNativeMessageCopyOptions: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sendCopy == rhs.sendCopy else { return false }
        guard lhs.replaceCaption == rhs.replaceCaption else { return false }
        guard lhs.newCaption == rhs.newCaption else { return false }
        guard lhs.newShowCaptionAboveMedia == rhs.newShowCaptionAboveMedia else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sendCopy)
        hasher.combine(replaceCaption)
        hasher.combine(newCaption)
        hasher.combine(newShowCaptionAboveMedia)
    }
}

// MARK: - TDNativeMessageCustomServiceAction + @retroactive Hashable

extension TDNativeMessageCustomServiceAction: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeMessageDice + @retroactive Hashable

extension TDNativeMessageDice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.initialState == rhs.initialState else { return false }
        guard lhs.finalState == rhs.finalState else { return false }
        guard lhs.emoji == rhs.emoji else { return false }
        guard lhs.value == rhs.value else { return false }
        guard lhs.successAnimationFrameNumber == rhs.successAnimationFrameNumber else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(initialState)
        hasher.combine(finalState)
        hasher.combine(emoji)
        hasher.combine(value)
        hasher.combine(successAnimationFrameNumber)
    }
}

// MARK: - TDNativeMessageDirectMessagePriceChanged + @retroactive Hashable

extension TDNativeMessageDirectMessagePriceChanged: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isEnabled == rhs.isEnabled else { return false }
        guard lhs.paidMessageStarCount == rhs.paidMessageStarCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isEnabled)
        hasher.combine(paidMessageStarCount)
    }
}

// MARK: - TDNativeMessageDocument + @retroactive Hashable

extension TDNativeMessageDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
        hasher.combine(caption)
    }
}

// MARK: - TDNativeMessageForumTopicCreated + @retroactive Hashable

extension TDNativeMessageForumTopicCreated: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.isNameImplicit == rhs.isNameImplicit else { return false }
        guard lhs.icon == rhs.icon else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(isNameImplicit)
        hasher.combine(icon)
    }
}

// MARK: - TDNativeMessageForumTopicEdited + @retroactive Hashable

extension TDNativeMessageForumTopicEdited: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.editIconCustomEmojiId == rhs.editIconCustomEmojiId else { return false }
        guard lhs.iconCustomEmojiId == rhs.iconCustomEmojiId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(editIconCustomEmojiId)
        hasher.combine(iconCustomEmojiId)
    }
}

// MARK: - TDNativeMessageForumTopicIsClosedToggled + @retroactive Hashable

extension TDNativeMessageForumTopicIsClosedToggled: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isClosed == rhs.isClosed else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isClosed)
    }
}

// MARK: - TDNativeMessageForumTopicIsHiddenToggled + @retroactive Hashable

extension TDNativeMessageForumTopicIsHiddenToggled: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isHidden == rhs.isHidden else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isHidden)
    }
}

// MARK: - TDNativeMessageForwardInfo + @retroactive Hashable

extension TDNativeMessageForwardInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.origin == rhs.origin else { return false }
        guard lhs.date == rhs.date else { return false }
        guard lhs.source == rhs.source else { return false }
        guard lhs.publicServiceAnnouncementType == rhs.publicServiceAnnouncementType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin)
        hasher.combine(date)
        hasher.combine(source)
        hasher.combine(publicServiceAnnouncementType)
    }
}

// MARK: - TDNativeMessageGame + @retroactive Hashable

extension TDNativeMessageGame: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.game == rhs.game else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(game)
    }
}

// MARK: - TDNativeMessageGameScore + @retroactive Hashable

extension TDNativeMessageGameScore: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gameMessageId == rhs.gameMessageId else { return false }
        guard lhs.gameId == rhs.gameId else { return false }
        guard lhs.score == rhs.score else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gameMessageId)
        hasher.combine(gameId)
        hasher.combine(score)
    }
}

// MARK: - TDNativeMessageGift + @retroactive Hashable

extension TDNativeMessageGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        guard lhs.senderId == rhs.senderId else { return false }
        guard lhs.receiverId == rhs.receiverId else { return false }
        guard lhs.receivedGiftId == rhs.receivedGiftId else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.uniqueGiftNumber == rhs.uniqueGiftNumber else { return false }
        guard lhs.sellStarCount == rhs.sellStarCount else { return false }
        guard lhs.prepaidUpgradeStarCount == rhs.prepaidUpgradeStarCount else { return false }
        guard lhs.isUpgradeSeparate == rhs.isUpgradeSeparate else { return false }
        guard lhs.isFromAuction == rhs.isFromAuction else { return false }
        guard lhs.isPrivate == rhs.isPrivate else { return false }
        guard lhs.isSaved == rhs.isSaved else { return false }
        guard lhs.isPrepaidUpgrade == rhs.isPrepaidUpgrade else { return false }
        guard lhs.canBeUpgraded == rhs.canBeUpgraded else { return false }
        guard lhs.wasConverted == rhs.wasConverted else { return false }
        guard lhs.wasUpgraded == rhs.wasUpgraded else { return false }
        guard lhs.wasRefunded == rhs.wasRefunded else { return false }
        guard lhs.upgradedReceivedGiftId == rhs.upgradedReceivedGiftId else { return false }
        guard lhs.prepaidUpgradeHash == rhs.prepaidUpgradeHash else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
        hasher.combine(senderId)
        hasher.combine(receiverId)
        hasher.combine(receivedGiftId)
        hasher.combine(text)
        hasher.combine(uniqueGiftNumber)
        hasher.combine(sellStarCount)
        hasher.combine(prepaidUpgradeStarCount)
        hasher.combine(isUpgradeSeparate)
        hasher.combine(isFromAuction)
        hasher.combine(isPrivate)
        hasher.combine(isSaved)
        hasher.combine(isPrepaidUpgrade)
        hasher.combine(canBeUpgraded)
        hasher.combine(wasConverted)
        hasher.combine(wasUpgraded)
        hasher.combine(wasRefunded)
        hasher.combine(upgradedReceivedGiftId)
        hasher.combine(prepaidUpgradeHash)
    }
}

// MARK: - TDNativeMessageGiftedGrams + @retroactive Hashable

extension TDNativeMessageGiftedGrams: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gifterUserId == rhs.gifterUserId else { return false }
        guard lhs.receiverUserId == rhs.receiverUserId else { return false }
        guard lhs.gramAmount == rhs.gramAmount else { return false }
        guard lhs.transactionId == rhs.transactionId else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gifterUserId)
        hasher.combine(receiverUserId)
        hasher.combine(gramAmount)
        hasher.combine(transactionId)
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeMessageGiftedPremium + @retroactive Hashable

extension TDNativeMessageGiftedPremium: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gifterUserId == rhs.gifterUserId else { return false }
        guard lhs.receiverUserId == rhs.receiverUserId else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.amount == rhs.amount else { return false }
        guard lhs.cryptocurrency == rhs.cryptocurrency else { return false }
        guard lhs.cryptocurrencyAmount == rhs.cryptocurrencyAmount else { return false }
        guard lhs.monthCount == rhs.monthCount else { return false }
        guard lhs.dayCount == rhs.dayCount else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gifterUserId)
        hasher.combine(receiverUserId)
        hasher.combine(text)
        hasher.combine(currency)
        hasher.combine(amount)
        hasher.combine(cryptocurrency)
        hasher.combine(cryptocurrencyAmount)
        hasher.combine(monthCount)
        hasher.combine(dayCount)
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeMessageGiftedStars + @retroactive Hashable

extension TDNativeMessageGiftedStars: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gifterUserId == rhs.gifterUserId else { return false }
        guard lhs.receiverUserId == rhs.receiverUserId else { return false }
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.amount == rhs.amount else { return false }
        guard lhs.cryptocurrency == rhs.cryptocurrency else { return false }
        guard lhs.cryptocurrencyAmount == rhs.cryptocurrencyAmount else { return false }
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.transactionId == rhs.transactionId else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gifterUserId)
        hasher.combine(receiverUserId)
        hasher.combine(currency)
        hasher.combine(amount)
        hasher.combine(cryptocurrency)
        hasher.combine(cryptocurrencyAmount)
        hasher.combine(starCount)
        hasher.combine(transactionId)
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeMessageGiveaway + @retroactive Hashable

extension TDNativeMessageGiveaway: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.parameters == rhs.parameters else { return false }
        guard lhs.winnerCount == rhs.winnerCount else { return false }
        guard lhs.prize == rhs.prize else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(parameters)
        hasher.combine(winnerCount)
        hasher.combine(prize)
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeMessageGiveawayCompleted + @retroactive Hashable

extension TDNativeMessageGiveawayCompleted: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.giveawayMessageId == rhs.giveawayMessageId else { return false }
        guard lhs.winnerCount == rhs.winnerCount else { return false }
        guard lhs.isStarGiveaway == rhs.isStarGiveaway else { return false }
        guard lhs.unclaimedPrizeCount == rhs.unclaimedPrizeCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(giveawayMessageId)
        hasher.combine(winnerCount)
        hasher.combine(isStarGiveaway)
        hasher.combine(unclaimedPrizeCount)
    }
}

// MARK: - TDNativeMessageGiveawayCreated + @retroactive Hashable

extension TDNativeMessageGiveawayCreated: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
    }
}

// MARK: - TDNativeMessageGiveawayPrizeStars + @retroactive Hashable

extension TDNativeMessageGiveawayPrizeStars: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.transactionId == rhs.transactionId else { return false }
        guard lhs.boostedChatId == rhs.boostedChatId else { return false }
        guard lhs.giveawayMessageId == rhs.giveawayMessageId else { return false }
        guard lhs.isUnclaimed == rhs.isUnclaimed else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
        hasher.combine(transactionId)
        hasher.combine(boostedChatId)
        hasher.combine(giveawayMessageId)
        hasher.combine(isUnclaimed)
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeMessageGiveawayWinners + @retroactive Hashable

extension TDNativeMessageGiveawayWinners: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.boostedChatId == rhs.boostedChatId else { return false }
        guard lhs.giveawayMessageId == rhs.giveawayMessageId else { return false }
        guard lhs.additionalChatCount == rhs.additionalChatCount else { return false }
        guard lhs.actualWinnersSelectionDate == rhs.actualWinnersSelectionDate else { return false }
        guard lhs.onlyNewMembers == rhs.onlyNewMembers else { return false }
        guard lhs.wasRefunded == rhs.wasRefunded else { return false }
        guard lhs.prize == rhs.prize else { return false }
        guard lhs.prizeDescription == rhs.prizeDescription else { return false }
        guard lhs.winnerCount == rhs.winnerCount else { return false }
        guard lhs.winnerUserIds == rhs.winnerUserIds else { return false }
        guard lhs.unclaimedPrizeCount == rhs.unclaimedPrizeCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(boostedChatId)
        hasher.combine(giveawayMessageId)
        hasher.combine(additionalChatCount)
        hasher.combine(actualWinnersSelectionDate)
        hasher.combine(onlyNewMembers)
        hasher.combine(wasRefunded)
        hasher.combine(prize)
        hasher.combine(prizeDescription)
        hasher.combine(winnerCount)
        hasher.combine(winnerUserIds)
        hasher.combine(unclaimedPrizeCount)
    }
}

// MARK: - TDNativeMessageGroupCall + @retroactive Hashable

extension TDNativeMessageGroupCall: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.uniqueId == rhs.uniqueId else { return false }
        guard lhs.isActive == rhs.isActive else { return false }
        guard lhs.wasMissed == rhs.wasMissed else { return false }
        guard lhs.isVideo == rhs.isVideo else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.otherParticipantIds == rhs.otherParticipantIds else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueId)
        hasher.combine(isActive)
        hasher.combine(wasMissed)
        hasher.combine(isVideo)
        hasher.combine(duration)
        hasher.combine(otherParticipantIds)
    }
}

// MARK: - TDNativeMessageImportInfo + @retroactive Hashable

extension TDNativeMessageImportInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.senderName == rhs.senderName else { return false }
        guard lhs.date == rhs.date else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(senderName)
        hasher.combine(date)
    }
}

// MARK: - TDNativeMessageInteractionInfo + @retroactive Hashable

extension TDNativeMessageInteractionInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.viewCount == rhs.viewCount else { return false }
        guard lhs.forwardCount == rhs.forwardCount else { return false }
        guard lhs.replyInfo == rhs.replyInfo else { return false }
        guard lhs.reactions == rhs.reactions else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(viewCount)
        hasher.combine(forwardCount)
        hasher.combine(replyInfo)
        hasher.combine(reactions)
    }
}

// MARK: - TDNativeMessageInviteVideoChatParticipants + @retroactive Hashable

extension TDNativeMessageInviteVideoChatParticipants: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groupCallId == rhs.groupCallId else { return false }
        guard lhs.userIds == rhs.userIds else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(groupCallId)
        hasher.combine(userIds)
    }
}

// MARK: - TDNativeMessageInvoice + @retroactive Hashable

extension TDNativeMessageInvoice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.productInfo == rhs.productInfo else { return false }
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.totalAmount == rhs.totalAmount else { return false }
        guard lhs.startParameter == rhs.startParameter else { return false }
        guard lhs.isTest == rhs.isTest else { return false }
        guard lhs.needShippingAddress == rhs.needShippingAddress else { return false }
        guard lhs.receiptMessageId == rhs.receiptMessageId else { return false }
        guard lhs.paidMedia == rhs.paidMedia else { return false }
        guard lhs.paidMediaCaption == rhs.paidMediaCaption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(productInfo)
        hasher.combine(currency)
        hasher.combine(totalAmount)
        hasher.combine(startParameter)
        hasher.combine(isTest)
        hasher.combine(needShippingAddress)
        hasher.combine(receiptMessageId)
        hasher.combine(paidMedia)
        hasher.combine(paidMediaCaption)
    }
}

// MARK: - TDNativeMessageLiveLocation + @retroactive Hashable

extension TDNativeMessageLiveLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        guard lhs.expiresIn == rhs.expiresIn else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(expiresIn)
    }
}

// MARK: - TDNativeMessageLocation + @retroactive Hashable

extension TDNativeMessageLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
    }
}

// MARK: - TDNativeMessageManagedBotCreated + @retroactive Hashable

extension TDNativeMessageManagedBotCreated: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.botUserId == rhs.botUserId else { return false }
        guard lhs.managerBotUserId == rhs.managerBotUserId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(botUserId)
        hasher.combine(managerBotUserId)
    }
}

// MARK: - TDNativeMessageOrigin + @retroactive Hashable

extension TDNativeMessageOrigin: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.messageOriginUser(let lhs), .messageOriginUser(let rhs)):
            lhs == rhs
        case (.messageOriginHiddenUser(let lhs), .messageOriginHiddenUser(let rhs)):
            lhs == rhs
        case (.messageOriginChat(let lhs), .messageOriginChat(let rhs)):
            lhs == rhs
        case (.messageOriginChannel(let lhs), .messageOriginChannel(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .messageOriginUser(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .messageOriginHiddenUser(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .messageOriginChat(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .messageOriginChannel(let value):
            hasher.combine(3)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeMessageOriginChannel + @retroactive Hashable

extension TDNativeMessageOriginChannel: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatId == rhs.chatId else { return false }
        guard lhs.messageId == rhs.messageId else { return false }
        guard lhs.authorSignature == rhs.authorSignature else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
        hasher.combine(messageId)
        hasher.combine(authorSignature)
    }
}

// MARK: - TDNativeMessageOriginChat + @retroactive Hashable

extension TDNativeMessageOriginChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.senderChatId == rhs.senderChatId else { return false }
        guard lhs.authorSignature == rhs.authorSignature else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(senderChatId)
        hasher.combine(authorSignature)
    }
}

// MARK: - TDNativeMessageOriginHiddenUser + @retroactive Hashable

extension TDNativeMessageOriginHiddenUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.senderName == rhs.senderName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(senderName)
    }
}

// MARK: - TDNativeMessageOriginUser + @retroactive Hashable

extension TDNativeMessageOriginUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.senderUserId == rhs.senderUserId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(senderUserId)
    }
}

// MARK: - TDNativeMessagePaidMedia + @retroactive Hashable

extension TDNativeMessagePaidMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.media == rhs.media else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
        hasher.combine(media)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
    }
}

// MARK: - TDNativeMessagePaidMessagePriceChanged + @retroactive Hashable

extension TDNativeMessagePaidMessagePriceChanged: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.paidMessageStarCount == rhs.paidMessageStarCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(paidMessageStarCount)
    }
}

// MARK: - TDNativeMessagePaidMessagesRefunded + @retroactive Hashable

extension TDNativeMessagePaidMessagesRefunded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.messageCount == rhs.messageCount else { return false }
        guard lhs.starCount == rhs.starCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(messageCount)
        hasher.combine(starCount)
    }
}

// MARK: - TDNativeMessagePassportDataReceived + @retroactive Hashable

extension TDNativeMessagePassportDataReceived: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.elements == rhs.elements else { return false }
        guard lhs.credentials == rhs.credentials else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(elements)
        hasher.combine(credentials)
    }
}

// MARK: - TDNativeMessagePassportDataSent + @retroactive Hashable

extension TDNativeMessagePassportDataSent: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.types == rhs.types else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(types)
    }
}

// MARK: - TDNativeMessagePaymentRefunded + @retroactive Hashable

extension TDNativeMessagePaymentRefunded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.ownerId == rhs.ownerId else { return false }
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.totalAmount == rhs.totalAmount else { return false }
        guard lhs.invoicePayload == rhs.invoicePayload else { return false }
        guard lhs.telegramPaymentChargeId == rhs.telegramPaymentChargeId else { return false }
        guard lhs.providerPaymentChargeId == rhs.providerPaymentChargeId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ownerId)
        hasher.combine(currency)
        hasher.combine(totalAmount)
        hasher.combine(invoicePayload)
        hasher.combine(telegramPaymentChargeId)
        hasher.combine(providerPaymentChargeId)
    }
}

// MARK: - TDNativeMessagePaymentSuccessful + @retroactive Hashable

extension TDNativeMessagePaymentSuccessful: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.invoiceChatId == rhs.invoiceChatId else { return false }
        guard lhs.invoiceMessageId == rhs.invoiceMessageId else { return false }
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.totalAmount == rhs.totalAmount else { return false }
        guard lhs.subscriptionUntilDate == rhs.subscriptionUntilDate else { return false }
        guard lhs.isRecurring == rhs.isRecurring else { return false }
        guard lhs.isFirstRecurring == rhs.isFirstRecurring else { return false }
        guard lhs.invoiceName == rhs.invoiceName else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(invoiceChatId)
        hasher.combine(invoiceMessageId)
        hasher.combine(currency)
        hasher.combine(totalAmount)
        hasher.combine(subscriptionUntilDate)
        hasher.combine(isRecurring)
        hasher.combine(isFirstRecurring)
        hasher.combine(invoiceName)
    }
}

// MARK: - TDNativeMessagePaymentSuccessfulBot + @retroactive Hashable

extension TDNativeMessagePaymentSuccessfulBot: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.totalAmount == rhs.totalAmount else { return false }
        guard lhs.subscriptionUntilDate == rhs.subscriptionUntilDate else { return false }
        guard lhs.isRecurring == rhs.isRecurring else { return false }
        guard lhs.isFirstRecurring == rhs.isFirstRecurring else { return false }
        guard lhs.invoicePayload == rhs.invoicePayload else { return false }
        guard lhs.shippingOptionId == rhs.shippingOptionId else { return false }
        guard lhs.orderInfo == rhs.orderInfo else { return false }
        guard lhs.telegramPaymentChargeId == rhs.telegramPaymentChargeId else { return false }
        guard lhs.providerPaymentChargeId == rhs.providerPaymentChargeId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(currency)
        hasher.combine(totalAmount)
        hasher.combine(subscriptionUntilDate)
        hasher.combine(isRecurring)
        hasher.combine(isFirstRecurring)
        hasher.combine(invoicePayload)
        hasher.combine(shippingOptionId)
        hasher.combine(orderInfo)
        hasher.combine(telegramPaymentChargeId)
        hasher.combine(providerPaymentChargeId)
    }
}

// MARK: - TDNativeMessagePinMessage + @retroactive Hashable

extension TDNativeMessagePinMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.messageId == rhs.messageId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
    }
}

// MARK: - TDNativeMessagePoll + @retroactive Hashable

extension TDNativeMessagePoll: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.poll == rhs.poll else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.media == rhs.media else { return false }
        guard lhs.canAddOption == rhs.canAddOption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(poll)
        hasher.combine(description)
        hasher.combine(media)
        hasher.combine(canAddOption)
    }
}

// MARK: - TDNativeMessagePollOptionAdded + @retroactive Hashable

extension TDNativeMessagePollOptionAdded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.pollMessageId == rhs.pollMessageId else { return false }
        guard lhs.optionId == rhs.optionId else { return false }
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pollMessageId)
        hasher.combine(optionId)
        hasher.combine(text)
    }
}

// MARK: - TDNativeMessagePollOptionDeleted + @retroactive Hashable

extension TDNativeMessagePollOptionDeleted: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.pollMessageId == rhs.pollMessageId else { return false }
        guard lhs.optionId == rhs.optionId else { return false }
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pollMessageId)
        hasher.combine(optionId)
        hasher.combine(text)
    }
}

// MARK: - TDNativeMessagePremiumGiftCode + @retroactive Hashable

extension TDNativeMessagePremiumGiftCode: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.creatorId == rhs.creatorId else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.isFromGiveaway == rhs.isFromGiveaway else { return false }
        guard lhs.isUnclaimed == rhs.isUnclaimed else { return false }
        guard lhs.currency == rhs.currency else { return false }
        guard lhs.amount == rhs.amount else { return false }
        guard lhs.cryptocurrency == rhs.cryptocurrency else { return false }
        guard lhs.cryptocurrencyAmount == rhs.cryptocurrencyAmount else { return false }
        guard lhs.monthCount == rhs.monthCount else { return false }
        guard lhs.dayCount == rhs.dayCount else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        guard lhs.code == rhs.code else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatorId)
        hasher.combine(text)
        hasher.combine(isFromGiveaway)
        hasher.combine(isUnclaimed)
        hasher.combine(currency)
        hasher.combine(amount)
        hasher.combine(cryptocurrency)
        hasher.combine(cryptocurrencyAmount)
        hasher.combine(monthCount)
        hasher.combine(dayCount)
        hasher.combine(sticker)
        hasher.combine(code)
    }
}

// MARK: - TDNativeMessageProperties + @retroactive Hashable

extension TDNativeMessageProperties: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canAddOffer == rhs.canAddOffer else { return false }
        guard lhs.canAddTasks == rhs.canAddTasks else { return false }
        guard lhs.canBeApproved == rhs.canBeApproved else { return false }
        guard lhs.canBeCopied == rhs.canBeCopied else { return false }
        guard lhs.canBeCopiedToSecretChat == rhs.canBeCopiedToSecretChat else { return false }
        guard lhs.canBeDeclined == rhs.canBeDeclined else { return false }
        guard lhs.canBeDeletedOnlyForSelf == rhs.canBeDeletedOnlyForSelf else { return false }
        guard lhs.canBeDeletedForAllUsers == rhs.canBeDeletedForAllUsers else { return false }
        guard lhs.canBeEdited == rhs.canBeEdited else { return false }
        guard lhs.canBeForwarded == rhs.canBeForwarded else { return false }
        guard lhs.canBePaid == rhs.canBePaid else { return false }
        guard lhs.canBePinned == rhs.canBePinned else { return false }
        guard lhs.canBeReplied == rhs.canBeReplied else { return false }
        guard lhs.canBeRepliedInAnotherChat == rhs.canBeRepliedInAnotherChat else { return false }
        guard lhs.canBeSaved == rhs.canBeSaved else { return false }
        guard lhs.canBeSharedInStory == rhs.canBeSharedInStory else { return false }
        guard lhs.canDeleteReactions == rhs.canDeleteReactions else { return false }
        guard lhs.canEditMedia == rhs.canEditMedia else { return false }
        guard lhs.canEditSchedulingState == rhs.canEditSchedulingState else { return false }
        guard lhs.canEditSuggestedPostInfo == rhs.canEditSuggestedPostInfo else { return false }
        guard lhs.canGetAuthor == rhs.canGetAuthor else { return false }
        guard lhs.canGetEmbeddingCode == rhs.canGetEmbeddingCode else { return false }
        guard lhs.canGetLink == rhs.canGetLink else { return false }
        guard lhs.canGetMediaTimestampLinks == rhs.canGetMediaTimestampLinks else { return false }
        guard lhs.canGetMessageThread == rhs.canGetMessageThread else { return false }
        guard lhs.canGetPollVoteStatistics == rhs.canGetPollVoteStatistics else { return false }
        guard lhs.canGetReadDate == rhs.canGetReadDate else { return false }
        guard lhs.canGetStatistics == rhs.canGetStatistics else { return false }
        guard lhs.canGetVideoAdvertisements == rhs.canGetVideoAdvertisements else { return false }
        guard lhs.canGetViewers == rhs.canGetViewers else { return false }
        guard lhs.canMarkTasksAsDone == rhs.canMarkTasksAsDone else { return false }
        guard lhs.canRecognizeSpeech == rhs.canRecognizeSpeech else { return false }
        guard lhs.canReportChat == rhs.canReportChat else { return false }
        guard lhs.canReportReactions == rhs.canReportReactions else { return false }
        guard lhs.canReportSupergroupSpam == rhs.canReportSupergroupSpam else { return false }
        guard lhs.canSetFactCheck == rhs.canSetFactCheck else { return false }
        guard lhs.hasProtectedContentByCurrentUser == rhs.hasProtectedContentByCurrentUser else { return false }
        guard lhs.hasProtectedContentByOtherUser == rhs.hasProtectedContentByOtherUser else { return false }
        guard lhs.needShowStatistics == rhs.needShowStatistics else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canAddOffer)
        hasher.combine(canAddTasks)
        hasher.combine(canBeApproved)
        hasher.combine(canBeCopied)
        hasher.combine(canBeCopiedToSecretChat)
        hasher.combine(canBeDeclined)
        hasher.combine(canBeDeletedOnlyForSelf)
        hasher.combine(canBeDeletedForAllUsers)
        hasher.combine(canBeEdited)
        hasher.combine(canBeForwarded)
        hasher.combine(canBePaid)
        hasher.combine(canBePinned)
        hasher.combine(canBeReplied)
        hasher.combine(canBeRepliedInAnotherChat)
        hasher.combine(canBeSaved)
        hasher.combine(canBeSharedInStory)
        hasher.combine(canDeleteReactions)
        hasher.combine(canEditMedia)
        hasher.combine(canEditSchedulingState)
        hasher.combine(canEditSuggestedPostInfo)
        hasher.combine(canGetAuthor)
        hasher.combine(canGetEmbeddingCode)
        hasher.combine(canGetLink)
        hasher.combine(canGetMediaTimestampLinks)
        hasher.combine(canGetMessageThread)
        hasher.combine(canGetPollVoteStatistics)
        hasher.combine(canGetReadDate)
        hasher.combine(canGetStatistics)
        hasher.combine(canGetVideoAdvertisements)
        hasher.combine(canGetViewers)
        hasher.combine(canMarkTasksAsDone)
        hasher.combine(canRecognizeSpeech)
        hasher.combine(canReportChat)
        hasher.combine(canReportReactions)
        hasher.combine(canReportSupergroupSpam)
        hasher.combine(canSetFactCheck)
        hasher.combine(hasProtectedContentByCurrentUser)
        hasher.combine(hasProtectedContentByOtherUser)
        hasher.combine(needShowStatistics)
    }
}

// MARK: - TDNativeMessageProximityAlertTriggered + @retroactive Hashable

extension TDNativeMessageProximityAlertTriggered: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.travelerId == rhs.travelerId else { return false }
        guard lhs.watcherId == rhs.watcherId else { return false }
        guard lhs.distance == rhs.distance else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(travelerId)
        hasher.combine(watcherId)
        hasher.combine(distance)
    }
}

// MARK: - TDNativeMessageRefundedUpgradedGift + @retroactive Hashable

extension TDNativeMessageRefundedUpgradedGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        guard lhs.senderId == rhs.senderId else { return false }
        guard lhs.receiverId == rhs.receiverId else { return false }
        guard lhs.origin == rhs.origin else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
        hasher.combine(senderId)
        hasher.combine(receiverId)
        hasher.combine(origin)
    }
}

// MARK: - TDNativeMessageReplyInfo + @retroactive Hashable

extension TDNativeMessageReplyInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.replyCount == rhs.replyCount else { return false }
        guard lhs.recentReplierIds == rhs.recentReplierIds else { return false }
        guard lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId else { return false }
        guard lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId else { return false }
        guard lhs.lastMessageId == rhs.lastMessageId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(replyCount)
        hasher.combine(recentReplierIds)
        hasher.combine(lastReadInboxMessageId)
        hasher.combine(lastReadOutboxMessageId)
        hasher.combine(lastMessageId)
    }
}

// MARK: - TDNativeMessageReplyTo + @retroactive Hashable

extension TDNativeMessageReplyTo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.messageReplyToMessage(let lhs), .messageReplyToMessage(let rhs)):
            lhs == rhs
        case (.messageReplyToStory(let lhs), .messageReplyToStory(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .messageReplyToMessage(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .messageReplyToStory(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeMessageReplyToMessage + @retroactive Hashable

extension TDNativeMessageReplyToMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatId == rhs.chatId else { return false }
        guard lhs.messageId == rhs.messageId else { return false }
        guard lhs.quote == rhs.quote else { return false }
        guard lhs.checklistTaskId == rhs.checklistTaskId else { return false }
        guard lhs.pollOptionId == rhs.pollOptionId else { return false }
        guard lhs.origin == rhs.origin else { return false }
        guard lhs.originSendDate == rhs.originSendDate else { return false }
        guard lhs.content == rhs.content else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
        hasher.combine(messageId)
        hasher.combine(quote)
        hasher.combine(checklistTaskId)
        hasher.combine(pollOptionId)
        hasher.combine(origin)
        hasher.combine(originSendDate)
        hasher.combine(content)
    }
}

// MARK: - TDNativeMessageReplyToStory + @retroactive Hashable

extension TDNativeMessageReplyToStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyPosterChatId == rhs.storyPosterChatId else { return false }
        guard lhs.storyId == rhs.storyId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyPosterChatId)
        hasher.combine(storyId)
    }
}

// MARK: - TDNativeMessageRichMessage + @retroactive Hashable

extension TDNativeMessageRichMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.message == rhs.message else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(message)
    }
}

// MARK: - TDNativeMessageSchedulingState + @retroactive Hashable

extension TDNativeMessageSchedulingState: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.messageSchedulingStateSendAtDate(let lhs), .messageSchedulingStateSendAtDate(let rhs)):
            lhs == rhs
        case (.messageSchedulingStateSendWhenOnline, .messageSchedulingStateSendWhenOnline):
            true
        case (
            .messageSchedulingStateSendWhenVideoProcessed(let lhs),
            .messageSchedulingStateSendWhenVideoProcessed(let rhs),
        ):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .messageSchedulingStateSendAtDate(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .messageSchedulingStateSendWhenOnline:
            hasher.combine(1)
        case .messageSchedulingStateSendWhenVideoProcessed(let value):
            hasher.combine(2)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeMessageSchedulingStateSendAtDate + @retroactive Hashable

extension TDNativeMessageSchedulingStateSendAtDate: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sendDate == rhs.sendDate else { return false }
        guard lhs.repeatPeriod == rhs.repeatPeriod else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sendDate)
        hasher.combine(repeatPeriod)
    }
}

// MARK: - TDNativeMessageSchedulingStateSendWhenVideoProcessed + @retroactive Hashable

extension TDNativeMessageSchedulingStateSendWhenVideoProcessed: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sendDate == rhs.sendDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sendDate)
    }
}

// MARK: - TDNativeMessageSelfDestructType + @retroactive Hashable

extension TDNativeMessageSelfDestructType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.messageSelfDestructTypeTimer(let lhs), .messageSelfDestructTypeTimer(let rhs)):
            lhs == rhs
        case (.messageSelfDestructTypeImmediately, .messageSelfDestructTypeImmediately):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .messageSelfDestructTypeTimer(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .messageSelfDestructTypeImmediately:
            hasher.combine(1)
        }
    }
}

// MARK: - TDNativeMessageSelfDestructTypeTimer + @retroactive Hashable

extension TDNativeMessageSelfDestructTypeTimer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.selfDestructTime == rhs.selfDestructTime else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(selfDestructTime)
    }
}

// MARK: - TDNativeMessageSendingState + @retroactive Hashable

extension TDNativeMessageSendingState: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.messageSendingStatePending(let lhs), .messageSendingStatePending(let rhs)):
            lhs == rhs
        case (.messageSendingStateFailed(let lhs), .messageSendingStateFailed(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .messageSendingStatePending(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .messageSendingStateFailed(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeMessageSendingStateFailed + @retroactive Hashable

extension TDNativeMessageSendingStateFailed: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.error == rhs.error else { return false }
        guard lhs.canRetry == rhs.canRetry else { return false }
        guard lhs.needAnotherSender == rhs.needAnotherSender else { return false }
        guard lhs.needAnotherReplyQuote == rhs.needAnotherReplyQuote else { return false }
        guard lhs.needDropReply == rhs.needDropReply else { return false }
        guard lhs.requiredPaidMessageStarCount == rhs.requiredPaidMessageStarCount else { return false }
        guard lhs.retryAfter == rhs.retryAfter else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(error)
        hasher.combine(canRetry)
        hasher.combine(needAnotherSender)
        hasher.combine(needAnotherReplyQuote)
        hasher.combine(needDropReply)
        hasher.combine(requiredPaidMessageStarCount)
        hasher.combine(retryAfter)
    }
}

// MARK: - TDNativeMessageSendingStatePending + @retroactive Hashable

extension TDNativeMessageSendingStatePending: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sendingId == rhs.sendingId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sendingId)
    }
}

// MARK: - TDNativeMessageStakeDice + @retroactive Hashable

extension TDNativeMessageStakeDice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.initialState == rhs.initialState else { return false }
        guard lhs.finalState == rhs.finalState else { return false }
        guard lhs.value == rhs.value else { return false }
        guard lhs.stakeGramAmount == rhs.stakeGramAmount else { return false }
        guard lhs.prizeGramAmount == rhs.prizeGramAmount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(initialState)
        hasher.combine(finalState)
        hasher.combine(value)
        hasher.combine(stakeGramAmount)
        hasher.combine(prizeGramAmount)
    }
}

// MARK: - TDNativeMessageStory + @retroactive Hashable

extension TDNativeMessageStory: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.storyPosterChatId == rhs.storyPosterChatId else { return false }
        guard lhs.storyId == rhs.storyId else { return false }
        guard lhs.viaMention == rhs.viaMention else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyPosterChatId)
        hasher.combine(storyId)
        hasher.combine(viaMention)
    }
}

// MARK: - TDNativeMessageSuggestBirthdate + @retroactive Hashable

extension TDNativeMessageSuggestBirthdate: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.birthdate == rhs.birthdate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(birthdate)
    }
}

// MARK: - TDNativeMessageSuggestProfilePhoto + @retroactive Hashable

extension TDNativeMessageSuggestProfilePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
    }
}

// MARK: - TDNativeMessageSuggestedPostApprovalFailed + @retroactive Hashable

extension TDNativeMessageSuggestedPostApprovalFailed: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId else { return false }
        guard lhs.price == rhs.price else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(suggestedPostMessageId)
        hasher.combine(price)
    }
}

// MARK: - TDNativeMessageSuggestedPostApproved + @retroactive Hashable

extension TDNativeMessageSuggestedPostApproved: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId else { return false }
        guard lhs.price == rhs.price else { return false }
        guard lhs.sendDate == rhs.sendDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(suggestedPostMessageId)
        hasher.combine(price)
        hasher.combine(sendDate)
    }
}

// MARK: - TDNativeMessageSuggestedPostDeclined + @retroactive Hashable

extension TDNativeMessageSuggestedPostDeclined: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId else { return false }
        guard lhs.comment == rhs.comment else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(suggestedPostMessageId)
        hasher.combine(comment)
    }
}

// MARK: - TDNativeMessageSuggestedPostPaid + @retroactive Hashable

extension TDNativeMessageSuggestedPostPaid: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId else { return false }
        guard lhs.starAmount == rhs.starAmount else { return false }
        guard lhs.gramAmount == rhs.gramAmount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(suggestedPostMessageId)
        hasher.combine(starAmount)
        hasher.combine(gramAmount)
    }
}

// MARK: - TDNativeMessageSuggestedPostRefunded + @retroactive Hashable

extension TDNativeMessageSuggestedPostRefunded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId else { return false }
        guard lhs.reason == rhs.reason else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(suggestedPostMessageId)
        hasher.combine(reason)
    }
}

// MARK: - TDNativeMessageSupergroupChatCreate + @retroactive Hashable

extension TDNativeMessageSupergroupChatCreate: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }
}

// MARK: - TDNativeMessageText + @retroactive Hashable

extension TDNativeMessageText: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.linkPreview == rhs.linkPreview else { return false }
        guard lhs.linkPreviewOptions == rhs.linkPreviewOptions else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(linkPreview)
        hasher.combine(linkPreviewOptions)
    }
}

// MARK: - TDNativeMessageUpgradedGift + @retroactive Hashable

extension TDNativeMessageUpgradedGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        guard lhs.senderId == rhs.senderId else { return false }
        guard lhs.receiverId == rhs.receiverId else { return false }
        guard lhs.origin == rhs.origin else { return false }
        guard lhs.receivedGiftId == rhs.receivedGiftId else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.isPrivate == rhs.isPrivate else { return false }
        guard lhs.isSaved == rhs.isSaved else { return false }
        guard lhs.canBeTransferred == rhs.canBeTransferred else { return false }
        guard lhs.wasTransferred == rhs.wasTransferred else { return false }
        guard lhs.transferStarCount == rhs.transferStarCount else { return false }
        guard lhs.dropOriginalDetailsStarCount == rhs.dropOriginalDetailsStarCount else { return false }
        guard lhs.nextTransferDate == rhs.nextTransferDate else { return false }
        guard lhs.nextResaleDate == rhs.nextResaleDate else { return false }
        guard lhs.exportDate == rhs.exportDate else { return false }
        guard lhs.craftDate == rhs.craftDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
        hasher.combine(senderId)
        hasher.combine(receiverId)
        hasher.combine(origin)
        hasher.combine(receivedGiftId)
        hasher.combine(text)
        hasher.combine(isPrivate)
        hasher.combine(isSaved)
        hasher.combine(canBeTransferred)
        hasher.combine(wasTransferred)
        hasher.combine(transferStarCount)
        hasher.combine(dropOriginalDetailsStarCount)
        hasher.combine(nextTransferDate)
        hasher.combine(nextResaleDate)
        hasher.combine(exportDate)
        hasher.combine(craftDate)
    }
}

// MARK: - TDNativeMessageUpgradedGiftPurchaseOffer + @retroactive Hashable

extension TDNativeMessageUpgradedGiftPurchaseOffer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        guard lhs.state == rhs.state else { return false }
        guard lhs.price == rhs.price else { return false }
        guard lhs.expirationDate == rhs.expirationDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
        hasher.combine(state)
        hasher.combine(price)
        hasher.combine(expirationDate)
    }
}

// MARK: - TDNativeMessageUpgradedGiftPurchaseOfferRejected + @retroactive Hashable

extension TDNativeMessageUpgradedGiftPurchaseOfferRejected: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift else { return false }
        guard lhs.price == rhs.price else { return false }
        guard lhs.offerMessageId == rhs.offerMessageId else { return false }
        guard lhs.wasExpired == rhs.wasExpired else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gift)
        hasher.combine(price)
        hasher.combine(offerMessageId)
        hasher.combine(wasExpired)
    }
}

// MARK: - TDNativeMessageUsersShared + @retroactive Hashable

extension TDNativeMessageUsersShared: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.users == rhs.users else { return false }
        guard lhs.buttonId == rhs.buttonId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(users)
        hasher.combine(buttonId)
    }
}

// MARK: - TDNativeMessageVenue + @retroactive Hashable

extension TDNativeMessageVenue: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.venue == rhs.venue else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(venue)
    }
}

// MARK: - TDNativeMessageVideoChatEnded + @retroactive Hashable

extension TDNativeMessageVideoChatEnded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.duration == rhs.duration else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(duration)
    }
}

// MARK: - TDNativeMessageVideoChatScheduled + @retroactive Hashable

extension TDNativeMessageVideoChatScheduled: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groupCallId == rhs.groupCallId else { return false }
        guard lhs.startDate == rhs.startDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(groupCallId)
        hasher.combine(startDate)
    }
}

// MARK: - TDNativeMessageVideoChatStarted + @retroactive Hashable

extension TDNativeMessageVideoChatStarted: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groupCallId == rhs.groupCallId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(groupCallId)
    }
}

// MARK: - TDNativeMessageVideoNote + @retroactive Hashable

extension TDNativeMessageVideoNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.videoNote == rhs.videoNote else { return false }
        guard lhs.isViewed == rhs.isViewed else { return false }
        guard lhs.isSecret == rhs.isSecret else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(videoNote)
        hasher.combine(isViewed)
        hasher.combine(isSecret)
    }
}

// MARK: - TDNativeMessageVoiceNote + @retroactive Hashable

extension TDNativeMessageVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.voiceNote == rhs.voiceNote else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.isListened == rhs.isListened else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceNote)
        hasher.combine(caption)
        hasher.combine(isListened)
    }
}

// MARK: - TDNativeMessageWebAppDataReceived + @retroactive Hashable

extension TDNativeMessageWebAppDataReceived: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.buttonText == rhs.buttonText else { return false }
        guard lhs.data == rhs.data else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(buttonText)
        hasher.combine(data)
    }
}

// MARK: - TDNativeMessageWebAppDataSent + @retroactive Hashable

extension TDNativeMessageWebAppDataSent: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.buttonText == rhs.buttonText else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(buttonText)
    }
}

// MARK: - TDNativeOrderInfo + @retroactive Hashable

extension TDNativeOrderInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.phoneNumber == rhs.phoneNumber else { return false }
        guard lhs.emailAddress == rhs.emailAddress else { return false }
        guard lhs.shippingAddress == rhs.shippingAddress else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(phoneNumber)
        hasher.combine(emailAddress)
        hasher.combine(shippingAddress)
    }
}

// MARK: - TDNativePageBlock + @retroactive Hashable

extension TDNativePageBlock: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.pageBlockTitle(let lhs), .pageBlockTitle(let rhs)):
            lhs == rhs
        case (.pageBlockSubtitle(let lhs), .pageBlockSubtitle(let rhs)):
            lhs == rhs
        case (.pageBlockAuthorDate(let lhs), .pageBlockAuthorDate(let rhs)):
            lhs == rhs
        case (.pageBlockHeader(let lhs), .pageBlockHeader(let rhs)):
            lhs == rhs
        case (.pageBlockSubheader(let lhs), .pageBlockSubheader(let rhs)):
            lhs == rhs
        case (.pageBlockSectionHeading(let lhs), .pageBlockSectionHeading(let rhs)):
            lhs == rhs
        case (.pageBlockKicker(let lhs), .pageBlockKicker(let rhs)):
            lhs == rhs
        case (.pageBlockParagraph(let lhs), .pageBlockParagraph(let rhs)):
            lhs == rhs
        case (.pageBlockPreformatted(let lhs), .pageBlockPreformatted(let rhs)):
            lhs == rhs
        case (.pageBlockFooter(let lhs), .pageBlockFooter(let rhs)):
            lhs == rhs
        case (.pageBlockThinking(let lhs), .pageBlockThinking(let rhs)):
            lhs == rhs
        case (.pageBlockDivider, .pageBlockDivider):
            true
        case (.pageBlockMathematicalExpression(let lhs), .pageBlockMathematicalExpression(let rhs)):
            lhs == rhs
        case (.pageBlockAnchor(let lhs), .pageBlockAnchor(let rhs)):
            lhs == rhs
        case (.pageBlockList(let lhs), .pageBlockList(let rhs)):
            lhs == rhs
        case (.pageBlockBlockQuote(let lhs), .pageBlockBlockQuote(let rhs)):
            lhs == rhs
        case (.pageBlockExpandableBlockQuote(let lhs), .pageBlockExpandableBlockQuote(let rhs)):
            lhs == rhs
        case (.pageBlockPullQuote(let lhs), .pageBlockPullQuote(let rhs)):
            lhs == rhs
        case (.pageBlockAnimation(let lhs), .pageBlockAnimation(let rhs)):
            lhs == rhs
        case (.pageBlockAudio(let lhs), .pageBlockAudio(let rhs)):
            lhs == rhs
        case (.pageBlockDocument(let lhs), .pageBlockDocument(let rhs)):
            lhs == rhs
        case (.pageBlockPhoto(let lhs), .pageBlockPhoto(let rhs)):
            lhs == rhs
        case (.pageBlockVideo(let lhs), .pageBlockVideo(let rhs)):
            lhs == rhs
        case (.pageBlockVoiceNote(let lhs), .pageBlockVoiceNote(let rhs)):
            lhs == rhs
        case (.pageBlockCover(let lhs), .pageBlockCover(let rhs)):
            lhs == rhs
        case (.pageBlockEmbedded(let lhs), .pageBlockEmbedded(let rhs)):
            lhs == rhs
        case (.pageBlockEmbeddedPost(let lhs), .pageBlockEmbeddedPost(let rhs)):
            lhs == rhs
        case (.pageBlockCollage(let lhs), .pageBlockCollage(let rhs)):
            lhs == rhs
        case (.pageBlockSlideshow(let lhs), .pageBlockSlideshow(let rhs)):
            lhs == rhs
        case (.pageBlockChatLink(let lhs), .pageBlockChatLink(let rhs)):
            lhs == rhs
        case (.pageBlockTable(let lhs), .pageBlockTable(let rhs)):
            lhs == rhs
        case (.pageBlockDetails(let lhs), .pageBlockDetails(let rhs)):
            lhs == rhs
        case (.pageBlockRelatedArticles(let lhs), .pageBlockRelatedArticles(let rhs)):
            lhs == rhs
        case (.pageBlockMap(let lhs), .pageBlockMap(let rhs)):
            lhs == rhs
        case (.pageBlockButtonRow(let lhs), .pageBlockButtonRow(let rhs)):
            lhs == rhs
        case (.pageBlockUnsupported, .pageBlockUnsupported):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .pageBlockTitle(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .pageBlockSubtitle(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .pageBlockAuthorDate(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .pageBlockHeader(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .pageBlockSubheader(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .pageBlockSectionHeading(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .pageBlockKicker(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .pageBlockParagraph(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .pageBlockPreformatted(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .pageBlockFooter(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .pageBlockThinking(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .pageBlockDivider:
            hasher.combine(11)
        case .pageBlockMathematicalExpression(let value):
            hasher.combine(12)
            hasher.combine(value)
        case .pageBlockAnchor(let value):
            hasher.combine(13)
            hasher.combine(value)
        case .pageBlockList(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .pageBlockBlockQuote(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .pageBlockExpandableBlockQuote(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .pageBlockPullQuote(let value):
            hasher.combine(17)
            hasher.combine(value)
        case .pageBlockAnimation(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .pageBlockAudio(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .pageBlockDocument(let value):
            hasher.combine(20)
            hasher.combine(value)
        case .pageBlockPhoto(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .pageBlockVideo(let value):
            hasher.combine(22)
            hasher.combine(value)
        case .pageBlockVoiceNote(let value):
            hasher.combine(23)
            hasher.combine(value)
        case .pageBlockCover(let value):
            hasher.combine(24)
            hasher.combine(value)
        case .pageBlockEmbedded(let value):
            hasher.combine(25)
            hasher.combine(value)
        case .pageBlockEmbeddedPost(let value):
            hasher.combine(26)
            hasher.combine(value)
        case .pageBlockCollage(let value):
            hasher.combine(27)
            hasher.combine(value)
        case .pageBlockSlideshow(let value):
            hasher.combine(28)
            hasher.combine(value)
        case .pageBlockChatLink(let value):
            hasher.combine(29)
            hasher.combine(value)
        case .pageBlockTable(let value):
            hasher.combine(30)
            hasher.combine(value)
        case .pageBlockDetails(let value):
            hasher.combine(31)
            hasher.combine(value)
        case .pageBlockRelatedArticles(let value):
            hasher.combine(32)
            hasher.combine(value)
        case .pageBlockMap(let value):
            hasher.combine(33)
            hasher.combine(value)
        case .pageBlockButtonRow(let value):
            hasher.combine(34)
            hasher.combine(value)
        case .pageBlockUnsupported:
            hasher.combine(35)
        }
    }
}

// MARK: - TDNativePageBlockAnchor + @retroactive Hashable

extension TDNativePageBlockAnchor: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - TDNativePageBlockAnimation + @retroactive Hashable

extension TDNativePageBlockAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animation == rhs.animation else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.needAutoplay == rhs.needAutoplay else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
        hasher.combine(caption)
        hasher.combine(needAutoplay)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativePageBlockAudio + @retroactive Hashable

extension TDNativePageBlockAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
        hasher.combine(caption)
    }
}

// MARK: - TDNativePageBlockAuthorDate + @retroactive Hashable

extension TDNativePageBlockAuthorDate: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.author == rhs.author else { return false }
        guard lhs.publishDate == rhs.publishDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(author)
        hasher.combine(publishDate)
    }
}

// MARK: - TDNativePageBlockBlockQuote + @retroactive Hashable

extension TDNativePageBlockBlockQuote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.credit == rhs.credit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(credit)
    }
}

// MARK: - TDNativePageBlockButtonRow + @retroactive Hashable

extension TDNativePageBlockButtonRow: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.buttons == rhs.buttons else { return false }
        guard lhs.align == rhs.align else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(buttons)
        hasher.combine(align)
    }
}

// MARK: - TDNativePageBlockCaption + @retroactive Hashable

extension TDNativePageBlockCaption: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.credit == rhs.credit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(credit)
    }
}

// MARK: - TDNativePageBlockChatLink + @retroactive Hashable

extension TDNativePageBlockChatLink: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.accentColorId == rhs.accentColorId else { return false }
        guard lhs.username == rhs.username else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(photo)
        hasher.combine(accentColorId)
        hasher.combine(username)
    }
}

// MARK: - TDNativePageBlockCollage + @retroactive Hashable

extension TDNativePageBlockCollage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(caption)
    }
}

// MARK: - TDNativePageBlockCover + @retroactive Hashable

extension TDNativePageBlockCover: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.cover == rhs.cover else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cover)
    }
}

// MARK: - TDNativePageBlockDetails + @retroactive Hashable

extension TDNativePageBlockDetails: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.header == rhs.header else { return false }
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.isOpen == rhs.isOpen else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(header)
        hasher.combine(blocks)
        hasher.combine(isOpen)
    }
}

// MARK: - TDNativePageBlockDocument + @retroactive Hashable

extension TDNativePageBlockDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
        hasher.combine(caption)
    }
}

// MARK: - TDNativePageBlockEmbedded + @retroactive Hashable

extension TDNativePageBlockEmbedded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.html == rhs.html else { return false }
        guard lhs.posterPhoto == rhs.posterPhoto else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.isFullWidth == rhs.isFullWidth else { return false }
        guard lhs.allowScrolling == rhs.allowScrolling else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(html)
        hasher.combine(posterPhoto)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(caption)
        hasher.combine(isFullWidth)
        hasher.combine(allowScrolling)
    }
}

// MARK: - TDNativePageBlockEmbeddedPost + @retroactive Hashable

extension TDNativePageBlockEmbeddedPost: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.author == rhs.author else { return false }
        guard lhs.authorPhoto == rhs.authorPhoto else { return false }
        guard lhs.date == rhs.date else { return false }
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(author)
        hasher.combine(authorPhoto)
        hasher.combine(date)
        hasher.combine(blocks)
        hasher.combine(caption)
    }
}

// MARK: - TDNativePageBlockExpandableBlockQuote + @retroactive Hashable

extension TDNativePageBlockExpandableBlockQuote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.credit == rhs.credit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(credit)
    }
}

// MARK: - TDNativePageBlockFooter + @retroactive Hashable

extension TDNativePageBlockFooter: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.footer == rhs.footer else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(footer)
    }
}

// MARK: - TDNativePageBlockHeader + @retroactive Hashable

extension TDNativePageBlockHeader: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.header == rhs.header else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(header)
    }
}

// MARK: - TDNativePageBlockKicker + @retroactive Hashable

extension TDNativePageBlockKicker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.kicker == rhs.kicker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kicker)
    }
}

// MARK: - TDNativePageBlockList + @retroactive Hashable

extension TDNativePageBlockList: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.items == rhs.items else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(items)
    }
}

// MARK: - TDNativePageBlockListItem + @retroactive Hashable

extension TDNativePageBlockListItem: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.label == rhs.label else { return false }
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.hasCheckbox == rhs.hasCheckbox else { return false }
        guard lhs.isChecked == rhs.isChecked else { return false }
        guard lhs.value == rhs.value else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(blocks)
        hasher.combine(hasCheckbox)
        hasher.combine(isChecked)
        hasher.combine(value)
        hasher.combine(type)
    }
}

// MARK: - TDNativePageBlockMap + @retroactive Hashable

extension TDNativePageBlockMap: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        guard lhs.zoom == rhs.zoom else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(zoom)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(caption)
    }
}

// MARK: - TDNativePageBlockMathematicalExpression + @retroactive Hashable

extension TDNativePageBlockMathematicalExpression: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.expression == rhs.expression else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(expression)
    }
}

// MARK: - TDNativePageBlockParagraph + @retroactive Hashable

extension TDNativePageBlockParagraph: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativePageBlockPhoto + @retroactive Hashable

extension TDNativePageBlockPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.url == rhs.url else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(caption)
        hasher.combine(url)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativePageBlockPreformatted + @retroactive Hashable

extension TDNativePageBlockPreformatted: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.language == rhs.language else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(language)
    }
}

// MARK: - TDNativePageBlockPullQuote + @retroactive Hashable

extension TDNativePageBlockPullQuote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.credit == rhs.credit else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(credit)
    }
}

// MARK: - TDNativePageBlockRelatedArticle + @retroactive Hashable

extension TDNativePageBlockRelatedArticle: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.author == rhs.author else { return false }
        guard lhs.publishDate == rhs.publishDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(title)
        hasher.combine(description)
        hasher.combine(photo)
        hasher.combine(author)
        hasher.combine(publishDate)
    }
}

// MARK: - TDNativePageBlockRelatedArticles + @retroactive Hashable

extension TDNativePageBlockRelatedArticles: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.header == rhs.header else { return false }
        guard lhs.articles == rhs.articles else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(header)
        hasher.combine(articles)
    }
}

// MARK: - TDNativePageBlockSectionHeading + @retroactive Hashable

extension TDNativePageBlockSectionHeading: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.size == rhs.size else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(size)
    }
}

// MARK: - TDNativePageBlockSlideshow + @retroactive Hashable

extension TDNativePageBlockSlideshow: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(caption)
    }
}

// MARK: - TDNativePageBlockSubheader + @retroactive Hashable

extension TDNativePageBlockSubheader: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subheader == rhs.subheader else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subheader)
    }
}

// MARK: - TDNativePageBlockSubtitle + @retroactive Hashable

extension TDNativePageBlockSubtitle: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subtitle == rhs.subtitle else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subtitle)
    }
}

// MARK: - TDNativePageBlockTable + @retroactive Hashable

extension TDNativePageBlockTable: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.cells == rhs.cells else { return false }
        guard lhs.isBordered == rhs.isBordered else { return false }
        guard lhs.isStriped == rhs.isStriped else { return false }
        guard lhs.isCompact == rhs.isCompact else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(caption)
        hasher.combine(cells)
        hasher.combine(isBordered)
        hasher.combine(isStriped)
        hasher.combine(isCompact)
    }
}

// MARK: - TDNativePageBlockTableCell + @retroactive Hashable

extension TDNativePageBlockTableCell: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.isHeader == rhs.isHeader else { return false }
        guard lhs.colspan == rhs.colspan else { return false }
        guard lhs.rowspan == rhs.rowspan else { return false }
        guard lhs.align == rhs.align else { return false }
        guard lhs.valign == rhs.valign else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(isHeader)
        hasher.combine(colspan)
        hasher.combine(rowspan)
        hasher.combine(align)
        hasher.combine(valign)
    }
}

// MARK: - TDNativePageBlockThinking + @retroactive Hashable

extension TDNativePageBlockThinking: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativePageBlockTitle + @retroactive Hashable

extension TDNativePageBlockTitle: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }
}

// MARK: - TDNativePageBlockVideo + @retroactive Hashable

extension TDNativePageBlockVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        guard lhs.caption == rhs.caption else { return false }
        guard lhs.needAutoplay == rhs.needAutoplay else { return false }
        guard lhs.isLooped == rhs.isLooped else { return false }
        guard lhs.hasSpoiler == rhs.hasSpoiler else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(caption)
        hasher.combine(needAutoplay)
        hasher.combine(isLooped)
        hasher.combine(hasSpoiler)
    }
}

// MARK: - TDNativePageBlockVoiceNote + @retroactive Hashable

extension TDNativePageBlockVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.voiceNote == rhs.voiceNote else { return false }
        guard lhs.caption == rhs.caption else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceNote)
        hasher.combine(caption)
    }
}

// MARK: - TDNativePaidMedia + @retroactive Hashable

extension TDNativePaidMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.paidMediaPreview(let lhs), .paidMediaPreview(let rhs)):
            lhs == rhs
        case (.paidMediaPhoto(let lhs), .paidMediaPhoto(let rhs)):
            lhs == rhs
        case (.paidMediaVideo(let lhs), .paidMediaVideo(let rhs)):
            lhs == rhs
        case (.paidMediaUnsupported, .paidMediaUnsupported):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .paidMediaPreview(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .paidMediaPhoto(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .paidMediaVideo(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .paidMediaUnsupported:
            hasher.combine(3)
        }
    }
}

// MARK: - TDNativePaidMediaPhoto + @retroactive Hashable

extension TDNativePaidMediaPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.video == rhs.video else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(video)
    }
}

// MARK: - TDNativePaidMediaPreview + @retroactive Hashable

extension TDNativePaidMediaPreview: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.minithumbnail == rhs.minithumbnail else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(duration)
        hasher.combine(minithumbnail)
    }
}

// MARK: - TDNativePaidMediaVideo + @retroactive Hashable

extension TDNativePaidMediaVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        guard lhs.cover == rhs.cover else { return false }
        guard lhs.startTimestamp == rhs.startTimestamp else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(cover)
        hasher.combine(startTimestamp)
    }
}

// MARK: - TDNativePoll + @retroactive Hashable

extension TDNativePoll: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.question == rhs.question else { return false }
        guard lhs.options == rhs.options else { return false }
        guard lhs.totalVoterCount == rhs.totalVoterCount else { return false }
        guard lhs.recentVoterIds == rhs.recentVoterIds else { return false }
        guard lhs.canGetVoters == rhs.canGetVoters else { return false }
        guard lhs.canSeeResults == rhs.canSeeResults else { return false }
        guard lhs.isAnonymous == rhs.isAnonymous else { return false }
        guard lhs.allowsMultipleAnswers == rhs.allowsMultipleAnswers else { return false }
        guard lhs.allowsRevoting == rhs.allowsRevoting else { return false }
        guard lhs.membersOnly == rhs.membersOnly else { return false }
        guard lhs.countryCodes == rhs.countryCodes else { return false }
        guard lhs.optionOrder == rhs.optionOrder else { return false }
        guard lhs.type == rhs.type else { return false }
        guard lhs.openPeriod == rhs.openPeriod else { return false }
        guard lhs.closeDate == rhs.closeDate else { return false }
        guard lhs.isClosed == rhs.isClosed else { return false }
        guard lhs.voteRestrictionReason == rhs.voteRestrictionReason else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(question)
        hasher.combine(options)
        hasher.combine(totalVoterCount)
        hasher.combine(recentVoterIds)
        hasher.combine(canGetVoters)
        hasher.combine(canSeeResults)
        hasher.combine(isAnonymous)
        hasher.combine(allowsMultipleAnswers)
        hasher.combine(allowsRevoting)
        hasher.combine(membersOnly)
        hasher.combine(countryCodes)
        hasher.combine(optionOrder)
        hasher.combine(type)
        hasher.combine(openPeriod)
        hasher.combine(closeDate)
        hasher.combine(isClosed)
        hasher.combine(voteRestrictionReason)
    }
}

// MARK: - TDNativePollMedia + @retroactive Hashable

extension TDNativePollMedia: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.pollMediaAnimation(let lhs), .pollMediaAnimation(let rhs)):
            lhs == rhs
        case (.pollMediaAudio(let lhs), .pollMediaAudio(let rhs)):
            lhs == rhs
        case (.pollMediaDocument(let lhs), .pollMediaDocument(let rhs)):
            lhs == rhs
        case (.pollMediaLink(let lhs), .pollMediaLink(let rhs)):
            lhs == rhs
        case (.pollMediaLocation(let lhs), .pollMediaLocation(let rhs)):
            lhs == rhs
        case (.pollMediaPhoto(let lhs), .pollMediaPhoto(let rhs)):
            lhs == rhs
        case (.pollMediaSticker(let lhs), .pollMediaSticker(let rhs)):
            lhs == rhs
        case (.pollMediaVenue(let lhs), .pollMediaVenue(let rhs)):
            lhs == rhs
        case (.pollMediaVideo(let lhs), .pollMediaVideo(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .pollMediaAnimation(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .pollMediaAudio(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .pollMediaDocument(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .pollMediaLink(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .pollMediaLocation(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .pollMediaPhoto(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .pollMediaSticker(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .pollMediaVenue(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .pollMediaVideo(let value):
            hasher.combine(8)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativePollMediaAnimation + @retroactive Hashable

extension TDNativePollMediaAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.animation == rhs.animation else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
    }
}

// MARK: - TDNativePollMediaAudio + @retroactive Hashable

extension TDNativePollMediaAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.audio == rhs.audio else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(audio)
    }
}

// MARK: - TDNativePollMediaDocument + @retroactive Hashable

extension TDNativePollMediaDocument: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
    }
}

// MARK: - TDNativePollMediaLink + @retroactive Hashable

extension TDNativePollMediaLink: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.url == rhs.url else { return false }
        guard lhs.linkPreview == rhs.linkPreview else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(linkPreview)
    }
}

// MARK: - TDNativePollMediaLocation + @retroactive Hashable

extension TDNativePollMediaLocation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
    }
}

// MARK: - TDNativePollMediaPhoto + @retroactive Hashable

extension TDNativePollMediaPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.video == rhs.video else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(video)
    }
}

// MARK: - TDNativePollMediaSticker + @retroactive Hashable

extension TDNativePollMediaSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sticker == rhs.sticker else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
    }
}

// MARK: - TDNativePollMediaVenue + @retroactive Hashable

extension TDNativePollMediaVenue: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.venue == rhs.venue else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(venue)
    }
}

// MARK: - TDNativePollMediaVideo + @retroactive Hashable

extension TDNativePollMediaVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.video == rhs.video else { return false }
        guard lhs.alternativeVideos == rhs.alternativeVideos else { return false }
        guard lhs.storyboards == rhs.storyboards else { return false }
        guard lhs.cover == rhs.cover else { return false }
        guard lhs.startTimestamp == rhs.startTimestamp else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(alternativeVideos)
        hasher.combine(storyboards)
        hasher.combine(cover)
        hasher.combine(startTimestamp)
    }
}

// MARK: - TDNativePollOption + @retroactive Hashable

extension TDNativePollOption: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.media == rhs.media else { return false }
        guard lhs.voterCount == rhs.voterCount else { return false }
        guard lhs.votePercentage == rhs.votePercentage else { return false }
        guard lhs.recentVoterIds == rhs.recentVoterIds else { return false }
        guard lhs.isChosen == rhs.isChosen else { return false }
        guard lhs.isBeingChosen == rhs.isBeingChosen else { return false }
        guard lhs.author == rhs.author else { return false }
        guard lhs.additionDate == rhs.additionDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(text)
        hasher.combine(media)
        hasher.combine(voterCount)
        hasher.combine(votePercentage)
        hasher.combine(recentVoterIds)
        hasher.combine(isChosen)
        hasher.combine(isBeingChosen)
        hasher.combine(author)
        hasher.combine(additionDate)
    }
}

// MARK: - TDNativePollType + @retroactive Hashable

extension TDNativePollType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.pollTypeRegular, .pollTypeRegular):
            true
        case (.pollTypeQuiz(let lhs), .pollTypeQuiz(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .pollTypeRegular:
            hasher.combine(0)
        case .pollTypeQuiz(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativePollTypeQuiz + @retroactive Hashable

extension TDNativePollTypeQuiz: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.correctOptionIds == rhs.correctOptionIds else { return false }
        guard lhs.explanation == rhs.explanation else { return false }
        guard lhs.explanationMedia == rhs.explanationMedia else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(correctOptionIds)
        hasher.combine(explanation)
        hasher.combine(explanationMedia)
    }
}

// MARK: - TDNativePollVoteRestrictionReason + @retroactive Hashable

extension TDNativePollVoteRestrictionReason: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.pollVoteRestrictionReasonClosed, .pollVoteRestrictionReasonClosed):
            true
        case (.pollVoteRestrictionReasonYetUnsent, .pollVoteRestrictionReasonYetUnsent):
            true
        case (.pollVoteRestrictionReasonScheduled, .pollVoteRestrictionReasonScheduled):
            true
        case (
            .pollVoteRestrictionReasonCountryRestricted(let lhs),
            .pollVoteRestrictionReasonCountryRestricted(let rhs),
        ):
            lhs == rhs
        case (
            .pollVoteRestrictionReasonMembershipRequired(let lhs),
            .pollVoteRestrictionReasonMembershipRequired(let rhs),
        ):
            lhs == rhs
        case (.pollVoteRestrictionReasonOther, .pollVoteRestrictionReasonOther):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .pollVoteRestrictionReasonClosed:
            hasher.combine(0)
        case .pollVoteRestrictionReasonYetUnsent:
            hasher.combine(1)
        case .pollVoteRestrictionReasonScheduled:
            hasher.combine(2)
        case .pollVoteRestrictionReasonCountryRestricted(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .pollVoteRestrictionReasonMembershipRequired(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .pollVoteRestrictionReasonOther:
            hasher.combine(5)
        }
    }
}

// MARK: - TDNativePollVoteRestrictionReasonCountryRestricted + @retroactive Hashable

extension TDNativePollVoteRestrictionReasonCountryRestricted: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.countryCode == rhs.countryCode else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(countryCode)
    }
}

// MARK: - TDNativePollVoteRestrictionReasonMembershipRequired + @retroactive Hashable

extension TDNativePollVoteRestrictionReasonMembershipRequired: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatId == rhs.chatId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
    }
}

// MARK: - TDNativeProductInfo + @retroactive Hashable

extension TDNativeProductInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.title == rhs.title else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(description)
        hasher.combine(photo)
    }
}

// MARK: - TDNativeProfilePhoto + @retroactive Hashable

extension TDNativeProfilePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.small == rhs.small else { return false }
        guard lhs.big == rhs.big else { return false }
        guard lhs.minithumbnail == rhs.minithumbnail else { return false }
        guard lhs.hasAnimation == rhs.hasAnimation else { return false }
        guard lhs.isPersonal == rhs.isPersonal else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(small)
        hasher.combine(big)
        hasher.combine(minithumbnail)
        hasher.combine(hasAnimation)
        hasher.combine(isPersonal)
    }
}

// MARK: - TDNativeProxy + @retroactive Hashable

extension TDNativeProxy: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.server == rhs.server else { return false }
        guard lhs.port == rhs.port else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(server)
        hasher.combine(port)
        hasher.combine(type)
    }
}

// MARK: - TDNativeProxyType + @retroactive Hashable

extension TDNativeProxyType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.proxyTypeSocks5(let lhs), .proxyTypeSocks5(let rhs)):
            lhs == rhs
        case (.proxyTypeHttp(let lhs), .proxyTypeHttp(let rhs)):
            lhs == rhs
        case (.proxyTypeMtproto(let lhs), .proxyTypeMtproto(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .proxyTypeSocks5(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .proxyTypeHttp(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .proxyTypeMtproto(let value):
            hasher.combine(2)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeProxyTypeHttp + @retroactive Hashable

extension TDNativeProxyTypeHttp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.username == rhs.username else { return false }
        guard lhs.password == rhs.password else { return false }
        guard lhs.httpOnly == rhs.httpOnly else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(username)
        hasher.combine(password)
        hasher.combine(httpOnly)
    }
}

// MARK: - TDNativeProxyTypeMtproto + @retroactive Hashable

extension TDNativeProxyTypeMtproto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.secret == rhs.secret else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(secret)
    }
}

// MARK: - TDNativeProxyTypeSocks5 + @retroactive Hashable

extension TDNativeProxyTypeSocks5: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.username == rhs.username else { return false }
        guard lhs.password == rhs.password else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(username)
        hasher.combine(password)
    }
}

// MARK: - TDNativeReplyMarkup + @retroactive Hashable

extension TDNativeReplyMarkup: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.replyMarkupRemoveKeyboard(let lhs), .replyMarkupRemoveKeyboard(let rhs)):
            lhs == rhs
        case (.replyMarkupForceReply(let lhs), .replyMarkupForceReply(let rhs)):
            lhs == rhs
        case (.replyMarkupShowKeyboard(let lhs), .replyMarkupShowKeyboard(let rhs)):
            lhs == rhs
        case (.replyMarkupInlineKeyboard(let lhs), .replyMarkupInlineKeyboard(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .replyMarkupRemoveKeyboard(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .replyMarkupForceReply(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .replyMarkupShowKeyboard(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .replyMarkupInlineKeyboard(let value):
            hasher.combine(3)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeReplyMarkupForceReply + @retroactive Hashable

extension TDNativeReplyMarkupForceReply: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isPersonal == rhs.isPersonal else { return false }
        guard lhs.inputFieldPlaceholder == rhs.inputFieldPlaceholder else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isPersonal)
        hasher.combine(inputFieldPlaceholder)
    }
}

// MARK: - TDNativeReplyMarkupInlineKeyboard + @retroactive Hashable

extension TDNativeReplyMarkupInlineKeyboard: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.rows == rhs.rows else { return false }
        guard lhs.forceReply == rhs.forceReply else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rows)
        hasher.combine(forceReply)
    }
}

// MARK: - TDNativeReplyMarkupRemoveKeyboard + @retroactive Hashable

extension TDNativeReplyMarkupRemoveKeyboard: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isPersonal == rhs.isPersonal else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isPersonal)
    }
}

// MARK: - TDNativeReplyMarkupShowKeyboard + @retroactive Hashable

extension TDNativeReplyMarkupShowKeyboard: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.rows == rhs.rows else { return false }
        guard lhs.isPersistent == rhs.isPersistent else { return false }
        guard lhs.resizeKeyboard == rhs.resizeKeyboard else { return false }
        guard lhs.oneTime == rhs.oneTime else { return false }
        guard lhs.isPersonal == rhs.isPersonal else { return false }
        guard lhs.forceReply == rhs.forceReply else { return false }
        guard lhs.inputFieldPlaceholder == rhs.inputFieldPlaceholder else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rows)
        hasher.combine(isPersistent)
        hasher.combine(resizeKeyboard)
        hasher.combine(oneTime)
        hasher.combine(isPersonal)
        hasher.combine(forceReply)
        hasher.combine(inputFieldPlaceholder)
    }
}

// MARK: - TDNativeRestrictionInfo + @retroactive Hashable

extension TDNativeRestrictionInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.restrictionReason == rhs.restrictionReason else { return false }
        guard lhs.hasSensitiveContent == rhs.hasSensitiveContent else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(restrictionReason)
        hasher.combine(hasSensitiveContent)
    }
}

// MARK: - TDNativeRichMessage + @retroactive Hashable

extension TDNativeRichMessage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        guard lhs.isRtl == rhs.isRtl else { return false }
        guard lhs.isFull == rhs.isFull else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
        hasher.combine(isRtl)
        hasher.combine(isFull)
    }
}

// MARK: - TDNativeRichMessageSource + @retroactive Hashable

extension TDNativeRichMessageSource: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.richMessageSourceBlocks(let lhs), .richMessageSourceBlocks(let rhs)):
            lhs == rhs
        case (.richMessageSourceMarkdown(let lhs), .richMessageSourceMarkdown(let rhs)):
            lhs == rhs
        case (.richMessageSourceHtml(let lhs), .richMessageSourceHtml(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .richMessageSourceBlocks(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .richMessageSourceMarkdown(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .richMessageSourceHtml(let value):
            hasher.combine(2)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeRichMessageSourceBlocks + @retroactive Hashable

extension TDNativeRichMessageSourceBlocks: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.blocks == rhs.blocks else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blocks)
    }
}

// MARK: - TDNativeRichMessageSourceHtml + @retroactive Hashable

extension TDNativeRichMessageSourceHtml: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.media == rhs.media else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(media)
    }
}

// MARK: - TDNativeRichMessageSourceMarkdown + @retroactive Hashable

extension TDNativeRichMessageSourceMarkdown: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.media == rhs.media else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(media)
    }
}

// MARK: - TDNativeRichText + @retroactive Hashable

extension TDNativeRichText: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.richTextPlain(let lhs), .richTextPlain(let rhs)):
            lhs == rhs
        case (.richTextBold(let lhs), .richTextBold(let rhs)):
            lhs == rhs
        case (.richTextItalic(let lhs), .richTextItalic(let rhs)):
            lhs == rhs
        case (.richTextUnderline(let lhs), .richTextUnderline(let rhs)):
            lhs == rhs
        case (.richTextStrikethrough(let lhs), .richTextStrikethrough(let rhs)):
            lhs == rhs
        case (.richTextSpoiler(let lhs), .richTextSpoiler(let rhs)):
            lhs == rhs
        case (.richTextSubscript(let lhs), .richTextSubscript(let rhs)):
            lhs == rhs
        case (.richTextSuperscript(let lhs), .richTextSuperscript(let rhs)):
            lhs == rhs
        case (.richTextMarked(let lhs), .richTextMarked(let rhs)):
            lhs == rhs
        case (.richTextDateTime(let lhs), .richTextDateTime(let rhs)):
            lhs == rhs
        case (.richTextMention(let lhs), .richTextMention(let rhs)):
            lhs == rhs
        case (.richTextHashtag(let lhs), .richTextHashtag(let rhs)):
            lhs == rhs
        case (.richTextCashtag(let lhs), .richTextCashtag(let rhs)):
            lhs == rhs
        case (.richTextBankCardNumber(let lhs), .richTextBankCardNumber(let rhs)):
            lhs == rhs
        case (.richTextBotCommand(let lhs), .richTextBotCommand(let rhs)):
            lhs == rhs
        case (.richTextFixed(let lhs), .richTextFixed(let rhs)):
            lhs == rhs
        case (.richTextMentionName(let lhs), .richTextMentionName(let rhs)):
            lhs == rhs
        case (.richTextUrl(let lhs), .richTextUrl(let rhs)):
            lhs == rhs
        case (.richTextEmailAddress(let lhs), .richTextEmailAddress(let rhs)):
            lhs == rhs
        case (.richTextPhoneNumber(let lhs), .richTextPhoneNumber(let rhs)):
            lhs == rhs
        case (.richTextCustomEmoji(let lhs), .richTextCustomEmoji(let rhs)):
            lhs == rhs
        case (.richTextIcon(let lhs), .richTextIcon(let rhs)):
            lhs == rhs
        case (.richTextMathematicalExpression(let lhs), .richTextMathematicalExpression(let rhs)):
            lhs == rhs
        case (.richTextButton(let lhs), .richTextButton(let rhs)):
            lhs == rhs
        case (.richTextDiff(let lhs), .richTextDiff(let rhs)):
            lhs == rhs
        case (.richTextReference(let lhs), .richTextReference(let rhs)):
            lhs == rhs
        case (.richTextReferenceLink(let lhs), .richTextReferenceLink(let rhs)):
            lhs == rhs
        case (.richTextAnchor(let lhs), .richTextAnchor(let rhs)):
            lhs == rhs
        case (.richTextAnchorLink(let lhs), .richTextAnchorLink(let rhs)):
            lhs == rhs
        case (.richTexts(let lhs), .richTexts(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .richTextPlain(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .richTextBold(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .richTextItalic(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .richTextUnderline(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .richTextStrikethrough(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .richTextSpoiler(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .richTextSubscript(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .richTextSuperscript(let value):
            hasher.combine(7)
            hasher.combine(value)
        case .richTextMarked(let value):
            hasher.combine(8)
            hasher.combine(value)
        case .richTextDateTime(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .richTextMention(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .richTextHashtag(let value):
            hasher.combine(11)
            hasher.combine(value)
        case .richTextCashtag(let value):
            hasher.combine(12)
            hasher.combine(value)
        case .richTextBankCardNumber(let value):
            hasher.combine(13)
            hasher.combine(value)
        case .richTextBotCommand(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .richTextFixed(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .richTextMentionName(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .richTextUrl(let value):
            hasher.combine(17)
            hasher.combine(value)
        case .richTextEmailAddress(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .richTextPhoneNumber(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .richTextCustomEmoji(let value):
            hasher.combine(20)
            hasher.combine(value)
        case .richTextIcon(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .richTextMathematicalExpression(let value):
            hasher.combine(22)
            hasher.combine(value)
        case .richTextButton(let value):
            hasher.combine(23)
            hasher.combine(value)
        case .richTextDiff(let value):
            hasher.combine(24)
            hasher.combine(value)
        case .richTextReference(let value):
            hasher.combine(25)
            hasher.combine(value)
        case .richTextReferenceLink(let value):
            hasher.combine(26)
            hasher.combine(value)
        case .richTextAnchor(let value):
            hasher.combine(27)
            hasher.combine(value)
        case .richTextAnchorLink(let value):
            hasher.combine(28)
            hasher.combine(value)
        case .richTexts(let value):
            hasher.combine(29)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeRichTextAnchor + @retroactive Hashable

extension TDNativeRichTextAnchor: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - TDNativeRichTextAnchorLink + @retroactive Hashable

extension TDNativeRichTextAnchorLink: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.anchorName == rhs.anchorName else { return false }
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(anchorName)
        hasher.combine(url)
    }
}

// MARK: - TDNativeRichTextBankCardNumber + @retroactive Hashable

extension TDNativeRichTextBankCardNumber: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.bankCardNumber == rhs.bankCardNumber else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(bankCardNumber)
    }
}

// MARK: - TDNativeRichTextBold + @retroactive Hashable

extension TDNativeRichTextBold: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextBotCommand + @retroactive Hashable

extension TDNativeRichTextBotCommand: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.botCommand == rhs.botCommand else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(botCommand)
    }
}

// MARK: - TDNativeRichTextButton + @retroactive Hashable

extension TDNativeRichTextButton: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.button == rhs.button else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(button)
    }
}

// MARK: - TDNativeRichTextCashtag + @retroactive Hashable

extension TDNativeRichTextCashtag: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.cashtag == rhs.cashtag else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(cashtag)
    }
}

// MARK: - TDNativeRichTextCustomEmoji + @retroactive Hashable

extension TDNativeRichTextCustomEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.customEmojiId == rhs.customEmojiId else { return false }
        guard lhs.alternativeText == rhs.alternativeText else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(customEmojiId)
        hasher.combine(alternativeText)
    }
}

// MARK: - TDNativeRichTextDateTime + @retroactive Hashable

extension TDNativeRichTextDateTime: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.unixTime == rhs.unixTime else { return false }
        guard lhs.formattingType == rhs.formattingType else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(unixTime)
        hasher.combine(formattingType)
    }
}

// MARK: - TDNativeRichTextDiff + @retroactive Hashable

extension TDNativeRichTextDiff: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.oldText == rhs.oldText else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(oldText)
    }
}

// MARK: - TDNativeRichTextEmailAddress + @retroactive Hashable

extension TDNativeRichTextEmailAddress: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.emailAddress == rhs.emailAddress else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(emailAddress)
    }
}

// MARK: - TDNativeRichTextFixed + @retroactive Hashable

extension TDNativeRichTextFixed: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextHashtag + @retroactive Hashable

extension TDNativeRichTextHashtag: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.hashtag == rhs.hashtag else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(hashtag)
    }
}

// MARK: - TDNativeRichTextIcon + @retroactive Hashable

extension TDNativeRichTextIcon: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.document == rhs.document else { return false }
        guard lhs.width == rhs.width else { return false }
        guard lhs.height == rhs.height else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(document)
        hasher.combine(width)
        hasher.combine(height)
    }
}

// MARK: - TDNativeRichTextItalic + @retroactive Hashable

extension TDNativeRichTextItalic: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextMarked + @retroactive Hashable

extension TDNativeRichTextMarked: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextMathematicalExpression + @retroactive Hashable

extension TDNativeRichTextMathematicalExpression: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.expression == rhs.expression else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(expression)
    }
}

// MARK: - TDNativeRichTextMention + @retroactive Hashable

extension TDNativeRichTextMention: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.username == rhs.username else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(username)
    }
}

// MARK: - TDNativeRichTextMentionName + @retroactive Hashable

extension TDNativeRichTextMentionName: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.userId == rhs.userId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(userId)
    }
}

// MARK: - TDNativeRichTextPhoneNumber + @retroactive Hashable

extension TDNativeRichTextPhoneNumber: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.phoneNumber == rhs.phoneNumber else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(phoneNumber)
    }
}

// MARK: - TDNativeRichTextPlain + @retroactive Hashable

extension TDNativeRichTextPlain: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextReference + @retroactive Hashable

extension TDNativeRichTextReference: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextReferenceLink + @retroactive Hashable

extension TDNativeRichTextReferenceLink: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.referenceName == rhs.referenceName else { return false }
        guard lhs.url == rhs.url else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(referenceName)
        hasher.combine(url)
    }
}

// MARK: - TDNativeRichTextSpoiler + @retroactive Hashable

extension TDNativeRichTextSpoiler: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextStrikethrough + @retroactive Hashable

extension TDNativeRichTextStrikethrough: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextSubscript + @retroactive Hashable

extension TDNativeRichTextSubscript: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextSuperscript + @retroactive Hashable

extension TDNativeRichTextSuperscript: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextUnderline + @retroactive Hashable

extension TDNativeRichTextUnderline: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeRichTextUrl + @retroactive Hashable

extension TDNativeRichTextUrl: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.url == rhs.url else { return false }
        guard lhs.isCached == rhs.isCached else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(url)
        hasher.combine(isCached)
    }
}

// MARK: - TDNativeRichTexts + @retroactive Hashable

extension TDNativeRichTexts: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.texts == rhs.texts else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(texts)
    }
}

// MARK: - TDNativeSettingsSection + @retroactive Hashable

extension TDNativeSettingsSection: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.settingsSectionAppearance(let lhs), .settingsSectionAppearance(let rhs)):
            lhs == rhs
        case (.settingsSectionAskQuestion, .settingsSectionAskQuestion):
            true
        case (.settingsSectionBusiness(let lhs), .settingsSectionBusiness(let rhs)):
            lhs == rhs
        case (.settingsSectionChatFolders(let lhs), .settingsSectionChatFolders(let rhs)):
            lhs == rhs
        case (.settingsSectionDataAndStorage(let lhs), .settingsSectionDataAndStorage(let rhs)):
            lhs == rhs
        case (.settingsSectionDevices(let lhs), .settingsSectionDevices(let rhs)):
            lhs == rhs
        case (.settingsSectionEditProfile(let lhs), .settingsSectionEditProfile(let rhs)):
            lhs == rhs
        case (.settingsSectionFaq, .settingsSectionFaq):
            true
        case (.settingsSectionFeatures, .settingsSectionFeatures):
            true
        case (.settingsSectionInAppBrowser(let lhs), .settingsSectionInAppBrowser(let rhs)):
            lhs == rhs
        case (.settingsSectionLanguage(let lhs), .settingsSectionLanguage(let rhs)):
            lhs == rhs
        case (.settingsSectionMyStars(let lhs), .settingsSectionMyStars(let rhs)):
            lhs == rhs
        case (.settingsSectionMyGrams, .settingsSectionMyGrams):
            true
        case (.settingsSectionNotifications(let lhs), .settingsSectionNotifications(let rhs)):
            lhs == rhs
        case (.settingsSectionPowerSaving(let lhs), .settingsSectionPowerSaving(let rhs)):
            lhs == rhs
        case (.settingsSectionPremium, .settingsSectionPremium):
            true
        case (.settingsSectionPrivacyAndSecurity(let lhs), .settingsSectionPrivacyAndSecurity(let rhs)):
            lhs == rhs
        case (.settingsSectionPrivacyPolicy, .settingsSectionPrivacyPolicy):
            true
        case (.settingsSectionQrCode(let lhs), .settingsSectionQrCode(let rhs)):
            lhs == rhs
        case (.settingsSectionSearch, .settingsSectionSearch):
            true
        case (.settingsSectionSendGift(let lhs), .settingsSectionSendGift(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .settingsSectionAppearance(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .settingsSectionAskQuestion:
            hasher.combine(1)
        case .settingsSectionBusiness(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .settingsSectionChatFolders(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .settingsSectionDataAndStorage(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .settingsSectionDevices(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .settingsSectionEditProfile(let value):
            hasher.combine(6)
            hasher.combine(value)
        case .settingsSectionFaq:
            hasher.combine(7)
        case .settingsSectionFeatures:
            hasher.combine(8)
        case .settingsSectionInAppBrowser(let value):
            hasher.combine(9)
            hasher.combine(value)
        case .settingsSectionLanguage(let value):
            hasher.combine(10)
            hasher.combine(value)
        case .settingsSectionMyStars(let value):
            hasher.combine(11)
            hasher.combine(value)
        case .settingsSectionMyGrams:
            hasher.combine(12)
        case .settingsSectionNotifications(let value):
            hasher.combine(13)
            hasher.combine(value)
        case .settingsSectionPowerSaving(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .settingsSectionPremium:
            hasher.combine(15)
        case .settingsSectionPrivacyAndSecurity(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .settingsSectionPrivacyPolicy:
            hasher.combine(17)
        case .settingsSectionQrCode(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .settingsSectionSearch:
            hasher.combine(19)
        case .settingsSectionSendGift(let value):
            hasher.combine(20)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeSettingsSectionAppearance + @retroactive Hashable

extension TDNativeSettingsSectionAppearance: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionBusiness + @retroactive Hashable

extension TDNativeSettingsSectionBusiness: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionChatFolders + @retroactive Hashable

extension TDNativeSettingsSectionChatFolders: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionDataAndStorage + @retroactive Hashable

extension TDNativeSettingsSectionDataAndStorage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionDevices + @retroactive Hashable

extension TDNativeSettingsSectionDevices: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionEditProfile + @retroactive Hashable

extension TDNativeSettingsSectionEditProfile: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionInAppBrowser + @retroactive Hashable

extension TDNativeSettingsSectionInAppBrowser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionLanguage + @retroactive Hashable

extension TDNativeSettingsSectionLanguage: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionMyStars + @retroactive Hashable

extension TDNativeSettingsSectionMyStars: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionNotifications + @retroactive Hashable

extension TDNativeSettingsSectionNotifications: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionPowerSaving + @retroactive Hashable

extension TDNativeSettingsSectionPowerSaving: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionPrivacyAndSecurity + @retroactive Hashable

extension TDNativeSettingsSectionPrivacyAndSecurity: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionQrCode + @retroactive Hashable

extension TDNativeSettingsSectionQrCode: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSettingsSectionSendGift + @retroactive Hashable

extension TDNativeSettingsSectionSendGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.subsection == rhs.subsection else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subsection)
    }
}

// MARK: - TDNativeSharedChat + @retroactive Hashable

extension TDNativeSharedChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatId == rhs.chatId else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.username == rhs.username else { return false }
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
        hasher.combine(title)
        hasher.combine(username)
        hasher.combine(photo)
    }
}

// MARK: - TDNativeSharedUser + @retroactive Hashable

extension TDNativeSharedUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.userId == rhs.userId else { return false }
        guard lhs.firstName == rhs.firstName else { return false }
        guard lhs.lastName == rhs.lastName else { return false }
        guard lhs.username == rhs.username else { return false }
        guard lhs.photo == rhs.photo else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
        hasher.combine(firstName)
        hasher.combine(lastName)
        hasher.combine(username)
        hasher.combine(photo)
    }
}

// MARK: - TDNativeSpeechRecognitionResult + @retroactive Hashable

extension TDNativeSpeechRecognitionResult: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.speechRecognitionResultPending(let lhs), .speechRecognitionResultPending(let rhs)):
            lhs == rhs
        case (.speechRecognitionResultText(let lhs), .speechRecognitionResultText(let rhs)):
            lhs == rhs
        case (.speechRecognitionResultError(let lhs), .speechRecognitionResultError(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .speechRecognitionResultPending(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .speechRecognitionResultText(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .speechRecognitionResultError(let value):
            hasher.combine(2)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeSpeechRecognitionResultError + @retroactive Hashable

extension TDNativeSpeechRecognitionResultError: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.error == rhs.error else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(error)
    }
}

// MARK: - TDNativeSpeechRecognitionResultPending + @retroactive Hashable

extension TDNativeSpeechRecognitionResultPending: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.partialText == rhs.partialText else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(partialText)
    }
}

// MARK: - TDNativeSpeechRecognitionResultText + @retroactive Hashable

extension TDNativeSpeechRecognitionResultText: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - TDNativeStarAmount + @retroactive Hashable

extension TDNativeStarAmount: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        guard lhs.nanostarCount == rhs.nanostarCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
        hasher.combine(nanostarCount)
    }
}

// MARK: - TDNativeSuggestedPostInfo + @retroactive Hashable

extension TDNativeSuggestedPostInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.price == rhs.price else { return false }
        guard lhs.sendDate == rhs.sendDate else { return false }
        guard lhs.state == rhs.state else { return false }
        guard lhs.canBeApproved == rhs.canBeApproved else { return false }
        guard lhs.canBeDeclined == rhs.canBeDeclined else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(price)
        hasher.combine(sendDate)
        hasher.combine(state)
        hasher.combine(canBeApproved)
        hasher.combine(canBeDeclined)
    }
}

// MARK: - TDNativeSuggestedPostPrice + @retroactive Hashable

extension TDNativeSuggestedPostPrice: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.suggestedPostPriceStar(let lhs), .suggestedPostPriceStar(let rhs)):
            lhs == rhs
        case (.suggestedPostPriceGram(let lhs), .suggestedPostPriceGram(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .suggestedPostPriceStar(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .suggestedPostPriceGram(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeSuggestedPostPriceGram + @retroactive Hashable

extension TDNativeSuggestedPostPriceGram: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gramCentCount == rhs.gramCentCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gramCentCount)
    }
}

// MARK: - TDNativeSuggestedPostPriceStar + @retroactive Hashable

extension TDNativeSuggestedPostPriceStar: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.starCount == rhs.starCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(starCount)
    }
}

// MARK: - TDNativeSupergroup + @retroactive Hashable

extension TDNativeSupergroup: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.usernames == rhs.usernames else { return false }
        guard lhs.date == rhs.date else { return false }
        guard lhs.status == rhs.status else { return false }
        guard lhs.memberCount == rhs.memberCount else { return false }
        guard lhs.boostLevel == rhs.boostLevel else { return false }
        guard lhs.hasAutomaticTranslation == rhs.hasAutomaticTranslation else { return false }
        guard lhs.hasLinkedChat == rhs.hasLinkedChat else { return false }
        guard lhs.hasLocation == rhs.hasLocation else { return false }
        guard lhs.signMessages == rhs.signMessages else { return false }
        guard lhs.showMessageSender == rhs.showMessageSender else { return false }
        guard lhs.joinToSendMessages == rhs.joinToSendMessages else { return false }
        guard lhs.joinByRequest == rhs.joinByRequest else { return false }
        guard lhs.isSlowModeEnabled == rhs.isSlowModeEnabled else { return false }
        guard lhs.isChannel == rhs.isChannel else { return false }
        guard lhs.isBroadcastGroup == rhs.isBroadcastGroup else { return false }
        guard lhs.isForum == rhs.isForum else { return false }
        guard lhs.isDirectMessagesGroup == rhs.isDirectMessagesGroup else { return false }
        guard lhs.isAdministeredDirectMessagesGroup == rhs.isAdministeredDirectMessagesGroup else { return false }
        guard lhs.verificationStatus == rhs.verificationStatus else { return false }
        guard lhs.hasDirectMessagesGroup == rhs.hasDirectMessagesGroup else { return false }
        guard lhs.hasForumTabs == rhs.hasForumTabs else { return false }
        guard lhs.restrictionInfo == rhs.restrictionInfo else { return false }
        guard lhs.paidMessageStarCount == rhs.paidMessageStarCount else { return false }
        guard lhs.activeStoryState == rhs.activeStoryState else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(usernames)
        hasher.combine(date)
        hasher.combine(status)
        hasher.combine(memberCount)
        hasher.combine(boostLevel)
        hasher.combine(hasAutomaticTranslation)
        hasher.combine(hasLinkedChat)
        hasher.combine(hasLocation)
        hasher.combine(signMessages)
        hasher.combine(showMessageSender)
        hasher.combine(joinToSendMessages)
        hasher.combine(joinByRequest)
        hasher.combine(isSlowModeEnabled)
        hasher.combine(isChannel)
        hasher.combine(isBroadcastGroup)
        hasher.combine(isForum)
        hasher.combine(isDirectMessagesGroup)
        hasher.combine(isAdministeredDirectMessagesGroup)
        hasher.combine(verificationStatus)
        hasher.combine(hasDirectMessagesGroup)
        hasher.combine(hasForumTabs)
        hasher.combine(restrictionInfo)
        hasher.combine(paidMessageStarCount)
        hasher.combine(activeStoryState)
    }
}

// MARK: - TDNativeTargetChat + @retroactive Hashable

extension TDNativeTargetChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.targetChatCurrent, .targetChatCurrent):
            true
        case (.targetChatChosen(let lhs), .targetChatChosen(let rhs)):
            lhs == rhs
        case (.targetChatInternalLink(let lhs), .targetChatInternalLink(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .targetChatCurrent:
            hasher.combine(0)
        case .targetChatChosen(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .targetChatInternalLink(let value):
            hasher.combine(2)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeTargetChatChosen + @retroactive Hashable

extension TDNativeTargetChatChosen: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.types == rhs.types else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(types)
    }
}

// MARK: - TDNativeTargetChatInternalLink + @retroactive Hashable

extension TDNativeTargetChatInternalLink: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.link == rhs.link else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(link)
    }
}

// MARK: - TDNativeTargetChatTypes + @retroactive Hashable

extension TDNativeTargetChatTypes: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.allowUserChats == rhs.allowUserChats else { return false }
        guard lhs.allowBotChats == rhs.allowBotChats else { return false }
        guard lhs.allowGroupChats == rhs.allowGroupChats else { return false }
        guard lhs.allowChannelChats == rhs.allowChannelChats else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(allowUserChats)
        hasher.combine(allowBotChats)
        hasher.combine(allowGroupChats)
        hasher.combine(allowChannelChats)
    }
}

// MARK: - TDNativeTermsOfService + @retroactive Hashable

extension TDNativeTermsOfService: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.minUserAge == rhs.minUserAge else { return false }
        guard lhs.showPopup == rhs.showPopup else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(minUserAge)
        hasher.combine(showPopup)
    }
}

// MARK: - TDNativeTextQuote + @retroactive Hashable

extension TDNativeTextQuote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.position == rhs.position else { return false }
        guard lhs.isManual == rhs.isManual else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(position)
        hasher.combine(isManual)
    }
}

// MARK: - TDNativeThemeSettings + @retroactive Hashable

extension TDNativeThemeSettings: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.baseTheme == rhs.baseTheme else { return false }
        guard lhs.accentColor == rhs.accentColor else { return false }
        guard lhs.background == rhs.background else { return false }
        guard lhs.outgoingMessageFill == rhs.outgoingMessageFill else { return false }
        guard lhs.animateOutgoingMessageFill == rhs.animateOutgoingMessageFill else { return false }
        guard lhs.outgoingMessageAccentColor == rhs.outgoingMessageAccentColor else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(baseTheme)
        hasher.combine(accentColor)
        hasher.combine(background)
        hasher.combine(outgoingMessageFill)
        hasher.combine(animateOutgoingMessageFill)
        hasher.combine(outgoingMessageAccentColor)
    }
}

// MARK: - TDNativeUnreadReaction + @retroactive Hashable

extension TDNativeUnreadReaction: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type else { return false }
        guard lhs.senderId == rhs.senderId else { return false }
        guard lhs.isBig == rhs.isBig else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(senderId)
        hasher.combine(isBig)
    }
}

// MARK: - TDNativeUpdateForumTopic + @retroactive Hashable

extension TDNativeUpdateForumTopic: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.chatId == rhs.chatId else { return false }
        guard lhs.forumTopicId == rhs.forumTopicId else { return false }
        guard lhs.isPinned == rhs.isPinned else { return false }
        guard lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId else { return false }
        guard lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId else { return false }
        guard lhs.unreadMentionCount == rhs.unreadMentionCount else { return false }
        guard lhs.unreadReactionCount == rhs.unreadReactionCount else { return false }
        guard lhs.unreadPollVoteCount == rhs.unreadPollVoteCount else { return false }
        guard lhs.notificationSettings == rhs.notificationSettings else { return false }
        guard lhs.draftMessage == rhs.draftMessage else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
        hasher.combine(forumTopicId)
        hasher.combine(isPinned)
        hasher.combine(lastReadInboxMessageId)
        hasher.combine(lastReadOutboxMessageId)
        hasher.combine(unreadMentionCount)
        hasher.combine(unreadReactionCount)
        hasher.combine(unreadPollVoteCount)
        hasher.combine(notificationSettings)
        hasher.combine(draftMessage)
    }
}

// MARK: - TDNativeUpdateMessageSendFailed + @retroactive Hashable

extension TDNativeUpdateMessageSendFailed: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.message == rhs.message else { return false }
        guard lhs.oldMessageId == rhs.oldMessageId else { return false }
        guard lhs.error == rhs.error else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(message)
        hasher.combine(oldMessageId)
        hasher.combine(error)
    }
}

// MARK: - TDNativeUpdateMessageSendSucceeded + @retroactive Hashable

extension TDNativeUpdateMessageSendSucceeded: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.message == rhs.message else { return false }
        guard lhs.oldMessageId == rhs.oldMessageId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(message)
        hasher.combine(oldMessageId)
    }
}

// MARK: - TDNativeUpgradedGift + @retroactive Hashable

extension TDNativeUpgradedGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.regularGiftId == rhs.regularGiftId else { return false }
        guard lhs.publisherChatId == rhs.publisherChatId else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.name == rhs.name else { return false }
        guard lhs.number == rhs.number else { return false }
        guard lhs.totalUpgradedCount == rhs.totalUpgradedCount else { return false }
        guard lhs.maxUpgradedCount == rhs.maxUpgradedCount else { return false }
        guard lhs.isBurned == rhs.isBurned else { return false }
        guard lhs.isCrafted == rhs.isCrafted else { return false }
        guard lhs.isPremium == rhs.isPremium else { return false }
        guard lhs.isThemeAvailable == rhs.isThemeAvailable else { return false }
        guard lhs.usedThemeChatId == rhs.usedThemeChatId else { return false }
        guard lhs.hostId == rhs.hostId else { return false }
        guard lhs.ownerId == rhs.ownerId else { return false }
        guard lhs.ownerAddress == rhs.ownerAddress else { return false }
        guard lhs.ownerName == rhs.ownerName else { return false }
        guard lhs.giftAddress == rhs.giftAddress else { return false }
        guard lhs.model == rhs.model else { return false }
        guard lhs.symbol == rhs.symbol else { return false }
        guard lhs.backdrop == rhs.backdrop else { return false }
        guard lhs.originalDetails == rhs.originalDetails else { return false }
        guard lhs.colors == rhs.colors else { return false }
        guard lhs.resaleParameters == rhs.resaleParameters else { return false }
        guard lhs.canSendPurchaseOffer == rhs.canSendPurchaseOffer else { return false }
        guard lhs.craftProbabilityPerMille == rhs.craftProbabilityPerMille else { return false }
        guard lhs.valueCurrency == rhs.valueCurrency else { return false }
        guard lhs.valueAmount == rhs.valueAmount else { return false }
        guard lhs.valueUsdAmount == rhs.valueUsdAmount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(regularGiftId)
        hasher.combine(publisherChatId)
        hasher.combine(title)
        hasher.combine(name)
        hasher.combine(number)
        hasher.combine(totalUpgradedCount)
        hasher.combine(maxUpgradedCount)
        hasher.combine(isBurned)
        hasher.combine(isCrafted)
        hasher.combine(isPremium)
        hasher.combine(isThemeAvailable)
        hasher.combine(usedThemeChatId)
        hasher.combine(hostId)
        hasher.combine(ownerId)
        hasher.combine(ownerAddress)
        hasher.combine(ownerName)
        hasher.combine(giftAddress)
        hasher.combine(model)
        hasher.combine(symbol)
        hasher.combine(backdrop)
        hasher.combine(originalDetails)
        hasher.combine(colors)
        hasher.combine(resaleParameters)
        hasher.combine(canSendPurchaseOffer)
        hasher.combine(craftProbabilityPerMille)
        hasher.combine(valueCurrency)
        hasher.combine(valueAmount)
        hasher.combine(valueUsdAmount)
    }
}

// MARK: - TDNativeUpgradedGiftAttributeRarity + @retroactive Hashable

extension TDNativeUpgradedGiftAttributeRarity: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.upgradedGiftAttributeRarityPerMille(let lhs), .upgradedGiftAttributeRarityPerMille(let rhs)):
            lhs == rhs
        case (.upgradedGiftAttributeRarityUncommon, .upgradedGiftAttributeRarityUncommon):
            true
        case (.upgradedGiftAttributeRarityRare, .upgradedGiftAttributeRarityRare):
            true
        case (.upgradedGiftAttributeRarityEpic, .upgradedGiftAttributeRarityEpic):
            true
        case (.upgradedGiftAttributeRarityLegendary, .upgradedGiftAttributeRarityLegendary):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .upgradedGiftAttributeRarityPerMille(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .upgradedGiftAttributeRarityUncommon:
            hasher.combine(1)
        case .upgradedGiftAttributeRarityRare:
            hasher.combine(2)
        case .upgradedGiftAttributeRarityEpic:
            hasher.combine(3)
        case .upgradedGiftAttributeRarityLegendary:
            hasher.combine(4)
        }
    }
}

// MARK: - TDNativeUpgradedGiftAttributeRarityPerMille + @retroactive Hashable

extension TDNativeUpgradedGiftAttributeRarityPerMille: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.perMille == rhs.perMille else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(perMille)
    }
}

// MARK: - TDNativeUpgradedGiftBackdrop + @retroactive Hashable

extension TDNativeUpgradedGiftBackdrop: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.name == rhs.name else { return false }
        guard lhs.colors == rhs.colors else { return false }
        guard lhs.rarity == rhs.rarity else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(colors)
        hasher.combine(rarity)
    }
}

// MARK: - TDNativeUpgradedGiftBackdropColors + @retroactive Hashable

extension TDNativeUpgradedGiftBackdropColors: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.centerColor == rhs.centerColor else { return false }
        guard lhs.edgeColor == rhs.edgeColor else { return false }
        guard lhs.symbolColor == rhs.symbolColor else { return false }
        guard lhs.textColor == rhs.textColor else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(centerColor)
        hasher.combine(edgeColor)
        hasher.combine(symbolColor)
        hasher.combine(textColor)
    }
}

// MARK: - TDNativeUpgradedGiftColors + @retroactive Hashable

extension TDNativeUpgradedGiftColors: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.modelCustomEmojiId == rhs.modelCustomEmojiId else { return false }
        guard lhs.symbolCustomEmojiId == rhs.symbolCustomEmojiId else { return false }
        guard lhs.lightThemeAccentColor == rhs.lightThemeAccentColor else { return false }
        guard lhs.lightThemeColors == rhs.lightThemeColors else { return false }
        guard lhs.darkThemeAccentColor == rhs.darkThemeAccentColor else { return false }
        guard lhs.darkThemeColors == rhs.darkThemeColors else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(modelCustomEmojiId)
        hasher.combine(symbolCustomEmojiId)
        hasher.combine(lightThemeAccentColor)
        hasher.combine(lightThemeColors)
        hasher.combine(darkThemeAccentColor)
        hasher.combine(darkThemeColors)
    }
}

// MARK: - TDNativeUpgradedGiftModel + @retroactive Hashable

extension TDNativeUpgradedGiftModel: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        guard lhs.rarity == rhs.rarity else { return false }
        guard lhs.isCrafted == rhs.isCrafted else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(sticker)
        hasher.combine(rarity)
        hasher.combine(isCrafted)
    }
}

// MARK: - TDNativeUpgradedGiftOrigin + @retroactive Hashable

extension TDNativeUpgradedGiftOrigin: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.upgradedGiftOriginUpgrade(let lhs), .upgradedGiftOriginUpgrade(let rhs)):
            lhs == rhs
        case (.upgradedGiftOriginTransfer, .upgradedGiftOriginTransfer):
            true
        case (.upgradedGiftOriginResale(let lhs), .upgradedGiftOriginResale(let rhs)):
            lhs == rhs
        case (.upgradedGiftOriginBlockchain, .upgradedGiftOriginBlockchain):
            true
        case (.upgradedGiftOriginPrepaidUpgrade, .upgradedGiftOriginPrepaidUpgrade):
            true
        case (.upgradedGiftOriginOffer(let lhs), .upgradedGiftOriginOffer(let rhs)):
            lhs == rhs
        case (.upgradedGiftOriginCraft, .upgradedGiftOriginCraft):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .upgradedGiftOriginUpgrade(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .upgradedGiftOriginTransfer:
            hasher.combine(1)
        case .upgradedGiftOriginResale(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .upgradedGiftOriginBlockchain:
            hasher.combine(3)
        case .upgradedGiftOriginPrepaidUpgrade:
            hasher.combine(4)
        case .upgradedGiftOriginOffer(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .upgradedGiftOriginCraft:
            hasher.combine(6)
        }
    }
}

// MARK: - TDNativeUpgradedGiftOriginOffer + @retroactive Hashable

extension TDNativeUpgradedGiftOriginOffer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.price == rhs.price else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(price)
    }
}

// MARK: - TDNativeUpgradedGiftOriginResale + @retroactive Hashable

extension TDNativeUpgradedGiftOriginResale: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.price == rhs.price else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(price)
    }
}

// MARK: - TDNativeUpgradedGiftOriginUpgrade + @retroactive Hashable

extension TDNativeUpgradedGiftOriginUpgrade: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.giftMessageId == rhs.giftMessageId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(giftMessageId)
    }
}

// MARK: - TDNativeUpgradedGiftOriginalDetails + @retroactive Hashable

extension TDNativeUpgradedGiftOriginalDetails: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.senderId == rhs.senderId else { return false }
        guard lhs.receiverId == rhs.receiverId else { return false }
        guard lhs.text == rhs.text else { return false }
        guard lhs.date == rhs.date else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(senderId)
        hasher.combine(receiverId)
        hasher.combine(text)
        hasher.combine(date)
    }
}

// MARK: - TDNativeUpgradedGiftSymbol + @retroactive Hashable

extension TDNativeUpgradedGiftSymbol: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.sticker == rhs.sticker else { return false }
        guard lhs.rarity == rhs.rarity else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(sticker)
        hasher.combine(rarity)
    }
}

// MARK: - TDNativeUser + @retroactive Hashable

extension TDNativeUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id else { return false }
        guard lhs.firstName == rhs.firstName else { return false }
        guard lhs.lastName == rhs.lastName else { return false }
        guard lhs.usernames == rhs.usernames else { return false }
        guard lhs.phoneNumber == rhs.phoneNumber else { return false }
        guard lhs.status == rhs.status else { return false }
        guard lhs.profilePhoto == rhs.profilePhoto else { return false }
        guard lhs.accentColorId == rhs.accentColorId else { return false }
        guard lhs.backgroundCustomEmojiId == rhs.backgroundCustomEmojiId else { return false }
        guard lhs.upgradedGiftColors == rhs.upgradedGiftColors else { return false }
        guard lhs.profileAccentColorId == rhs.profileAccentColorId else { return false }
        guard lhs.profileBackgroundCustomEmojiId == rhs.profileBackgroundCustomEmojiId else { return false }
        guard lhs.emojiStatus == rhs.emojiStatus else { return false }
        guard lhs.isContact == rhs.isContact else { return false }
        guard lhs.isMutualContact == rhs.isMutualContact else { return false }
        guard lhs.isCloseFriend == rhs.isCloseFriend else { return false }
        guard lhs.verificationStatus == rhs.verificationStatus else { return false }
        guard lhs.isPremium == rhs.isPremium else { return false }
        guard lhs.isSupport == rhs.isSupport else { return false }
        guard lhs.restrictionInfo == rhs.restrictionInfo else { return false }
        guard lhs.activeStoryState == rhs.activeStoryState else { return false }
        guard lhs.restrictsNewChats == rhs.restrictsNewChats else { return false }
        guard lhs.paidMessageStarCount == rhs.paidMessageStarCount else { return false }
        guard lhs.haveAccess == rhs.haveAccess else { return false }
        guard lhs.type == rhs.type else { return false }
        guard lhs.languageCode == rhs.languageCode else { return false }
        guard lhs.addedToAttachmentMenu == rhs.addedToAttachmentMenu else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(firstName)
        hasher.combine(lastName)
        hasher.combine(usernames)
        hasher.combine(phoneNumber)
        hasher.combine(status)
        hasher.combine(profilePhoto)
        hasher.combine(accentColorId)
        hasher.combine(backgroundCustomEmojiId)
        hasher.combine(upgradedGiftColors)
        hasher.combine(profileAccentColorId)
        hasher.combine(profileBackgroundCustomEmojiId)
        hasher.combine(emojiStatus)
        hasher.combine(isContact)
        hasher.combine(isMutualContact)
        hasher.combine(isCloseFriend)
        hasher.combine(verificationStatus)
        hasher.combine(isPremium)
        hasher.combine(isSupport)
        hasher.combine(restrictionInfo)
        hasher.combine(activeStoryState)
        hasher.combine(restrictsNewChats)
        hasher.combine(paidMessageStarCount)
        hasher.combine(haveAccess)
        hasher.combine(type)
        hasher.combine(languageCode)
        hasher.combine(addedToAttachmentMenu)
    }
}

// MARK: - TDNativeUserStatus + @retroactive Hashable

extension TDNativeUserStatus: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.userStatusEmpty, .userStatusEmpty):
            true
        case (.userStatusOnline(let lhs), .userStatusOnline(let rhs)):
            lhs == rhs
        case (.userStatusOffline(let lhs), .userStatusOffline(let rhs)):
            lhs == rhs
        case (.userStatusRecently(let lhs), .userStatusRecently(let rhs)):
            lhs == rhs
        case (.userStatusLastWeek(let lhs), .userStatusLastWeek(let rhs)):
            lhs == rhs
        case (.userStatusLastMonth(let lhs), .userStatusLastMonth(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .userStatusEmpty:
            hasher.combine(0)
        case .userStatusOnline(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .userStatusOffline(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .userStatusRecently(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .userStatusLastWeek(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .userStatusLastMonth(let value):
            hasher.combine(5)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeUserStatusLastMonth + @retroactive Hashable

extension TDNativeUserStatusLastMonth: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.byMyPrivacySettings == rhs.byMyPrivacySettings else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(byMyPrivacySettings)
    }
}

// MARK: - TDNativeUserStatusLastWeek + @retroactive Hashable

extension TDNativeUserStatusLastWeek: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.byMyPrivacySettings == rhs.byMyPrivacySettings else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(byMyPrivacySettings)
    }
}

// MARK: - TDNativeUserStatusOffline + @retroactive Hashable

extension TDNativeUserStatusOffline: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.wasOnline == rhs.wasOnline else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(wasOnline)
    }
}

// MARK: - TDNativeUserStatusOnline + @retroactive Hashable

extension TDNativeUserStatusOnline: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.expires == rhs.expires else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(expires)
    }
}

// MARK: - TDNativeUserStatusRecently + @retroactive Hashable

extension TDNativeUserStatusRecently: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.byMyPrivacySettings == rhs.byMyPrivacySettings else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(byMyPrivacySettings)
    }
}

// MARK: - TDNativeUserType + @retroactive Hashable

extension TDNativeUserType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.userTypeRegular, .userTypeRegular):
            true
        case (.userTypeDeleted, .userTypeDeleted):
            true
        case (.userTypeBot(let lhs), .userTypeBot(let rhs)):
            lhs == rhs
        case (.userTypeUnknown, .userTypeUnknown):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .userTypeRegular:
            hasher.combine(0)
        case .userTypeDeleted:
            hasher.combine(1)
        case .userTypeBot(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .userTypeUnknown:
            hasher.combine(3)
        }
    }
}

// MARK: - TDNativeUserTypeBot + @retroactive Hashable

extension TDNativeUserTypeBot: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.canBeEdited == rhs.canBeEdited else { return false }
        guard lhs.canJoinGroups == rhs.canJoinGroups else { return false }
        guard lhs.canReadAllGroupMessages == rhs.canReadAllGroupMessages else { return false }
        guard lhs.hasMainWebApp == rhs.hasMainWebApp else { return false }
        guard lhs.hasTopics == rhs.hasTopics else { return false }
        guard lhs.allowsUsersToCreateTopics == rhs.allowsUsersToCreateTopics else { return false }
        guard lhs.canManageBots == rhs.canManageBots else { return false }
        guard lhs.isInline == rhs.isInline else { return false }
        guard lhs.inlineQueryPlaceholder == rhs.inlineQueryPlaceholder else { return false }
        guard lhs.supportsGuestQueries == rhs.supportsGuestQueries else { return false }
        guard lhs.isGuard == rhs.isGuard else { return false }
        guard lhs.needLocation == rhs.needLocation else { return false }
        guard lhs.canConnectToBusiness == rhs.canConnectToBusiness else { return false }
        guard lhs.canBeAddedToAttachmentMenu == rhs.canBeAddedToAttachmentMenu else { return false }
        guard lhs.activeUserCount == rhs.activeUserCount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canBeEdited)
        hasher.combine(canJoinGroups)
        hasher.combine(canReadAllGroupMessages)
        hasher.combine(hasMainWebApp)
        hasher.combine(hasTopics)
        hasher.combine(allowsUsersToCreateTopics)
        hasher.combine(canManageBots)
        hasher.combine(isInline)
        hasher.combine(inlineQueryPlaceholder)
        hasher.combine(supportsGuestQueries)
        hasher.combine(isGuard)
        hasher.combine(needLocation)
        hasher.combine(canConnectToBusiness)
        hasher.combine(canBeAddedToAttachmentMenu)
        hasher.combine(activeUserCount)
    }
}

// MARK: - TDNativeUsernames + @retroactive Hashable

extension TDNativeUsernames: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.activeUsernames == rhs.activeUsernames else { return false }
        guard lhs.disabledUsernames == rhs.disabledUsernames else { return false }
        guard lhs.editableUsername == rhs.editableUsername else { return false }
        guard lhs.collectibleUsernames == rhs.collectibleUsernames else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(activeUsernames)
        hasher.combine(disabledUsernames)
        hasher.combine(editableUsername)
        hasher.combine(collectibleUsernames)
    }
}

// MARK: - TDNativeVenue + @retroactive Hashable

extension TDNativeVenue: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.address == rhs.address else { return false }
        guard lhs.provider == rhs.provider else { return false }
        guard lhs.id == rhs.id else { return false }
        guard lhs.type == rhs.type else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        hasher.combine(title)
        hasher.combine(address)
        hasher.combine(provider)
        hasher.combine(id)
        hasher.combine(type)
    }
}

// MARK: - TDNativeVerificationStatus + @retroactive Hashable

extension TDNativeVerificationStatus: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isVerified == rhs.isVerified else { return false }
        guard lhs.isScam == rhs.isScam else { return false }
        guard lhs.isFake == rhs.isFake else { return false }
        guard lhs.botVerificationIconCustomEmojiId == rhs.botVerificationIconCustomEmojiId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(isVerified)
        hasher.combine(isScam)
        hasher.combine(isFake)
        hasher.combine(botVerificationIconCustomEmojiId)
    }
}

// MARK: - TDNativeVideoChat + @retroactive Hashable

extension TDNativeVideoChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groupCallId == rhs.groupCallId else { return false }
        guard lhs.hasParticipants == rhs.hasParticipants else { return false }
        guard lhs.defaultParticipantId == rhs.defaultParticipantId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(groupCallId)
        hasher.combine(hasParticipants)
        hasher.combine(defaultParticipantId)
    }
}

// MARK: - TDNativeVideoNote + @retroactive Hashable

extension TDNativeVideoNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.waveform == rhs.waveform else { return false }
        guard lhs.length == rhs.length else { return false }
        guard lhs.minithumbnail == rhs.minithumbnail else { return false }
        guard lhs.thumbnail == rhs.thumbnail else { return false }
        guard lhs.speechRecognitionResult == rhs.speechRecognitionResult else { return false }
        guard lhs.video == rhs.video else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(duration)
        hasher.combine(waveform)
        hasher.combine(length)
        hasher.combine(minithumbnail)
        hasher.combine(thumbnail)
        hasher.combine(speechRecognitionResult)
        hasher.combine(video)
    }
}

// MARK: - TDNativeVoiceNote + @retroactive Hashable

extension TDNativeVoiceNote: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.duration == rhs.duration else { return false }
        guard lhs.waveform == rhs.waveform else { return false }
        guard lhs.mimeType == rhs.mimeType else { return false }
        guard lhs.speechRecognitionResult == rhs.speechRecognitionResult else { return false }
        guard lhs.voice == rhs.voice else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(duration)
        hasher.combine(waveform)
        hasher.combine(mimeType)
        hasher.combine(speechRecognitionResult)
        hasher.combine(voice)
    }
}

// MARK: - TDNativeWebApp + @retroactive Hashable

extension TDNativeWebApp: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.shortName == rhs.shortName else { return false }
        guard lhs.title == rhs.title else { return false }
        guard lhs.description == rhs.description else { return false }
        guard lhs.photo == rhs.photo else { return false }
        guard lhs.animation == rhs.animation else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(shortName)
        hasher.combine(title)
        hasher.combine(description)
        hasher.combine(photo)
        hasher.combine(animation)
    }
}
