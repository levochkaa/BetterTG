// MessageContentKind.swift

import TDLibKit

extension MessageContent {
    /// The TDLib constructor of this content. TDLibKit's generated instance `typeID` reports
    /// `messageUnsupported` for every payload-free case, so two different service messages would compare equal.
    var constructorID: Int32 {
        switch self {
        case .messageExpiredPhoto: TDNativeMessageExpiredPhoto.typeID
        case .messageExpiredVideo: TDNativeMessageExpiredVideo.typeID
        case .messageExpiredVideoNote: TDNativeMessageExpiredVideoNote.typeID
        case .messageExpiredVoiceNote: TDNativeMessageExpiredVoiceNote.typeID
        case .messageChatDeletePhoto: TDNativeMessageChatDeletePhoto.typeID
        case .messageChatJoinByLink: TDNativeMessageChatJoinByLink.typeID
        case .messageChatJoinByRequest: TDNativeMessageChatJoinByRequest.typeID
        case .messageChatRemovedFromCommunity: TDNativeMessageChatRemovedFromCommunity.typeID
        case .messageScreenshotTaken: TDNativeMessageScreenshotTaken.typeID
        case .messageContactRegistered: TDNativeMessageContactRegistered.typeID
        case .messageUnsupported: TDNativeMessageUnsupported.typeID
        default: typeID
        }
    }
}
