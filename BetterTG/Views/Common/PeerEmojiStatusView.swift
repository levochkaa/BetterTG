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

/// EmojiStatusComponent in ChatListItem's 20 pt status slot: the status emoji filling it, or the Premium star
/// (EntityInputPremiumIcon) inset by 4 of its 44 pt in the accent colour.
final class PeerEmojiStatusView: UIView {
    static let side: CGFloat = 20

    private static let premiumImage: UIImage? = {
        guard let star = UIImage(named: "ChatList/PremiumStatusIcon") else { return nil }
        let inset = side * 4 / 44
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            .image { _ in
                star.draw(in: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset))
            }
            .withRenderingMode(.alwaysTemplate)
    }()

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    private(set) var status: PeerEmojiStatus?

    private let premiumView = UIImageView(image: premiumImage)
    private var emojiView: CustomEmojiInlineView?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        premiumView.tintColor = .systemBlue
        premiumView.frame = bounds
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

    func configure(_ status: PeerEmojiStatus?, client: TDLibClient) {
        guard status != self.status else { return }
        self.status = status
        loadTask?.cancel()
        loadTask = nil
        emojiView?.prepareForReuse()
        emojiView?.removeFromSuperview()
        emojiView = nil
        premiumView.isHidden = status != .premium
        guard case .emoji(let identifier) = status else { return }
        loadTask = Task { [weak self] in
            let sticker = await CustomEmojiStickerRepository.shared.stickers(
                for: [identifier],
                client: client,
            )[identifier]
            guard !Task.isCancelled, let sticker, let self, self.status == .emoji(identifier) else { return }
            install(sticker, client: client)
        }
    }

    private func install(_ sticker: Sticker, client: TDLibClient) {
        let view = CustomEmojiInlineView()
        // ChatListItem stops status emoji with Emoji Animations off.
        view.energySaving = EnergySavingRole(item: .loopEmoji, whenOff: .still)
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        addSubview(view)
        emojiView = view
        view.configure(sticker: sticker, client: client)
        view.setPlaybackVisible(window != nil)
    }
}
