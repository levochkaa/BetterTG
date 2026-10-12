// ChatTimelineLayout.swift

import UIKit

// MARK: - ChatTimelineLayout

/// The chat timeline's layout. The timeline is drawn flipped, newest first: collection-view y = 0 is the screen's
/// bottom edge, and items with lower indexes are newer.
///
/// Telegram keeps a sent message in place when its temporary id becomes final. UIKit crossfades the deleted temporary
/// row with the inserted final row; the temporary copy is wider (it shows the sending clock), so two bubbles showed
/// for a moment. Here the final row takes the place at once and the temporary one is hidden.
final class ChatTimelineLayout: UICollectionViewCompositionalLayout {
    private var replacedItems = Set<IndexPath>()

    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        replacedItems = []
        var inserted = Set<IndexPath>()
        var deleted = Set<IndexPath>()
        for item in updateItems {
            switch item.updateAction {
            case .insert: if let path = item.indexPathAfterUpdate { inserted.insert(path) }
            case .delete: if let path = item.indexPathBeforeUpdate { deleted.insert(path) }
            case .move, .reload: return
            default: break
            }
        }
        guard let section = inserted.map(\.section).min() else { return }
        // A delete at the same bottom position as an insert is a message whose temporary id became final.
        var replaced = Set<IndexPath>()
        var item = 0
        while inserted.contains(IndexPath(item: item, section: section)) {
            let path = IndexPath(item: item, section: section)
            if deleted.contains(path) { replaced.insert(path) }
            item += 1
        }
        guard !replaced.isEmpty, deleted == replaced else { return }
        replacedItems = replaced
        // Hide the temporary copy now; a reused cell gets its alpha back from its next attributes.
        for path in replaced {
            collectionView?.cellForItem(at: path)?.alpha = 0
        }
    }

    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath)
        -> UICollectionViewLayoutAttributes?
    {
        let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)
        guard replacedItems.contains(itemIndexPath),
              let start = layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        else { return attributes }
        start.alpha = 1
        // Above the outgoing temporary copy. It doesn't move, so reordering the cell costs no animation.
        start.zIndex = (attributes?.zIndex ?? 0) + 1
        return start
    }

    /// The temporary copy of a sent message, keyed by its pre-update position, goes under its final copy.
    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath)
        -> UICollectionViewLayoutAttributes?
    {
        let attributes = super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)
        guard replacedItems.contains(itemIndexPath),
              let end = attributes?.copy() as? UICollectionViewLayoutAttributes
        else { return attributes }
        end.alpha = 0
        end.zIndex -= 1
        return end
    }

    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        replacedItems = []
    }
}
