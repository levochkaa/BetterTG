// MessageReactionState.swift

import TDLibKitDynamic

// MARK: - MessageReactionStateReducer

enum MessageReactionStateReducer {
    static func isChosen(
        _ type: ReactionType,
        in reactions: MessageReactions?,
    ) -> Bool {
        reactions?.reactions.first(where: { $0.type == type })?.isChosen == true
    }

    static func toggling(
        _ type: ReactionType,
        in reactions: MessageReactions?,
        areTags: Bool,
        maximumChosenCount: Int,
    ) -> MessageReactions? {
        guard !type.isPaid else { return reactions }
        var values = reactions?.reactions ?? []
        if let index = values.firstIndex(where: { $0.type == type }) {
            let current = values[index]
            if current.isChosen {
                let updatedCount = max(0, current.totalCount - 1)
                if updatedCount == 0 {
                    values.remove(at: index)
                } else {
                    values[index] = MessageReaction(
                        isChosen: false,
                        recentSenderIds: current.recentSenderIds,
                        totalCount: updatedCount,
                        type: current.type,
                        usedSenderId: nil,
                    )
                }
            } else {
                let chosenCount = values.lazy.filter(\.isChosen).count
                guard chosenCount < max(1, maximumChosenCount) else { return reactions }
                values[index] = MessageReaction(
                    isChosen: true,
                    recentSenderIds: current.recentSenderIds,
                    totalCount: current.totalCount + 1,
                    type: current.type,
                    usedSenderId: current.usedSenderId,
                )
            }
        } else {
            let chosenCount = values.lazy.filter(\.isChosen).count
            guard chosenCount < max(1, maximumChosenCount) else { return reactions }
            values.append(MessageReaction(
                isChosen: true,
                recentSenderIds: [],
                totalCount: 1,
                type: type,
                usedSenderId: nil,
            ))
        }
        guard !values.isEmpty else { return nil }
        return MessageReactions(
            areTags: reactions?.areTags ?? areTags,
            canGetAddedReactions: reactions?.canGetAddedReactions ?? false,
            paidReactors: reactions?.paidReactors ?? [],
            reactions: values,
        )
    }

    static func visible(_ reactions: MessageReactions?) -> [MessageReaction] {
        let values = reactions?.reactions.filter { !$0.type.isPaid && $0.totalCount > 0 } ?? []
        return values.enumerated()
            .sorted { lhs, rhs in
                let lhsScore = lhs.element.totalCount - (lhs.element.isChosen ? 1 : 0)
                let rhsScore = rhs.element.totalCount - (rhs.element.isChosen ? 1 : 0)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.element.isChosen != rhs.element.isChosen {
                    return lhs.element.isChosen
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

extension ReactionType {
    var isPaid: Bool {
        if case .reactionTypePaid = self {
            true
        } else {
            false
        }
    }

    var standardEmoji: String? {
        if case .reactionTypeEmoji(let reaction) = self {
            reaction.emoji
        } else {
            nil
        }
    }

    var customEmojiID: TdInt64? {
        if case .reactionTypeCustomEmoji(let reaction) = self {
            reaction.customEmojiId
        } else {
            nil
        }
    }

    var accessibilityName: String {
        switch self {
        case .reactionTypeEmoji(let reaction):
            reaction.emoji
        case .reactionTypeCustomEmoji:
            "Custom emoji"
        case .reactionTypePaid:
            "Paid reaction"
        }
    }

    var accessibilityIdentifierComponent: String {
        switch self {
        case .reactionTypeEmoji(let reaction):
            reaction.emoji
                .unicodeScalars
                .map { String($0.value, radix: 16) }
                .joined(separator: "-")
        case .reactionTypeCustomEmoji(let reaction):
            "custom-\(reaction.customEmojiId.rawValue)"
        case .reactionTypePaid:
            "paid"
        }
    }
}

extension AvailableReactions {
    var nonPremiumReactionTypes: [ReactionType] {
        var seen = Set<ReactionType>()
        return (topReactions + recentReactions + popularReactions)
            .filter { !$0.needsPremium && !$0.type.isPaid }
            .compactMap { reaction in
                seen.insert(reaction.type).inserted ? reaction.type : nil
            }
    }

    func allowsNonPremium(_ type: ReactionType) -> Bool {
        unavailabilityReason == nil && nonPremiumReactionTypes.contains(type)
    }
}

extension ChatAvailableReactions {
    var maximumChosenReactionCount: Int {
        switch self {
        case .chatAvailableReactionsAll(let reactions):
            reactions.maxReactionCount
        case .chatAvailableReactionsSome(let reactions):
            reactions.maxReactionCount
        }
    }
}
