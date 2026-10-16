// DeviceProximityMonitor.swift

import AVFoundation
import UIKit

// MARK: - DeviceProximityMonitor

/// Telegram's DeviceProximityManager: the proximity sensor runs only while something listens to it, so the screen
/// goes dark at the ear only then, and never while headphones play (MediaManager turns it off globally for a
/// connected headset). Each listener hears the current value when it subscribes.
@MainActor final class DeviceProximityMonitor {
    // MARK: Internal

    static let shared = DeviceProximityMonitor()

    /// The phone is held to the ear.
    private(set) var currentValue = false

    // MARK: Private

    private var subscribers = [UUID: (Bool) -> Void]()
    private var isGloballyEnabled = true
    private var observers = [NSObjectProtocol]()
    #if DEBUG
        private var simulatedValue: Bool?
    #endif

    /// The sensor's own reading. It outlives the last listener, since the sensor keeps running until the phone
    /// leaves the ear, so a phone still at the ear when playback ends is known to be there.
    var isNear: Bool {
        #if DEBUG
            if let simulatedValue { return simulatedValue }
        #endif
        return currentValue || (UIDevice.current.isProximityMonitoringEnabled && UIDevice.current.proximityState)
    }

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: UIDevice.current,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sensorChanged(UIDevice.current.proximityState) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setGloballyEnabled(!Self.isHeadsetConnected()) }
        })
        self.isGloballyEnabled = !Self.isHeadsetConnected()
    }

    // MARK: Private

    /// ManagedAudioSession's isHeadsetPluggedIn: wired or Bluetooth headphones.
    private static func isHeadsetConnected() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType)
        }
    }

    // MARK: Internal

    func add(_ subscriber: @escaping (Bool) -> Void) -> UUID {
        let wasEmpty = subscribers.isEmpty
        let id = UUID()
        subscribers[id] = subscriber
        subscriber(currentValue)
        if wasEmpty { updateState(hasSubscribers: true) }
        return id
    }

    func remove(_ id: UUID) {
        let wasEmpty = subscribers.isEmpty
        subscribers[id] = nil
        if subscribers.isEmpty, !wasEmpty { updateState(hasSubscribers: false) }
    }

    #if DEBUG
        /// Stands in for the sensor, which the Simulator lacks. `nil` gives it back.
        func simulate(_ value: Bool?) {
            simulatedValue = value
            sensorChanged(value ?? false)
        }
    #endif

    private func setGloballyEnabled(_ value: Bool) {
        guard isGloballyEnabled != value else { return }
        isGloballyEnabled = value
        updateState(hasSubscribers: !subscribers.isEmpty)
    }

    private func sensorChanged(_ value: Bool) {
        // The sensor stays on until the phone leaves the ear, so the screen doesn't light up against the cheek.
        if !value, subscribers.isEmpty { UIDevice.current.isProximityMonitoringEnabled = false }
        guard currentValue != value else { return }
        currentValue = value
        notify()
    }

    private func updateState(hasSubscribers: Bool) {
        if hasSubscribers, isGloballyEnabled {
            UIDevice.current.isProximityMonitoringEnabled = true
            var value = UIDevice.current.proximityState
            #if DEBUG
                if let simulatedValue { value = simulatedValue }
            #endif
            if value != currentValue {
                currentValue = value
                notify()
            }
        } else if currentValue {
            currentValue = false
            notify()
        } else {
            UIDevice.current.isProximityMonitoringEnabled = false
        }
    }

    private func notify() {
        for subscriber in Array(subscribers.values) {
            subscriber(currentValue)
        }
    }
}
