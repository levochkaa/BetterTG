// MessageEffectStore.swift

import Combine
import TDLibKit

// MARK: - MessageEffectStore

/// The message effects TDLib describes by getMessageEffect, as Telegram's AvailableMessageEffects keeps them: a
/// bubble with an effect shows its emoji in the status line and plays its animation. An effect is asked for once per
/// client; `loaded` tells the chat to redraw the messages that carry it.
@MainActor final class MessageEffectStore {
    static let shared = MessageEffectStore()

    let loaded = PassthroughSubject<Int64, Never>()

    /// updateAvailableMessageEffects: the effects messages can be sent with, from reactions and from stickers.
    private(set) var availableReactionEffectIDs = [Int64]()
    private(set) var availableStickerEffectIDs = [Int64]()

    private var availableClientID: Int32?

    private var clientID: Int32?
    private var effects = [Int64: MessageEffect]()
    private var loading = Set<Int64>()

    /// The effect's animation: an emoji reaction's effect, or a premium sticker's premium animation.
    static func animationFile(of effect: MessageEffect) -> File? {
        switch effect.type {
        case .messageEffectTypeEmojiReaction(let reaction):
            return reaction.effectAnimation.sticker
        case .messageEffectTypePremiumSticker(let premium):
            if case .stickerFullTypeRegular(let regular) = premium.sticker.fullType {
                return regular.premiumAnimation
            }
            return nil
        }
    }

    func receive(_ update: UpdateAvailableMessageEffects, clientID: Int32) {
        availableClientID = clientID
        availableReactionEffectIDs = update.reactionEffectIds
        availableStickerEffectIDs = update.stickerEffectIds
    }

    /// The emoji effects a message can be sent with by this account: Premium ones only for Premium.
    func sendableReactionEffects(client: TDLibClient) async -> [MessageEffect] {
        let isPremium = await (try? client.getMe().isPremium) ?? false
        var result = [MessageEffect]()
        for id in availableReactionEffectIDs.prefix(24) {
            guard let effect = try? await client.send(TDNativeRequests.getMessageEffect(effectId: id)),
                  isPremium || !effect.isPremium, !effect.emoji.isEmpty
            else { continue }
            effects[id] = effect
            result.append(effect)
        }
        return result
    }

    /// The effect if TDLib has described it; otherwise nil while it is asked for.
    func effect(_ id: Int64, client: TDLibClient) -> MessageEffect? {
        guard id != 0 else { return nil }
        if clientID != client.id {
            clientID = client.id
            effects = [:]
            loading = []
        }
        if let effect = effects[id] { return effect }
        guard loading.insert(id).inserted else { return nil }
        let clientID = client.id
        Task { [weak self] in
            let effect = try? await client.send(TDNativeRequests.getMessageEffect(effectId: id))
            guard let self, self.clientID == clientID else { return }
            loading.remove(id)
            guard let effect else { return }
            effects[id] = effect
            loaded.send(id)
        }
        return nil
    }
}
