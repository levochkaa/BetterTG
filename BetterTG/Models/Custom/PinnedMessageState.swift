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
    /// The pinned message the banner shows and where it stands among the chat's pins (ChatPinnedMessage).
    struct Selection: Equatable {
        let messageID: Int64
        /// 0 is the oldest pin.
        let index: Int
        let totalCount: Int
    }

    /// What the reference message is (ChatController.PinnedReferenceMessage): the newest visible message, or the pin
    /// the user just jumped to from the banner.
    enum Reference: Equatable {
        case visible(Int64)
        case scrolled(Int64)
    }

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

    /// ChatController.topPinnedMessageSignal over the loaded pins, newest first as TDLib returns them: the newest pin
    /// at or above the newest visible message, or after a jump the newest pin older than its target, wrapping to the
    /// newest pin from the oldest. Without a reference, the newest pin.
    static func selection(pinnedIDs newestFirst: [Int64], totalCount: Int, reference: Reference?) -> Selection? {
        guard !newestFirst.isEmpty else { return nil }
        let ascending = Array(newestFirst.reversed())
        let total = max(totalCount, ascending.count)
        // Indexes count from the oldest pin; pins older than the loaded page stay unseen.
        let firstIndex = total - ascending.count
        let top = Selection(messageID: ascending[ascending.count - 1], index: total - 1, totalCount: total)
        if case .scrolled(let target) = reference, target == ascending[0], firstIndex == 0 {
            return top
        }
        var selected = Selection(messageID: ascending[0], index: firstIndex, totalCount: total)
        for (offset, id) in ascending.enumerated() {
            let matches =
                switch reference {
                case .scrolled(let target): id < target
                case .visible(let newestVisible): id <= newestVisible
                case nil: true
                }
            if matches { selected = Selection(messageID: id, index: firstIndex + offset, totalCount: total) }
        }
        return selected
    }

    static func fetchErrorMeansNoPinnedMessage(_ error: Swift.Error) -> Bool {
        (error as? TDLibError)?.code == 404
    }
}
