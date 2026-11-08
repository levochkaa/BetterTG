// BoostLevelsViewController.swift

import TDLibKit
import UIKit

// MARK: - BoostLevelsViewController

/// Telegram's PremiumBoostLevelsScreen for a channel or group: its photo over the level bar (Level N to Level N + 1
/// with the boosts so far), how many more boosts it needs, or that it reached its level, and Boost (Boost Again once
/// the account boosted it), which spends a free boost slot (boostChat). Without a free slot the account learns it needs
/// more boosts; without Premium, that boosting needs it.
final class BoostLevelsViewController: UIViewController {
    private let client: TDLibClient
    private let chat: Chat
    private var status: TDNativeChatBoostStatus?
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let levelBar = BoostLevelBar()
    private let textLabel = UILabel()
    private let boostButton = UIButton(configuration: .prominentGlass())
    private let linkButton = UIButton(configuration: .plain())
    private var isBoosting = false
    /// An admin gets the boost link to share (ChannelStatsController's boosts section).
    private let isAdmin: Bool

    init(chat: Chat, isAdmin: Bool, client: TDLibClient) {
        self.chat = chat
        self.isAdmin = isAdmin
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        avatarView.configure(
            file: chat.photo?.small,
            minithumbnail: chat.photo?.minithumbnail,
            placeholder: SettingsPeer(chat: chat).placeholder,
            client: client,
        )
        avatarView.layer.cornerRadius = 40
        avatarView.clipsToBounds = true
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.text = L10n.telegram("ChannelBoost.Title.Current")
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.font = .preferredFont(forTextStyle: .body)
        boostButton.isEnabled = false
        boostButton.addAction(UIAction { [weak self] _ in self?.boost() }, for: .touchUpInside)
        linkButton.addAction(UIAction { [weak self] _ in self?.copyLink() }, for: .touchUpInside)
        linkButton.isHidden = true
        let stack = UIStackView(arrangedSubviews: [
            avatarView,
            titleLabel,
            levelBar,
            textLabel,
            boostButton,
            linkButton,
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(24, after: textLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 80),
            avatarView.heightAnchor.constraint(equalToConstant: 80),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            levelBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            boostButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            boostButton.heightAnchor.constraint(equalToConstant: 50),
        ])
        load()
    }

    private func load() {
        let client = client
        let chatID = chat.id
        Task { [weak self] in
            let status = try? await client.send(TDNativeRequests.getChatBoostStatus(chatId: chatID))
            guard let self, let status else { return }
            self.status = status
            render(status)
        }
    }

    /// The level bar and the text: Level reached, or the boosts still needed, worded for whether the account boosted.
    private func render(_ status: TDNativeChatBoostStatus) {
        levelBar.configure(
            level: status.level,
            boosts: status.boostCount,
            current: status.currentLevelBoostCount,
            next: status.nextLevelBoostCount,
        )
        let title = chat.title
        let boosted = !status.appliedSlotIds.isEmpty
        let text: String
        if status.nextLevelBoostCount == 0 {
            text = L10n.telegram("ChannelBoost.MaxLevelReached.Text", title, "\(status.level)")
        } else {
            let remaining = max(0, status.nextLevelBoostCount - status.boostCount)
            let boosts = L10n.telegramPlural("ChannelBoost.MoreBoostsNeeded.Boosts", count: remaining)
            text = boosted
                ? L10n.telegram("ChannelBoost.MoreBoostsNeeded.Boosted.Text", boosts)
                : L10n.telegram("ChannelBoost.MoreBoostsNeeded.Text", title, boosts)
        }
        textLabel.text = text.withoutTelegramMarkup
        var buttonTitle = AttributedString(L10n.telegram(boosted ? "ChannelBoost.BoostAgain" : "ChannelBoost.Boost"))
        buttonTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        boostButton.configuration?.attributedTitle = buttonTitle
        boostButton.isEnabled = !isBoosting
        // The link an admin shares to ask for boosts.
        if !status.boostUrl.isEmpty, isAdmin {
            linkButton.configuration?.title = status.boostUrl
            linkButton.isHidden = false
        }
    }

