// TDNativeValueEquality+Generated.swift

import Foundation
import TDLibKit

// MARK: - TDNativeAccountInfo + @retroactive Hashable

extension TDNativeAccountInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.registrationMonth == rhs.registrationMonth, lhs.registrationYear == rhs.registrationYear,
              lhs.phoneNumberCountryCode == rhs.phoneNumberCountryCode,
              lhs.lastNameChangeDate == rhs.lastNameChangeDate,
              lhs.lastPhotoChangeDate == rhs.lastPhotoChangeDate else { return false }
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
        guard lhs.countryCode == rhs.countryCode, lhs.state == rhs.state, lhs.city == rhs.city,
              lhs.streetLine1 == rhs.streetLine1, lhs.streetLine2 == rhs.streetLine2,
              lhs.postalCode == rhs.postalCode else { return false }
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
        guard lhs.sticker == rhs.sticker, lhs.stickerWidth == rhs.stickerWidth, lhs.stickerHeight == rhs.stickerHeight,
              lhs.fitzpatrickType == rhs.fitzpatrickType, lhs.sound == rhs.sound,
              lhs.isRegularEmoji == rhs.isRegularEmoji else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
        hasher.combine(stickerWidth)
        hasher.combine(stickerHeight)
        hasher.combine(fitzpatrickType)
        hasher.combine(sound)
        hasher.combine(isRegularEmoji)
    }
}

// MARK: - TDNativeAudio + @retroactive Hashable

