// ChatMessageNavigationScrollProbe.swift

#if DEBUG
    import UIKit

    /// Actual native animation and production settlement driver; the route/model
    /// adapter is isolated and does not instantiate ChatView or issue TDLib reads.
    @MainActor enum ChatMessageNavigationScrollProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        private final class Cell: UICollectionViewCell {
            var rowHeight: CGFloat = 48

            override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
                -> UICollectionViewLayoutAttributes
            {
                let result = attributes.copy() as! UICollectionViewLayoutAttributes
                result.size.height = rowHeight
                return result
            }
        }

        private final class Collection: UICollectionView {
            override var isTracking: Bool { trackingOverride || super.isTracking }

            var trackingOverride = false
        }

        @MainActor private final class Fixture: NSObject, UICollectionViewDelegate {
            let driver = ChatMessageNavigationScroll()
            let window: UIWindow
            let collection: Collection
            var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
            var ids = Array(1...100)
            var target: Int?
            var targetDisplay: Int?
            var targetMemberPresent = true
            var current = true
            var attached = true
            var layoutReady = true
            var deferred = false
            var height: CGFloat = 48
            var targetHeight: CGFloat = 48
            var results = [ChatMessageNavigationScroll.Outcome]()
            var commands = [Bool]()
            var ends = 0
            var scrolls = 0
            var blockedWriters = 0
            var quoted = [Int]()
            var commandHook: (() -> Void)?

            init(scene: UIWindowScene) {
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(80),
                ))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(80)),
                    subitems: [item],
                )
                let layout = UICollectionViewCompositionalLayout(section: .init(group: group))
                self.collection = Collection(
                    frame: CGRect(x: 0, y: 0, width: 320, height: 400),
                    collectionViewLayout: layout,
                )
                self.window = UIWindow(windowScene: scene)
                super.init()
                collection.contentInsetAdjustmentBehavior = .never
                collection.transform = .init(scaleX: 1, y: -1)
                collection.register(Cell.self, forCellWithReuseIdentifier: "row")
                collection.delegate = self
                self
                    .dataSource =
                    UICollectionViewDiffableDataSource(collectionView: collection) { [weak self] collection, path, id in
                    let cell = collection.dequeueReusableCell(withReuseIdentifier: "row", for: path) as! Cell
                    cell.rowHeight = id == self?.targetDisplay ? self?.targetHeight ?? 48 : self?.height ?? 48
                    return cell
                }
                window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
                let root = UIViewController()
                window.rootViewController = root
                window.isHidden = false
                root.view.addSubview(collection)
            }

            func install() async {
                layoutReady = false
                var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
                snapshot.appendSections([0])
                snapshot.appendItems(ids)
                let previous = Set(dataSource.snapshot().itemIdentifiers)
                snapshot.reconfigureItems(ids.filter { previous.contains($0) })
                await withCheckedContinuation { continuation in
                    dataSource.apply(snapshot, animatingDifferences: false) { continuation.resume() }
                }
                collection.layoutIfNeeded()
                layoutReady = true
                driver.layoutDidSettle()
            }

            func request(_ id: Int, animated: Bool) {
                cancel()
                target = id
                targetDisplay = id
                targetMemberPresent = true
                driver.start(
                    scrollView: collection, animated: animated,
                    resolve: { [weak self] in self?.resolve() ?? .cancelled },
                    onCommand: { [weak self] _, animated in
                        self?.commands.append(animated)
                        self?.commandHook?()
                    },
                    completion: { [weak self] outcome in
                        guard let self, target == id else { return }
                        target = nil
                        results.append(outcome)
                        if outcome == .settled { quoted.append(id) }
                    },
                )
            }

            func resolve() -> ChatMessageNavigationScroll.Resolution {
                guard current, attached, target != nil else { return .cancelled }
                guard layoutReady, !deferred else { return .deferred }
                guard targetMemberPresent, let display = targetDisplay, ids.contains(display) else { return .missing }
                guard let path = dataSource.indexPath(for: display),
                      let frame = collection.layoutAttributesForItem(at: path)?.frame else { return .deferred }
                let inset = collection.adjustedContentInset
                let minimum = -inset.top
                let maximum = max(minimum, collection.contentSize.height - collection.bounds.height + inset.bottom)
                return .ready(.init(
                    offset: .init(
                        x: 0,
                        y: min(
                            maximum,
                            max(minimum, frame.midY - (collection.bounds.height + inset.top - inset.bottom) / 2),
                        ),
                    ),
                    isVisible: frame.intersects(collection.bounds.inset(by: inset))
                        && collection.indexPathsForVisibleItems.contains(path) && collection
                            .cellForItem(at: path) != nil,
                ))
            }

            func automaticWrite() {
                guard target == nil, !driver.ownsViewport else { blockedWriters += 1
                    return
                }
                collection.setContentOffset(.zero, animated: false)
            }

            func cancel() {
                target = nil // Retire consumer intent before a synchronous native end.
                driver.cancel()
            }

            func scrollViewDidScroll(_: UIScrollView) {
                scrolls += 1
                driver.didScroll()
            }

            func scrollViewDidEndScrollingAnimation(_: UIScrollView) {
                ends += 1
                driver.animationEnded()
            }

            func close() {
                cancel()
                window.isHidden = true
                window.rootViewController = nil
            }

            func targetIsVisible(_ id: Int) -> Bool {
                guard let path = dataSource.indexPath(for: id),
                      let frame = collection.layoutAttributesForItem(at: path)?.frame
                else { return false }
                return frame.intersects(collection.bounds.inset(by: collection.adjustedContentInset))
                    && collection.indexPathsForVisibleItems.contains(path) && collection.cellForItem(at: path) != nil
            }
        }

        static func verify() async throws {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                throw Failure(description: "missing settlement scene")
            }
            let native = Fixture(scene: scene)
            defer { native.close() }
            await native.install()
            native.request(92, animated: true)
            try require(
                native.target == 92 && native.driver.ownsViewport && native.quoted.isEmpty,
                "intent/quote retired before native arrival",
            )
            try await wait("native animation never moved") { native.collection.contentOffset.y > 20 }
            try require(native.driver.ownsViewport, "animation lost ownership while moving")
            native.automaticWrite() // Snapshot anchor.
            native.automaticWrite() // Latest pin.
            native.collection.contentInset = .init(top: 30, left: 0, bottom: 55, right: 0)
            native.automaticWrite() // Inset previousOffset fallback.
            native.targetHeight = 156
            await native.install() // Estimated-height reconfiguration while native animation runs.
            try await wait("native animated resize did not finish") { !native.results.isEmpty }
            try require(
                native.results == [.settled] && native.targetIsVisible(92) && native.quoted == [92],
                "animated target/quote did not settle after resize",
            )
            try require(
                native.blockedWriters == 3 && native.commands.first == true && native.commands.count <= 3,
                "automatic writers escaped or correction budget exceeded",
            )
            try require(native.scrolls > 2 && native.ends > 0, "fixture did not exercise UIKit native animation")

            let initial = Fixture(scene: scene)
            defer { initial.close() }
            await initial.install()
            initial.request(70, animated: false)
            try await wait("initial nonanimated target did not settle") { !initial.results.isEmpty }
            try require(
                initial.results == [.settled] && initial.commands.allSatisfy { !$0 } && initial.targetIsVisible(70),
                "initial position lost its synchronous offset command",
            )

            let remap = Fixture(scene: scene)
            defer { remap.close() }
            await remap.install()
            remap.request(92, animated: true)
            try await wait("album animation never moved") { remap.collection.contentOffset.y > 20 }
            remap.targetDisplay = 72 // Same raw member is now in another displayed album.
            remap.targetHeight = 128
            await remap.install()
            try await wait("album remapping never settled") { !remap.results.isEmpty }
            try require(
                remap.results == [.settled] && remap.targetIsVisible(72) && remap.quoted == [92],
                "stale display identity/quote survived album regrouping",
            )

            for cause in ["new-target", "drag", "latest", "source", "cover", "missing-member"] {
                let fixture = Fixture(scene: scene)
                defer { fixture.close() }
                await fixture.install()
                fixture.request(90, animated: true)
                try await wait("\(cause) animation never moved") { fixture.collection.contentOffset.y > 20 }
                switch cause {
                case "new-target": fixture.request(30, animated: true)
                case "source": fixture.current = false
                fixture.driver.layoutDidSettle()
                case "cover": fixture.attached = false
                fixture.driver.layoutDidSettle()
                case "missing-member": fixture.targetMemberPresent = false
                fixture.driver.layoutDidSettle()
                default:
                    fixture.cancel()
                    if cause == "latest" { fixture.collection.setContentOffset(.zero, animated: false) }
                }
                if cause == "new-target" {
                    let replacedOffset = fixture.collection.contentOffset.y
                    try await wait("replacement animation never moved") {
                        abs(fixture.collection.contentOffset.y - replacedOffset) > 10
                    }
                    fixture.driver.animationEnded() // A queued end from the superseded native command.
                    try await wait("new target did not settle") { !fixture.results.isEmpty }
                    try require(
                        fixture.results == [.settled] && fixture.quoted == [30] && fixture.targetIsVisible(30),
                        "superseded target/quote completed",
                    )
                } else {
                    let offset = fixture.collection.contentOffset
                    fixture.driver.animationEnded() // A late untagged UIKit wake must be inert.
                    fixture.driver.layoutDidSettle()
                    fixture.driver.didScroll()
                    try require(
                        !fixture.driver.ownsViewport && fixture.target == nil && fixture.quoted.isEmpty
                                && fixture.collection.contentOffset == offset,
                        "\(cause) retained or revived old authority",
                    )
                    if cause == "missing-member" { try require(
                        fixture.results == [.missing],
                        "deleted album member falsely settled",
                    ) }
                    if cause == "source" || cause == "cover" {
                        try require(fixture.results == [.cancelled], "revoked route falsely settled")
                    }
                }
            }

            let tracking = Fixture(scene: scene)
            defer { tracking.close() }
            await tracking.install()
            tracking.request(70, animated: false)
            tracking.collection.trackingOverride = true // DEBUG touch-down injection without willBeginDragging.
            try await wait("tracking-only cancellation retained consumer intent") { !tracking.results.isEmpty }
            try require(
                tracking.results == [.cancelled] && tracking.target == nil && !tracking.driver.ownsViewport,
                "tracking-only cancellation was not delivered",
            )

            let deferred = Fixture(scene: scene)
            defer { deferred.close() }
            await deferred.install()
            deferred.deferred = true
            deferred.request(90, animated: true)
            try require(
                deferred.driver.ownsViewport && deferred.commands.isEmpty,
                "unready layout consumed initial intent",
            )
            deferred.deferred = false
            deferred.driver.layoutDidSettle()
            try await wait("external layout release lost wakeup") { !deferred.results.isEmpty }
            try require(deferred.results == [.settled], "deferred native target failed")

            let failure = Fixture(scene: scene)
            defer { failure.close() }
            await failure.install()
            failure.deferred = true
            failure.request(90, animated: true)
            try await wait("watchdog left permanent barrier") { !failure.results.isEmpty }
            try require(
                failure.results == [.failed] && failure.quoted.isEmpty && !failure.driver.ownsViewport,
                "deadline claimed arrival or kept ownership",
            )
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw Failure(description: "A39 native settlement: \(detail)") }
        }

        private static func wait(_ detail: String, until condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while !condition(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try require(condition(), detail)
        }
    }
#endif
