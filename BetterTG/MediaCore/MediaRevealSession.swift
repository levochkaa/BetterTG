// MediaRevealSession.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MediaRevealSession

/// A route-owned grant, never a global set of numeric message IDs.
@MainActor final class MediaRevealSession {
    struct Key: Equatable {
        enum Kind: Equatable { case photo, video, animation, voiceNote }

        let chatID: Int64
        let messageID: Int64
        let revision: Int
        let kind: Kind
        let files: [Int]
        let hasSpoiler: Bool
        let isSecret: Bool
        /// TDLib marks the media 18+ (`has_sensitive_content`); it shows once confirmed or with Show 18+ Content.
        let isSensitive: Bool

        /// Neither a spoiler, self-destructing nor 18+: any client may show these pixels.
        var isPublic: Bool { !hasSpoiler && !isSecret && !isSensitive }

        init?(message: Message) {
            self.chatID = message.chatId
            self.messageID = message.id
            self.revision = message.editDate
            self.isSensitive = SensitiveContentStore.isSensitive(message)
            switch message.content {
            case .messagePhoto(let value):
                self.kind = .photo
                self.files = value.photo.sizes.map(\.photo.id).sorted()
                self.hasSpoiler = value.hasSpoiler
                self.isSecret = value.isSecret
            case .messageVideo(let value):
                self.kind = .video
                self.files = [value.video.video.id]
                self.hasSpoiler = value.hasSpoiler
                self.isSecret = value.isSecret
            case .messageAnimation(let value):
                self.kind = .animation
                self.files = [value.animation.animation.id]
                self.hasSpoiler = value.hasSpoiler
                self.isSecret = value.isSecret
            case .messageVoiceNote(let value):
                // A voice note shows no pixels, but a self-destructing one is consumed when it plays: the key keeps it
                // out of prefetch, and only a current permit lets the play-once overlay open it.
                self.kind = .voiceNote
                self.files = [value.voiceNote.voice.id]
                self.hasSpoiler = false
                self.isSecret = message.selfDestructType != nil
            default:
                return nil
            }
        }
    }

    /// `openSecret`: self-destructing media opens only in the secret preview, which consumes it.
    /// `confirmSensitive`: 18+ media reveals after ChatAgeRestrictionAlertController's View Anyway.
    enum TapResult { case rejected, revealed, open, openSecret, confirmSensitive }

    struct RevisionChange {
        let messages: [Message]

        var ids: Set<Int64> { Set(messages.map(\.id)) }
    }

    let context: MediaGalleryPlaybackContext
    let revisionsChanged = PassthroughSubject<RevisionChange, Never>()

    private var latest = [Int64: Key]()
    private var revealed = [Int64: Key]()
    /// The accepted key a public-to-public change replaced. A timeline row built a moment before the change still
    /// renders it until the next snapshot lands; covering public media for that frame only flashes a placeholder.
    private var predecessors = [Int64: Key]()

    /// Show 18+ Content for the route's client.
    private var showsSensitive: Bool {
        SensitiveContentStore.shows(chatID: context.location.chatID, clientID: context.location.clientID)
    }

    init(context: MediaGalleryPlaybackContext) { self.context = context }

    /// ChatVM emits after replacing its accepted model. Revoke before any queued cell/snapshot work.
    func observeAcceptedMessages(
        changes: AnyPublisher<Void, Never>, current: @escaping () -> [CustomMessage],
    ) -> AnyCancellable {
        reconcile(current().flatMap(\.sourceMessages))
        return changes.sink { [weak self] in self?.reconcile(current().flatMap(\.sourceMessages)) }
    }

    func timelineTap(captured: Message, current: Message) -> TapResult {
        guard context.isCurrent, context.location.matches(message: current),
              captured.id == current.id, captured.chatId == current.chatId,
              Key(message: captured) == Key(message: current) else { return .rejected }
        reconcile([current])
        if MediaRevealPermit.allows(current, permit: permit(for: current), requiresPermit: true) { return .open }
        if let key = Key(message: current), key.isSecret, key.kind != .voiceNote,
           self.current(key) { return .openSecret }
        if let key = Key(message: current), key.isSensitive, !showsSensitive, self.current(key),
           revealed[key.messageID] != key { return .confirmSensitive }
        return reveal(current) ? .revealed : .rejected
    }

    /// Call only when accepting the route's current model, never from a delayed callback.
    func reconcile(_ messages: [Message], replacingExisting: Bool = true) {
        guard context.isCurrent else { return }
        var changed = Set<Int64>()
        for message in messages where context.location.matches(message: message) {
            if !replacingExisting, latest[message.id] != nil { continue }
            let key = Key(message: message)
            if latest[message.id] != key {
                if let previous = latest[message.id] {
                    changed.insert(message.id)
                    predecessors[message.id] = previous.isPublic && key?.isPublic == true ? previous : nil
                }
                revealed[message.id] = nil
            }
            latest[message.id] = key
        }
        if !changed
            .isEmpty { revisionsChanged.send(RevisionChange(messages: messages.filter { changed.contains($0.id) })) }
    }