extension TDNativeAudio: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.duration == rhs.duration, lhs.title == rhs.title, lhs.performer == rhs.performer,
              lhs.fileName == rhs.fileName, lhs.mimeType == rhs.mimeType,
              lhs.albumCoverMinithumbnail == rhs.albumCoverMinithumbnail,
              lhs.albumCoverThumbnail == rhs.albumCoverThumbnail, lhs.externalAlbumCovers == rhs.externalAlbumCovers,
              lhs.audio == rhs.audio else { return false }
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
        guard lhs.phoneNumber == rhs.phoneNumber, lhs.type == rhs.type, lhs.nextType == rhs.nextType,
              lhs.timeout == rhs.timeout else { return false }
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
        guard lhs.deviceVerificationParameters == rhs.deviceVerificationParameters,
              lhs.length == rhs.length else { return false }
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
        guard lhs.receipt == rhs.receipt, lhs.pushTimeout == rhs.pushTimeout,
              lhs.length == rhs.length else { return false }
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
        guard lhs.url == rhs.url, lhs.length == rhs.length else { return false }
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
        guard lhs.phoneNumberPrefix == rhs.phoneNumberPrefix, lhs.length == rhs.length else { return false }
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
        guard lhs.allowAppleId == rhs.allowAppleId, lhs.allowGoogleId == rhs.allowGoogleId else { return false }
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
        guard lhs.allowAppleId == rhs.allowAppleId, lhs.allowGoogleId == rhs.allowGoogleId,
              lhs.codeInfo == rhs.codeInfo,
              lhs.emailAddressResetState == rhs.emailAddressResetState else { return false }
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
        guard lhs.passwordHint == rhs.passwordHint, lhs.hasRecoveryEmailAddress == rhs.hasRecoveryEmailAddress,
              lhs.hasPassportData == rhs.hasPassportData,
              lhs.recoveryEmailAddressPattern == rhs.recoveryEmailAddressPattern else { return false }
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
        guard lhs.storeProductId == rhs.storeProductId, lhs.premiumDayCount == rhs.premiumDayCount,
              lhs.supportEmailAddress == rhs.supportEmailAddress,
              lhs.supportEmailSubject == rhs.supportEmailSubject else { return false }
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
        guard lhs.id == rhs.id, lhs.isDefault == rhs.isDefault, lhs.isDark == rhs.isDark, lhs.name == rhs.name,
              lhs.document == rhs.document, lhs.type == rhs.type else { return false }
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
        guard lhs.topColor == rhs.topColor, lhs.bottomColor == rhs.bottomColor,
              lhs.rotationAngle == rhs.rotationAngle else { return false }
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
        guard lhs.fill == rhs.fill, lhs.intensity == rhs.intensity, lhs.isInverted == rhs.isInverted,
              lhs.isMoving == rhs.isMoving else { return false }
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
        guard lhs.isBlurred == rhs.isBlurred, lhs.isMoving == rhs.isMoving else { return false }
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
        guard lhs.id == rhs.id, lhs.memberCount == rhs.memberCount, lhs.status == rhs.status,
              lhs.isActive == rhs.isActive,
              lhs.upgradedToSupergroupId == rhs.upgradedToSupergroupId else { return false }
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
        guard lhs.day == rhs.day, lhs.month == rhs.month, lhs.year == rhs.year else { return false }
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
        guard lhs.botUserId == rhs.botUserId, lhs.manageUrl == rhs.manageUrl, lhs.isBotPaused == rhs.isBotPaused,
              lhs.canBotReply == rhs.canBotReply else { return false }
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
        guard lhs.id == rhs.id, lhs.type == rhs.type, lhs.title == rhs.title, lhs.photo == rhs.photo,
              lhs.accentColorId == rhs.accentColorId, lhs.backgroundCustomEmojiId == rhs.backgroundCustomEmojiId,
              lhs.upgradedGiftColors == rhs.upgradedGiftColors, lhs.profileAccentColorId == rhs.profileAccentColorId,
              lhs.profileBackgroundCustomEmojiId == rhs.profileBackgroundCustomEmojiId,
              lhs.permissions == rhs.permissions, lhs.lastMessage == rhs.lastMessage, lhs.positions == rhs.positions,
              lhs.chatLists == rhs.chatLists, lhs.messageSenderId == rhs.messageSenderId,
              lhs.blockList == rhs.blockList,
              lhs.hasProtectedContent == rhs.hasProtectedContent, lhs.isTranslatable == rhs.isTranslatable,
              lhs.isMarkedAsUnread == rhs.isMarkedAsUnread, lhs.viewAsTopics == rhs.viewAsTopics,
              lhs.hasScheduledMessages == rhs.hasScheduledMessages, lhs.hasWelcomeMessages == rhs.hasWelcomeMessages,
              lhs.canBeDeletedOnlyForSelf == rhs.canBeDeletedOnlyForSelf,
              lhs.canBeDeletedForAllUsers == rhs.canBeDeletedForAllUsers, lhs.canBeReported == rhs.canBeReported,
              lhs.defaultDisableNotification == rhs.defaultDisableNotification, lhs.unreadCount == rhs.unreadCount,
              lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId,
              lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId,
              lhs.unreadMentionCount == rhs.unreadMentionCount, lhs.unreadReactionCount == rhs.unreadReactionCount,
              lhs.unreadPollVoteCount == rhs.unreadPollVoteCount, lhs.notificationSettings == rhs.notificationSettings,
              lhs.availableReactions == rhs.availableReactions, lhs.messageAutoDeleteTime == rhs.messageAutoDeleteTime,
              lhs.emojiStatus == rhs.emojiStatus, lhs.background == rhs.background, lhs.theme == rhs.theme,
              lhs.actionBar == rhs.actionBar, lhs.businessBotManageBar == rhs.businessBotManageBar,
              lhs.videoChat == rhs.videoChat, lhs.pendingJoinRequests == rhs.pendingJoinRequests,
              lhs.replyMarkupMessageId == rhs.replyMarkupMessageId, lhs.draftMessage == rhs.draftMessage,
              lhs.clientData == rhs.clientData else { return false }
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
        guard lhs.title == rhs.title, lhs.isChannel == rhs.isChannel,
              lhs.requestDate == rhs.requestDate else { return false }
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
        guard lhs.canUnarchive == rhs.canUnarchive, lhs.accountInfo == rhs.accountInfo else { return false }
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
        guard lhs.canManageChat == rhs.canManageChat, lhs.canChangeInfo == rhs.canChangeInfo,
              lhs.canPostMessages == rhs.canPostMessages, lhs.canEditMessages == rhs.canEditMessages,
              lhs.canDeleteMessages == rhs.canDeleteMessages, lhs.canInviteUsers == rhs.canInviteUsers,
              lhs.canRestrictMembers == rhs.canRestrictMembers, lhs.canPinMessages == rhs.canPinMessages,
              lhs.canManageTopics == rhs.canManageTopics, lhs.canPromoteMembers == rhs.canPromoteMembers,
              lhs.canManageVideoChats == rhs.canManageVideoChats, lhs.canPostStories == rhs.canPostStories,
              lhs.canEditStories == rhs.canEditStories, lhs.canDeleteStories == rhs.canDeleteStories,
              lhs.canManageDirectMessages == rhs.canManageDirectMessages, lhs.canManageTags == rhs.canManageTags,
              lhs.canSendWelcomeMessages == rhs.canSendWelcomeMessages,
              lhs.isAnonymous == rhs.isAnonymous else { return false }
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
        guard lhs.reactions == rhs.reactions, lhs.maxReactionCount == rhs.maxReactionCount else { return false }
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
        guard lhs.background == rhs.background, lhs.darkThemeDimming == rhs.darkThemeDimming else { return false }
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
        guard lhs.totalCount == rhs.totalCount, lhs.userIds == rhs.userIds else { return false }
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
        guard lhs.memberId == rhs.memberId, lhs.tag == rhs.tag, lhs.inviterUserId == rhs.inviterUserId,
              lhs.joinedChatDate == rhs.joinedChatDate, lhs.status == rhs.status else { return false }
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
        guard lhs.canBeEdited == rhs.canBeEdited, lhs.rights == rhs.rights else { return false }
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
        guard lhs.isAnonymous == rhs.isAnonymous, lhs.isMember == rhs.isMember else { return false }
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
        guard lhs.isMember == rhs.isMember, lhs.restrictedUntilDate == rhs.restrictedUntilDate,
              lhs.permissions == rhs.permissions else { return false }
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
        guard lhs.useDefaultMuteFor == rhs.useDefaultMuteFor, lhs.muteFor == rhs.muteFor,
              lhs.useDefaultSound == rhs.useDefaultSound, lhs.soundId == rhs.soundId,
              lhs.useDefaultShowPreview == rhs.useDefaultShowPreview, lhs.showPreview == rhs.showPreview,
              lhs.useDefaultMuteStories == rhs.useDefaultMuteStories, lhs.muteStories == rhs.muteStories,
              lhs.useDefaultStorySound == rhs.useDefaultStorySound, lhs.storySoundId == rhs.storySoundId,
              lhs.useDefaultShowStoryPoster == rhs.useDefaultShowStoryPoster,
              lhs.showStoryPoster == rhs.showStoryPoster,
              lhs.useDefaultDisablePinnedMessageNotifications == rhs.useDefaultDisablePinnedMessageNotifications,
              lhs.disablePinnedMessageNotifications == rhs.disablePinnedMessageNotifications,
              lhs.useDefaultDisableMentionNotifications == rhs.useDefaultDisableMentionNotifications,
              lhs.disableMentionNotifications == rhs.disableMentionNotifications else { return false }
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
        guard lhs.canSendBasicMessages == rhs.canSendBasicMessages, lhs.canSendAudios == rhs.canSendAudios,
              lhs.canSendDocuments == rhs.canSendDocuments, lhs.canSendPhotos == rhs.canSendPhotos,
              lhs.canSendVideos == rhs.canSendVideos, lhs.canSendVideoNotes == rhs.canSendVideoNotes,
              lhs.canSendVoiceNotes == rhs.canSendVoiceNotes, lhs.canSendPolls == rhs.canSendPolls,
              lhs.canSendOtherMessages == rhs.canSendOtherMessages, lhs.canAddLinkPreviews == rhs.canAddLinkPreviews,
              lhs.canReactToMessages == rhs.canReactToMessages, lhs.canEditTag == rhs.canEditTag,
              lhs.canChangeInfo == rhs.canChangeInfo, lhs.canInviteUsers == rhs.canInviteUsers,
              lhs.canPinMessages == rhs.canPinMessages, lhs.canCreateTopics == rhs.canCreateTopics else { return false }
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
        guard lhs.id == rhs.id, lhs.addedDate == rhs.addedDate, lhs.minithumbnail == rhs.minithumbnail,
              lhs.sizes == rhs.sizes, lhs.animation == rhs.animation, lhs.smallAnimation == rhs.smallAnimation,
              lhs.sticker == rhs.sticker else { return false }
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
        guard lhs.type == rhs.type, lhs.backgroundFill == rhs.backgroundFill else { return false }
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
        guard lhs.stickerSetId == rhs.stickerSetId, lhs.stickerId == rhs.stickerId else { return false }
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
        guard lhs.list == rhs.list, lhs.order == rhs.order, lhs.isPinned == rhs.isPinned,
              lhs.source == rhs.source else { return false }
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
        guard lhs.type == rhs.type, lhs.text == rhs.text else { return false }
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
        guard lhs.secretChatId == rhs.secretChatId, lhs.userId == rhs.userId else { return false }
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
        guard lhs.supergroupId == rhs.supergroupId, lhs.isChannel == rhs.isChannel else { return false }
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
        guard lhs.title == rhs.title, lhs.tasks == rhs.tasks, lhs.othersCanAddTasks == rhs.othersCanAddTasks,
              lhs.canAddTasks == rhs.canAddTasks, lhs.othersCanMarkTasksAsDone == rhs.othersCanMarkTasksAsDone,
              lhs.canMarkTasksAsDone == rhs.canMarkTasksAsDone else { return false }
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
        guard lhs.id == rhs.id, lhs.text == rhs.text, lhs.completedBy == rhs.completedBy,
              lhs.completionDate == rhs.completionDate else { return false }
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
        guard lhs.phoneNumber == rhs.phoneNumber, lhs.firstName == rhs.firstName, lhs.lastName == rhs.lastName,
              lhs.vcard == rhs.vcard, lhs.userId == rhs.userId else { return false }
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
        guard lhs.timePrecision == rhs.timePrecision, lhs.datePrecision == rhs.datePrecision,
              lhs.showDayOfWeek == rhs.showDayOfWeek else { return false }
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
        guard lhs.file == rhs.file, lhs.date == rhs.date else { return false }
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
        guard lhs.background == rhs.background, lhs.lever == rhs.lever, lhs.leftReel == rhs.leftReel,
              lhs.centerReel == rhs.centerReel, lhs.rightReel == rhs.rightReel else { return false }
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
        guard lhs.fileName == rhs.fileName, lhs.mimeType == rhs.mimeType, lhs.minithumbnail == rhs.minithumbnail,
              lhs.thumbnail == rhs.thumbnail, lhs.document == rhs.document else { return false }
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
        guard lhs.replyTo == rhs.replyTo, lhs.date == rhs.date, lhs.content == rhs.content,
              lhs.effectId == rhs.effectId,
              lhs.suggestedPostInfo == rhs.suggestedPostInfo else { return false }
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
        guard lhs.text == rhs.text, lhs.linkPreviewOptions == rhs.linkPreviewOptions else { return false }
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
        guard lhs.filePath == rhs.filePath, lhs.duration == rhs.duration, lhs.length == rhs.length,
              lhs.selfDestructType == rhs.selfDestructType else { return false }
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
        guard lhs.filePath == rhs.filePath, lhs.duration == rhs.duration, lhs.waveform == rhs.waveform,
              lhs.selfDestructType == rhs.selfDestructType else { return false }
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
        guard lhs.emailAddressPattern == rhs.emailAddressPattern, lhs.length == rhs.length else { return false }
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
        guard lhs.type == rhs.type, lhs.expirationDate == rhs.expirationDate else { return false }
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
        guard lhs.upgradedGiftId == rhs.upgradedGiftId, lhs.giftTitle == rhs.giftTitle, lhs.giftName == rhs.giftName,
              lhs.modelCustomEmojiId == rhs.modelCustomEmojiId, lhs.symbolCustomEmojiId == rhs.symbolCustomEmojiId,
              lhs.backdropColors == rhs.backdropColors else { return false }
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
        guard lhs.data == rhs.data, lhs.hash == rhs.hash, lhs.secret == rhs.secret else { return false }
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
        guard lhs.type == rhs.type, lhs.data == rhs.data, lhs.frontSide == rhs.frontSide,
              lhs.reverseSide == rhs.reverseSide, lhs.selfie == rhs.selfie, lhs.translation == rhs.translation,
              lhs.files == rhs.files, lhs.value == rhs.value, lhs.hash == rhs.hash else { return false }
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
        guard lhs.canBeSaved == rhs.canBeSaved, lhs.hasTimestampedMedia == rhs.hasTimestampedMedia,
              lhs.content == rhs.content, lhs.replyMarkup == rhs.replyMarkup else { return false }
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
        guard lhs.code == rhs.code, lhs.message == rhs.message else { return false }
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
        guard lhs.text == rhs.text, lhs.countryCode == rhs.countryCode else { return false }
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
        guard lhs.nonce == rhs.nonce, lhs.cloudProjectNumber == rhs.cloudProjectNumber else { return false }
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
        guard lhs.info == rhs.info, lhs.lastMessage == rhs.lastMessage, lhs.order == rhs.order,
              lhs.isPinned == rhs.isPinned, lhs.unreadCount == rhs.unreadCount,
              lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId,
              lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId,
              lhs.unreadMentionCount == rhs.unreadMentionCount, lhs.unreadReactionCount == rhs.unreadReactionCount,
              lhs.unreadPollVoteCount == rhs.unreadPollVoteCount, lhs.notificationSettings == rhs.notificationSettings,
              lhs.draftMessage == rhs.draftMessage else { return false }
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
        guard lhs.color == rhs.color, lhs.customEmojiId == rhs.customEmojiId else { return false }
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
        guard lhs.chatId == rhs.chatId, lhs.forumTopicId == rhs.forumTopicId, lhs.name == rhs.name,
              lhs.icon == rhs.icon,
              lhs.creationDate == rhs.creationDate, lhs.creatorId == rhs.creatorId, lhs.isGeneral == rhs.isGeneral,
              lhs.isOutgoing == rhs.isOutgoing, lhs.isClosed == rhs.isClosed, lhs.isHidden == rhs.isHidden,
              lhs.isNameImplicit == rhs.isNameImplicit else { return false }
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
        guard lhs.chatId == rhs.chatId, lhs.messageId == rhs.messageId, lhs.senderId == rhs.senderId,
              lhs.senderName == rhs.senderName, lhs.date == rhs.date,
              lhs.isOutgoing == rhs.isOutgoing else { return false }
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
        guard lhs.id == rhs.id, lhs.shortName == rhs.shortName, lhs.title == rhs.title, lhs.text == rhs.text,
              lhs.description == rhs.description, lhs.photo == rhs.photo,
              lhs.animation == rhs.animation else { return false }
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
        guard lhs.id == rhs.id, lhs.publisherChatId == rhs.publisherChatId, lhs.sticker == rhs.sticker,
              lhs.starCount == rhs.starCount, lhs.defaultSellStarCount == rhs.defaultSellStarCount,
              lhs.upgradeStarCount == rhs.upgradeStarCount, lhs.upgradeVariantCount == rhs.upgradeVariantCount,
              lhs.hasColors == rhs.hasColors, lhs.isForBirthday == rhs.isForBirthday, lhs.isPremium == rhs.isPremium,
              lhs.auctionInfo == rhs.auctionInfo, lhs.nextSendDate == rhs.nextSendDate,
              lhs.userLimits == rhs.userLimits,
              lhs.overallLimits == rhs.overallLimits, lhs.background == rhs.background,
              lhs.firstSendDate == rhs.firstSendDate, lhs.lastSendDate == rhs.lastSendDate else { return false }
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
        guard lhs.id == rhs.id, lhs.giftsPerRound == rhs.giftsPerRound,
              lhs.startDate == rhs.startDate else { return false }
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
        guard lhs.centerColor == rhs.centerColor, lhs.edgeColor == rhs.edgeColor,
              lhs.textColor == rhs.textColor else { return false }
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
        guard lhs.gift == rhs.gift, lhs.lightSettings == rhs.lightSettings,
              lhs.darkSettings == rhs.darkSettings else { return false }
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
        guard lhs.totalCount == rhs.totalCount, lhs.remainingCount == rhs.remainingCount else { return false }
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
        guard lhs.starCount == rhs.starCount, lhs.gramCentCount == rhs.gramCentCount,
              lhs.gramOnly == rhs.gramOnly else { return false }
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
        guard lhs.boostedChatId == rhs.boostedChatId, lhs.additionalChatIds == rhs.additionalChatIds,
              lhs.winnersSelectionDate == rhs.winnersSelectionDate, lhs.onlyNewMembers == rhs.onlyNewMembers,
              lhs.hasPublicWinners == rhs.hasPublicWinners, lhs.countryCodes == rhs.countryCodes,
              lhs.prizeDescription == rhs.prizeDescription else { return false }
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
        guard lhs.text == rhs.text, lhs.style == rhs.style, lhs.type == rhs.type else { return false }
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
        guard lhs.text == rhs.text, lhs.iconCustomEmojiId == rhs.iconCustomEmojiId, lhs.style == rhs.style,
              lhs.type == rhs.type else { return false }
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
        guard lhs.url == rhs.url, lhs.id == rhs.id, lhs.forwardText == rhs.forwardText else { return false }
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
        guard lhs.query == rhs.query, lhs.targetChat == rhs.targetChat else { return false }
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
        guard lhs.animation == rhs.animation, lhs.thumbnail == rhs.thumbnail,
              lhs.addedStickerFileIds == rhs.addedStickerFileIds, lhs.duration == rhs.duration, lhs.width == rhs.width,
              lhs.height == rhs.height else { return false }
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
        guard lhs.audio == rhs.audio, lhs.albumCoverThumbnail == rhs.albumCoverThumbnail, lhs.duration == rhs.duration,
              lhs.title == rhs.title, lhs.performer == rhs.performer else { return false }
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
        guard lhs.title == rhs.title, lhs.tasks == rhs.tasks, lhs.othersCanAddTasks == rhs.othersCanAddTasks,
              lhs.othersCanMarkTasksAsDone == rhs.othersCanMarkTasksAsDone else { return false }
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
        guard lhs.id == rhs.id, lhs.text == rhs.text else { return false }
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
        guard lhs.document == rhs.document, lhs.thumbnail == rhs.thumbnail,
              lhs.disableContentTypeDetection == rhs.disableContentTypeDetection else { return false }
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
        guard lhs.originalPath == rhs.originalPath, lhs.conversion == rhs.conversion,
              lhs.expectedSize == rhs.expectedSize else { return false }
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
        guard lhs.animation == rhs.animation, lhs.caption == rhs.caption,
              lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia,
              lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.audio == rhs.audio, lhs.caption == rhs.caption else { return false }
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
        guard lhs.emoji == rhs.emoji, lhs.clearDraft == rhs.clearDraft else { return false }
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
        guard lhs.document == rhs.document, lhs.caption == rhs.caption else { return false }
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
        guard lhs.fromChatId == rhs.fromChatId, lhs.messageId == rhs.messageId, lhs.inGameShare == rhs.inGameShare,
              lhs.replaceVideoStartTimestamp == rhs.replaceVideoStartTimestamp,
              lhs.newVideoStartTimestamp == rhs.newVideoStartTimestamp,
              lhs.copyOptions == rhs.copyOptions else { return false }
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
        guard lhs.botUserId == rhs.botUserId, lhs.gameShortName == rhs.gameShortName else { return false }
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
        guard lhs.invoice == rhs.invoice, lhs.title == rhs.title, lhs.description == rhs.description,
              lhs.photoUrl == rhs.photoUrl, lhs.photoSize == rhs.photoSize, lhs.photoWidth == rhs.photoWidth,
              lhs.photoHeight == rhs.photoHeight, lhs.payload == rhs.payload, lhs.providerToken == rhs.providerToken,
              lhs.providerData == rhs.providerData, lhs.startParameter == rhs.startParameter,
              lhs.paidMedia == rhs.paidMedia, lhs.paidMediaCaption == rhs.paidMediaCaption else { return false }
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
        guard lhs.starCount == rhs.starCount, lhs.paidMedia == rhs.paidMedia, lhs.caption == rhs.caption,
              lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia, lhs.payload == rhs.payload else { return false }
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
        guard lhs.photo == rhs.photo, lhs.caption == rhs.caption,
              lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia,
              lhs.selfDestructType == rhs.selfDestructType, lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.question == rhs.question, lhs.options == rhs.options, lhs.description == rhs.description,
              lhs.media == rhs.media, lhs.isAnonymous == rhs.isAnonymous,
              lhs.allowsMultipleAnswers == rhs.allowsMultipleAnswers, lhs.allowsRevoting == rhs.allowsRevoting,
              lhs.membersOnly == rhs.membersOnly, lhs.countryCodes == rhs.countryCodes,
              lhs.shuffleOptions == rhs.shuffleOptions, lhs.hideResultsUntilCloses == rhs.hideResultsUntilCloses,
              lhs.type == rhs.type, lhs.openPeriod == rhs.openPeriod, lhs.closeDate == rhs.closeDate,
              lhs.isClosed == rhs.isClosed else { return false }
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
        guard lhs.message == rhs.message, lhs.clearDraft == rhs.clearDraft else { return false }
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
        guard lhs.stateHash == rhs.stateHash, lhs.stakeGramAmount == rhs.stakeGramAmount,
              lhs.clearDraft == rhs.clearDraft else { return false }
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
        guard lhs.sticker == rhs.sticker, lhs.emoji == rhs.emoji else { return false }
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
        guard lhs.storyPosterChatId == rhs.storyPosterChatId, lhs.storyId == rhs.storyId else { return false }
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
        guard lhs.text == rhs.text, lhs.linkPreviewOptions == rhs.linkPreviewOptions,
              lhs.clearDraft == rhs.clearDraft else { return false }
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
        guard lhs.video == rhs.video, lhs.caption == rhs.caption,
              lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia,
              lhs.selfDestructType == rhs.selfDestructType, lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.videoNote == rhs.videoNote, lhs.selfDestructType == rhs.selfDestructType else { return false }
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
        guard lhs.voiceNote == rhs.voiceNote, lhs.caption == rhs.caption,
              lhs.selfDestructType == rhs.selfDestructType else { return false }
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
        guard lhs.animation == rhs.animation, lhs.caption == rhs.caption,
              lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.audio == rhs.audio, lhs.caption == rhs.caption else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.credit == rhs.credit else { return false }
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
        guard lhs.buttons == rhs.buttons, lhs.align == rhs.align else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.caption == rhs.caption else { return false }
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
        guard lhs.header == rhs.header, lhs.blocks == rhs.blocks, lhs.isOpen == rhs.isOpen else { return false }
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
        guard lhs.document == rhs.document, lhs.caption == rhs.caption else { return false }
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
        guard lhs.text == rhs.text, lhs.credit == rhs.credit else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.hasCheckbox == rhs.hasCheckbox, lhs.isChecked == rhs.isChecked,
              lhs.value == rhs.value, lhs.type == rhs.type else { return false }
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
        guard lhs.location == rhs.location, lhs.zoom == rhs.zoom, lhs.width == rhs.width, lhs.height == rhs.height,
              lhs.caption == rhs.caption else { return false }
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
        guard lhs.photo == rhs.photo, lhs.caption == rhs.caption, lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.text == rhs.text, lhs.language == rhs.language else { return false }
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
        guard lhs.text == rhs.text, lhs.credit == rhs.credit else { return false }
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
        guard lhs.text == rhs.text, lhs.size == rhs.size else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.caption == rhs.caption else { return false }
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
        guard lhs.caption == rhs.caption, lhs.cells == rhs.cells, lhs.isBordered == rhs.isBordered,
              lhs.isStriped == rhs.isStriped, lhs.isCompact == rhs.isCompact else { return false }
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
        guard lhs.video == rhs.video, lhs.caption == rhs.caption, lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.voiceNote == rhs.voiceNote, lhs.caption == rhs.caption else { return false }
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
        guard lhs.type == rhs.type, lhs.media == rhs.media, lhs.thumbnail == rhs.thumbnail,
              lhs.addedStickerFileIds == rhs.addedStickerFileIds, lhs.width == rhs.width,
              lhs.height == rhs.height else { return false }
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
        guard lhs.cover == rhs.cover, lhs.startTimestamp == rhs.startTimestamp, lhs.duration == rhs.duration,
              lhs.supportsStreaming == rhs.supportsStreaming else { return false }
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
        guard lhs.photo == rhs.photo, lhs.thumbnail == rhs.thumbnail, lhs.video == rhs.video,
              lhs.addedStickerFileIds == rhs.addedStickerFileIds, lhs.width == rhs.width,
              lhs.height == rhs.height else { return false }
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
        guard lhs.text == rhs.text, lhs.media == rhs.media else { return false }
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
        guard lhs.correctOptionIds == rhs.correctOptionIds, lhs.explanation == rhs.explanation,
              lhs.explanationMedia == rhs.explanationMedia else { return false }
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
        guard lhs.source == rhs.source, lhs.isRtl == rhs.isRtl,
              lhs.detectAutomaticBlocks == rhs.detectAutomaticBlocks else { return false }
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
        guard lhs.id == rhs.id, lhs.media == rhs.media else { return false }
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
        guard lhs.sticker == rhs.sticker, lhs.thumbnail == rhs.thumbnail, lhs.width == rhs.width,
              lhs.height == rhs.height else { return false }
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
        guard lhs.price == rhs.price, lhs.sendDate == rhs.sendDate else { return false }
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
        guard lhs.thumbnail == rhs.thumbnail, lhs.width == rhs.width, lhs.height == rhs.height else { return false }
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
        guard lhs.video == rhs.video, lhs.thumbnail == rhs.thumbnail, lhs.cover == rhs.cover,
              lhs.startTimestamp == rhs.startTimestamp, lhs.addedStickerFileIds == rhs.addedStickerFileIds,
              lhs.duration == rhs.duration, lhs.width == rhs.width, lhs.height == rhs.height,
              lhs.supportsStreaming == rhs.supportsStreaming else { return false }
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
        guard lhs.videoNote == rhs.videoNote, lhs.thumbnail == rhs.thumbnail, lhs.duration == rhs.duration,
              lhs.length == rhs.length else { return false }
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
        guard lhs.voiceNote == rhs.voiceNote, lhs.duration == rhs.duration,
              lhs.waveform == rhs.waveform else { return false }
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
        case (.internalLinkTypeTonConnect(let lhs), .internalLinkTypeTonConnect(let rhs)):
            lhs == rhs
        case (.internalLinkTypeTonWalletTransfer(let lhs), .internalLinkTypeTonWalletTransfer(let rhs)):
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
        case .internalLinkTypeTonConnect(let value):
            hasher.combine(51)
            hasher.combine(value)
        case .internalLinkTypeTonWalletTransfer(let value):
            hasher.combine(52)
            hasher.combine(value)
        case .internalLinkTypeUnknownDeepLink(let value):
            hasher.combine(53)
            hasher.combine(value)
        case .internalLinkTypeUpgradedGift(let value):
            hasher.combine(54)
            hasher.combine(value)
        case .internalLinkTypeUserPhoneNumber(let value):
            hasher.combine(55)
            hasher.combine(value)
        case .internalLinkTypeUserToken(let value):
            hasher.combine(56)
            hasher.combine(value)
        case .internalLinkTypeVideoChat(let value):
            hasher.combine(57)
            hasher.combine(value)
        case .internalLinkTypeWebApp(let value):
            hasher.combine(58)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeInternalLinkTypeAttachmentMenuBot + @retroactive Hashable

