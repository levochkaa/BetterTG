// LocationViewerProbe.swift

#if DEBUG
    import CoreLocation
    import UIKit

    /// Launch with `-ui-probe-location-viewer`. Once an account is active it opens Telegram's location viewer over
    /// the current screen on a fixed venue in San Francisco, so the viewer is checked without a location message.
    /// Pass `-ui-probe-location-viewer-plain` for a bare location, whose address is reverse geocoded. Nothing is
    /// sent: the viewer gets no live location sender.
    @MainActor enum LocationViewerProbe {
        private static let coordinate = CLLocationCoordinate2D(latitude: 37.78508, longitude: -122.40217)

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-ui-probe-location-viewer") else { return }
            let isPlain = arguments.contains("-ui-probe-location-viewer-plain")
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard TDLib.shared.activeAccountID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                let venue = LocationPickerVenue(
                    probeTitle: "Yerba Buena Gardens",
                    address: "750 Howard St",
                    coordinate: coordinate,
                    type: "parks_outdoors",
                )
                let subject = LocationViewSubject(probeCoordinate: coordinate, venue: isPlain ? nil : venue)
                let viewer = LocationViewController(
                    subject: subject,
                    client: TDLib.shared.activeClient,
                    source: TDLib.shared.activeUpdateSource,
                )
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                presenter?.present(viewer.makeNavigationController(), animated: true)
            }
        }
    }

    private extension LocationViewSubject {
        init(probeCoordinate: CLLocationCoordinate2D, venue: LocationPickerVenue?) {
            self.coordinate = probeCoordinate
            self.venue = venue
            self.liveMessage = nil
        }
    }

    private extension LocationPickerVenue {
        init(probeTitle: String, address: String, coordinate: CLLocationCoordinate2D, type: String) {
            self.title = probeTitle
            self.address = address
            self.coordinate = coordinate
            self.provider = "foursquare"
            self.id = ""
            self.type = type
        }
    }
#endif