    func permit(for message: Message) -> MediaRevealPermit? {
        guard let key = Key(message: message), current(key) else { return nil }
        return MediaRevealPermit(session: self, key: key)
    }

    /// No revision event: the caller must synchronously clear its cells and
    /// gallery/PiP owners before scheduling a read. Only fresh admission may reconcile again.
    func revoke(messageIDs: Set<Int64>) {
        for id in messageIDs {
            latest[id] = nil
            revealed[id] = nil
            predecessors[id] = nil
        }
    }

    /// A spoiler's tap, or 18+ media once its alert was confirmed (`confirmedSensitive`).
    @discardableResult func reveal(_ message: Message, confirmedSensitive: Bool = false) -> Bool {
        guard let key = Key(message: message), current(key), !key.isSecret,
              key.hasSpoiler || key.isSensitive,
              !key.isSensitive || confirmedSensitive || showsSensitive,
              revealed[key.messageID] != key else { return false }
        revealed[key.messageID] = key
        return true
    }

    /// A same-account client renewal keeps the spoilers the user revealed. File IDs belong to a client, so an
    /// unchanged revision of the message identifies the same media.
    func adoptReveals(from previous: MediaRevealSession, messages: [Message]) {
        guard previous.context.location.accountID == context.location.accountID,
              previous.context.location.chatID == context.location.chatID else { return }
        for message in messages {
            guard let earlier = previous.revealed[message.id], let key = Key(message: message),
                  earlier.revision == key.revision, earlier.kind == key.kind else { continue }
            reveal(message, confirmedSensitive: true)
        }
    }

    fileprivate func current(_ key: Key) -> Bool {
        guard context.isCurrent, key.chatID == context.location.chatID else { return false }
        return latest[key.messageID] == key || predecessors[key.messageID] == key
    }

    fileprivate func allows(_ key: Key) -> Bool {
        let covered = key.hasSpoiler || (key.isSensitive && !showsSensitive)
        return current(key) && !key.isSecret && (!covered || revealed[key.messageID] == key)
    }
}

// MARK: - MediaRevealPermit

/// The issuing session keeps its immutable account/client authority through gallery and PiP transfer.
@MainActor struct MediaRevealPermit {
    let key: MediaRevealSession.Key

    private let session: MediaRevealSession

    var isCurrent: Bool { session.current(key) }
    var allowsPixels: Bool { session.allows(key) }
    var revisionChanges: AnyPublisher<Void, Never> {
        session.revisionsChanged.filter { $0.ids.contains(key.messageID) }.map { _ in () }.eraseToAnyPublisher()
    }

    fileprivate init(session: MediaRevealSession, key: MediaRevealSession.Key) {
        self.session = session
        self.key = key
    }

    static func allows(_ message: Message, permit: Self?, requiresPermit: Bool = false) -> Bool {
        guard let key = MediaRevealSession.Key(message: message) else { return true }
        if let permit { return permit.matches(message) && permit.allowsPixels }
        let sensitiveCovered = key.isSensitive
            && !SensitiveContentStore.shows(chatID: key.chatID, clientID: TDLib.shared.activeUpdateSource?.clientID)
        return !requiresPermit && !key.isSecret && !key.hasSpoiler && !sensitiveCovered
    }

    func matches(_ message: Message) -> Bool { isCurrent && key == MediaRevealSession.Key(message: message) }

    func matches(_ context: MediaGalleryPlaybackContext) -> Bool { session.context.matches(context) }
}

// MARK: - MediaConcealmentView

/// No hidden source image or player exists underneath this cover. Self-destructing media shows only its blurred inline
/// thumbnail, as Telegram does.
final class MediaConcealmentView: UIControl, ReusableMediaView, GalleryMediaView {
    private var onTap: (() -> Void)?
    private var selfDestructing: (message: Message, clientID: Int32?)?
    private var timerView: SecretMediaTimerView?
    private var badgeView: SecretMediaBadgeView?
    private var ticker: Timer?
    private var deadlineChanges: AnyCancellable?

    // MARK: 18+ media

    private var sensitiveLabel: UILabel?