extension TDNativeInternalLinkTypeAttachmentMenuBot: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.targetChat == rhs.targetChat, lhs.botUsername == rhs.botUsername,
              lhs.url == rhs.url else { return false }
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
        guard lhs.botUsername == rhs.botUsername,
              lhs.administratorRights == rhs.administratorRights else { return false }
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
        guard lhs.botUsername == rhs.botUsername, lhs.startParameter == rhs.startParameter,
              lhs.autostart == rhs.autostart else { return false }
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
        guard lhs.botUsername == rhs.botUsername, lhs.startParameter == rhs.startParameter,
              lhs.administratorRights == rhs.administratorRights else { return false }
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
        guard lhs.username == rhs.username, lhs.referrer == rhs.referrer else { return false }
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
        guard lhs.botUsername == rhs.botUsername, lhs.gameShortName == rhs.gameShortName else { return false }
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
        guard lhs.giftOwnerUsername == rhs.giftOwnerUsername, lhs.collectionId == rhs.collectionId else { return false }
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
        guard lhs.url == rhs.url, lhs.fallbackUrl == rhs.fallbackUrl else { return false }
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
        guard lhs.botUsername == rhs.botUsername, lhs.startParameter == rhs.startParameter,
              lhs.mode == rhs.mode else { return false }
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
        guard lhs.text == rhs.text, lhs.containsLink == rhs.containsLink else { return false }
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
        guard lhs.botUserId == rhs.botUserId, lhs.scope == rhs.scope, lhs.publicKey == rhs.publicKey,
              lhs.nonce == rhs.nonce, lhs.callbackUrl == rhs.callbackUrl else { return false }
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
        guard lhs.hash == rhs.hash, lhs.phoneNumber == rhs.phoneNumber else { return false }
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
        guard lhs.chatUsername == rhs.chatUsername, lhs.draftText == rhs.draftText,
              lhs.openProfile == rhs.openProfile else { return false }
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
        guard lhs.managerBotUsername == rhs.managerBotUsername, lhs.suggestedBotUsername == rhs.suggestedBotUsername,
              lhs.suggestedBotName == rhs.suggestedBotName else { return false }
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
        guard lhs.starCount == rhs.starCount, lhs.purpose == rhs.purpose else { return false }
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
        guard lhs.stickerSetName == rhs.stickerSetName,
              lhs.expectCustomEmoji == rhs.expectCustomEmoji else { return false }
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
        guard lhs.storyPosterUsername == rhs.storyPosterUsername, lhs.storyId == rhs.storyId else { return false }
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
        guard lhs.storyAlbumOwnerUsername == rhs.storyAlbumOwnerUsername,
              lhs.storyAlbumId == rhs.storyAlbumId else { return false }
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

// MARK: - TDNativeInternalLinkTypeTonConnect + @retroactive Hashable

extension TDNativeInternalLinkTypeTonConnect: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.version == rhs.version, lhs.dappClientId == rhs.dappClientId,
              lhs.connectRequest == rhs.connectRequest,
              lhs.returnStrategy == rhs.returnStrategy, lhs.rpcRequest == rhs.rpcRequest,
              lhs.traceId == rhs.traceId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(dappClientId)
        hasher.combine(connectRequest)
        hasher.combine(returnStrategy)
        hasher.combine(rpcRequest)
        hasher.combine(traceId)
    }
}

// MARK: - TDNativeInternalLinkTypeTonWalletTransfer + @retroactive Hashable

