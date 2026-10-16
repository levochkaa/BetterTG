// RaiseToListenActivator.swift

import AVFoundation
import CoreMotion
import QuartzCore
import UIKit

// MARK: - RaiseToListenSettings

/// Telegram's Data and Storage switch (MediaInputSettings.enableRaiseToSpeak), on by default and kept on the device.
enum RaiseToListenSettings {
    // MARK: Private

    private static let key = "BetterTG.raiseToListen"

    // MARK: Internal

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - RecordingTone

/// ManagedAudioRecorder's begin_record tone, which a recording started by raising the phone plays from the speaker
/// before it records.
@MainActor enum RecordingTone {
    // MARK: Private

    private static var player: AVAudioPlayer?

    // MARK: Internal

    static func play() async {
        guard let url = Bundle.main.url(forResource: "begin_record", withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        player.play()
        defer { if self.player === player { self.player = nil } }
        try? await Task.sleep(for: .seconds(player.duration))
    }
}

// MARK: - RaiseToListenActivator

/// Telegram's RaiseToListenActivator: a raise gesture gives the phone one second to reach the ear, and the
/// proximity sensor going on then activates; taking the phone away deactivates. `activateBasedOnProximity` lets a
/// phone still held to the ear activate again, as after a voice playlist ends.
@MainActor final class RaiseToListenActivator {
    // MARK: Internal

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                gestureSource = RaiseGesture.make { [weak self] in self?.raiseDetected() }
            } else {
                gestureSource?.invalidate()
                gestureSource = nil
                stopCheckingProximity()
                if isActivated {
                    isActivated = false
                    deactivate()
                }
            }
        }
    }

    private(set) var isActivated = false

    // MARK: Private

    private let shouldActivate: () -> Bool
    private let activate: () -> Void
    private let deactivate: () -> Void
    private var gestureSource: RaiseGesture?
    private var proximitySubscription: UUID?
    private var proximityState = false
    private var timer: Timer?
    private var activationTimestamp: CFTimeInterval = 0

    #if DEBUG
        /// Which raise gestures the activator hears: CoreMotion's gesture manager or the attitude fallback.
        var gestureSourceName: String? {
            gestureSource?.kind
        }
    #endif

    init(shouldActivate: @escaping () -> Bool, activate: @escaping () -> Void, deactivate: @escaping () -> Void) {
        self.shouldActivate = shouldActivate
        self.activate = activate
        self.deactivate = deactivate
    }

    isolated deinit {
        timer?.invalidate()
        gestureSource?.invalidate()
        if let proximitySubscription { DeviceProximityMonitor.shared.remove(proximitySubscription) }
    }

    // MARK: Internal

    func activateBasedOnProximity() {
        if DeviceProximityMonitor.shared.isNear { raiseDetected() }
    }

    /// An activation younger than a second is undone when the app leaves the foreground: the raise most likely
    /// came with locking or switching away from the phone.
    func applicationResignedActive() {
        guard isActivated else { return }
        let duration = CACurrentMediaTime() - activationTimestamp
        guard duration > 0, duration < 1 else { return }
        timer?.invalidate()
        timer = nil
        stopCheckingProximity()
        isActivated = false
        deactivate()
    }

    /// startCheckingProximity: the gesture that starts the one-second window.
    func raiseDetected() {
        guard isEnabled, shouldActivate() else { return }
        let previous = proximitySubscription
        proximitySubscription = DeviceProximityMonitor.shared.add { [weak self] value in
            self?.proximityChanged(value)
        }
        if let previous { DeviceProximityMonitor.shared.remove(previous) }
        if proximityState {
            isActivated = true
            activationTimestamp = CACurrentMediaTime()
            activate()
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.timer = nil
                    self.stopCheckingProximity()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    // MARK: Private

    private func stopCheckingProximity() {
        guard let proximitySubscription else { return }
        self.proximitySubscription = nil
        DeviceProximityMonitor.shared.remove(proximitySubscription)
    }

    private func proximityChanged(_ value: Bool) {
        guard proximityState != value else { return }
        proximityState = value
        if value, timer != nil {
            timer?.invalidate()
            timer = nil
            isActivated = true
            activationTimestamp = CACurrentMediaTime()
            activate()
        } else if !value {
            timer?.invalidate()
            timer = nil
            stopCheckingProximity()
            isActivated = false
            deactivate()
        }
    }
}

// MARK: - RaiseGesture

/// Where raise gestures come from: CoreMotion's private gesture manager, which Telegram's activator reaches by
/// name, or, on a system without it, the device's attitude moving from facing the user to standing at the ear.
@MainActor private final class RaiseGesture {
    // MARK: Private

    /// Telegram stores the class name shifted by one character (TGEncodeText).
    private static let managerClassName = String("DNHftuvsfNbobhfs".unicodeScalars.map {
        Character(UnicodeScalar($0.value - 1) ?? $0)
    })
    private static let initializer = "initWithPriority:"
    private static let handlerSetter = "setGestureHandler:"
    /// How long after facing the screen a phone standing upright still counts as raised.
    private static let raiseWindow: TimeInterval = 1.5

    private var systemManager: NSObject?
    private var motionManager: CMMotionManager?
    private var facedAt: TimeInterval?
    private var isAtEar = false

    // MARK: Internal

    var kind: String {
        systemManager != nil ? "system" : "motion"
    }

    // MARK: Internal

    static func make(handler: @escaping @MainActor () -> Void) -> RaiseGesture? {
        let gesture = RaiseGesture()
        if gesture.startSystemManager(handler: handler) || gesture.startMotionUpdates(handler: handler) {
            return gesture
        }
        return nil
    }

    func invalidate() {
        if let systemManager {
            typealias SetHandler = @convention(c) (AnyObject, Selector, (@convention(block) (Int32, Int32) -> Void)?)
                -> Void
            let selector = NSSelectorFromString(Self.handlerSetter)
            unsafeBitCast(systemManager.method(for: selector), to: SetHandler.self)(systemManager, selector, nil)
        }
        systemManager = nil
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
    }

    // MARK: Private

    /// `initWithPriority:2` and a handler whose first argument 0 is the raise, as RaiseToListenActivator sets it.
    private func startSystemManager(handler: @escaping @MainActor () -> Void) -> Bool {
        typealias Initialize = @convention(c) (AnyObject, Selector, Int32) -> Unmanaged<NSObject>?
        typealias SetHandler = @convention(c) (AnyObject, Selector, (@convention(block) (Int32, Int32) -> Void)?)
            -> Void
        guard let managerClass = NSClassFromString(Self.managerClassName) as? NSObject.Type,
              [Self.initializer, Self.handlerSetter]
                  .allSatisfy({ managerClass.instancesRespond(to: NSSelectorFromString($0)) }),
                  let allocated = (managerClass as AnyObject)
                      .perform(NSSelectorFromString("alloc"))?
                      .takeUnretainedValue()
        else { return false }
        let initSelector = NSSelectorFromString(Self.initializer)
        let initialize = unsafeBitCast(managerClass.instanceMethod(for: initSelector), to: Initialize.self)
        guard let manager = initialize(allocated, initSelector, 2)?.takeRetainedValue() else { return false }
        let setterSelector = NSSelectorFromString(Self.handlerSetter)
        let setHandler = unsafeBitCast(manager.method(for: setterSelector), to: SetHandler.self)
        setHandler(manager, setterSelector) { gesture, _ in
            guard gesture == 0 else { return }
            DispatchQueue.main.async { handler() }
        }
        systemManager = manager
        return true
    }

    /// The public fallback: a phone facing the user (screen tilted up) that turns upright with its screen sideways
    /// within `raiseWindow`. The activator's one-second proximity check decides whether it reached the ear.
    private func startMotionUpdates(handler: @escaping @MainActor () -> Void) -> Bool {
        let manager = CMMotionManager()
        guard manager.isDeviceMotionAvailable else { return false }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.attitudeChanged(motion.gravity, at: motion.timestamp, handler: handler) }
        }
        motionManager = manager
        return true
    }

    private func attitudeChanged(_ gravity: CMAcceleration, at timestamp: TimeInterval, handler: () -> Void) {
        let isFacing = gravity.z < -0.45
        let isUpright = abs(gravity.z) < 0.35 && (gravity.y < -0.3 || abs(gravity.x) > 0.6)
        if isFacing {
            facedAt = timestamp
            isAtEar = false
        } else if isUpright {
            guard !isAtEar else { return }
            isAtEar = true
            if let facedAt, timestamp - facedAt < Self.raiseWindow {
                self.facedAt = nil
                handler()
            }
        } else {
            isAtEar = false
        }
    }
}