    init(message: Message, size: CGSize? = nil, clientID: Int32? = nil, onTap: (() -> Void)? = nil) {
        super.init(frame: .zero)
        self.onTap = onTap
        backgroundColor = .secondarySystemBackground
        clipsToBounds = true
        let key = MediaRevealSession.Key(message: message)
        let secret = key?.isSecret == true
        let sensitive = key?.isSensitive == true && !secret
        if secret, message.selfDestructType != nil {
            configureSelfDestructing(message: message, clientID: clientID)
        } else if sensitive {
            configureSensitive(message: message)
        } else {
            let symbol = UIImageView(image: UIImage(systemName: secret ? "lock.fill" : "eye.slash.fill"))
            symbol.tintColor = .secondaryLabel
            symbol.translatesAutoresizingMaskIntoConstraints = false
            addSubview(symbol)
            NSLayoutConstraint.activate([
                symbol.centerXAnchor.constraint(equalTo: centerXAnchor),
                symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
                symbol.widthAnchor.constraint(equalToConstant: 28),
                symbol.heightAnchor.constraint(equalToConstant: 24),
            ])
        }
        if let size {
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: size.width),
                heightAnchor.constraint(equalToConstant: size.height),
            ])
        }
        isAccessibilityElement = true
        accessibilityLabel =
            if selfDestructing != nil {
                SecretMediaPreviewViewController.title(for: message)
            } else if sensitive {
                L10n.telegram("Chat.SensitiveContent")
            } else {
                secret
                    ? L10n.betterTG("Accessibility.ProtectedMedia")
                    : L10n.betterTG("Accessibility.MediaSpoiler")
            }
        accessibilityHint = secret ? nil : L10n.betterTG("Accessibility.RevealMediaSpoiler")
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityActivate() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSelfDestructState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // wideLayout: the full "18+ Content" where it fits, else "18+".
        sensitiveLabel?.text = L10n.telegram(bounds.width >= 160
            ? "Chat.SensitiveContent"
            : "Chat.SensitiveContentShort")
    }

    private static func minithumbnail(of message: Message) -> Data? {
        switch message.content {
        case .messagePhoto(let value): value.photo.minithumbnail?.data
        case .messageVideo(let value): value.video.minithumbnail?.data
        case .messageAnimation(let value): value.animation.minithumbnail?.data
        default: nil
        }
    }

    func prepareForReuse() {
        onTap = nil
        ticker?.invalidate()
        ticker = nil
        deadlineChanges = nil
    }

    func setPlaybackVisible(_: Bool) {}

    @objc private func tapped() { onTap?() }

    /// ChatMessageInteractiveMediaNode's ExtendedMediaOverlayNode with the eye icon: the blurred thumbnail and a
    /// capsule reading "18+ Content", or "18+" where the media is narrow.
    private func configureSensitive(message: Message) {
        if let data = Self.minithumbnail(of: message), let image = UIImage(data: data) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.frame = bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(imageView)
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            blur.frame = bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.isUserInteractionEnabled = false
            addSubview(blur)
        }
        let capsule = UIView()
        capsule.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        capsule.layer.cornerRadius = 14
        capsule.isUserInteractionEnabled = false
        capsule.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(
            systemName: "eye.slash.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
        ))
        icon.tintColor = .white
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.text = L10n.telegram("Chat.SensitiveContent")
        sensitiveLabel = label
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(stack)
        addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsule.heightAnchor.constraint(equalToConstant: 28),
            capsule.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])
    }

    // MARK: Self-destructing media

    /// Telegram's secret media bubble (ChatMessageInteractiveMediaNode with `containsSecretMedia`): the blurred
    /// thumbnail, a 48 pt flame in the middle that turns into the countdown ring once the media is opened, and a
    /// badge with "1" for view-once media or the seconds left.
    private func configureSelfDestructing(message: Message, clientID: Int32?) {
        selfDestructing = (message, clientID)
        if let data = Self.minithumbnail(of: message), let image = UIImage(data: data) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.frame = bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(imageView)
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            blur.frame = bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.isUserInteractionEnabled = false
            addSubview(blur)
        }
        let timerView = SecretMediaTimerView(diameter: 48)
        timerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timerView)
        let badgeView = SecretMediaBadgeView()
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeView)
        NSLayoutConstraint.activate([
            timerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            timerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            timerView.widthAnchor.constraint(equalToConstant: 48),
            timerView.heightAnchor.constraint(equalToConstant: 48),
            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
        self.timerView = timerView
        self.badgeView = badgeView
        if let clientID {
            let key = SelfDestructDeadlines.Key(clientID: clientID, message: message)
            deadlineChanges = SelfDestructDeadlines.changed
                .filter { $0 == key }
                .sink { [weak self] _ in self?.updateSelfDestructState() }
        }
        updateSelfDestructState()
    }

    private func updateSelfDestructState() {
        guard let (message, clientID) = selfDestructing, let timerView, let badgeView else { return }
        switch message.selfDestructType {
        case .messageSelfDestructTypeTimer(let timer):
            let timeout = TimeInterval(timer.selfDestructTime)
            let deadline = clientID.flatMap { SelfDestructDeadlines.deadline(clientID: $0, message: message) }
            let remaining = deadline.map { max(0, $0 - SelfDestructDeadlines.now) } ?? timeout
            timerView.configure(icon: .flame, countdown: deadline.map { .init(deadline: $0, timeout: timeout) })
            let seconds = Int(remaining.rounded(.up))
            let text = L10n.telegramPlural("MessageTimer.ShortSeconds", count: seconds, formattedCount: "\(seconds)")
            badgeView.configure(isViewOnce: false, text: text)
            accessibilityValue = text
            // The badge counts the seconds down while the bubble is on screen.
            if deadline != nil, remaining > 0, window != nil {
                if ticker == nil {
                    ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.updateSelfDestructState() }
                    }
                }
            } else {
                ticker?.invalidate()
                ticker = nil
            }
        default:
            timerView.configure(icon: .flame, countdown: nil)
            badgeView.configure(isViewOnce: true, text: "1")
            accessibilityValue = nil
        }
    }
}
