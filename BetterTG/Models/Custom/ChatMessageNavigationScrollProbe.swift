// ChatMessageNavigationScrollProbe.swift

#if DEBUG
    import UIKit

    /// Actual native animation and production settlement driver; the route/model
    /// adapter is isolated and does not instantiate ChatView or issue TDLib reads.
    @MainActor enum ChatMessageNavigationScrollProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }
        private struct EndOrderSetupFailure: Swift.Error, CustomStringConvertible { let description: String }

        private struct GeometryReceipt: CustomStringConvertible {
            let offset: CGPoint
            let bounds: CGRect
            let size: CGSize
            let inset: UIEdgeInsets
            let targetFrame: CGRect?
            let targetOffset: CGFloat?
            let intersects: Bool
            let visibleIndex: Bool
            let mounted: Bool
            let targetPresent: Bool
            let sceneState: Int?

            var description: String {
                "offset=\(offset) bounds=\(bounds) size=\(size) inset=\(inset)"
                    + " targetFrame=\(String(describing: targetFrame)) targetOffset=\(String(describing: targetOffset))"
                    + " errorY=\(String(describing: targetOffset.map { offset.y - $0 }))"
                    + " intersects=\(intersects) visibleIndex=\(visibleIndex) mounted=\(mounted)"
                    + " targetPresent=\(targetPresent) sceneState=\(String(describing: sceneState))"
            }
        }

        private struct CompletionReceipt {
            let outcome: ChatMessageNavigationScroll.Outcome
            let geometry: GeometryReceipt
            let commands: [Bool]
            let ends: Int
            let scrolls: Int
        }

        /// Observes only existing sleep resumptions; it schedules no work.
        private final class WaitReceipt: CustomStringConvertible {
            private var startedAt: CFTimeInterval = 0
            private var previousResume: CFTimeInterval = 0
            private var count = 0
            private var maximumGap: CFTimeInterval = 0
            private var lastGaps = [CFTimeInterval]()

            var description: String {
                "count=\(count) maxGap=\(maximumGap) elapsed=\(previousResume - startedAt) lastGaps=\(lastGaps)"
            }

            func begin() {
                startedAt = CACurrentMediaTime()
                previousResume = startedAt
            }

            func resumed() {
                let now = CACurrentMediaTime()
                let gap = now - previousResume
                previousResume = now
                count += 1
                maximumGap = max(maximumGap, gap)
                if lastGaps.count == 5 { lastGaps.removeFirst() }
                lastGaps.append(gap)
            }
        }

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
            var rowHeights = [Int: CGFloat]()
            var results = [ChatMessageNavigationScroll.Outcome]()
            var commands = [Bool]()
            var ends = 0
            var lastEndOffset: CGPoint?
            var scrolls = 0
            var blockedWriters = 0
            var quoted = [Int]()
            var completionReceipt: CompletionReceipt?
            var commandHook: (() -> Void)?
            var layoutMutationTask: Task<Void, Never>?

            init(scene: UIWindowScene, estimatedHeight: CGFloat = 80) {
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimatedHeight),
                ))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: .init(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .estimated(estimatedHeight),
                    ),
                    subitems: [item],
                )
                let layout = UICollectionViewCompositionalLayout(section: .init(group: group))
                self.collection = Collection(
                    frame: CGRect(x: 0, y: 0, width: 320, height: 400),
                    collectionViewLayout: layout,
                )
                self.window = UIWindow(windowScene: scene)
                super.init()
                driver.debugTracingEnabled = true
                collection.contentInsetAdjustmentBehavior = .never
                collection.transform = .init(scaleX: 1, y: -1)
                collection.register(Cell.self, forCellWithReuseIdentifier: "row")
                collection.delegate = self
                self
                    .dataSource =
                    UICollectionViewDiffableDataSource(collectionView: collection) { [weak self] collection, path, id in
                    let cell = collection.dequeueReusableCell(withReuseIdentifier: "row", for: path) as! Cell
                    cell.rowHeight = self?.rowHeights[id]
                        ?? (id == self?.targetDisplay ? self?.targetHeight ?? 48 : self?.height ?? 48)
                    return cell
                }
                window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
                let root = UIViewController()
                window.rootViewController = root
                window.isHidden = false
                root.view.addSubview(collection)
            }

            func install(wake: Bool = true) async {
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
                if wake { driver.layoutDidSettle() }
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
                        // Observe before retiring the consumer target. Do not force
                        // layout or resolve again to obtain this diagnostic receipt.
                        completionReceipt = .init(
                            outcome: outcome, geometry: geometryReceipt(for: targetDisplay),
                            commands: commands, ends: ends, scrolls: scrolls,
                        )
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
                lastEndOffset = collection.contentOffset
                driver.animationEnded()
            }

            func close() {
                layoutMutationTask?.cancel()
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

            func targetOffset(_ id: Int) -> CGFloat? {
                guard let path = dataSource.indexPath(for: id),
                      let frame = collection.layoutAttributesForItem(at: path)?.frame
                else { return nil }
                let inset = collection.adjustedContentInset
                let minimum = -inset.top
                let maximum = max(minimum, collection.contentSize.height - collection.bounds.height + inset.bottom)
                return min(
                    maximum,
                    max(minimum, frame.midY - (collection.bounds.height + inset.top - inset.bottom) / 2),
                )
            }

            func diagnostics(for display: Int) -> String {
                let completion = completionReceipt.map {
                    "completion outcome=\($0.outcome) commands=\($0.commands) ends=\($0.ends) scrolls=\($0.scrolls) \($0.geometry)"
                } ?? "completion=none"
                return "\(completion)\npost results=\(results) commands=\(commands) ends=\(ends) scrolls=\(scrolls)"
                    + " quoteCount=\(quoted.count) \(geometryReceipt(for: display))\n\(driver.debugReport)"
            }

            private func geometryReceipt(for display: Int?) -> GeometryReceipt {
                let path = display.flatMap { dataSource.indexPath(for: $0) }
                let frame = path.flatMap { collection.layoutAttributesForItem(at: $0)?.frame }
                let inset = collection.adjustedContentInset
                let minimum = -inset.top
                let maximum = max(minimum, collection.contentSize.height - collection.bounds.height + inset.bottom)
                return .init(
                    offset: collection.contentOffset, bounds: collection.bounds, size: collection.contentSize,
                    inset: inset, targetFrame: frame,
                    targetOffset: frame.map {
                        min(maximum, max(minimum, $0.midY - (collection.bounds.height + inset.top - inset.bottom) / 2))
                    },
                    intersects: frame?.intersects(collection.bounds.inset(by: inset)) ?? false,
                    visibleIndex: path.map { collection.indexPathsForVisibleItems.contains($0) } ?? false,
                    mounted: path.flatMap { collection.cellForItem(at: $0) } != nil,
                    targetPresent: target != nil, sceneState: window.windowScene?.activationState.rawValue,
                )
            }
        }

        static func runEndOrderProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-navigation-end-order") else { return }
            Task {
                let result: String
                do {
                    try await verifyLatestEndOrder()
                    result = "Navigation end-order probe passed: native later-end callback after harness relocation; "
                        + "manual verifier scheduling/real retained display link=true; "
                        + "two post-latest-end observations before correction=true; "
                        + "second native animation=injected; full settlement/ChatView/historical failure cause=unverified; RPC=0"
                } catch let error as EndOrderSetupFailure {
                    result = "Navigation end-order probe inconclusive: \(error)"
                } catch {
                    result = "Navigation end-order probe failed: \(error)"
                }
                log(result)
                if let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: root.appendingPathComponent("message-navigation-end-order-probe.txt"), options: .atomic,
                    )
                }
            }
        }

        static func verify() async throws {
            try verifyCorrectionBudget()
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                throw Failure(description: "missing settlement scene")
            }
            let native = Fixture(scene: scene)
            let motionWait = WaitReceipt()
            let completionWait = WaitReceipt()
            defer { native.close() }
            do {
                await native.install()
                native.request(92, animated: true)
                try require(
                    native.target == 92 && native.driver.ownsViewport && native.quoted.isEmpty,
                    "intent/quote retired before native arrival",
                )
                try await wait("native animation never moved", receipt: motionWait) {
                    native.collection.contentOffset.y > 20
                }
                try require(native.driver.ownsViewport, "animation lost ownership while moving")
                native.automaticWrite() // Snapshot anchor.
                native.automaticWrite() // Latest pin.
                native.collection.contentInset = .init(top: 30, left: 0, bottom: 55, right: 0)
                native.automaticWrite() // Inset previousOffset fallback.
                native.targetHeight = 156
                await native.install() // Estimated-height reconfiguration while native animation runs.
                try await wait("native animated resize did not finish", receipt: completionWait) {
                    !native.results.isEmpty
                }
                let settled = native.results == [.settled]
                let visible = native.targetIsVisible(92)
                let quoted = native.quoted == [92]
                try require(
                    settled && visible && quoted,
                    "animated target/quote did not settle after resize: outcomeSettled=\(settled) postVisible=\(visible) quoted=\(quoted)",
                )
                try require(
                    native.blockedWriters == 3 && native.commands.first == true
                        && native.commands.dropFirst().allSatisfy { !$0 }
                        && native.commands.count <= ChatMessageNavigationScroll.CorrectionBudget.maximum + 1,
                    "automatic writers escaped or correction budget exceeded",
                )
                try require(native.scrolls > 2 && native.ends > 0, "fixture did not exercise UIKit native animation")
            } catch {
                throw Failure(
                    description: "\(error)\nwait-motion \(motionWait)\nwait-completion \(completionWait)\n\(native.diagnostics(for: 92))",
                )
            }

            try await verifySuccessiveSizing(scene: scene)

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

        private static func verifyLatestEndOrder() async throws {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                throw EndOrderSetupFailure(description: "missing native scene")
            }
            // Accurate estimates isolate end ordering from the natural fixture's
            // separate self-sizing/deadline behavior. Rows still use UIKit sizing.
            let fixture = Fixture(scene: scene, estimatedHeight: 48)
            fixture.driver.debugManualVerification = true
            defer { fixture.close() }
            await fixture.install()
            fixture.request(40, animated: true)
            do {
                try await waitForEndOrderSetup("first genuine end") {
                    fixture.ends > 0 || !fixture.results.isEmpty
                }
                try requireEndOrderSetup(
                    fixture.ends == 1 && fixture.commands == [true] && fixture.results.isEmpty
                        && fixture.driver.ownsViewport && fixture.driver.debugVerificationReceipt.elapsed < 2,
                    "first flight did not produce one current end before the unchanged deadline",
                )
                try requireEndOrderSetup(fixture.driver.debugAdvanceScheduledFrame(), "first sample not scheduled")
                let firstSample = fixture.driver.debugVerificationReceipt
                guard let oldOffset = firstSample.firstOffset,
                      let targetOffset = fixture.targetOffset(40)
                else {
                    throw EndOrderSetupFailure(description: "first sample/target geometry unavailable")
                }
                let injectedOffset = CGPoint(x: 0, y: targetOffset + 64)
                let inset = fixture.collection.adjustedContentInset
                let maximum = fixture.collection.contentSize.height - fixture.collection.bounds.height + inset.bottom
                try requireEndOrderSetup(
                    firstSample.checking && firstSample.receivedEnd
                        && injectedOffset.y > -inset.top && injectedOffset.y < maximum
                        && abs(injectedOffset.y - oldOffset.y) > 32,
                    "manual scheduling or distinct unclamped relocation not armed",
                )
                // Deliberately injected second UIKit animation, not a second
                // driver command or a claim about actual ChatView behavior.
                fixture.collection.setContentOffset(injectedOffset, animated: true)
                try await waitForEndOrderSetup("injected native movement") {
                    abs(fixture.collection.contentOffset.y - oldOffset.y) > 1 || !fixture.results.isEmpty
                }
                try await waitForEndOrderSetup("later genuine end") {
                    fixture.ends >= 2 || !fixture.results.isEmpty
                }
                let before = fixture.driver.debugVerificationReceipt
                try requireEndOrderSetup(
                    fixture.ends == 2 && fixture.commands == [true] && fixture.results.isEmpty
                        && before.elapsed < 2 && before.checking && before.receivedEnd
                        && abs((fixture.lastEndOffset?.y ?? .infinity) - injectedOffset.y) <= 0.75
                        && abs(fixture.collection.contentOffset.y - injectedOffset.y) <= 0.75,
                    "later end was not at the injected endpoint before the unchanged deadline",
                )
                try requireEndOrderSetup(fixture.driver.debugAdvanceScheduledFrame(), "later-end sample not scheduled")
                let after = fixture.driver.debugVerificationReceipt
                try requireEndOrderSetup(after.elapsed < 2, "decisive sample reached the unchanged deadline")
                try require(
                    fixture.results.isEmpty && fixture.driver.ownsViewport
                        && fixture.commands == [true] && fixture.quoted.isEmpty
                        && abs(fixture.collection.contentOffset.y - (fixture.targetOffset(40) ?? .infinity)) > 0.75,
                    "first post-latest-end sample prematurely corrected, settled, or retired the residual",
                )
                if !after.checking || !after.receivedEnd {
                    try require(!after.checking && !after.receivedEnd, "unexpected partial checker/end retirement")
                    let refusedAfterStop = !fixture.driver.debugAdvanceScheduledFrame()
                    try require(refusedAfterStop, "manual verifier bypassed the stopped production checker")
                    throw Failure(description: "latest accepted end lost its checker using a pre-end sample; "
                        + "checking=\(after.checking) receivedEnd=\(after.receivedEnd) manualAfterStopRefused=\(refusedAfterStop) "
                        + "owner=\(fixture.driver.ownsViewport) driverCommands=\(fixture.commands) nativeEnds=\(fixture.ends) "
                        + "quotes=\(fixture.quoted.count) elapsed=\(after.elapsed) "
                        + "injectedOffsetY=\(injectedOffset.y) pre-endSampleY=\(oldOffset.y) "
                        + "skippedAutomaticFrames=\(after.skippedAutomaticFrames)")
                }
                try require(
                    after.firstOffset == fixture.collection.contentOffset && fixture.commands == [true]
                        && fixture.quoted.isEmpty,
                    "first post-latest-end observation prematurely corrected or quoted",
                )
                try require(fixture.driver.debugAdvanceScheduledFrame(), "second post-latest-end sample lost checker")
                try require(
                    fixture.commands == [true, false] && fixture.results.isEmpty && fixture.quoted.isEmpty,
                    "second post-latest-end observation did not admit the current residual correction",
                )
            } catch let error as EndOrderSetupFailure {
                throw EndOrderSetupFailure(description: "\(error)\n\(fixture.diagnostics(for: 40))")
            } catch {
                throw Failure(description: "\(error)\n\(fixture.diagnostics(for: 40))")
            }
        }

        private static func requireEndOrderSetup(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw EndOrderSetupFailure(description: detail) }
        }

        private static func waitForEndOrderSetup(_ detail: String, until condition: () -> Bool) async throws {
            do {
                try await wait(detail, until: condition)
            } catch {
                throw EndOrderSetupFailure(description: "\(detail): \(error)")
            }
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw Failure(description: "A39 native settlement: \(detail)") }
        }

        private static func verifyCorrectionBudget() throws {
            var convergence = ChatMessageNavigationScroll.CorrectionBudget()
            for error: CGFloat in [1403.833, 177.167, 46.167, 7.0] {
                try require(convergence.admit(error: error), "converging self-size pass exhausted budget")
            }
            var stalled = ChatMessageNavigationScroll.CorrectionBudget()
            try require(
                stalled.admit(error: 46) && stalled.admit(error: 46)
                        && !stalled.admit(error: 46),
                "repeated no-progress correction did not stop",
            )
            var oscillating = ChatMessageNavigationScroll.CorrectionBudget()
            for pass in 0..<ChatMessageNavigationScroll.CorrectionBudget.maximum {
                try require(
                    oscillating.admit(error: pass.isMultiple(of: 2) ? 100 : 90),
                    "one rebounding pass could not retry",
                )
            }
            try require(!oscillating.admit(error: 80), "oscillating corrections exceeded hard command cap")
        }

        private static func verifySuccessiveSizing(scene: UIWindowScene) async throws {
            let fixture = Fixture(scene: scene)
            defer { fixture.close() }
            await fixture.install()
            let rows = [67, 68, 69, 71]
            let residuals: [CGFloat] = [1404, 177, 46, 7]
            var appliedRows = [Int]()
            // Real estimated cells resize in distinct passes. The post-layout offset
            // adjustment is injected deterministically, matching the recorded UIKit
            // compensation shape; it is not claimed as a synthetic user gesture.
            fixture.commandHook = { [weak fixture] in
                guard let fixture, fixture.commands.count <= rows.count else { return }
                let pass = fixture.commands.count - 1
                fixture.layoutReady = false
                fixture.layoutMutationTask = Task { @MainActor [weak fixture] in
                    guard let fixture, !Task.isCancelled, fixture.driver.ownsViewport else { return }
                    fixture.rowHeights[rows[pass]] = CGFloat(180 - pass * 30)
                    await fixture.install(wake: false)
                    guard !Task.isCancelled, fixture.driver.ownsViewport,
                          let offset = fixture.targetOffset(70) else { return }
                    appliedRows.append(rows[pass])
                    fixture.collection.setContentOffset(.init(x: 0, y: offset + residuals[pass]), animated: false)
                    fixture.driver.layoutDidSettle()
                    fixture.layoutMutationTask = nil
                }
            }
            fixture.request(70, animated: false)
            try await wait("successive sizing correction did not finish") { !fixture.results.isEmpty }
            try require(
                fixture.results == [.settled] && fixture.quoted == [70] && fixture.targetIsVisible(70),
                "successive self-size lost settled target/quote: \(fixture.results)",
            )
            try require(
                appliedRows == rows && fixture.commands.count > 3
                        && fixture.commands.count <= ChatMessageNavigationScroll.CorrectionBudget.maximum + 1,
                "successive-sizing fixture did not cross old two-correction limit",
            )
            try require(
                abs(fixture.collection.contentOffset.y - (fixture.targetOffset(70) ?? .infinity)) <= 0.75,
                "visible but off-center target falsely settled",
            )
        }

        private static func wait(
            _ detail: String,
            receipt: WaitReceipt? = nil,
            until condition: () -> Bool,
        ) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            receipt?.begin()
            while !condition(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
                receipt?.resumed()
            }
            try require(condition(), detail)
        }
    }
#endif
