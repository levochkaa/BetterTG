// OneShotLocation.swift

import CoreLocation

// MARK: - OneShotLocation

/// Telegram's currentLocationManagerCoordinate: one location fix once the user chose to share it, asking for When In
/// Use access first when it hasn't been decided. nil when access is denied or no fix arrives in time.
@MainActor final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    /// Requests in flight stay alive until they finish.
    private static var active = Set<OneShotLocation>()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var requestedLocation = false

    static func current(timeout: Duration = .seconds(10)) async -> (latitude: Double, longitude: Double)? {
        let request = OneShotLocation()
        active.insert(request)
        defer { active.remove(request) }
        let coordinate = await withCheckedContinuation { continuation in
            request.start(continuation, timeout: timeout)
        }
        return coordinate.map { ($0.latitude, $0.longitude) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor [weak self] in self?.finish(coordinate) }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        Task { @MainActor [weak self] in self?.finish(nil) }
    }

    private func start(_ continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>, timeout: Duration) {
        self.continuation = continuation
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
        authorizationChanged()
    }

    private func authorizationChanged() {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedLocation else { return }
            requestedLocation = true
            manager.requestLocation()
        default:
            finish(nil)
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        manager.delegate = nil
        continuation.resume(returning: coordinate)
    }
}
