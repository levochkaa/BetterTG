// GiftActions.swift

import TDLibKit
import UIKit

// MARK: - GiftActions

/// What the gift's tile menu and its sheet share for the account's own upgraded gift: Transfer, Wear and Take Off.
@MainActor enum GiftActions {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    /// formatCollectibleNumber with the gift's title: "Sakura Flower #46,271".
    static func title(_ upgraded: TDNativeUpgradedGift) -> String {
        upgraded.title + " #" + formatted(upgraded.number)
    }

    static func formatted(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func showError(_ error: Error, in host: UIViewController) {
        let message = (error as? TDLibError)?.message ?? error.localizedDescription
        TelegramUndoToast.show(text: message, in: host.view, bottomInset: 12, undo: nil)
    }

    // MARK: Transfer

    /// PeerInfoGiftsPaneNode's and GiftViewScreen's Transfer: a gift hosted on Fragment is locked there, one TDLib
    /// can't move yet says when it can (Try Later); otherwise the Transfer picker, Confirm Transfer, free or for the
    /// gift's transfer Stars, and transferGift. `completion` gets the success text once the picker has closed; a
    /// person's chat opens after it, as Telegram's does, and a channel's stays put.
    static func transfer(
        _ gift: TDNativeReceivedGift,
        upgraded: TDNativeUpgradedGift,
        client: TDLibClient,
        host: UIViewController,
        completion: @escaping (String) -> Void,
    ) {
        guard upgraded.hostId == nil else {
            presentLocked(upgraded, host: host)
            return
        }
        if gift.nextTransferDate > Int(Date().timeIntervalSince1970) {
            let date = ChatVM.fullDateString(Date(timeIntervalSince1970: TimeInterval(gift.nextTransferDate)))
            let alert = UIAlertController(
                title: L10n.telegram("Gift.Transfer.Unavailable.Title"),
                message: L10n.telegram("Gift.Transfer.Unavailable.Text", date).withoutTelegramMarkup,
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            host.present(alert, animated: true)
            return
        }
        let picker = GiftTransferPickerViewController()
        picker.onPick = { [weak picker] recipient in
            guard let picker else { return }
            confirmTransfer(
                gift,
                upgraded: upgraded,
                to: recipient,
                client: client,
                picker: picker,
                completion: completion,
            )
        }
        host.present(UINavigationController(rootViewController: picker), animated: true)
    }

    /// presentActionLockedForHostedGift: Action Locked, with Open Fragment.
    static func presentLocked(_ upgraded: TDNativeUpgradedGift, host: UIViewController) {
        let alert = UIAlertController(
            title: L10n.telegram("Gift.UnavailableAction.Title"),
            message: L10n.telegram("Gift.UnavailableAction.Text"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Gift.UnavailableAction.OpenFragment"), style: .default) {
            _ in
            guard let url = URL(string: "https://fragment.com/gift/\(upgraded.name)") else { return }
            UIApplication.shared.open(url)
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        host.present(alert, animated: true)
    }

    // MARK: Wear

    /// Whether the account wears the gift as its emoji status now.
    static func isWearing(_ upgraded: TDNativeUpgradedGift, status: TDNativeEmojiStatus?) -> Bool {
        if case .emojiStatusTypeUpgradedGift(let value) = status?.type {
            value.upgradedGiftId == upgraded.id
        } else {
            false
        }
    }

    /// setStarGiftStatus: the gift's emoji status, as TDLib lists the account's upgraded gifts' statuses. Without
    /// Premium, Telegram's tooltip instead; `completion` runs once the status is set.
    static func wear(
        _ upgraded: TDNativeUpgradedGift,
        isPremium: Bool,
        client: TDLibClient,
        host: UIViewController,
        completion: (() -> Void)? = nil,
    ) {
        guard isPremium else {
            TelegramUndoToast.show(
                text: L10n.telegram("Gift.View.TooltipPremiumWearing").withoutTelegramMarkup,
                in: host.view, bottomInset: 62, undo: nil,
            )
            return
        }
        Task { [weak host] in
            do {
                let statuses = try await client.send(TDNativeRequests.getUpgradedGiftEmojiStatuses())
                guard let status = statuses.emojiStatuses.first(where: { isWearing(upgraded, status: $0) }) else {
                    return
                }
                _ = try await client.send(TDNativeRequests.setEmojiStatus(emojiStatus: status))
                completion?()
            } catch {
                if let host { showError(error, in: host) }
            }
        }
    }

    /// commitTakeOff: no emoji status.
    static func takeOff(client: TDLibClient, host: UIViewController, completion: (() -> Void)? = nil) {
        Task { [weak host] in
            do {
                _ = try await client.send(TDNativeRequests.setEmojiStatus(emojiStatus: nil))
                completion?()
            } catch {
                if let host { showError(error, in: host) }
            }
        }
    }

    /// giftTransferAlertController: Confirm Transfer, "Transfer" when it's free and "Transfer for N Stars" otherwise.
    private static func confirmTransfer(
        _ gift: TDNativeReceivedGift,
        upgraded: TDNativeUpgradedGift,
        to recipient: GiftTransferPickerViewController.Recipient,
        client: TDLibClient,
        picker: UIViewController,
        completion: @escaping (String) -> Void,
    ) {
        let giftTitle = title(upgraded)
        let stars = Int(gift.transferStarCount)
        let starsText = L10n.telegramPlural(
            "Gift.Transfer.Confirmation.Text.Stars", count: stars, formattedCount: formatted(stars),
        )
        let text = stars > 0
            ? L10n.telegram("Gift.Transfer.Confirmation.Text", giftTitle, recipient.peer.title, starsText)
            : L10n.telegram("Gift.Transfer.Confirmation.TextFree", giftTitle, recipient.peer.title)
        let button = stars > 0
            ? L10n.telegram("Gift.Transfer.Confirmation.Transfer") + " " + starsText
            : L10n.telegram("Gift.Transfer.Confirmation.TransferFree")
        let alert = UIAlertController(
            title: L10n.telegram("Gift.Transfer.Confirmation.Title"),
            message: text.withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: button, style: .default) { [weak picker] _ in
            guard let picker else { return }
            send(gift, giftTitle: giftTitle, to: recipient, client: client, picker: picker, completion: completion)
        })
        picker.present(alert, animated: true)
    }

    private static func send(
        _ gift: TDNativeReceivedGift,
        giftTitle: String,
        to recipient: GiftTransferPickerViewController.Recipient,
        client: TDLibClient,
        picker: UIViewController,
        completion: @escaping (String) -> Void,
    ) {
        Task { [weak picker] in
            do {
                _ = try await client.send(TDNativeRequests.transferGift(
                    businessConnectionId: "",
                    receivedGiftId: gift.receivedGiftId,
                    newOwnerId: recipient.sender,
                    starCount: gift.transferStarCount,
                ))
            } catch {
                if let picker { showError(error, in: picker) }
                return
            }
            let success = L10n.telegram("Gift.Transfer.Success", giftTitle, recipient.peer.title).withoutTelegramMarkup
            if let picker {
                picker.dismiss(animated: true) { completion(success) }
            } else {
                completion(success)
            }
            if !recipient.isChannel,
               let chat = try? await client.createPrivateChat(force: false, userId: recipient.peer.id),
               let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client)
            {
                NavigationStorage.shared.push(.customChat(customChat))
            }
        }
    }
}
