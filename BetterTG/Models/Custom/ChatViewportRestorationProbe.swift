// ChatViewportRestorationProbe.swift

#if DEBUG
    import Foundation
    import UIKit

    enum ChatMessageNavigationDiagnostic {
        static func record(_ phase: String) {
            guard !Task.isCancelled, ProcessInfo.processInfo.arguments.contains("-ui-probe-message-navigation"),
                  let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                  else { return }
            try? Data(phase.utf8).write(
                to: root.appendingPathComponent("message-navigation-phase.txt"),
                options: .atomic,
            )
        }
    }

    @MainActor enum ChatViewportRestorationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        /// Isolated consumer of the real viewport/ticket helpers and UIKit layout.
        /// This does not instantiate ChatVM or claim to execute its server loader.
        @MainActor private final class NavigationFixture {
            let source = TdUpdateSource(accountID: UUID(), clientID: 914)
            var current: TdUpdateSource?
            var viewport: ChatClientRestorationViewport
            var authority = ChatViewportRestorationAuthority()
            let window: UIWindow
            let collection: UICollectionView
            let dataSource: UICollectionViewDiffableDataSource<Int, Int>
            var pending: (id: Int, quote: String)?
            var applied = [(id: Int, quote: String)]()
            var appliedAnimations = [Bool]()
            var initialScrollCompleted = false
            var scrolling = false
            var layoutDepth = 0

            init(scene: UIWindowScene) {
                self.current = source
                self.viewport = .init(
                    source: source,
                    messageID: nil,
                    pixelOffset: 0,
                    keepsLatest: true,
                    fallbackOffset: 0,
                )
                let layout = UICollectionViewFlowLayout()
                layout.itemSize = CGSize(width: 320, height: 40)
                layout.minimumLineSpacing = 0
                self.collection = UICollectionView(
                    frame: CGRect(x: 0, y: 0, width: 320, height: 400),
                    collectionViewLayout: layout,
                )
                collection.contentInsetAdjustmentBehavior = .never
                collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "row")
                self
                    .dataSource =
                    UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, _ in
                    collection.dequeueReusableCell(withReuseIdentifier: "row", for: path)
                }
                self.window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
                let root = UIViewController()
                window.rootViewController = root
                window.isHidden = false
                root.view.addSubview(collection)
            }

            func install(_ ids: ClosedRange<Int>) async {
                var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
                snapshot.appendSections([0])
                snapshot.appendItems(Array(ids))
                await withCheckedContinuation { continuation in
                    dataSource.apply(snapshot, animatingDifferences: false) { continuation.resume() }
                }
                collection.layoutIfNeeded()
            }

            func request(_ id: Int) {
                authority.invalidate()
                viewport.invalidate()
                pending = (id, "fixture quote")
                applyTarget()
            }

            func completeSnapshot(_ ticket: ChatViewportRestorationAuthority.Ticket) {
                guard current == source else { return }
                if viewport.markSnapshotApplied() { return }
                if pending != nil { applyTarget() }
                else if authority.consume(ticket, contextIsCurrent: current == source, userIsScrolling: scrolling) {
                    collection.contentOffset.y = 0
                    initialScrollCompleted = true
                }
            }

            func appear() {
                viewport.appeared = true
                if viewport.take(currentSource: current, hasLayout: true, keyboardChanging: false) {
                    collection.contentOffset.y = 0
                }
            }

            func applyTarget() {
                guard let target = pending, current == source, !scrolling, layoutDepth == 0, collection.window != nil,
                      collection.bounds.height > 0, let path = dataSource.indexPath(for: target.id),
                      let attributes = collection.layoutAttributesForItem(at: path) else { return }
                let animated = initialScrollCompleted
                initialScrollCompleted = true
                pending = nil
                let maximum = max(0, collection.contentSize.height - collection.bounds.height)
                collection.setContentOffset(
                    .init(x: 0, y: min(maximum, max(0, attributes.center.y - collection.bounds.height / 2))),
                    animated: animated,
                )
                applied.append(target)
                appliedAnimations.append(animated)
            }

            func finishLayout(retry: Bool = true) {
                if ChatViewportRestorationAuthority.finishLayoutMutation(depth: &layoutDepth), retry { applyTarget() }
            }

            func drag() {
                scrolling = true
                authority.invalidate()
                viewport.invalidate()
                pending = nil
                initialScrollCompleted = true
            }

            func close() {
                window.isHidden = true
                window.rootViewController = nil
            }
        }

        static func runDebugProbeIfRequested() {
            ChatMessageNavigationScrollProbe.runEndOrderProbeIfRequested()
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-viewport-authority") else { return }
            Task {
                let result: String
                do {
                    try verify()
                    try await verifyExplicitNavigation()
                    try await verifyLayoutRelease()
                    try await ChatMessageNavigationScrollProbe.verify()
                    result = "Viewport authority probe passed: production-ticket=true; latest-layout-only=true; "
                        + "gesture/navigation/revoked-context-retire=true; active-scroll/replay-rejected=true; "
                        + "fresh-restoration-after-gesture=true; "
                        + "A39-current-snapshot-marker/actual-UICollectionView-diffable=true; "
                        + "A39-loaded/unloaded/delayed-snapshot/appearance/layout/initial-position/quote-metadata/gesture/client/failure=true; "
                        + "A39-rotation-release=production-helper/value-only-consumer; nested-release/no-recursion=true; "
                        + "A39-settlement=production-driver/native-animation/estimated-compositional-cells; "
                        + "A39-flight-anchor/latest/inset-gates/resize/album-remap/quote/supersession/cancel/deferred/deadline=true; "
                        + "A39-successive-self-size/injected-offset-convergence/strict-centering/stall-and-cap=true; "
                        + "navigation-consumer=value-only; ChatView-wiring=source-reviewed; "
                        + "real-ChatVM/TDLib/foreground/rotation=unverified; server/account-stores=0"
                } catch {
                    result = "Viewport authority probe failed: \(error)"
                }
                log(result)
                if let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: root.appendingPathComponent("viewport-authority-probe.txt"), options: .atomic,
                    )
                }
            }
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw Failure(description: detail) }
        }

        private static func verify() throws {
            var authority = ChatViewportRestorationAuthority()
            let first = authority.begin()
            let second = authority.begin()
            try require(!authority.consume(first, contextIsCurrent: true, userIsScrolling: false), "old layout applied")
            try require(authority.consume(second, contextIsCurrent: true, userIsScrolling: false), "latest layout lost")
            try require(
                !authority.consume(second, contextIsCurrent: true, userIsScrolling: false),
                "layout applied twice",
            )

            for cause in ["drag", "explicit navigation", "keyboard inset", "highlight reconfigure"] {
                let before = authority.begin()
                authority.invalidate()
                // Even after dragging finishes, the old completion has no authority.
                try require(
                    !authority.consume(before, contextIsCurrent: true, userIsScrolling: false),
                    "\(cause) revived",
                )
                let after = authority.begin()
                try require(
                    !authority.consume(before, contextIsCurrent: true, userIsScrolling: false),
                    "stale consumed new ticket",
                )
                try require(
                    authority.consume(after, contextIsCurrent: true, userIsScrolling: false),
                    "fresh \(cause) layout lost",
                )
            }

            let tracking = authority.begin()
            try require(
                !authority.consume(tracking, contextIsCurrent: true, userIsScrolling: true),
                "active scroll moved",
            )
            try require(
                !authority.consume(tracking, contextIsCurrent: true, userIsScrolling: false),
                "scroll ticket replayed",
            )
            let retired = authority.begin()
            try require(
                !authority.consume(retired, contextIsCurrent: false, userIsScrolling: false),
                "retired context moved",
            )
            try require(
                !authority.consume(retired, contextIsCurrent: true, userIsScrolling: false),
                "retired ticket revived",
            )

            let queued = (0..<1000).map { _ in authority.begin() }
            for ticket in queued.dropLast() {
                try require(
                    !authority.consume(ticket, contextIsCurrent: true, userIsScrolling: false),
                    "queued obsolete geometry applied",
                )
            }
            try require(
                authority.consume(queued.last!, contextIsCurrent: true, userIsScrolling: false),
                "queued latest lost",
            )
        }

        private static func verifyExplicitNavigation() async throws {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                throw Failure(description: "missing navigation fixture scene")
            }
            for loaded in [true, false] {
                let fixture = NavigationFixture(scene: scene)
                defer { fixture.close() }
                await fixture.install(1...(loaded ? 90 : 30))
                let oldSnapshot = fixture.authority.begin()
                try require(fixture.viewport.pending, "old restoring snapshot fixture was already consumed")
                fixture.request(75)
                if !loaded {
                    fixture.completeSnapshot(oldSnapshot)
                    try require(
                        fixture.pending?.id == 75 && !fixture.initialScrollCompleted && fixture.applied.isEmpty,
                        "old snapshot consumed absent target/initial state",
                    )
                    await fixture.install(1...90)
                    fixture.collection.bounds.size.height = 0
                    fixture.completeSnapshot(oldSnapshot)
                    try require(
                        fixture.pending?.id == 75 && fixture.applied.isEmpty,
                        "zero layout consumed pending target",
                    )
                    fixture.collection.bounds.size.height = 400
                    fixture.collection.layoutIfNeeded()
                }
                fixture.completeSnapshot(oldSnapshot)
                fixture.appear()
                fixture.completeSnapshot(oldSnapshot)
                try require(
                    fixture.applied.count == 1 && fixture.applied.first?.id == 75
                    && fixture.applied.first?.quote == "fixture quote" && fixture.initialScrollCompleted,
                    "explicit target/quote was lost or replayed",
                )
                try require(
                    fixture.collection.contentOffset.y > 2000 && !fixture.viewport.pending,
                    "late snapshot/foreground pinned explicit target to latest",
                )
                try require(fixture.appliedAnimations == [false], "initial target did not settle synchronously")
                fixture.request(65)
                try require(fixture.appliedAnimations == [false, true], "initialized navigation lost its animation")
            }

            let fixture = NavigationFixture(scene: scene)
            defer { fixture.close() }
            await fixture.install(1...30)
            let old = fixture.authority.begin()
            fixture.request(75)
            fixture.drag()
            fixture.scrolling = false
            fixture.collection.contentOffset.y = 240
            await fixture.install(1...90)
            fixture.completeSnapshot(old)
            fixture.appear()
            try require(
                fixture.applied.isEmpty && fixture.collection.contentOffset.y == 240,
                "late target overrode drag",
            )
            fixture.request(150)
            fixture.current = .init(accountID: fixture.source.accountID, clientID: 915)
            await fixture.install(1...180)
            fixture.completeSnapshot(old)
            fixture.appear()
            try require(fixture.applied.isEmpty && fixture.pending?.id == 150, "foreign client applied old intent")

            let failed = NavigationFixture(scene: scene)
            defer { failed.close() }
            await failed.install(1...30)
            failed.request(75)
            failed.pending = nil // Isolated loader reports failure without a server request.
            let fallback = failed.authority.begin()
            failed.completeSnapshot(fallback)
            try require(
                failed.applied.isEmpty && failed.initialScrollCompleted && failed.collection.contentOffset.y == 0,
                "failed lookup lost safe initial fallback",
            )
        }

        private static func verifyLayoutRelease() async throws {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                throw Failure(description: "missing layout release scene")
            }
            for loaded in [true, false] {
                let fixture = NavigationFixture(scene: scene)
                defer { fixture.close() }
                await fixture.install(1...(loaded ? 90 : 30))
                let oldSnapshot = fixture.authority.begin()
                fixture.layoutDepth += 1 // Rotation owns layout through its completion.
                fixture.request(75)
                if loaded { fixture.request(76) }
                let target = loaded ? 76 : 75
                try require(
                    fixture.pending?.id == target && fixture.applied.isEmpty,
                    "direct loaded target bypassed active layout owner",
                )
                fixture.layoutDepth += 1 // A history snapshot completes inside rotation.
                if !loaded { await fixture.install(1...90) }
                fixture.completeSnapshot(oldSnapshot)
                fixture.finishLayout()
                fixture.appear()
                try require(
                    fixture.layoutDepth == 1 && fixture.pending?.id == target && fixture.applied.isEmpty,
                    "nested release consumed pending target/quote",
                )
                fixture.finishLayout()
                try require(
                    fixture.layoutDepth == 0 && fixture.pending == nil && fixture.applied.count == 1
                    && fixture.applied.first?.id == target && fixture.applied.first?.quote == "fixture quote",
                    "final rotation release lost target/quote wakeup",
                )
                try require(fixture.collection.contentOffset.y > 2000, "rotation release left target at latest")
            }

            for retired in [true, false] {
                let fixture = NavigationFixture(scene: scene)
                defer { fixture.close() }
                await fixture.install(1...90)
                fixture.layoutDepth = 1
                fixture.request(75)
                if retired { fixture.current = .init(accountID: fixture.source.accountID, clientID: 915) }
                else { fixture.drag() }
                fixture.finishLayout()
                try require(
                    fixture.applied.isEmpty && fixture.layoutDepth == 0,
                    "final release bypassed source or active gesture",
                )
            }

            let unavailable = NavigationFixture(scene: scene)
            defer { unavailable.close() }
            await unavailable.install(1...90)
            unavailable.layoutDepth = 1
            unavailable.request(75)
            unavailable.collection.bounds.size.height = 0
            unavailable.finishLayout(retry: false) // The explicit scroll's own layout must not recursively retry.
            try require(
                unavailable.layoutDepth == 0 && unavailable.pending?.id == 75 && unavailable.applied.isEmpty,
                "own release consumed unavailable layout",
            )
            unavailable.collection.bounds.size.height = 400
            unavailable.collection.layoutIfNeeded()
            unavailable.applyTarget()
            try require(
                unavailable.applied.count == 1 && unavailable.pending == nil,
                "external layout did not settle deferred target",
            )
        }
    }
#endif
