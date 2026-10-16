// WebAppSensors.swift

import CoreLocation
import CoreMotion
import UIKit

// MARK: - WebAppSensors

/// WebAppController's motion sensors on one CMMotionManager: the accelerometer in m/s² (`accelerometer_*`), the
/// gyroscope's
/// rotation rate (`gyroscope_*`) and the attitude as alpha, beta and gamma (`device_orientation_*`), each updated every
/// `refresh_rate` ms (1 s by default). A sensor the device lacks fails with UNSUPPORTED; starting a running sensor or
/// stopping a stopped one does nothing.
@MainActor final class WebAppSensors {
    private static let gravity = 9.81

    private let send: (String, [String: Any]?) -> Void
    private let motionManager = CMMotionManager()
    private var isAccelerometerActive = false
    private var isGyroscopeActive = false
    private var isDeviceOrientationActive = false

    init(bridge: WebAppBridge) {
        self.send = bridge.send
    }

    // MARK: Private

    private static func interval(_ refreshRate: Double?) -> TimeInterval {
        refreshRate.map { $0 * 0.001 } ?? 1
    }

    /// Telegram starts a sensor only for an event with parameters.
    func startAccelerometer(_ json: [String: Any]?) {
        guard let json else { return }
        setAccelerometerActive(true, refreshRate: json["refresh_rate"] as? Double)
    }

    func stopAccelerometer() {
        setAccelerometerActive(false, refreshRate: nil)
    }

    func startGyroscope(_ json: [String: Any]?) {
        guard let json else { return }
        setGyroscopeActive(true, refreshRate: json["refresh_rate"] as? Double)
    }

    func stopGyroscope() {
        setGyroscopeActive(false, refreshRate: nil)
    }

    func startDeviceOrientation(_ json: [String: Any]?) {
        guard let json else { return }
        setDeviceOrientationActive(
            true,
            refreshRate: json["refresh_rate"] as? Double,
            absolute: json["need_absolute"] as? Bool == true,
        )
    }

    func stopDeviceOrientation() {
        setDeviceOrientationActive(false, refreshRate: nil, absolute: false)
    }

    /// The Web App closed: the sensors stop without telling the page.
    func stopAll() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopDeviceMotionUpdates()
        isAccelerometerActive = false
        isGyroscopeActive = false
        isDeviceOrientationActive = false
    }

    private func setAccelerometerActive(_ active: Bool, refreshRate: Double?) {
        guard motionManager.isAccelerometerAvailable else {
            send("accelerometer_failed", ["error": "UNSUPPORTED"])
            return
        }
        guard active != isAccelerometerActive else { return }
        isAccelerometerActive = active
        guard active else {
            if motionManager.isAccelerometerActive { motionManager.stopAccelerometerUpdates() }
            send("accelerometer_stopped", nil)
            return
        }
        send("accelerometer_started", nil)
        motionManager.accelerometerUpdateInterval = Self.interval(refreshRate)
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let acceleration = data?.acceleration else { return }
            MainActor.assumeIsolated {
                self?.send("accelerometer_changed", [
                    "x": acceleration.x * Self.gravity,
                    "y": acceleration.y * Self.gravity,
                    "z": acceleration.z * Self.gravity,
                ])
            }
        }
    }

    private func setGyroscopeActive(_ active: Bool, refreshRate: Double?) {
        guard motionManager.isGyroAvailable else {
            send("gyroscope_failed", ["error": "UNSUPPORTED"])
            return
        }
        guard active != isGyroscopeActive else { return }
        isGyroscopeActive = active
        guard active else {
            if motionManager.isGyroActive { motionManager.stopGyroUpdates() }
            send("gyroscope_stopped", nil)
            return
        }
        send("gyroscope_started", nil)
        motionManager.gyroUpdateInterval = Self.interval(refreshRate)
        motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let rate = data?.rotationRate else { return }
            MainActor.assumeIsolated {
                self?.send("gyroscope_changed", ["x": rate.x, "y": rate.y, "z": rate.z])
            }
        }
    }

    /// An absolute orientation uses true north when location access allows it, magnetic north otherwise; a relative
    /// one uses the corrected arbitrary frame when the device has it.
    private func setDeviceOrientationActive(_ active: Bool, refreshRate: Double?, absolute: Bool) {
        guard motionManager.isDeviceMotionAvailable else {
            send("device_orientation_failed", ["error": "UNSUPPORTED"])
            return
        }
        guard active != isDeviceOrientationActive else { return }
        isDeviceOrientationActive = active
        guard active else {
            if motionManager.isDeviceMotionActive { motionManager.stopDeviceMotionUpdates() }
            send("device_orientation_stopped", nil)
            return
        }
        send("device_orientation_started", nil)
        motionManager.deviceMotionUpdateInterval = Self.interval(refreshRate)
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let status = CLLocationManager().authorizationStatus
        let isLocationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        let referenceFrame: CMAttitudeReferenceFrame
        let isAbsolute: Bool
        if absolute, isLocationAuthorized, frames.contains(.xTrueNorthZVertical) {
            referenceFrame = .xTrueNorthZVertical
            isAbsolute = true
        } else if absolute, frames.contains(.xMagneticNorthZVertical) {
            referenceFrame = .xMagneticNorthZVertical
            isAbsolute = true
        } else {
            referenceFrame = frames.contains(.xArbitraryCorrectedZVertical)
                ? .xArbitraryCorrectedZVertical
                : .xArbitraryZVertical
            isAbsolute = false
        }
        motionManager.startDeviceMotionUpdates(using: referenceFrame, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            var alpha: Double
            if isAbsolute {
                alpha = motion.heading * .pi / 180
                if alpha > .pi {
                    alpha -= 2 * .pi
                } else if alpha < -.pi {
                    alpha += 2 * .pi
                }
            } else {
                alpha = motion.attitude.yaw
            }
            let beta = motion.attitude.pitch
            let gamma = motion.attitude.roll
            MainActor.assumeIsolated {
                self?.send("device_orientation_changed", [
                    "absolute": isAbsolute,
                    "alpha": alpha,
                    "beta": beta,
                    "gamma": gamma,
                ])
            }
        }
    }
}
