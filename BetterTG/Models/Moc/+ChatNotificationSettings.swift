// +ChatNotificationSettings.swift

import SwiftUI
import TDLibKit

extension ChatNotificationSettings {
    static let moc = ChatNotificationSettings(
        disableMentionNotifications: false,
        disablePinnedMessageNotifications: false,
        muteFor: 0,
        showPreview: false,
        soundId: 0,
        useDefaultDisableMentionNotifications: false,
        useDefaultDisablePinnedMessageNotifications: false,
        useDefaultMuteFor: false,
        useDefaultShowPreview: false,
        useDefaultSound: false
    )
}
