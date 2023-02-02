// ChatPermission.swift

import SwiftUI
import TDLibKit

extension ChatPermissions {
    static let moc = ChatPermissions(
        canAddWebPagePreviews: false,
        canChangeInfo: false,
        canInviteUsers: false,
        canManageTopics: false,
        canPinMessages: false,
        canSendMediaMessages: false,
        canSendMessages: false,
        canSendOtherMessages: false,
        canSendPolls: false
    )
}