extension TDNativeInternalLinkTypeTonWalletTransfer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.receiver == rhs.receiver, lhs.gramAmount == rhs.gramAmount else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(receiver)
        hasher.combine(gramAmount)
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
        guard lhs.phoneNumber == rhs.phoneNumber, lhs.draftText == rhs.draftText,
              lhs.openProfile == rhs.openProfile else { return false }
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
        guard lhs.chatUsername == rhs.chatUsername, lhs.inviteHash == rhs.inviteHash,
              lhs.isLiveStream == rhs.isLiveStream else { return false }
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
        guard lhs.botUsername == rhs.botUsername, lhs.webAppShortName == rhs.webAppShortName,
              lhs.startParameter == rhs.startParameter, lhs.mode == rhs.mode else { return false }
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
        guard lhs.currency == rhs.currency, lhs.priceParts == rhs.priceParts,
              lhs.subscriptionPeriod == rhs.subscriptionPeriod, lhs.maxTipAmount == rhs.maxTipAmount,
              lhs.suggestedTipAmounts == rhs.suggestedTipAmounts,
              lhs.recurringPaymentTermsOfServiceUrl == rhs.recurringPaymentTermsOfServiceUrl,
              lhs.termsOfServiceUrl == rhs.termsOfServiceUrl, lhs.isTest == rhs.isTest, lhs.needName == rhs.needName,
              lhs.needPhoneNumber == rhs.needPhoneNumber, lhs.needEmailAddress == rhs.needEmailAddress,
              lhs.needShippingAddress == rhs.needShippingAddress,
              lhs.sendPhoneNumberToProvider == rhs.sendPhoneNumberToProvider,
              lhs.sendEmailAddressToProvider == rhs.sendEmailAddressToProvider,
              lhs.isFlexible == rhs.isFlexible else { return false }
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
        guard lhs.text == rhs.text, lhs.iconCustomEmojiId == rhs.iconCustomEmojiId, lhs.style == rhs.style,
              lhs.type == rhs.type else { return false }
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
        guard lhs.id == rhs.id, lhs.chatIsChannel == rhs.chatIsChannel,
              lhs.restrictChatIsForum == rhs.restrictChatIsForum, lhs.chatIsForum == rhs.chatIsForum,
              lhs.restrictChatHasUsername == rhs.restrictChatHasUsername, lhs.chatHasUsername == rhs.chatHasUsername,
              lhs.chatIsCreated == rhs.chatIsCreated, lhs.userAdministratorRights == rhs.userAdministratorRights,
              lhs.botAdministratorRights == rhs.botAdministratorRights, lhs.botIsMember == rhs.botIsMember,
              lhs.requestTitle == rhs.requestTitle, lhs.requestUsername == rhs.requestUsername,
              lhs.requestPhoto == rhs.requestPhoto else { return false }
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
        guard lhs.id == rhs.id, lhs.suggestedName == rhs.suggestedName,
              lhs.suggestedUsername == rhs.suggestedUsername else { return false }
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
        guard lhs.forceRegular == rhs.forceRegular, lhs.forceQuiz == rhs.forceQuiz else { return false }
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
        guard lhs.id == rhs.id, lhs.restrictUserIsBot == rhs.restrictUserIsBot, lhs.userIsBot == rhs.userIsBot,
              lhs.restrictUserIsPremium == rhs.restrictUserIsPremium, lhs.userIsPremium == rhs.userIsPremium,
              lhs.maxQuantity == rhs.maxQuantity, lhs.requestName == rhs.requestName,
              lhs.requestUsername == rhs.requestUsername, lhs.requestPhoto == rhs.requestPhoto else { return false }
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
        guard lhs.label == rhs.label, lhs.amount == rhs.amount else { return false }
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
        guard lhs.url == rhs.url, lhs.displayUrl == rhs.displayUrl, lhs.siteName == rhs.siteName,
              lhs.title == rhs.title,
              lhs.description == rhs.description, lhs.author == rhs.author, lhs.type == rhs.type,
              lhs.hasLargeMedia == rhs.hasLargeMedia, lhs.showLargeMedia == rhs.showLargeMedia,
              lhs.showMediaAboveDescription == rhs.showMediaAboveDescription,
              lhs.skipConfirmation == rhs.skipConfirmation, lhs.showAboveText == rhs.showAboveText,
              lhs.instantViewVersion == rhs.instantViewVersion else { return false }
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
        guard lhs.isDisabled == rhs.isDisabled, lhs.url == rhs.url, lhs.forceSmallMedia == rhs.forceSmallMedia,
              lhs.forceLargeMedia == rhs.forceLargeMedia, lhs.showAboveText == rhs.showAboveText else { return false }
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
        guard lhs.media == rhs.media, lhs.caption == rhs.caption else { return false }
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
        guard lhs.document == rhs.document, lhs.backgroundType == rhs.backgroundType else { return false }
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
        guard lhs.type == rhs.type, lhs.photo == rhs.photo,
              lhs.createsJoinRequest == rhs.createsJoinRequest else { return false }
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
        guard lhs.url == rhs.url, lhs.animation == rhs.animation, lhs.thumbnail == rhs.thumbnail,
              lhs.duration == rhs.duration, lhs.width == rhs.width, lhs.height == rhs.height else { return false }
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
        guard lhs.url == rhs.url, lhs.audio == rhs.audio, lhs.thumbnail == rhs.thumbnail, lhs.duration == rhs.duration,
              lhs.width == rhs.width, lhs.height == rhs.height else { return false }
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
        guard lhs.url == rhs.url, lhs.video == rhs.video, lhs.thumbnail == rhs.thumbnail, lhs.duration == rhs.duration,
              lhs.width == rhs.width, lhs.height == rhs.height else { return false }
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
        guard lhs.url == rhs.url, lhs.mimeType == rhs.mimeType, lhs.duration == rhs.duration else { return false }
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
        guard lhs.url == rhs.url, lhs.mimeType == rhs.mimeType, lhs.width == rhs.width, lhs.height == rhs.height,
              lhs.duration == rhs.duration else { return false }
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
        guard lhs.gift == rhs.gift, lhs.auctionEndDate == rhs.auctionEndDate else { return false }
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
        guard lhs.storyPosterChatId == rhs.storyPosterChatId, lhs.storyId == rhs.storyId else { return false }
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
        guard lhs.storyPosterChatId == rhs.storyPosterChatId, lhs.storyId == rhs.storyId else { return false }
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
        guard lhs.photoIcon == rhs.photoIcon, lhs.videoIcon == rhs.videoIcon else { return false }
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
        guard lhs.documents == rhs.documents, lhs.settings == rhs.settings else { return false }
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
        guard lhs.photo == rhs.photo, lhs.isBot == rhs.isBot else { return false }
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
        guard lhs.video == rhs.video, lhs.cover == rhs.cover,
              lhs.startTimestamp == rhs.startTimestamp else { return false }
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
        guard lhs.photo == rhs.photo, lhs.isLiveStream == rhs.isLiveStream,
              lhs.joinsAsSpeaker == rhs.joinsAsSpeaker else { return false }
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
        guard lhs.location == rhs.location, lhs.livePeriod == rhs.livePeriod, lhs.heading == rhs.heading,
              lhs.proximityAlertRadius == rhs.proximityAlertRadius else { return false }
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
        guard lhs.latitude == rhs.latitude, lhs.longitude == rhs.longitude,
              lhs.horizontalAccuracy == rhs.horizontalAccuracy else { return false }
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
        guard lhs.id == rhs.id, lhs.senderId == rhs.senderId, lhs.receiverId == rhs.receiverId,
              lhs.chatId == rhs.chatId,
              lhs.sendingState == rhs.sendingState, lhs.schedulingState == rhs.schedulingState,
              lhs.isOutgoing == rhs.isOutgoing, lhs.isPinned == rhs.isPinned, lhs.isFromOffline == rhs.isFromOffline,
              lhs.canBeSaved == rhs.canBeSaved, lhs.hasTimestampedMedia == rhs.hasTimestampedMedia,
              lhs.isChannelPost == rhs.isChannelPost, lhs.isPaidStarSuggestedPost == rhs.isPaidStarSuggestedPost,
              lhs.isPaidGramSuggestedPost == rhs.isPaidGramSuggestedPost,
              lhs.containsUnreadMention == rhs.containsUnreadMention,
              lhs.containsUnreadPollVotes == rhs.containsUnreadPollVotes, lhs.date == rhs.date,
              lhs.editDate == rhs.editDate, lhs.forwardInfo == rhs.forwardInfo, lhs.importInfo == rhs.importInfo,
              lhs.interactionInfo == rhs.interactionInfo, lhs.unreadReactions == rhs.unreadReactions,
              lhs.factCheck == rhs.factCheck, lhs.suggestedPostInfo == rhs.suggestedPostInfo,
              lhs.replyTo == rhs.replyTo,
              lhs.topicId == rhs.topicId, lhs.selfDestructType == rhs.selfDestructType,
              lhs.selfDestructIn == rhs.selfDestructIn, lhs.autoDeleteIn == rhs.autoDeleteIn,
              lhs.viaBotUserId == rhs.viaBotUserId, lhs.guestBotCallerId == rhs.guestBotCallerId,
              lhs.senderBusinessBotUserId == rhs.senderBusinessBotUserId, lhs.senderBoostCount == rhs.senderBoostCount,
              lhs.senderTag == rhs.senderTag, lhs.paidMessageStarCount == rhs.paidMessageStarCount,
              lhs.authorSignature == rhs.authorSignature, lhs.mediaAlbumId == rhs.mediaAlbumId,
              lhs.effectId == rhs.effectId, lhs.restrictionInfo == rhs.restrictionInfo,
              lhs.summaryLanguageCode == rhs.summaryLanguageCode, lhs.content == rhs.content,
              lhs.ephemeralContent == rhs.ephemeralContent, lhs.replyMarkup == rhs.replyMarkup,
              lhs.ephemeralMessageId == rhs.ephemeralMessageId,
              lhs.chatInstance == rhs.chatInstance else { return false }
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
        guard lhs.animatedEmoji == rhs.animatedEmoji, lhs.emoji == rhs.emoji else { return false }
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
        guard lhs.audio == rhs.audio, lhs.caption == rhs.caption else { return false }
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
        guard lhs.title == rhs.title, lhs.memberUserIds == rhs.memberUserIds else { return false }
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
        guard lhs.uniqueId == rhs.uniqueId, lhs.isVideo == rhs.isVideo, lhs.discardReason == rhs.discardReason,
              lhs.duration == rhs.duration else { return false }
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
        guard lhs.requestMessageId == rhs.requestMessageId, lhs.oldHasProtectedContent == rhs.oldHasProtectedContent,
              lhs.newHasProtectedContent == rhs.newHasProtectedContent else { return false }
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
        guard lhs.oldBackgroundMessageId == rhs.oldBackgroundMessageId, lhs.background == rhs.background,
              lhs.onlyForSelf == rhs.onlyForSelf else { return false }
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
        guard lhs.messageAutoDeleteTime == rhs.messageAutoDeleteTime,
              lhs.fromUserId == rhs.fromUserId else { return false }
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
        guard lhs.chat == rhs.chat, lhs.buttonId == rhs.buttonId else { return false }
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
        guard lhs.title == rhs.title, lhs.basicGroupId == rhs.basicGroupId else { return false }
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
        guard lhs.checklistMessageId == rhs.checklistMessageId, lhs.tasks == rhs.tasks else { return false }
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
        guard lhs.checklistMessageId == rhs.checklistMessageId, lhs.markedAsDoneTaskIds == rhs.markedAsDoneTaskIds,
              lhs.markedAsNotDoneTaskIds == rhs.markedAsNotDoneTaskIds else { return false }
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
        case (.messageTonWalletTransfer(let lhs), .messageTonWalletTransfer(let rhs)):
            lhs == rhs
        case (.messageTonConnectRequest(let lhs), .messageTonConnectRequest(let rhs)):
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
        case .messageTonWalletTransfer(let value):
            hasher.combine(80)
            hasher.combine(value)
        case .messageTonConnectRequest(let value):
            hasher.combine(81)
            hasher.combine(value)
        case .messageGift(let value):
            hasher.combine(82)
            hasher.combine(value)
        case .messageUpgradedGift(let value):
            hasher.combine(83)
            hasher.combine(value)
        case .messageRefundedUpgradedGift(let value):
            hasher.combine(84)
            hasher.combine(value)
        case .messageUpgradedGiftPurchaseOffer(let value):
            hasher.combine(85)
            hasher.combine(value)
        case .messageUpgradedGiftPurchaseOfferRejected(let value):
            hasher.combine(86)
            hasher.combine(value)
        case .messagePaidMessagesRefunded(let value):
            hasher.combine(87)
            hasher.combine(value)
        case .messagePaidMessagePriceChanged(let value):
            hasher.combine(88)
            hasher.combine(value)
        case .messageDirectMessagePriceChanged(let value):
            hasher.combine(89)
            hasher.combine(value)
        case .messageChecklistTasksDone(let value):
            hasher.combine(90)
            hasher.combine(value)
        case .messageChecklistTasksAdded(let value):
            hasher.combine(91)
            hasher.combine(value)
        case .messageSuggestedPostApprovalFailed(let value):
            hasher.combine(92)
            hasher.combine(value)
        case .messageSuggestedPostApproved(let value):
            hasher.combine(93)
            hasher.combine(value)
        case .messageSuggestedPostDeclined(let value):
            hasher.combine(94)
            hasher.combine(value)
        case .messageSuggestedPostPaid(let value):
            hasher.combine(95)
            hasher.combine(value)
        case .messageSuggestedPostRefunded(let value):
            hasher.combine(96)
            hasher.combine(value)
        case .messageContactRegistered:
            hasher.combine(97)
        case .messageUsersShared(let value):
            hasher.combine(98)
            hasher.combine(value)
        case .messageChatShared(let value):
            hasher.combine(99)
            hasher.combine(value)
        case .messageBotWriteAccessAllowed(let value):
            hasher.combine(100)
            hasher.combine(value)
        case .messageWebAppDataSent(let value):
            hasher.combine(101)
            hasher.combine(value)
        case .messageWebAppDataReceived(let value):
            hasher.combine(102)
            hasher.combine(value)
        case .messagePassportDataSent(let value):
            hasher.combine(103)
            hasher.combine(value)
        case .messagePassportDataReceived(let value):
            hasher.combine(104)
            hasher.combine(value)
        case .messageProximityAlertTriggered(let value):
            hasher.combine(105)
            hasher.combine(value)
        case .messageUnsupported:
            hasher.combine(106)
        }
    }
}

