// MediaRevealSession.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MediaRevealSession

/// A route-owned grant, never a global set of numeric message IDs.
@MainActor final class MediaRevealSession {
    struct Key: Equatable {
        enum Kind: Equatable { case photo, video, animation }

        let chatID: Int64
        let messageID: Int64
        let revision: Int
        let kind: Kind
        let files: [Int]
        let hasSpoiler: Bool
        let isSecret: Bool

        /// Neither a spoiler nor self-destructing: any client may show these pixels.
        var isPublic: Bool { !hasSpoiler && !isSecret }

        init?(message: Message) {
            self.chatID = message.chatId
            self.messageID = message.id
            self.revision = message.editDate
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
            default:
                return nil
            }
        }
    }

    enum TapResult { case rejected, revealed, open }

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

    @discardableResult func reveal(_ message: Message) -> Bool {
        guard let key = Key(message: message), current(key), !key.isSecret, key.hasSpoiler,
              revealed[key.messageID] != key else { return false }
        revealed[key.messageID] = key
        return true
    }

    fileprivate func current(_ key: Key) -> Bool {
        guard context.isCurrent, key.chatID == context.location.chatID else { return false }
        return latest[key.messageID] == key || predecessors[key.messageID] == key
    }

    fileprivate func allows(_ key: Key) -> Bool {
        current(key) && !key.isSecret && (!key.hasSpoiler || revealed[key.messageID] == key)
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
        return !requiresPermit && !key.isSecret && !key.hasSpoiler
    }

    func matches(_ message: Message) -> Bool { isCurrent && key == MediaRevealSession.Key(message: message) }

    func matches(_ context: MediaGalleryPlaybackContext) -> Bool { session.context.matches(context) }
}

// MARK: - MediaConcealmentView

/// No hidden source image or player exists underneath this cover.
final class MediaConcealmentView: UIControl, ReusableMediaView, GalleryMediaView {
    private var onTap: (() -> Void)?

    init(message: Message, size: CGSize? = nil, onTap: (() -> Void)? = nil) {
        super.init(frame: .zero)
        self.onTap = onTap
        backgroundColor = .secondarySystemBackground
        clipsToBounds = true
        let secret = MediaRevealSession.Key(message: message)?.isSecret == true
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
        if let size {
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: size.width),
                heightAnchor.constraint(equalToConstant: size.height),
            ])
        }
        isAccessibilityElement = true
        accessibilityLabel = secret
            ? L10n.betterTG("Accessibility.ProtectedMedia")
            : L10n.betterTG("Accessibility.MediaSpoiler")
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

    func prepareForReuse() { onTap = nil }
    func setPlaybackVisible(_: Bool) {}

    @objc private func tapped() { onTap?() }
}
