// PinnedMessageSelectionProbe.swift

import UIKit

#if DEBUG
    /// Checks the pinned banner's multi-pin rules offline: PinnedMessageState.selection (topPinnedMessageSignal), the
    /// banner's titles and the navigation stripe's geometry.
    /// Launch with `-ui-probe-pinned-selection`; the result goes to the log and to
    /// Documents/pinned-selection-probe.txt.
    @MainActor enum PinnedMessageSelectionProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-pinned-selection") else { return }
            let result: String
            do {
                try verifySelection()
                try verifyTitles()
                try verifyStripe()
                result = "Pinned selection probe passed: no-reference-newest/bottom-newest/between/above-oldest/"
                    + "jump-previous/jump-oldest-wraps/partial-page-index=true; "
                    + "titles-single/previous/numbered/newest=true; stripe-single/three/many-scrolled=true"
            } catch {
                result = "Pinned selection probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("pinned-selection-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verifySelection() throws {
            typealias Selection = PinnedMessageState.Selection
            // Pins at 10, 20 and 30, newest first as TDLib returns them.
            let pins: [Int64] = [30, 20, 10]
            func select(_ reference: PinnedMessageState.Reference?, total: Int = 3) -> Selection? {
                PinnedMessageState.selection(pinnedIDs: pins, totalCount: total, reference: reference)
            }
            let cases: [(String, Selection?, Selection)] = [
                ("no reference", select(nil), Selection(messageID: 30, index: 2, totalCount: 3)),
                ("bottom", select(.visible(40)), Selection(messageID: 30, index: 2, totalCount: 3)),
                ("between", select(.visible(25)), Selection(messageID: 20, index: 1, totalCount: 3)),
                ("above oldest", select(.visible(5)), Selection(messageID: 10, index: 0, totalCount: 3)),
                ("jump", select(.scrolled(30)), Selection(messageID: 20, index: 1, totalCount: 3)),
                ("jump oldest", select(.scrolled(10)), Selection(messageID: 30, index: 2, totalCount: 3)),
                ("partial page", select(.visible(25), total: 10), Selection(messageID: 20, index: 8, totalCount: 10)),
            ]
            for (name, selection, expected) in cases {
                try require(selection == expected, "\(name): \(String(describing: selection))")
            }
            try require(
                PinnedMessageState.selection(pinnedIDs: [], totalCount: 0, reference: nil) == nil,
                "no pins",
            )
        }

        private static func verifyTitles() throws {
            let pinned = L10n.telegram("Conversation.PinnedMessage")
            try require(PinnedMessageBannerView.title(index: 0, totalCount: 1) == pinned, "single")
            try require(
                PinnedMessageBannerView.title(index: 0, totalCount: 2) == L10n
                    .telegram("Conversation.PinnedPreviousMessage")
                    && PinnedMessageBannerView.title(index: 1, totalCount: 2) == pinned,
                "two",
            )
            try require(PinnedMessageBannerView.title(index: 1, totalCount: 5) == pinned + " #2", "numbered")
            try require(PinnedMessageBannerView.title(index: 4, totalCount: 5) == pinned, "newest")
        }

        private static func verifyStripe() throws {
            let stripe = PinnedNavigationStripeView(frame: CGRect(x: 0, y: 0, width: 2, height: 50))
            stripe.update(index: 0, count: 1, animated: false)
            stripe.layoutIfNeeded()
            try require(
                stripe.probeSegmentFrames == [CGRect(x: 0, y: 7, width: 2, height: 36)],
                "single \(stripe.probeSegmentFrames)",
            )
            stripe.update(index: 2, count: 3, animated: false)
            stripe.layoutIfNeeded()
            let three = stripe.probeSegmentFrames
            try require(
                three.count == 3 && abs(three[0].minY - 7) < 0.01 && abs(three[2].maxY - 43) < 0.01
                    && abs(three[1].minY - three[0].maxY - 2) < 0.01,
                "three \(three)",
            )
            stripe.update(index: 5, count: 10, animated: false)
            stripe.layoutIfNeeded()
            let many = stripe.probeSegmentFrames
            try require(
                many.count == 10 && many[5].height == 8 && many[5].minY >= 7 && many[5].maxY <= 43,
                "many \(many[5])",
            )
        }
    }
#endif
