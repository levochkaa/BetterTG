// LiveLocationManager.swift

import Combine
import CoreLocation
import Foundation

// MARK: - LiveLocationBroadcast

/// One of the account's own live locations being shared, an entry of Telegram's `broadcastToMessageIds`.
struct LiveLocationBroadcast: Equatable {
    struct Key: Hashable {
        let chatID: Int64
        let messageID: Int64
    }

    /// The client whose `updateActiveLiveLocationMessages` listed the message.
    let source: TdUpdateSource
    let chatID: Int64
    let messageID: Int64
    /// The message's date, for Telegram's newest-first order.
    let date: Int
    /// When sharing ends, in Unix time; nil for an indefinite period.
    let deadline: Int?
    /// Kept on every update: TDLib takes 0 as turning the proximity alert off.
    let proximityAlertRadius: Int

    var key: Key { Key(chatID: chatID, messageID: messageID) }
}

// MARK: - LiveLocationManager

/// Telegram's LiveLocationManager: while the account shares a live location, the device location goes to every such
/// message with `editMessageLiveLocation`, at most once in 4 seconds, and a message whose period has ended is stopped.
/// TDLib lists the account's own live locations that need updating in `updateActiveLiveLocationMessages`; the list
/// belongs to the client that sent it, so a replaced client's or another account's messages are never edited.
/// BetterTG has When In Use access and closes TDLib in the background, so updates go while the app is open.
@MainActor final class LiveLocationManager: NSObject, CLLocationManagerDelegate {
    // MARK: Private

    /// A location fix as plain values, carried from CoreLocation's delegate queue.
    private struct Fix {
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        let course: Double
        let speed: Double
    }

    // MARK: Internal

    static let shared = LiveLocationManager()
    /// Telegram's liveLocationIndefinitePeriod.
    static let indefinitePeriod = Int(Int32.max)

    /// Telegram's throttle for location edits.
    private static let updateInterval = Duration.seconds(4)
    /// TDLib's limit for a location's horizontal accuracy.
    private static let maximumAccuracy = 1500.0

    /// The live locations being shared, in TDLib's order.
    @Published private(set) var broadcasts = [LiveLocationBroadcast]()

    private let manager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    /// The client `broadcasts` belongs to.
    private var source: TdUpdateSource?
    private var stoppedMessages = Set<LiveLocationBroadcast.Key>()
    private var invalidationTask: Task<Void, Never>?
    private var invalidationDeadline: Int?
    private var isUpdatingLocation = false
    private var fix: Fix?
    private var heading: Double?
    private var throttleTask: Task<Void, Never>?
    private var hasPendingFix = false

    override private init() {
        super.init()
        // DeviceLocationManager's configuration.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 2
        manager.showsBackgroundLocationIndicator = true
        manager.delegate = self
    }

    /// TDLib's heading is 1-360 degrees, 0 when unknown; CoreLocation's course is negative when unknown.
    private static func tdHeading(_ degrees: Double) -> Int {
        guard degrees >= 0 else { return 0 }
        let value = Int(degrees) % 360
        return value == 0 ? 360 : value
    }