// MARK: - TDNativeMessageCopyOptions + @retroactive Hashable

extension TDNativeMessageCopyOptions: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sendCopy == rhs.sendCopy, lhs.replaceCaption == rhs.replaceCaption, lhs.newCaption == rhs.newCaption,
              lhs.newShowCaptionAboveMedia == rhs.newShowCaptionAboveMedia else { return false }
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
        guard lhs.initialState == rhs.initialState, lhs.finalState == rhs.finalState, lhs.emoji == rhs.emoji,
              lhs.value == rhs.value,
              lhs.successAnimationFrameNumber == rhs.successAnimationFrameNumber else { return false }
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
        guard lhs.isEnabled == rhs.isEnabled, lhs.paidMessageStarCount == rhs.paidMessageStarCount else { return false }
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
        guard lhs.document == rhs.document, lhs.caption == rhs.caption else { return false }
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
        guard lhs.name == rhs.name, lhs.isNameImplicit == rhs.isNameImplicit, lhs.icon == rhs.icon else { return false }
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
        guard lhs.name == rhs.name, lhs.editIconCustomEmojiId == rhs.editIconCustomEmojiId,
              lhs.iconCustomEmojiId == rhs.iconCustomEmojiId else { return false }
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
        guard lhs.origin == rhs.origin, lhs.date == rhs.date, lhs.source == rhs.source,
              lhs.publicServiceAnnouncementType == rhs.publicServiceAnnouncementType else { return false }
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
        guard lhs.gameMessageId == rhs.gameMessageId, lhs.gameId == rhs.gameId,
              lhs.score == rhs.score else { return false }
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
        guard lhs.gift == rhs.gift, lhs.senderId == rhs.senderId, lhs.receiverId == rhs.receiverId,
              lhs.receivedGiftId == rhs.receivedGiftId, lhs.text == rhs.text,
              lhs.uniqueGiftNumber == rhs.uniqueGiftNumber, lhs.sellStarCount == rhs.sellStarCount,
              lhs.prepaidUpgradeStarCount == rhs.prepaidUpgradeStarCount,
              lhs.isUpgradeSeparate == rhs.isUpgradeSeparate,
              lhs.isFromAuction == rhs.isFromAuction, lhs.isPrivate == rhs.isPrivate, lhs.isSaved == rhs.isSaved,
              lhs.isPrepaidUpgrade == rhs.isPrepaidUpgrade, lhs.canBeUpgraded == rhs.canBeUpgraded,
              lhs.wasConverted == rhs.wasConverted, lhs.wasUpgraded == rhs.wasUpgraded,
              lhs.wasRefunded == rhs.wasRefunded, lhs.upgradedReceivedGiftId == rhs.upgradedReceivedGiftId,
              lhs.prepaidUpgradeHash == rhs.prepaidUpgradeHash else { return false }
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
        guard lhs.gifterUserId == rhs.gifterUserId, lhs.receiverUserId == rhs.receiverUserId,
              lhs.gramAmount == rhs.gramAmount, lhs.transactionId == rhs.transactionId,
              lhs.sticker == rhs.sticker else { return false }
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
        guard lhs.gifterUserId == rhs.gifterUserId, lhs.receiverUserId == rhs.receiverUserId, lhs.text == rhs.text,
              lhs.currency == rhs.currency, lhs.amount == rhs.amount, lhs.cryptocurrency == rhs.cryptocurrency,
              lhs.cryptocurrencyAmount == rhs.cryptocurrencyAmount, lhs.monthCount == rhs.monthCount,
              lhs.dayCount == rhs.dayCount, lhs.sticker == rhs.sticker else { return false }
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
        guard lhs.gifterUserId == rhs.gifterUserId, lhs.receiverUserId == rhs.receiverUserId,
              lhs.currency == rhs.currency, lhs.amount == rhs.amount, lhs.cryptocurrency == rhs.cryptocurrency,
              lhs.cryptocurrencyAmount == rhs.cryptocurrencyAmount, lhs.starCount == rhs.starCount,
              lhs.transactionId == rhs.transactionId, lhs.sticker == rhs.sticker else { return false }
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
        guard lhs.parameters == rhs.parameters, lhs.winnerCount == rhs.winnerCount, lhs.prize == rhs.prize,
              lhs.sticker == rhs.sticker else { return false }
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
        guard lhs.giveawayMessageId == rhs.giveawayMessageId, lhs.winnerCount == rhs.winnerCount,
              lhs.isStarGiveaway == rhs.isStarGiveaway,
              lhs.unclaimedPrizeCount == rhs.unclaimedPrizeCount else { return false }
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
        guard lhs.starCount == rhs.starCount, lhs.transactionId == rhs.transactionId,
              lhs.boostedChatId == rhs.boostedChatId, lhs.giveawayMessageId == rhs.giveawayMessageId,
              lhs.isUnclaimed == rhs.isUnclaimed, lhs.sticker == rhs.sticker else { return false }
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
        guard lhs.boostedChatId == rhs.boostedChatId, lhs.giveawayMessageId == rhs.giveawayMessageId,
              lhs.additionalChatCount == rhs.additionalChatCount,
              lhs.actualWinnersSelectionDate == rhs.actualWinnersSelectionDate,
              lhs.onlyNewMembers == rhs.onlyNewMembers,
              lhs.wasRefunded == rhs.wasRefunded, lhs.prize == rhs.prize, lhs.prizeDescription == rhs.prizeDescription,
              lhs.winnerCount == rhs.winnerCount, lhs.winnerUserIds == rhs.winnerUserIds,
              lhs.unclaimedPrizeCount == rhs.unclaimedPrizeCount else { return false }
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
        guard lhs.uniqueId == rhs.uniqueId, lhs.isActive == rhs.isActive, lhs.wasMissed == rhs.wasMissed,
              lhs.isVideo == rhs.isVideo, lhs.duration == rhs.duration,
              lhs.otherParticipantIds == rhs.otherParticipantIds else { return false }
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
        guard lhs.senderName == rhs.senderName, lhs.date == rhs.date else { return false }
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
        guard lhs.viewCount == rhs.viewCount, lhs.forwardCount == rhs.forwardCount, lhs.replyInfo == rhs.replyInfo,
              lhs.reactions == rhs.reactions else { return false }
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
        guard lhs.groupCallId == rhs.groupCallId, lhs.userIds == rhs.userIds else { return false }
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
        guard lhs.productInfo == rhs.productInfo, lhs.currency == rhs.currency, lhs.totalAmount == rhs.totalAmount,
              lhs.startParameter == rhs.startParameter, lhs.isTest == rhs.isTest,
              lhs.needShippingAddress == rhs.needShippingAddress, lhs.receiptMessageId == rhs.receiptMessageId,
              lhs.paidMedia == rhs.paidMedia, lhs.paidMediaCaption == rhs.paidMediaCaption else { return false }
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
        guard lhs.location == rhs.location, lhs.expiresIn == rhs.expiresIn else { return false }
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
        guard lhs.botUserId == rhs.botUserId, lhs.managerBotUserId == rhs.managerBotUserId else { return false }
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
        guard lhs.chatId == rhs.chatId, lhs.messageId == rhs.messageId,
              lhs.authorSignature == rhs.authorSignature else { return false }
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
        guard lhs.senderChatId == rhs.senderChatId, lhs.authorSignature == rhs.authorSignature else { return false }
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
        guard lhs.starCount == rhs.starCount, lhs.media == rhs.media, lhs.caption == rhs.caption,
              lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia else { return false }
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
        guard lhs.messageCount == rhs.messageCount, lhs.starCount == rhs.starCount else { return false }
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
        guard lhs.elements == rhs.elements, lhs.credentials == rhs.credentials else { return false }
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
        guard lhs.ownerId == rhs.ownerId, lhs.currency == rhs.currency, lhs.totalAmount == rhs.totalAmount,
              lhs.invoicePayload == rhs.invoicePayload, lhs.telegramPaymentChargeId == rhs.telegramPaymentChargeId,
              lhs.providerPaymentChargeId == rhs.providerPaymentChargeId else { return false }
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
        guard lhs.invoiceChatId == rhs.invoiceChatId, lhs.invoiceMessageId == rhs.invoiceMessageId,
              lhs.currency == rhs.currency, lhs.totalAmount == rhs.totalAmount,
              lhs.subscriptionUntilDate == rhs.subscriptionUntilDate, lhs.isRecurring == rhs.isRecurring,
              lhs.isFirstRecurring == rhs.isFirstRecurring, lhs.invoiceName == rhs.invoiceName else { return false }
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
        guard lhs.currency == rhs.currency, lhs.totalAmount == rhs.totalAmount,
              lhs.subscriptionUntilDate == rhs.subscriptionUntilDate, lhs.isRecurring == rhs.isRecurring,
              lhs.isFirstRecurring == rhs.isFirstRecurring, lhs.invoicePayload == rhs.invoicePayload,
              lhs.shippingOptionId == rhs.shippingOptionId, lhs.orderInfo == rhs.orderInfo,
              lhs.telegramPaymentChargeId == rhs.telegramPaymentChargeId,
              lhs.providerPaymentChargeId == rhs.providerPaymentChargeId else { return false }
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
        guard lhs.poll == rhs.poll, lhs.description == rhs.description, lhs.media == rhs.media,
              lhs.canAddOption == rhs.canAddOption else { return false }
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
        guard lhs.pollMessageId == rhs.pollMessageId, lhs.optionId == rhs.optionId,
              lhs.text == rhs.text else { return false }
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
        guard lhs.pollMessageId == rhs.pollMessageId, lhs.optionId == rhs.optionId,
              lhs.text == rhs.text else { return false }
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
        guard lhs.creatorId == rhs.creatorId, lhs.text == rhs.text, lhs.isFromGiveaway == rhs.isFromGiveaway,
              lhs.isUnclaimed == rhs.isUnclaimed, lhs.currency == rhs.currency, lhs.amount == rhs.amount,
              lhs.cryptocurrency == rhs.cryptocurrency, lhs.cryptocurrencyAmount == rhs.cryptocurrencyAmount,
              lhs.monthCount == rhs.monthCount, lhs.dayCount == rhs.dayCount, lhs.sticker == rhs.sticker,
              lhs.code == rhs.code else { return false }
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
        guard lhs.canAddOffer == rhs.canAddOffer, lhs.canAddTasks == rhs.canAddTasks,
              lhs.canBeApproved == rhs.canBeApproved, lhs.canBeCopied == rhs.canBeCopied,
              lhs.canBeCopiedToSecretChat == rhs.canBeCopiedToSecretChat, lhs.canBeDeclined == rhs.canBeDeclined,
              lhs.canBeDeletedOnlyForSelf == rhs.canBeDeletedOnlyForSelf,
              lhs.canBeDeletedForAllUsers == rhs.canBeDeletedForAllUsers, lhs.canBeEdited == rhs.canBeEdited,
              lhs.canBeForwarded == rhs.canBeForwarded, lhs.canBePaid == rhs.canBePaid,
              lhs.canBePinned == rhs.canBePinned, lhs.canBeReplied == rhs.canBeReplied,
              lhs.canBeRepliedInAnotherChat == rhs.canBeRepliedInAnotherChat, lhs.canBeSaved == rhs.canBeSaved,
              lhs.canBeSharedInStory == rhs.canBeSharedInStory, lhs.canDeleteReactions == rhs.canDeleteReactions,
              lhs.canEditMedia == rhs.canEditMedia, lhs.canEditSchedulingState == rhs.canEditSchedulingState,
              lhs.canEditSuggestedPostInfo == rhs.canEditSuggestedPostInfo, lhs.canGetAuthor == rhs.canGetAuthor,
              lhs.canGetEmbeddingCode == rhs.canGetEmbeddingCode, lhs.canGetLink == rhs.canGetLink,
              lhs.canGetMediaTimestampLinks == rhs.canGetMediaTimestampLinks,
              lhs.canGetMessageThread == rhs.canGetMessageThread,
              lhs.canGetPollVoteStatistics == rhs.canGetPollVoteStatistics, lhs.canGetReadDate == rhs.canGetReadDate,
              lhs.canGetStatistics == rhs.canGetStatistics,
              lhs.canGetVideoAdvertisements == rhs.canGetVideoAdvertisements, lhs.canGetViewers == rhs.canGetViewers,
              lhs.canMarkTasksAsDone == rhs.canMarkTasksAsDone, lhs.canRecognizeSpeech == rhs.canRecognizeSpeech,
              lhs.canReportChat == rhs.canReportChat, lhs.canReportReactions == rhs.canReportReactions,
              lhs.canReportSupergroupSpam == rhs.canReportSupergroupSpam, lhs.canSetFactCheck == rhs.canSetFactCheck,
              lhs.customEmojiIds == rhs.customEmojiIds,
              lhs.hasProtectedContentByCurrentUser == rhs.hasProtectedContentByCurrentUser,
              lhs.hasProtectedContentByOtherUser == rhs.hasProtectedContentByOtherUser,
              lhs.needShowStatistics == rhs.needShowStatistics else { return false }
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
        hasher.combine(customEmojiIds)
        hasher.combine(hasProtectedContentByCurrentUser)
        hasher.combine(hasProtectedContentByOtherUser)
        hasher.combine(needShowStatistics)
    }
}

