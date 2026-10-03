// ChatTimelineCellProvider.swift

import UIKit

/// One dequeue and one returned object, including missing-model reconfiguration.
@MainActor enum ChatTimelineCellProvider {
    static func dequeue<Cell: UICollectionViewCell>(
        _: Cell.Type,
        from collection: UICollectionView,
        at indexPath: IndexPath,
        reuseIdentifier: String,
        configure: (Cell) -> Bool,
        unavailable: (Cell) -> Void,
    ) -> UICollectionViewCell {
        let dequeued = collection.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath)
        guard let cell = dequeued as? Cell else {
            makeInert(dequeued)
            return dequeued
        }
        if configure(cell) {
            cell.contentView.isHidden = false
            cell.accessibilityElementsHidden = false
            cell.isUserInteractionEnabled = true
        } else {
            unavailable(cell)
            makeInert(cell)
        }
        return cell
    }

    private static func makeInert(_ cell: UICollectionViewCell) {
        cell.contentView.isHidden = true
        cell.isUserInteractionEnabled = false
        cell.isAccessibilityElement = false
        cell.accessibilityElementsHidden = true
        cell.accessibilityLabel = nil
        cell.accessibilityValue = nil
        cell.accessibilityHint = nil
        cell.accessibilityIdentifier = nil
        cell.accessibilityTraits = []
        cell.accessibilityCustomActions = nil
    }
}
