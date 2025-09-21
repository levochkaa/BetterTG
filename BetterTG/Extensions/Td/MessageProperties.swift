// MessageProperties.swift

import SwiftUI
import TDLibKit

extension MessageProperties {
    static let `default` = MessageProperties(
        canAddOffer: false,
        canAddTasks: false,
        canBeApproved: false,
        canBeCopied: false,
        canBeCopiedToSecretChat: false,
        canBeDeclined: false,
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
        canEditSuggestedPostInfo: false,
        canGetAuthor: false,
        canGetEmbeddingCode: false,
        canGetLink: false,
        canGetMediaTimestampLinks: false,
        canGetMessageThread: false,
        canGetReadDate: false,
        canGetStatistics: false,
        canGetVideoAdvertisements: false,
        canGetViewers: false,
        canMarkTasksAsDone: false,
        canRecognizeSpeech: false,
        canReportChat: false,
        canReportReactions: false,
        canReportSupergroupSpam: false,
        canSetFactCheck: false,
        needShowStatistics: false,
    )
}
