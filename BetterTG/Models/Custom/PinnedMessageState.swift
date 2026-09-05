// PinnedMessageState.swift

import TDLibKit

// MARK: - MessagePinMode

enum MessagePinMode: Equatable {
    case channel
    case groupNotify
    case groupSilent
    case privateForBoth
    case privateForSelf
    case savedMessages

    var disableNotification: Bool {
        self != .groupNotify
    }

    var onlyForSelf: Bool {
        self == .privateForSelf || self == .savedMessages
    }
}

// MARK: - PinnedMessageState

enum PinnedMessageState {
    static func visibleMessage(
        newest: Message?,
        locallyHiddenMessageID: Int64?,
        supported: Bool,
    ) -> Message? {
        guard supported,
              let newest,
              newest.id != locallyHiddenMessageID
        else { return nil }
        return newest
    }

    static func fetchErrorMeansNoPinnedMessage(_ error: Swift.Error) -> Bool {
        (error as? TDLibError)?.code == 404
    }
}
