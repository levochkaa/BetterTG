// +User.swift

import SwiftUI
import TDLibKit

extension User {
    static let moc = User(
        addedToAttachmentMenu: false,
        emojiStatus: nil,
        firstName: "firstName",
        hasActiveStories: false,
        hasUnreadActiveStories: false,
        haveAccess: false,
        id: 0,
        isCloseFriend: false,
        isContact: false,
        isFake: false,
        isMutualContact: false,
        isPremium: false,
        isScam: false,
        isSupport: false,
        isVerified: false,
        languageCode: "en",
        lastName: "lastName",
        phoneNumber: "",
        profilePhoto: nil,
        restrictionReason: "",
        status: .userStatusEmpty,
        type: .userTypeUnknown,
        usernames: nil
    )
}