// MARK: - TDNativeMessageProximityAlertTriggered + @retroactive Hashable

extension TDNativeMessageProximityAlertTriggered: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.travelerId == rhs.travelerId, lhs.watcherId == rhs.watcherId,
              lhs.distance == rhs.distance else { return false }
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
        guard lhs.gift == rhs.gift, lhs.senderId == rhs.senderId, lhs.receiverId == rhs.receiverId,
              lhs.origin == rhs.origin else { return false }
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
        guard lhs.replyCount == rhs.replyCount, lhs.recentReplierIds == rhs.recentReplierIds,
              lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId,
              lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId,
              lhs.lastMessageId == rhs.lastMessageId else { return false }
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
        guard lhs.chatId == rhs.chatId, lhs.messageId == rhs.messageId, lhs.quote == rhs.quote,
              lhs.checklistTaskId == rhs.checklistTaskId, lhs.pollOptionId == rhs.pollOptionId,
              lhs.origin == rhs.origin,
              lhs.originSendDate == rhs.originSendDate, lhs.content == rhs.content else { return false }
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
        guard lhs.storyPosterChatId == rhs.storyPosterChatId, lhs.storyId == rhs.storyId else { return false }
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
        guard lhs.sendDate == rhs.sendDate, lhs.repeatPeriod == rhs.repeatPeriod else { return false }
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
        guard lhs.error == rhs.error, lhs.canRetry == rhs.canRetry, lhs.needAnotherSender == rhs.needAnotherSender,
              lhs.needAnotherReplyQuote == rhs.needAnotherReplyQuote, lhs.needDropReply == rhs.needDropReply,
              lhs.requiredPaidMessageStarCount == rhs.requiredPaidMessageStarCount,
              lhs.retryAfter == rhs.retryAfter else { return false }
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
        guard lhs.initialState == rhs.initialState, lhs.finalState == rhs.finalState, lhs.value == rhs.value,
              lhs.stakeGramAmount == rhs.stakeGramAmount,
              lhs.prizeGramAmount == rhs.prizeGramAmount else { return false }
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
        guard lhs.storyPosterChatId == rhs.storyPosterChatId, lhs.storyId == rhs.storyId,
              lhs.viaMention == rhs.viaMention else { return false }
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
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId, lhs.price == rhs.price else { return false }
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
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId, lhs.price == rhs.price,
              lhs.sendDate == rhs.sendDate else { return false }
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
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId, lhs.comment == rhs.comment else { return false }
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
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId, lhs.starAmount == rhs.starAmount,
              lhs.gramAmount == rhs.gramAmount else { return false }
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
        guard lhs.suggestedPostMessageId == rhs.suggestedPostMessageId, lhs.reason == rhs.reason else { return false }
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
        guard lhs.text == rhs.text, lhs.linkPreview == rhs.linkPreview,
              lhs.linkPreviewOptions == rhs.linkPreviewOptions else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(linkPreview)
        hasher.combine(linkPreviewOptions)
    }
}

// MARK: - TDNativeMessageTonConnectRequest + @retroactive Hashable

extension TDNativeMessageTonConnectRequest: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sessionId == rhs.sessionId, lhs.state == rhs.state, lhs.dappName == rhs.dappName,
              lhs.topic == rhs.topic, lhs.traceId == rhs.traceId else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sessionId)
        hasher.combine(state)
        hasher.combine(dappName)
        hasher.combine(topic)
        hasher.combine(traceId)
    }
}

// MARK: - TDNativeMessageTonWalletTransfer + @retroactive Hashable

extension TDNativeMessageTonWalletTransfer: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.senderUserId == rhs.senderUserId, lhs.transactionId == rhs.transactionId,
              lhs.peerAddress == rhs.peerAddress, lhs.amount == rhs.amount, lhs.comment == rhs.comment,
              lhs.isCommentEncrypted == rhs.isCommentEncrypted else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(senderUserId)
        hasher.combine(transactionId)
        hasher.combine(peerAddress)
        hasher.combine(amount)
        hasher.combine(comment)
        hasher.combine(isCommentEncrypted)
    }
}

// MARK: - TDNativeMessageUpgradedGift + @retroactive Hashable

