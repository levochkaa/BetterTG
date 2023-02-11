// +User.swift

import SwiftUI
import TDLibKit

extension User {
    static let moc = User(
        addedToAttachmentMenu: false,
        emojiStatus: nil,
        firstName: "firstName",
        haveAccess: false,
        id: 0,
        isContact: false,
        isFake: false,
        isMutualContact: false,
        isPremium: false,
        isScam: false,
        isSupport: false,
        isVerified: false,
        languageCode: "",
        lastName: "lastName",
        phoneNumber: "",
        profilePhoto: nil,
        restrictionReason: "",
        status: .userStatusEmpty,
        type: .userTypeRegular,
        usernames: nil
    )
}