    func start() {
        guard cancellables.isEmpty else { return }
        nc.scopedPublisher(&cancellables, for: .updateActiveLiveLocationMessages) { [weak self] update in
            self?.update(messages: update.value.messages, source: update.source)
        }
        TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, source != self.source else { return }
                reset()
            }
            .store(in: &cancellables)
    }

    /// Telegram's cancelLiveLocation: stops sharing every live location in the chat.
    func stop(chatID: Int64, source: TdUpdateSource) {
        for broadcast in broadcasts where broadcast.source == source && broadcast.chatID == chatID {
            sendStop(broadcast.key)
        }
    }

    /// Stop All in Telegram's live location menu.
    func stopAll(source: TdUpdateSource) {
        for broadcast in broadcasts where broadcast.source == source {
            sendStop(broadcast.key)
        }
    }

    // MARK: Location

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        let fix = Fix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            course: location.course,
            speed: location.speed,
        )
        Task { @MainActor [weak self] in self?.locationUpdated(fix) }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // DeviceLocationManager's effectiveHeading.
        let heading: Double? =
            if newHeading.headingAccuracy < 0 {
                nil
            } else if newHeading.trueHeading > 0 {
                newHeading.trueHeading
            } else {
                newHeading.magneticHeading
            }
        Task { @MainActor [weak self] in self?.headingUpdated(heading) }
    }

    /// Telegram's activeLiveLocationMessages handler: an outgoing message that was sent is shared until its date plus
    /// its period, or forever for the indefinite period; one past it is stopped.
    private func update(messages: [Message], source: TdUpdateSource) {
        if self.source != source {
            reset()
            self.source = source
        }
        let now = Int(Foundation.Date().timeIntervalSince1970)
        var broadcasts = [LiveLocationBroadcast]()
        var stopped = Set<LiveLocationBroadcast.Key>()
        for message in messages where message.isOutgoing && message.sendingState == nil {
            guard case .messageLiveLocation(let live) = message.content else { continue }
            let period = live.location.livePeriod
            let broadcast = LiveLocationBroadcast(
                source: source,
                chatID: message.chatId,
                messageID: message.id,
                date: message.date,
                deadline: period == Self.indefinitePeriod ? nil : message.date + period,
                proximityAlertRadius: live.location.proximityAlertRadius,
            )
            if period == Self.indefinitePeriod || message.date + period > now {
                broadcasts.append(broadcast)
            } else {
                stopped.insert(broadcast.key)
            }
        }
        apply(broadcasts, stopped: stopped)
    }

    /// Telegram's update(broadcastToMessageIds:stopMessageIds:): newly stopped messages get a stop edit, and the
    /// device location runs while anything is shared.
    private func apply(_ broadcasts: [LiveLocationBroadcast], stopped: Set<LiveLocationBroadcast.Key>) {
        let newlyStopped = stopped.subtracting(stoppedMessages)
        stoppedMessages = stopped
        for key in newlyStopped {
            sendStop(key)
        }
        if self.broadcasts != broadcasts {
            self.broadcasts = broadcasts
            if broadcasts.isEmpty {
                stopUpdatingLocation()
            } else {
                startUpdatingLocation()
            }
        }
        rescheduleTimer()
    }

    /// Telegram's rescheduleTimer: a message whose period has ended moves to the stopped ones, and a timer fires at
    /// the earliest remaining end.
    private func rescheduleTimer() {
        let now = Int(Foundation.Date().timeIntervalSince1970)
        let expired = broadcasts.filter { broadcast in broadcast.deadline.map { now >= $0 } ?? false }
        guard expired.isEmpty else {
            let expiredKeys = Set(expired.map(\.key))
            apply(
                broadcasts.filter { !expiredKeys.contains($0.key) },
                stopped: stoppedMessages.union(expiredKeys),
            )
            return
        }
        let earliest = broadcasts.compactMap(\.deadline).min()
        guard earliest != invalidationDeadline else { return }
        invalidationTask?.cancel()
        invalidationTask = nil
        invalidationDeadline = earliest
        guard let earliest else { return }
        invalidationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, earliest - now)))
            guard let self, !Task.isCancelled else { return }
            invalidationTask = nil
            invalidationDeadline = nil
            rescheduleTimer()
        }
    }

    private func reset() {
        invalidationTask?.cancel()
        invalidationTask = nil
        invalidationDeadline = nil
        stoppedMessages = []
        stopUpdatingLocation()
        source = nil
        if !broadcasts.isEmpty { broadcasts = [] }
    }

    private func authorizationChanged() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if !broadcasts.isEmpty { startUpdatingLocation() }
        case .notDetermined:
            break
        default:
            stopUpdatingLocation()
        }
    }

    private func startUpdatingLocation() {
        guard !isUpdatingLocation else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            // The authorization change starts the updates.
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isUpdatingLocation = true
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        default:
            break
        }
    }

    private func stopUpdatingLocation() {
        throttleTask?.cancel()
        throttleTask = nil
        hasPendingFix = false
        fix = nil
        heading = nil
        guard isUpdatingLocation else { return }
        isUpdatingLocation = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func locationUpdated(_ newFix: Fix) {
        guard isUpdatingLocation else { return }
        fix = newFix
        sendThrottled()
    }

    private func headingUpdated(_ newHeading: Double?) {
        guard isUpdatingLocation else { return }
        heading = newHeading
        guard fix != nil else { return }
        sendThrottled()
    }

    /// Telegram's mapToThrottled with a 4 second pause: the first location goes at once, then the latest one at most
    /// every 4 seconds.
    private func sendThrottled() {
        guard throttleTask == nil else {
            hasPendingFix = true
            return
        }
        hasPendingFix = false
        sendLocation()
        throttleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.updateInterval)
            guard let self, !Task.isCancelled else { return }
            throttleTask = nil
            if hasPendingFix { sendThrottled() }
        }
    }

    /// Telegram's updateDeviceCoordinate: every shared message gets the location with its accuracy and the heading,
    /// or the course while moving faster than 1 m/s.
    private func sendLocation() {
        guard let fix, let source, let client = TDLib.shared.authorizationClient(for: source) else { return }
        var direction = heading ?? fix.course
        if fix.speed > 1 { direction = fix.course }
        let accuracy = Double(Int(min(max(fix.horizontalAccuracy, 0), Self.maximumAccuracy)))
        let tdHeading = Self.tdHeading(direction)
        for broadcast in broadcasts where broadcast.source == source {
            let location = LiveLocation(
                location: Location(latitude: fix.latitude, longitude: fix.longitude, horizontalAccuracy: accuracy),
                livePeriod: 0,
                heading: tdHeading,
                proximityAlertRadius: broadcast.proximityAlertRadius,
            )
            let chatID = broadcast.chatID
            let messageID = broadcast.messageID
            Task {
                _ = try? await client.editMessageLiveLocation(
                    chatId: chatID,
                    messageId: messageID,
                    replyMarkup: nil,
                    location: location,
                )
            }
        }
    }

    /// Telegram's requestEditLiveLocation with stop.
    private func sendStop(_ key: LiveLocationBroadcast.Key) {
        guard let source, let client = TDLib.shared.authorizationClient(for: source) else { return }
        Task {
            _ = try? await client.editMessageLiveLocation(
                chatId: key.chatID,
                messageId: key.messageID,
                replyMarkup: nil,
                location: nil,
            )
        }
    }
}