    /// The account's free boost slot goes to the chat; with none, More Boosts Needed or Premium's note.
    private func boost() {
        guard !isBoosting else { return }
        isBoosting = true
        boostButton.isEnabled = false
        let client = client
        let chatID = chat.id
        Task { [weak self] in
            let slots = await (try? client.send(TDNativeRequests.getAvailableChatBoostSlots()))?.slots ?? []
            let now = Int(Date().timeIntervalSince1970)
            let free = slots.first { $0.currentlyBoostedChatId == 0 && $0.cooldownUntilDate <= now }
            var boosted = false
            if let free {
                boosted = await (try? client.send(TDNativeRequests.boostChat(
                    chatId: chatID,
                    slotIds: [free.slotId],
                ))) != nil
            }
            guard let self else { return }
            isBoosting = false
            boostButton.isEnabled = true
            if boosted {
                TelegramUndoToast.show(
                    text: L10n.telegram("ChannelBoost.YouBoostedChannelText", chat.title),
                    in: view,
                    bottomInset: 12,
                    undo: nil,
                )
                load()
            } else if slots.isEmpty {
                // Only Premium boosts; BetterTG offers no Premium, so the question's first sentence stays.
                let text = L10n.telegram("ChannelBoost.Error.PremiumNeededText").withoutTelegramMarkup
                TelegramUndoToast.show(
                    text: text.components(separatedBy: "?").first.map { sentence in
                        sentence.components(separatedBy: ". ").first.map { $0 + "." } ?? sentence
                    } ?? text,
                    in: view,
                    bottomInset: 12,
                    undo: nil,
                )
            } else {
                let alert = UIAlertController(
                    title: L10n.telegram("ChannelBoost.MoreBoosts.Title"),
                    message: L10n.telegram("ChannelBoost.MoreBoosts.Text", chat.title, "\(slots.count)")
                        .withoutTelegramMarkup,
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func copyLink() {
        guard let url = status?.boostUrl, !url.isEmpty else { return }
        UIPasteboard.general.string = url
        TelegramUndoToast.show(
            text: L10n.telegram("ChannelBoost.BoostLinkCopied"),
            in: view,
            bottomInset: 12,
            undo: nil,
        )
    }
}

// MARK: - BoostLevelBar

/// PremiumLimitDisplayComponent in its boost mode: Level N and Level N + 1 at the ends of a rounded bar filled to the
/// boosts so far, the count on top.
private final class BoostLevelBar: UIView {
    private let track = UIView()
    private let fill = CAGradientLayer()
    private let currentLabel = UILabel()
    private let nextLabel = UILabel()
    private let countLabel = UILabel()
    private var fraction: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = .tertiarySystemFill
        track.layer.cornerRadius = 15
        track.layer.cornerCurve = .continuous
        track.clipsToBounds = true
        track.layer.addSublayer(fill)
        fill.colors = [UIColor(rgb: 0x6B93FF).cgColor, UIColor(rgb: 0x976FFF).cgColor, UIColor(rgb: 0xE46ACE).cgColor]
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        for label in [currentLabel, nextLabel] {
            label.font = .systemFont(ofSize: 15, weight: .semibold)
        }
        countLabel.font = .systemFont(ofSize: 17, weight: .bold)
        countLabel.textAlignment = .center
        for view in [track, currentLabel, nextLabel, countLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: topAnchor),
            countLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            track.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 8),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.heightAnchor.constraint(equalToConstant: 30),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            currentLabel.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 12),
            currentLabel.centerYAnchor.constraint(equalTo: track.centerYAnchor),
            nextLabel.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -12),
            nextLabel.centerYAnchor.constraint(equalTo: track.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(track.bounds.height, track.bounds.width * fraction)
        fill.frame = CGRect(x: 0, y: 0, width: width, height: track.bounds.height)
    }

    func configure(level: Int, boosts: Int, current: Int, next: Int) {
        currentLabel.text = L10n.telegram("ChannelBoost.Level", "\(level)")
        nextLabel.text = next == 0 ? nil : L10n.telegram("ChannelBoost.Level", "\(level + 1)")
        countLabel.text = "⚡️ \(boosts)"
        fraction = next > current ? CGFloat(boosts - current) / CGFloat(next - current) : 1
        fraction = min(1, max(0, fraction))
        // The left label reads white over the fill and in the text colour while the fill is short of it.
        currentLabel.textColor = fraction > 0.3 ? .white : .label
        nextLabel.textColor = fraction > 0.85 ? .white : .label
        setNeedsLayout()
    }
}