extension TDNativeMessageUpgradedGift: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.gift == rhs.gift, lhs.senderId == rhs.senderId, lhs.receiverId == rhs.receiverId,
              lhs.origin == rhs.origin, lhs.receivedGiftId == rhs.receivedGiftId, lhs.text == rhs.text,
              lhs.isPrivate == rhs.isPrivate, lhs.isSaved == rhs.isSaved, lhs.canBeTransferred == rhs.canBeTransferred,
              lhs.wasTransferred == rhs.wasTransferred, lhs.transferStarCount == rhs.transferStarCount,
              lhs.dropOriginalDetailsStarCount == rhs.dropOriginalDetailsStarCount,
              lhs.nextTransferDate == rhs.nextTransferDate, lhs.nextResaleDate == rhs.nextResaleDate,
              lhs.exportDate == rhs.exportDate, lhs.craftDate == rhs.craftDate else { return false }
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
        guard lhs.gift == rhs.gift, lhs.state == rhs.state, lhs.price == rhs.price,
              lhs.expirationDate == rhs.expirationDate else { return false }
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
        guard lhs.gift == rhs.gift, lhs.price == rhs.price, lhs.offerMessageId == rhs.offerMessageId,
              lhs.wasExpired == rhs.wasExpired else { return false }
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
        guard lhs.users == rhs.users, lhs.buttonId == rhs.buttonId else { return false }
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
        guard lhs.groupCallId == rhs.groupCallId, lhs.startDate == rhs.startDate else { return false }
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
        guard lhs.videoNote == rhs.videoNote, lhs.isViewed == rhs.isViewed,
              lhs.isSecret == rhs.isSecret else { return false }
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
        guard lhs.voiceNote == rhs.voiceNote, lhs.caption == rhs.caption,
              lhs.isListened == rhs.isListened else { return false }
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
        guard lhs.buttonText == rhs.buttonText, lhs.data == rhs.data else { return false }
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
        guard lhs.name == rhs.name, lhs.phoneNumber == rhs.phoneNumber, lhs.emailAddress == rhs.emailAddress,
              lhs.shippingAddress == rhs.shippingAddress else { return false }
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
        guard lhs.animation == rhs.animation, lhs.caption == rhs.caption, lhs.needAutoplay == rhs.needAutoplay,
              lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.audio == rhs.audio, lhs.caption == rhs.caption else { return false }
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
        guard lhs.author == rhs.author, lhs.publishDate == rhs.publishDate else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.credit == rhs.credit else { return false }
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
        guard lhs.buttons == rhs.buttons, lhs.align == rhs.align else { return false }
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
        guard lhs.text == rhs.text, lhs.credit == rhs.credit else { return false }
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
        guard lhs.title == rhs.title, lhs.photo == rhs.photo, lhs.accentColorId == rhs.accentColorId,
              lhs.username == rhs.username else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.caption == rhs.caption else { return false }
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
        guard lhs.header == rhs.header, lhs.blocks == rhs.blocks, lhs.isOpen == rhs.isOpen else { return false }
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
        guard lhs.document == rhs.document, lhs.caption == rhs.caption else { return false }
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
        guard lhs.url == rhs.url, lhs.html == rhs.html, lhs.posterPhoto == rhs.posterPhoto, lhs.width == rhs.width,
              lhs.height == rhs.height, lhs.caption == rhs.caption, lhs.isFullWidth == rhs.isFullWidth,
              lhs.allowScrolling == rhs.allowScrolling else { return false }
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
        guard lhs.url == rhs.url, lhs.author == rhs.author, lhs.authorPhoto == rhs.authorPhoto, lhs.date == rhs.date,
              lhs.blocks == rhs.blocks, lhs.caption == rhs.caption else { return false }
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
        guard lhs.text == rhs.text, lhs.credit == rhs.credit else { return false }
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
        guard lhs.label == rhs.label, lhs.blocks == rhs.blocks, lhs.hasCheckbox == rhs.hasCheckbox,
              lhs.isChecked == rhs.isChecked, lhs.value == rhs.value, lhs.type == rhs.type else { return false }
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
        guard lhs.location == rhs.location, lhs.zoom == rhs.zoom, lhs.width == rhs.width, lhs.height == rhs.height,
              lhs.caption == rhs.caption else { return false }
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
        guard lhs.photo == rhs.photo, lhs.caption == rhs.caption, lhs.url == rhs.url,
              lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.text == rhs.text, lhs.language == rhs.language else { return false }
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
        guard lhs.text == rhs.text, lhs.credit == rhs.credit else { return false }
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
        guard lhs.url == rhs.url, lhs.title == rhs.title, lhs.description == rhs.description, lhs.photo == rhs.photo,
              lhs.author == rhs.author, lhs.publishDate == rhs.publishDate else { return false }
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
        guard lhs.header == rhs.header, lhs.articles == rhs.articles else { return false }
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
        guard lhs.text == rhs.text, lhs.size == rhs.size else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.caption == rhs.caption else { return false }
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
        guard lhs.caption == rhs.caption, lhs.cells == rhs.cells, lhs.isBordered == rhs.isBordered,
              lhs.isStriped == rhs.isStriped, lhs.isCompact == rhs.isCompact else { return false }
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
        guard lhs.text == rhs.text, lhs.isHeader == rhs.isHeader, lhs.colspan == rhs.colspan,
              lhs.rowspan == rhs.rowspan,
              lhs.align == rhs.align, lhs.valign == rhs.valign else { return false }
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
        guard lhs.video == rhs.video, lhs.caption == rhs.caption, lhs.needAutoplay == rhs.needAutoplay,
              lhs.isLooped == rhs.isLooped, lhs.hasSpoiler == rhs.hasSpoiler else { return false }
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
        guard lhs.voiceNote == rhs.voiceNote, lhs.caption == rhs.caption else { return false }
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
        guard lhs.photo == rhs.photo, lhs.video == rhs.video else { return false }
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
        guard lhs.width == rhs.width, lhs.height == rhs.height, lhs.duration == rhs.duration,
              lhs.minithumbnail == rhs.minithumbnail else { return false }
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
        guard lhs.video == rhs.video, lhs.cover == rhs.cover,
              lhs.startTimestamp == rhs.startTimestamp else { return false }
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
        guard lhs.id == rhs.id, lhs.question == rhs.question, lhs.options == rhs.options,
              lhs.totalVoterCount == rhs.totalVoterCount, lhs.recentVoterIds == rhs.recentVoterIds,
              lhs.canGetVoters == rhs.canGetVoters, lhs.canSeeResults == rhs.canSeeResults,
              lhs.isAnonymous == rhs.isAnonymous, lhs.allowsMultipleAnswers == rhs.allowsMultipleAnswers,
              lhs.allowsRevoting == rhs.allowsRevoting, lhs.membersOnly == rhs.membersOnly,
              lhs.countryCodes == rhs.countryCodes, lhs.optionOrder == rhs.optionOrder, lhs.type == rhs.type,
              lhs.openPeriod == rhs.openPeriod, lhs.closeDate == rhs.closeDate, lhs.isClosed == rhs.isClosed,
              lhs.voteRestrictionReason == rhs.voteRestrictionReason else { return false }
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
        guard lhs.url == rhs.url, lhs.linkPreview == rhs.linkPreview else { return false }
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
        guard lhs.photo == rhs.photo, lhs.video == rhs.video else { return false }
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
        guard lhs.video == rhs.video, lhs.alternativeVideos == rhs.alternativeVideos,
              lhs.storyboards == rhs.storyboards,
              lhs.cover == rhs.cover, lhs.startTimestamp == rhs.startTimestamp else { return false }
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
        guard lhs.id == rhs.id, lhs.text == rhs.text, lhs.media == rhs.media, lhs.voterCount == rhs.voterCount,
              lhs.votePercentage == rhs.votePercentage, lhs.recentVoterIds == rhs.recentVoterIds,
              lhs.isChosen == rhs.isChosen, lhs.isBeingChosen == rhs.isBeingChosen, lhs.author == rhs.author,
              lhs.additionDate == rhs.additionDate else { return false }
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
        guard lhs.correctOptionIds == rhs.correctOptionIds, lhs.explanation == rhs.explanation,
              lhs.explanationMedia == rhs.explanationMedia else { return false }
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
        guard lhs.title == rhs.title, lhs.description == rhs.description, lhs.photo == rhs.photo else { return false }
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
        guard lhs.id == rhs.id, lhs.small == rhs.small, lhs.big == rhs.big, lhs.minithumbnail == rhs.minithumbnail,
              lhs.hasAnimation == rhs.hasAnimation, lhs.isPersonal == rhs.isPersonal else { return false }
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
        guard lhs.server == rhs.server, lhs.port == rhs.port, lhs.type == rhs.type else { return false }
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
        guard lhs.username == rhs.username, lhs.password == rhs.password,
              lhs.httpOnly == rhs.httpOnly else { return false }
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
        guard lhs.username == rhs.username, lhs.password == rhs.password else { return false }
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
        guard lhs.isPersonal == rhs.isPersonal,
              lhs.inputFieldPlaceholder == rhs.inputFieldPlaceholder else { return false }
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
        guard lhs.rows == rhs.rows, lhs.forceReply == rhs.forceReply else { return false }
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
        guard lhs.rows == rhs.rows, lhs.isPersistent == rhs.isPersistent, lhs.resizeKeyboard == rhs.resizeKeyboard,
              lhs.oneTime == rhs.oneTime, lhs.isPersonal == rhs.isPersonal, lhs.forceReply == rhs.forceReply,
              lhs.inputFieldPlaceholder == rhs.inputFieldPlaceholder else { return false }
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
        guard lhs.restrictionReason == rhs.restrictionReason,
              lhs.hasSensitiveContent == rhs.hasSensitiveContent else { return false }
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
        guard lhs.blocks == rhs.blocks, lhs.isRtl == rhs.isRtl, lhs.isFull == rhs.isFull else { return false }
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
        guard lhs.text == rhs.text, lhs.media == rhs.media else { return false }
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
        guard lhs.text == rhs.text, lhs.media == rhs.media else { return false }
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
        case (.richTextTonAddress(let lhs), .richTextTonAddress(let rhs)):
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
        case .richTextTonAddress(let value):
            hasher.combine(14)
            hasher.combine(value)
        case .richTextBotCommand(let value):
            hasher.combine(15)
            hasher.combine(value)
        case .richTextFixed(let value):
            hasher.combine(16)
            hasher.combine(value)
        case .richTextMentionName(let value):
            hasher.combine(17)
            hasher.combine(value)
        case .richTextUrl(let value):
            hasher.combine(18)
            hasher.combine(value)
        case .richTextEmailAddress(let value):
            hasher.combine(19)
            hasher.combine(value)
        case .richTextPhoneNumber(let value):
            hasher.combine(20)
            hasher.combine(value)
        case .richTextCustomEmoji(let value):
            hasher.combine(21)
            hasher.combine(value)
        case .richTextIcon(let value):
            hasher.combine(22)
            hasher.combine(value)
        case .richTextMathematicalExpression(let value):
            hasher.combine(23)
            hasher.combine(value)
        case .richTextButton(let value):
            hasher.combine(24)
            hasher.combine(value)
        case .richTextDiff(let value):
            hasher.combine(25)
            hasher.combine(value)
        case .richTextReference(let value):
            hasher.combine(26)
            hasher.combine(value)
        case .richTextReferenceLink(let value):
            hasher.combine(27)
            hasher.combine(value)
        case .richTextAnchor(let value):
            hasher.combine(28)
            hasher.combine(value)
        case .richTextAnchorLink(let value):
            hasher.combine(29)
            hasher.combine(value)
        case .richTexts(let value):
            hasher.combine(30)
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
        guard lhs.text == rhs.text, lhs.anchorName == rhs.anchorName, lhs.url == rhs.url else { return false }
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
        guard lhs.text == rhs.text, lhs.bankCardNumber == rhs.bankCardNumber else { return false }
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
        guard lhs.text == rhs.text, lhs.botCommand == rhs.botCommand else { return false }
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
        guard lhs.text == rhs.text, lhs.cashtag == rhs.cashtag else { return false }
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
        guard lhs.customEmojiId == rhs.customEmojiId, lhs.alternativeText == rhs.alternativeText else { return false }
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
        guard lhs.text == rhs.text, lhs.unixTime == rhs.unixTime,
              lhs.formattingType == rhs.formattingType else { return false }
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
        guard lhs.text == rhs.text, lhs.oldText == rhs.oldText else { return false }
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
        guard lhs.text == rhs.text, lhs.emailAddress == rhs.emailAddress else { return false }
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
        guard lhs.text == rhs.text, lhs.hashtag == rhs.hashtag else { return false }
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
        guard lhs.document == rhs.document, lhs.width == rhs.width, lhs.height == rhs.height else { return false }
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
        guard lhs.text == rhs.text, lhs.username == rhs.username else { return false }
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
        guard lhs.text == rhs.text, lhs.userId == rhs.userId else { return false }
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
        guard lhs.text == rhs.text, lhs.phoneNumber == rhs.phoneNumber else { return false }
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
        guard lhs.name == rhs.name, lhs.text == rhs.text else { return false }
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
        guard lhs.text == rhs.text, lhs.referenceName == rhs.referenceName, lhs.url == rhs.url else { return false }
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

// MARK: - TDNativeRichTextTonAddress + @retroactive Hashable

extension TDNativeRichTextTonAddress: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.text == rhs.text, lhs.address == rhs.address else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(address)
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
        guard lhs.text == rhs.text, lhs.url == rhs.url, lhs.isCached == rhs.isCached else { return false }
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
        guard lhs.chatId == rhs.chatId, lhs.title == rhs.title, lhs.username == rhs.username,
              lhs.photo == rhs.photo else { return false }
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
        guard lhs.userId == rhs.userId, lhs.firstName == rhs.firstName, lhs.lastName == rhs.lastName,
              lhs.username == rhs.username, lhs.photo == rhs.photo else { return false }
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
        guard lhs.starCount == rhs.starCount, lhs.nanostarCount == rhs.nanostarCount else { return false }
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
        guard lhs.price == rhs.price, lhs.sendDate == rhs.sendDate, lhs.state == rhs.state,
              lhs.canBeApproved == rhs.canBeApproved, lhs.canBeDeclined == rhs.canBeDeclined else { return false }
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
        guard lhs.id == rhs.id, lhs.usernames == rhs.usernames, lhs.date == rhs.date, lhs.status == rhs.status,
              lhs.memberCount == rhs.memberCount, lhs.boostLevel == rhs.boostLevel,
              lhs.hasAutomaticTranslation == rhs.hasAutomaticTranslation, lhs.hasLinkedChat == rhs.hasLinkedChat,
              lhs.hasLocation == rhs.hasLocation, lhs.signMessages == rhs.signMessages,
              lhs.showMessageSender == rhs.showMessageSender, lhs.joinToSendMessages == rhs.joinToSendMessages,
              lhs.joinByRequest == rhs.joinByRequest, lhs.isSlowModeEnabled == rhs.isSlowModeEnabled,
              lhs.isChannel == rhs.isChannel, lhs.isBroadcastGroup == rhs.isBroadcastGroup, lhs.isForum == rhs.isForum,
              lhs.isDirectMessagesGroup == rhs.isDirectMessagesGroup,
              lhs.isAdministeredDirectMessagesGroup == rhs.isAdministeredDirectMessagesGroup,
              lhs.verificationStatus == rhs.verificationStatus,
              lhs.hasDirectMessagesGroup == rhs.hasDirectMessagesGroup,
              lhs.hasForumTabs == rhs.hasForumTabs, lhs.restrictionInfo == rhs.restrictionInfo,
              lhs.paidMessageStarCount == rhs.paidMessageStarCount,
              lhs.activeStoryState == rhs.activeStoryState else { return false }
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
        guard lhs.allowUserChats == rhs.allowUserChats, lhs.allowBotChats == rhs.allowBotChats,
              lhs.allowGroupChats == rhs.allowGroupChats,
              lhs.allowChannelChats == rhs.allowChannelChats else { return false }
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
        guard lhs.text == rhs.text, lhs.minUserAge == rhs.minUserAge,
              lhs.showPopup == rhs.showPopup else { return false }
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
        guard lhs.text == rhs.text, lhs.position == rhs.position, lhs.isManual == rhs.isManual else { return false }
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
        guard lhs.baseTheme == rhs.baseTheme, lhs.accentColor == rhs.accentColor, lhs.background == rhs.background,
              lhs.outgoingMessageFill == rhs.outgoingMessageFill,
              lhs.animateOutgoingMessageFill == rhs.animateOutgoingMessageFill,
              lhs.hasOutgoingMessageAccentColor == rhs.hasOutgoingMessageAccentColor,
              lhs.outgoingMessageAccentColor == rhs.outgoingMessageAccentColor else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(baseTheme)
        hasher.combine(accentColor)
        hasher.combine(background)
        hasher.combine(outgoingMessageFill)
        hasher.combine(animateOutgoingMessageFill)
        hasher.combine(hasOutgoingMessageAccentColor)
        hasher.combine(outgoingMessageAccentColor)
    }
}

