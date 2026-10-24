// ReactionEffectOverlay.swift

import Lottie
import TDLibKit
import UIKit

// MARK: - ReactionEffectOverlay

/// StandaloneReactionAnimation.animateReactionSelection for a standard reaction the user chose: the reaction's
/// center animation plays once over its chip's icon, which hides meanwhile, and its around animation bursts once over
/// three times the icon's size around it, above the chat.
@MainActor enum ReactionEffectOverlay {
    private struct Key: Hashable {
        let clientID: Int32
        let emoji: String
    }

    private static var reactions = [Key: EmojiReaction]()

    static func play(emoji: String, iconView: UIView, client: TDLibClient) {
        Task { [weak iconView] in
            guard let reaction = await emojiReaction(emoji, client: client),
                  let around = reaction.aroundAnimation, let center = reaction.centerAnimation
            else { return }
            async let aroundAnimation = animation(around, client: client)
            async let centerAnimation = animation(center, client: client)
            let (aroundValue, centerValue) = await (aroundAnimation, centerAnimation)
            guard let iconView, let window = iconView.window, !iconView.isHidden, let aroundValue, let centerValue
            else { return }
            let iconFrame = iconView.convert(iconView.bounds, to: window)
            guard iconFrame.width > 0, window.bounds.intersects(iconFrame) else { return }
            // ReactionNode fits the animation to the icon's square; the effect frame adds the icon's size each side.
            let side = max(iconFrame.width, iconFrame.height)
            let centerFrame = CGRect(
                x: iconFrame.midX - side / 2,
                y: iconFrame.midY - side / 2,
                width: side,
                height: side,
            )
            let effectFrame = centerFrame.insetBy(dx: -side, dy: -side)
            let centerView = makeView(centerValue, frame: centerFrame)
            let aroundView = makeView(aroundValue, frame: effectFrame)
            window.addSubview(centerView)
            window.addSubview(aroundView)
            iconView.alpha = 0
            centerView.play { [weak iconView, weak centerView] _ in
                iconView?.alpha = 1
                centerView?.removeFromSuperview()
            }
            aroundView.play { [weak aroundView] _ in aroundView?.removeFromSuperview() }
        }
    }

    private static func emojiReaction(_ emoji: String, client: TDLibClient) async -> EmojiReaction? {
        let key = Key(clientID: client.id, emoji: emoji)
        if let cached = reactions[key] { return cached }
        guard let reaction = try? await client.send(TDNativeRequests.getEmojiReaction(emoji: emoji)) else { return nil }
        reactions[key] = reaction
        return reaction
    }

    /// The sticker's TGS, downloaded at TDLib's top priority and decoded off the main thread.
    private static func animation(_ sticker: Sticker, client: TDLibClient) async -> LottieAnimation? {
        guard case .stickerFormatTgs = sticker.format else { return nil }
        var file = sticker.sticker
        if !file.local.isDownloadingCompleted {
            guard let downloaded = try? await client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            ) else { return nil }
            file = downloaded
        }
        guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return nil }
        return await TGSAnimationRepository.animation(at: file.local.path)
    }

    private static func makeView(_ animation: LottieAnimation, frame: CGRect) -> LottieAnimationView {
        let view = LottieAnimationView(animation: animation)
        view.frame = frame
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.backgroundBehavior = .stop
        return view
    }
}
