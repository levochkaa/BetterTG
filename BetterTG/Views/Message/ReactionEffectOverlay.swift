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

    private static var bundled = [String: LottieAnimation]()

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

    /// A custom emoji reaction, as StandaloneReactionAnimation plays one inline: Telegram's bundled
    /// generic_reaction_small_effect bursts over three times the icon's size, and generic_reaction_inline_pattern
    /// throws seven copies of the emoji out of it. The chip keeps its icon.
    static func play(customEmoji sticker: Sticker, iconView: UIView, client: TDLibClient) {
        Task { [weak iconView] in
            async let effect = bundledAnimation("generic_reaction_small_effect")
            async let pattern = bundledAnimation("generic_reaction_inline_pattern")
            let (effectValue, patternValue) = await (effect, pattern)
            guard let iconView, let window = iconView.window, !iconView.isHidden, let effectValue, let patternValue
            else { return }
            let iconFrame = iconView.convert(iconView.bounds, to: window)
            guard iconFrame.width > 0, window.bounds.intersects(iconFrame) else { return }
            let side = max(iconFrame.width, iconFrame.height)
            let effectFrame = CGRect(
                x: iconFrame.midX - side / 2,
                y: iconFrame.midY - side / 2,
                width: side,
                height: side,
            ).insetBy(dx: -side, dy: -side)
            let effectView = makeView(effectValue, frame: effectFrame)
            let patternView = LottieAnimationView(
                animation: patternValue,
                configuration: LottieConfiguration(renderingEngine: .mainThread),
            )
            patternView.frame = effectFrame.insetBy(dx: -20, dy: -20)
            patternView.contentMode = .scaleAspectFit
            patternView.isUserInteractionEnabled = false
            patternView.backgroundBehavior = .stop
            // The placeholders' outlines mark where the emoji go; Telegram hides them.
            patternView.setValueProvider(
                FloatValueProvider(0),
                keypath: AnimationKeypath(keypath: "**.Stroke 1.Opacity"),
            )
            // InlineStickerItemLayer draws the emoji from cache at once; here the copies wait for their first frame.
            // Each copy renders at the size the pattern shows its 512-unit layer on screen, scaled up to those units,
            // so
            // seven players don't decode full-size frames.
            let renderSide = max(24, ceil(patternView.bounds.width))
            let emojiViews = (1...7).map { _ in
                let emoji = CustomEmojiInlineView(frame: CGRect(x: 0, y: 0, width: renderSide, height: renderSide))
                emoji.isUserInteractionEnabled = false
                emoji.layer.anchorPoint = .zero
                emoji.layer.position = .zero
                emoji.transform = CGAffineTransform(scaleX: 512 / renderSide, y: 512 / renderSide)
                return emoji
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var pending = emojiViews.count
                var resumed = false
                func finish() {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                for emoji in emojiViews {
                    emoji.onFirstFrameReady = {
                        pending -= 1
                        if pending == 0 { finish() }
                    }
                    emoji.configure(sticker: sticker, client: client)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { finish() }
            }
            for (index, emoji) in emojiViews.enumerated() {
                let host = AnimationSubview()
                emoji.setPlaybackVisible(true)
                host.addSubview(emoji)
                patternView.addSubview(host, forLayerAt: AnimationKeypath(keypath: "placeholder_\(index + 1)"))
            }
            guard iconView.window === window else { return }
            window.addSubview(patternView)
            window.addSubview(effectView)
            effectView.play { [weak effectView] _ in effectView?.removeFromSuperview() }
            patternView.play { [weak patternView] _ in patternView?.removeFromSuperview() }
        }
    }

    private static func bundledAnimation(_ name: String) async -> LottieAnimation? {
        if let cached = bundled[name] { return cached }
        guard let path = Bundle.main.path(forResource: name, ofType: "json") else { return nil }
        let animation = await Task.detached(priority: .userInitiated) {
            LottieAnimation.filepath(path)
        }.value
        if let animation { bundled[name] = animation }
        return animation
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
