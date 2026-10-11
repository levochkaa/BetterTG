// PeerProfileMembersRestoration.swift

import TDLibKit
import UIKit

// MARK: - PeerProfileMemberID

enum PeerProfileMemberID: Hashable {
    case chat(Int64)
    case user(Int64)

    init(_ sender: MessageSender) {
        self =
            switch sender {
            case .messageSenderChat(let value): .chat(value.chatId)
            case .messageSenderUser(let value): .user(value.userId)
            }
    }
}

// MARK: - PeerProfileMemberAnchor

struct PeerProfileMemberAnchor {
    let id: PeerProfileMemberID
    let offset: CGFloat

    @MainActor static func capture(_ table: UITableView, id: (IndexPath) -> PeerProfileMemberID?) -> Self? {
        guard let path = table.indexPathsForVisibleRows?.sorted().first, let member = id(path) else { return nil }
        return Self(id: member, offset: table.rectForRow(at: path).minY - table.contentOffset.y)
    }

    @MainActor func restore(_ table: UITableView, path: IndexPath) {
        table.layoutIfNeeded()
        let minimum = -table.adjustedContentInset.top
        let maximum = max(minimum, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
        let target = table.rectForRow(at: path).minY - offset
        table.setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, target))), animated: false)
    }
}

// MARK: - PeerProfileMembersRevision

/// Full-info notifications may precede their own RPC response. Only a changed
/// membership/availability snapshot invalidates the request, never its replay.
struct PeerProfileMembersRevision<Value: Equatable> {
    private var value: Value?

    mutating func observe(_ next: Value) -> Bool {
        guard value != next else { return false }
        value = next
        return true
    }
}

// MARK: - PeerProfileMembersRestorationState

/// Only accepted identities and geometry cross client ownership. Roles, names,
/// member objects, request handles and action authority must be read again.
struct PeerProfileMembersRestorationState {
    let source: TdUpdateSource
    let actorID: Int64
    let chatID: Int64
    let administrators: Bool
    let ids: [PeerProfileMemberID]
    let heights: [PeerProfileMemberID: CGFloat]
    let rawOffset: Int
    let total: Int
    let hasMore: Bool
    let anchor: PeerProfileMemberAnchor?
}

// MARK: - PeerProfileMembersRevalidation

/// Replays at most one server page per consumer request. Offscreen retained rows
/// remain neutral until scroll demand reaches them; errors require explicit Retry.
struct PeerProfileMembersRevalidation {
    private(set) var active = false
    private(set) var cursor = 0
    private(set) var quarantined = Set<PeerProfileMemberID>()

    private var extent = 0
    private var retained = [PeerProfileMemberID]()
    private var fresh = [PeerProfileMemberID]()
    private var accepted = Set<PeerProfileMemberID>()

    mutating func begin(ids: [PeerProfileMemberID], rawOffset: Int) {
        active = true
        cursor = 0
        extent = max(0, rawOffset)
        retained = ids
        fresh = []
        accepted = []
        quarantined = Set(ids)
    }

    mutating func admit(ids: [PeerProfileMemberID], rawCount: Int, hasMore: Bool) -> [PeerProfileMemberID] {
        precondition(active && rawCount >= 0)
        cursor += rawCount
        for id in ids where accepted.insert(id).inserted {
            fresh.append(id)
            quarantined.remove(id)
        }
        if !hasMore || cursor >= extent {
            active = false
            quarantined.removeAll()
            return fresh
        }
        return fresh + retained.filter { !accepted.contains($0) }
    }

    func hasDemand(visibleIDs: [PeerProfileMemberID]) -> Bool {
        active && (retained.isEmpty || visibleIDs.contains(where: quarantined.contains))
    }
}

// MARK: - PeerProfileMemberPlaceholder

@MainActor enum PeerProfileMemberPlaceholder {
    static func configure(_ cell: UITableViewCell, retrying: Bool) {
        var content = cell.defaultContentConfiguration()
        content.text = retrying ? "Member unavailable — retry" : "Updating member…"
        content.secondaryText = nil
        content.textProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = content.text
        cell.accessibilityHint = nil
        cell.accessibilityTraits = .staticText
    }
}

// MARK: - PeerProfileMembersParentBinding

/// Exact adjacent stack membership, including the live window root, is retained
/// before Ready. A replacement parent must explicitly adopt the same child.
@MainActor final class PeerProfileMembersParentBinding {
    private(set) weak var parent: UIViewController?

    init(parent: UIViewController? = nil) { self.parent = parent }

    func attach(_ parent: UIViewController) { self.parent = parent }

    func contains(_ child: UIViewController, parent: UIViewController) -> Bool {
        guard self.parent === parent, parent.chatListActionOwnerIsAttached,
              child.chatListActionOwnerIsAttached, let navigation = parent.navigationController,
              child.navigationController === navigation, navigation.topViewController === child,
              let index = navigation.viewControllers.firstIndex(where: { $0 === parent }),
              navigation.viewControllers.indices.contains(index + 1) else { return false }
        return navigation.viewControllers[index + 1] === child
    }

    func transfer(_ child: UIViewController, from parent: UIViewController, to replacement: UIViewController) -> Bool {
        guard contains(child, parent: parent) else { return false }
        self.parent = replacement
        return true
    }
}