// MARK: - TDNativeTonConnectConnectItem + @retroactive Hashable

extension TDNativeTonConnectConnectItem: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.tonConnectConnectItemAddress(let lhs), .tonConnectConnectItemAddress(let rhs)):
            lhs == rhs
        case (.tonConnectConnectItemProof(let lhs), .tonConnectConnectItemProof(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .tonConnectConnectItemAddress(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .tonConnectConnectItemProof(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeTonConnectConnectItemAddress + @retroactive Hashable

extension TDNativeTonConnectConnectItemAddress: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.network == rhs.network else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(network)
    }
}

// MARK: - TDNativeTonConnectConnectItemProof + @retroactive Hashable

extension TDNativeTonConnectConnectItemProof: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.payload == rhs.payload else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(payload)
    }
}

// MARK: - TDNativeTonConnectConnectRequest + @retroactive Hashable

extension TDNativeTonConnectConnectRequest: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.manifestUrl == rhs.manifestUrl, lhs.items == rhs.items else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(manifestUrl)
        hasher.combine(items)
    }
}

// MARK: - TDNativeTonConnectRequestState + @retroactive Hashable

extension TDNativeTonConnectRequestState: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.tonConnectRequestStatePending(let lhs), .tonConnectRequestStatePending(let rhs)):
            lhs == rhs
        case (.tonConnectRequestStateAccepted, .tonConnectRequestStateAccepted):
            true
        case (.tonConnectRequestStateRejected, .tonConnectRequestStateRejected):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .tonConnectRequestStatePending(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .tonConnectRequestStateAccepted:
            hasher.combine(1)
        case .tonConnectRequestStateRejected:
            hasher.combine(2)
        }
    }
}

// MARK: - TDNativeTonConnectRequestStatePending + @retroactive Hashable

extension TDNativeTonConnectRequestStatePending: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.expirationDate == rhs.expirationDate else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(expirationDate)
    }
}

// MARK: - TDNativeTonWalletTransferReceiver + @retroactive Hashable

extension TDNativeTonWalletTransferReceiver: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.tonWalletTransferReceiverUser(let lhs), .tonWalletTransferReceiverUser(let rhs)):
            lhs == rhs
        case (.tonWalletTransferReceiverAddress(let lhs), .tonWalletTransferReceiverAddress(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .tonWalletTransferReceiverUser(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .tonWalletTransferReceiverAddress(let value):
            hasher.combine(1)
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeTonWalletTransferReceiverAddress + @retroactive Hashable

extension TDNativeTonWalletTransferReceiverAddress: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.address == rhs.address else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(address)
    }
}

// MARK: - TDNativeTonWalletTransferReceiverUser + @retroactive Hashable

extension TDNativeTonWalletTransferReceiverUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.username == rhs.username else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(username)
    }
}

// MARK: - TDNativeUnreadReaction + @retroactive Hashable

extension TDNativeUnreadReaction: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type == rhs.type, lhs.senderId == rhs.senderId, lhs.isBig == rhs.isBig else { return false }
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
        guard lhs.chatId == rhs.chatId, lhs.forumTopicId == rhs.forumTopicId, lhs.isPinned == rhs.isPinned,
              lhs.lastReadInboxMessageId == rhs.lastReadInboxMessageId,
              lhs.lastReadOutboxMessageId == rhs.lastReadOutboxMessageId,
              lhs.unreadMentionCount == rhs.unreadMentionCount, lhs.unreadReactionCount == rhs.unreadReactionCount,
              lhs.unreadPollVoteCount == rhs.unreadPollVoteCount, lhs.notificationSettings == rhs.notificationSettings,
              lhs.draftMessage == rhs.draftMessage else { return false }
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
        guard lhs.message == rhs.message, lhs.oldMessageId == rhs.oldMessageId,
              lhs.error == rhs.error else { return false }
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
        guard lhs.message == rhs.message, lhs.oldMessageId == rhs.oldMessageId else { return false }
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
        guard lhs.id == rhs.id, lhs.regularGiftId == rhs.regularGiftId, lhs.publisherChatId == rhs.publisherChatId,
              lhs.title == rhs.title, lhs.name == rhs.name, lhs.number == rhs.number,
              lhs.totalUpgradedCount == rhs.totalUpgradedCount, lhs.maxUpgradedCount == rhs.maxUpgradedCount,
              lhs.isBurned == rhs.isBurned, lhs.isCrafted == rhs.isCrafted, lhs.isPremium == rhs.isPremium,
              lhs.isThemeAvailable == rhs.isThemeAvailable, lhs.usedThemeChatId == rhs.usedThemeChatId,
              lhs.hostId == rhs.hostId, lhs.ownerId == rhs.ownerId, lhs.ownerAddress == rhs.ownerAddress,
              lhs.ownerName == rhs.ownerName, lhs.giftAddress == rhs.giftAddress, lhs.model == rhs.model,
              lhs.symbol == rhs.symbol, lhs.backdrop == rhs.backdrop, lhs.originalDetails == rhs.originalDetails,
              lhs.colors == rhs.colors, lhs.resaleParameters == rhs.resaleParameters,
              lhs.canSendPurchaseOffer == rhs.canSendPurchaseOffer,
              lhs.craftProbabilityPerMille == rhs.craftProbabilityPerMille, lhs.valueCurrency == rhs.valueCurrency,
              lhs.valueAmount == rhs.valueAmount, lhs.valueUsdAmount == rhs.valueUsdAmount else { return false }
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
        guard lhs.id == rhs.id, lhs.name == rhs.name, lhs.colors == rhs.colors,
              lhs.rarity == rhs.rarity else { return false }
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
        guard lhs.centerColor == rhs.centerColor, lhs.edgeColor == rhs.edgeColor, lhs.symbolColor == rhs.symbolColor,
              lhs.textColor == rhs.textColor else { return false }
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
        guard lhs.id == rhs.id, lhs.modelCustomEmojiId == rhs.modelCustomEmojiId,
              lhs.symbolCustomEmojiId == rhs.symbolCustomEmojiId,
              lhs.lightThemeAccentColor == rhs.lightThemeAccentColor,
              lhs.lightThemeColors == rhs.lightThemeColors, lhs.darkThemeAccentColor == rhs.darkThemeAccentColor,
              lhs.darkThemeColors == rhs.darkThemeColors else { return false }
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
        guard lhs.name == rhs.name, lhs.sticker == rhs.sticker, lhs.rarity == rhs.rarity,
              lhs.isCrafted == rhs.isCrafted else { return false }
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
        guard lhs.senderId == rhs.senderId, lhs.receiverId == rhs.receiverId, lhs.text == rhs.text,
              lhs.date == rhs.date else { return false }
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
        guard lhs.name == rhs.name, lhs.sticker == rhs.sticker, lhs.rarity == rhs.rarity else { return false }
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
        guard lhs.id == rhs.id, lhs.firstName == rhs.firstName, lhs.lastName == rhs.lastName,
              lhs.usernames == rhs.usernames, lhs.phoneNumber == rhs.phoneNumber, lhs.status == rhs.status,
              lhs.profilePhoto == rhs.profilePhoto, lhs.accentColorId == rhs.accentColorId,
              lhs.backgroundCustomEmojiId == rhs.backgroundCustomEmojiId,
              lhs.upgradedGiftColors == rhs.upgradedGiftColors, lhs.profileAccentColorId == rhs.profileAccentColorId,
              lhs.profileBackgroundCustomEmojiId == rhs.profileBackgroundCustomEmojiId,
              lhs.emojiStatus == rhs.emojiStatus, lhs.isContact == rhs.isContact,
              lhs.isMutualContact == rhs.isMutualContact, lhs.isCloseFriend == rhs.isCloseFriend,
              lhs.verificationStatus == rhs.verificationStatus, lhs.isPremium == rhs.isPremium,
              lhs.isSupport == rhs.isSupport, lhs.restrictionInfo == rhs.restrictionInfo,
              lhs.activeStoryState == rhs.activeStoryState, lhs.restrictsNewChats == rhs.restrictsNewChats,
              lhs.paidMessageStarCount == rhs.paidMessageStarCount, lhs.haveAccess == rhs.haveAccess,
              lhs.type == rhs.type, lhs.languageCode == rhs.languageCode,
              lhs.addedToAttachmentMenu == rhs.addedToAttachmentMenu else { return false }
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
        guard lhs.canBeEdited == rhs.canBeEdited, lhs.canJoinGroups == rhs.canJoinGroups,
              lhs.canReadAllGroupMessages == rhs.canReadAllGroupMessages, lhs.hasMainWebApp == rhs.hasMainWebApp,
              lhs.hasTopics == rhs.hasTopics, lhs.allowsUsersToCreateTopics == rhs.allowsUsersToCreateTopics,
              lhs.canManageBots == rhs.canManageBots, lhs.isInline == rhs.isInline,
              lhs.inlineQueryPlaceholder == rhs.inlineQueryPlaceholder,
              lhs.supportsGuestQueries == rhs.supportsGuestQueries, lhs.isGuard == rhs.isGuard,
              lhs.needLocation == rhs.needLocation, lhs.canConnectToBusiness == rhs.canConnectToBusiness,
              lhs.canBeAddedToAttachmentMenu == rhs.canBeAddedToAttachmentMenu,
              lhs.activeUserCount == rhs.activeUserCount else { return false }
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
        guard lhs.activeUsernames == rhs.activeUsernames, lhs.disabledUsernames == rhs.disabledUsernames,
              lhs.editableUsername == rhs.editableUsername, lhs.collectibleUsernames == rhs.collectibleUsernames,
              lhs.secondaryUsername == rhs.secondaryUsername else { return false }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(activeUsernames)
        hasher.combine(disabledUsernames)
        hasher.combine(editableUsername)
        hasher.combine(collectibleUsernames)
        hasher.combine(secondaryUsername)
    }
}

// MARK: - TDNativeVenue + @retroactive Hashable

extension TDNativeVenue: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.location == rhs.location, lhs.title == rhs.title, lhs.address == rhs.address,
              lhs.provider == rhs.provider, lhs.id == rhs.id, lhs.type == rhs.type else { return false }
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
        guard lhs.isVerified == rhs.isVerified, lhs.isScam == rhs.isScam, lhs.isFake == rhs.isFake,
              lhs.botVerificationIconCustomEmojiId == rhs.botVerificationIconCustomEmojiId else { return false }
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
        guard lhs.groupCallId == rhs.groupCallId, lhs.hasParticipants == rhs.hasParticipants,
              lhs.defaultParticipantId == rhs.defaultParticipantId else { return false }
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
        guard lhs.duration == rhs.duration, lhs.waveform == rhs.waveform, lhs.length == rhs.length,
              lhs.minithumbnail == rhs.minithumbnail, lhs.thumbnail == rhs.thumbnail,
              lhs.speechRecognitionResult == rhs.speechRecognitionResult, lhs.video == rhs.video else { return false }
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
        guard lhs.duration == rhs.duration, lhs.waveform == rhs.waveform, lhs.mimeType == rhs.mimeType,
              lhs.speechRecognitionResult == rhs.speechRecognitionResult, lhs.voice == rhs.voice else { return false }
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
        guard lhs.shortName == rhs.shortName, lhs.title == rhs.title, lhs.description == rhs.description,
              lhs.photo == rhs.photo, lhs.animation == rhs.animation else { return false }
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
