// MessageProperties.swift

import SwiftUI
import TDLibKit

extension MessageProperties {
    static let `default` = MessageProperties(
        canBeCopiedToSecretChat: false,
        canBeDeletedForAllUsers: false,
        canBeDeletedOnlyForSelf: false,
        canBeEdited: false,
        canBeForwarded: false,
        canBePaid: false,
        canBePinned: false,
        canBeReplied: false,
        canBeRepliedInAnotherChat: false,
        canBeSaved: false,
        canBeSharedInStory: false,
        canEditMedia: false,
        canEditSchedulingState: false,
        canGetEmbeddingCode: false,
        canGetLink: false,
        canGetMediaTimestampLinks: false,
        canGetMessageThread: false,
        canGetReadDate: false,
        canGetStatistics: false,
        canGetViewers: false,
        canRecognizeSpeech: false,
        canReportChat: false,
        canReportReactions: false,
        canReportSupergroupSpam: false,
        canSetFactCheck: false,
        needShowStatistics: false
    )
}
