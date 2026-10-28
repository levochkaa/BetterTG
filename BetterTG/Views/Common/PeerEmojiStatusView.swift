// PeerEmojiStatusView.swift

import TDLibKit
import UIKit

// MARK: - PeerEmojiStatus

/// ChatListItem's status icon after a peer's name: the emoji status a person or channel set (an upgraded gift's model
/// for a gift status), or the Premium star of a Premium user without one. A SCAM or FAKE label replaces both, and the
/// verified badge replaces the star.
enum PeerEmojiStatus: Equatable {
    case emoji(Int64)
    case premium

    @MainActor init?(chat: CustomChat, badge: PeerCredibilityBadge?) {
        guard !chat.isSavedMessages, badge != .scam, badge != .fake else { return nil }
        switch chat.chat.emojiStatus?.type {
        case .emojiStatusTypeCustomEmoji(let status):
            self = .emoji(status.customEmojiId)
        case .emojiStatusTypeUpgradedGift(let gift):
            self = .emoji(gift.modelCustomEmojiId)
        case nil:
            guard badge == nil, chat.user?.isPremium == true else { return nil }
            self = .premium
        }
    }
}

// MARK: - PeerEmojiStatusView

/// EmojiStatusComponent in a status slot after a name (20 pt in ChatListItem and ChatTitleView, 26 pt in
/// PeerInfoHeaderNode): the status emoji filling it, or the Premium star (EntityInputPremiumIcon) inset by 4 of its
/// 44 pt in the accent colour.
final class PeerEmojiStatusView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: side, height: side)
    }

    let side: CGFloat

    private(set) var status: PeerEmojiStatus?

    /// The loops the emoji plays each time it is shown; nil loops on.
    private let loopLimit: Int?
    private let premiumView = UIImageView()
    private var emojiView: CustomEmojiInlineView?
    private var loadTask: Task<Void, Never>?
    /// Whether the status shows what it will: the emoji's first frame, the star, or nothing.
    private var isShown = true
    private var shownHandlers = [() -> Void]()

    /// `loopLimit` is ChatListItem's and ChatTitleView's `.count(2)` by default; PeerInfoHeaderNode loops on.
    init(side: CGFloat = 20, loopLimit: Int? = 2) {
        self.side = side
        self.loopLimit = loopLimit
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        isUserInteractionEnabled = false
        premiumView.image = UIImage(named: "ChatList/PremiumStatusIcon")
        premiumView.contentMode = .scaleAspectFit
        premiumView.tintColor = .systemBlue
        premiumView.frame = bounds.insetBy(dx: side * 4 / 44, dy: side * 4 / 44)
        premiumView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        premiumView.isHidden = true
        addSubview(premiumView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        emojiView?.setPlaybackVisible(window != nil)
    }

    /// Calls `ready` once the status shows what it will, for a screen that waits to be shown ready: an emoji's first
    /// frame, or at once for the star or no status.
    func whenShown(_ ready: @escaping () -> Void) {
        guard !isShown else { return ready() }
        shownHandlers.append(ready)
    }

    /// `client` loads a status emoji; the Premium star needs none.
    func configure(_ status: PeerEmojiStatus?, client: TDLibClient?) {
        guard status != self.status else { return }
        self.status = status
        loadTask?.cancel()
        loadTask = nil
        emojiView?.prepareForReuse()
        emojiView?.removeFromSuperview()
        emojiView = nil
        premiumView.isHidden = status != .premium
        guard case .emoji(let identifier) = status, let client else { return markShown() }
        isShown = false
        loadTask = Task { [weak self] in
            let sticker = await CustomEmojiStickerRepository.shared.stickers(
                for: [identifier],
                client: client,
            )[identifier]
            guard !Task.isCancelled, let self, self.status == .emoji(identifier) else { return }
            guard let sticker else { return markShown() }
            install(sticker, client: client)
        }
    }

    private func markShown() {
        isShown = true
        let handlers = shownHandlers
        shownHandlers = []
        for handler in handlers {
            handler()
        }
    }

    private func install(_ sticker: Sticker, client: TDLibClient) {
        let view = CustomEmojiInlineView()
        // ChatListItem stops status emoji with Emoji Animations off.
        view.energySaving = EnergySavingRole(item: .loopEmoji, whenOff: .still)
        view.loopLimit = loopLimit
        // EmojiStatusComponent's themeColor: a template status takes the accent colour.
        view.templateColor = .systemBlue
        view.repaintsAccentPacks = true
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        addSubview(view)
        emojiView = view
        view.onFirstFrameReady = { [weak self, weak view] in
            guard let self, emojiView === view, !isShown else { return }
            markShown()
        }
        view.configure(sticker: sticker, client: client)
        view.setPlaybackVisible(window != nil)
    }
}
