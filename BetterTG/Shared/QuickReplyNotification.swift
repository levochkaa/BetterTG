// QuickReplyNotification.swift

import Foundation
import TDLibKitDynamic

enum QuickReplyNotification {
    // MARK: Internal

    static let actionIdentifier = "TELEGRAM_REPLY"
    static let categoryIdentifier = "TELEGRAM_MESSAGE_REPLY"
    static let messageCategoryIdentifier = "TELEGRAM_MESSAGE"

    static func canSendText(to chat: Chat, using client: TDLibClient) async -> Bool {
        switch chat.type {
        case .chatTypePrivate(let privateChat):
            guard let result = try? await client.canSendMessageToUser(
                onlyLocal: false,
                userId: privateChat.userId,
            ) else { return false }
            if case .canSendMessageToUserResultOk = result {
                return true
            }
            return false
        case .chatTypeBasicGroup(let basicGroupChat):
            guard let group = try? await client.getBasicGroup(
                basicGroupId: basicGroupChat.basicGroupId,
            ) else { return false }
            return canSendText(status: group.status, defaultPermissions: chat.permissions)
        case .chatTypeSupergroup(let supergroupChat):
            guard let group = try? await client.getSupergroup(
                supergroupId: supergroupChat.supergroupId,
            ) else { return false }
            return canSendText(
                status: group.status,
                defaultPermissions: chat.permissions,
                requiresPayment: group.paidMessageStarCount > 0,
                requiresPostPermission: group.isChannel || group.isBroadcastGroup,
            )
        case .chatTypeSecret:
            return false
        }
    }

    // MARK: Private

    private static func canSendText(
        status: ChatMemberStatus,
        defaultPermissions: ChatPermissions,
        requiresPayment: Bool = false,
        requiresPostPermission: Bool = false,
    ) -> Bool {
        switch status {
        case .chatMemberStatusCreator(let creator):
            creator.isMember
        case .chatMemberStatusAdministrator(let administrator):
            !requiresPostPermission || administrator.rights.canPostMessages
        case .chatMemberStatusMember:
            !requiresPayment
                && !requiresPostPermission
                && defaultPermissions.canSendBasicMessages
        case .chatMemberStatusRestricted(let restricted):
            !requiresPayment
                && !requiresPostPermission
                && restricted.isMember
                && restricted.permissions.canSendBasicMessages
        case .chatMemberStatusBanned, .chatMemberStatusLeft:
            false
        }
    }
}
